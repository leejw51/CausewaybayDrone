//! Dedicated service dock per drone. Times are simulation seconds.
use serde::{Deserialize, Serialize};
#[derive(Clone, Serialize, Deserialize)]
pub struct Maintenance {
    pub health: f64,
    pub requested: String,
    pub elapsed: f64,
    pub repairs: u64,
    pub charges: u64,
    pub avoiding: bool,
}
impl Default for Maintenance {
    fn default() -> Self {
        Self {
            health: 100.,
            requested: String::new(),
            elapsed: 0.,
            repairs: 0,
            charges: 0,
            avoiding: false,
        }
    }
}
pub fn charging_rate(battery: f64) -> f64 {
    // 2 kW charger, 1 kWh battery, 90% efficiency; constant-current then taper.
    2000. * 0.9 / 1000. / 3600.
        * 100.
        * if battery > 90. {
            ((100. - battery) / 10.).max(0.12)
        } else {
            1.
        }
}

impl crate::engine::Engine {
    pub(crate) fn vehicle_event(&mut self, kind: &str, i: usize) {
        self.event(kind, 0);
        if let Some(event) = self.events.last_mut() {
            event["drone"] = serde_json::json!(i);
        }
    }
    /// Explicit simulator shortcut; normal dock charging remains unchanged.
    pub fn instant_charge(&mut self, i: usize) -> Result<(), String> {
        if i >= self.state.vehicles.len() {
            return Err("Drone missing".into());
        }
        let v = &mut self.state.vehicles[i];
        if v.battery < 100. {
            v.maintenance.charges += 1;
        }
        v.battery = 100.;
        let healthy = v.maintenance.health >= 85. && v.maintenance.requested != "repair";
        if v.maintenance.requested == "charge" {
            v.maintenance.requested.clear();
        }
        if v.state == "CHARGING" {
            v.state = "IDLE".into();
            v.maintenance.elapsed = 0.;
        }
        if v.state == "RECOVERY RETURN" && healthy {
            let job = v.job;
            if job >= 0 && v.payload > 0. && self.state.orders[job as usize].state != "DELIVERED" {
                let human = self.state.orders[job as usize].human;
                self.state.orders[job as usize].state = "OUT FOR DELIVERY".into();
                self.state.vehicles[i].state = "DELIVERING".into();
                self.route(i, self.state.layout.customers[human]);
            }
        }
        self.state.running = true;
        self.vehicle_event("INSTANT_CHARGED", i);
        Ok(())
    }
    pub fn request_service(&mut self, i: usize, reason: &str) -> Result<(), String> {
        if i >= self.state.vehicles.len() || !["charge", "repair"].contains(&reason) {
            return Err("Invalid service request".into());
        }
        if matches!(
            self.state.vehicles[i].state.as_str(),
            "DIAGNOSING" | "REPAIRING" | "CHARGING" | "RECOVERY RETURN"
        ) {
            return Err("Drone is already in service".into());
        }
        self.state.vehicles[i].maintenance.requested = reason.into();
        self.vehicle_event("SERVICE_REQUESTED", i);
        Ok(())
    }
    pub fn inject_fault(&mut self, i: usize) -> Result<(), String> {
        if i >= self.state.vehicles.len() {
            return Err("Drone missing".into());
        }
        if matches!(
            self.state.vehicles[i].state.as_str(),
            "DIAGNOSING" | "REPAIRING" | "CHARGING" | "RECOVERY RETURN"
        ) {
            return Err("Drone is already in service".into());
        }
        self.state.vehicles[i].maintenance.health = 55.;
        self.state.vehicles[i].maintenance.requested = "repair".into();
        self.vehicle_event("FAULT_DETECTED", i);
        Ok(())
    }
    pub(crate) fn begin_recovery(&mut self, i: usize) {
        let job = self.state.vehicles[i].job;
        if job >= 0 {
            let order = &mut self.state.orders[job as usize];
            if order.state != "DELIVERED" {
                order.state = "RETURNING ITEMS".into();
            }
        }
        self.state.vehicles[i].state = "RECOVERY RETURN".into();
        self.route(i, self.state.layout.homes[i]);
        self.vehicle_event("SERVICE_RETURN_STARTED", i);
    }
    fn begin_dock_service(&mut self, i: usize) {
        let v = &mut self.state.vehicles[i];
        v.velocity = [0.; 3];
        v.body = crate::physics::FlightBody::default();
        v.maintenance.avoiding = false;
        v.maintenance.elapsed = 0.;
        if v.maintenance.health < 85. || v.maintenance.requested == "repair" {
            v.state = "DIAGNOSING".into();
            self.vehicle_event("DIAGNOSTICS_STARTED", i);
        } else if v.battery < 99.5 {
            v.state = "CHARGING".into();
            self.vehicle_event("CHARGING_STARTED", i);
        } else {
            v.state = "IDLE".into();
            v.maintenance.requested.clear();
        }
    }
    pub(crate) fn service_tick(&mut self, i: usize, dt: f64) -> bool {
        let state = self.state.vehicles[i].state.clone();
        if state == "RECOVERY RETURN" {
            let watts = 900. + self.state.vehicles[i].payload * 120.;
            self.state.vehicles[i].battery =
                (self.state.vehicles[i].battery - watts * dt / 36000.).max(0.);
            if self.fly(i, dt) {
                let job = self.state.vehicles[i].job;
                if job >= 0 {
                    let j = job as usize;
                    let c = self.state.orders[j].cafe;
                    if self.state.orders[j].state == "RETURNING ITEMS" {
                        // Returned goods are removed from delivery; the shop prepares
                        // a fresh replacement under the same order ID.
                        self.state.orders[j].state = "ORDERED".into();
                        self.state.orders[j].drone = -1;
                        if self.state.cafes[c].job == job {
                            self.state.cafes[c].job = -1;
                        }
                        self.event("ORDER_REQUEUED", j + 1);
                    }
                    self.event("DRONE_RETURNED", j + 1);
                }
                self.state.vehicles[i].job = -1;
                self.state.vehicles[i].payload = 0.;
                self.begin_dock_service(i);
            }
            return true;
        }
        if state == "CHARGING" {
            let v = &mut self.state.vehicles[i];
            v.maintenance.elapsed += dt;
            v.battery = (v.battery + charging_rate(v.battery) * dt).min(100.);
            if v.battery >= 99.5 {
                v.battery = 100.;
                v.maintenance.charges += 1;
                v.maintenance.requested.clear();
                v.state = "IDLE".into();
                self.vehicle_event("CHARGING_COMPLETED", i);
            }
            return true;
        }
        if state == "DIAGNOSING" {
            self.state.vehicles[i].maintenance.elapsed += dt;
            if self.state.vehicles[i].maintenance.elapsed >= 5. {
                self.state.vehicles[i].state = "REPAIRING".into();
                self.state.vehicles[i].maintenance.elapsed = 0.;
                self.vehicle_event("REPAIR_STARTED", i);
            }
            return true;
        }
        if state == "REPAIRING" {
            let v = &mut self.state.vehicles[i];
            v.maintenance.elapsed += dt;
            if v.maintenance.elapsed > 20. {
                v.maintenance.health = (v.maintenance.health + dt * 0.5).min(100.);
            }
            if v.maintenance.health >= 100. && v.maintenance.elapsed >= 20. {
                v.maintenance.repairs += 1;
                v.maintenance.requested = "charge".into();
                self.vehicle_event("REPAIR_COMPLETED", i);
                self.begin_dock_service(i);
            }
            return true;
        }
        let request = !self.state.vehicles[i].maintenance.requested.is_empty();
        if state == "IDLE" {
            if request
                || self.state.vehicles[i].battery < crate::ai::CHARGE_BELOW
                || self.state.vehicles[i].maintenance.health < 85.
            {
                self.begin_dock_service(i);
                return self.state.vehicles[i].state != "IDLE";
            }
        } else if request {
            self.begin_recovery(i);
            return true;
        }
        false
    }
}
