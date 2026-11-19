@tool
extends VBoxContainer
## Scene authoring only. Never calls runtime preparation, playback or networking APIs.
const TYPES = {
	"Playback": preload("res://addons/spatial_fabric/runtime/playback_cue.gd"),
	"Live input": preload("res://addons/spatial_fabric/runtime/live_input_cue.gd"),
	"Spatial object": preload("res://addons/spatial_fabric/runtime/spatial_object.gd"),
	"Stage": preload("res://addons/spatial_fabric/runtime/spatial_stage.gd"),
	"Manager": preload("res://addons/spatial_fabric/runtime/spatial_manager.gd"),
}
var plugin: EditorPlugin
var search: LineEdit
var nodes: ItemList
var kind: OptionButton
var properties: OptionButton
const PropertyEditor = preload("res://addons/spatial_fabric/editor/scene_property_editor.gd")
var value_editor: VBoxContainer
var editor_slot: VBoxContainer
var draft_binding := ""
var membership: Dictionary = {}
var protection: Dictionary = {}
var filter_timer: Timer
var status: Label
var listed: Array[Node] = []
var chosen: Array[Node] = []
var refreshing := false
var mixed_value := false
var draft_authored := false

func setup(editor_plugin: EditorPlugin) -> void:
	plugin = editor_plugin
	var title := Label.new()
	title.text = "Central Scene Object Manager (SF only)"
	add_child(title)
	search = LineEdit.new()
	search.placeholder_text = "Filter all scene nodes by path / type"
	filter_timer = Timer.new()
	filter_timer.one_shot = true
	filter_timer.wait_time = 0.18
	filter_timer.timeout.connect(filter_rows)
	add_child(filter_timer)
	search.text_changed.connect(func(_text: String): filter_timer.start())
	add_child(search)
	button("Refresh all placed nodes", refresh)
	button("Use Scene Tree selection", use_scene_selection)
	nodes = ItemList.new()
	nodes.select_mode = ItemList.SELECT_MULTI
	nodes.custom_minimum_size.y = 140
	nodes.multi_selected.connect(func(_index: int, _selected: bool): select_list())
	add_child(nodes)
	kind = OptionButton.new()
	for label in TYPES:
		kind.add_item(label)
	kind.item_selected.connect(func(_index: int): refresh_properties())
	add_child(kind)
	button("Add typed SF child to selected nodes", add_selected)
	button("Remove selected SF functionality", remove_selected)
	properties = OptionButton.new()
	properties.item_selected.connect(func(_index: int): show_value())
	add_child(properties)
	editor_slot = VBoxContainer.new()
	add_child(editor_slot)
	button("Apply authored SF property to selection", apply_value)
	button("Inspect first SF component (normal Inspector)", inspect_first)
	status = Label.new()
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(status)
	refresh()

func button(text: String, callback: Callable) -> void:
	var control := Button.new()
	control.text = text
	control.pressed.connect(callback)
	add_child(control)

func root() -> Node:
	return plugin.get_editor_interface().get_edited_scene_root()

func scene_nodes() -> Array[Node]:
	var result: Array[Node] = []
	if root() != null:
		collect(root(), result)
	return result

func collect(node: Node, result: Array[Node]) -> void:
	# Internal children are deliberately excluded; hidden/nonspatial placed nodes are not.
	if node == root() or node.owner != null:
		result.append(node)
		for child in node.get_children(false):
			collect(child, result)

func cache_scene() -> void:
	membership.clear()
	protection.clear()
	for node in scene_nodes():
		membership[node] = true
	var inherited := inheritance_reason()
	for node in membership:
		var why := inherited
		# collect() is parent-first, so external ancestry is a constant-time lookup.
		if why.is_empty() and node != root():
			why = protection.get(node.get_parent(), "")
			if not node.scene_file_path.is_empty() or node.owner != root():
				why = "Packed/external scene content: open its source scene to edit."
		protection[node] = why

func inheritance_reason() -> String:
	if root() == null:
		return "No edited scene."
	# At most one pack per refresh/operation, never per row or filter keystroke.
	var packed: PackedScene
	if root().scene_file_path.is_empty():
		# An unsaved inherited scene has no resource path, but packing still preserves
		# its root base instance. Do not rely on a nonexistent Node inherited-state API.
		packed = PackedScene.new()
		if packed.pack(root()) != OK:
			return "Cannot validate unsaved scene inheritance; save/open the source scene first."
	elif ResourceLoader.exists(root().scene_file_path):
		packed = load(root().scene_file_path) as PackedScene
	else:
		return "Scene source is missing; save/open the scene before authoring."
	if packed != null and packed.get_state().get_node_instance(0) != null:
		return "Inherited scene: edit the source scene instead (protected)."
	return ""

func reason(node: Node, cached := false) -> String:
	if not cached:
		cache_scene()
	return protection.get(node, "Not a placed node in the current edited scene.")

func refresh() -> void:
	if nodes == null:
		return
	cache_scene()
	chosen = chosen.filter(func(node: Node): return is_instance_valid(node) and membership.has(node))
	filter_rows()
	refresh_properties()

func filter_rows() -> void:
	refreshing = true
	listed.clear()
	nodes.clear()
	var selected_nodes: Dictionary = {}
	for node in chosen:
		if is_instance_valid(node):
			selected_nodes[node] = true
	for node in membership:
		if not is_instance_valid(node):
			continue
		var type_label: String = node.get_class()
		for label in TYPES:
			if is_instance_of(node, TYPES[label]):
				type_label = "SF " + label
				break
		var text := "%s [%s]" % [root().get_path_to(node), type_label]
		if not search.text.is_empty() and not search.text.to_lower() in text.to_lower():
			continue
		listed.append(node)
		nodes.add_item(text)
		nodes.set_item_tooltip(nodes.item_count - 1, reason(node, true))
		if selected_nodes.has(node):
			nodes.select(nodes.item_count - 1, false)
	refreshing = false

func select_list() -> void:
	if refreshing:
		return
	chosen.clear()
	for index in nodes.get_selected_items():
		chosen.append(listed[index])
	refresh_properties()

func use_scene_selection() -> void:
	chosen.assign(plugin.get_editor_interface().get_selection().get_selected_nodes())
	refresh()

func script_type() -> Script:
	return TYPES[kind.get_item_text(kind.selected)]

func component(node: Node, script: Script) -> Node:
	if is_instance_of(node, script):
		return node
	for child in node.get_children(false):
		if is_instance_of(child, script):
			return child
	return null

func targets() -> Array[Node]:
	var result: Array[Node] = []
	for node in chosen:
		if is_instance_valid(node):
			var target := component(node, script_type())
			if target != null and target not in result:
				result.append(target)
	return result

func exported(script: Script) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in script.get_script_property_list():
		if entry.usage & PROPERTY_USAGE_EDITOR and entry.usage & PROPERTY_USAGE_STORAGE and not entry.usage & PROPERTY_USAGE_CATEGORY:
			result.append(entry)
	return result

func refresh_properties() -> void:
	if properties == null:
		return
	var key := properties.get_item_text(properties.selected) if properties.selected >= 0 else ""
	properties.clear()
	for entry in exported(script_type()):
		properties.add_item(entry.name)
		properties.set_item_metadata(properties.item_count - 1, entry)
		if entry.name == key:
			properties.select(properties.item_count - 1)
	show_value()

func show_value() -> void:
	var found := targets()
	var ids: Array[int] = []
	for node in chosen:
		if is_instance_valid(node):
			ids.append(node.get_instance_id())
	ids.sort()
	var target_ids: Array[int] = []
	for target in found:
		target_ids.append(target.get_instance_id())
	target_ids.sort()
	var key := properties.get_item_text(properties.selected) if properties.selected >= 0 else ""
	var binding := str([root().get_instance_id() if root() != null else 0, script_type(), ids, target_ids, key])
	if draft_authored and binding == draft_binding:
		status.text = "Pending draft retained for %s on %d components. Apply remains explicit." % [key, found.size()]
		return
	var cancelled := draft_authored
	draft_authored = false
	draft_binding = binding
	if value_editor != null:
		editor_slot.remove_child(value_editor)
		value_editor.queue_free()
		value_editor = null
	mixed_value = false
	var messages := PackedStringArray()
	for node in chosen:
		var why := reason(node, true)
		if not why.is_empty():
			messages.append("%s: %s" % [node.name, why])
		elif component(node, script_type()) == null:
			messages.append("%s: no %s; explicitly Add first." % [node.name, kind.text])
	if found.is_empty() or properties.selected < 0:
		messages.append("Select scene nodes and an SF type. No functionality is added automatically.")
	else:
		var first: Variant = found[0].get(key)
		var mixed := false
		for target in found:
			if target.get(key) != first:
				mixed = true
		mixed_value = mixed
		value_editor = PropertyEditor.new()
		editor_slot.add_child(value_editor)
		value_editor.setup(properties.get_item_metadata(properties.selected), first, mixed)
		var bound_editor := value_editor
		value_editor.authored.connect(func():
			if value_editor == bound_editor and draft_binding == binding:
				draft_authored = true)
		messages.append("%d SF components. Only Apply changes values; unedited mixed draft is never applied." % found.size())
	if cancelled:
		messages.append("Pending draft cancelled: scene, target set, SF type or property changed. No draft was applied.")
	status.text = "\n".join(messages)

func validate_selection(require_component: bool) -> bool:
	cache_scene()
	var errors := PackedStringArray()
	if chosen.is_empty():
		errors.append("Select at least one placed scene node.")
	for node in chosen:
		var why := reason(node, true)
		if why.is_empty() and require_component:
			var target := component(node, script_type())
			why = "Missing selected SF type; explicitly Add first." if target == null else reason(target, true)
		if not why.is_empty():
			errors.append("%s: %s" % [node.name if is_instance_valid(node) else "Deleted node", why])
	status.text = "\n".join(errors)
	return errors.is_empty()

func add_selected() -> void:
	attach(chosen, script_type())

func attach(selection: Array[Node], script: Script) -> void:
	chosen = selection.duplicate()
	if script not in TYPES.values() or not validate_selection(false):
		return
	var additions: Array = []
	for node in chosen:
		if component(node, script) == null:
			var child: Node = script.new()
			child.name = script.get_global_name()
			# Spatial functionality follows an appropriate 3D parent; nonspatial parents
			# still support an explicit independent Node3D component, never a guessed binding.
			if child is SpatialFabricObject and node is Node3D:
				child.bound_transform = NodePath("..")
			additions.append([node, child])
	if additions.is_empty():
		status.text = "Already configured: no duplicate SF children added."
		return
	var undo := plugin.get_undo_redo()
	undo.create_action("Add SF scene functionality", UndoRedo.MERGE_DISABLE, root())
	for pair in additions:
		undo.add_do_method(pair[0], "add_child", pair[1], true)
		undo.add_do_property(pair[1], "owner", root())
		undo.add_undo_method(pair[0], "remove_child", pair[1])
		undo.add_do_reference(pair[1])
	undo.commit_action()
	refresh()

func remove_selected() -> void:
	if not validate_selection(true):
		return
	var found := targets()
	if root() in found:
		status.text = "Cannot remove the edited scene root."
		return
	# Removing existing authored subtrees would need preserving every descendant owner.
	for target in found:
		if target.get_child_count() != 0:
			status.text = "SF node has children; remove it using the Scene Tree instead."
			return
	# Undo methods execute in registration order. Restore siblings ascending, regardless
	# of Scene Tree / list selection order, including untouched siblings between them.
	found.sort_custom(func(a: Node, b: Node):
		if a.get_parent() == b.get_parent():
			return a.get_index() < b.get_index()
		return a.get_parent().get_instance_id() < b.get_parent().get_instance_id())
	var undo := plugin.get_undo_redo()
	undo.create_action("Remove SF scene functionality", UndoRedo.MERGE_DISABLE, root())
	for target in found:
		undo.add_do_method(target.get_parent(), "remove_child", target)
		undo.add_undo_method(target.get_parent(), "add_child", target, true)
		undo.add_undo_property(target, "owner", root())
		undo.add_undo_method(target.get_parent(), "move_child", target, target.get_index())
		undo.add_undo_reference(target)
	undo.commit_action()
	refresh()

func apply_value() -> void:
	if properties.selected < 0 or value_editor == null:
		return
	if not draft_authored:
		status.text += "\nValues retained. Author an explicit value first."
		return
	# Recheck binding before using a draft (a scene switch can precede refresh).
	show_value()
	if not draft_authored:
		return
	edit_draft(properties.get_item_text(properties.selected), value_editor.draft)

func edit_property(key: String, authored: Variant) -> void:
	edit_draft(key, {"mode": "value", "value": authored})

func edit_draft(key: String, authored: Dictionary) -> void:
	if not validate_selection(true):
		return
	var metadata: Dictionary = {}
	for entry in exported(script_type()):
		if entry.name == key:
			metadata = entry
	if metadata.is_empty():
		status.text = "Not an exported SF property."
		return
	var changes: Array = []
	# Convert and validate EVERY target before constructing any history transaction.
	for target in targets():
		var old: Variant = target.get(key)
		var converted := PropertyEditor.convert(authored, metadata, old, target, membership)
		var why: String = converted.get("error", "")
		var next: Variant = converted.get("value")
		if why.is_empty():
			why = PropertyEditor.validate(metadata, next)
		if why.is_empty() and old is Array and old.is_typed():
			for item in next:
				if typeof(item) != old.get_typed_builtin():
					why = "Array element type does not match the real exported property."
					break
			if why.is_empty():
				var typed: Array = old.duplicate()
				typed.assign(next)
				next = typed
		# Replay limits are nonnegative (export hints), with no invented one-hour cap.
		# Only validate the affected pair, not unrelated legacy configuration.
		if why.is_empty() and key in ["replay_delay_min", "replay_delay_max"]:
			var low: float = next if key == "replay_delay_min" else target.get("replay_delay_min")
			var high: float = next if key == "replay_delay_max" else target.get("replay_delay_max")
			if low > high:
				why = "replay_delay_min must not exceed replay_delay_max."
		if not why.is_empty():
			status.text = "%s / %s: %s No targets changed." % [target.name, key, why]
			return
		if old != next:
			changes.append([target, old, next])
	if not changes.is_empty():
		var undo := plugin.get_undo_redo()
		undo.create_action("Edit SF " + key, UndoRedo.MERGE_DISABLE, root())
		for change in changes:
			undo.add_do_property(change[0], key, change[2])
			undo.add_undo_property(change[0], key, change[1])
		undo.commit_action()
	draft_authored = false
	refresh_properties()

func inspect_first() -> void:
	if not validate_selection(true):
		return
	plugin.get_editor_interface().inspect_object(targets()[0])
