//! Optional presentation challenges score real simulation outcomes.
use serde::{Deserialize, Serialize};
#[derive(Clone, Serialize, Deserialize, Default)]
pub struct Arcade {
    pub score: u64,
    pub combo: u64,
    pub best_combo: u64,
    pub last_delivery: Option<f64>,
    pub challenge: Option<Challenge>,
}
#[derive(Clone, Serialize, Deserialize)]
pub struct Challenge {
    pub deadline: f64,
    pub target: u64,
    pub delivered: u64,
    pub status: String,
}
impl Arcade {
    pub fn delivery(&mut self, time: f64, apartment: bool) {
        self.combo = if self.last_delivery.is_some_and(|last| time - last <= 60.) {
            self.combo + 1
        } else {
            1
        };
        self.best_combo = self.best_combo.max(self.combo);
        self.last_delivery = Some(time);
        self.score += 100 + 25 * self.combo.min(10) + if apartment { 50 } else { 0 };
        if let Some(c) = &mut self.challenge {
            if c.status == "ACTIVE" && time <= c.deadline {
                c.delivered += 1;
                if c.delivered >= c.target {
                    c.status = "WON".into();
                    self.score += 1000;
                }
            }
        }
    }
    pub fn tick(&mut self, time: f64) {
        if self.last_delivery.is_some_and(|last| time - last > 60.) {
            self.combo = 0;
        }
        if let Some(c) = &mut self.challenge {
            if c.status == "ACTIVE" && time > c.deadline {
                c.status = "EXPIRED".into();
            }
        }
    }
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn scoring_combo_deadline_and_restore() {
        let mut a = Arcade::default();
        a.challenge = Some(Challenge {
            deadline: 200.,
            target: 2,
            delivered: 0,
            status: "ACTIVE".into(),
        });
        a.delivery(10., false);
        a.delivery(40., true);
        assert_eq!(a.score, 1325);
        assert_eq!(a.best_combo, 2);
        assert_eq!(a.challenge.as_ref().unwrap().status, "WON");
        let mut a: Arcade = serde_json::from_str(&serde_json::to_string(&a).unwrap()).unwrap();
        a.tick(101.);
        assert_eq!(a.combo, 0);
        a.challenge = Some(Challenge {
            deadline: 120.,
            target: 1,
            delivered: 0,
            status: "ACTIVE".into(),
        });
        a.tick(121.);
        a.delivery(122., false);
        assert_eq!(a.challenge.unwrap().status, "EXPIRED");
    }
}
