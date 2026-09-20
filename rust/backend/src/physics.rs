//! SI-unit translational multirotor model. Guidance supplies desired velocity;
//! forces, motor response and semi-implicit integration determine movement.
use crate::engine::P;
use serde::{Deserialize, Serialize};
pub const GRAVITY: f64 = 9.81;
pub const EMPTY_MASS: f64 = 5.0;
pub const MAX_THRUST: f64 = 120.0;
#[derive(Clone, Serialize, Deserialize, Default)]
pub struct FlightBody {
    pub thrust: P,
    pub acceleration: P,
    pub pitch: f64,
    pub roll: f64,
    #[serde(default)]
    pub angular_velocity: P,
    #[serde(default)]
    pub motor_thrust: f64,
    pub hold: Option<P>,
    pub initialized: bool,
}
fn norm(p: P) -> f64 {
    p.iter().map(|x| x * x).sum::<f64>().sqrt()
}
pub fn step(
    body: &mut FlightBody,
    position: &mut P,
    velocity: &mut P,
    payload: f64,
    desired: P,
    yaw: f64,
    dt: f64,
) {
    if !dt.is_finite() || dt <= 0. {
        return;
    }
    let mass = EMPTY_MASS + payload.max(0.);
    if !body.initialized {
        body.thrust = [0., mass * GRAVITY, 0.];
        body.motor_thrust = mass * GRAVITY;
        body.initialized = true;
    }
    if body.motor_thrust <= 0. {
        body.motor_thrust = norm(body.thrust);
    }
    // Substeps keep motor lag and drag stable when the caller advances a large tick.
    let count = (dt / 0.01).ceil() as usize;
    let h = dt / count as f64;
    for _ in 0..count {
        let drag: P =
            std::array::from_fn(|a| -0.10 * velocity[a] * velocity[a].abs() - 0.15 * velocity[a]);
        let mut commanded: P = std::array::from_fn(|a| {
            mass * ((desired[a] - velocity[a]) * 2.4).clamp(-3., 3.) - drag[a]
        });
        commanded[1] = (commanded[1] + mass * GRAVITY).max(0.);
        let horizontal = commanded[0].hypot(commanded[2]);
        let tilt_limit = commanded[1] * 35_f64.to_radians().tan();
        if horizontal > tilt_limit && horizontal > 0. {
            commanded[0] *= tilt_limit / horizontal;
            commanded[2] *= tilt_limit / horizontal;
        }
        let force = norm(commanded);
        if force > MAX_THRUST {
            for value in &mut commanded {
                *value *= MAX_THRUST / force;
            }
        }
        let forward = commanded[0] * yaw.sin() + commanded[2] * yaw.cos();
        let right = commanded[0] * yaw.cos() - commanded[2] * yaw.sin();
        let target_pitch = forward.atan2(commanded[1]);
        let target_roll = -right.atan2(forward.hypot(commanded[1]));
        // Body attitude is a dynamic state, not a cosmetic angle derived after movement.
        // PD attitude control acts through bounded torque and load-dependent inertia.
        let inertia = 0.65 + payload.max(0.) * 0.12;
        for (axis, target) in [(0, target_pitch), (2, target_roll)] {
            let angle = if axis == 0 { body.pitch } else { body.roll };
            let torque = (inertia * (64. * (target - angle) - 16. * body.angular_velocity[axis]))
                .clamp(-4., 4.);
            body.angular_velocity[axis] =
                (body.angular_velocity[axis] + torque / inertia * h).clamp(-2.5, 2.5);
            if axis == 0 {
                body.pitch += body.angular_velocity[axis] * h;
            } else {
                body.roll += body.angular_velocity[axis] * h;
            }
        }
        let response = 1. - (-h / 0.12).exp();
        body.motor_thrust += (norm(commanded) - body.motor_thrust) * response;
        // Godot uses Y-up and the same Y-X-Z attitude convention.
        let x = -body.roll.sin();
        let y = body.roll.cos() * body.pitch.cos();
        let z = body.roll.cos() * body.pitch.sin();
        body.thrust = [
            (yaw.cos() * x + yaw.sin() * z) * body.motor_thrust,
            y * body.motor_thrust,
            (-yaw.sin() * x + yaw.cos() * z) * body.motor_thrust,
        ];
        for a in 0..3 {
            body.acceleration[a] =
                (body.thrust[a] + drag[a]) / mass - if a == 1 { GRAVITY } else { 0. };
            velocity[a] += body.acceleration[a] * h;
            position[a] += velocity[a] * h;
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn tilt_precedes_horizontal_force_and_has_angular_inertia() {
        let mut body = FlightBody::default();
        let mut p = [0., 20., 0.];
        let mut v = [0.; 3];
        step(&mut body, &mut p, &mut v, 1., [5., 0., 0.], 0., 0.01);
        assert!(body.roll < 0. && body.angular_velocity[2] < 0.);
        assert!(body.roll.abs() < 0.01);
        assert!(body.thrust[0] > 0.);
        assert!((norm(body.thrust) - body.motor_thrust).abs() < 1e-8);
        assert!(body.thrust[1] < body.motor_thrust);
        let angle = body.roll;
        step(&mut body, &mut p, &mut v, 1., [-5., 0., 0.], 0., 0.01);
        assert!((body.roll - angle).abs() < 0.01); // attitude cannot snap to opposite tilt
    }
    #[test]
    fn hover_balances_gravity_for_both_payloads() {
        for payload in [0., 2.1] {
            let mut body = FlightBody::default();
            let mut p = [0., 10., 0.];
            let mut v = [0.; 3];
            for _ in 0..200 {
                step(&mut body, &mut p, &mut v, payload, [0.; 3], 0., 0.05);
            }
            assert!((p[1] - 10.).abs() < 1e-8);
            assert!((body.thrust[1] - (EMPTY_MASS + payload) * GRAVITY).abs() < 1e-8);
        }
    }
    #[test]
    fn acceleration_inertia_and_thrust_are_bounded() {
        let mut body = FlightBody::default();
        let mut p = [0., 10., 0.];
        let mut v = [0.; 3];
        step(&mut body, &mut p, &mut v, 0., [12., 0., 0.], 0., 0.05);
        assert!(v[0] > 0. && v[0] < 0.15); // motor ramp, no instantaneous velocity assignment
        for _ in 0..100 {
            step(&mut body, &mut p, &mut v, 2.1, [12., 12., 12.], 0., 0.05);
            assert!(norm(body.thrust) <= MAX_THRUST + 1e-8);
        }
        let before = p[0];
        step(&mut body, &mut p, &mut v, 2.1, [0.; 3], 0., 0.05);
        assert!(p[0] > before); // braking retains momentum
    }
    #[test]
    fn integration_is_consistent_across_tick_sizes() {
        let mut a = FlightBody::default();
        let mut b = a.clone();
        let mut pa = [0., 10., 0.];
        let mut pb = pa;
        let mut va = [0.; 3];
        let mut vb = va;
        for _ in 0..100 {
            step(&mut a, &mut pa, &mut va, 1., [5., 0., 0.], 0., 0.05);
        }
        for _ in 0..500 {
            step(&mut b, &mut pb, &mut vb, 1., [5., 0., 0.], 0., 0.01);
        }
        assert!((pa[0] - pb[0]).abs() < 1e-8);
    }
}
