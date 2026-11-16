extends CharacterBody3D
## Original capsule visitor; no template or automatic mouse capture.

var camera: Camera3D
var pitch := 0.0

func _ready() -> void:
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.8
	shape.shape = capsule
	shape.position.y = 0.9
	add_child(shape)
	camera = Camera3D.new()
	camera.position.y = 1.65
	camera.current = true
	add_child(camera)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		rotate_y(-event.relative.x * 0.002)
		pitch = clampf(pitch - event.relative.y * 0.002, -1.4, 1.4)
		camera.rotation.x = pitch

func _physics_process(delta: float) -> void:
	var direction := Vector3.ZERO
	if Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		if Input.is_physical_key_pressed(KEY_W): direction.z -= 1
		if Input.is_physical_key_pressed(KEY_S): direction.z += 1
		if Input.is_physical_key_pressed(KEY_A): direction.x -= 1
		if Input.is_physical_key_pressed(KEY_D): direction.x += 1
	var movement := basis * direction.normalized() * (7.0 if Input.is_physical_key_pressed(KEY_SHIFT) else 4.0)
	velocity.x = movement.x
	velocity.z = movement.z
	if not is_on_floor(): velocity.y -= 20.0 * delta
	elif Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and Input.is_physical_key_pressed(KEY_SPACE): velocity.y = 6.0
	else: velocity.y = -0.1
	move_and_slide()
