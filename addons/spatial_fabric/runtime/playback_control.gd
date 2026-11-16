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
