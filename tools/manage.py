"""Lifecycle and isolated end-to-end test runner; application state lives in Rust."""

import json, os, signal, socket, subprocess, sys, tempfile, time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
BUILD = ROOT / "build"
BUILD.mkdir(exist_ok=True)
BACKEND = ROOT / "rust/target/debug/coast-backend"
GODOT = (
    sys.argv[2] if len(sys.argv) > 2 else "/Applications/Godot.app/Contents/MacOS/Godot"
)
PIDFILE = BUILD / "processes.json"


def launch(command, log, env=None):
    with (BUILD / log).open("w") as f:
        return subprocess.Popen(
            command,
            cwd=ROOT,
            env=env,
            stdout=f,
            stderr=subprocess.STDOUT,
            start_new_session=True,
        )


def stop_pid(pid):
    result = subprocess.run(
        ["ps", "-p", str(pid), "-o", "command="], capture_output=True, text=True
    )
    cmd = result.stdout.strip()
    if (
        str(BACKEND) in cmd
        or os.path.normpath(cmd) == str(BACKEND)
        or (GODOT in cmd and "--path" in cmd and str(ROOT / "godot") in cmd)
    ):
        os.kill(
            pid,
            signal.SIGINT
            if (str(BACKEND) in cmd or os.path.normpath(cmd) == str(BACKEND))
            else signal.SIGTERM,
        )
        for _ in range(30):
            try:
                os.kill(pid, 0)
            except ProcessLookupError:
                return
            time.sleep(0.1)


def stop():
    if PIDFILE.exists():
        for pid in json.loads(PIDFILE.read_text()):
            stop_pid(pid)
        PIDFILE.unlink()
    # Also recognize the exact backend launched by Godot's auto-connect fallback.
    result = subprocess.run(
        ["ps", "-axo", "pid=,command="], capture_output=True, text=True
    )
    for line in result.stdout.splitlines():
        fields = line.strip().split(None, 1)
        if len(fields) == 2 and os.path.normpath(fields[1]) == str(BACKEND):
            stop_pid(int(fields[0]))
    print("Simulator stopped; SQLite state retained.")


if sys.argv[1] == "start":
    stop()
    backend = launch([str(BACKEND)], "backend.log")
    time.sleep(0.5)
    if backend.poll() is not None:
        raise SystemExit((BUILD / "backend.log").read_text())
    frontend = launch(
        [GODOT, "--path", str(ROOT / "godot")]
        + (["--"] + sys.argv[3:] if len(sys.argv) > 3 else []),
        "frontend.log",
        dict(os.environ, COAST_WS=os.environ.get("COAST_WS", "ws://127.0.0.1:8799")),
    )
    PIDFILE.write_text(json.dumps([backend.pid, frontend.pid]))
    print("Started. Data: ~/.causewaybaydrone; logs: build/")
elif sys.argv[1] == "stop":
    stop()
elif sys.argv[1] in (
    "test",
    "gallery",
    "nature-gallery",
    "operations-gallery",
    "story-gallery",
):
    visual = sys.argv[1] != "test"
    with tempfile.TemporaryDirectory(prefix="coast-integration-") as directory:
        with socket.socket() as s:
            s.bind(("127.0.0.1", 0))
            port = s.getsockname()[1]
        env = dict(
            os.environ,
            COAST_DATA_DIR=directory,
            COAST_BIND=f"127.0.0.1:{port}",
            COAST_WS=f"ws://127.0.0.1:{port}",
            COAST_TEST_SPEED="8" if visual else "40",
        )
        backend = launch(
            [str(BACKEND), "--test-instance"], "integration-backend.log", env
        )
        try:
            time.sleep(0.4)
            try:
                result = subprocess.run(
                    [GODOT]
                    + (["--headless"] if sys.argv[1] == "test" else [])
                    + [
                        "--path",
                        str(ROOT / "godot"),
                        "--",
                        "--fleet-test" if sys.argv[1] == "test" else "--fleet-gallery",
                    ]
                    + (["--nature-only"] if sys.argv[1] == "nature-gallery" else [])
                    + (
                        ["--operations-only"]
                        if sys.argv[1] == "operations-gallery"
                        else []
                    )
                    + (["--story-only"] if sys.argv[1] == "story-gallery" else []),
                    cwd=ROOT,
                    env=env,
                    capture_output=True,
                    text=True,
                    timeout=100,
                )
            except subprocess.TimeoutExpired as e:
                (BUILD / "integration-godot.log").write_bytes(
                    (e.stdout or b"") + (e.stderr or b"")
                )
                raise
            (BUILD / "integration-godot.log").write_text(result.stdout + result.stderr)
            print(result.stdout)
            print(result.stderr)
            if (
                result.returncode
                or "SCRIPT ERROR:" in result.stdout + result.stderr
                or "ERROR:" in result.stdout + result.stderr
                or (
                    "GODOT_FLEET_TEST_OK"
                    if sys.argv[1] == "test"
                    else "FLEET_GALLERY_OK"
                )
                not in result.stdout
            ):
                raise SystemExit(
                    "Godot integration failed; see build/integration-godot.log"
                )
        finally:
            backend.send_signal(signal.SIGINT)
            backend.wait(timeout=10)
        if visual:
            raise SystemExit(0)
        import sqlite3

        db = sqlite3.connect(Path(directory) / "simulator.sqlite3")
        rows = db.execute("select status from orders").fetchall()
        assert len(rows) >= 4 and all(row == ("DELIVERED",) for row in rows), rows
        events = [r[0] for r in db.execute("select kind from events")]
        for kind in [
            "COOKING_STARTED",
            "PACKING_STARTED",
            "SHIPPING_STARTED",
            "FOOD_READY",
            "HANDOFF_STARTED",
            "PICKED_UP",
            "DELIVERED",
            "DRONE_RETURNED",
        ]:
            assert events.count(kind) == len(rows), (kind, events)
        for kind in [
            "FAULT_DETECTED",
            "DIAGNOSTICS_STARTED",
            "REPAIR_STARTED",
            "REPAIR_COMPLETED",
            "CHARGING_STARTED",
            "CHARGING_COMPLETED",
        ]:
            assert kind in events, kind
        config = [
            json.loads(line)
            for line in (Path(directory) / "config.jsonl").read_text().splitlines()
        ]
        assert {"en", "ko", "ja", "yue_HK", "zh_CN", "cs"}.issubset(
            {r["config"].get("language") for r in config}
        )
        assert any(
            not r["config"].get("sfx_enabled", True)
            and r["config"].get("sfx_volume") == 0.25
            for r in config
        )
        assert config[-1]["config"]["drones"] == 2
        assert any(
            r["config"]["drones"] == 2 and r["config"].get("auto_orders")
            for r in config
        )
        assert not config[-1]["config"]["auto_orders"]
        saved = json.loads(db.execute("select payload from simulation").fetchone()[0])
        assert saved["arcade"]["score"] > 0
        assert saved["arcade"]["challenge"] is not None
        assert "CHALLENGE_STARTED" in events
        # Start a second backend process against the same SQLite state to verify recovery.
        backend = launch(
            [str(BACKEND), "--test-instance"], "integration-restart.log", env
        )
        time.sleep(0.4)
        backend.send_signal(signal.SIGINT)
        backend.wait(timeout=10)
        state = json.loads(db.execute("select payload from simulation").fetchone()[0])
        assert not state["running"]
        # JSON round trips can differ by one ULP in floating simulation times.
        # Scores, counters and statuses must still match exactly.
        import math

        previous_arcade = saved["arcade"].copy()
        restored_arcade = state["arcade"].copy()
        for record in [previous_arcade, restored_arcade]:
            record["challenge"] = record["challenge"].copy()
        assert math.isclose(
            previous_arcade.pop("last_delivery"),
            restored_arcade.pop("last_delivery"),
            rel_tol=0.0,
            abs_tol=1e-9,
        )
        assert math.isclose(
            previous_arcade["challenge"].pop("deadline"),
            restored_arcade["challenge"].pop("deadline"),
            rel_tol=0.0,
            abs_tol=1e-9,
        )
        assert restored_arcade == previous_arcade
        assert all(o["state"] == "DELIVERED" for o in state["orders"])
        db.close()
        print(
            "SQLITE_JSONL_INTEGRATION_OK: events, orders, config history, restart recovery"
        )
else:
    raise SystemExit("Use start, stop, or test")
