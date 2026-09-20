extends RefCounted


static func data_directory() -> String:
	var override := OS.get_environment("COAST_DATA_DIR")
	if not override.is_empty():
		return override
	var home := OS.get_environment("HOME")
	if home.is_empty():
		home = OS.get_environment("USERPROFILE")
	return home.path_join(".causewaybaydrone")


static func valid(value: Variant) -> bool:
	if not value is Dictionary or value.get("schema", 0) != 1:
		return false
	if value.get("window_mode", "") not in ["fullscreen", "windowed"]:
		return false
	if value.get("orientation", "") not in ["vertical", "horizontal"]:
		return false
	var dimensions: Variant = value.get("window_size")
	if not dimensions is Array or dimensions.size() != 2:
		return false
	for dimension in dimensions:
		if not (dimension is int or dimension is float):
			return false
		if (
			not is_finite(float(dimension))
			or dimension < 320
			or dimension > 16384
			or float(dimension) != floorf(float(dimension))
		):
			return false
	return (dimensions[0] < dimensions[1]) == (value.orientation == "vertical")


static func read_latest(directory := "") -> Dictionary:
	var root := data_directory() if directory.is_empty() else directory
	var file := FileAccess.open(root.path_join("frontend.jsonl"), FileAccess.READ)
	var latest := {}
	if file:
		while not file.eof_reached():
			var parser := JSON.new()
			if parser.parse(file.get_line()) == OK and valid(parser.data):
				latest = parser.data
				latest["schema"] = 1
				latest["window_size"] = [int(latest.window_size[0]), int(latest.window_size[1])]
	return latest


static func append(value: Dictionary, directory := "") -> Error:
	if not valid(value):
		return ERR_INVALID_DATA
	var root := data_directory() if directory.is_empty() else directory
	var result := DirAccess.make_dir_recursive_absolute(root)
	if result != OK:
		return result
	var path := root.path_join("frontend.jsonl")
	var file := FileAccess.open(
		path, FileAccess.READ_WRITE if FileAccess.file_exists(path) else FileAccess.WRITE
	)
	if not file:
		return FileAccess.get_open_error()
	file.seek_end()
	# Separate any interrupted final record before appending a complete snapshot.
	if file.get_position() > 0:
		file.store_string("\n")
	var record := value.duplicate(true)
	record["saved_at"] = Time.get_datetime_string_from_system(true)
	file.store_line(JSON.stringify(record))
	file.flush()
	return file.get_error()
