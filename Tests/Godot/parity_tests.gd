extends RefCounted
## Synthetic workers only. No device inventory, audio, capture, or sockets.
class CueProbe extends SpatialFabricPlaybackCue:
	var requests := 0
	func try_play() -> bool:
		requests += 1
		_active_route = _route()
		_start_pending = true
		return true

class ManagerProbe extends SpatialFabricManager:
	var acknowledgements: Array = []
	func _ack(cue: Node, command: String, result: String, _detail: String = "") -> void:
		acknowledgements.append([cue, command, result])

class LiveProbe extends SpatialFabricLiveInputCue:
	var requests := 0
	func try_start() -> bool:
		requests += 1
		_active_route = _route()
		_start_pending = true
		return true

static func run(tree: SceneTree, check: Callable) -> void:
	var cue := CueProbe.new()
	cue.name = "Cue_α"
	tree.root.add_child(cue)
	check.call(cue.requests == 0 and not cue.play_on_start, "parity: default startup is inert")
	cue.play_on_start = true
	cue._ready()
	check.call(cue.requests == 1, "parity: opt-in startup requests play only in runtime")
	cue.stop()
	cue.requests = 0
	cue.output_channel = 2
	cue.source_path = "res://changed.wav"
	cue._process(0.0)
	check.call(cue.requests == 0, "parity: idle route/source edits never start audio")
	cue._playing = true
	cue._active_route = cue._route()
	cue.output_channel = 3
	cue.device_id = "invalid-id"
	cue._process(0.0)
	check.call(cue.requests == 1, "parity: active route edits batch one restart")
	cue._process(0.0)
	check.call(cue.requests == 1, "parity: unchanged active route never restarts")
	cue.source_path = "res://next.wav"
	cue._process(0.0)
	check.call(cue.requests == 2, "parity: active source edit restarts")
	cue.stop()
	cue._playing = false
	cue.auto_replay = true
	cue.random_replay_delay = true
	cue.replay_delay_min = 0.25
	cue.replay_delay_max = 0.75
	var values: Dictionary = {}
	var bounded := true
	for i in 100:
		var delay := cue.choose_replay_delay()
		bounded = bounded and delay >= 0.25 and delay <= 0.75
		values[delay] = true
	check.call(bounded and values.size() > 1, "parity: randomized replay min/max vary within bounds")
	cue.replay_delay_min = 0.4
	cue.replay_delay_max = 0.4
	cue.observe({"state": 2, "reason": 0, "started_sequence": 1, "ended_sequence": 0, "error": "", "output_latency_ms": 7.5, "output_mode": 3})
	check.call(cue.output_latency_ms == 7.5 and cue.output_mode == 3, "parity: OS latency and fallback mode use additive status")
	cue.observe({"state": 0, "reason": 1, "started_sequence": 1, "ended_sequence": 1, "error": ""})
	check.call(is_equal_approx(cue._replay_remaining, 0.4), "parity: EOF selects random delay")
	cue.stop()
	check.call(not cue.replay_pending(), "parity: stop cancels randomized replay")
	cue.observe({"state": 2, "reason": 0, "started_sequence": 2, "ended_sequence": 1, "error": ""})
	var stop_on_end := func(playing: bool) -> void:
		if not playing:
			cue.stop()
	cue.state_changed.connect(stop_on_end)
	cue.observe({"state": 0, "reason": 1, "started_sequence": 2, "ended_sequence": 2, "error": ""})
	check.call(not cue.replay_pending(), "parity: stop from EOF subscriber cannot rearm replay")
	cue.state_changed.disconnect(stop_on_end)
	cue.observe({"state": 2, "reason": 0, "started_sequence": 3, "ended_sequence": 2, "error": ""})
	cue.observe({"state": 0, "reason": 1, "started_sequence": 3, "ended_sequence": 3, "error": ""})
	cue.auto_replay = false
	var before_cancel := cue.requests
	cue._process(1.0)
	check.call(not cue.replay_pending() and cue.requests == before_cancel, "parity: disabling replay cancels pending delay")
	cue.auto_replay = true
	cue.random_replay_delay = false
	cue.replay_delay_seconds = 1.25
	check.call(cue.choose_replay_delay() == 1.25, "parity: fixed replay retained")
	cue.replay_delay_seconds = 7200.0
	check.call(cue.choose_replay_delay() == 7200.0, "parity: long finite replay delay is not silently clamped")
	cue.random_replay_delay = true
	cue.replay_delay_min = NAN
	check.call(cue.choose_replay_delay() < 0, "parity: nonfinite random interval fails closed")
	var other := SpatialFabricPlaybackCue.new()
	other.name = "Cue-α"
	tree.root.add_child(other)
	check.call(cue.effective_osc_base() != other.effective_osc_base(), "parity: blank overrides derive unique escaped hierarchy paths")
	var before := other.effective_osc_base()
	other.persistent_key = "changed-by-author"
	check.call(other.effective_osc_base() == before and other.osc_base.is_empty(), "parity: derivation is read-only")
	cue.osc_base = "/godot/playback/cue"
	check.call(cue.effective_osc_base() == "/godot/playback/cue", "parity: legacy explicit OSC path preserved")
	other.osc_base = cue.osc_base
	var manager := ManagerProbe.new()
	tree.root.add_child(manager)
	manager.cue_paths = [manager.get_path_to(cue), manager.get_path_to(other), manager.get_path_to(cue)]
	check.call(manager._cues().size() == 2, "parity: repeated bindings never dispatch twice")
	check.call(manager.routing_diagnostics().size() == 1, "parity: explicit OSC conflict diagnostics")
	other.osc_base = "/bad/*"
	check.call(manager.routing_diagnostics().size() == 1, "parity: invalid OSC diagnostics")
	cue.osc_base = "/nested"
	var nested_child := CueProbe.new()
	tree.root.add_child(nested_child)
	nested_child.osc_base = "/nested/child"
	manager.cue_paths = [manager.get_path_to(cue), manager.get_path_to(nested_child)]
	manager._dispatch_playback({"address": "/nested/child/state", "args": [0.0]})
	manager._dispatch_playback({"address": "/nested/child/ack", "args": []})
	check.call(manager.acknowledgements.is_empty(), "parity: nested feedback globally suppressed")
	var before_parent := cue.requests
	var before_child := nested_child.requests
	manager._dispatch_playback({"address": "/nested/child/play", "args": [1.0]})
	check.call(cue.requests == before_parent and nested_child.requests == before_child + 1 and manager.acknowledgements.size() == 1, "parity: most-specific base owns nested commands")
	var live := LiveProbe.new()
	tree.root.add_child(live)
	live.output_device_id = "invalid"
	live._process(0.0)
	check.call(live.requests == 0, "parity: idle live route edit never captures")
	live._live = true
	live._active_route = live._route()
	live.input_channel = 2
	live._process(0.0)
	check.call(live.requests == 1, "parity: active live route change restarts only active session")
	live.observe({"state": 2, "reason": 0, "started_sequence": 1, "ended_sequence": 0, "error": "", "output_latency_ms": 4.25, "output_mode": 1})
	check.call(live.output_latency_ms == 4.25 and live.output_mode == 1, "parity: live OS output latency separate from ring occupancy")
	if ClassDB.class_exists("SFNativePlayer"):
		var native: Object = ClassDB.instantiate("SFNativePlayer")
		var status: Dictionary = native.status()
		check.call(status.get("output_latency_ms", 999) == -1.0 and status.get("output_mode", -1) == 0, "parity: native playback additive latency/mode API inactive sentinel")
	if ClassDB.class_exists("SFNativeLive"):
		var native: Object = ClassDB.instantiate("SFNativeLive")
		var status: Dictionary = native.status()
		check.call(status.get("output_latency_ms", 999) == -1.0 and status.get("output_mode", -1) == 0, "parity: native live additive latency/mode API inactive sentinel")
	# Same property transaction primitive used by editor manager; persistence tested by packing.
	var undo := UndoRedo.new()
	undo.create_action("routing")
	undo.add_do_property(other, "output_channel", 5)
	undo.add_undo_property(other, "output_channel", 0)
	undo.commit_action()
	check.call(other.output_channel == 5, "parity: authoring property transaction applies")
	undo.undo()
	check.call(other.output_channel == 0, "parity: routing Undo")
	undo.redo()
	check.call(other.output_channel == 5, "parity: routing Redo")
	other.osc_base = ""
	var packed := PackedScene.new()
	check.call(packed.pack(other) == OK, "parity: authored cue packs")
	var restored := packed.instantiate() as SpatialFabricPlaybackCue
	check.call(restored.output_channel == 5 and restored.osc_base.is_empty(), "parity: authored routing and blank override persist")
	restored.free()
	var save_path := "user://spatialfabric-routing-persistence.tscn"
	check.call(ResourceSaver.save(packed, save_path) == OK, "parity: routing scene saves to disk")
	var disk_scene := ResourceLoader.load(save_path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var disk_cue := disk_scene.instantiate() as SpatialFabricPlaybackCue
	check.call(disk_cue.output_channel == 5 and disk_cue.osc_base.is_empty(), "parity: saved scene reload preserves routing and derived override")
	disk_cue.free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))
	undo.clear_history()
	undo.free()
	manager.free()
	nested_child.free()
	cue.free()
	other.free()
	live.free()
