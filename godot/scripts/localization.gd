extends RefCounted
const CODES = ["en", "ko", "ja", "yue_HK", "zh_CN", "cs"]
const NAMES = ["English", "한국어", "日本語", "廣東話（香港）", "中文（简体）", "Čeština"]


static func install() -> void:
	var catalogs: Array[Translation] = []
	for code in CODES:
		var catalog := Translation.new()
		catalog.locale = code
		catalogs.append(catalog)
	var file := FileAccess.open("res://i18n/messages.jsonl", FileAccess.READ)
	while not file.eof_reached():
		var line := file.get_line()
		if line.is_empty():
			continue
		var row: Dictionary = JSON.parse_string(line)
		for i in CODES.size():
			catalogs[i].add_message(row.en, row[CODES[i]])
	for catalog in catalogs:
		TranslationServer.add_translation(catalog)
	TranslationServer.set_locale("en")
