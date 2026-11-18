@tool
extends EditorPlugin
## Run with Tools/validate_editor.py in an isolated project and normal editor loop.
## Enabled only in that copy and gated by an explicit report argument.
## Edits only in-memory scene properties and undoes them. Never saves the example.
var failures: Array[String] = []
var passes: Array[String] = []

func check(ok: bool, label: String) -> void:
	(passes if ok else failures).append(label)

var report_path := ""

func _enter_tree() -> void:
	var args := OS.get_cmdline_user_args()
	var flag := args.find("--spatialfabric-authoring-report")
	if flag < 0:
		return
	if flag + 1 >= args.size():
		push_error("Missing editor authoring report path")
		get_tree().quit(2)
		return
	report_path = args[flag + 1]
	call_deferred("run")

func run() -> void:
	var plugin: Node
	for i in 300:
		for node in get_tree().root.find_children("*", "", true, false):
			if node.get_script() == load("res://addons/spatial_fabric/plugin.gd"):
				plugin = node
				break
		if plugin != null:
			break
		await get_tree().process_frame
	var scene: Node
	if plugin != null:
		EditorInterface.open_scene_from_path("res://examples/four_rooms/room_showcase.tscn")
		for i in 300:
			scene = EditorInterface.get_edited_scene_root()
			if scene != null and scene.scene_file_path == "res://examples/four_rooms/room_showcase.tscn":
				break
			scene = null
			await get_tree().process_frame
	if plugin == null or scene == null:
		check(false, "authoring plugin and requested scene become ready in editor")
	else:
		var cue := scene.get_node("Mono") as SpatialFabricPlaybackCue
		cue.play_on_start = true
		cue._ready()
		cue._process(1.0)
		check(not cue.is_playing() and cue._player == null and not cue.is_prepared(), "editor startup/process never prepares or opens stream")
		check(not cue.try_play() and cue.prepare_source() == ERR_UNAVAILABLE, "editor playback and preparation APIs fail closed")
		cue.play_on_start = false
		var authored_base := cue.osc_base
		cue.osc_base = ""
		var expected_base := "/godot/playback/" + str(scene.name).to_utf8_buffer().hex_encode() + "/" + str(cue.name).to_utf8_buffer().hex_encode()
		check(cue.effective_osc_base() == expected_base, "derived editor OSC excludes editor viewport ancestors")
		cue.osc_base = authored_base
		plugin.call("_refresh")
		var original := cue.output_channel
		var row: Dictionary = plugin.call("_snapshot", cue)
		row.output_channel = 7
		plugin.call("_commit_rows", [row], PackedStringArray(), "test routing authoring")
		check(cue.output_channel == 7, "editor manager applies valid row")
		var history := (plugin as EditorPlugin).get_undo_redo()
		var id := history.get_object_history_id(cue)
		var undo := history.get_history_undo_redo(id)
		undo.undo()
		check(cue.output_channel == original, "EditorUndoRedoManager undoes routing transaction")
		undo.redo()
		check(cue.output_channel == 7, "EditorUndoRedoManager redoes routing transaction")
		undo.undo()
		var invalid := row.duplicate(true)
		invalid.output_channel = 999
		plugin.call("_commit_rows", [invalid], PackedStringArray(), "invalid row")
		check(cue.output_channel == original, "editor invalid whole row has no mutation")
		plugin.call("_commit_rows", [row, row], PackedStringArray(), "duplicate rows")
		check(cue.output_channel == original, "editor duplicate targets reject all duplicate rows")
		var other := scene.get_node("Stereo") as SpatialFabricPlaybackCue
		row.osc_base = other.effective_osc_base()
		plugin.call("_commit_rows", [row], PackedStringArray(), "conflicting OSC")
		check(cue.output_channel == original, "editor conflicting OSC rejects whole row")
		row.osc_base = cue.osc_base
		var live := SpatialFabricLiveInputCue.new()
		live.name = "CollisionLive"
		live.osc_base = cue.effective_osc_base()
		scene.add_child(live)
		live.owner = scene
		check(not plugin.call("_osc_diagnostics", {}).is_empty() and plugin.call("_scene_cues").size() == 3, "editor diagnoses playback/live collisions without exporting live rows")
		plugin.call("_commit_rows", [row], PackedStringArray(), "live conflict")
		check(cue.output_channel == original, "editor playback/live collision rejects whole row")
		scene.remove_child(live)
		live.free()
		plugin.call("_commit_rows", [row, invalid], PackedStringArray(), "partially valid import")
		check(cue.output_channel == 7, "editor valid row survives invalid row")
		undo.undo()
		check(cue.output_channel == original, "editor partial import is one undoable transaction")
		# File dialog result changes only draft until Apply.
		plugin.set("selected", cue)
		plugin.set("source_target_id", cue.get_instance_id())
		plugin.call("_source_chosen", "res://draft-only.wav")
		check(cue.source_path != "res://draft-only.wav", "source file dialog assignment is draft-only")
		plugin.set("file_scene_id", scene.get_instance_id())
		var csv_path := report_path.get_base_dir().path_join("routing-fixture.csv")
		plugin.call("_export_csv", csv_path)
		var policy := preload("res://addons/spatial_fabric/editor/routing_policy.gd")
		var imported := policy.import_csv(FileAccess.get_file_as_string(csv_path))
		check(imported.rows.size() == 3 and imported.errors.is_empty(), "editor CSV export is roundtrippable")
		for record in imported.rows:
			if record.node_path == row.node_path:
				record.output_channel = 9
		var csv_file := FileAccess.open(csv_path, FileAccess.WRITE)
		csv_file.store_string(policy.export_csv(imported.rows))
		csv_file.close()
		plugin.call("_import_csv", csv_path)
		check(cue.output_channel == 9, "editor CSV file import applies routing")
		undo.undo()
		check(cue.output_channel == original, "editor CSV file import undoes as one transaction")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(csv_path))
		check(cue._player == null and not cue.is_prepared(), "editor authoring never opens audio")
	# Let the normal editor's background scan finish before shutdown; quitting during
	# first-scan initialization otherwise emits "Scan thread aborted" warnings.
	var filesystem := EditorInterface.get_resource_filesystem()
	for i in 600:
		if not filesystem.is_scanning():
			break
		await get_tree().process_frame
	if filesystem.is_scanning():
		check(false, "editor filesystem scan completes before shutdown")
	var report := {"passed": passes, "failed": failures, "status": "passed" if failures.is_empty() else "failed"}
	print(JSON.stringify(report))
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file == null:
		push_error("Cannot write editor authoring report")
		get_tree().quit(2)
		return
	file.store_string(JSON.stringify(report, "\t"))
	file.close()
	# Keep the normal editor MainLoop: replacing it with SceneTree leaks editor RIDs.
	get_tree().quit(0 if failures.is_empty() else 1)
