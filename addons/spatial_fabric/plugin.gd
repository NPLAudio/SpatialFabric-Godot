@tool
extends EditorPlugin

var dock: VBoxContainer
var report: TextEdit

func _enter_tree() -> void:
	dock = VBoxContainer.new()
	dock.name = "SpatialFabric"
	var title := Label.new()
	title.text = "Wireframe • local inspection only\nOSC / native playback: not implemented"
	dock.add_child(title)
	var refresh := Button.new()
	refresh.text = "Inspect edited scene (no I/O)"
	refresh.pressed.connect(_inspect_scene)
	dock.add_child(refresh)
	report = TextEdit.new()
	report.editable = false
	report.custom_minimum_size = Vector2(280, 280)
	dock.add_child(report)
	add_control_to_dock(DOCK_SLOT_RIGHT_UL, dock)

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
	if dock != null:
		remove_control_from_docks(dock)
		dock.queue_free()
