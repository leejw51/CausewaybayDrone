use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
pub type P = [f64; 3];
fn default_autonomy() -> bool {
    true
}
#[derive(Clone, Serialize, Deserialize, Debug)]
pub struct Config {
    pub drones: usize,
    pub cafes: usize,
    pub humans: usize,
    pub mode: String,
    #[serde(default = "default_autonomy")]
    pub auto_orders: bool,
    #[serde(default = "default_language")]
    pub language: String,
    #[serde(default = "default_autonomy")]
    pub sfx_enabled: bool,
    #[serde(default = "default_sfx_volume")]
    pub sfx_volume: f64,
}
fn default_sfx_volume() -> f64 {
    0.65
}
fn default_language() -> String {
    "en".into()
}
impl Default for Config {
    fn default() -> Self {
        Self {
            drones: 8,
            cafes: 3,
            humans: 20,
            mode: "Massive".into(),
            auto_orders: true,
            language: default_language(),
            sfx_enabled: true,
            sfx_volume: default_sfx_volume(),
        }
    }
}
impl Config {
    pub fn valid(&self) -> bool {
        ["en", "ko", "ja", "yue_HK", "zh_CN", "cs"].contains(&self.language.as_str())
            && self.sfx_volume.is_finite()
            && (0.0..=1.0).contains(&self.sfx_volume)
            && (1..=32).contains(&self.drones)
            && (1..=12).contains(&self.cafes)
            && (1..=200).contains(&self.humans)
            && ["Solo", "Massive"].contains(&self.mode.as_str())
            && (self.mode != "Solo" || (self.drones == 1 && self.cafes == 1 && self.humans == 1))
    }
}
#[derive(Clone, Serialize, Deserialize, Default)]
pub struct Layout {
    pub homes: Vec<P>,
    pub pickups: Vec<P>,
    pub customers: Vec<P>,
    #[serde(default)]
    pub windows: Vec<P>,
    #[serde(default)]
    pub interiors: Vec<P>,
}
#[derive(Clone, Serialize, Deserialize)]
pub struct Order {
    pub id: usize,
    pub human: usize,
    pub cafe: usize,
    pub drone: i64,
    pub item: String,
    pub quantity: usize,
    pub state: String,
    pub created: f64,
    pub delivered: Option<f64>,
    #[serde(default)]
    pub apartment: bool,
}
#[derive(Clone, Serialize, Deserialize)]
pub struct Drone {
    pub position: P,
    pub velocity: P,
    #[serde(default)]
    pub body: crate::physics::FlightBody,
    #[serde(default)]
    pub maintenance: crate::maintenance::Maintenance,
    pub rotation: f64,
    pub job: i64,
    pub state: String,
    pub path: Vec<P>,
    #[serde(default)]
    pub precise_points: Vec<usize>,
    pub step: usize,
    pub timer: f64,
    pub battery: f64,
    pub payload: f64,
}
#[derive(Clone, Serialize, Deserialize)]
pub struct Cafe {
    pub job: i64,
    pub timer: f64,
}
#[derive(Clone, Serialize, Deserialize)]
pub struct State {
    pub schema: u32,
    pub config: Config,
    pub layout: Layout,
    pub run_id: String,
    pub time: f64,
    pub serial: u64,
    pub running: bool,
    pub orders: Vec<Order>,
    pub vehicles: Vec<Drone>,
    pub cafes: Vec<Cafe>,
    #[serde(default)]
    pub arcade: crate::arcade::Arcade,
}
impl Default for State {
    fn default() -> Self {
        Self {
            schema: 2,
            config: Config::default(),
            layout: Layout::default(),
            run_id: String::new(),
            time: 0.,
            serial: 0,
            running: false,
            orders: vec![],
            vehicles: vec![],
            cafes: vec![],
            arcade: crate::arcade::Arcade::default(),
        }
    }
}
pub struct Engine {
    pub state: State,
    pub events: Vec<Value>,
    pub terrain: Value,
    pub buildings: Vec<[f64; 5]>,
    pub fence: Option<crate::geofence::Fence>,
}
pub fn distance(a: P, b: P) -> f64 {
    (0..3).map(|i| (a[i] - b[i]).powi(2)).sum::<f64>().sqrt()
}
impl Engine {
    pub fn new(map: Value) -> Self {
        let buildings = map["buildings"]
            .as_array()
            .unwrap()
            .iter()
            .map(|b| {
                let mut v = [
                    f64::MAX,
                    f64::MIN,
                    f64::MAX,
                    f64::MIN,
                    b["base"].as_f64().unwrap() + b["height"].as_f64().unwrap(),
                ];
                for p in b["rings"][0].as_array().unwrap() {
                    let x = p[0].as_f64().unwrap();
                    let z = p[1].as_f64().unwrap();
                    v[0] = v[0].min(x);
                    v[1] = v[1].max(x);
                    v[2] = v[2].min(z);
                    v[3] = v[3].max(z);
                }
                v
            })
            .collect();
        Self {
            state: State::default(),
            events: vec![],
            terrain: map["terrain"].clone(),
            buildings,
            fence: serde_json::from_value(map["scope"].clone()).ok(),
        }
    }
    pub fn within_scope(&self) -> bool {
        self.fence.as_ref().is_none_or(|f| {
            self.state
                .layout
                .homes
                .iter()
                .chain(&self.state.layout.pickups)
                .chain(&self.state.layout.customers)
                .chain(&self.state.layout.windows)
                .chain(&self.state.layout.interiors)
                .all(|p| f.contains(*p))
                && self.state.vehicles.iter().all(|v| {
                    f.contains(v.position) && v.path.windows(2).all(|p| f.segment(p[0], p[1]))
                })
        })
    }
    pub fn event(&mut self, kind: &str, order: usize) {
        self.state.serial += 1;
        self.events.push(json!({"id":format!("{}-{}",self.state.run_id,self.state.serial),"time":self.state.time,"kind":kind,"order":order}));
    }
    pub fn configure(&mut self, c: Config, l: Layout) -> Result<(), String> {
        if !c.valid()
            || l.homes.len() != c.drones
            || l.pickups.len() != c.cafes
            || l.customers.len() != c.humans
        {
            return Err("Invalid fleet configuration or layout".into());
        }
        if l.homes
            .iter()
            .chain(l.pickups.iter())
            .chain(l.customers.iter())
            .chain(l.windows.iter())
            .chain(l.interiors.iter())
            .any(|p| {
                p.iter().any(|x| !x.is_finite())
                    || self.fence.as_ref().is_some_and(|f| !f.contains(*p))
                    || p[0].abs() > 4000.
                    || p[2].abs() > 4000.
                    || p[1] < -100.
                    || p[1] > 625.
            })
        {
            return Err("Layout outside simulation bounds".into());
        }
        self.state = State {
            run_id: format!(
                "{}",
                std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap()
                    .as_nanos()
            ),
            config: c.clone(),
            layout: l.clone(),
            vehicles: l
                .homes
                .iter()
                .map(|p| Drone {
                    position: *p,
                    velocity: [0.; 3],
                    body: crate::physics::FlightBody::default(),
                    maintenance: crate::maintenance::Maintenance::default(),
                    rotation: 0.,
                    job: -1,
                    state: "IDLE".into(),
                    path: vec![],
                    precise_points: vec![],
                    step: 0,
                    timer: 0.,
                    battery: 100.,
                    payload: 0.,
                })
                .collect(),
            cafes: (0..c.cafes).map(|_| Cafe { job: -1, timer: 0. }).collect(),
            ..State::default()
        };
        self.events.clear();
        self.event("CONFIGURED", 0);
        Ok(())
    }
    pub fn order(&mut self, h: usize, c: usize, item: &str, q: usize) -> Result<usize, String> {
        if h >= self.state.config.humans
            || c >= self.state.config.cafes
            || self.state.layout.homes.is_empty()
            || !(1..=3).contains(&q)
            || !["Sandwich", "Coffee", "Sandwich + Coffee"].contains(&item)
        {
            return Err("Invalid order".into());
        }
        if self
            .state
            .orders
            .iter()
            .filter(|o| !matches!(o.state.as_str(), "DELIVERED" | "FAILED"))
            .count()
            >= 500
        {
            return Err("Order queue is full".into());
        }
        let id = self.state.orders.len() + 1;
        self.state.orders.push(Order {
            id,
            human: h,
            cafe: c,
            drone: -1,
            item: item.into(),
            quantity: q,
            state: "ORDERED".into(),
            created: self.state.time,
            delivered: None,
            apartment: false,
        });
        self.event("ORDER_PLACED", id);
        Ok(id)
    }
    pub fn top(&self, p: P) -> f64 {
        let t = &self.terrain;
        let nx = t["nx"].as_u64().unwrap() as usize;
        let nz = t["nz"].as_u64().unwrap() as usize;
        let step = t["step"].as_f64().unwrap();
        let fx = ((p[0] - t["x"].as_f64().unwrap()) / step).clamp(0., (nx - 1) as f64);
        let fz = ((p[2] - t["z"].as_f64().unwrap()) / step).clamp(0., (nz - 1) as f64);
        let x = (fx as usize).min(nx - 2);
        let z = (fz as usize).min(nz - 2);
        let (u, v) = (fx - x as f64, fz - z as f64);
        let h = |dx, dz| t["heights"][(z + dz) * nx + x + dx].as_f64().unwrap();
        let (a, b, c, d) = (h(0, 0), h(1, 0), h(0, 1), h(1, 1));
        // Match the rendered/collision triangles, including their diagonal.
        let mut y = if u + v <= 1. {
            a + (b - a) * u + (c - a) * v
        } else {
            d + (c - d) * (1. - u) + (b - d) * (1. - v)
        };
        for b in &self.buildings {
            if p[0] > b[0] - 3. && p[0] < b[1] + 3. && p[2] > b[2] - 3. && p[2] < b[3] + 3. {
                y = y.max(b[4]);
            }
        }
        y
    }
    pub(crate) fn route(&mut self, i: usize, dest: P) {
        let start = self.state.vehicles[i].position;
        let approach = if self.state.vehicles[i].job >= 0 {
            let order = &self.state.orders[self.state.vehicles[i].job as usize];
            if order.apartment && self.state.vehicles[i].state == "DELIVERING" {
                self.state
                    .layout
                    .windows
                    .get(order.human)
                    .copied()
                    .unwrap_or(dest)
            } else {
                dest
            }
        } else {
            dest
        };
        let count = (distance(start, approach) / 8.).ceil().max(2.) as usize;
        let mut height = start[1].max(dest[1]) + 18. + i as f64 * 4.;
        for n in 0..=count {
            let p = std::array::from_fn(|a| {
                start[a] + (approach[a] - start[a]) * n as f64 / count as f64
            });
            height = height.max(self.top(p) + 18. + i as f64 * 4.);
        }
        for building in &self.buildings {
            if crate::ai::crosses_footprint(start, approach, building) {
                height = height.max(building[4] + 18. + i as f64 * 4.);
            }
        }
        let v = &mut self.state.vehicles[i];
        v.path = vec![
            [start[0], height, start[2]],
            [dest[0], height, dest[2]],
            dest,
        ];
        v.step = 0;
        if v.job >= 0 {
            let order = &self.state.orders[v.job as usize];
            if order.apartment && self.state.layout.windows.len() > order.human {
                let window = self.state.layout.windows[order.human];
                let interior = self.state.layout.interiors[order.human];
                if v.state == "DELIVERING" {
                    v.path = vec![
                        [start[0], height, start[2]],
                        [window[0], height, window[2]],
                        window,
                    ];
                }
                if matches!(v.state.as_str(), "RETURNING" | "RECOVERY RETURN")
                    && (distance(start, interior) < 4. || distance(start, window) < 4.)
                {
                    v.path = vec![
                        window,
                        [window[0], height, window[2]],
                        [dest[0], height, dest[2]],
                        dest,
                    ];
                }
            }
        }
        let floor = start[1].max(dest[1]) + 8.;
        let (curved, precise) = crate::guidance::rounded(start, &v.path, floor);
        let original = v.path.clone();
        // Check the added bend samples against map roof/terrain clearance.
        // If a bend would cut across an obstacle, retain precise waypoints.
        let clear = curved
            .iter()
            .all(|p| original.contains(p) || p[1] >= self.top(*p) + 6.);
        let v = &mut self.state.vehicles[i];
        if clear {
            v.path = curved;
            v.precise_points = precise;
        } else {
            v.precise_points = (0..v.path.len()).collect();
        }
        if let Some(fence) = &self.fence {
            let original = self.state.vehicles[i].path.clone();
            let mut safe = Vec::new();
            let mut from = start;
            let mut detoured = false;
            for goal in original {
                detoured |= !fence.segment(from, goal);
                let Some(mut leg) = fence.route(from, goal) else {
                    self.state.running = false;
                    self.vehicle_event("GEOFENCE_ROUTE_BLOCKED", i);
                    return;
                };
                let len = leg.len();
                for point in leg.iter_mut().take(len.saturating_sub(1)) {
                    point[1] = point[1].max(self.top(*point) + 22.);
                }
                safe.extend(leg);
                from = goal;
            }
            self.state.vehicles[i].path = safe;
            if detoured {
                self.state.vehicles[i].precise_points =
                    (0..self.state.vehicles[i].path.len()).collect();
            }
        }
    }
    pub(crate) fn fly(&mut self, i: usize, dt: f64) -> bool {
        let v = &mut self.state.vehicles[i];
        if v.path.is_empty() {
            return true;
        }
        // Fly through curve samples; only access points and the final dock require a stop.
        while v.step + 1 < v.path.len()
            && !v.precise_points.is_empty()
            && !v.precise_points.contains(&v.step)
            && distance(v.position, v.path[v.step]) < 2.0
        {
            v.step += 1;
        }
        let target = v.path[v.step];
        let pos = v.position;
        let dist = distance(pos, target);
        let precise = v.precise_points.is_empty() || v.precise_points.contains(&v.step);
        let limit: f64 = if precise {
            4.
        } else if dist > 25. {
            12.
        } else {
            4.5
        };
        let speed = if precise {
            limit.min((2. * 2.5 * dist).sqrt()).min(dist * 1.5)
        } else {
            // Brake ahead of bends, maintaining forward motion around the arc.
            limit.min((2. * 2.0 * dist + 4.5_f64.powi(2)).sqrt())
        };
        let desired: P = std::array::from_fn(|a| {
            if dist > 0. {
                (target[a] - pos[a]) / dist * speed
            } else {
                0.
            }
        });
        let traffic: Vec<_> = self
            .state
            .vehicles
            .iter()
            .enumerate()
            .filter(|(j, o)| {
                *j != i
                    && !matches!(
                        o.state.as_str(),
                        "IDLE" | "CHARGING" | "DIAGNOSING" | "REPAIRING"
                    )
            })
            .map(|(j, o)| (j, o.position, o.velocity))
            .collect();
        let (desired, avoiding) = crate::avoidance::steer(i, pos, desired, &traffic);
        if avoiding != self.state.vehicles[i].maintenance.avoiding {
            self.state.vehicles[i].maintenance.avoiding = avoiding;
            self.vehicle_event(
                if avoiding {
                    "AVOIDANCE_STARTED"
                } else {
                    "AVOIDANCE_CLEARED"
                },
                i,
            );
        }
        let v = &mut self.state.vehicles[i];
        crate::physics::step(
            &mut v.body,
            &mut v.position,
            &mut v.velocity,
            v.payload,
            desired,
            v.rotation,
            dt,
        );
        if self
            .fence
            .as_ref()
            .is_some_and(|f| !f.segment(pos, v.position))
        {
            v.position = pos;
            v.velocity = [0.; 3];
            v.body = crate::physics::FlightBody::default();
            v.body.hold = Some(pos);
        }
        if v.velocity[0].abs() + v.velocity[2].abs() > 0.1 {
            let heading = v.velocity[0].atan2(v.velocity[2]);
            let difference = (heading - v.rotation + std::f64::consts::PI)
                .rem_euclid(std::f64::consts::TAU)
                - std::f64::consts::PI;
            v.rotation += difference.clamp(-1.5 * dt, 1.5 * dt);
        }
        if precise && distance(v.position, target) < 0.10 && distance(v.velocity, [0.; 3]) < 0.15 {
            v.body.hold = Some(target);
            v.step += 1;
            if v.step >= v.path.len() {
                v.path.clear();
                return true;
            }
        }
        false
    }
    fn autonomous_orders(&mut self) {
        if !self.state.config.auto_orders || self.state.layout.homes.is_empty() {
            return;
        }
        for human in 0..self.state.config.humans {
            let history: Vec<_> = self
                .state
                .orders
                .iter()
                .filter(|o| o.human == human)
                .collect();
            if history
                .iter()
                .any(|o| !matches!(o.state.as_str(), "DELIVERED" | "FAILED"))
            {
                continue;
            }
            let cycle = history.len();
            if let Some(last) = history.last() {
                let ready_at =
                    last.delivered.unwrap_or(last.created) + 90. + (human % 5) as f64 * 10.;
                if self.state.time < ready_at {
                    continue;
                }
            }
            let cafe = (0..self.state.config.cafes)
                .min_by_key(|c| {
                    self.state
                        .orders
                        .iter()
                        .filter(|o| {
                            o.cafe == *c && !matches!(o.state.as_str(), "DELIVERED" | "FAILED")
                        })
                        .count()
                })
                .unwrap();
            let item = ["Sandwich", "Coffee", "Sandwich + Coffee"][(human + cycle) % 3];
            if let Ok(id) = self.order(human, cafe, item, 1 + (cycle % 3)) {
                self.state.orders[id - 1].apartment = human % 3 == 0
                    && human < self.state.layout.windows.len()
                    && human < self.state.layout.interiors.len();
                self.event("AUTONOMOUS_ORDER", id);
            }
        }
    }
    pub fn tick(&mut self, dt: f64) {
        if !self.state.running {
            return;
        }
        let previous_positions: Vec<P> = self.state.vehicles.iter().map(|v| v.position).collect();
        self.state.time += dt;
        self.state.arcade.tick(self.state.time);
        self.autonomous_orders();
        for c in 0..self.state.cafes.len() {
            if self.state.cafes[c].job < 0 {
                if let Some(j) = self
                    .state
                    .orders
                    .iter()
                    .position(|o| o.cafe == c && o.state == "ORDERED")
                {
                    self.state.cafes[c].job = j as i64;
                    self.state.cafes[c].timer = 0.;
                    self.state.orders[j].state = "COOKING".into();
                    self.event("COOKING_STARTED", j + 1);
                }
            }
            let j = self.state.cafes[c].job;
            if j >= 0 {
                let j = j as usize;
                let transition = match self.state.orders[j].state.as_str() {
                    "COOKING" => Some((
                        12. + self.state.orders[j].quantity as f64 * 4.,
                        "PACKING",
                        "PACKING_STARTED",
                    )),
                    "PACKING" => Some((4., "SHIPPING", "SHIPPING_STARTED")),
                    "SHIPPING" => Some((4., "READY", "FOOD_READY")),
                    _ => None,
                };
                if let Some((duration, next, event)) = transition {
                    self.state.cafes[c].timer += dt;
                    if self.state.cafes[c].timer >= duration {
                        self.state.cafes[c].timer = 0.;
                        self.state.orders[j].state = next.into();
                        self.event(event, j + 1);
                    }
                }
            }
        }
        for i in 0..self.state.vehicles.len() {
            if self.service_tick(i, dt) {
                continue;
            }
            if self.state.vehicles[i].state == "IDLE" {
                if self.state.vehicles[i].battery >= crate::ai::DISPATCH_BATTERY {
                    let candidate = self
                        .state
                        .orders
                        .iter()
                        .enumerate()
                        .filter(|(_, o)| {
                            matches!(
                                o.state.as_str(),
                                "COOKING" | "PACKING" | "SHIPPING" | "READY"
                            ) && o.drone < 0
                                && !self.state.orders.iter().any(|other| {
                                    other.human == o.human
                                        && other.drone >= 0
                                        && !matches!(other.state.as_str(), "DELIVERED" | "FAILED")
                                })
                        })
                        .min_by(|(_, a), (_, b)| {
                            distance(
                                self.state.vehicles[i].position,
                                self.state.layout.pickups[a.cafe],
                            )
                            .total_cmp(&distance(
                                self.state.vehicles[i].position,
                                self.state.layout.pickups[b.cafe],
                            ))
                        })
                        .map(|(j, _)| j);
                    if let Some(j) = candidate {
                        self.state.vehicles[i].job = j as i64;
                        self.state.vehicles[i].state = "TO CAFE".into();
                        self.state.orders[j].drone = i as i64;
                        self.route(i, self.state.layout.pickups[self.state.orders[j].cafe]);
                        self.event("DRONE_DISPATCHED", j + 1);
                    }
                }
            }
            let j = self.state.vehicles[i].job;
            if j < 0 {
                continue;
            }
            let j = j as usize;
            let c = self.state.orders[j].cafe;
            let watts = 900.
                + distance(self.state.vehicles[i].velocity, [0.; 3]).powi(2) * 1.8
                + self.state.vehicles[i].payload * 120.;
            self.state.vehicles[i].battery =
                (self.state.vehicles[i].battery - watts * dt / 3600. / 1000. * 100.).max(0.);
            self.state.vehicles[i].maintenance.health =
                (self.state.vehicles[i].maintenance.health - dt * 0.004).max(0.);
            let recovery = crate::ai::recovery_reason(
                self.state.vehicles[i].battery,
                self.state.vehicles[i].maintenance.health,
            );
            if let Some(reason) = recovery {
                if self.state.vehicles[i].state != "RETURNING" {
                    self.state.vehicles[i].maintenance.requested = reason.into();
                    self.begin_recovery(i);
                    continue;
                }
            }
            if matches!(
                self.state.vehicles[i].state.as_str(),
                "WAITING FOR FOOD" | "LOADING" | "UNLOADING"
            ) {
                let v = &mut self.state.vehicles[i];
                let target = v.body.hold.unwrap_or(v.position);
                let desired =
                    std::array::from_fn(|a| ((target[a] - v.position[a]) * 1.5).clamp(-1., 1.));
                crate::physics::step(
                    &mut v.body,
                    &mut v.position,
                    &mut v.velocity,
                    v.payload,
                    desired,
                    v.rotation,
                    dt,
                );
            }
            let v = &self.state.vehicles[i];
            let action = crate::ai::decide(
                &v.state,
                self.state.orders[j].state == "READY",
                crate::ai::settled(v.position, v.velocity, v.body.hold),
            );
            // Interrupted handoffs must settle again for the full transfer duration.
            if action == crate::ai::Action::Wait
                && matches!(v.state.as_str(), "LOADING" | "UNLOADING")
            {
                self.state.vehicles[i].timer = 0.;
            }
            match action {
                crate::ai::Action::FlyToShop => {
                    if self.fly(i, dt) {
                        self.state.vehicles[i].state = "WAITING FOR FOOD".into();
                    }
                }
                crate::ai::Action::BeginPickup => {
                    if self.state.orders[j].state == "READY" {
                        self.state.vehicles[i].state = "LOADING".into();
                        self.state.vehicles[i].timer = 0.;
                        self.state.orders[j].state = "HANDOFF".into();
                        self.event("HANDOFF_STARTED", j + 1);
                    }
                }
                crate::ai::Action::PickUp => {
                    self.state.vehicles[i].timer += dt;
                    if self.state.vehicles[i].timer >= 3. {
                        self.state.vehicles[i].payload = self.state.orders[j].quantity as f64
                            * if self.state.orders[j].item == "Sandwich + Coffee" {
                                0.7
                            } else {
                                0.35
                            };
                        self.state.vehicles[i].state = "DELIVERING".into();
                        self.state.orders[j].state = "OUT FOR DELIVERY".into();
                        self.state.cafes[c].job = -1;
                        self.route(i, self.state.layout.customers[self.state.orders[j].human]);
                        self.event("PICKED_UP", j + 1);
                    }
                }
                crate::ai::Action::FlyToCustomer => {
                    if self.fly(i, dt) {
                        self.state.vehicles[i].state = "UNLOADING".into();
                        self.state.vehicles[i].timer = 0.;
                        self.state.orders[j].state = "DELIVERING".into();
                        self.event("DELIVERY_STARTED", j + 1);
                    }
                }
                crate::ai::Action::DropOff => {
                    self.state.vehicles[i].timer += dt;
                    if self.state.vehicles[i].timer >= 3. {
                        self.state.orders[j].state = "DELIVERED".into();
                        self.state.orders[j].delivered = Some(self.state.time);
                        self.state.vehicles[i].payload = 0.;
                        self.state.vehicles[i].state = "RETURNING".into();
                        self.route(i, self.state.layout.homes[i]);
                        self.state
                            .arcade
                            .delivery(self.state.time, self.state.orders[j].apartment);
                        self.event("DELIVERED", j + 1);
                    }
                }
                crate::ai::Action::ReturnHome => {
                    if self.fly(i, dt) {
                        // Dock capture dissipates residual velocity only after the
                        // physics controller reaches the home tolerance at low speed.
                        self.state.vehicles[i].velocity = [0.; 3];
                        self.state.vehicles[i].body = crate::physics::FlightBody::default();
                        self.state.vehicles[i].state = "IDLE".into();
                        self.state.vehicles[i].job = -1;
                        self.state.vehicles[i].payload = 0.;
                        self.event("DRONE_RETURNED", j + 1);
                    }
                }
                _ => {}
            }
        }
        if let Some(fence) = &self.fence {
            for (v, previous) in self.state.vehicles.iter_mut().zip(previous_positions) {
                if !fence.segment(previous, v.position) {
                    v.position = previous;
                    v.velocity = [0.; 3];
                    v.body = crate::physics::FlightBody::default();
                    v.body.hold = Some(previous);
                }
            }
        }
    }
}
