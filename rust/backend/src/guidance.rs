//! Round open-air route corners with quadratic Bezier fillets. Low-altitude
//! access points remain mandatory, precise stops (windows and docking paths).
use crate::engine::P;
fn distance(a: P, b: P) -> f64 {
    a.iter()
        .zip(b)
        .map(|(x, y)| (x - y).powi(2))
        .sum::<f64>()
        .sqrt()
}
fn mix(a: P, b: P, t: f64) -> P {
    std::array::from_fn(|i| a[i] + (b[i] - a[i]) * t)
}
pub fn rounded(start: P, route: &[P], clearance_floor: f64) -> (Vec<P>, Vec<usize>) {
    let mut points = Vec::new();
    let mut precise = Vec::new();
    for (i, &corner) in route.iter().enumerate() {
        let before = if i == 0 { start } else { route[i - 1] };
        if i + 1 == route.len() || corner[1] < clearance_floor {
            precise.push(points.len());
            points.push(corner);
            continue;
        }
        let after = route[i + 1];
        let incoming = distance(before, corner);
        let outgoing = distance(corner, after);
        let radius = 8_f64.min(incoming * 0.25).min(outgoing * 0.25);
        if radius < 1. {
            precise.push(points.len());
            points.push(corner);
            continue;
        }
        let enter = mix(corner, before, radius / incoming);
        let exit = mix(corner, after, radius / outgoing);
        // Convex Bezier hull stays within the checked eight-metre corner envelope.
        for n in 0..=12 {
            let t = n as f64 / 12.;
            points.push(mix(mix(enter, corner, t), mix(corner, exit, t), t));
        }
    }
    (points, precise)
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn curves_leave_axis_aligned_path_but_preserve_window() {
        let (points, precise) = rounded(
            [0., 0., 0.],
            &[
                [0., 30., 0.],
                [50., 30., 0.],
                [50., 10., 0.],
                [50., 10., -8.],
            ],
            18.,
        );
        assert!(points
            .iter()
            .any(|p| p[0] > 0.1 && p[0] < 7.9 && p[1] < 29.9 && p[1] > 22.));
        assert_eq!(points.last(), Some(&[50., 10., -8.]));
        assert!(precise.iter().any(|&i| points[i] == [50., 10., 0.]));
        assert!(points.windows(2).all(|w| distance(w[0], w[1]) > 0.));
    }
}
