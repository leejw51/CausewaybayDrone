//! Small deterministic drone brain. No model service or network inference required.
//! The engine applies these decisions through its physics and order transactions.
use crate::engine::{distance, P};

pub const RETURN_BATTERY: f64 = 20.;
pub const DISPATCH_BATTERY: f64 = 35.;
pub const CHARGE_BELOW: f64 = 90.;

#[derive(Debug, PartialEq)]
pub enum Action {
    Wait,
    FlyToShop,
    BeginPickup,
    PickUp,
    FlyToCustomer,
    DropOff,
    ReturnHome,
}

/// Transfer goods only while settled at the planned handoff location.
pub fn settled(position: P, velocity: P, handoff: Option<P>) -> bool {
    handoff.is_some_and(|p| distance(position, p) <= 0.35) && distance(velocity, [0.; 3]) <= 0.3
}

pub fn decide(state: &str, food_ready: bool, at_handoff: bool) -> Action {
    match state {
        "TO CAFE" => Action::FlyToShop,
        "WAITING FOR FOOD" if food_ready && at_handoff => Action::BeginPickup,
        "LOADING" if at_handoff => Action::PickUp,
        "DELIVERING" => Action::FlyToCustomer,
        "UNLOADING" if at_handoff => Action::DropOff,
        "RETURNING" => Action::ReturnHome,
        _ => Action::Wait,
    }
}

/// Safety interrupts delivery; cargo stays aboard until recovered at the dock.
pub fn recovery_reason(battery: f64, health: f64) -> Option<&'static str> {
    if health < 60. {
        Some("repair")
    } else if battery < RETURN_BATTERY {
        Some("charge")
    } else {
        None
    }
}

/// Continuous segment versus expanded building footprint. Unlike point sampling,
/// this also detects thin obstacles between samples. Height is checked by routing.
pub fn crosses_footprint(start: P, end: P, bounds: &[f64; 5]) -> bool {
    let mut enter: f64 = 0.;
    let mut leave: f64 = 1.;
    for (axis, lo, hi) in [
        (0, bounds[0] - 3., bounds[1] + 3.),
        (2, bounds[2] - 3., bounds[3] + 3.),
    ] {
        let d = end[axis] - start[axis];
        if d.abs() < 1e-9 {
            if start[axis] < lo || start[axis] > hi {
                return false;
            }
        } else {
            let a = (lo - start[axis]) / d;
            let b = (hi - start[axis]) / d;
            enter = enter.max(a.min(b));
            leave = leave.min(a.max(b));
            if enter > leave {
                return false;
            }
        }
    }
    true
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn delivery_brain_requires_food_and_stable_handoff() {
        assert_eq!(decide("WAITING FOR FOOD", false, true), Action::Wait);
        assert_eq!(decide("WAITING FOR FOOD", true, true), Action::BeginPickup);
        assert_eq!(decide("LOADING", true, false), Action::Wait);
        assert_eq!(decide("LOADING", true, true), Action::PickUp);
        assert_eq!(decide("UNLOADING", false, false), Action::Wait);
        assert_eq!(decide("UNLOADING", false, true), Action::DropOff);
        assert!(!settled([0.; 3], [1., 0., 0.], Some([0.; 3])));
        assert!(!settled([2., 0., 0.], [0.; 3], Some([0.; 3])));
        assert!(!settled([0.; 3], [0.; 3], None));
        assert!(settled([0.; 3], [0.; 3], Some([0.; 3])));
        assert_eq!(recovery_reason(19., 100.), Some("charge"));
        assert_eq!(recovery_reason(19., 50.), Some("repair"));
        assert_eq!(recovery_reason(50., 100.), None);
    }
    #[test]
    fn thin_buildings_and_parallel_routes() {
        let b = [4., 4.1, -1., 1., 40.];
        assert!(crosses_footprint([0., 20., 0.], [10., 20., 0.], &b));
        assert!(crosses_footprint([10., 20., 0.], [0., 20., 0.], &b));
        assert!(!crosses_footprint([0., 20., 8.], [10., 20., 8.], &b));
        assert!(!crosses_footprint([0., 20., 0.], [0., 40., 0.], &b));
    }
}
