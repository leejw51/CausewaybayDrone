# CAUSEWAYBAY DRONE

A local autonomous-delivery simulator and operations prototype built with a **Rust backend, SQLite, a Rust Godot GDExtension, and JSON over WebSocket**. The world uses real Olympic Park / Seoul map geometry at metre scale. Cafes, robot kitchens, customers and apartment delivery bays are fictional simulation fixtures.

## Run

```sh
make help
make start
make start ARGS=--autonomous  # Immediately start/resume autonomous operations
make stop
make test
make format
```

macOS defaults: Godot at `/Applications/Godot.app`, Rust/Cargo, Python 3 and `uv` for formatting. Override `GODOT` and `PYTHON` in Make. The supplied build target copies the macOS native library; other platforms need the corresponding library copy target. `make start` builds/imports, starts the local backend and opens Godot. `make stop` saves backend state and closes the managed processes. Logs are under `build/`.

## Use the simulator

1. Press Space on **CAUSEWAYBAY DRONE**. The title preserves the requested text, “press spackey to continue”.
2. Choose **Solo** (one drone/cafe/customer) or **Massive**. Set counts, then **NEW SIMULATION / APPLY COUNTS**. Maximum selectable counts: 32 drones, 12 cafes, 200 customers. The tested concurrent scenario is 8 drones, 3 cafes and 20 orders; the maximum is a configuration bound, not a performance guarantee.
3. **AUTONOMOUS** is enabled by default. Press **START** once: a fresh scenario is configured automatically, people place their own orders, and cafes/drones keep fulfilling them. Each person has at most one unfinished automatic order and orders again 90–130 simulation seconds after delivery. The scheduler chooses a cafe with the shortest outstanding queue and varies food/quantity; every third customer uses an apartment window. Toggle autonomy off to stop new automatic demand while existing jobs finish. The setting persists in `config.jsonl`.
4. You can also order a sandwich, coffee or meal set; select quantity, cafe, customer and **Outside / Apartment window**. Orders can be queued while stopped. **MASSIVE / ORDER FOR EVERYONE** generates one outdoor order per customer.
5. **START** advances the simulation. **STOP** pauses the clock and all workflow progress. Start resumes. Changing counts starts a new scenario; previous orders and events remain in SQLite under their run ID.
6. Choose a drone in the live list, then **3RD PERSON / 1ST PERSON**. `V` toggles the view; right-drag orbits and the wheel zooms. Cafe and Customer buttons cycle subjects. `M` toggles the menu.

Each order follows **queued → robot cooking → ready → drone pickup → loaded flight → handoff → delivered → drone return**. A robot visibly cooks and extends its arms to hand over the Blender-made food. The payload follows the drone, then moves to the customer. Apartment orders use an open window approach waypoint, an indoor handoff point, and an exit waypoint before climbing to return. A face display and optional local text-to-speech announce the selected drone’s actions. Speech requires an installed English system voice; captions remain available.

## Architecture and persistence

- `rust/backend`: authoritative 20 Hz simulation, dispatch, cooking queues, flight kinematics, battery, order lifecycle, event journal and SQLite transactions. Restored simulations start paused.
- `rust/frontend`: native `CoastTransport` GDExtension exposes JSON WebSocket send/poll functions to Godot through Rust FFI.
- `godot/scripts/fleet_simulator.gd`: map-aware fixture placement, 3D visualization, camera tracking, robot/food animation, face and speech.
- `godot/scripts/fleet_ui.gd`: title, configuration, ordering and operations controls.
- `blender/delivery_food.blend`: editable sandwich/coffee models; `blender/tools/build_food.py` regenerates them and the two Godot GLBs. The original drone remains in `blender/coast_drone.blend`.

Data defaults to **`~/.causewaybaydrone`**:

| File | Contents |
| --- | --- |
| `config.jsonl` | Append-only, versioned configuration history. One JSON object per changed configuration. |
| `simulator.sqlite3` | Orders, event history and resumable simulation snapshot; SQLite WAL transactions. |

`COAST_DATA_DIR` overrides the data folder for isolated testing. `COAST_BIND` defaults to `127.0.0.1:8799`; `COAST_WS` is the frontend URL override. `COAST_MAP` overrides the map JSON. `COAST_TEST_SPEED` advances multiple fixed steps per interval and is used only by tests/gallery capture. No cloud service or payment is involved.

See [protocol](docs/PROTOCOL.md), [map sources and accuracy](godot/MAP_REFERENCES.md) and [data licensing](godot/data/LICENSE.md).

## Validation and physical scope

`make test` runs Rust unit tests and an isolated Godot → Rust FFI → WebSocket → SQLite integration test. Coverage includes queue ordering, chef preparation, payload pickup, outdoor/window delivery, return, multiple drones, pause/resume, invalid inputs, camera modes, configuration JSONL and database restart recovery. Test data is temporary and separate from the user's data directory.

Flight uses an acceleration-limited point-mass controller (3 m/s²), 12 m/s cruise, 4 m/s approach/climb, terrain/building clearance sampling, staggered altitude lanes, basic inter-drone yielding, 1,000 Wh nominal battery, estimated propulsion power, payload-dependent energy use, low-battery return and charging at home. These parameters are **uncalibrated simulation assumptions**. Map elevations are coarse public data and some building heights are estimated.

This prototype provides reusable order/dispatch states, IDs, events and a transport boundary for further engineering. It does not yet model full aerodynamics, rotor downwash, wind estimation, sensor uncertainty, localization failures, live obstacle perception, closed-window detection, certified separation, real robot manipulation or real aircraft commands. Apartment openings are deliberately sized demonstration fixtures. Hardware deployment requires vehicle/robot adapters, calibrated models and hardware-in-the-loop/field validation; the simulator is not evidence of operational flight safety.

Rendering uses Godot Metal/Mobile, a stylized cloud sky, animated transparent water and reflection probes. Godot 4.7.2 currently reports seven texture RIDs at graphical shutdown; captures complete without shader/runtime errors. Earlier standalone flight/campaign tests remain available under `godot/` as legacy scenarios.

Cafe robots prepare the exact ordered items, pack them for 4 seconds, then send them along a dispatch conveyor for 4 seconds. A docking lift hands the parcel to the waiting drone. PACKING and SHIPPING are persisted stages; pickup is permitted only after dispatch completes.

Default Massive fleet: 8 autonomous drones, 3 robot cafes, 20 customers. Use `make start ARGS="--autonomous --massive"` to start a new Massive scenario; previous runs remain in SQLite. Use `--autonomous` alone to resume the saved fleet. Menu counts remain configurable up to 32 drones.

Multiple shops have independent robot kitchens, queues, dispatch conveyors, and color-coded signs. Select named shops and customers in the order menu. Names are fictional simulation labels, not verified real businesses. Shop/customer limits are 12/200; the default scenario uses 3/20.

The simulator inspector has Operations, Shops/Queues, Customers, and Live Orders views. Telemetry and fulfillment times come from the Rust simulation clock. The scrollable lists expose individual robot work stages, waiting queues, customer delivery locations, and drone speed, battery, and payload.

Language support: English (`en`), Korean (`ko`), Japanese (`ja`), Cantonese in Hong Kong traditional characters (`yue_HK`), simplified Chinese (`zh_CN`), and Czech (`cs`). Choose Language in the menu. The backend appends the selection to `~/.causewaybaydrone/config.jsonl`, and restores it on restart. Config JSONL remains separate from `~/.causewaybaydrone/simulator.sqlite3` (orders, events, runtime state). `COAST_DATA_DIR` is an optional test/isolation override. Existing configs without language default to English. Translations live in `godot/i18n/messages.jsonl`; protocol state/item IDs stay unchanged. Voice announcements use installed system voices matching the selected language; unavailable voices remain silent. Names of shops/customers and map attribution remain proper names.

Sound effects: spatial drone rotors (speed-dependent pitch), robot kitchen machinery, packaging, order notification, pickup and delivery chimes. Menu sound toggle and effects volume persist in config.jsonl as sfx_enabled/sfx_volume, independently of speech. Simulation pause stops machinery; loading a saved run does not replay historical alerts. Burst alerts and one-shot voices are capped. Samples are original, reproducible with `python3 tools/generate_sounds.py`.

Flight physics now runs authoritatively in Rust: 5 kg empty mass plus cargo, 9.81 m/s² gravity, quadratic/linear air drag, 120 N maximum total thrust, 35° commanded tilt limit, 0.12 s motor response and integration substeps of at most 10 ms. A velocity controller guides the force model; Godot interpolates position and thrust-derived pitch/roll. Waypoints no longer snap position or zero velocity. Dock capture stops residual motion only within 0.10 m at less than 0.15 m/s. Waiting/pickup/delivery use active hover control. Flight state persists in SQLite and older snapshots load with default body state. The operations panel shows mass and thrust. This is a simplified translational multirotor model: angular torque dynamics, wind, rotor aerodynamics, and contact/collision response are not yet modeled; mapped clearance routing remains the obstacle-avoidance mechanism.

Guidance rounds open-air climb/cruise/descent corners with quadratic Bézier fillets (up to 8 m radius). The force controller flies through curve samples without stopping; it slows near bends and preserves precise stops for windows and endpoints. Added samples are checked against mapped roof/terrain height with a 6 m allowance; unsafe bends fall back to the original precise waypoints. This is sampled route clearance, not physical collision response. Intermediate and precision waypoint metadata persist in SQLite.

Fleet maintenance: every drone has a dedicated charging/repair dock. Below 90% battery, an idle drone enters CHARGING and is unavailable for dispatch until full. The 1 kWh battery uses a simulated 2 kW charger at 90% efficiency with taper above 90%; this takes simulation time. In-flight wear reduces health by 0.004 percentage points/second. Below 85% health, a returned drone gets 5 seconds of diagnostics, 20 seconds of repair setup, and recovery at 0.5 health points/second. Below 60% health or 20% battery, it returns for service. Menu actions request service or inject a controlled fault (55% health). Interrupted orders remain attached to the returning drone until dock arrival, then the shop prepares the same order again. Completed deliveries are not requeued. Maintenance counters, reasons, timers and events persist in SQLite.

Cooperative drone avoidance projects closest approach up to 4 seconds ahead. Within a predicted 8 m conflict zone, the higher-ID drone yields, slows, moves right and climbs while lower-ID traffic proceeds. This uses the force model and reports AVOIDING TRAFFIC in telemetry. A head-on physics test verifies separation in that scenario; the controller is a simulation heuristic, not a certified collision-avoidance system. Map clearance routing remains separate from inter-drone avoidance.

Game effects use native Godot GPUParticles3D: short rotor downwash, ground dust only below 6 m above mapped surface, charging energy markers, repair-tool sparks after the setup stage, and delivery bursts. These stylized effects are visual indicators, not simulated smoke or air flow. Emitters pause with simulation, stop beyond 70 m, and hide for the selected cockpit view.

Attitude and translation are coupled: pitch/roll evolve through bounded PD control torque (4 Nm), payload-dependent inertia (0.65 + 0.12 × payload kg·m²), angular-rate limits and motor response. Thrust follows the resulting body-up direction; banking therefore reduces its vertical component until the controller compensates. Angular state and motor thrust persist across restart. This remains an engineering approximation: yaw guidance is rate-limited, rather than a complete rotor torque mixer; rotor geometry, drag/inertia coefficients, wind and contact response require validation against the target company's robot hardware. It is not yet a calibrated flight dynamics model.

UI transitions use Godot Tween TRANS_EXPO with EASE_IN_OUT: title-to-simulator crossfade, reversible menu fades, and inspector page fade-out/fade-in. New transitions cancel older tweens; fading-out controls stop accepting input. UI animation remains responsive while simulation is paused.

### Delivery challenges and cinematic camera

Open the menu (M) and choose **RUSH HOUR / 10 MINUTES** after configuring a fleet. The challenge starts the simulation and autonomous customer demand: deliver `min(customers × 2, 8)` orders in 600 simulated seconds for a 1,000-point bonus. Stop pauses the clock; a finished or expired challenge can be started again. Automatic demand remains enabled until switched off in the menu.

Each successful delivery earns 100 + 25 × combo (bonus capped at combo 10), plus 50 for apartment deliveries. Consecutive deliveries within 60 simulation seconds build the combo. Score, best combo, and mission progress survive SQLite restarts; a new fleet configuration starts a fresh score. These are game rewards, not operational performance certifications.

The optional **Director camera** switches between working drones every eight seconds with smooth camera movement. Right-mouse camera input postpones the next automatic cut. Reward text, score counting, and fades use exponential ease-in/out. Challenge controls and feedback support all six languages.

### Simple drone AI

The deterministic Rust brain is in `rust/backend/src/ai.rs`: wait → fly to shop → wait for food → pick up → fly to customer → drop off → return home. Each physics tick evaluates the next action. Transfers require position within 0.35 m of the handoff and speed at most 0.3 m/s continuously for three seconds. An interrupted transfer resets its timer.

Routes climb above terrain and building roofs, checking continuous expanded building footprints, including the apartment window approach. `avoidance.rs` predicts drone conflicts four seconds ahead; the higher-ID aircraft slows and steers aside/up. Safety recovery interrupts work below 20% battery or 60% health, retaining cargo until the dock; unfinished orders are requeued. Idle drones below 90% recharge automatically. `maintenance.rs` applies charging and repairs. All movement still runs through the physics controller.

This is rule-based simulation AI using known map geometry and fleet positions, not onboard perception. Unmapped obstacles, sensor uncertainty, and certified real-world collision avoidance are not modeled.

### Lone Tree and park animals

The dedicated evergreen Lone Tree model uses the existing OSM landmark 3739451104 (37.5227406 N, 127.1203766 E), terrain height, and an approximate 10 m silhouette. Its solitary hill setting follows the [official park description](https://www.ksponco.or.kr/menu.es?mid=a20107010000). Three stylized cats and six rabbits wander, rest, and hop near the tree, following terrain and excluding mapped water/building polygons. These are decorative simulated animals, not a claim about real animal locations or population. They pause with the simulation; their cosmetic movement restarts with the scene.

Menu → Park wildlife → Lone Tree / Watch cats and rabbits opens the corresponding orbit camera. The animals and tree are procedural Godot meshes in `godot/scripts/park_wildlife.gd`.

### Textured terrain and Blender source

Four original 1024×1024 base-color maps were generated using the OpenAI Images API (`gpt-image-2`, high quality): `blender/textures/park-grass.png`, `park-earth.png`, `tree-bark.png`, and `tree-foliage.png`. Exact prompts are preserved in `blender/textures/prompts.jsonl`. They depict mown lawn, compacted sandy trail, fibrous arborvitae bark, and evergreen scale foliage under neutral light. They are illustrative surface materials, not aerial imagery or surveyed terrain.

`blender/olympic_park_environment.blend` packs all four images into materials on the map-derived terrain and tree. It is a build output rather than a source and is not tracked: it embeds the exported dressing mesh, so build it locally with Blender `--background --python blender/tools/build_park_environment.py` (add `-- --rebuild-dressing` to regenerate `godot/assets/park-dressing.glb` too). The tree is exported to `godot/assets/lone-tree.glb`. Every generated image is kept once, in `blender/textures/`; only the three surfaces Godot actually samples are mirrored under `godot/assets/textures`. Godot uses world-space metre-scale repeating textures with mipmapping and broad color variation. Blender uses procedural micro-bump, separate from the generated color images.

Landcover now clips to individual terrain triangles, avoiding large flat polygon faces over hills. Road edges follow the same terrain sampler. `make test` checks terrain/landcover alignment. OSM footprints and map coordinates remain authoritative; the existing Mapzen global DEM is coarse and a 15m mesh does not imply 15m survey accuracy. Higher-fidelity earthworks require a higher-resolution local DEM or LiDAR survey. [Terrain source resolution](https://github.com/tilezen/joerd/blob/master/docs/data-sources.md).

### Architectural and vegetation detail

An earlier realism pass used Godot PhysicalSkyMaterial; the current adventure preset uses a stylized cloud shader, filmic tonemapping and cool ambient fill. Buildings retain their mapped footprints and heights, with metre-scaled estimated window modules, frames, varied glazing and a generated 2048² concrete albedo. The concrete is packed into the Blender authoring scene; `blender/textures/concrete-prompt.txt` records the OpenAI Images API prompt (`gpt-image-2`, high quality). These are generic facade treatments, not measured reproductions of specific buildings.

The Lone Tree uses 1,250 small irregular foliage sprays rather than 150 large blobs. Instanced short lawn tufts around it follow the terrain, avoid mapped paths and blocked water/building areas, and bend in wind. Plant placement is decorative and is not a surveyed vegetation inventory. Minecraft-style characters are retained.

### Codex built-in foliage image

`blender/textures/arborvitae-spray-codex.png` was generated with the Codex built-in image generator, preserving its transparent alpha. Exact prompt: `blender/textures/arborvitae-spray-codex-prompt.txt`. The same image is copied to `godot/assets/textures/arborvitae-spray-codex.png` and packed into the Blender park scene. The tree builder uses 1,250 pairs of crossed foliage cards, replacing the earlier solid foliage clumps. Godot applies alpha scissor transparency for fine silhouettes and opaque depth/shadow handling.

### Toy-brick art direction

The requested art direction is now colorful construction-toy plastic rather than photorealism. `blender/textures/toy-plastic-codex.png` was created with the Codex built-in image generator only, without the user's API key. Its exact prompt is `blender/textures/toy-plastic-codex-prompt.txt`. Godot's `toy_material.gd` tints the texture and sets satin plastic roughness on procedural fleet objects, walkers and wildlife. `blender/toy_materials.blend` contains six color variants and rounded sample bricks; rebuild using `blender/tools/build_toy_materials.py`. This material pass does not yet convert all terrain and imported models into toy-brick geometry.

### Colorful adventure lighting pass

The latest art pass takes its mood from colorful console adventures: painted spring-green lawn, soft cloud shapes, warm sunlight with cool ambient fill, satin architectural surfaces, turquoise shallows and blue lake depths with sparse wave glints. It retains original game assets and the mapped park layout. `adventure-grass-codex.png` was generated using only Codex's built-in image generator; the exact prompt is saved beside it in `blender/textures/adventure-grass-codex-prompt.txt`. Grass textures fade toward filtered color at distance to suppress visible repetition. The current sky is the stylized `park_sky.gdshader`, replacing the previous physical sky preset.

### CB service humanoid

`blender/cb_robot.blend` is an original white/graphite CB robot with teal service lights, rounded shells, finger geometry and independent shoulder pivots. Design reference: [Tesla Optimus](https://www.tesla.com/en_sa/AI); this is a stylized game design, not Tesla hardware or a dynamics model. Its standing height is 1.80 m, verified in Blender and in the imported Godot GLB. The generated CB badge uses only Codex's built-in image generator. Image and exact prompt: `blender/textures/cb-robot-badge-codex.png` and `cb-robot-badge-codex-prompt.txt`. Rebuild with `blender/tools/build_cb_robot.py`. Cafes instantiate `godot/assets/cb-robot.glb` and animate its shoulders during cooking and packing.


## Autonomous field trial — current prototype

The protagonist is **Causewaybay Rust Coder**, the orange-hooded developer inspired by the sibling CausewaybayRaiden project. Press Space on **CAUSEWAYBAY DRONE** to start automatic orders, robot preparation, pickup, delivery and return. `make start ARGS=--autonomous` bypasses the title for unattended observation. Start/stop, fleet counts, orders and first/third-person cameras remain available. The default interface emphasizes delivery telemetry; arcade challenge controls are deferred.

Supporting cast uses original 3D interpretations of CausewaybayGolang: Alex (navy hoodie/backpack), Mei (yellow hoodie/pink clip), and Chef Bo (white chef uniform). Their Blender sources are `blender/alex.blend`, `blender/mei.blend`, and `blender/chef_bo.blend`. The protagonist and rendered title sources are `blender/rust_coder.blend` and `blender/title_field_trial.blend`; reproduce them with the corresponding scripts in `blender/tools/`.

Drone routes and physics steps are constrained to the mapped park polygon with an 8 m inward margin. Only 396 building components within 250 m of the park are rendered. Park scenery includes 180 artist-placed tree groups along mapped paths; these are not surveyed tree locations. World units remain metres. The DEM is coarse global elevation data: a 15 m mesh spacing does **not** establish 15 m source resolution or survey-grade height accuracy. High-resolution surveyed terrain validation remains outstanding.

Configuration remains JSONL and operational state/order history SQLite under `~/.causewaybaydrone`. Existing runs outside the new boundary are archived before a new in-park layout is configured.


Path furnishings are generated by `blender/tools/park_dressing.py` through `build_park_environment.py -- --rebuild-dressing`. Timber benches have slatted seats, backs and armrests; flower borders use shared daisy meshes with colored petals and terrain-following stone edging. The generated `godot/data/park-dressing.json` records the actual counts. These furnishings are artistic additions, not claims of surveyed bench or flowerbed locations.


The September 13 precision pass adds a reproducible geographic audit (`docs/geography-audit.md`), matching Rust/Godot terrain interpolation, and strict missing-elevation-tile errors during rebuild. Supporting characters now have knee/head pivots, distance-driven gait, eased acceleration/stopping, idle motion, blinking and blended receiving gestures. `make nature-gallery` includes a close-up cast pose capture. Real-world survey accuracy remains unverified; the report separates source consistency from independent ground truth.

### Revised controls and presentation

The main bar opens **Orders**, **Fleet**, or **Settings** directly. **Start / Pause** controls simulation time; **Details** reveals the longer telemetry view. The order form and service tools have separate pages. **Horizontal / Vertical mode** switches the window between wide and tall layouts, and controls wrap to fit the available width.

Choose **Free camera [F]** or press **F** to detach from the drone. Use WASD to fly, Q/E to descend/ascend, right-drag to look, Shift for speed, and the wheel to adjust travel speed. Opening the menu stops camera movement. Free-camera travel does not alter the drone geofence or simulation state.

The desktop presentation uses Godot Forward+, ambient occlusion, four shadow cascades and restrained bloom. Codex-generated meadow and limestone textures have mipmaps for stable distant rendering. Their originals are in `blender/textures/`, with packed reusable Blender materials in `blender/codex_surface_library.blend`. These are artistic surface materials; the geographic source remains the existing OSM/Terrarium snapshots. No NGII data or personal OpenAI API key is used.

Follow-drone camera stabilization uses a shared, exponentially filtered anchor for both position and aim, with a world-up horizon. Camera orbit input is filtered separately. Drone telemetry therefore cannot repeatedly rotate the camera through a mismatch between position lag and immediate aiming. Regression checks cover noisy targets and matching damping at 30/120 FPS; first-person and free-flight cameras keep their own behavior.

Drone airframes use a separate 150 ms snapshot playback buffer. Positions interpolate on the sender's simulation timeline, and orientations use shortest-arc quaternion slerp. Packet arrival jitter no longer restarts easing on the model. Physics, collision decisions and delivery state remain authoritative in Rust; the delay applies only to presentation. Playback holds the latest known pose on a network interruption and reanchors after a long gap or pause. Tests exercise 20 Hz updates displayed at 120 FPS, alternating packet delays, heading wraparound and interrupted streams.

Playback continuously corrects sender-clock drift. A recovered stream blends large pose corrections over 300 ms instead of snapping. Network transforms render every frame; dashboard text refreshes at 10 Hz to avoid unnecessary layout work.

Follow mode uses the airframe's already-interpolated presentation position directly, rather than applying a second positional lag to the camera. Orbit input remains smoothed. This keeps the camera and drone on the same timeline and avoids apparent airframe motion caused by double filtering. Position playback uses linear interpolation; rotation playback uses quaternion slerp.

Apartment delivery now ends at the exterior balcony hover point (the legacy JSON field `windows`). The Blender residence is authored in `blender/balcony_house.blend` with oak decking, planters and a clear central handoff opening. Customers start empty-handed; the live drone parcel eases into their hands during unloading, transfers ownership on confirmed delivery, then plays the meal and bin-cleanup sequence before clearing. Historical orders never recreate displayed meals. Shop owners have preparation gestures; customers turn, reach and hold their parcel. Actor animation pauses with the simulation.

The product is a networked robotics prototype presented as a playful simulator game. Rust remains authoritative for orders and robot motion over JSON/WebSocket; idle poses, receipt celebrations, and cinematic camera motion are client presentation. Random Camera cycles through balanced subject categories (animals, customers, cafes, drones, landmarks), plans a raised flight arc over sampled scene geometry, eases in/out exponentially, and smoothly turns toward its subject. Clicking the button again stops the tour; selecting another view or free flight exits it.

The UI uses the CausewaybayGolang CJK font plus a bundled Latin Extended fallback for all six supported languages (Korean, Cantonese, Chinese, English, Japanese, Czech). Press Start 2P titles, VT323 menu/dialogue text, and navy/coin-gold controls follow the CausewaybayGolang retro palette. The Menu button or M opens the adventure menu; Orders, Fleet, Settings, Story, Dashboard and camera controls are grouped there. Arrow keys and Enter navigate the highlighted menu choices. Font origins and licenses are in `godot/assets/fonts/PROVENANCE.md`.

The toolbar's Instant charge button sends `{"command":"instant_charge","drone":index}` through the existing WebSocket transport. Rust sets the selected battery to 100%, exits dock charging, resumes the simulation, and dispatches available orders on the next tick. In-flight orders and poses are preserved; a loaded drone returning only for charge can resume its delivery. This simulator shortcut does not repair damaged components. Normal dock charging is still available.

Dashboard opens a responsive in-game overview with delivered/pending orders, active aircraft, mean battery and fulfillment time, service attention counts, a 12-bin delivery histogram covering the last 60 simulation seconds, per-drone battery bars, cafe queues and the latest 20 orders. It uses the current authoritative WebSocket snapshot, refreshes at 4 Hz only while visible, and clearly labels disconnected data. Fleet rows open the corresponding follow camera. Counts handle empty fleets and exclude failed orders from the pending queue. Lists scroll independently; the layout stacks on narrow displays.

The selected-drone HUD follows the toolbar drone selection, independently of camera mode. It shows the live state, battery, speed, altitude above ground, payload, health and assigned order. Landscape uses a compact upper-right card; portrait uses the available width below the toolbar. It is hidden while menus/dashboard/details are open, updates at 10 Hz, and labels disconnected data explicitly. All text supports the six UI languages.

The orientation toggle displays the current mode (Horizontal or Vertical). Clicking it switches to the other mode. The Operations inspector docks on the right in landscape and across the bottom above the footer in portrait; its scrollable content resizes immediately with the window.

The title screen and Settings include Story: five localized chapters about Rust Con at Seoul Olympic Park, Rust Coder treating participants to Subway sandwiches and Starbucks iced coffee, and good Skynet helping with friendly drones and robot chefs. The story is a separate 3D diorama using the project's Blender models, warm lighting, particle sparkles, animated characters, smooth camera reframing and retro dialogue. Space on the title opens the story. Chapters reveal their dialogue and advance automatically after a localized reading interval; the final chapter launches the simulation. Space or Next dialogue optionally advances sooner. Back/Escape returns without launching. Orientation can change mid-story: portrait increases camera distance and reflows the dialogue panel. The story viewport stops rendering when closed.


Count controls commit typed values when Apply Counts is pressed. The client pauses a running simulation, waits for the server acknowledgment, creates the new configured run, then resumes it. Custom counts select Massive instead of being silently replaced by the Solo preset. Applying starts a new run and resets current orders; the settings page displays this and reports success or connection failure.

The adventure menu includes Camera to rabbit and Camera to lone tree. Selecting either exits random/free/director modes and uses the existing smooth camera tracking.

Customers take short, staggered strolls within 0.85 m of their receiving area. They return and face an approaching assigned drone within 25 m, receive the parcel, celebrate, unwrap food, eat or drink, then take a short step toward their bin and toss the wrapper/cup into it. Meal presentation uses 12 real seconds while running, followed by a 2.8-second cleanup; pausing freezes it. Balcony customers stay within their receiving area. Human idle, gaze, gait and consumption poses are procedural Godot animations on the Blender character rigs; these local presentation states are not authoritative backend task states.

`blender/park_litter_bin.blend` contains the Blender bin and waste models; rebuild with `blender/tools/build_litter_bin.py`. Its packed enamel image is generated by the built-in Codex image generator and copied to `godot/assets/textures/bin-enamel-codex.png`. No user API key is used. The GLB exports are `park-litter-bin.glb`, `meal-wrapper.glb`, and `empty-coffee-cup.glb`.


Frontend display preferences are appended to `~/.causewaybaydrone/frontend.jsonl`, alongside the backend's `config.jsonl` and `simulator.sqlite3`. Records contain schema version, fullscreen/windowed mode, windowed horizontal/vertical orientation, window dimensions, and a UTC save timestamp. The last valid record is restored on startup; malformed/incomplete trailing lines are ignored. Buttons save immediately, manual resizing saves after a 400 ms debounce, and closing the window flushes the latest choice. Fullscreen uses the monitor dimensions; returning to a window restores its saved orientation and size. `COAST_DATA_DIR` overrides the same root for both frontend and backend, including isolated tests.

In third-person drone follow mode, drag with either mouse button to orbit around the drone; the wheel changes distance. Manual orbit disables automatic director changes and retains the existing interpolated drone anchor and smooth camera offset. Menus block orbit input.

Mouse orbit in drone follow mode is a temporary look-around: releasing both buttons returns to the pre-drag yaw/elevation over 1.4 seconds using exponential ease in/out. Re-grabbing during the return continues smoothly and retains the original home view. The return follows the moving drone rather than its old world position.


Story presentation now uses the Blender-authored `story-stage.glb` miniature festival set: cafe canopy, benches, flower borders, pennants and paving, backed by a Codex-generated panoramic sky. Five per-chapter dolly paths move from an establishing view to speaker-focused compositions, then pull back for departure. The dialogue displays autoplay progress; both monitor orientations reframe the shots. The CB robot shoulder parenting evaluates Blender transforms before attaching parts, with Blender and Godot regression checks that the actuator stays at its socket throughout animation. Sources: `blender/story_stage.blend`, `blender/cb_robot.blend`; texture provenance and generation prompt: `blender/STORY_ASSETS.md`.

The opening now uses separate wide and portrait Codex title key art. After the automatic story, a large gold CAUSEWAYBAY DRONE logo fades and scales into the blue-hour park artwork with exponential easing, a slow image pullback and drifting gold particles. The logo holds briefly, fades out, and the scene dissolves into the running simulation. Story dialogue and title prompts use larger type. `story-gallery` captures both orientations and the final title reveal; the Godot integration test waits for the complete automatic story-to-simulation transition.

After the cinematic logo, a five-second camera opening approaches the lone tree (1s), visits the rabbits (1s), rises vertically into the sky (1s), then crosses above the park into live drone follow (2s). Position, flight arc and camera aim share Godot Tween TRANS_EXPO / EASE_IN_OUT interpolation. The route samples actual scene collider heights with camera clearance, sweeps between rendered positions, and carries frame-time remainder across shots. The final safe offset seeds normal drone follow. Gameplay HUD stays hidden during the opening; selecting another camera cancels it. Backend simulation continues throughout.
