@tool
class_name SpatialFabricPlaybackCue
extends Node3D
## Direct-device cue. Source preparation, device inventory and playback are explicit calls.
## There is no AudioStreamPlayer/mixer fallback: without the native extension everything fails closed.
## Playing is only what the native worker has OBSERVABLY started, never a request acknowledgement.

signal state_changed(playing: bool)

@export var persistent_key: String = ""
@export var osc_base: String = "/godot/playback/cue"
@export_file("*.wav") var source_path: String = ""
@export_range(0, 256) var output_channel: int = 0
@export var device_id: String = ""
@export var exclusive: bool = false
@export_range(5, 500) var buffer_ms: int = 20
@export var loop: bool = false
@export var auto_replay: bool = false
@export_range(0.0, 3600.0) var replay_delay_seconds: float = 2.5
var last_error: String = ""
var last_device_json: String = ""
var _buffer: Object
var _player: Object
var _playing := false
var _replay_remaining := -1.0
var _seen_start := 0
var _seen_end := 0

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
	_replay_remaining = -1.0
	if not is_prepared():
		last_error = "Source is not prepared; call prepare_source() explicitly first."
		return false
	if _player == null:
		_player = ClassDB.instantiate("SFNativePlayer")
	if _player.start(_buffer, device_id, output_channel, exclusive, buffer_ms, loop) != 0:
		last_error = "Native player refused the start request."
		return false
	last_error = ""
	return true

func set_loop(enabled: bool) -> void:
	loop = enabled
	if _player != null:
		_player.set_loop(enabled)
	if enabled:
		_replay_remaining = -1.0

func stop() -> void:
	_replay_remaining = -1.0
	if _player != null:
		_player.stop()
		observe(_player.status())

func _process(delta: float) -> void:
	if _player != null:
		observe(_player.status())
	if _replay_remaining >= 0.0:
		_replay_remaining -= delta
		if _replay_remaining <= 0.0:
			_replay_remaining = -1.0
			try_play()

## Consumes a native status snapshot (public so tests can feed synthetic statuses).
func observe(status: Dictionary) -> void:
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
		state_changed.emit(false)
		if ended and status.reason == 1 and auto_replay and not loop and status.state != 4:
			_replay_remaining = replay_delay_seconds
