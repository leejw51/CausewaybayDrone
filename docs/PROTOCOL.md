# JSON / WebSocket protocol

Local endpoint: `ws://127.0.0.1:8799`. The Rust backend is authoritative and broadcasts `{ "type": "state", "state": {...}, "error": "" }` at 20 Hz. Commands receive a state snapshot or `{ "type": "error", "message": "..." }`. State schema version is 2. Snapshots also include `server_id` and monotonically increasing `revision`; the client discards older revisions and resets its revision cursor when the backend process changes. All positions are `[east_metres, local_height_metres, south_metres]`, matching the Godot map origin documented in MAP_REFERENCES.

```json
{"command":"configure","config":{"mode":"Solo","drones":1,"cafes":1,"humans":1,"auto_orders":true},"layout":{"homes":[[-155,3,145]],"pickups":[[-135,5,100]],"customers":[[-20,4,98]],"windows":[[-20,10,110]],"interiors":[[-20,10,102]]}}
```

The frontend derives layout coordinates from terrain and open map locations. The numeric example illustrates the protocol, not a surveyed landing site. Configuration is permitted only while stopped.

```json
{"command":"order","item":"Sandwich + Coffee","quantity":2,"human":0,"cafe":0,"apartment":true}
{"command":"autonomy","enabled":true}
{"command":"start"}
{"command":"stop"}
{"command":"snapshot"}
{"command":"batch"}
```

Customer/cafe/drone indexes are zero-based on the wire and one-based on screen. Order IDs are one-based within a run; `run_id + order.id` is the durable identity. `drone = -1` means unassigned. Payload quantity is 1–3. `batch` creates one outdoor order for each customer. Commands do not have retry IDs; a caller must not automatically retry an uncertain `order` command, because a second submission means a second order.

Order states: `ORDERED`, `COOKING`, `PACKING`, `SHIPPING`, `READY`, `HANDOFF`, `OUT FOR DELIVERY`, `DELIVERING`, `DELIVERED`, `FAILED`. Aircraft states: `IDLE`, `TO CAFE`, `WAITING FOR FOOD`, `LOADING`, `DELIVERING`, `UNLOADING`, `RETURNING`. The order may already be delivered while its aircraft is still returning.

Every material transition gets a unique event ID using run ID and a persisted sequence counter. SQLite saves orders, new events and the simulation snapshot in one transaction at transitions and periodically during flight. The backend stops progression if saving fails. On process restart it loads positions, velocities, routes, timers, payloads and orders, then waits for Start. Godot reconnects and reconstructs visuals from the snapshot.

The default listener is loopback-only, without account authentication. Remote deployment needs a separate authenticated/TLS gateway, command authorization, idempotency and ownership rules. No real vehicle adapter is connected by this protocol.

Godot FFI implementation follows the [godot-rust GDExtension documentation](https://godot-rust.github.io/book/intro/hello-world.html).

Cafe timers reset at each stage: cooking is 12 + 4 × quantity seconds, packing 4 seconds, dispatch shipping 4 seconds. PACKING_STARTED and SHIPPING_STARTED precede FOOD_READY; HANDOFF_STARTED cannot occur before FOOD_READY. Cafe job and timer are included in persisted snapshots for pause/recovery.

`{"command":"language","language":"ko"}` changes UI language without resetting or pausing the scenario. Allowed codes: `en`, `ko`, `ja`, `yue_HK`, `zh_CN`, `cs`. Config and state snapshots include `language`; the preference is appended to config.jsonl. Display translations never change canonical order item/state strings.

`{"command":"sound","enabled":true,"volume":0.65}` saves sound-effects preferences without resetting the simulation. Volume must be a finite number from 0 to 1. Missing legacy config fields default to enabled at 0.65.

Each vehicle includes `body` with thrust (world-axis N), acceleration (m/s²), pitch/roll (radians), hold target, and initialization flag. Physics uses metres, seconds, kg and N; legacy snapshots default this object.

`{"command":"service","drone":0,"reason":"charge"}` and reason `repair` request a dock visit. `{"command":"fault","drone":0}` injects a controlled simulated fault; IDs are zero-based. Already-servicing drones reject duplicate service/fault requests. New states: RECOVERY RETURN, CHARGING, DIAGNOSING, REPAIRING; interrupted orders use RETURNING ITEMS until dock arrival, then ORDERED for replacement. Vehicle `maintenance` records health, requested reason, elapsed service seconds, charge/repair counts, and avoiding flag. Vehicle-specific events use order=0 and an explicit drone field. All service progression pauses with the simulation.

### Challenge command

`{"command":"challenge"}` requires a configured fleet and no ACTIVE challenge. It enables autonomous orders, starts/resumes simulation, emits CHALLENGE_STARTED, and creates a 600-second mission for min(humans*2,8) deliveries. The snapshot `arcade` object contains score, combo, best_combo, last_delivery, and nullable challenge {deadline,target,delivered,status}. Status is ACTIVE, WON, or EXPIRED. Only delivery completion increments scores; mission success adds 1000 once. Snapshot restore defaults arcade for older saves. Pause freezes deadlines because they use simulation time.
