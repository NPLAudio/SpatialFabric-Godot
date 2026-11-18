@tool
class_name SpatialFabricLiveInputCue
extends Node3D
## Live capture device -> direct output. Starting is explicit and may trigger an OS microphone prompt.
## No Godot AudioServer/mixer/AudioStreamMicrophone is used and there is no default fallback for a
## configured ID. "Live" means the native worker really started, not that a start was requested.

signal state_changed(live: bool)
signal start_failed(detail: String)

@export var persistent_key: String = ""
@export var osc_base: String = ""
## Exact capture endpoint ID; empty selects the system default input.
@export var input_device_id: String = ""
## 0 = all input channels, 1..N = only that input channel.
@export_range(0, 64) var input_channel: int = 0
## Exact render endpoint ID; empty selects the system default output.
@export var output_device_id: String = ""
## 0 = corresponding channels (a single selected input lands on output 1), 1..N = exactly one output.
@export_range(0, 64) var output_channel: int = 0
@export var exclusive_output: bool = false
@export_range(0, 2000) var buffer_ms: int = 0
@export_range(0.0, 4.0) var gain: float = 1.0
var last_error: String = ""
var last_input_json: String = ""
var worker_state: int = 0
var input_peak: float = 0.0
var underruns: int = 0
var overruns: int = 0
## Queue occupancy estimate, not OS output latency.
var latency_ms: float = 0.0
var output_latency_ms: float = -1.0
var output_mode: int = 0
var _session: Object
var _live := false
var _seen_start := 0
var _seen_end := 0
var _start_pending := false
var _active_route: Array = []

func effective_osc_base() -> String:
	return osc_base if not osc_base.is_empty() else SpatialFabricPlaybackCue.derived_osc_base(self, "live")

func _route() -> Array:
	return [input_device_id, input_channel, output_device_id, output_channel, exclusive_output, buffer_ms]

func _exit_tree() -> void:
	stop()

static func native_available() -> bool:
	return ClassDB.class_exists("SFNativeLive") and ClassDB.instantiate("SFNativeLive").live_abi_version() == 1

func is_live() -> bool:
	return _live

## Explicit capture-endpoint inventory. Opens no stream; the JSON is kept in last_input_json.
func refresh_input_devices() -> Error:
	if not ClassDB.class_exists("SFNativeLive"):
		last_error = "Native live input is not loaded."
		return ERR_UNAVAILABLE
	var result: Dictionary = ClassDB.instantiate("SFNativeLive").input_devices_json()
	if not result.ok:
		last_error = result.error
		return FAILED
	last_input_json = result.json
	last_error = ""
	return OK

## Submits a start REQUEST (may prompt for microphone access). is_live() follows the worker.
func try_start() -> bool:
	if Engine.is_editor_hint():
		last_error = "Live capture is disabled in editor authoring."
		return false
	poll_status()
	stop()
	_active_route = _route()
	if not ClassDB.class_exists("SFNativeLive"):
		last_error = "Native live input is not loaded; nothing was started."
		return false
	if _session == null:
		_session = ClassDB.instantiate("SFNativeLive")
	if _session.start(input_device_id, input_channel, output_device_id, output_channel, exclusive_output, buffer_ms, gain) == 0:
		observe(_session.status())
		if last_error.is_empty():
			last_error = "Native live session refused the start request."
		return false
	_start_pending = true
	last_error = ""
	return true

func set_gain(value: float) -> bool:
	if is_nan(value) or is_inf(value) or value < 0.0 or value > 4.0:
		last_error = "Gain must be finite 0..4."
		return false
	gain = value
	if _session != null:
		_session.set_gain(value)
	return true

func stop() -> void:
	_start_pending = false
	if _session != null:
		_session.stop()
		observe(_session.status())

func poll_status() -> void:
	if _session != null:
		observe(_session.status())

func _process(_delta: float) -> void:
	if Engine.is_editor_hint():
		return
	poll_status()
	if (_live or _start_pending) and _active_route != _route():
		try_start()

## Consumes a native status snapshot (public so tests can feed synthetic statuses).
func observe(status: Dictionary) -> void:
	output_latency_ms = float(status.get("output_latency_ms", -1.0))
	output_mode = int(status.get("output_mode", 0))
	worker_state = status.state
	input_peak = maxf(input_peak * 0.9, status.get("input_peak", 0.0))
	underruns = status.get("underruns", 0)
	overruns = status.get("overruns", 0)
	var rate: int = status.get("input_rate", 0)
	latency_ms = float(status.get("latency_frames", 0)) * 1000.0 / rate if rate > 0 else 0.0
	if status.state == 4:
		last_error = status.error
	var started: bool = status.started_sequence > _seen_start
	var ended: bool = status.ended_sequence > _seen_end
	_seen_start = status.started_sequence
	_seen_end = status.ended_sequence
	var active: bool = status.state == 2 or status.state == 3
	var was_live := _live
	if started and not _live:
		_live = true
		state_changed.emit(true)
	var restarted := was_live and started and active
	if _live and ((ended and not restarted) or not active):
		_live = false
		state_changed.emit(false)
	if _start_pending:
		if started:
			_start_pending = false
		elif status.state == 4:
			_start_pending = false
			start_failed.emit(last_error)
