@tool
class_name SpatialFabricRoutingPolicy
extends RefCounted
## Pure authoring API; no loading, device enumeration, playback, networking or mutation.
## snapshot(cue) copies authored properties and node_path (cue path in CSV).
## validate(row) returns Array[String]; empty source/device mean unassigned/default.
## export_csv(rows) returns "" on ANY invalid row or bound violation (no partial export).
## import_csv(text, legacy_candidates = []) returns {rows, errors}. Errors are
## {row: int, severity: String, message: String}; row 1 is the header, and subsequent
## indexes count logical CSV records, including quoted multiline records.
## Native rows are complete replacements. Only validated rows are returned, never applied.
## Lexical CSV corruption rejects the document; semantic row errors skip only that row.
## Bounds: 1 MiB UTF-8 CSV, 4096 data records, 4096 characters per field.
## Plugin must resolve node_path, check conflicts/capabilities, then use UndoRedo itself.
## Optional legacy_candidates are snapshots with an extra device_label string. Legacy
## SoundWave's object basename matches source_path's file basename, case-insensitively;
## nonempty DeviceId must match an already authored exact native ID or an explicitly
## inventoried device_label. It is never copied blindly into the native route.
## Exactly one candidate must match. Unreal identity/derived OSC columns are reported
## as unmapped, not guessed as Godot paths. Unsupported runtime fields remain authored
## data only; the plugin must feature-gate application (not silently discard them).

const COLUMNS := ["node_path", "source_path", "device_id", "output_channel", "exclusive", "buffer_ms", "osc_base", "loop", "auto_replay", "replay_delay_seconds", "random_replay_delay", "replay_delay_min", "replay_delay_max", "play_on_start"]
const LEGACY_COLUMNS := ["ActorName", "ActorLabel", "ComponentName", "ComponentIndex", "SoundWave", "DeviceId", "OutputChannel", "OscAddress", "OscBase", "OscPlay", "OscStop", "OscLoop", "OscState"]
const BOOL_FIELDS := ["exclusive", "loop", "auto_replay", "random_replay_delay", "play_on_start"]
const INT_FIELDS := ["output_channel", "buffer_ms"]
const FLOAT_FIELDS := ["replay_delay_seconds", "replay_delay_min", "replay_delay_max"]
const MAX_BYTES := 1048576
const MAX_ROWS := 4096
const MAX_FIELD := 4096

static func _defaults() -> Dictionary:
	return {"node_path": "", "source_path": "", "device_id": "", "output_channel": 0, "exclusive": false, "buffer_ms": 20, "osc_base": "", "loop": false, "auto_replay": false, "replay_delay_seconds": 2.5, "random_replay_delay": false, "replay_delay_min": 0.0, "replay_delay_max": 0.0, "play_on_start": false}

static func snapshot(cue: Node) -> Dictionary:
	var row := _defaults()
	if not is_instance_valid(cue):
		return row
	row.node_path = str(cue.get_path()) if cue.is_inside_tree() else str(cue.name)
	for property in cue.get_property_list():
		var key := str(property.name)
		if key in COLUMNS and key != "node_path":
			row[key] = cue.get(key)
	return row

static func validate(row: Dictionary) -> Array[String]:
	var errors: Array[String] = []
	for key in COLUMNS:
		if not row.has(key):
			errors.append("Missing field: " + key)
			continue
		var value: Variant = row[key]
		if key in BOOL_FIELDS:
			if not value is bool:
				errors.append(key + " must be a boolean")
		elif key in INT_FIELDS:
			if not value is int:
				errors.append(key + " must be an integer")
			elif (key == "output_channel" and (value < 0 or value > 2147483647)) or (key == "buffer_ms" and (value < 5 or value > 500)):
				errors.append(key + " is out of range")
		elif key in FLOAT_FIELDS:
			if not (value is float or value is int):
				errors.append(key + " must be a number")
			elif not is_finite(float(value)) or value < 0:
				errors.append(key + " must be finite and nonnegative seconds")
		elif not value is String:
			errors.append(key + " must be a string")
		elif value.length() > MAX_FIELD:
			errors.append(key + " exceeds the field bound")
		elif key == "node_path" and (value.strip_edges().is_empty() or NodePath(value).get_subname_count() != 0):
			errors.append("node_path must identify a cue node, not a property")
		elif key == "source_path" and not value.is_empty() and value.get_extension().to_lower() != "wav":
			errors.append("source_path must be empty or a WAV file path")
		elif key == "osc_base" and not value.is_empty() and not _valid_osc(value):
			errors.append("osc_base must be blank (derived) or a literal absolute OSC path without trailing slash")
	if errors.is_empty() and row.replay_delay_min > row.replay_delay_max:
		errors.append("replay_delay_min must not exceed replay_delay_max")
	return errors

static func _valid_osc(value: String) -> bool:
	if not value.begins_with("/") or value.ends_with("/") or value.contains("//"):
		return false
	for character in value:
		if character.unicode_at(0) <= 32 or character in ["#", "*", ",", "?", "[", "]", "{", "}"]:
			return false
	return true

static func _quote(value: String) -> String:
	if value.contains(",") or value.contains("\"") or value.contains("\n") or value.contains("\r"):
		return "\"" + value.replace("\"", "\"\"") + "\""
	return value

static func export_csv(rows: Array) -> String:
	if rows.size() > MAX_ROWS:
		return ""
	var lines := PackedStringArray([",".join(COLUMNS)])
	var bytes := lines[0].to_utf8_buffer().size() + 1
	for row in rows:
		if not row is Dictionary or not validate(row).is_empty():
			return ""
		var fields := PackedStringArray()
		for key in COLUMNS:
			fields.append(_quote(str(row[key])))
		var line := ",".join(fields)
		bytes += line.to_utf8_buffer().size() + 1
		if bytes > MAX_BYTES:
			return ""
		lines.append(line)
	return "\n".join(lines) + "\n"

static func _issue(errors: Array, index: int, message: String, severity: String = "error") -> void:
	errors.append({"row": index, "severity": severity, "message": message})

## Strict bounded parser: line splitting cannot handle multiline records, and native
## FileAccess CSV helpers require I/O. This state machine deliberately does neither.
static func _parse(text: String) -> Dictionary:
	var records: Array = []
	var fields: Array[String] = []
	var field := ""
	var state := 0 # 0 unquoted, 1 quoted, 2 closed quote
	var i := 0
	while i < text.length():
		var c := text[i]
		if state == 1:
			if c == "\"":
				if i + 1 < text.length() and text[i + 1] == "\"":
					field += "\""
					i += 1
				else:
					state = 2
			else:
				field += c
		elif c == "," or c == "\n" or c == "\r":
			fields.append(field)
			field = ""
			state = 0
			if fields.size() > COLUMNS.size():
				return {"error": "Too many columns", "row": records.size() + 1}
			if c != ",":
				records.append(fields)
				fields = []
				if records.size() > MAX_ROWS + 1:
					return {"error": "Too many rows", "row": records.size()}
				if c == "\r" and i + 1 < text.length() and text[i + 1] == "\n":
					i += 1
		elif c == "\"" and field.is_empty() and state == 0:
			state = 1
		elif state == 2 or c == "\"":
			return {"error": "Malformed CSV quoting", "row": records.size() + 1}
		else:
			field += c
		if field.length() > MAX_FIELD:
			return {"error": "Field exceeds bound", "row": records.size() + 1}
		i += 1
	if state == 1:
		return {"error": "Unterminated quoted field", "row": records.size() + 1}
	if not fields.is_empty() or not field.is_empty() or state == 2:
		fields.append(field)
		records.append(fields)
	if records.size() > MAX_ROWS + 1:
		return {"error": "Too many rows", "row": records.size()}
	return {"records": records}

static func import_csv(text: String, legacy_candidates: Array = []) -> Dictionary:
	var result := {"rows": [], "errors": []}
	if text.length() > MAX_BYTES or text.to_utf8_buffer().size() > MAX_BYTES:
		_issue(result.errors, 1, "CSV exceeds byte bound")
		return result
	var parsed := _parse(text.trim_prefix(String.chr(0xfeff)))
	if parsed.has("error"):
		_issue(result.errors, parsed.row, parsed.error)
		return result
	var records: Array = parsed.records
	if records.is_empty():
		_issue(result.errors, 1, "Missing CSV header")
		return result
	var header: Array = records[0]
	var legacy: bool = header == LEGACY_COLUMNS
	if not legacy and header != COLUMNS:
		_issue(result.errors, 1, "Expected complete native or exact 13-column AudioLoom header")
		return result
	for index in range(1, records.size()):
		var fields: Array = records[index]
		if fields == [""]:
			continue
		if fields.size() != header.size():
			_issue(result.errors, index + 1, "Expected %d columns, got %d; entire row skipped" % [header.size(), fields.size()])
			continue
		var row: Dictionary = {}
		for column in header.size():
			row[header[column]] = fields[column]
		if legacy:
			row = _legacy(row, legacy_candidates, result.errors, index + 1)
			if row.is_empty():
				continue
		else:
			var conversion_errors: Array[String] = []
			for key in BOOL_FIELDS:
				if row[key] not in ["true", "false"]:
					conversion_errors.append(key + " must be true or false")
				row[key] = row[key] == "true"
			for key in INT_FIELDS:
				if not row[key].is_valid_int():
					conversion_errors.append(key + " must be an integer")
				row[key] = row[key].to_int()
			for key in FLOAT_FIELDS:
				if not row[key].is_valid_float():
					conversion_errors.append(key + " must be a finite number")
				row[key] = row[key].to_float()
			if not conversion_errors.is_empty():
				for message in conversion_errors:
					_issue(result.errors, index + 1, message)
				continue
		var problems := validate(row)
		for message in problems:
			_issue(result.errors, index + 1, message)
		if problems.is_empty():
			result.rows.append(row)
	return result

static func _legacy(old: Dictionary, candidates: Array, errors: Array, index: int) -> Dictionary:
	# Unreal /Game/Folder/Asset.Asset -> Asset; do not pretend it is a WAV path.
	var basename: String = old.SoundWave.replace("\\", "/").get_file().get_slice(".", 0).to_lower()
	var matches: Array = []
	for candidate in candidates:
		if not candidate is Dictionary or not validate(candidate).is_empty():
			continue
		var source_matches: bool = (basename.is_empty() and candidate.source_path.is_empty()) or (not basename.is_empty() and candidate.source_path.get_file().get_basename().to_lower() == basename)
		var device_matches: bool = (old.DeviceId.is_empty() and candidate.device_id.is_empty()) or (not old.DeviceId.is_empty() and (candidate.device_id == old.DeviceId or candidate.get("device_label", "") == old.DeviceId))
		if source_matches and device_matches:
			matches.append(candidate)
	if matches.size() != 1:
		_issue(errors, index, "Unmapped legacy SoundWave '%s' (source basename '%s') / DeviceId '%s' (known ID/device label): expected one candidate, got %d; entire row skipped" % [old.SoundWave, basename, old.DeviceId, matches.size()])
		return {}
	if not old.OutputChannel.is_valid_int() or not old.ComponentIndex.is_valid_int() or old.ComponentIndex.to_int() < 0 or old.ActorName.is_empty():
		_issue(errors, index, "Invalid legacy identity/channel; entire row skipped")
		return {}
	var row: Dictionary = matches[0].duplicate(true)
	row.output_channel = old.OutputChannel.to_int()
	row.osc_base = old.OscAddress if not old.OscAddress.is_empty() else old.OscBase
	_issue(errors, index, "Unmapped legacy fields: ActorName, ActorLabel, ComponentName, ComponentIndex (Unreal identity), OscPlay, OscStop, OscLoop, OscState (derived endpoints). Non-CSV settings retained from candidate; SoundWave/DeviceId resolved by source basename/known ID or device label.", "warning")
	return row
