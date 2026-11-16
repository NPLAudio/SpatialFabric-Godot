extends SceneTree
## Explicit local render acceptance; never used by normal startup.

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size()!=1:
		push_error("Supply an external screenshot directory after --")
		quit(1)
		return
	DirAccess.make_dir_recursive_absolute(args[0])
	var scene: Node3D = load("res://examples/four_rooms/room_showcase.tscn").instantiate()
	root.add_child(scene)
	var camera := Camera3D.new()
	scene.add_child(camera)
	camera.current = true
	var views := [
		["hall",Vector3(-12.0,1.65,-5.0),Vector3(-10.0,1.5,22.0)],
		["spatial",Vector3(-6.0,1.65,5.0),Vector3(1.0,2.5,-2.0)],
		["mono",Vector3(-8.0,1.65,14.0),Vector3(-1.0,1.8,14.0)]
	]
	for view in views:
		if view[0] == "mono":
			scene.get_node("Visitor").position = Vector3(-5, 0.05, 14)
		camera.global_position = view[1]
		camera.look_at(view[2])
		await process_frame
		await process_frame
		await RenderingServer.frame_post_draw
		var image := root.get_texture().get_image()
		if image.is_empty() or image.save_png(args[0].path_join(view[0]+".png"))!=OK:
			push_error("Screenshot capture failed")
			quit(1)
			return
	print("Captured three real Godot views.")
	quit(0)
