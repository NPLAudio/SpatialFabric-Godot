extends SceneTree
## Test-bed engine: serves the example scene's OSC inputs for a fixed time so external tools (the OSC
## Controller debugger) can compare what a sender emits with what the running engine reports.
## SILENT BY CONSTRUCTION: every cue is pointed at an intentionally invalid device ID, so a forwarded /play can
## only fail (and report why); nothing reaches a real output and no microphone can open.
## Usage: godot --headless --path . --script res://Tests/Godot/serve_for_debugger.gd -- <seconds>

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	var seconds := float(args[0]) if args.size() > 0 else 30.0
	var scene: Node3D = load("res://examples/four_rooms/room_showcase.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	for cue_name in ["Mono", "Stereo", "Replay"]:
		var cue := scene.get_node(cue_name) as SpatialFabricPlaybackCue
		cue.device_id = "godot-debugger-invalid-output"
		if SpatialFabricPlaybackCue.native_available():
			cue.prepare_source() # explicit and silent; the start will fail on the invalid device
	var live := scene.get_node("Live") as SpatialFabricLiveInputCue
	live.input_device_id = "godot-debugger-invalid-input"
	live.output_device_id = "godot-debugger-invalid-output"
	var manager := scene.get_node("Manager") as SpatialFabricManager
	var result := manager.start_networking()
	manager.adm_enabled = true # so a controller/tracker can be verified against a real sending engine
	if result != OK:
		push_error("Could not start networking: " + manager.last_error)
		quit(1)
		return
	print("SERVING spatial=%d playback=%d monitor=%d" % [manager.spatial_input_port, manager.playback_input_port, manager.monitor_port])
	await create_timer(seconds).timeout
	manager.stop_networking()
	print("DONE")
	quit(0)
