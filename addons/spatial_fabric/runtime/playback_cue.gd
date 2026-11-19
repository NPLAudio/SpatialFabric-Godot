@tool
class_name SpatialFabricPlaybackCue
extends Node3D
## Direct-device cue. Inventory is explicit; playback is explicit or opt-in runtime startup.
## There is no AudioStreamPlayer/mixer fallback: without the native extension everything fails closed.
## Playing is only what the native worker has OBSERVABLY started, never a request acknowledgement.

signal state_changed(playing: bool)
signal start_failed(detail: String)

@export var persistent_key: String = ""
## Blank derives a unique hierarchy address; serialized explicit paths are never rewritten.
@export var osc_base: String = ""
@export_file("*.wav") var source_path: String = ""
@export_range(0, 2147483647) var output_channel: int = 0
@export var device_id: String = ""
@export var exclusive: bool = false
@export_range(5, 500) var buffer_ms: int = 20
@export var loop: bool = false
@export var auto_replay: bool = false
@export_range(0.0, 3600.0, 0.01, "or_greater") var replay_delay_seconds: float = 2.5
@export var random_replay_delay: bool = false
@export_range(0.0, 3600.0, 0.01, "or_greater") var replay_delay_min: float = 0.0
@export_range(0.0, 3600.0, 0.01, "or_greater") var replay_delay_max: float = 2.5
## Only actual runtime _ready, never editor inspection/discovery.
@export var play_on_start: bool = false
var output_latency_ms: float = -1.0
var output_mode: int = 0
var last_error: String = ""
var last_device_json: String = ""
var _buffer: Object
var _prepared_path := ""
var _player: Object
var _playing := false
var _replay_remaining := -1.0
var _seen_start := 0
var _seen_end := 0
var _start_pending := false
var _active_route: Array = []
var _active_loop := false

func effective_osc_base() -> String:
	return osc_base if not osc_base.is_empty() else derived_osc_base(self, "playback")

static func derived_osc_base(node: Node, kind: String) -> String:
	# Hex is injective for UTF-8 (unlike replacing punctuation with underscores).
	var parts := PackedStringArray()
	var cursor := node
	var scope: Node
	# Ignore editor viewport/dock ancestors: the same scene must derive the same
	# addresses in editor and game. Outer authored scene retains nested-instance uniqueness.
	while cursor != null and not cursor is Window:
		if not cursor.scene_file_path.is_empty():
			scope = cursor
		cursor = cursor.get_parent()
	if node.is_inside_tree() and node.get_tree().edited_scene_root != null:
		var edited := node.get_tree().edited_scene_root
		if edited == node or edited.is_ancestor_of(node):
			scope = edited
	cursor = node
	while cursor != null and not cursor is Window:
		parts.insert(0, str(cursor.name).to_utf8_buffer().hex_encode())
		if cursor == scope:
			break
		cursor = cursor.get_parent()
	return "/godot/" + kind + "/" + "/".join(parts)

func _ready() -> void:
	if not Engine.is_editor_hint() and play_on_start:
		try_play()

func _exit_tree() -> void:
	stop()

func _route() -> Array:
	return [source_path, device_id, output_channel, exclusive, buffer_ms]

func choose_replay_delay() -> float:
	if random_replay_delay:
		if not is_finite(replay_delay_min) or not is_finite(replay_delay_max):
			return -1.0
		var low := maxf(replay_delay_min, 0.0)
		var high := maxf(replay_delay_max, 0.0)
		return randf_range(minf(low, high), maxf(low, high))
	return maxf(replay_delay_seconds, 0.0) if is_finite(replay_delay_seconds) else -1.0

static func native_available() -> bool:
	return ClassDB.class_exists("SFNativePlayer") and ClassDB.class_exists("SFNativeBuffer")

func is_playing() -> bool:
	return _playing

func is_prepared() -> bool:
	return _buffer != null and _buffer.is_valid()

func replay_pending() -> bool:
	return _replay_remaining >= 0.0

## Decodes and copies PCM into immutable native memory. Never opens a device.
func prepare_source() -> Error:
	if Engine.is_editor_hint():
		return ERR_UNAVAILABLE
	if not native_available():
		last_error = "Native direct-device extension is not loaded; no source was prepared."
		return ERR_UNAVAILABLE
	if _playing or replay_pending():
		last_error = "Stop playback before preparing another source."
		return ERR_BUSY
	var decoded := SpatialFabricWav.load_file(source_path)
	if not decoded.ok:
		last_error = decoded.error
		return ERR_FILE_CORRUPT
	var candidate: Object = ClassDB.instantiate("SFNativeBuffer")
	if not candidate.create(decoded.samples, decoded.channels, decoded.rate):
		last_error = candidate.get_error()
		return ERR_INVALID_DATA
	_buffer = candidate
	_prepared_path = source_path
	last_error = ""
	return OK

## Explicit inventory (does not open a stream). Result JSON is kept in last_device_json.
func refresh_devices() -> Error:
	if not native_available():
		last_error = "Native direct-device extension is not loaded."
		return ERR_UNAVAILABLE
	var probe: Object = ClassDB.instantiate("SFNativePlayer")
	var result: Dictionary = probe.devices_json()
	if not result.ok:
		last_error = result.error
		return FAILED
	last_device_json = result.json
	last_error = ""
	return OK

## Submits a start REQUEST. is_playing() becomes true only after the worker reports it started.
func try_play() -> bool:
	if Engine.is_editor_hint():
		last_error = "Playback is disabled in editor authoring."
		return false
	poll_status()
	# Consume the old worker BEFORE decoding a changed source, including pending starts.
	stop()
	_active_route = _route()
	_active_loop = loop
	# Play is itself an explicit action (E key, OSC /play, API call), so it prepares the configured source on demand.
	# Preparation decodes and copies PCM only; it never opens a device. A changed source_path is re-prepared.
	if not is_prepared() or _prepared_path != source_path:
		if source_path.is_empty():
			last_error = "No source_path is set; there is nothing to play."
			return false
		if prepare_source() != OK:
			return false
	if _player == null:
		_player = ClassDB.instantiate("SFNativePlayer")
	if _player.start(_buffer, device_id, output_channel, exclusive, buffer_ms, loop) == 0:
		observe(_player.status())
		if last_error.is_empty():
			last_error = "Native player refused the start request."
		return false
	_start_pending = true
	last_error = ""
	return true

func set_loop(enabled: bool) -> void:
	loop = enabled
	if _player != null:
		_player.set_loop(enabled)
	if enabled:
		_replay_remaining = -1.0

func stop() -> void:
	_start_pending = false
	_replay_remaining = -1.0
	if _player != null:
		_player.stop()
		observe(_player.status())

func poll_status() -> void:
	if _player != null:
		observe(_player.status())

func _process(delta: float) -> void:
	if Engine.is_editor_hint():
		return
	poll_status()
	# Batch property changes once per frame; idle cues never open a stream.
	if (_playing or _start_pending) and _active_route != _route():
		try_play()
	if _active_loop != loop:
		_active_loop = loop
		set_loop(loop)
	if not auto_replay or loop:
		_replay_remaining = -1.0
	if _replay_remaining >= 0.0:
		_replay_remaining -= delta
		if _replay_remaining <= 0.0:
			_replay_remaining = -1.0
			try_play()

## Consumes a native status snapshot (public so tests can feed synthetic statuses).
func observe(status: Dictionary) -> void:
	output_latency_ms = float(status.get("output_latency_ms", -1.0))
	output_mode = int(status.get("output_mode", 0))
	var started: bool = status.started_sequence > _seen_start
	var ended: bool = status.ended_sequence > _seen_end
	_seen_start = status.started_sequence
	_seen_end = status.ended_sequence
	if status.state == 4:
		last_error = status.error
		_replay_remaining = -1.0 # a failure never triggers replay or a false Playing
	var active: bool = status.state == 2 or status.state == 3
	var was_playing := _playing
	if started and not _playing:
		_playing = true
		state_changed.emit(true)
	var restarted := was_playing and started and active
	if _playing and ((ended and not restarted) or not active):
		_playing = false
		if ended and status.reason == 1 and auto_replay and not loop and status.state != 4:
			_replay_remaining = choose_replay_delay()
		# Subscribers may stop synchronously; don't re-arm after their cancellation.
		state_changed.emit(false)
	if _start_pending:
		if started:
			_start_pending = false
		elif status.state == 4:
			_start_pending = false
			start_failed.emit(last_error)
