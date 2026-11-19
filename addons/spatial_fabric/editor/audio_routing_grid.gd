@tool
extends Control
## Constant control count. Only visible crosspoints are painted; headers clip independently.
signal route_requested(cue: Node, device: String, channel: int)
signal row_selected(cue: Node)
const CELL := 36.0
const ROW := 26.0
const HEADER := 96.0
var rows: Array = []
var groups: Array = []
var count := 0
var body := Control.new()
var top := Control.new()
var left := Control.new()
var horizontal := HScrollBar.new()
var vertical := VScrollBar.new()
var pressed: Array = []

func _init() -> void:
	custom_minimum_size = Vector2(280, 220)
	size_flags_vertical = SIZE_EXPAND_FILL
	clip_contents = true
	mouse_filter = MOUSE_FILTER_PASS
	for canvas in [body, top, left]:
		canvas.clip_contents = true
		canvas.mouse_filter = MOUSE_FILTER_PASS
		add_child(canvas)
	add_child(horizontal)
	add_child(vertical)
	body.draw.connect(_draw_body)
	top.draw.connect(_draw_top)
	left.draw.connect(_draw_left)
	body.gui_input.connect(_body_input)
	left.gui_input.connect(_left_input)
	top.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseMotion:
			var col := column(int((event.position.x + horizontal.value) / CELL))
			top.tooltip_text = "" if col.is_empty() else ("Dynamic OS default · capacity unknown" if col.id == "" else "Exact ID: " + col.id) + "\nAuto 0: corresponding source channels; positive: first source → destination")
	gui_input.connect(_wheel)
	horizontal.value_changed.connect(func(_value: float): repaint())
	vertical.value_changed.connect(func(_value: float): repaint())
	resized.connect(layout)

func capture(new_rows: Array, devices: Array) -> void:
	rows = new_rows
	groups.clear()
	count = 0
	var authored := {}
	for row in rows:
		if not authored.has(row.device):
			authored[row.device] = {}
		authored[row.device][row.channel] = true
	var snapshots := {"": {"id": "", "name": "Dynamic OS default", "channels": 0, "online": false}}
	for entry in devices:
		snapshots[entry.id] = entry
	for id in authored:
		if not snapshots.has(id):
			snapshots[id] = {"id": id, "name": id, "channels": 0, "online": false}
	for id in snapshots:
		var entry: Dictionary = snapshots[id]
		var stored: Array = []
		for channel in authored.get(id, {}):
			if channel < 0 or channel > entry.channels:
				stored.append(channel)
		stored.sort()
		var group := {"id": id, "title": str(entry.name) + ("" if id == "" else (" · online" if entry.online else " · OFFLINE")), "capacity": int(entry.channels), "stored": stored, "start": count, "count": 1 + int(entry.channels) + stored.size()}
		groups.append(group)
		count += group.count
	pressed.clear()
	layout()

func column(index: int) -> Dictionary:
	var low := 0
	var high := groups.size() - 1
	while low <= high:
		var mid := (low + high) / 2
		var group: Dictionary = groups[mid]
		if index < group.start:
			high = mid - 1
		elif index >= group.start + group.count:
			low = mid + 1
		else:
			var offset: int = index - group.start
			return {"id": group.id, "channel": offset if offset <= group.capacity else group.stored[offset - group.capacity - 1], "stored": offset > group.capacity}
	return {}

func layout() -> void:
	var label_width := minf(180, maxf(60, size.x - 60))
	body.position = Vector2(label_width, HEADER)
	body.size = Vector2(maxf(1, size.x - label_width - 16), maxf(1, size.y - HEADER - 16))
	top.position = Vector2(label_width, 0)
	top.size = Vector2(body.size.x, HEADER)
	left.position = Vector2(0, HEADER)
	left.size = Vector2(label_width, body.size.y)
	horizontal.position = Vector2(label_width, size.y - 16)
	horizontal.size = Vector2(body.size.x, 16)
	vertical.position = Vector2(size.x - 16, HEADER)
	vertical.size = Vector2(16, body.size.y)
	horizontal.max_value = maxf(body.size.x, count * CELL)
	horizontal.page = body.size.x
	vertical.max_value = maxf(body.size.y, rows.size() * ROW)
	vertical.page = body.size.y
	repaint()

func repaint() -> void:
	for canvas in [body, top, left]:
		canvas.queue_redraw()

func label(canvas: Control, point: Vector2, text: String, width: float) -> void:
	canvas.draw_string(get_theme_default_font(), point, text, HORIZONTAL_ALIGNMENT_LEFT, width, 12, Color.WHITE)

func _draw_body() -> void:
	for r in range(int(vertical.value / ROW), mini(rows.size(), int(ceil((vertical.value + body.size.y) / ROW)))):
		var row: Dictionary = rows[r]
		for c in range(int(horizontal.value / CELL), mini(count, int(ceil((horizontal.value + body.size.x) / CELL)))):
			var col := column(c)
			var point := Vector2(c * CELL - horizontal.value, r * ROW - vertical.value)
			var checked: bool = row.device == col.id and row.channel == col.channel
			var fill := Color(0.12, 0.5, 0.25) if checked else Color(0.23, 0.25, 0.28)
			if not row.reason.is_empty():
				fill = fill.darkened(0.4)
			body.draw_rect(Rect2(point + Vector2.ONE, Vector2(CELL - 2, ROW - 2)), fill)
			if checked:
				label(body, point + Vector2(10, 18), "✓", CELL)

func _draw_top() -> void:
	for group in groups:
		var x: float = group.start * CELL - horizontal.value
		var end: float = x + group.count * CELL
		if end <= 0 or x >= top.size.x:
			continue
		top.draw_rect(Rect2(Vector2(x, 0), Vector2(group.count * CELL - 1, HEADER - 27)), Color(0.22, 0.28, 0.3))
		if group.count * CELL < 120:
			top.draw_set_transform(Vector2(x + 23, HEADER - 30), -PI / 2)
			label(top, Vector2.ZERO, group.title, HEADER - 30)
			top.draw_set_transform(Vector2.ZERO)
		else:
			label(top, Vector2(maxf(0, x) + 3, 30), group.title, minf(end, top.size.x) - maxf(0, x) - 4)
	for c in range(int(horizontal.value / CELL), mini(count, int(ceil((horizontal.value + top.size.x) / CELL)))):
		var col := column(c)
		label(top, Vector2(c * CELL - horizontal.value + 2, HEADER - 7), ("Auto" if col.channel == 0 else str(col.channel)) + ("*" if col.stored else ""), CELL - 2)

func _draw_left() -> void:
	for r in range(int(vertical.value / ROW), mini(rows.size(), int(ceil((vertical.value + left.size.y) / ROW)))):
		label(left, Vector2(3, r * ROW - vertical.value + 18), rows[r].name, left.size.x - 5)

func hit(point: Vector2) -> Array:
	if not Rect2(Vector2.ZERO, body.size).has_point(point):
		return []
	var r := int((point.y + vertical.value) / ROW)
	var c := int((point.x + horizontal.value) / CELL)
	if r >= rows.size() or c >= count:
		return []
	var col := column(c)
	return [rows[r].cue, col.id, col.channel]

func _body_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var target := hit(event.position)
		body.tooltip_text = "" if target.is_empty() else str(target[1]) + " / " + str(target[2]) + " — configured route, not live"
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		var target := hit(event.position)
		if event.pressed:
			pressed = target
		else:
			var previous := pressed
			pressed = []
			if not target.is_empty() and target == previous:
				row_selected.emit(target[0])
				route_requested.emit(target[0], target[1], target[2])
		body.accept_event()

func _left_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		var row := int((event.position.y + vertical.value) / ROW)
		left.tooltip_text = rows[row].path + "\n" + rows[row].reason if row >= 0 and row < rows.size() else ""
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var row := int((event.position.y + vertical.value) / ROW)
		if row >= 0 and row < rows.size():
			row_selected.emit(rows[row].cue)
			left.accept_event()

func _wheel(event: InputEvent) -> void:
	if not event is InputEventMouseButton or not event.pressed:
		return
	var direction := 0
	if event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
		direction = 1
	elif event.button_index == MOUSE_BUTTON_WHEEL_UP:
		direction = -1
	if direction == 0:
		return
	var bar: ScrollBar = horizontal if event.shift_pressed else vertical
	var before := bar.value
	bar.value += direction * 3 * ROW
	if bar.value != before:
		accept_event()
