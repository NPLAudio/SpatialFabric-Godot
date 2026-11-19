@tool
extends EditorPlugin
## Authoring only: never prepares sources, starts streams, or opens network sockets.
const Policy = preload("res://addons/spatial_fabric/editor/routing_policy.gd")

var dock: VBoxContainer
var report: TextEdit
var diagnostics: TextEdit
var cue_list: ItemList
var fields: Dictionary = {}
var cues: Array[Node] = []
var selected: Node
var latency: Label
var source_dialog: FileDialog
var import_dialog: FileDialog
var export_dialog: FileDialog
var source_target_id: int = 0
var file_scene_id: int = 0
var device_labels: Dictionary = {}
var committing := false
var object_manager: VBoxContainer
var routing_panel: VBoxContainer

func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "SpatialFabric"
	dock.custom_minimum_size.x = 320
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock.add_child(tabs)
	object_manager = preload("res://addons/spatial_fabric/editor/scene_object_manager.gd").new()
	var object_scroll := ScrollContainer.new()
	object_scroll.name = "Scene Objects"
	object_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	tabs.add_child(object_scroll)
	object_manager.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	object_scroll.add_child(object_manager)
	object_manager.setup(self)
	routing_panel = preload("res://addons/spatial_fabric/editor/audio_routing_panel.gd").new()
	routing_panel.name = "Routing Grid"
	tabs.add_child(routing_panel)
	routing_panel.setup(self)
	var authoring := VBoxContainer.new()
	authoring.name = "Routing CSV"
	tabs.add_child(authoring)
	_build_routing(authoring)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)
	scene_changed.connect(_scene_changed)
	get_undo_redo().version_changed.connect(_history_changed)
	_refresh()

func _build_routing(dock: VBoxContainer) -> void:
	var title := Label.new()
	title.text = "Cue authoring (no playback / network)"
	dock.add_child(title)
	_button(dock, "Refresh scene cues / discard draft", _refresh)
	cue_list = ItemList.new()
	cue_list.custom_minimum_size.y = 100
	cue_list.item_selected.connect(_select_index)
	dock.add_child(cue_list)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 300
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	dock.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(grid)
	for key in Policy.COLUMNS:
		if key == "node_path":
			continue
		var label := Label.new()
		label.text = key
		grid.add_child(label)
		var control: Control
		if key in Policy.BOOL_FIELDS:
			control = CheckBox.new()
		elif key in Policy.INT_FIELDS or key in Policy.FLOAT_FIELDS:
			var spin := SpinBox.new()
			spin.min_value = 5 if key == "buffer_ms" else 0
			spin.max_value = 500 if key == "buffer_ms" else (2147483647 if key == "output_channel" else 3600)
			spin.allow_greater = key in Policy.FLOAT_FIELDS
			spin.step = 1 if key in Policy.INT_FIELDS else 0.01
			control = spin
		else:
			control = LineEdit.new()
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(control)
		fields[key] = control
	_button(dock, "Choose source WAV (draft only)", _choose_source)
	_button(dock, "Refresh Interfaces (see Routing Grid)", _inventory)
	latency = Label.new()
	dock.add_child(latency)
	_button(dock, "Apply draft to selected cue", _apply)
	_button(dock, "Export scene cues CSV…", _choose_export)
	_button(dock, "Import CSV / apply valid rows…", _choose_import)
	diagnostics = TextEdit.new()
	diagnostics.editable = false
	diagnostics.custom_minimum_size.y = 110
	dock.add_child(diagnostics)
	_button(dock, "Inspect edited scene JSON (no I/O)", _inspect_scene)
	report = TextEdit.new()
	report.editable = false
	report.custom_minimum_size = Vector2(280, 110)
	dock.add_child(report)
	source_dialog = _dialog(FileDialog.FILE_MODE_OPEN_FILE, "*.wav ; WAV source")
	source_dialog.file_selected.connect(_source_chosen)
	import_dialog = _dialog(FileDialog.FILE_MODE_OPEN_FILE, "*.csv ; Routing CSV")
	import_dialog.file_selected.connect(_import_csv)
	export_dialog = _dialog(FileDialog.FILE_MODE_SAVE_FILE, "*.csv ; Routing CSV")
	export_dialog.file_selected.connect(_export_csv)

func _button(parent: Node, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	parent.add_child(button)

func _dialog(mode: FileDialog.FileMode, filter: String) -> FileDialog:
	var dialog := FileDialog.new()
	dialog.file_mode = mode
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.filters = PackedStringArray([filter])
	dock.add_child(dialog)
	return dialog

func _scene_changed(_root: Node) -> void:
	selected = null
	_refresh()

func _history_changed() -> void:
	if not committing:
		_refresh.call_deferred()

func _scene_cues() -> Array[Node]:
	var result: Array[Node] = []
	var root := get_editor_interface().get_edited_scene_root()
	if root != null:
		_collect(root, result)
	return result

func _scene_routes() -> Array[Node]:
	var result: Array[Node] = []
	var root := get_editor_interface().get_edited_scene_root()
	if root != null:
		_collect(root, result, true)
	return result

func _collect(node: Node, result: Array[Node], include_live: bool = false) -> void:
	if node is SpatialFabricPlaybackCue or (include_live and node is SpatialFabricLiveInputCue):
		result.append(node)
	for child in node.get_children():
		_collect(child, result, include_live)

func _snapshot(cue: Node) -> Dictionary:
	var row := Policy.snapshot(cue)
	var root := get_editor_interface().get_edited_scene_root()
	row.node_path = str(root.get_path_to(cue))
	return row

func _refresh() -> void:
	if object_manager != null:
		object_manager.refresh()
	if routing_panel != null:
		routing_panel.refresh()
	cues = _scene_cues()
	cue_list.clear()
	var index := -1
	for cue in cues:
		cue_list.add_item(str(_snapshot(cue).node_path))
		if cue == selected:
			index = cue_list.item_count - 1
	if index < 0 and not cues.is_empty():
		index = 0
	selected = null
	if index >= 0:
		cue_list.select(index)
		_select_index(index)
	else:
		latency.text = "Latency: unavailable / no active stream"
	diagnostics.text = "\n".join(_osc_diagnostics({}))

func _select_index(index: int) -> void:
	if index < 0 or index >= cues.size() or not is_instance_valid(cues[index]):
		return
	selected = cues[index]
	var row := _snapshot(selected)
	for key in fields:
		var control: Control = fields[key]
		if control is CheckBox:
			control.button_pressed = row[key]
		elif control is SpinBox:
			control.value = row[key]
			# Hidden dock controls may not repaint their LineEdit before Apply.
			# Keep the editable text bound to this snapshot, not the previous cue.
			control.get_line_edit().text = str(row[key])
		else:
			control.text = str(row[key])
	var value: Variant = selected.get("output_latency_ms") if _has_property(selected, "output_latency_ms") else -1
	var mode: int = selected.get("output_mode") if _has_property(selected, "output_mode") else 0
	latency.text = "OSC: " + selected.effective_osc_base() + "\n" + ("OS output latency: %.2f ms" % float(value) if value != null and float(value) >= 0 else "OS output latency: unavailable / no active stream") + "\nOutput mode: " + ["inactive", "shared", "exclusive", "shared fallback"][clampi(mode, 0, 3)]

func _has_property(node: Node, key: String) -> bool:
	for property in node.get_property_list():
		if str(property.name) == key:
			return true
	return false

func _choose_source() -> void:
	if not is_instance_valid(selected) or selected not in _scene_cues():
		return
	source_target_id = selected.get_instance_id()
	source_dialog.popup_centered_ratio(0.7)

func _source_chosen(path: String) -> void:
	if is_instance_valid(selected) and selected in _scene_cues() and selected.get_instance_id() == source_target_id:
		fields.source_path.text = path

func _inventory() -> void:
	routing_panel.refresh_interfaces()
	device_labels.clear()
	for entry in routing_panel.cache.devices:
		device_labels[entry.id] = entry.name
	report.text = JSON.stringify(routing_panel.cache.devices, "\t")
	diagnostics.text = routing_panel.status.text

func _effective(cue: Node, overrides: Dictionary) -> String:
	if overrides.has(cue) and not str(overrides[cue].osc_base).is_empty():
		return str(overrides[cue].osc_base)
	if overrides.has(cue):
		return SpatialFabricPlaybackCue.derived_osc_base(cue, "playback")
	if cue.has_method("effective_osc_base"):
		return str(cue.call("effective_osc_base"))
	return str(cue.get("osc_base"))

func _osc_groups(overrides: Dictionary) -> Dictionary:
	var groups: Dictionary = {}
	for cue in _scene_routes():
		var address := _effective(cue, overrides)
		if not groups.has(address):
			groups[address] = []
		groups[address].append(cue)
	return groups

func _osc_diagnostics(overrides: Dictionary) -> PackedStringArray:
	var messages := PackedStringArray()
	var groups := _osc_groups(overrides)
	for address in groups:
		var paths := PackedStringArray()
		for cue in groups[address]:
			paths.append(str(get_editor_interface().get_edited_scene_root().get_path_to(cue)))
		if not Policy._valid_osc(address):
			messages.append("Invalid effective OSC '%s': %s" % [address, ", ".join(paths)])
		if groups[address].size() > 1:
			messages.append("Duplicate effective OSC '%s': %s" % [address, ", ".join(paths)])
		for child in groups:
			if child.begins_with(address + "/"):
				messages.append("Nested OSC '%s': the more-specific base owns matching commands over '%s'." % [child, address])
	return messages

func _apply() -> void:
	if not is_instance_valid(selected) or selected not in _scene_cues():
		diagnostics.text = "Select a cue in the current edited scene."
		return
	var row := _snapshot(selected)
	for key in fields:
		var control: Control = fields[key]
		if control is CheckBox:
			row[key] = control.button_pressed
		elif control is SpinBox:
			control.apply()
			row[key] = int(control.value) if key in Policy.INT_FIELDS else control.value
		else:
			row[key] = control.text
	_commit_rows([row], PackedStringArray(), "Apply SpatialFabric cue")

func _choose_import() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	file_scene_id = root.get_instance_id()
	import_dialog.popup_centered_ratio(0.7)

func _choose_export() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	file_scene_id = root.get_instance_id()
	export_dialog.popup_centered_ratio(0.7)

func _file_scene_valid() -> bool:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null or root.get_instance_id() != file_scene_id:
		diagnostics.text = "Edited scene changed while dialog was open; operation cancelled."
		return false
	return true

func _export_csv(path: String) -> void:
	if not _file_scene_valid():
		return
	var rows: Array = []
	var messages := _osc_diagnostics({})
	for cue in _scene_cues():
		var row := _snapshot(cue)
		for error in Policy.validate(row):
			messages.append("%s: %s" % [row.node_path, error])
		rows.append(row)
	var text := Policy.export_csv(rows)
	if text.is_empty():
		messages.append("Export rejected by routing policy (invalid rows or bounds).")
	else:
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file == null:
			messages.append("Cannot write CSV: %s" % error_string(FileAccess.get_open_error()))
		else:
			file.store_string(text)
			var error := file.get_error()
			file.close()
			messages.append("Exported %d scene cues." % rows.size() if error == OK else "CSV write failed: " + error_string(error))
	diagnostics.text = "\n".join(messages)

func _import_csv(path: String) -> void:
	if not _file_scene_valid():
		return
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		diagnostics.text = "Cannot read CSV: " + error_string(FileAccess.get_open_error())
		return
	if file.get_length() > Policy.MAX_BYTES:
		diagnostics.text = "CSV exceeds byte bound."
		return
	var text := file.get_as_text()
	file.close()
	var candidates: Array = []
	for cue in _scene_cues():
		var row := _snapshot(cue)
		row.device_label = device_labels.get(row.device_id, "")
		candidates.append(row)
	var parsed := Policy.import_csv(text, candidates)
	var messages := PackedStringArray()
	for issue in parsed.errors:
		messages.append("CSV row %s [%s]: %s" % [issue.row, issue.severity, issue.message])
	_commit_rows(parsed.rows, messages, "Import SpatialFabric routing CSV")

func _commit_rows(rows: Array, messages: PackedStringArray, action: String) -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		return
	var current := _scene_cues()
	object_manager.cache_scene()
	var targets: Dictionary = {}
	var counts: Dictionary = {}
	for row in rows:
		var errors := Policy.validate(row)
		if not errors.is_empty():
			messages.append("%s: %s" % [row.get("node_path", "?"), "; ".join(errors)])
			continue
		var cue := root.get_node_or_null(NodePath(row.node_path))
		if cue == null or cue not in current:
			messages.append("Not a playback cue in this edited scene: " + str(row.node_path))
			continue
		var protected_reason: String = object_manager.reason(cue, true)
		if not protected_reason.is_empty():
			messages.append("%s: %s" % [row.node_path, protected_reason])
			continue
		counts[cue] = int(counts.get(cue, 0)) + 1
		targets[cue] = row
	for cue in counts:
		if counts[cue] > 1:
			messages.append("Duplicate target rejected (all rows): " + str(_snapshot(cue).node_path))
			targets.erase(cue)
	for cue in targets.keys():
		for key in Policy.COLUMNS:
			if key != "node_path" and not _has_property(cue, key):
				messages.append("%s: runtime lacks %s; entire row rejected, not silently discarded." % [_snapshot(cue).node_path, key])
				targets.erase(cue)
				break
	# Recheck after rejection: retaining an old address can invalidate another proposed row.
	var changed := true
	while changed:
		changed = false
		var groups := _osc_groups(targets)
		for address in groups:
			if groups[address].size() > 1 or not Policy._valid_osc(address):
				for cue in groups[address]:
					if targets.has(cue):
						messages.append("%s: conflicting/invalid effective OSC '%s'; row rejected." % [_snapshot(cue).node_path, address])
						targets.erase(cue)
						changed = true
	var edits: Array = []
	for cue in targets:
		for key in Policy.COLUMNS:
			if key != "node_path" and cue.get(key) != targets[cue][key]:
				edits.append([cue, key, cue.get(key), targets[cue][key]])
	if not edits.is_empty():
		var undo := get_undo_redo()
		# Explicit cue context selects the edited scene history; normal commit marks it unsaved.
		undo.create_action(action, UndoRedo.MERGE_DISABLE, edits[0][0])
		for change in edits:
			undo.add_do_property(change[0], change[1], change[3])
			undo.add_undo_property(change[0], change[1], change[2])
		committing = true
		undo.commit_action()
		committing = false
	messages.append("Accepted %d/%d rows; %d property changes (undoable)." % [targets.size(), rows.size(), edits.size()])
	messages.append_array(_osc_diagnostics({}))
	# Refresh the draft; our commit's version signal is suppressed to retain diagnostics.
	_refresh()
	diagnostics.text = "\n".join(messages)

func _inspect_scene() -> void:
	var root := get_editor_interface().get_edited_scene_root()
	if root == null:
		report.text = "No edited scene."
		return
	var managers := root.find_children("*", "", true, false)
	if root is SpatialFabricManager:
		managers.push_front(root)
	for node in managers:
		if node is SpatialFabricManager:
			report.text = JSON.stringify(node.get_scene_page(), "\t")
			return
	report.text = "No SpatialFabricManager in the edited scene."

func _exit_tree() -> void:
	if get_undo_redo().version_changed.is_connected(_history_changed):
		get_undo_redo().version_changed.disconnect(_history_changed)
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()
