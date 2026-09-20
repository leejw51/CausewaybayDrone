use crate::engine::P;
use serde::Deserialize;
use std::cmp::Reverse;
use std::collections::BinaryHeap;
#[derive(Clone, Deserialize)]
pub struct Navigation {
    pub points: Vec<[f64; 2]>,
    pub edges: Vec<Vec<usize>>,
}
#[derive(Clone, Deserialize)]
pub struct Fence {
    pub flight_polygons: Vec<Vec<Vec<[f64; 2]>>>,
    pub navigation: Navigation,
}
fn cross(a: [f64; 2], b: [f64; 2], c: [f64; 2]) -> f64 {
    (b[0] - a[0]) * (c[1] - a[1]) - (b[1] - a[1]) * (c[0] - a[0])
}
fn on(a: [f64; 2], b: [f64; 2], p: [f64; 2]) -> bool {
    cross(a, b, p).abs() < 1e-7
        && (0..2).all(|i| p[i] >= a[i].min(b[i]) - 1e-7 && p[i] <= a[i].max(b[i]) + 1e-7)
}
fn intersects(a: [f64; 2], b: [f64; 2], c: [f64; 2], d: [f64; 2]) -> bool {
    (cross(a, b, c) * cross(a, b, d) < 0. && cross(c, d, a) * cross(c, d, b) < 0.)
        || on(a, b, c)
        || on(a, b, d)
        || on(c, d, a)
        || on(c, d, b)
}
fn inside(p: [f64; 2], r: &[[f64; 2]]) -> bool {
    let mut yes = false;
    for i in 0..r.len() {
        let a = r[i];
        let b = r[(i + 1) % r.len()];
        if (a[1] > p[1]) != (b[1] > p[1])
            && p[0] < (b[0] - a[0]) * (p[1] - a[1]) / (b[1] - a[1]) + a[0]
        {
            yes = !yes;
        }
    }
    yes
}
impl Fence {
    pub fn contains(&self, p: P) -> bool {
        p.iter().all(|v| v.is_finite())
            && self.flight_polygons.iter().any(|poly| {
                !poly.is_empty()
                    && inside([p[0], p[2]], &poly[0])
                    && !poly.iter().skip(1).any(|r| inside([p[0], p[2]], r))
            })
    }
    pub fn segment(&self, a: P, b: P) -> bool {
        if !self.contains(a) || !self.contains(b) {
            return false;
        }
        if (a[0] - b[0]).abs() + (a[2] - b[2]).abs() < 1e-8 {
            return true;
        }
        !self.flight_polygons.iter().flatten().any(|r| {
            (0..r.len()).any(|i| intersects([a[0], a[2]], [b[0], b[2]], r[i], r[(i + 1) % r.len()]))
        })
    }
    pub fn route(&self, a: P, b: P) -> Option<Vec<P>> {
        if self.segment(a, b) {
            return Some(vec![b]);
        }
        if !self.contains(a) || !self.contains(b) {
            return None;
        }
        let points = &self.navigation.points;
        let nearest = |p: P| -> Option<usize> {
            let mut ids: Vec<_> = (0..points.len()).collect();
            ids.sort_by(|&i, &j| {
                let d = |k: usize| (points[k][0] - p[0]).hypot(points[k][1] - p[2]);
                d(i).total_cmp(&d(j))
            });
            ids.into_iter()
                .find(|&i| self.segment(p, [points[i][0], p[1], points[i][1]]))
        };
        let start = nearest(a)?;
        let end = nearest(b)?;
        let mut distances = vec![u64::MAX; points.len()];
        let mut previous = vec![usize::MAX; points.len()];
        let mut queue = BinaryHeap::new();
        distances[start] = 0;
        queue.push(Reverse((0, start)));
        while let Some(Reverse((cost, i))) = queue.pop() {
            if i == end {
                break;
            }
            if cost != distances[i] {
                continue;
            }
            for &j in &self.navigation.edges[i] {
                let weight = ((points[i][0] - points[j][0]).hypot(points[i][1] - points[j][1])
                    * 100.)
                    .ceil() as u64;
                let next = cost + weight;
                if next < distances[j] {
                    distances[j] = next;
                    previous[j] = i;
                    queue.push(Reverse((next, j)));
                }
            }
        }
        if distances[end] == u64::MAX {
            return None;
        }
        let mut indices = vec![end];
        let mut i = end;
        while i != start {
            i = previous[i];
            indices.push(i);
        }
        indices.reverse();
        let mut route: Vec<P> = indices
            .into_iter()
            .map(|i| [points[i][0], a[1].max(b[1]), points[i][1]])
            .collect();
        route.push(b);
        let mut result = vec![];
        let mut current = a;
        let mut offset = 0;
        while offset < route.len() {
            let next = (offset..route.len())
                .rev()
                .find(|&i| self.segment(current, route[i]))?;
            current = route[next];
            result.push(current);
            offset = next + 1;
        }
        Some(result)
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn concave_boundary_rejects_chord() {
        let f = Fence {
            flight_polygons: vec![vec![vec![
                [0., 0.],
                [10., 0.],
                [10., 3.],
                [3., 3.],
                [3., 10.],
                [0., 10.],
                [0., 0.],
            ]]],
            navigation: Navigation {
                points: vec![[1., 1.], [8., 1.], [1., 8.]],
                edges: vec![vec![1, 2], vec![0], vec![0]],
            },
        };
        let a = [8., 4., 1.];
        let b = [1., 4., 8.];
        assert!(f.contains(a) && f.contains(b));
        assert!(!f.segment(a, b));
        let path = f.route(a, b).unwrap();
        let mut p = a;
        for q in path {
            assert!(f.segment(p, q));
            p = q;
        }
        assert_eq!(p, b);
        assert!(!f.contains([12., 0., 1.]));
    }
    #[test]
    fn real_park_routes_stay_inside() {
        let f: Fence =
            serde_json::from_str(include_str!("../../../godot/data/park-scope.json")).unwrap();
        let a = [130., 20., -40.];
        let b = [500., 20., -350.];
        assert!(f.contains(a));
        let mut p = a;
        for q in f.route(a, b).unwrap() {
            assert!(f.segment(p, q));
            p = q;
        }
        assert_eq!(p, b);
        assert!(!f.contains([-500., 20., 500.]));
    }
}
