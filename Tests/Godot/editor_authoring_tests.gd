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

func select_property(manager: Node, key: String) -> Node:
	var picker: OptionButton = manager.get("properties")
	for index in picker.item_count:
		if picker.get_item_text(index) == key:
			picker.select(index)
	manager.call("show_value")
	return manager.get("value_editor")

func author_number(editor: Node, text: String, axis := 0) -> void:
	var spin: SpinBox = editor.get("controls")[axis]
	spin.get_line_edit().text = text
	spin.get_line_edit().text_changed.emit(text)

func central_manager_tests(plugin: Node) -> void:
	# Let startup layout restoration finish before changing the edited scene. Typed
	# controls exercise deferred signals/timers; startup must not reopen the example.
	await get_tree().create_timer(1.0).timeout
	var fixture := Node3D.new()
	fixture.name = "CentralFixture"
	var plain := Node.new()
	plain.name = "Ordinary"
	fixture.add_child(plain)
	plain.owner = fixture
	var hidden := Node3D.new()
	hidden.name = "Hidden"
	hidden.visible = false
	fixture.add_child(hidden)
	hidden.owner = fixture
	var packed := PackedScene.new()
	check(packed.pack(fixture) == OK, "central fixture packs")
	var path := "res://Tests/Godot/central_fixture.tscn"
	check(ResourceSaver.save(packed, path) == OK, "central fixture saves only in disposable project")
	fixture.free()
	EditorInterface.open_scene_from_path(path)
	for i in 300:
		fixture = EditorInterface.get_edited_scene_root()
		if fixture != null and fixture.scene_file_path == path:
			break
		await get_tree().process_frame
	var manager: Node = plugin.get("object_manager")
	plain = fixture.get_node("Ordinary")
	hidden = fixture.get_node("Hidden")
	manager.call("refresh")
	fixture.scene_file_path = ""
	check(manager.call("reason", plain).is_empty(), "central permits ordinary unsaved scenes")
	fixture.scene_file_path = path
	var listed: Array = manager.call("scene_nodes")
	check(listed.size() == 3 and plain in listed and hidden in listed, "central lists unconfigured ordinary and hidden nodes")
	manager.get("search").text = "hidden"
	manager.call("refresh")
	check(manager.get("listed") == [hidden], "central path filter includes hidden nodes")
	manager.get("search").text = ""
	manager.call("refresh")
	var internal := Node.new()
	fixture.add_child(internal, false, Node.INTERNAL_MODE_BACK)
	check(internal not in manager.call("scene_nodes"), "central excludes editor/internal nodes")
	fixture.remove_child(internal)
	internal.free()
	var selection := EditorInterface.get_selection()
	selection.clear()
	selection.add_node(plain)
	manager.call("use_scene_selection")
	check(manager.get("chosen") == [plain], "central accepts parent Scene Tree selection")
	var types: Dictionary = manager.get("TYPES")
	var single: Array[Node] = [plain]
	manager.call("attach", single, types.Playback)
	var cue: Node = manager.call("component", plain, types.Playback)
	check(cue != null and cue.owner == fixture and cue.get_parent() == plain, "central single add creates typed owned child")
	var inactive := SpatialFabricPlaybackCue.new()
	var equivalent := true
	for entry in manager.call("exported", types.Playback):
		if cue.get(entry.name) != inactive.get(entry.name):
			equivalent = false
	inactive.free()
	check(equivalent and plain.get_script() == null and not hidden.visible, "central attachment matches inactive defaults without replacing parent behavior")
	var history := (plugin as EditorPlugin).get_undo_redo()
	var undo := history.get_history_undo_redo(history.get_object_history_id(fixture))
	undo.undo()
	check(cue.get_parent() == null and is_instance_valid(cue), "central creation Undo retains child lifetime")
	undo.redo()
	check(cue.get_parent() == plain and cue.owner == fixture, "central creation redo restores ownership")
	var bulk: Array[Node] = [plain, hidden]
	manager.call("attach", bulk, types.Playback)
	var second: Node = manager.call("component", hidden, types.Playback)
	check(second != null and plain.get_child_count() == 1, "central bulk add prevents existing duplicates")
	undo.undo()
	check(second.get_parent() == null and cue.get_parent() == plain, "central bulk Undo only removes newly added children")
	undo.redo()
	manager.call("attach", bulk, types.Playback)
	check(plain.get_child_count() == 1 and hidden.get_child_count() == 1, "central repeated attachment is duplicate safe")
	manager.call("attach", single, types.Stage)
	var discarded: Node = manager.call("component", plain, types.Stage)
	undo.undo()
	# A different creation discards the redo branch; add_do_reference must free it.
	manager.call("attach", single, types["Spatial object"])
	check(not is_instance_valid(discarded), "central discarded creation redo frees detached child")
	cue.output_channel = 2
	second.output_channel = 5
	manager.set("chosen", bulk)
	manager.get("kind").select(0)
	manager.call("refresh_properties")
	var property_control: OptionButton = manager.get("properties")
	for index in property_control.item_count:
		if property_control.get_item_text(index) == "output_channel":
			property_control.select(index)
	manager.call("show_value")
	var typed_editor: Node = manager.get("value_editor")
	var spin: SpinBox = typed_editor.get("controls")[0]
	check(spin.get_line_edit().text.is_empty() and "Mixed" in spin.get_line_edit().placeholder_text, "central mixed SF values are clearly shown")
	manager.call("apply_value")
	check(cue.output_channel == 2 and second.output_channel == 5, "central mixed values retained until authored")
	author_number(typed_editor, "8")
	manager.call("apply_value")
	check(cue.output_channel == 8 and second.output_channel == 8, "central bulk property edit uses real exported property")
	check(property_control.get_item_text(property_control.selected) == "output_channel", "central Apply retains property key")
	undo.undo()
	check(cue.output_channel == 2 and second.output_channel == 5, "central property Undo restores distinct mixed originals")
	undo.redo()
	manager.call("remove_selected")
	check(cue.get_parent() == null and second.get_parent() == null, "central bulk removal detaches SF children")
	undo.undo()
	check(cue.owner == fixture and second.owner == fixture and cue.get_index() == 0, "central removal Undo restores owned children")
	undo.redo()
	check(cue.get_parent() == null and second.get_parent() == null, "central removal redo detaches without freeing early")
	undo.undo()
	for label in ["Live input", "Spatial object", "Stage", "Manager"]:
		manager.call("attach", single, types[label])
	var live: Node = manager.call("component", plain, types["Live input"])
	var runtime_manager: Node = manager.call("component", plain, types.Manager)
	check(cue._player == null and second._player == null and not cue.play_on_start and live._session == null and not runtime_manager.is_listening(), "central inactive attachment never starts audio capture or network")
	check(runtime_manager.cue_paths.is_empty() and runtime_manager.live_paths.is_empty() and runtime_manager.object_paths.is_empty(), "central attachment does not auto-enroll network manager")
	var names: Array = []
	for entry in manager.call("exported", types.Playback):
		names.append(entry.name)
	check("output_channel" in names and "transform" not in names and "name" not in names, "central exposes SF exports not general engine properties")
	manager.set("chosen", single)
	manager.get("kind").select(4)
	manager.call("refresh_properties")
	var paths: Array[NodePath] = [NodePath("../SpatialFabricPlaybackCue")]
	manager.call("edit_property", "cue_paths", paths)
	check(runtime_manager.cue_paths == paths, "central edits typed exported NodePath arrays")
	undo.undo()
	check(runtime_manager.cue_paths.is_empty(), "central explicit manager configuration is undoable")
	manager.call("edit_property", "spatial_input_port", "wrong type")
	check(runtime_manager.spatial_input_port == 8100, "central rejects wrong exported property types")
	await typed_control_tests(manager, plugin, fixture, plain, hidden, cue, second, runtime_manager, undo)
	# A packed external instance remains listed but is never mutated.
	var external_root := Node.new()
	external_root.name = "External"
	var external_child := Node.new()
	external_child.name = "Protected"
	external_root.add_child(external_child)
	external_child.owner = external_root
	var external_pack := PackedScene.new()
	external_pack.pack(external_root)
	ResourceSaver.save(external_pack, "res://Tests/Godot/central_external.tscn")
	external_root.free()
	var instance := (load("res://Tests/Godot/central_external.tscn") as PackedScene).instantiate()
	fixture.add_child(instance)
	instance.owner = fixture
	check(instance.get_child(0) in manager.call("scene_nodes") and not manager.call("reason", instance.get_child(0)).is_empty(), "central lists external packed nodes with protected reason")
	var protected_selection: Array[Node] = [instance.get_child(0)]
	manager.call("attach", protected_selection, types.Playback)
	check(instance.get_child(0).get_child_count() == 0, "central rejects external packed mutation")
	# Dummy rendering cannot create thumbnails; use the editor's no-preview save API.
	EditorInterface.save_scene_as(path, false)
	check(FileAccess.file_exists(path), "central edited fixture saves through normal editor")
	var saved := ResourceLoader.load(path, "PackedScene", ResourceLoader.CACHE_MODE_IGNORE) as PackedScene
	var restored := saved.instantiate()
	var persisted: Node = manager.call("component", restored.get_node("Ordinary"), types.Playback)
	check(persisted != null and persisted.output_channel == 8 and persisted.owner == restored, "central SF property and child ownership persist after save reload")
	restored.free()
	manager.set("chosen", single)
	manager.get("kind").select(0)
	manager.call("refresh_properties")
	var scene_draft := select_property(manager, "output_channel")
	author_number(scene_draft, "23")
	# Root instance in a saved inherited scene must also fail closed.
	var inherited_path := "res://Tests/Godot/central_inherited.tscn"
	var inherited_file := FileAccess.open(inherited_path, FileAccess.WRITE)
	inherited_file.store_string('[gd_scene load_steps=2 format=3]\n[ext_resource type="PackedScene" path="res://Tests/Godot/central_external.tscn" id="1"]\n[node name="Inherited" instance=ExtResource("1")]\n')
	inherited_file.close()
	EditorInterface.open_scene_from_path(inherited_path)
	for i in 300:
		var current := EditorInterface.get_edited_scene_root()
		if current != null and current.scene_file_path == inherited_path:
			break
		await get_tree().process_frame
	var inherited_root := EditorInterface.get_edited_scene_root()
	manager.call("refresh")
	check(not manager.get("draft_authored") and cue.output_channel == 8, "central scene switch cannot leak pending draft")
	check(not manager.call("reason", inherited_root).is_empty(), "central rejects protected inherited scene mutation")
	inherited_root.scene_file_path = ""
	check(not manager.call("reason", inherited_root).is_empty(), "central rejects unsaved inherited scene mutation")
	inherited_root.scene_file_path = inherited_path

func typed_control_tests(manager: Node, plugin: Node, fixture: Node, plain: Node, hidden: Node, cue: Node, second: Node, runtime_manager: Node, undo: UndoRedo) -> void:
	var bulk: Array[Node] = [plain, hidden]
	var types: Dictionary = manager.get("TYPES")
	manager.set("chosen", bulk)
	manager.get("kind").select(0)
	manager.call("refresh_properties")
	var editor := select_property(manager, "output_channel")
	check(editor.get("controls")[0] is SpinBox, "central numeric export creates SpinBox")
	author_number(editor, "-1")
	manager.call("apply_value")
	check(cue.output_channel == 8 and second.output_channel == 8, "central typed out of range edit rejects all targets")
	var numeric: SpinBox = editor.get("controls")[0]
	numeric.get_line_edit().grab_focus()
	await get_tree().process_frame
	author_number(editor, "-1")
	numeric.get_line_edit().release_focus()
	# Hidden/headless editor docks need not own OS focus. Exercise the exact native
	# normalization + focus signal sequence as well, without claiming manual input.
	numeric.value = 0
	numeric.get_line_edit().focus_exited.emit()
	await get_tree().process_frame
	check(editor.get("draft").text == "-1", "central numeric focus loss retains raw invalid draft")
	manager.call("apply_value")
	check(cue.output_channel == 8 and second.output_channel == 8, "central focus loss cannot clamp invalid input into accepted edit")
	numeric.get_line_edit().grab_focus()
	author_number(editor, "8.5")
	numeric.get_line_edit().release_focus()
	numeric.value = 9
	numeric.get_line_edit().focus_exited.emit()
	await get_tree().process_frame
	manager.call("apply_value")
	check(cue.output_channel == 8 and second.output_channel == 8 and editor.get("draft").text == "8.5", "central integer focus loss cannot round fractional draft into accepted edit")
	author_number(editor, "nan")
	manager.call("apply_value")
	check(cue.output_channel == 8 and second.output_channel == 8, "central numeric text rejects nonfinite input")
	author_number(editor, "12")
	numeric.value = 12
	var step_key := InputEventKey.new()
	step_key.keycode = KEY_UP
	step_key.pressed = true
	numeric.get_line_edit().gui_input.emit(step_key)
	numeric.value = 13
	manager.call("apply_value")
	check(cue.output_channel == 13 and second.output_channel == 13, "central numeric step signal remains authorable after raw text")
	undo.undo()
	manager.call("refresh")
	editor = manager.get("value_editor")
	author_number(editor, "11")
	manager.call("refresh")
	check(manager.get("value_editor") == editor and manager.get("draft_authored"), "central refresh retains compatible typed draft")
	var history := (plugin as EditorPlugin).get_undo_redo()
	history.create_action("Unrelated visibility", UndoRedo.MERGE_DISABLE, fixture)
	history.add_do_property(hidden, "visible", true)
	history.add_undo_property(hidden, "visible", false)
	history.commit_action()
	undo.undo()
	manager.call("refresh")
	check(manager.get("value_editor") == editor and editor.get("draft").text == "11", "central unrelated history retains bound draft and property")
	select_property(manager, "loop")
	check("cancelled" in manager.get("status").text, "central property switch visibly cancels draft")
	cue.loop = false
	second.loop = true
	manager.call("show_value")
	editor = manager.get("value_editor")
	check(editor.get("controls")[0] is CheckBox and "Mixed" in editor.get("hint").text, "central mixed bool has checkbox and mixed indicator")
	manager.call("apply_value")
	check(not cue.loop and second.loop, "central mixed checkbox opening does not overwrite")
	editor.get("controls")[0].button_pressed = true
	manager.call("apply_value")
	check(cue.loop and second.loop, "central checkbox authors bool without syntax")
	undo.undo()
	editor = select_property(manager, "source_path")
	check(editor.get("file_dialog") is EditorFileDialog and "*.wav" in editor.get("file_dialog").filters[0], "central file picker uses export filter")
	editor.call("choose_file", "res://draft-only.wav")
	check(cue.source_path.is_empty() and second.source_path.is_empty(), "central file picker result is draft only")
	manager.call("apply_value")
	check(cue.source_path == "res://draft-only.wav" and second.source_path == cue.source_path, "central file picker drafts apply via typed helper")
	undo.undo()
	editor = select_property(manager, "replay_delay_seconds")
	check(editor.get("controls")[0].allow_greater, "central range SpinBox respects or_greater")
	author_number(editor, "7201.5")
	manager.call("apply_value")
	check(cue.replay_delay_seconds == 7201.5 and second.replay_delay_seconds == 7201.5, "central replay permits longer than one hour")
	undo.undo()
	cue.replay_delay_max = 100.0
	second.replay_delay_max = 5.0
	editor = select_property(manager, "replay_delay_min")
	author_number(editor, "10")
	manager.call("apply_value")
	check(cue.replay_delay_min == 0.0 and second.replay_delay_min == 0.0, "central semantic min max validates every target atomically")
	cue.replay_delay_max = 2.5
	second.replay_delay_max = 2.5
	manager.get("kind").select(4)
	manager.call("refresh_properties")
	manager.call("attach", bulk, types.Manager)
	var other: Node = manager.call("component", hidden, types.Manager)
	editor = select_property(manager, "adm_mode")
	var options: OptionButton = editor.get("controls")[0]
	check(options.get_item_text(0) == "XYZ" and options.get_item_text(2) == "Both", "central enum UI displays export labels")
	options.select(2)
	options.item_selected.emit(2)
	manager.call("apply_value")
	check(runtime_manager.adm_mode == 2 and other.adm_mode == 2, "central enum label applies numeric export")
	undo.undo()
	manager.call("edit_property", "adm_mode", 99)
	check(runtime_manager.adm_mode == 0 and other.adm_mode == 0, "central invalid enum rejects atomically")
	manager.call("edit_property", "spatial_input_port", 65536)
	check(runtime_manager.spatial_input_port == 8100 and other.spatial_input_port == 8100, "central invalid port range rejects atomically")
	editor = select_property(manager, "cue_paths")
	check(editor.get("controls")[0] is Label, "central NodePath array uses scene selection controls")
	editor.call("choose_nodes", [cue, second])
	check(runtime_manager.cue_paths.is_empty() and other.cue_paths.is_empty(), "central node array selection is draft only")
	manager.call("apply_value")
	check(runtime_manager.cue_paths == [runtime_manager.get_path_to(cue), runtime_manager.get_path_to(second)] and other.cue_paths == [other.get_path_to(cue), other.get_path_to(second)], "central node arrays compute paths relative to each real component")
	check(runtime_manager.get_node(runtime_manager.cue_paths[1]) == second and other.get_node(other.cue_paths[0]) == cue, "central node array UI conversion resolves correct nodes")
	editor = manager.get("value_editor")
	editor.call("choose_nodes", [])
	manager.call("apply_value")
	check(runtime_manager.cue_paths.is_empty() and other.cue_paths.is_empty(), "central node array clear is explicit")
	editor = manager.get("value_editor")
	var deleted := Node.new()
	fixture.add_child(deleted)
	deleted.owner = fixture
	editor.call("choose_nodes", [cue, deleted])
	deleted.free()
	manager.call("apply_value")
	check(runtime_manager.cue_paths.is_empty() and other.cue_paths.is_empty(), "central stale node array selection rejects all targets")
	editor = select_property(manager, "stage_path")
	editor.call("choose_nodes", [plain])
	manager.call("apply_value")
	check(runtime_manager.stage_path == runtime_manager.get_path_to(plain) and other.stage_path == other.get_path_to(plain), "central single NodePath computes per target relative paths")
	undo.undo()
	manager.get("kind").select(3)
	manager.call("refresh_properties")
	manager.call("attach", bulk, types.Stage)
	var stage: Node = manager.call("component", plain, types.Stage)
	var stage2: Node = manager.call("component", hidden, types.Stage)
	stage2.dimensions_meters = Vector3(20, 30, 40)
	editor = select_property(manager, "dimensions_meters")
	check(editor.get("controls").size() == 3 and editor.get("controls")[1] is SpinBox, "central vector exports create numeric axis fields")
	author_number(editor, "25", 0)
	manager.call("apply_value")
	check(stage.dimensions_meters == Vector3(25, 18, 6) and stage2.dimensions_meters == Vector3(25, 30, 40), "central mixed vector edit preserves untouched per target axes")
	undo.undo()
	editor = manager.get("value_editor")
	author_number(editor, "-1", 2)
	manager.call("apply_value")
	check(stage.dimensions_meters.z == 6 and stage2.dimensions_meters.z == 40, "central rejects invalid dimensions atomically")
	# Reverse selection [C,B,A], with untouched D, must restore original [A,B,C,D].
	var siblings: Array[Node] = []
	for label in ["A", "B", "C", "D"]:
		var sibling: Node = types.Stage.new()
		sibling.name = label
		fixture.add_child(sibling)
		sibling.owner = fixture
		siblings.append(sibling)
	var indices: Array[int] = []
	for sibling in siblings:
		indices.append(sibling.get_index())
	var reversed_selection: Array[Node] = [siblings[2], siblings[1], siblings[0]]
	manager.set("chosen", reversed_selection)
	manager.call("remove_selected")
	undo.undo()
	var ordered := true
	for i in siblings.size():
		ordered = ordered and siblings[i].get_index() == indices[i] and siblings[i].owner == fixture
	check(ordered, "central reversed A B C removal Undo restores ascending original siblings")
	undo.redo()
	undo.undo()
	ordered = true
	for i in siblings.size():
		ordered = ordered and siblings[i].get_index() == indices[i]
	check(ordered, "central reversed sibling restoration survives redo Undo")
	# Same-type target-set switch cannot leak a previous draft.
	manager.set("chosen", bulk)
	manager.get("kind").select(0)
	manager.call("refresh_properties")
	editor = select_property(manager, "output_channel")
	author_number(editor, "17")
	var single: Array[Node] = [plain]
	manager.set("chosen", single)
	manager.call("refresh")
	check(not manager.get("draft_authored") and "cancelled" in manager.get("status").text, "central target set change cancels draft visibly")
	manager.call("apply_value")
	check(cue.output_channel == 8 and second.output_channel == 8, "central cancelled draft cannot apply to different targets")
	# Debounced filter uses cached rows and never rebuilds a pending typed editor.
	editor = select_property(manager, "output_channel")
	author_number(editor, "19")
	manager.get("search").text = "Ordinary"
	manager.get("search").text_changed.emit("Ordinary")
	await get_tree().create_timer(0.25).timeout
	check(manager.get("value_editor") == editor and manager.get("draft_authored"), "central debounced filter retains draft without scene refresh")
	manager.get("search").text = ""
	manager.set("chosen", bulk)
	manager.call("filter_rows")
	check(manager.get("nodes").get_selected_items().size() == bulk.size(), "central cached membership filtering preserves every selected row")
	manager.set("chosen", single)
	manager.call("filter_rows")
	select_property(manager, "persistent_key")
	var property_editor = preload("res://addons/spatial_fabric/editor/scene_property_editor.gd")
	var lesser := property_editor.new()
	manager.add_child(lesser)
	var metadata := {"name": "test", "type": TYPE_FLOAT, "hint": PROPERTY_HINT_RANGE, "hint_string": "0,10,0.1,or_lesser"}
	lesser.setup(metadata, 0.0, false)
	check(lesser.controls[0].allow_lesser and not lesser.controls[0].allow_greater and property_editor.validate(metadata, -50.0).is_empty() and not property_editor.validate(metadata, 11.0).is_empty(), "central metadata range honors or_lesser without invented lower cap")
	lesser.queue_free()
	check(manager.get_parent() is ScrollContainer and manager.get_parent().horizontal_scroll_mode == ScrollContainer.SCROLL_MODE_DISABLED, "central typed dock has vertical scrolling")

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
		invalid.output_channel = -1
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
		await preload("res://Tests/Godot/audio_routing_editor_tests.gd").new().run(plugin, check, report_path.get_base_dir())
		await central_manager_tests(plugin)
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
