@tool
extends RefCounted
## Inventory history only; never contains scene objects or performs native operations.
const MAX_DEVICES := 256
const MAX_CHANNELS := 4096
const MAX_BYTES := 2097152
var devices: Array = []
var last_error := "Not refreshed this session."
var path := ""

static func valid_text(value: Variant, required := false) -> bool:
	if not value is String or value.length() > 1024 or (required and value.is_empty()):
		return false
	for code in value.length():
		var character: int = value.unicode_at(code)
		if character < 32 or (character >= 127 and character <= 159):
			return false
	return true

static func whole(value: Variant, low: int, high: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value == floor(value) and value >= low and value <= high

static func valid(entry: Variant) -> bool:
	return entry is Dictionary and valid_text(entry.get("id"), true) and valid_text(entry.get("name")) and whole(entry.get("channels"), 1, MAX_CHANNELS) and whole(entry.get("sample_rate"), 0, 768000) and valid_text(entry.get("last_seen", ""))

func load_history(file_path: String) -> void:
	path = file_path
	devices.clear()
	if not FileAccess.file_exists(path):
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		last_error = "Cache ignored: unreadable or oversized."
		return
	var document: Variant = JSON.parse_string(file.get_as_text())
	if not document is Dictionary or document.get("version") != 1 or not document.get("devices") is Array or document.devices.size() > MAX_DEVICES:
		last_error = "Cache ignored: invalid schema."
		return
	var ids := {}
	for entry in document.devices:
		if not valid(entry) or not valid_text(entry.get("last_seen"), true) or ids.has(entry.id):
			last_error = "Cache ignored: invalid entry."
			return
		ids[entry.id] = true
	for entry in document.devices:
		devices.append({"id": entry.id, "name": entry.name, "channels": int(entry.channels), "sample_rate": int(entry.sample_rate), "last_seen": entry.last_seen, "online": false})

func accept(result: Dictionary) -> bool:
	for entry in devices:
		entry.online = false
	last_error = "Interface refresh failed; history retained."
	if result.get("ok") != true or not str(result.get("error", "")).is_empty() or not result.get("json") is String or result.json.to_utf8_buffer().size() > MAX_BYTES:
		return false
	# Godot's SFNativePlayer.devices_json returns {ok,json,error}; JSON is the
	# native endpoint ARRAY, with channels/sample_rate (not Unity managed fields).
	var inventory: Variant = JSON.parse_string(result.json)
	if not inventory is Array or inventory.size() > MAX_DEVICES:
		return false
	var merged: Array = []
	var ids := {}
	var seen := Time.get_datetime_string_from_system(true) + "Z"
	for entry in inventory:
		if not valid(entry) or ids.has(entry.id):
			return false
		ids[entry.id] = true
		merged.append({"id": entry.id, "name": entry.name, "channels": int(entry.channels), "sample_rate": int(entry.sample_rate), "last_seen": seen, "online": true})
	for entry in devices:
		if not ids.has(entry.id):
			merged.append(entry.duplicate())
	if merged.size() > MAX_DEVICES:
		return false
	var persisted := merged.duplicate(true)
	for entry in persisted:
		entry.erase("online")
	var text := JSON.stringify({"version": 1, "devices": persisted})
	if text.to_utf8_buffer().size() > MAX_BYTES or path.is_empty():
		return false
	var file := FileAccess.open(path + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(text)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(path + ".tmp", path) != OK:
		last_error = "Could not persist interface history."
		return false
	devices = merged
	last_error = ""
	return true
