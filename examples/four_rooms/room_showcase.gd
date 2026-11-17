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

## Explicit user action. Starting also enables ADM position output (otherwise the example would listen but send nothing);
## stopping turns it off again. Returns the manager's start result.
func toggle_networking() -> Error:
	if manager.is_listening():
		manager.stop_networking()
		manager.adm_enabled = false
		return OK
	var result := manager.start_networking()
	manager.adm_enabled = result == OK
	return result

func _osc_summary() -> String:
	if not manager.is_listening():
		return "OSC off (N): ADM output, state output and inputs are all stopped"
	return "OSC ON — in %d/%d • ADM xyz → %s:%d • state → %s:%d" % [manager.spatial_input_port, manager.playback_input_port, manager.adm_host, manager.adm_port, manager.monitor_host, manager.monitor_port]

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
			if cue != null:
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
			toggle_networking()

func _box(label: String, center: Vector3, size: Vector3, color: Color) -> void:
	var body := StaticBody3D.new()
	body.name = label
	body.position = center
	var mesh := MeshInstance3D.new()
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	mesh.material_override = _surface(label, color)
	body.add_child(mesh)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	add_child(body)

var _floor_texture: ImageTexture

## A 256 px tile with a thin groove, sampled in world space so the floor reads as large polished tiles.
func _tile_texture() -> ImageTexture:
	if _floor_texture == null:
		var image := Image.create(256, 256, false, Image.FORMAT_RGB8)
		image.fill(Color(0.74, 0.76, 0.80))
		for i in 256:
			for w in 3:
				image.set_pixel(i, w, Color(0.42, 0.44, 0.48))
				image.set_pixel(w, i, Color(0.42, 0.44, 0.48))
		image.generate_mipmaps()
		_floor_texture = ImageTexture.create_from_image(image)
	return _floor_texture

## Lit PBR surfaces: polished tiled floor, softly lit matte walls and ceilings.
func _surface(label: String, color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.88
	if label.contains("foundation"):
		material.albedo_texture = _tile_texture()
		material.albedo_color = Color(0.52, 0.52, 0.55) # neutral mid-tone: the tile texture carries the pattern, room lights add the colour
		material.uv1_triplanar = true
		material.uv1_world_triplanar = true
		material.uv1_scale = Vector3(0.25, 0.25, 0.25)
		material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
		material.roughness = 0.42
		material.metallic = 0.04
	elif label.contains("ceiling"):
		material.roughness = 0.95
	return material

func _glow(color: Color, energy: float) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = energy
	material.roughness = 0.4
	return material

func _decor(label: String, center: Vector3, size: Vector3, material: Material) -> void:
	var mesh := MeshInstance3D.new() # visual only: no collision
	mesh.name = label
	var cube := BoxMesh.new()
	cube.size = size
	mesh.mesh = cube
	mesh.material_override = material
	mesh.position = center
	add_child(mesh)

func _light(label: String, point: Vector3, color: Color, energy: float, light_range: float, shadow: bool) -> void:
	var light := OmniLight3D.new()
	light.name = label
	light.position = point
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = 1.3
	light.shadow_enabled = shadow
	add_child(light)

func _environment() -> void:
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.015, 0.02, 0.035)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.66, 0.68, 0.74)
	environment.ambient_light_energy = 0.9
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 1.05
	environment.glow_enabled = true
	environment.glow_intensity = 0.45
	environment.glow_bloom = 0.08
	environment.glow_hdr_threshold = 1.15
	environment.ssao_enabled = true
	environment.ssao_radius = 1.2
	environment.ssao_intensity = 2.0
	environment.fog_enabled = true
	environment.fog_light_color = Color(0.1, 0.13, 0.2)
	environment.fog_density = 0.004
	environment.adjustment_enabled = true
	environment.adjustment_contrast = 1.08
	environment.adjustment_saturation = 1.12
	var node := WorldEnvironment.new()
	node.name = "Environment"
	node.environment = environment
	add_child(node)

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
	# Lighting: a ceiling panel with a real shadow-casting light, and a glowing door frame in the room's accent colour.
	var accent := tint.lerp(Color.WHITE, 0.25)
	_decor(label+" light panel", Vector3(center.x,height-0.02,center.z), Vector3(clampf(width*0.3,1.0,3.0),0.04,clampf(depth*0.2,1.0,2.0)), _glow(Color(1.0, 0.96, 0.9), 1.15))
	_light(label+" light", Vector3(center.x,height-0.5,center.z), tint.lerp(Color.WHITE, 0.55), 3.2 if height < 5.0 else 4.2, maxf(width,depth)*1.25, true)
	_decor(label+" door glow", Vector3(x_min-0.02,2.42,door), Vector3(0.06,0.07,2.25), _glow(accent, 3.2))
	_decor(label+" threshold", Vector3(x_min+0.3,0.015,door), Vector3(0.6,0.03,2.2), _glow(accent, 1.4))
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
	_room("1 / Spatial motion",-9,9,-9,9,6,0,Color(0.22,0.37,0.43),"Stage + 4 OSC objects (3 animated)\nOSC inputs 8100 / 9000 after N")
	_room("2 / Mono cue",-9,-1,11,17,3.6,14,Color(0.43,0.30,0.22),"WARM PERCUSSION / OUTPUT 1\nE play • Q stop\n/godot/playback/mono")
	_room("3 / Stereo loop",-9,-1,18,24,3.6,21,Color(0.22,0.4,0.32),"STEREO GROOVE / MATCHING L-R\nE play • Q stop • L loop\n/godot/playback/stereo")
	_room("4 / Replay cue",-9,-1,25,31,3.6,28,Color(0.34,0.27,0.43),"GLASS & MECHANICAL / OUTPUT 2\nE play • R replay 2.5 s\n/godot/playback/replay")
	_environment()
	# Hall: evenly spaced ceiling strips with lights, so the walk between rooms is lit rather than flat.
	for z in [-5.0, 5.0, 15.0, 25.0]:
		_decor("Hall light panel", Vector3(-11.5,3.58,z), Vector3(1.4,0.04,3.2), _glow(Color(1.0, 0.95, 0.88), 1.9))
		_light("Hall light", Vector3(-11.5,3.0,z), Color(1.0, 0.93, 0.82), 3.2, 10.0, false)
	# Spatial room: corner lights and a glowing outline of the stage footprint.
	for corner in [Vector2(-6,-6), Vector2(6,-6), Vector2(-6,6), Vector2(6,6)]:
		_light("Stage light", Vector3(corner.x,5.4,corner.y), Color(0.7, 0.88, 1.0), 4.0, 15.0, true)
	var outline := _glow(Color(0.25, 0.75, 0.95), 2.2)
	_decor("Stage outline N", Vector3(0,0.02,-8.0), Vector3(16,0.04,0.12), outline)
	_decor("Stage outline S", Vector3(0,0.02,8.0), Vector3(16,0.04,0.12), outline)
	_decor("Stage outline W", Vector3(-8.0,0.02,0), Vector3(0.12,0.04,16), outline)
	_decor("Stage outline E", Vector3(8.0,0.02,0), Vector3(0.12,0.04,16), outline)
	for i in 4:
		var item := get_node("Object"+str(i+1)) as SpatialFabricObject
		origins.append(item.position)
		var mesh := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		mesh.mesh = sphere
		var tint := Color.from_hsv(float(i)/4.0,0.65,1.0)
		mesh.material_override = _glow(tint, 2.4)
		item.add_child(mesh)
		var glow := OmniLight3D.new() # each OSC object lights its surroundings in its own colour
		glow.light_color = tint
		glow.light_energy = 1.6
		glow.omni_range = 4.5
		item.add_child(glow)
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
		var user_args := OS.get_cmdline_user_args()
		var check_at := user_args.find("--sf-selfcheck")
		if check_at >= 0 and check_at + 1 < user_args.size():
			var shot_at := user_args.find("--sf-shot")
			_selfcheck.call_deferred(user_args[check_at + 1], user_args[shot_at + 1] if shot_at >= 0 and shot_at + 1 < user_args.size() else "")

## Release gate: verifies an exported build without sound, sockets or devices, then quits.
## Usage: game.exe -- --sf-selfcheck report.json [--sf-shot view.png]
func _selfcheck(report_path: String, shot_path: String) -> void:
	for i in 8:
		await get_tree().process_frame
	var page := manager.get_scene_page()
	var playing := false
	for cue_node in manager._cues():
		playing = playing or cue_node.is_playing()
	var live := get_node_or_null("Live") as SpatialFabricLiveInputCue
	var sources_ok := true
	var source_errors := {}
	for cue_node in manager._cues():
		var decoded := SpatialFabricWav.load_file(cue_node.source_path)
		sources_ok = sources_ok and decoded.ok
		if not decoded.ok:
			source_errors[cue_node.source_path] = decoded.error
	var report := {
		"sources_decodable": sources_ok,
		"source_errors": source_errors,
		"engine": Engine.get_version_info().string,
		"exported_template": OS.has_feature("template"),
		"native_playback": SpatialFabricPlaybackCue.native_available(),
		"native_live_input": SpatialFabricLiveInputCue.native_available(),
		"inventory_records": page.get("total", -1),
		"inventory_error": page.get("error", ""),
		"listening_at_startup": manager.is_listening(),
		"playing_at_startup": playing,
		"live_at_startup": live != null and live.is_live(),
	}
	var user_args := OS.get_cmdline_user_args()
	if user_args.has("--sf-osc"):
		# Prove the exported build really sends: same code path as the N key, on test ports.
		manager.spatial_input_port = 18710
		manager.playback_input_port = 19710
		var port_at := user_args.find("--sf-adm-port")
		if port_at >= 0 and port_at + 1 < user_args.size():
			manager.adm_port = int(user_args[port_at + 1])
		report["osc_started"] = toggle_networking() == OK
		report["adm_enabled_after_start"] = manager.adm_enabled
		await get_tree().create_timer(1.5).timeout
		report["adm_packets_sent_counter"] = manager._adm_sent
		toggle_networking()
	if shot_path != "":
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(shot_path)
		report["screenshot"] = shot_path
	report["status"] = "passed" if report.sources_decodable and report.native_playback and report.native_live_input and report.inventory_records == 10 and report.inventory_error == "" and not report.listening_at_startup and not report.playing_at_startup and not report.live_at_startup else "failed"
	var file := FileAccess.open(report_path, FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(report, "\t"))
	print(JSON.stringify(report))
	get_tree().quit(0 if report.status == "passed" else 1)

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
	var network := _osc_summary()
	var native := "loaded" if SpatialFabricPlaybackCue.native_available() else "NOT loaded"
	return "SPATIALFABRIC GODOT\nClick capture • WASD • Shift • Space • Esc release • X stop all • N OSC on/off\n%s\nNative audio: %s. Nothing starts automatically; E uses the default output device.\n%s" % [network, native, line]

func _process(delta: float) -> void:
	if Engine.is_editor_hint() or origins.size()!=4: return
	if hud != null:
		hud.text = _hud_text()
	elapsed += delta
	for i in 3:
		var item := get_node("Object"+str(i+1)) as SpatialFabricObject
		item.position = origins[i]+Vector3(sin(elapsed+i)*1.2,sin(elapsed*0.7+i)*0.4,cos(elapsed+i)*1.2)
