@tool
extends Node3D
## Original procedural wireframe geometry. No imported template assets or source audio.

var origins: Array[Vector3] = []
var elapsed := 0.0
var hud: Label
var manager: SpatialFabricManager

## Playback rooms: x -9..-1; z 11..17 mono, 18..24 stereo, 25..31 replay.
static func cue_name_at(point: Vector3) -> String:
	if point.x < -9.0 or point.x > -1.0:
		return ""
	if point.z >= 11.0 and point.z <= 17.0:
		return "Mono"
	if point.z >= 18.0 and point.z <= 24.0:
		return "Stereo"
	if point.z >= 25.0 and point.z <= 31.0:
		return "Replay"
	return ""

func _current_cue() -> SpatialFabricPlaybackCue:
	var visitor := get_node_or_null("Visitor") as Node3D
	if visitor == null:
		return null
	var cue_name := cue_name_at(visitor.global_position)
	return get_node_or_null(cue_name) as SpatialFabricPlaybackCue if cue_name != "" else null

func _unhandled_key_input(event: InputEvent) -> void:
	if Engine.is_editor_hint() or not (event is InputEventKey) or not event.pressed or event.echo:
		return
	var cue := _current_cue()
	match event.keycode:
		KEY_E: # explicit user action: prepares the source on first use, then requests playback
			if cue != null and (cue.is_prepared() or cue.prepare_source() == OK):
				cue.try_play()
		KEY_Q:
			if cue != null:
				cue.stop()
		KEY_L:
			if cue != null:
				cue.set_loop(not cue.loop)
		KEY_R:
			if cue != null:
				cue.auto_replay = not cue.auto_replay
		KEY_X:
			for cue_node in manager._cues():
				cue_node.stop()
		KEY_I: # explicit: opens the default microphone/line input and plays it on the default output
			var live := get_node_or_null("Live") as SpatialFabricLiveInputCue
			if live != null:
				if live.is_live():
					live.stop()
				else:
					live.try_start()
		KEY_N:
			if manager.is_listening():
				manager.stop_networking()
			else:
				manager.start_networking()

func _box(label: String, center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = center
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	mesh.material_override = material
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

func _sign(text: String, point: Vector3, yaw: float) -> void:
	var label := Label3D.new()
	label.text = text
	label.position = point
	label.rotation.y = yaw
	label.pixel_size = 0.006
	label.font_size = 48
	label.no_depth_test = false
	add_child(label)

func _room(label: String, x_min: float, x_max: float, z_min: float, z_max: float, height: float, door: float, tint: Color, note: String) -> void:
	var center := Vector3((x_min+x_max)*0.5, height*0.5, (z_min+z_max)*0.5)
	var width := x_max-x_min
	var depth := z_max-z_min
	_box(label+" ceiling", Vector3(center.x,height+0.1,center.z), Vector3(width,0.2,depth), tint.darkened(0.3))
	_box(label+" back", Vector3(x_max,height*0.5,center.z), Vector3(0.2,height,depth), tint)
	_box(label+" north", Vector3(center.x,height*0.5,z_min), Vector3(width,height,0.2), tint)
	_box(label+" south", Vector3(center.x,height*0.5,z_max), Vector3(width,height,0.2), tint)
	for span in [Vector2(z_min,door-1.1),Vector2(door+1.1,z_max)]:
		if span.y>span.x:
			_box(label+" door side",Vector3(x_min,height*0.5,(span.x+span.y)*0.5),Vector3(0.2,height,span.y-span.x),tint)
	_box(label+" lintel",Vector3(x_min,(height+2.4)*0.5,door),Vector3(0.2,height-2.4,2.2),tint)
	_sign(label,Vector3(x_min-0.15,2.7,door),-PI*0.5)
	_sign(note,Vector3(x_max-0.2,2.0,center.z),-PI*0.5)

func _ready() -> void:
	_box("Continuous foundation",Vector3(-2.5,-0.15,11),Vector3(23,0.3,40),Color(0.13,0.17,0.21))
	_box("Hall outer wall",Vector3(-14,1.8,11),Vector3(0.2,3.6,40),Color(0.25,0.3,0.36))
	_box("Hall north",Vector3(-11.5,1.8,-9),Vector3(5,3.6,0.2),Color(0.25,0.3,0.36))
	_box("Hall south",Vector3(-11.5,1.8,31),Vector3(5,3.6,0.2),Color(0.25,0.3,0.36))
	_box("Hall ceiling",Vector3(-11.5,3.7,11),Vector3(5,0.2,40),Color(0.2,0.24,0.29))
	# Enclose the hall between rooms too; door gaps are the only entrances.
	for span in [Vector2(9,11),Vector2(17,18),Vector2(24,25)]:
		_box("Hall partition",Vector3(-9,1.8,(span.x+span.y)*0.5),Vector3(0.2,3.6,span.y-span.x),Color(0.25,0.3,0.36))
	_room("1 / Spatial motion",-9,9,-9,9,6,0,Color(0.22,0.37,0.43),"Stage + 4 OSC objects (3 animated)\nOSC inputs 8300 / 9200 after N")
	_room("2 / Mono cue",-9,-1,11,17,3.6,14,Color(0.43,0.30,0.22),"WARM PERCUSSION / OUTPUT 1\nE play • Q stop\n/godot/playback/mono")
	_room("3 / Stereo loop",-9,-1,18,24,3.6,21,Color(0.22,0.4,0.32),"STEREO GROOVE / MATCHING L-R\nE play • Q stop • L loop\n/godot/playback/stereo")
	_room("4 / Replay cue",-9,-1,25,31,3.6,28,Color(0.34,0.27,0.43),"GLASS & MECHANICAL / OUTPUT 2\nE play • R replay 2.5 s\n/godot/playback/replay")
	for i in 4:
		var item := get_node("Object"+str(i+1)) as SpatialFabricObject
		origins.append(item.position)
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		mesh.mesh = sphere
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = Color.from_hsv(float(i)/4.0,0.6,0.95)
		mesh.material_override = material
		item.add_child(mesh)
	if not Engine.is_editor_hint():
		var visitor := CharacterBody3D.new()
		visitor.name = "Visitor"
		visitor.set_script(preload("visitor.gd"))
		visitor.position = Vector3(-11.5,0.05,-6)
		visitor.rotation.y = PI
		add_child(visitor)
		manager = get_node("Manager") as SpatialFabricManager
		var canvas := CanvasLayer.new()
		hud = Label.new()
		hud.position = Vector2(16,16)
		canvas.add_child(hud)
		add_child(canvas)

func _hud_text() -> String:
	var cue := _current_cue()
	var line := "In hallway or spatial room: walk into a playback room"
	if cue != null:
		line = "%s  prepared:%s playing:%s loop:%s replay:%s\nE play • Q stop • L loop • R auto-replay" % [cue.name, cue.is_prepared(), cue.is_playing(), cue.loop, cue.auto_replay]
		if not cue.last_error.is_empty():
			line += "\nlast: " + cue.last_error
	var live := get_node_or_null("Live") as SpatialFabricLiveInputCue
	if live != null:
		line += "\nLive input (I): %s  peak %.2f  latency %.0f ms  xruns %d/%d — headphones or low gain: mic to speakers feeds back" % ["LIVE" if live.is_live() else "off", live.input_peak, live.latency_ms, live.underruns, live.overruns]
		if not live.last_error.is_empty():
			line += "\nlive: " + live.last_error
	var network := "LISTENING" if manager.is_listening() else "off"
	var native := "loaded" if SpatialFabricPlaybackCue.native_available() else "NOT loaded"
	return "SPATIALFABRIC GODOT\nClick capture • WASD • Shift • Space • Esc release • X stop all • N network (%s)\nNative audio: %s. Nothing starts automatically; E uses the default output device.\n%s" % [network, native, line]

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or origins.size()!=4: return
	if hud != null:
		hud.text = _hud_text()
	elapsed += delta
	for i in 3:
		var item := get_node("Object"+str(i+1)) as SpatialFabricObject
		item.position = origins[i]+Vector3(sin(elapsed+i)*1.2,sin(elapsed*0.7+i)*0.4,cos(elapsed+i)*1.2)
