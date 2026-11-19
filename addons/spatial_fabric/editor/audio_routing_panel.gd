@tool
extends VBoxContainer
const Cache = preload("res://addons/spatial_fabric/editor/audio_interface_cache.gd")
const Grid = preload("res://addons/spatial_fabric/editor/audio_routing_grid.gd")
var cache := Cache.new()
var plugin: EditorPlugin
var grid: Control
var cue_selector := OptionButton.new()
var interfaces := OptionButton.new()
var channels := OptionButton.new()
var status := Label.new()
var chosen: Node
var rows: Array = []
var inventory_provider: Callable

func setup(editor_plugin: EditorPlugin) -> void:
	plugin = editor_plugin
	# Project-specific editor metadata directory, outside project.godot and scenes.
	cache.load_history(EditorInterface.get_editor_paths().get_project_settings_dir().path_join("spatialfabric_audio_interfaces_v1.json"))
	var refresh_button := Button.new()
	refresh_button.text = "Refresh Interfaces"
	refresh_button.pressed.connect(refresh_interfaces)
	add_child(refresh_button)
	var scene_button := Button.new()
	scene_button.text = "Refresh scene cues"
	scene_button.pressed.connect(plugin._refresh)
	add_child(scene_button)
	var help := Label.new()
	help.text = "Checks = configured, not live. One route per cue.\nAuto 0: corresponding source channels.\n1+: first source → 1-based output. *: stored / unverified.\nShift + wheel: horizontal scroll. Click row to use selectors."
	help.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(help)
	var selectors := [cue_selector, interfaces, channels]
	var labels := ["Playback cue", "Audio interface", "Output channel"]
	for index in selectors.size():
		var field := HBoxContainer.new()
		var caption := Label.new()
		caption.text = labels[index]
		caption.custom_minimum_size.x = 96
		field.add_child(caption)
		var selector: OptionButton = selectors[index]
		selector.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		selector.fit_to_longest_item = false
		field.add_child(selector)
		add_child(field)
	cue_selector.item_selected.connect(func(index: int): choose(rows[index].cue))
	interfaces.item_selected.connect(func(index: int):
		if is_instance_valid(chosen):
			assign(chosen, str(interfaces.get_item_metadata(index)), chosen.output_channel))
	channels.item_selected.connect(func(index: int):
		if is_instance_valid(chosen):
			assign(chosen, chosen.device_id, int(channels.get_item_metadata(index))))
	grid = Grid.new()
	add_child(grid)
	grid.row_selected.connect(choose)
	grid.route_requested.connect(assign)
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)

func refresh() -> void:
	if grid == null:
		return
	rows.clear()
	cue_selector.clear()
	# Reuse the central manager's linear scene/protection cache, including inactive cues.
	var manager: Node = plugin.object_manager
	for node in manager.membership:
		if is_instance_valid(node) and node is SpatialFabricPlaybackCue:
			var why := guard(node, true)
			rows.append({"cue": node, "name": str(node.name), "device": node.device_id, "channel": node.output_channel, "reason": why, "path": str(manager.root().get_path_to(node))})
			cue_selector.add_item(str(manager.root().get_path_to(node)))
			cue_selector.set_item_tooltip(cue_selector.item_count - 1, why)
	if not is_instance_valid(chosen) or not manager.membership.has(chosen):
		chosen = rows[0].cue if not rows.is_empty() else null
	grid.capture(rows, cache.devices)
	choose(chosen)

func choose(cue: Node) -> void:
	chosen = cue
	interfaces.clear()
	channels.clear()
	if not is_instance_valid(cue):
		interfaces.disabled = true
		channels.disabled = true
		status.text = "No playback cues in the edited scene. " + cache.last_error
		return
	for index in rows.size():
		if rows[index].cue == cue:
			cue_selector.select(index)
	var ids := {"": true}
	interfaces.add_item("Dynamic OS default (capacity unknown)")
	interfaces.set_item_metadata(0, "")
	var capacity := 0
	for entry in cache.devices:
		ids[entry.id] = true
		interfaces.add_item("%s [%s] · %d ch%s" % [entry.name, entry.id, entry.channels, "" if entry.online else " · OFFLINE / cached"])
		interfaces.set_item_metadata(interfaces.item_count - 1, entry.id)
		interfaces.set_item_tooltip(interfaces.item_count - 1, "%s\n%d Hz · last seen %s" % [entry.id, entry.sample_rate, entry.last_seen])
		if entry.id == cue.device_id:
			capacity = entry.channels
	if not ids.has(cue.device_id):
		interfaces.add_item(cue.device_id + " · UNKNOWN / offline")
		interfaces.set_item_metadata(interfaces.item_count - 1, cue.device_id)
	for index in interfaces.item_count:
		if interfaces.get_item_metadata(index) == cue.device_id:
			interfaces.select(index)
	for channel in capacity + 1:
		channels.add_item("Auto 0 — corresponding source channels" if channel == 0 else "Output %d — first source channel" % channel)
		channels.set_item_metadata(channels.item_count - 1, channel)
	if cue.output_channel > capacity or cue.output_channel < 0:
		channels.add_item("%d — stored / capacity unverified" % cue.output_channel)
		channels.set_item_metadata(channels.item_count - 1, cue.output_channel)
	for index in channels.item_count:
		if channels.get_item_metadata(index) == cue.output_channel:
			channels.select(index)
	var why := guard(cue, true)
	interfaces.disabled = not why.is_empty()
	channels.disabled = not why.is_empty()
	status.text = (why + "\n" if not why.is_empty() else "") + ("Last explicit refresh succeeded (not continuous monitoring)." if cache.last_error.is_empty() else cache.last_error)

func guard(cue: Node, cached := false) -> String:
	if not Engine.is_editor_hint() or EditorInterface.is_playing_scene():
		return "Routing requires a stopped editor."
	if not is_instance_valid(cue) or not cue is SpatialFabricPlaybackCue:
		return "Cue is missing."
	if cue.is_playing() or cue.replay_pending() or cue._start_pending or cue._player != null:
		return "Stop cue / pending replay before routing (native worker retained)."
	return plugin.object_manager.reason(cue, cached)

func assign(cue: Node, device: String, channel: int) -> bool:
	var why := guard(cue) # Always rebuild scene protection at mutation, never trust painted rows.
	if not why.is_empty():
		status.text = why
		return false
	if channel < 0 or channel > 2147483647 or not Cache.valid_text(device):
		status.text = "Invalid route ID/channel."
		return false
	if cue.device_id == device and cue.output_channel == channel:
		return false
	var history := plugin.get_undo_redo()
	history.create_action("Assign audio output route", UndoRedo.MERGE_DISABLE, cue)
	history.add_do_property(cue, "device_id", device)
	history.add_do_property(cue, "output_channel", channel)
	history.add_undo_property(cue, "device_id", cue.device_id)
	history.add_undo_property(cue, "output_channel", cue.output_channel)
	history.commit_action()
	refresh()
	return true

func refresh_interfaces() -> bool:
	var result: Dictionary = {"ok": false, "error": "Native extension unavailable."}
	if inventory_provider.is_valid():
		result = inventory_provider.call()
	elif ClassDB.class_exists("SFNativePlayer"):
		# The only automatic-free native boundary: static inventory, no player instance.
		result = ClassDB.class_call_static("SFNativePlayer", "devices_json")
	var accepted := cache.accept(result)
	refresh()
	return accepted
