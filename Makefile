GODOT ?= /Applications/Godot.app/Contents/MacOS/Godot
PYTHON ?= /usr/bin/python3
.PHONY: help build start stop test format gallery nature-gallery
.DEFAULT_GOAL := help
help:
	@echo "make start   Build and open CAUSEWAYBAY DRONE + Rust backend"
	@echo "make stop    Stop this simulator and save backend state"
	@echo "make test    Rust unit + WebSocket/SQLite + Godot FFI integration tests"
	@echo "make format  Format Rust, GDScript, and Python source"
	@echo "make build   Build Rust libraries and import Godot assets"
	@echo "make nature-gallery  Capture the textured Lone Tree, cats and rabbits"
build:
	cargo build --manifest-path rust/Cargo.toml
	@mkdir -p godot/bin
	cp rust/target/debug/libcoast_frontend.dylib godot/bin/
	"$(GODOT)" --headless --path godot --editor --import --quit
start: build
	$(PYTHON) tools/manage.py start "$(GODOT)" $(ARGS)
stop:
	$(PYTHON) tools/manage.py stop "$(GODOT)"
test: build
	$(PYTHON) tools/check_terrain.py
	cargo test --manifest-path rust/Cargo.toml -p coast-backend
	$(PYTHON) tools/manage.py test "$(GODOT)"
format:
	cargo fmt --manifest-path rust/Cargo.toml --all
	uv tool run --from gdtoolkit==4.5.0 gdformat godot/scripts
	uv tool run --from ruff==0.16.7 ruff format tools blender/tools
gallery: build
	$(PYTHON) tools/manage.py gallery "$(GODOT)"

nature-gallery: build
	$(PYTHON) tools/manage.py nature-gallery "$(GODOT)"
