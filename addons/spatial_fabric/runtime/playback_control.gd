@tool
class_name SpatialFabricPlaybackControl
extends RefCounted
## AudioLoom-compatible trigger semantics. The first float anywhere precedes the first int.

static func _numeric(args: Array) -> Variant:
	for arg in args:
		if typeof(arg) == TYPE_FLOAT:
			return arg
	for arg in args:
		if typeof(arg) == TYPE_INT:
			return arg
	return null

## true => start. Address-only starts; nonnumeric payloads never start.
static func should_play(args: Array) -> bool:
	if args.is_empty():
		return true
	var value: Variant = _numeric(args)
	if value == null:
		return false
	return value >= 0.5 if typeof(value) == TYPE_FLOAT else value >= 1

## Returns true/false to set looping, or null to ignore. Float enables only above 0.5.
static func loop_value(args: Array) -> Variant:
	if args.is_empty():
		return false
	var value: Variant = _numeric(args)
	if value == null:
		return null
	return value > 0.5 if typeof(value) == TYPE_FLOAT else value >= 1

## Live-input gain: first float anywhere, else first int; finite 0..4. Invalid returns null.
static func gain_value(args: Array) -> Variant:
	var value: Variant = _numeric(args)
	if value == null:
		return null
	var level := float(value)
	return level if is_finite(level) and level >= 0.0 and level <= 4.0 else null

## Pure command classification; "received" means dispatch an action, not observed playback.
static func decision(kind: String, command: String, args: Array) -> Dictionary:
	match command:
		"play":
			if not should_play(args):
				return {"result": "ignored", "detail": "play payload does not trigger"}
		"stop":
			pass # Payload is intentionally ignored for stop.
		"loop":
			if kind != "playback":
				return {"result": "rejected", "detail": "loop does not apply to live input"}
			if loop_value(args) == null:
				return {"result": "ignored", "detail": "non-numeric payload"}
		"gain":
			if kind != "live":
				return {"result": "rejected", "detail": "gain does not apply to playback"}
			if gain_value(args) == null:
				return {"result": "rejected", "detail": "gain must be numeric 0..4"}
		"status":
			if not args.is_empty():
				return {"result": "rejected", "detail": "status takes no arguments"}
		"ack", "state":
			return {"result": "ignored", "detail": "engine-only message"}
		_:
			return {"result": "rejected", "detail": "unknown command"}
	return {"result": "received", "detail": ""}

static func safe_command(command: String) -> String:
	var clean := ""
	for character in command.left(32):
		clean += character if character.unicode_at(0) >= 33 and character.unicode_at(0) <= 126 else "_"
	return clean
