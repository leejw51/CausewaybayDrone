use crate::engine::{Config, State};
use rusqlite::{params, Connection, OptionalExtension};
use serde_json::{json, Value};
use std::{
    fs::{self, OpenOptions},
    io::Write,
    path::PathBuf,
};
pub struct Store {
    db: Connection,
    root: PathBuf,
}
impl Store {
    pub fn open(root: PathBuf) -> Result<Self, Box<dyn std::error::Error>> {
        fs::create_dir_all(&root)?;
        let db = Connection::open(root.join("simulator.sqlite3"))?;
        db.pragma_update(None, "journal_mode", "WAL")?;
        db.execute_batch("CREATE TABLE IF NOT EXISTS simulation(id INTEGER PRIMARY KEY CHECK(id=1),payload TEXT NOT NULL); CREATE TABLE IF NOT EXISTS orders(run_id TEXT,id INTEGER,customer INTEGER,cafe INTEGER,drone INTEGER,item TEXT,status TEXT,payload TEXT,PRIMARY KEY(run_id,id)); CREATE TABLE IF NOT EXISTS events(id TEXT PRIMARY KEY,run_id TEXT,sim_time REAL,kind TEXT,payload TEXT);")?;
        Ok(Self { db, root })
    }
    pub fn load(&self) -> Result<Option<State>, Box<dyn std::error::Error>> {
        let raw: Option<String> = self
            .db
            .query_row("SELECT payload FROM simulation WHERE id=1", [], |r| {
                r.get(0)
            })
            .optional()?;
        // A malformed snapshot is an error, never permission to overwrite it with a new run.
        match raw {
            Some(raw) => Ok(Some(serde_json::from_str(&raw)?)),
            None => Ok(None),
        }
    }
    pub fn config(&self) -> Config {
        fs::read_to_string(self.root.join("config.jsonl"))
            .unwrap_or_default()
            .lines()
            .filter_map(|l| serde_json::from_str::<Value>(l).ok())
            .filter_map(|v| serde_json::from_value::<Config>(v["config"].clone()).ok())
            .filter(|c| c.valid())
            .last()
            .unwrap_or_default()
    }
    pub fn save_config(&self, c: &Config) -> Result<(), Box<dyn std::error::Error>> {
        let latest = fs::read_to_string(self.root.join("config.jsonl"))
            .unwrap_or_default()
            .lines()
            .filter_map(|line| serde_json::from_str::<Value>(line).ok())
            .filter(|value| {
                serde_json::from_value::<Config>(value["config"].clone())
                    .map(|config| config.valid())
                    .unwrap_or(false)
            })
            .last();
        if latest.as_ref().map(|value| &value["config"]) == Some(&serde_json::to_value(c)?) {
            return Ok(());
        }
        let path = self.root.join("config.jsonl");
        if let Ok(bytes) = fs::read(&path) {
            if !bytes.is_empty() && !bytes.ends_with(b"\n") {
                let n = bytes
                    .iter()
                    .rposition(|b| *b == b'\n')
                    .map(|i| i + 1)
                    .unwrap_or(0);
                OpenOptions::new()
                    .write(true)
                    .open(&path)?
                    .set_len(n as u64)?;
            }
        }
        let mut f = OpenOptions::new().create(true).append(true).open(path)?;
        writeln!(
            f,
            "{}",
            json!({"schema":2,"saved_at":format!("{:?}",std::time::SystemTime::now()),"config":c})
        )?;
        f.sync_all()?;
        Ok(())
    }
    pub fn save(&mut self, s: &State, events: &[Value]) -> Result<(), Box<dyn std::error::Error>> {
        let tx = self.db.transaction()?;
        tx.execute(
            "INSERT OR REPLACE INTO simulation VALUES(1,?)",
            [serde_json::to_string(s)?],
        )?;
        for o in &s.orders {
            tx.execute(
                "INSERT OR REPLACE INTO orders VALUES(?,?,?,?,?,?,?,?)",
                params![
                    s.run_id,
                    o.id,
                    o.human,
                    o.cafe,
                    o.drone,
                    o.item,
                    o.state,
                    serde_json::to_string(o)?
                ],
            )?;
        }
        for e in events {
            tx.execute(
                "INSERT OR IGNORE INTO events VALUES(?,?,?,?,?)",
                params![
                    e["id"].as_str(),
                    s.run_id,
                    e["time"].as_f64(),
                    e["kind"].as_str(),
                    e.to_string()
                ],
            )?;
        }
        tx.commit()?;
        Ok(())
    }
}
