mod ai;
mod arcade;
mod avoidance;
mod engine;
mod geofence;
mod guidance;
mod maintenance;
mod physics;
mod store;
use engine::{Config, Engine, Layout};
use futures_util::{SinkExt, StreamExt};
use serde_json::{json, Value};
use std::{path::PathBuf, sync::Arc};
use store::Store;
use tokio::{
    net::TcpListener,
    sync::{broadcast, Mutex},
};
use tokio_tungstenite::tungstenite::Message;
struct App {
    revision: u64,
    server_id: String,
    engine: Engine,
    store: Store,
    error: String,
}
impl App {
    fn persist(&mut self) {
        match self.store.save(&self.engine.state, &self.engine.events) {
            Ok(()) => {
                self.engine.events.clear();
                self.error.clear()
            }
            Err(e) => {
                self.error = e.to_string();
                self.engine.state.running = false;
            }
        }
    }
    fn snapshot(&self) -> String {
        json!({"type":"state","revision":self.revision,"server_id":self.server_id,"state":self.engine.state,"error":self.error}).to_string()
    }
    fn command(&mut self, v: Value) -> Result<(), String> {
        self.revision += 1;
        match v["command"].as_str().unwrap_or("") {
            "configure" => {
                if self.engine.state.running {
                    return Err("Stop the simulation before changing its configuration".into());
                }
                let c: Config =
                    serde_json::from_value(v["config"].clone()).map_err(|e| e.to_string())?;
                let l: Layout =
                    serde_json::from_value(v["layout"].clone()).map_err(|e| e.to_string())?;
                self.engine.configure(c, l)?;
                self.store
                    .save_config(&self.engine.state.config)
                    .map_err(|e| e.to_string())?;
            }
            "challenge" => {
                if !self.engine.within_scope() {
                    return Err("Configure a fleet inside Olympic Park".into());
                }
                if self.engine.state.vehicles.is_empty() {
                    return Err("Configure a simulation first".into());
                }
                if self
                    .engine
                    .state
                    .arcade
                    .challenge
                    .as_ref()
                    .is_some_and(|c| c.status == "ACTIVE")
                {
                    return Err("Challenge already active".into());
                }
                let target = (self.engine.state.config.humans * 2).min(8) as u64;
                self.engine.state.arcade.challenge = Some(arcade::Challenge {
                    deadline: self.engine.state.time + 600.,
                    target,
                    delivered: 0,
                    status: "ACTIVE".into(),
                });
                self.engine.state.config.auto_orders = true;
                self.store
                    .save_config(&self.engine.state.config)
                    .map_err(|e| e.to_string())?;
                self.engine.state.running = true;
                self.engine.event("CHALLENGE_STARTED", 0);
            }
            "instant_charge" => {
                let i = v["drone"].as_u64().ok_or("Drone missing")? as usize;
                self.engine.instant_charge(i)?;
            }
            "service" => {
                let i = v["drone"].as_u64().ok_or("Drone missing")? as usize;
                let reason = v["reason"].as_str().ok_or("Service reason missing")?;
                self.engine.request_service(i, reason)?;
            }
            "fault" => {
                let i = v["drone"].as_u64().ok_or("Drone missing")? as usize;
                self.engine.inject_fault(i)?;
            }
            "sound" => {
                let mut config = self.engine.state.config.clone();
                config.sfx_enabled = v["enabled"]
                    .as_bool()
                    .ok_or("Sound enabled boolean required")?;
                config.sfx_volume = v["volume"].as_f64().ok_or("Sound volume required")?;
                if !config.valid() {
                    return Err("Sound volume must be between 0 and 1".into());
                }
                self.store.save_config(&config).map_err(|e| e.to_string())?;
                self.engine.state.config = config;
            }
            "language" => {
                let language = v["language"].as_str().ok_or("Language missing")?;
                let mut config = self.engine.state.config.clone();
                config.language = language.into();
                if !config.valid() {
                    return Err("Unsupported language".into());
                }
                self.store.save_config(&config).map_err(|e| e.to_string())?;
                self.engine.state.config = config;
            }
            "autonomy" => {
                self.engine.state.config.auto_orders = v["enabled"]
                    .as_bool()
                    .ok_or("Autonomy requires enabled boolean")?;
                self.store
                    .save_config(&self.engine.state.config)
                    .map_err(|e| e.to_string())?;
                self.engine.event("AUTONOMY_CHANGED", 0);
            }
            "start" => {
                if !self.engine.within_scope() {
                    return Err("Configure a fleet inside Olympic Park".into());
                }
                if self.engine.state.vehicles.is_empty() {
                    return Err("Configure a simulation first".into());
                }
                self.engine.state.running = true;
                self.engine.event("SIMULATION_STARTED", 0);
            }
            "stop" => {
                self.engine.state.running = false;
                self.engine.event("SIMULATION_STOPPED", 0);
            }
            "order" => {
                let h = v["human"].as_u64().ok_or("Customer missing")? as usize;
                let c = v["cafe"].as_u64().ok_or("Cafe missing")? as usize;
                let item = v["item"].as_str().ok_or("Item missing")?;
                let q = v["quantity"].as_u64().ok_or("Quantity missing")? as usize;
                if v["apartment"].as_bool().unwrap_or(false)
                    && (h >= self.engine.state.layout.windows.len()
                        || h >= self.engine.state.layout.interiors.len())
                {
                    return Err("Apartment window layout unavailable".into());
                }
                let id = self.engine.order(h, c, item, q)?;
                if v["apartment"].as_bool().unwrap_or(false) {
                    if h >= self.engine.state.layout.windows.len()
                        || h >= self.engine.state.layout.interiors.len()
                    {
                        self.engine.state.orders.pop();
                        return Err("Apartment window layout unavailable".into());
                    }
                    self.engine.state.orders[id - 1].apartment = true;
                }
            }
            "batch" => {
                for h in 0..self.engine.state.config.humans {
                    self.engine.order(
                        h,
                        h % self.engine.state.config.cafes,
                        ["Sandwich", "Coffee", "Sandwich + Coffee"][h % 3],
                        1,
                    )?;
                }
            }
            "snapshot" => {}
            _ => return Err("Unknown command".into()),
        }
        self.persist();
        if !self.error.is_empty() {
            return Err(self.error.clone());
        }
        Ok(())
    }
}
#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    let root = std::env::var("COAST_DATA_DIR")
        .map(PathBuf::from)
        .unwrap_or_else(|_| {
            PathBuf::from(std::env::var("HOME").unwrap()).join(".causewaybaydrone")
        });
    let map = std::env::var("COAST_MAP").unwrap_or_else(|_| {
        format!(
            "{}/../../godot/data/real-map.json",
            env!("CARGO_MANIFEST_DIR")
        )
    });
    let mut map_data: Value = serde_json::from_str(&std::fs::read_to_string(map)?)?;
    map_data["scope"] = serde_json::from_str(include_str!("../../../godot/data/park-scope.json"))?;
    let mut engine = Engine::new(map_data);
    let mut store = Store::open(root)?;
    if let Some(s) = store.load()? {
        engine.state = s;
        engine.state.running = false;
        // Resume old apartment flights at the balcony instead of entering the building.
        for i in 0..engine.state.vehicles.len() {
            let v = &engine.state.vehicles[i];
            if v.state == "DELIVERING" && v.job >= 0 {
                let order = &engine.state.orders[v.job as usize];
                if order.apartment {
                    let dest = engine.state.layout.customers[order.human];
                    engine.route(i, dest);
                }
            }
        }
        if !engine.within_scope() {
            // Archive the old run in SQLite; do not resume an out-of-park layout.
            store.save(&engine.state, &[])?;
            engine.state = engine::State {
                config: engine.state.config.clone(),
                ..engine::State::default()
            };
            eprintln!("PARK_SCOPE_MIGRATION: previous run archived; configure an in-park fleet");
        }
    } else {
        engine.state.config = store.config();
    }
    store.save_config(&engine.state.config)?;
    let app = Arc::new(Mutex::new(App {
        revision: 0,
        server_id: format!("{:?}", std::time::SystemTime::now()),
        engine,
        store,
        error: String::new(),
    }));
    let (broadcast, _) = broadcast::channel::<String>(16);
    let test_speed: usize = std::env::var("COAST_TEST_SPEED")
        .ok()
        .and_then(|s| s.parse().ok())
        .unwrap_or(1)
        .clamp(1, 40);
    let tick_app = app.clone();
    let tick_tx = broadcast.clone();
    tokio::spawn(async move {
        let mut interval = tokio::time::interval(std::time::Duration::from_millis(50));
        interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        let mut n = 0u64;
        loop {
            interval.tick().await;
            let mut a = tick_app.lock().await;
            a.revision += 1;
            for _ in 0..test_speed {
                a.engine.tick(0.05);
            }
            n += 1;
            if n % 20 == 0 || !a.engine.events.is_empty() {
                a.persist();
            }
            let _ = tick_tx.send(a.snapshot());
        }
    });
    let addr = std::env::var("COAST_BIND").unwrap_or_else(|_| "127.0.0.1:8799".into());
    let listener = TcpListener::bind(&addr).await?;
    println!("COAST_BACKEND_READY ws://{addr}");
    loop {
        tokio::select! { connection=listener.accept()=>{let (stream,_)=connection?;let app=app.clone();let mut rx=broadcast.subscribe();tokio::spawn(async move{let Ok(ws)=tokio_tungstenite::accept_async(stream).await else{return};let (mut sink,mut source)=ws.split();let initial=app.lock().await.snapshot();if sink.send(Message::Text(initial.into())).await.is_err(){return}loop{tokio::select!{msg=source.next()=>{let Some(Ok(msg))=msg else{break};if let Message::Text(txt)=msg{if txt.len()>200000{break}let result=serde_json::from_str::<Value>(&txt).map_err(|e|e.to_string());let mut a=app.lock().await;let reply=match result.and_then(|v|a.command(v)){Ok(())=>a.snapshot(),Err(e)=>json!({"type":"error","message":e}).to_string()};if sink.send(Message::Text(reply.into())).await.is_err(){break}}},event=rx.recv()=>{match event{Ok(s)=>if sink.send(Message::Text(s.into())).await.is_err(){break},Err(broadcast::error::RecvError::Lagged(_))=>continue,Err(_)=>break}}}}});},_=tokio::signal::ctrl_c()=>{let mut a=app.lock().await;a.engine.state.running=false;a.persist();break;}}
    }
    Ok(())
}
#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn instant_charge_resumes_delivery_without_moving_drone() {
        let mut e = engine();
        e.configure(
            Config {
                drones: 1,
                cafes: 1,
                humans: 1,
                mode: "Solo".into(),
                auto_orders: false,
                ..Config::default()
            },
            Layout {
                homes: vec![[0., 2., 0.]],
                pickups: vec![[20., 4., 0.]],
                customers: vec![[45., 3.5, 15.]],
                ..Layout::default()
            },
        )
        .unwrap();
        e.order(0, 0, "Coffee", 1).unwrap();
        e.state.vehicles[0].battery = 12.;
        e.state.vehicles[0].state = "CHARGING".into();
        e.state.vehicles[0].maintenance.requested = "charge".into();
        let position = e.state.vehicles[0].position;
        assert!(e.instant_charge(4).is_err());
        e.instant_charge(0).unwrap();
        assert_eq!(e.state.vehicles[0].battery, 100.);
        assert_eq!(e.state.vehicles[0].position, position);
        assert_eq!(e.state.vehicles[0].state, "IDLE");
        assert!(e.state.running);
        e.tick(0.05);
        assert_eq!(e.state.vehicles[0].state, "TO CAFE");
        let job = e.state.vehicles[0].job;
        let path = e.state.vehicles[0].path.clone();
        e.state.vehicles[0].battery = 30.;
        e.instant_charge(0).unwrap();
        assert_eq!(e.state.vehicles[0].job, job);
        assert_eq!(e.state.vehicles[0].path, path);
        e.state.vehicles[0].state = "REPAIRING".into();
        e.state.vehicles[0].maintenance.health = 55.;
        e.instant_charge(0).unwrap();
        assert_eq!(e.state.vehicles[0].state, "REPAIRING");
        assert_eq!(e.state.vehicles[0].maintenance.health, 55.);
    }
    #[test]
    fn language_jsonl_persistence_and_validation() {
        let root = std::env::temp_dir().join(format!(
            "drone-language-{}-{:?}",
            std::process::id(),
            std::time::SystemTime::now()
        ));
        let mut app = App {
            revision: 0,
            server_id: "test".into(),
            engine: engine(),
            store: Store::open(root.clone()).unwrap(),
            error: String::new(),
        };
        for code in ["en", "ko", "ja", "yue_HK", "zh_CN", "cs"] {
            app.command(json!({"command":"language", "language":code}))
                .unwrap();
            assert_eq!(app.store.config().language, code);
            assert_eq!(app.store.load().unwrap().unwrap().config.language, code);
        }
        assert!(app
            .command(json!({"command":"language", "language":"invalid"}))
            .is_err());
        assert_eq!(app.store.config().language, "cs");
        let rows = std::fs::read_to_string(root.join("config.jsonl")).unwrap();
        assert_eq!(rows.lines().count(), 6);
        for row in rows.lines() {
            assert!(serde_json::from_str::<Value>(row).is_ok());
        }
        app.command(json!({"command":"sound", "enabled":false,"volume":0.25}))
            .unwrap();
        assert!(!app.store.config().sfx_enabled);
        assert_eq!(app.store.config().sfx_volume, 0.25);
        assert!(app
            .command(json!({"command":"sound","enabled":true,"volume":1.5}))
            .is_err());
        assert_eq!(app.store.config().sfx_volume, 0.25);
        drop(app);
        let store = Store::open(root.clone()).unwrap();
        assert_eq!(store.config().language, "cs");
        assert!(!store.config().sfx_enabled);
        assert_eq!(store.load().unwrap().unwrap().config.sfx_volume, 0.25);
        drop(store);
        std::fs::remove_dir_all(&root).unwrap();
        let legacy: Config =
            serde_json::from_value(json!({"drones":1,"cafes":1,"humans":1,"mode":"Solo"})).unwrap();
        assert_eq!(legacy.language, "en");
        std::fs::create_dir_all(&root).unwrap();
        std::fs::write(
            root.join("config.jsonl"),
            "{\"config\":{\"drones\":1,\"cafes\":1,\"humans\":1,\"mode\":\"Solo\"}}\n",
        )
        .unwrap();
        let store = Store::open(root.clone()).unwrap();
        store.save_config(&legacy).unwrap();
        let lines = std::fs::read_to_string(root.join("config.jsonl")).unwrap();
        let last: Value = serde_json::from_str(lines.lines().last().unwrap()).unwrap();
        assert_eq!(last["config"]["language"], "en");
        drop(store);
        std::fs::remove_dir_all(&root).unwrap();
    }
    #[test]
    fn fault_recovery_requeues_then_repairs_and_charges() {
        let mut e = engine();
        e.configure(
            Config {
                drones: 1,
                cafes: 1,
                humans: 1,
                mode: "Solo".into(),
                auto_orders: false,
                ..Config::default()
            },
            Layout {
                homes: vec![[0., 2., 0.]],
                pickups: vec![[20., 4., 0.]],
                customers: vec![[45., 3.5, 15.]],
                windows: vec![],
                interiors: vec![],
            },
        )
        .unwrap();
        e.order(0, 0, "Sandwich + Coffee", 1).unwrap();
        e.state.running = true;
        for _ in 0..6000 {
            e.tick(0.05);
            if e.state.orders[0].state == "OUT FOR DELIVERY" {
                break;
            }
        }
        assert_eq!(e.state.orders[0].state, "OUT FOR DELIVERY");
        e.inject_fault(0).unwrap();
        e.tick(0.05);
        assert_eq!(e.state.vehicles[0].state, "RECOVERY RETURN");
        assert!(e.state.vehicles[0].payload > 0.);
        let mut restored = false;
        for _ in 0..60000 {
            e.tick(0.05);
            if !restored && e.state.vehicles[0].state == "REPAIRING" {
                e.state.running = false;
                let health = e.state.vehicles[0].maintenance.health;
                e.tick(10.);
                assert_eq!(health, e.state.vehicles[0].maintenance.health);
                let raw = serde_json::to_string(&e.state).unwrap();
                e.state = serde_json::from_str(&raw).unwrap();
                e.state.running = true;
                restored = true;
            }
            if e.state.orders[0].state == "DELIVERED" && e.state.vehicles[0].state == "IDLE" {
                break;
            }
        }
        assert!(restored);
        assert_eq!(e.state.orders.len(), 1);
        assert_eq!(e.state.orders[0].state, "DELIVERED");
        assert_eq!(e.state.vehicles[0].maintenance.repairs, 1);
        assert!(e.state.vehicles[0].maintenance.charges >= 1);
        assert!(e.events.iter().any(|v| v["kind"] == "ORDER_REQUEUED"));
        e.state.vehicles[0].battery = 82.;
        e.tick(0.05);
        assert_eq!(e.state.vehicles[0].state, "CHARGING");
        let battery = e.state.vehicles[0].battery;
        e.tick(10.);
        assert!(e.state.vehicles[0].battery > battery && e.state.vehicles[0].battery < 83.);
    }
    #[test]
    fn terrain_matches_both_triangle_halves_and_grid_edges() {
        let e = Engine::new(
            json!({"terrain":{"x":0,"z":0,"step":10,"nx":2,"nz":2,"heights":[0,10,20,40]},"buildings":[]}),
        );
        assert!((e.top([2., 0., 3.]) - 8.).abs() < 1e-9);
        assert!((e.top([8., 0., 7.]) - 27.).abs() < 1e-9);
        assert!((e.top([5., 0., 5.]) - 15.).abs() < 1e-9);
        assert!((e.top([10., 0., 10.]) - 40.).abs() < 1e-9);
        assert!((e.top([-10., 0., -10.])).abs() < 1e-9);
    }
    fn engine() -> Engine {
        Engine::new(
            json!({"terrain":{"x":-500,"z":-500,"step":100,"nx":11,"nz":11,"heights":vec![0.;121]},"buildings":[]}),
        )
    }
    fn solo_ai() -> Engine {
        let mut e = engine();
        e.configure(
            Config {
                drones: 1,
                cafes: 1,
                humans: 1,
                mode: "Solo".into(),
                auto_orders: false,
                ..Config::default()
            },
            Layout {
                homes: vec![[0., 2., 0.]],
                pickups: vec![[30., 4., 0.]],
                customers: vec![[60., 3., 0.]],
                windows: vec![],
                interiors: vec![],
            },
        )
        .unwrap();
        e.state.running = true;
        e
    }
    #[test]
    fn ai_flies_over_thin_obstacle_with_physics() {
        let mut e = solo_ai();
        e.buildings.push([13., 13.1, -3., 3., 25.]);
        e.order(0, 0, "Coffee", 1).unwrap();
        let mut crossed = false;
        for _ in 0..16000 {
            e.tick(0.05);
            let p = e.state.vehicles[0].position;
            if p[0] >= 10. && p[0] <= 16.1 && p[2].abs() <= 6. {
                crossed = true;
                assert!(p[1] > 31., "Obstacle clearance lost: {p:?}");
            }
            if e.state.orders[0].state == "DELIVERED" && e.state.vehicles[0].state == "IDLE" {
                break;
            }
        }
        assert!(crossed);
        assert_eq!(e.state.orders[0].state, "DELIVERED");
        assert_eq!(e.state.vehicles[0].state, "IDLE");
    }
    #[test]
    fn ai_low_battery_recovers_cargo_and_recharges() {
        let mut e = solo_ai();
        e.order(0, 0, "Coffee", 1).unwrap();
        for _ in 0..6000 {
            e.tick(0.05);
            if e.state.orders[0].state == "OUT FOR DELIVERY" {
                break;
            }
        }
        assert!(e.state.vehicles[0].payload > 0.);
        e.state.vehicles[0].battery = 19.;
        e.tick(0.05);
        assert_eq!(e.state.vehicles[0].state, "RECOVERY RETURN");
        assert!(e.state.vehicles[0].payload > 0.);
        let mut charged = false;
        for _ in 0..60000 {
            e.tick(0.05);
            if e.state.vehicles[0].maintenance.charges > 0 {
                charged = true;
                break;
            }
        }
        assert!(charged);
        assert_eq!(e.state.vehicles[0].battery, 100.);
        assert_eq!(e.state.vehicles[0].payload, 0.);
        assert!(e.events.iter().any(|v| v["kind"] == "ORDER_REQUEUED"));
        assert!(!e.events.iter().any(|v| v["kind"] == "DELIVERED"));
    }
    #[test]
    fn full_flow_and_resume() {
        let mut e = engine();
        e.configure(
            Config {
                drones: 2,
                cafes: 2,
                humans: 4,
                mode: "Massive".into(),
                auto_orders: false,
                language: "en".into(),
                sfx_enabled: true,
                sfx_volume: 0.65,
            },
            Layout {
                homes: vec![[-30., 2., 30.], [-20., 2., 30.]],
                pickups: vec![[0., 4., 0.], [20., 4., 0.]],
                customers: vec![
                    [40., 3., 40.],
                    [50., 3., 40.],
                    [40., 3., 60.],
                    [50., 3., 60.],
                ],
                windows: vec![],
                interiors: vec![],
            },
        )
        .unwrap();
        for h in 0..4 {
            e.order(h, h % 2, "Sandwich + Coffee", 2).unwrap();
        }
        e.state.running = true;
        let mut resumed = false;
        let mut history = vec![];
        for _ in 0..20000 {
            e.tick(0.05);
            history.extend(e.events.drain(..));
            if !resumed && e.state.orders.iter().any(|o| o.state == "SHIPPING") {
                let bytes = serde_json::to_string(&e.state).unwrap();
                e.state = serde_json::from_str(&bytes).unwrap();
                resumed = true;
            }
            if e.state.orders.iter().all(|o| o.state == "DELIVERED")
                && e.state.vehicles.iter().all(|v| v.state == "IDLE")
            {
                break;
            }
        }
        assert!(resumed);
        assert!(e.state.orders.iter().all(|o| o.state == "DELIVERED"));
        assert!(e.state.vehicles.iter().all(|v| v.state == "IDLE"));
        for id in 1..=4 {
            let kinds: Vec<_> = history
                .iter()
                .filter(|e| e["order"] == id)
                .map(|e| e["kind"].as_str().unwrap())
                .collect();
            assert_eq!(kinds.len(), 11);
            let sequence: Vec<_> = kinds
                .iter()
                .copied()
                .filter(|k| *k != "DRONE_DISPATCHED")
                .collect();
            assert_eq!(
                sequence,
                vec![
                    "ORDER_PLACED",
                    "COOKING_STARTED",
                    "PACKING_STARTED",
                    "SHIPPING_STARTED",
                    "FOOD_READY",
                    "HANDOFF_STARTED",
                    "PICKED_UP",
                    "DELIVERY_STARTED",
                    "DELIVERED",
                    "DRONE_RETURNED"
                ]
            );
            assert!(
                kinds.iter().position(|k| *k == "DRONE_DISPATCHED").unwrap()
                    < kinds.iter().position(|k| *k == "HANDOFF_STARTED").unwrap()
            );
        }
        let t = e.state.time;
        e.state.running = false;
        e.tick(10.);
        assert_eq!(t, e.state.time);
    }
    #[test]
    fn rejects_invalid() {
        let mut e = engine();
        assert!(e.order(0, 0, "Coffee", 1).is_err());
        let mut c = Config::default();
        c.drones = 0;
        assert!(!c.valid());
    }
    #[test]
    fn massive_and_window_routes() {
        let mut e = engine();
        let layout = Layout {
            homes: (0..8).map(|i| [-100. + i as f64 * 10., 2., 60.]).collect(),
            pickups: vec![[0., 4., 0.], [25., 4., 0.], [50., 4., 0.]],
            customers: (0..20)
                .map(|i| [80. + (i % 5) as f64 * 14., 3.5, 50. + (i / 5) as f64 * 20.])
                .collect(),
            windows: (0..20)
                .map(|i| [80. + (i % 5) as f64 * 14., 9.8, 62. + (i / 5) as f64 * 20.])
                .collect(),
            interiors: (0..20)
                .map(|i| [80. + (i % 5) as f64 * 14., 9.8, 54. + (i / 5) as f64 * 20.])
                .collect(),
        };
        e.configure(
            Config {
                drones: 8,
                cafes: 3,
                humans: 20,
                mode: "Massive".into(),
                auto_orders: false,
                language: "en".into(),
                sfx_enabled: true,
                sfx_volume: 0.65,
            },
            layout.clone(),
        )
        .unwrap();
        for h in 0..20 {
            e.order(h, h % 3, "Sandwich + Coffee", 1).unwrap();
            e.state.orders[h].apartment = h % 2 == 0;
        }
        e.state.running = true;
        let mut entry = false;
        let mut exit = false;
        let mut curved_motion = false;
        let mut peak_active = 0;
        let mut used = std::collections::HashSet::new();
        for _ in 0..50000 {
            e.tick(0.05);
            peak_active = peak_active.max(
                e.state
                    .vehicles
                    .iter()
                    .filter(|v| v.state != "IDLE")
                    .count(),
            );
            for (i, v) in e.state.vehicles.iter().enumerate() {
                if v.job >= 0 {
                    used.insert(i);
                    if v.path.len() > 4
                        && v.velocity[1].abs() > 0.3
                        && v.velocity[0].hypot(v.velocity[2]) > 0.3
                    {
                        curved_motion = true;
                    }
                    let o = &e.state.orders[v.job as usize];
                    if o.apartment {
                        if v.state == "DELIVERING" {
                            assert_eq!(v.path.last(), Some(&layout.windows[o.human]));
                            assert!(!v.path.contains(&layout.interiors[o.human]));
                            assert!(v.path.contains(&layout.windows[o.human]));
                            entry = true;
                        }
                        if v.state == "RETURNING" && !v.path.is_empty() {
                            assert_eq!(v.path[0], layout.windows[o.human]);
                            exit = true;
                        }
                    }
                }
            }
            if e.state.orders.iter().all(|o| o.state == "DELIVERED")
                && e.state.vehicles.iter().all(|v| v.state == "IDLE")
            {
                break;
            }
        }
        assert!(entry && exit);
        assert!(
            curved_motion,
            "Flight must blend vertical and horizontal movement through curves"
        );
        assert!(peak_active >= 3, "Multiple drones must work concurrently");
        assert!(
            used.len() >= 3,
            "Dispatch must distribute orders across the fleet"
        );
        assert_eq!(
            e.state
                .orders
                .iter()
                .filter(|o| o.state == "DELIVERED")
                .count(),
            20
        );
        assert!(e.state.vehicles.iter().all(|v| v.state == "IDLE"));
    }
    #[test]
    fn autonomous_repeat_pause_and_resume() {
        let mut e = engine();
        e.configure(
            Config {
                drones: 1,
                cafes: 1,
                humans: 1,
                mode: "Solo".into(),
                auto_orders: true,
                language: "en".into(),
                sfx_enabled: true,
                sfx_volume: 0.65,
            },
            Layout {
                homes: vec![[-30., 2., 30.]],
                pickups: vec![[0., 4., 0.]],
                customers: vec![[40., 3.5, 40.]],
                windows: vec![[40., 9.8, 52.]],
                interiors: vec![[40., 9.8, 44.]],
            },
        )
        .unwrap();
        e.tick(10.);
        assert!(e.state.orders.is_empty());
        e.state.running = true;
        let mut restored = false;
        for _ in 0..40000 {
            e.tick(0.05);
            assert!(
                e.state
                    .orders
                    .iter()
                    .filter(|o| !matches!(o.state.as_str(), "DELIVERED" | "FAILED"))
                    .count()
                    <= 1
            );
            if !restored && e.state.orders.iter().any(|o| o.state == "DELIVERED") {
                let raw = serde_json::to_string(&e.state).unwrap();
                e.state = serde_json::from_str(&raw).unwrap();
                restored = true;
            }
            if e.state
                .orders
                .iter()
                .filter(|o| o.state == "DELIVERED")
                .count()
                >= 3
            {
                break;
            }
        }
        assert!(restored);
        assert_eq!(e.state.orders.len(), 3);
        assert!(e.state.orders.iter().all(|o| o.state == "DELIVERED"));
        let n = e.state.orders.len();
        let time = e.state.time;
        e.state.running = false;
        for _ in 0..1000 {
            e.tick(1.);
        }
        assert_eq!(e.state.orders.len(), n);
        assert_eq!(e.state.time, time);
        e.state.config.auto_orders = false;
        e.state.running = true;
        for _ in 0..1000 {
            e.tick(0.05);
        }
        assert_eq!(e.state.orders.len(), n);
    }
}
