@tool
extends VBoxContainer
## Draft-only controls. Conversion is shared by UI Apply and headless editor tests.
signal authored
var entry: Dictionary
var controls: Array[Control] = []
var draft: Dictionary = {}
var hint: Label
var file_dialog: EditorFileDialog

func setup(metadata: Dictionary, initial: Variant, mixed: bool) -> void:
	entry = metadata
	hint = Label.new()
	hint.text = "Mixed — unchanged until explicitly authored" if mixed else "Only Apply changes the scene"
	add_child(hint)
	if entry.type == TYPE_BOOL:
		var check := CheckBox.new()
		check.text = "Mixed (click to author true)" if mixed else "Enabled"
		check.button_pressed = false if mixed else initial
		check.toggled.connect(func(enabled: bool):
			check.text = "Enabled"
			set_draft({"mode": "value", "value": enabled}))
		add_child(check)
		controls.append(check)
	elif entry.hint == PROPERTY_HINT_ENUM:
		var options := OptionButton.new()
		for item in enum_items(entry):
			options.add_item(item.label)
			options.set_item_metadata(options.item_count - 1, item.value)
			if not mixed and item.value == initial:
				options.select(options.item_count - 1)
		if mixed:
			options.select(-1)
		options.item_selected.connect(func(index: int): set_draft({"mode": "value", "value": options.get_item_metadata(index)}))
		add_child(options)
		controls.append(options)
	elif entry.type in [TYPE_INT, TYPE_FLOAT]:
		add_number(initial, mixed, -1)
	elif entry.type in [TYPE_VECTOR2, TYPE_VECTOR3, TYPE_VECTOR4, TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I]:
		var count := 2 if entry.type in [TYPE_VECTOR2, TYPE_VECTOR2I] else (3 if entry.type in [TYPE_VECTOR3, TYPE_VECTOR3I] else 4)
		for axis in count:
			var label := Label.new()
			label.text = ["X", "Y", "Z", "W"][axis]
			add_child(label)
			add_number(initial[axis], mixed, axis)
	elif entry.type == TYPE_NODE_PATH or is_node_array(entry):
		var display := Label.new()
		display.text = "Mixed" if mixed else str(initial)
		add_child(display)
		controls.append(display)
		var choose := Button.new()
		choose.text = "Use Scene Tree selection" if is_node_array(entry) else "Use first Scene Tree selected node"
		choose.pressed.connect(func(): choose_nodes(EditorInterface.get_selection().get_selected_nodes()))
		add_child(choose)
		var clear := Button.new()
		clear.text = "Clear paths"
		clear.pressed.connect(func(): choose_nodes([]))
		add_child(clear)
	elif entry.type == TYPE_STRING:
		var text := LineEdit.new()
		text.text = "" if mixed else initial
		text.placeholder_text = "Mixed — type to replace" if mixed else "Empty is allowed"
		text.text_changed.connect(func(content: String): set_draft({"mode": "value", "value": content}))
		add_child(text)
		controls.append(text)
		if entry.hint in [PROPERTY_HINT_FILE, PROPERTY_HINT_GLOBAL_FILE]:
			file_dialog = EditorFileDialog.new()
			file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
			file_dialog.access = EditorFileDialog.ACCESS_FILESYSTEM if entry.hint == PROPERTY_HINT_GLOBAL_FILE else EditorFileDialog.ACCESS_RESOURCES
			for filter in str(entry.hint_string).split(",", false):
				file_dialog.add_filter(filter.strip_edges())
			file_dialog.file_selected.connect(choose_file)
			add_child(file_dialog)
			var browse := Button.new()
			browse.text = "Choose file…"
			browse.pressed.connect(func(): file_dialog.popup_centered_ratio())
			add_child(browse)
	else:
		var text := LineEdit.new()
		text.text = "" if mixed else var_to_str(initial)
		text.placeholder_text = "Advanced Variant syntax (complex field only)"
		text.text_changed.connect(func(content: String): set_draft({"mode": "value", "value": str_to_var(content)}))
		add_child(text)
		controls.append(text)

func set_draft(next: Dictionary) -> void:
	draft = next
	authored.emit()

func choose_file(path: String) -> void:
	(controls[0] as LineEdit).text = path
	set_draft({"mode": "value", "value": path})

func choose_nodes(selection: Array) -> void:
	var ids: Array[int] = []
	for node in selection:
		ids.append(node.get_instance_id())
		if entry.type == TYPE_NODE_PATH:
			break
	(controls[0] as Label).text = "Clear" if ids.is_empty() else "Selected: " + ", ".join(selection.map(func(node: Node): return str(node.name)))
	set_draft({"mode": "nodes", "ids": ids})

func add_number(initial: Variant, mixed: bool, axis: int) -> void:
	var spin := SpinBox.new()
	spin.allow_greater = true
	spin.allow_lesser = true
	spin.step = 1.0 if entry.type in [TYPE_INT, TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I] else 0.001
	if axis < 0 and entry.hint == PROPERTY_HINT_RANGE:
		var parts := str(entry.hint_string).split(",")
		spin.min_value = float(parts[0])
		spin.max_value = float(parts[1])
		if parts.size() > 2:
			spin.step = float(parts[2])
		spin.allow_greater = "or_greater" in parts
		spin.allow_lesser = "or_lesser" in parts
	spin.value = initial
	add_child(spin)
	controls.append(spin)
	var line := spin.get_line_edit()
	if mixed:
		line.text = ""
		line.placeholder_text = "Mixed"
	var changed := func(content: String):
		if axis < 0:
			set_draft({"mode": "number", "text": content})
		else:
			var axes: Dictionary = draft.get("axes", {}).duplicate()
			axes[axis] = content
			set_draft({"mode": "vector", "axes": axes})
	# SpinBox normalizes/clamps on focus loss. Keep raw user text authoritative
	# until Apply validates it; normalization is not a new authored value.
	var input := {"raw": false, "text": ""}
	line.text_changed.connect(func(content: String):
		input.raw = true
		input.text = content
		changed.call(content))
	var step_input := func(event: InputEvent):
		var step: bool = event is InputEventKey and event.pressed and event.keycode in [KEY_UP, KEY_DOWN]
		if event is InputEventMouseButton and event.pressed:
			step = event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN] or (event.button_index == MOUSE_BUTTON_LEFT and not line.get_global_rect().has_point(spin.get_global_mouse_position()))
		if step:
			input.raw = false
			# Native handling can precede gui_input; sample the current value too.
			changed.call(str(spin.value))
	spin.gui_input.connect(step_input)
	line.gui_input.connect(step_input)
	spin.value_changed.connect(func(number: float):
		if not input.raw:
			changed.call(str(number)))
	line.focus_exited.connect(func():
		if input.raw:
			line.set_deferred("text", input.text))

static func is_node_array(metadata: Dictionary) -> bool:
	return metadata.type == TYPE_ARRAY and str(metadata.hint_string).get_slice(":", 0).get_slice("/", 0) == str(TYPE_NODE_PATH)

static func enum_items(metadata: Dictionary) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	var index := 0
	for item in str(metadata.hint_string).split(","):
		var parts := item.split(":")
		if parts.size() > 1:
			index = int(parts[1])
		items.append({"label": parts[0], "value": parts[0] if metadata.type == TYPE_STRING else index})
		index += 1
	return items

static func number(text: String, integer: bool) -> Dictionary:
	if not text.is_valid_float() or not is_finite(float(text)):
		return {"error": "Enter a finite number."}
	var parsed := float(text)
	if integer and (parsed != floor(parsed) or parsed < -9223372036854775808.0 or parsed >= 9223372036854775808.0):
		return {"error": "Enter a whole integer in the supported range."}
	return {"value": int(parsed) if integer else parsed}

static func convert(authored: Dictionary, metadata: Dictionary, old: Variant, target: Node, membership: Dictionary) -> Dictionary:
	match authored.get("mode", ""):
		"value":
			return {"value": authored.value}
		"number":
			return number(authored.text, metadata.type == TYPE_INT)
		"vector":
			var next: Variant = old
			for axis in authored.axes:
				var parsed := number(authored.axes[axis], metadata.type in [TYPE_VECTOR2I, TYPE_VECTOR3I, TYPE_VECTOR4I])
				if parsed.has("error"):
					return parsed
				next[axis] = parsed.value
			return {"value": next}
		"nodes":
			var paths: Array[NodePath] = []
			for id in authored.ids:
				var node := instance_from_id(id) as Node
				if node == null or not membership.has(node):
					return {"error": "Selected path node is no longer in this edited scene. Select it again."}
				paths.append(target.get_path_to(node))
			return {"value": (NodePath("") if paths.is_empty() else paths[0]) if metadata.type == TYPE_NODE_PATH else paths}
	return {"error": "Author a value first."}

static func validate(metadata: Dictionary, next: Variant) -> String:
	if typeof(next) != metadata.type:
		return "Not an exported SF property or wrong type."
	if next is float and not is_finite(next):
		return "Value must be finite."
	if next is Vector2 or next is Vector3 or next is Vector4:
		if not next.is_finite():
			return "Vector components must be finite."
	if metadata.hint == PROPERTY_HINT_ENUM:
		var valid := false
		for item in enum_items(metadata):
			valid = valid or next == item.value
		if not valid:
			return "Choose one of the exported enum labels."
	if metadata.hint == PROPERTY_HINT_RANGE:
		var parts := str(metadata.hint_string).split(",")
		if (not "or_lesser" in parts and next < float(parts[0])) or (not "or_greater" in parts and next > float(parts[1])):
			return "Value is outside the exported range: " + str(metadata.hint_string)
	if metadata.name == "dimensions_meters" and (next.x <= 0 or next.y <= 0 or next.z <= 0):
		return "Stage dimensions must be finite and positive."
	if metadata.name == "source_path" and not next.is_empty() and next.get_extension().to_lower() != "wav":
		return "source_path must be empty or a WAV file path."
	if metadata.name == "osc_base" and not next.is_empty() and not preload("res://addons/spatial_fabric/editor/routing_policy.gd")._valid_osc(next):
		return "osc_base must be blank or a literal absolute OSC path without trailing slash."
	return ""
