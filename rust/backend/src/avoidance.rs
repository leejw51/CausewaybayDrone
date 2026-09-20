//! Predictive cooperative avoidance: lower vehicle ID has right of way.
use crate::engine::{distance, P};
pub fn steer(id: usize, position: P, desired: P, others: &[(usize, P, P)]) -> (P, bool) {
    for &(other_id, p, v) in others {
        if other_id >= id {
            continue;
        }
        let relative: P = std::array::from_fn(|a| p[a] - position[a]);
        let closing: P = std::array::from_fn(|a| desired[a] - v[a]);
        let speed2: f64 = closing.iter().map(|x| x * x).sum();
        let time = if speed2 > 0.01 {
            (relative
                .iter()
                .zip(closing)
                .map(|(a, b)| a * b)
                .sum::<f64>()
                / speed2)
                .clamp(0., 4.)
        } else {
            0.
        };
        let nearest: P = std::array::from_fn(|a| relative[a] - closing[a] * time);
        if distance(nearest, [0.; 3]) < 8. && distance(position, p) < 60. {
            let horizontal = desired[0].hypot(desired[2]);
            let right = if horizontal > 0.1 {
                [-desired[2] / horizontal, 0., desired[0] / horizontal]
            } else {
                [1., 0., 0.]
            };
            return (
                [
                    desired[0] * 0.15 + right[0] * 4.,
                    desired[1].max(0.) + 1.5,
                    desired[2] * 0.15 + right[2] * 4.,
                ],
                true,
            );
        }
    }
    (desired, false)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn head_on_aircraft_keep_separation_with_inertia() {
        let mut p0 = [-20., 20., 0.];
        let mut p1 = [20., 20., 0.];
        let mut v0 = [6., 0., 0.];
        let mut v1 = [-6., 0., 0.];
        let mut b0 = crate::physics::FlightBody::default();
        let mut b1 = b0.clone();
        let mut minimum = f64::MAX;
        let mut avoided = false;
        for _ in 0..240 {
            let (desired, active) = steer(1, p1, [-6., 0., 0.], &[(0, p0, v0)]);
            avoided |= active;
            crate::physics::step(&mut b0, &mut p0, &mut v0, 0., [6., 0., 0.], 0., 0.05);
            crate::physics::step(&mut b1, &mut p1, &mut v1, 0., desired, 0., 0.05);
            minimum = minimum.min(distance(p0, p1));
        }
        assert!(avoided);
        assert!(minimum > 6., "minimum separation: {minimum}");
    }
    #[test]
    fn predicts_crossing_and_preserves_right_of_way() {
        let others = [(0, [20., 20., 0.], [-6., 0., 0.])];
        let (v, active) = steer(1, [-20., 20., 0.], [6., 0., 0.], &others);
        assert!(active && v[2] > 0. && v[0] < 6. && v[1] > 0.);
        assert!(
            !steer(
                0,
                [-20., 20., 0.],
                [6., 0., 0.],
                &[(1, [20., 20., 0.], [-6., 0., 0.])]
            )
            .1
        );
        assert!(!steer(1, [-20., 60., 0.], [6., 0., 0.], &others).1);
    }
}
