@tool
extends RefCounted
const Cache = preload("res://addons/spatial_fabric/editor/audio_interface_cache.gd")
const Grid = preload("res://addons/spatial_fabric/editor/audio_routing_grid.gd")
const Policy = preload("res://addons/spatial_fabric/editor/routing_policy.gd")

func inventory(entries: Array) -> Dictionary:
	return {"ok": true, "json": JSON.stringify(entries), "error": ""}

func endpoint(id := "endpoint-A", capacity := 4) -> Dictionary:
	return {"id": id, "name": "Studio output", "channels": capacity, "sample_rate": 48000}

func mouse(grid: Control, point: Vector2, down: bool) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.position = point
	event.pressed = down
	grid.body.gui_input.emit(event)

func run(plugin: Node, check: Callable, evidence_dir: String) -> void:
	var panel: Node = plugin.routing_panel
	var original_cache: RefCounted = panel.cache
	var path := evidence_dir.path_join("audio-interface-fixture.json")
	var cache := Cache.new()
	cache.load_history(path)
	check.call(cache.devices.is_empty() and not FileAccess.file_exists(path), "routing cache load is offline and read only")
	check.call(cache.accept(inventory([endpoint()])), "routing accepts actual Godot native JSON array schema")
	var disk := FileAccess.get_file_as_string(path)
	check.call(not disk.contains("online") and disk.contains("last_seen") and not disk.contains("cue"), "routing cache persists bounded inventory only")
	var loaded := Cache.new()
	loaded.load_history(path)
	check.call(loaded.devices.size() == 1 and not loaded.devices[0].online, "routing cache reload never claims online")
	check.call(not cache.accept({"ok": false, "json": JSON.stringify([endpoint()]), "error": "stale"}) and not cache.devices[0].online and FileAccess.get_file_as_string(path) == disk, "routing stale failed refresh preserves disk and marks offline")
	check.call(not cache.accept(inventory([endpoint(), endpoint()])), "routing duplicate exact IDs reject whole inventory")
	var oversized := endpoint()
	oversized.extra = "界".repeat(Cache.MAX_BYTES >> 1)
	var oversized_result := inventory([oversized])
	check.call(oversized_result.json.length() < Cache.MAX_BYTES and oversized_result.json.to_utf8_buffer().size() > Cache.MAX_BYTES and not cache.accept(oversized_result) and cache.devices.size() == 1 and FileAccess.get_file_as_string(path) == disk, "routing incoming inventory bound counts UTF8 bytes and preserves history")
	check.call(not cache.accept(inventory([endpoint("", 2)])) and not cache.accept(inventory([endpoint("bad", 4097)])), "routing cache rejects empty IDs and excessive channel bounds")
	var malformed := endpoint("control\nID")
	check.call(not cache.accept(inventory([malformed])) and not cache.accept({"ok": true, "json": JSON.stringify([endpoint()]), "error": "stale cached result"}), "routing control IDs and successful stale error envelope rejected")
	malformed = endpoint()
	malformed.channels = 1.5
	check.call(not cache.accept(inventory([malformed])), "routing fractional capacity cannot fabricate channels")
	var full := Cache.new()
	full.load_history(evidence_dir.path_join("audio-full.json"))
	var many: Array = []
	for index in Cache.MAX_DEVICES:
		many.append(endpoint("id-" + str(index)))
	check.call(full.accept(inventory(many)) and not full.accept(inventory([endpoint("new-id")])) and full.devices.size() == Cache.MAX_DEVICES, "routing full bounded history rejects refresh without evicting offline endpoints")
	check.call(not cache.accept({"ok": true, "json": "{}"}) and not cache.accept(inventory([{"id": "bad", "name": "Bad", "channels": 2}])), "routing malformed or missing native fields fail closed")
	check.call(cache.accept(inventory([])) and cache.devices.size() == 1 and not cache.devices[0].online, "routing missing interface preserves offline history")
	var last_seen: String = cache.devices[0].last_seen
	check.call(cache.accept(inventory([endpoint("endpoint-B", 2)])) and cache.devices.size() == 2 and cache.devices[1].last_seen == last_seen, "routing successful refresh merges history without eviction")
	check.call(cache.accept(inventory([endpoint()])) and cache.devices[0].online and not cache.devices[1].online, "routing exact ID reconnect restores session online only")
	var invalid_path := evidence_dir.path_join("audio-invalid.json")
	var invalid := FileAccess.open(invalid_path, FileAccess.WRITE)
	invalid.store_string('{"version":99,"devices":[]}')
	invalid.close()
	loaded.load_history(invalid_path)
	check.call(loaded.devices.is_empty() and loaded.last_error.contains("schema"), "routing unsupported cache version ignored")
	var calls := [0]
	panel.cache = cache
	panel.inventory_provider = func():
		calls[0] += 1
		return inventory([endpoint()])
	plugin._refresh()
	panel.choose(panel.chosen)
	check.call(calls[0] == 0, "routing construction refresh and selectors never implicitly enumerate")
	check.call(panel.refresh_interfaces() and calls[0] == 1, "routing explicit Refresh Interfaces invokes inventory once")
	var scene := EditorInterface.get_edited_scene_root()
	var cue := scene.get_node("Mono") as SpatialFabricPlaybackCue
	var sibling := scene.get_node("Stereo") as SpatialFabricPlaybackCue
	var old_device := cue.device_id
	var old_channel := cue.output_channel
	var other_channel := sibling.output_channel
	var source := cue.source_path
	cue.visible = false
	plugin._refresh()
	check.call(panel.rows.size() == 3 and panel.rows.any(func(row: Dictionary): return row.cue == cue), "routing rows include inactive hidden edited scene playback cues")
	var tabs: TabContainer = panel.get_parent()
	var ancestor: Node = panel
	while ancestor.get_parent() != null:
		if ancestor.get_parent() is TabContainer:
			var ancestor_tabs := ancestor.get_parent() as TabContainer
			ancestor_tabs.current_tab = ancestor_tabs.get_tab_idx_from_control(ancestor)
		ancestor = ancestor.get_parent()
	tabs.current_tab = tabs.get_tab_idx_from_control(panel)
	await plugin.get_tree().process_frame
	check.call(panel.visible and tabs.get_child(0).name == "Scene Objects" and tabs.get_child(2).name == "Routing CSV", "routing dedicated grid tab preserves Scene Objects and CSV")
	check.call(panel.assign(cue, "endpoint-A", 99) and cue.device_id == "endpoint-A" and cue.output_channel == 99 and cue.source_path == source and sibling.output_channel == other_channel, "routing one action changes exact cue real route properties only")
	var history: EditorUndoRedoManager = plugin.get_undo_redo()
	var undo := history.get_history_undo_redo(history.get_object_history_id(cue))
	undo.undo()
	check.call(cue.device_id == old_device and cue.output_channel == old_channel, "routing route Undo restores both original properties")
	undo.redo()
	check.call(cue.device_id == "endpoint-A" and cue.output_channel == 99, "routing route Redo restores both configured properties")
	panel.choose(cue)
	check.call(panel.channels.get_item_metadata(panel.channels.selected) == 99 and panel.channels.get_item_text(panel.channels.selected).contains("stored"), "routing dropdown preserves stored out of range channel")
	var b_index := -1
	for index in panel.interfaces.item_count:
		if panel.interfaces.get_item_metadata(index) == "endpoint-B":
			b_index = index
	panel.interfaces.item_selected.emit(b_index)
	check.call(cue.device_id == "endpoint-B" and cue.output_channel == 99, "routing real interface dropdown signal does not clamp channel")
	panel.channels.item_selected.emit(1)
	check.call(cue.output_channel == 1, "routing real channel dropdown signal authors first source destination")
	var file_path := "res://Tests/Godot/routing-persistence.tscn"
	var packed := PackedScene.new()
	check.call(packed.pack(scene) == OK and ResourceSaver.save(packed, file_path) == OK, "routing configured scene packs and saves")
	var persisted := (load(file_path) as PackedScene).instantiate()
	check.call(persisted.get_node("Mono").device_id == "endpoint-B" and persisted.get_node("Mono").output_channel == 1, "routing route survives PackedScene reload")
	persisted.free()
	cue._playing = true
	check.call(not panel.assign(cue, "blocked", 2), "routing fresh guard rejects active playback")
	cue._playing = false
	cue._replay_remaining = 1.0
	check.call(not panel.assign(cue, "blocked", 2), "routing fresh guard rejects pending replay")
	cue._replay_remaining = -1.0
	cue._start_pending = true
	check.call(not panel.assign(cue, "blocked", 2), "routing fresh guard rejects starting worker")
	cue._start_pending = false
	var foreign := SpatialFabricPlaybackCue.new()
	check.call(not panel.assign(foreign, "blocked", 2), "routing fresh guard rejects foreign transient cue")
	foreign.free()
	var external := (load(file_path) as PackedScene).instantiate()
	scene.add_child(external)
	external.owner = scene
	check.call(not panel.assign(external.get_node("Mono"), "blocked", 2), "routing fresh guard rejects external packed content")
	scene.remove_child(external)
	external.free()
	plugin._refresh()
	panel.choose(cue)
	var grid: Control = panel.grid
	grid.horizontal.value = 0
	grid.vertical.value = 0
	var cue_row := 0
	for index in grid.rows.size():
		if grid.rows[index].cue == cue:
			cue_row = index
	var point := Vector2(10, cue_row * Grid.ROW + 10)
	mouse(grid, point, true)
	mouse(grid, point, false)
	check.call(cue.device_id == "" and cue.output_channel == 0, "routing actual grid GUI signals assign dynamic default crosspoint")
	undo.undo()
	check.call(cue.device_id == "endpoint-B" and cue.output_channel == 1, "routing grid crosspoint mutation uses editor Undo")
	plugin._refresh()
	await plugin.get_tree().process_frame
	var viewport := grid.get_viewport()
	for down in [true, false]:
		var native_event := InputEventMouseButton.new()
		native_event.button_index = MOUSE_BUTTON_LEFT
		native_event.pressed = down
		native_event.position = grid.body.get_global_transform_with_canvas() * point
		native_event.global_position = native_event.position
		viewport.push_input(native_event, true)
		await plugin.get_tree().process_frame
	check.call(cue.device_id == "" and cue.output_channel == 0, "routing native viewport mouse dispatch reaches crosspoint")
	undo.undo()
	plugin._refresh()
	var before := [cue.device_id, cue.output_channel]
	var saved_history := undo.get_version()
	check.call(not panel.assign(cue, cue.device_id, cue.output_channel) and undo.get_version() == saved_history, "routing clicking configured route is a no op not a disconnect")
	panel.inventory_provider = func(): return {"ok": false, "error": "unplugged"}
	var disk_before := FileAccess.get_file_as_string(path)
	check.call(not panel.refresh_interfaces() and [cue.device_id, cue.output_channel] == before and FileAccess.get_file_as_string(path) == disk_before, "routing failed explicit refresh preserves all cue routes and persisted history")
	mouse(grid, Vector2(-1, 10), true)
	mouse(grid, Vector2(-1, 10), false)
	check.call([cue.device_id, cue.output_channel] == before and grid.hit(Vector2(grid.body.size.x + 1, 0)).is_empty(), "routing clipped viewport rejects outside clicks")
	for down in [true, false]:
		var outside := InputEventMouseButton.new()
		outside.button_index = MOUSE_BUTTON_LEFT
		outside.pressed = down
		outside.position = grid.body.get_global_transform_with_canvas() * Vector2(-2, 10)
		outside.global_position = outside.position
		viewport.push_input(outside, true)
		await plugin.get_tree().process_frame
	check.call([cue.device_id, cue.output_channel] == before, "routing native viewport excludes sticky row header from route hit targets")
	mouse(grid, point, true)
	cue._replay_remaining = 0.5
	mouse(grid, point, false)
	check.call([cue.device_id, cue.output_channel] == before, "routing mouse release revalidates live guard after press")
	cue._replay_remaining = -1
	panel.assign(cue, "unknown-exact-ID", 7000)
	panel.choose(cue)
	check.call(panel.channels.item_count == 2 and panel.channels.get_item_metadata(1) == 7000 and panel.interfaces.get_item_text(panel.interfaces.selected).contains("UNKNOWN"), "routing unknown endpoint exposes Auto and stored channel without fabricated capacity")
	check.call(grid.groups[0].id == "" and grid.groups[0].capacity == 0, "routing dynamic default remains separate with unknown capacity")
	plugin._select_index(plugin.cues.find(cue))
	# SpinBox updates its native LineEdit on the next editor frame, like a real
	# selection followed by an Apply click; don't apply an unpainted draft.
	await plugin.get_tree().process_frame
	check.call(plugin.fields.output_channel.value == 7000, "routing CSV draft preserves grid channels above 256")
	var original_loop: bool = cue.loop
	plugin.fields.loop.button_pressed = not original_loop
	plugin._apply()
	check.call(cue.output_channel == 7000 and cue.loop != original_loop, "routing unrelated CSV draft edit preserves stored grid channel")
	undo.undo()
	check.call(cue.output_channel == 7000 and cue.loop == original_loop, "routing CSV draft Undo preserves original high channel")
	var parsed := Policy.import_csv(Policy.export_csv([plugin._snapshot(cue)]))
	check.call(parsed.rows.size() == 1 and parsed.rows[0].output_channel == 7000, "routing high grid channel survives CSV roundtrip")
	check.call(not panel.assign(cue, "unknown-exact-ID", 2147483648) and cue.output_channel == 7000, "routing rejects channels beyond native int32 without changing stored route")
	await plugin.get_tree().process_frame
	var control_count := grid.get_child_count()
	var synthetic: Array = []
	for i in 10000:
		synthetic.append({"cue": cue, "name": "Cue", "device": "large", "channel": 4096, "reason": "", "path": "Cue"})
	grid.capture(synthetic, [{"id": "large", "name": "Large", "channels": 4096, "online": false}])
	check.call(grid.get_child_count() == control_count and grid.groups.size() == 2 and grid.count == 4098 and grid.column(4097).channel == 4096, "routing large matrix uses compact groups and constant native control count")
	grid.horizontal.value = grid.horizontal.max_value
	check.call(grid.horizontal.value > 0 and grid.top.position.y == 0 and grid.left.position.x == 0 and grid.body.clip_contents, "routing both axes scroll with independent clipped sticky headers")
	grid.vertical.value = 0
	var wheel := InputEventMouseButton.new()
	wheel.button_index = MOUSE_BUTTON_WHEEL_UP
	wheel.pressed = true
	grid._wheel(wheel)
	check.call(grid.vertical.value == 0, "routing wheel at boundary leaves offset unchanged")
	await plugin.get_tree().process_frame
	var ancestor_wheels := [0]
	var observe_wheel := func(event: InputEvent):
		if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			ancestor_wheels[0] += 1
	panel.gui_input.connect(observe_wheel)
	wheel.position = grid.body.get_global_transform_with_canvas() * Vector2(10, 10)
	wheel.global_position = wheel.position
	viewport.push_input(wheel, true)
	check.call(ancestor_wheels[0] == 1 and grid.vertical.value == 0, "routing native wheel at boundary propagates to ancestor")
	wheel.button_index = MOUSE_BUTTON_WHEEL_DOWN
	viewport.push_input(wheel, true)
	check.call(ancestor_wheels[0] == 1 and grid.vertical.value > 0, "routing native wheel with movement is consumed before ancestor")
	panel.gui_input.disconnect(observe_wheel)
	panel.assign(cue, old_device, old_channel)
	cue.loop = original_loop
	cue.visible = true
	panel.cache = original_cache
	panel.inventory_provider = Callable()
	plugin._refresh()
	check.call(cue._player == null and sibling._player == null and not cue.is_prepared() and calls[0] == 1, "routing entire UI lifecycle never prepares plays captures or polls inventory")
	tabs.current_tab = 0
