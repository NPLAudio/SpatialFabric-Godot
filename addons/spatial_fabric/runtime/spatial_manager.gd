@tool
class_name SpatialFabricManager
extends Node3D
## Nothing binds or sends until start_networking(). Playback/native audio remains unavailable.

@export var persistent_key: String = ""
@export var stage_path: NodePath
@export var object_paths: Array[NodePath] = []
@export var cue_paths: Array[NodePath] = []
@export var live_paths: Array[NodePath] = []
@export_range(1024, 65535) var spatial_input_port: int = 8100
@export_range(1024, 65535) var playback_input_port: int = 9000
@export_range(1024, 65535) var monitor_port: int = 9001
@export_range(1024, 65535) var adm_port: int = 50018
@export_range(1024, 65535) var custom_port: int = 9002
@export var listen_address: String = "127.0.0.1"
@export var allow_remote_discovery: bool = false
@export var adm_enabled: bool = false
@export var adm_host: String = "127.0.0.1"
@export var monitor_host: String = "127.0.0.1"
@export_enum("XYZ", "AED", "Both") var adm_mode: int = 0
@export_range(1.0, 240.0) var adm_rate_hz: float = 30.0
## Unchanged positions are re-sent this often so a receiver that starts later (or misses a packet) still learns
## every object, including static ones. 0 sends only on change.
@export_range(0.0, 60.0) var adm_refresh_seconds: float = 1.0
var last_error: String = ""
var transport: SpatialFabricTransport
var queries_answered := 0
var queries_ignored := 0
var _adm_clock := 0.0
var _adm_refresh_clock := 0.0
var _adm_last: Dictionary = {}
var _adm_sent := 0

func is_listening() -> bool:
	return transport != null and transport.is_open()

## Explicit user/API action. Binds spatial and playback input ports exactly or fails with no sockets.
func start_networking() -> Error:
	if is_listening():
		return ERR_ALREADY_IN_USE
	if not allow_remote_discovery and not SpatialFabricSceneQuery.is_loopback(listen_address):
		last_error = "Non-loopback listen address requires allow_remote_discovery."
		return ERR_UNAUTHORIZED
	var candidate := SpatialFabricTransport.new()
	var result := candidate.open([spatial_input_port, playback_input_port], listen_address)
	if result != OK:
		last_error = candidate.last_error
		return result
	transport = candidate
	last_error = ""
	for cue in _cues():
		cue.state_changed.connect(_on_cue_state.bind(cue))
	for live in _lives():
		live.state_changed.connect(_on_live_state.bind(live))
	set_process(true)
	return OK

func _cues() -> Array[SpatialFabricPlaybackCue]:
	var out: Array[SpatialFabricPlaybackCue] = []
	for path in cue_paths:
		var cue := get_node_or_null(path) as SpatialFabricPlaybackCue
		if cue != null:
			out.append(cue)
	return out

func _lives() -> Array[SpatialFabricLiveInputCue]:
	var out: Array[SpatialFabricLiveInputCue] = []
	for path in live_paths:
		var live := get_node_or_null(path) as SpatialFabricLiveInputCue
		if live != null:
			out.append(live)
	return out

func _on_live_state(is_live: bool, live: SpatialFabricLiveInputCue) -> void:
	if is_listening():
		transport.send(monitor_host, monitor_port, SpatialFabricOsc.encode(live.osc_base + "/state", [1.0 if is_live else 0.0]))

## Observed worker lifecycle only (1/0), never an acknowledgement of the request.
func _on_cue_state(playing: bool, cue: SpatialFabricPlaybackCue) -> void:
	if is_listening():
		transport.send(monitor_host, monitor_port, SpatialFabricOsc.encode(cue.osc_base + "/state", [1.0 if playing else 0.0]))

func _dispatch_playback(message: Dictionary) -> void:
	for live in _lives():
		var live_tail: String = message.address.trim_prefix(live.osc_base + "/") if message.address.begins_with(live.osc_base + "/") else ""
		match live_tail:
			"play":
				if SpatialFabricPlaybackControl.should_play(message.args):
					live.try_start()
			"stop":
				live.stop()
			"gain":
				var level: Variant = SpatialFabricPlaybackControl.gain_value(message.args)
				if level != null:
					live.set_gain(level)
	for cue in _cues():
		var tail: String = message.address.trim_prefix(cue.osc_base + "/") if message.address.begins_with(cue.osc_base + "/") else ""
		match tail:
			"play":
				if SpatialFabricPlaybackControl.should_play(message.args):
					cue.try_play()
			"stop":
				cue.stop()
			"loop":
				var value: Variant = SpatialFabricPlaybackControl.loop_value(message.args)
				if value != null:
					cue.set_loop(value)

func stop_networking() -> void:
	for cue in _cues():
		var bound := _on_cue_state.bind(cue)
		if cue.state_changed.is_connected(bound):
			cue.state_changed.disconnect(bound)
	for live in _lives():
		var live_bound := _on_live_state.bind(live)
		if live.state_changed.is_connected(live_bound):
			live.state_changed.disconnect(live_bound)
	if transport != null:
		transport.close()
	transport = null
	_adm_last.clear()

func _exit_tree() -> void:
	stop_networking()

func _process(delta: float) -> void:
	if not is_listening():
		return
	for message in transport.poll():
		if message.port == playback_input_port and message.address != SpatialFabricSceneQuery.QUERY:
			_dispatch_playback(message)
			continue
		if message.address != SpatialFabricSceneQuery.QUERY:
			continue
		var request := SpatialFabricSceneQuery.parse(message.args)
		var loopback := SpatialFabricSceneQuery.is_loopback(message.ip)
		if request.is_empty() or (not loopback and not allow_remote_discovery):
			queries_ignored += 1
			continue
		var packets := SpatialFabricSceneQuery.response_packets(request, get_scene_page(request.offset, request.limit))
		if packets.is_empty():
			queries_ignored += 1
			continue
		for packet in packets:
			transport.send(message.ip, request.reply_port, packet)
		queries_answered += 1
	if adm_enabled:
		_adm_refresh_clock += delta
		if adm_refresh_seconds > 0.0 and _adm_refresh_clock >= adm_refresh_seconds:
			_adm_refresh_clock = 0.0
			_adm_last.clear() # forces every object to be re-sent once
		_adm_clock += delta
		if _adm_clock >= 1.0 / adm_rate_hz:
			_adm_clock = 0.0
			_emit_adm()

func _emit_adm() -> void:
	var stage := get_node_or_null(stage_path) as SpatialFabricStage
	if stage == null or not stage.is_valid_stage():
		return
	for path in object_paths:
		var item := get_node_or_null(path) as SpatialFabricObject
		if item == null or item.object_id < 1:
			continue
		var target := item.pose()
		if target == null:
			continue
		var normalized: Variant = stage.normalize_world(target.global_position)
		if normalized == null:
			continue
		var wire := SpatialFabricStage.adm_xyz(normalized)
		var previous: Variant = _adm_last.get(item.object_id)
		if previous != null and previous.distance_to(wire) < 0.0001:
			continue
		var base := "/adm/obj/%d" % item.object_id
		var packets: Array[PackedByteArray] = []
		if adm_mode == 0 or adm_mode == 2:
			packets.append(SpatialFabricOsc.encode(base + "/xyz", [wire.x, wire.y, wire.z]))
		if adm_mode == 1 or adm_mode == 2:
			var aed := SpatialFabricStage.adm_aed(normalized)
			packets.append(SpatialFabricOsc.encode(base + "/aed", [aed.x, aed.y, aed.z]))
		var ok := true
		for packet in packets:
			ok = ok and transport.send(adm_host, adm_port, packet) == OK
			_adm_sent += 1
		if ok:
			_adm_last[item.object_id] = wire

static func _error(message: String) -> Dictionary:
	return {"schema": "org.nplaudio.spatialfabric.scene", "schema_version": 1, "engine": "Godot", "error": message}

static func _array(value: Vector3) -> Array:
	return [value.x, value.y, value.z]

func _row(kind: String, item: Node3D, key: String) -> Dictionary:
	return {"kind": kind, "key": key, "actor_path": str(item.get_path()), "actor_label": str(item.name), "world_transform": {"position_cm": _array(SpatialFabricStage.canonical_world_meters(item.global_position) * 100.0)}}

func get_scene_page(offset: int = 0, limit: int = 64) -> Dictionary:
	if offset < 0 or offset > 16384 or limit < 1 or limit > 64:
		return _error("Invalid page bounds.")
	if object_paths.size() > 4096 or cue_paths.size() > 4096:
		return _error("Binding list exceeds wireframe bounds.")
	var scope := get_parent()
	var stage := get_node_or_null(stage_path) as SpatialFabricStage
	if scope == null or stage == null or not scope.is_ancestor_of(stage) or not stage.is_valid_stage():
		return _error("Missing, out-of-scope or invalid stage.")
	var nodes: Array[Node3D] = [self, stage]
	var kinds: Array[String] = ["manager", "stage"]
	for path in object_paths:
		var item := get_node_or_null(path) as SpatialFabricObject
		if item == null or not scope.is_ancestor_of(item):
			return _error("Unresolved/out-of-scope object binding.")
		nodes.append(item)
		kinds.append("binding")
	for path in cue_paths:
		var cue := get_node_or_null(path) as SpatialFabricPlaybackCue
		if cue == null or not scope.is_ancestor_of(cue):
			return _error("Unresolved/out-of-scope playback cue.")
		nodes.append(cue)
		kinds.append("playback")
	for path in live_paths:
		var live_node := get_node_or_null(path) as SpatialFabricLiveInputCue
		if live_node == null or not scope.is_ancestor_of(live_node):
			return _error("Unresolved/out-of-scope live input.")
		nodes.append(live_node)
		kinds.append("live_input")
	var keys: Dictionary = {}
	var rows: Array[Dictionary] = []
	for i in nodes.size():
		var item := nodes[i]
		var key: String = item.get("persistent_key")
		if key.is_empty() or key.length() > 128 or keys.has(key):
			return _error("Missing/duplicate authored key; repair explicitly, never in discovery.")
		keys[key] = true
		if not item.global_transform.is_finite() or not (SpatialFabricStage.canonical_world_meters(item.global_position) * 100.0).is_finite():
			return _error("Non-finite transform.")
		var row := _row(kinds[i], item, key)
		if item is SpatialFabricStage:
			row["dimensions_meters"] = _array(item.dimensions_meters)
			row["listener_follow_mode"] = "Off"
		elif item is SpatialFabricObject:
			var target: Node3D = item.pose()
			if item.object_id < 1 or target == null or not scope.is_ancestor_of(target):
				return _error("Invalid object ID or unresolved/out-of-scope pose.")
			var normalized: Variant = stage.normalize_world(target.global_position)
			if normalized == null:
				return _error("Non-finite bound pose.")
			row["default_object_id"] = item.object_id
			row["display_label"] = item.display_label
			row["stage_normalized"] = _array(normalized)
			row["stage_meters"] = _array(normalized * stage.dimensions_meters * 0.5)
		elif item is SpatialFabricPlaybackCue:
			row["osc_base"] = item.osc_base
			row["output_channel"] = item.output_channel
			row["playing"] = item.is_playing()
			row["prepared"] = item.is_prepared()
			row["loop"] = item.loop
			row["backend_status"] = "available" if SpatialFabricPlaybackCue.native_available() else "unavailable"
			row["last_error"] = item.last_error
		elif item is SpatialFabricLiveInputCue:
			row["osc_base"] = item.osc_base
			row["controls"] = {"play": item.osc_base + "/play", "stop": item.osc_base + "/stop", "gain": item.osc_base + "/gain"}
			row["state_address"] = item.osc_base + "/state"
			row["input_device_id"] = item.input_device_id
			row["configured_device_id"] = item.output_device_id
			row["input_channel"] = item.input_channel
			row["output_channel"] = item.output_channel
			row["gain"] = item.gain
			row["playing"] = item.is_live()
			row["input_peak"] = item.input_peak
			row["backend_status"] = "available" if SpatialFabricLiveInputCue.native_available() else "unavailable"
			row["last_error"] = item.last_error
		rows.append(row)
	var end: int = mini(offset + limit, rows.size())
	var page_rows: Array[Dictionary] = rows.slice(mini(offset, rows.size()), end)
	var page := {"schema": "org.nplaudio.spatialfabric.scene", "schema_version": 1, "engine": "Godot", "world": scope.scene_file_path, "world_type": "Editor" if Engine.is_editor_hint() else "Game", "snapshot_utc": Time.get_datetime_string_from_system(true) + "Z", "coordinates": "Canonical front/right/up = Godot -Z/X/Y meters; world_transform.position_cm is canonical centimeters.", "playback_network": {"listening": is_listening(), "status": "listening" if is_listening() else "stopped", "requested_port": playback_input_port, "native_playback": "available" if SpatialFabricPlaybackCue.native_available() else "unavailable"}, "offset": offset, "limit": limit, "returned": page_rows.size(), "total": rows.size(), "next_offset": end if end < rows.size() else -1, "objects": page_rows}
	if JSON.stringify(page).to_utf8_buffer().size() > 96 * 1024:
		return _error("Page exceeds 96 KiB.")
	return page
