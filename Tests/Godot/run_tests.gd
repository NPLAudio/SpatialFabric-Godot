extends SceneTree

var passed: Array[String] = []
var failed: Array[String] = []

func check(value: bool, label: String) -> void:
	(passed if value else failed).append(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	var stage := SpatialFabricStage.new()
	stage.dimensions_meters = Vector3(2,2,2)
	root.add_child(stage)
	var fixtures: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Tests/Fixtures/coordinates-v1.json"))
	for row in fixtures.vectors:
		var c: Array = row.canonical
		var canonical := Vector3(c[0],c[1],c[2])
		var world := Vector3(c[1],c[2],-c[0])
		check(stage.normalize_world(world).is_equal_approx(canonical), "canonical Godot -Z/X/Y / "+row.name)
		var expected: Array = row.adm_xyz
		check(SpatialFabricStage.adm_xyz(canonical).is_equal_approx(Vector3(expected[0],expected[1],expected[2])), "ADM wire axes / "+row.name)
	check(is_equal_approx(SpatialFabricStage.adm_aed(Vector3(0,1,0)).x,-90.0),"ADM positive right means negative azimuth")
	check(is_equal_approx(SpatialFabricStage.adm_xyz(Vector3(2,2,2)).length(),1.0),"ADM unit sphere limit")
	stage.rotation.y = PI*0.5
	check(stage.normalize_world(stage.global_basis*Vector3(0,0,-1)).is_equal_approx(Vector3(1,0,0)),"rotated authored stage basis")
	stage.dimensions_meters.x = 0
	check(stage.normalize_world(Vector3.ZERO)==null,"invalid stage fails closed")
	stage.queue_free()
	var osc: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Tests/Fixtures/osc-v1.json"))
	for vector in osc.valid:
		var wire := PackedByteArray()
		wire.resize(vector.hex.length() / 2)
		for i in wire.size():
			wire[i] = vector.hex.substr(i * 2, 2).hex_to_int()
		var decoded := SpatialFabricOsc.decode(wire)
		check(decoded.ok and decoded.messages.size() == 1 and decoded.messages[0].address == vector.address, "OSC decode / " + vector.name)
		check(decoded.ok and SpatialFabricOsc.encode(decoded.messages[0].address, decoded.messages[0].args) == wire, "OSC byte-exact re-encode / " + vector.name)
	for vector in osc.invalid:
		var bad := PackedByteArray()
		bad.resize(vector.hex.length() / 2)
		for i in bad.size():
			bad[i] = vector.hex.substr(i * 2, 2).hex_to_int()
		check(not SpatialFabricOsc.decode(bad).ok, "OSC rejects / " + vector.name)
	var bundle := PackedByteArray("#bundle".to_ascii_buffer())
	bundle.append_array(PackedByteArray([0,0,0,0,0,0,0,0,1]))
	var one := SpatialFabricOsc.encode("/a", [1, 0.5, "日本"])
	bundle = PackedByteArray("#bundle".to_ascii_buffer())
	bundle.append_array(PackedByteArray([0, 0,0,0,0,0,0,0,1]))
	bundle.append_array(SpatialFabricOsc._put_be32(one.size()))
	bundle.append_array(one)
	var parsed := SpatialFabricOsc.decode(bundle)
	check(parsed.ok and parsed.messages.size() == 1 and parsed.messages[0].args == [1, 0.5, "日本"], "OSC bundle + UTF-8 args")
	check(SpatialFabricOsc.encode("/a", [NAN]).is_empty() and SpatialFabricOsc.encode("a", []).is_empty() and SpatialFabricOsc.encode("/a", [2147483648]).is_empty() and SpatialFabricOsc.encode("/a", [Vector2.ZERO]).is_empty(), "OSC encode rejects invalid input")
	var many: Array = []
	many.resize(129)
	many.fill(1)
	check(SpatialFabricOsc.encode("/a", many).is_empty(), "OSC argument bound")
	var scene: Node3D = load("res://examples/four_rooms/room_showcase.tscn").instantiate()
	root.add_child(scene)
	await process_frame
	await physics_frame
	var manager := scene.get_node("Manager") as SpatialFabricManager
	var page := manager.get_scene_page()
	check(not page.has("error") and page.total==9,"nine local records")
	check(page.playback_network.listening==false and not manager.is_listening(),"no startup listener")
	check(manager.get_scene_page(0,4).returned==4 and manager.get_scene_page(4,4).next_offset==8 and manager.get_scene_page(8,4).returned==1,"bounded pagination")
	check(manager.get_scene_page(-1,4).has("error") and manager.get_scene_page(0,65).has("error"),"invalid page bounds rejected")
	var a := scene.get_node("Object1") as SpatialFabricObject
	var b := scene.get_node("Object2") as SpatialFabricObject
	var original := b.persistent_key
	b.persistent_key = a.persistent_key
	check(manager.get_scene_page().has("error") and b.persistent_key==a.persistent_key,"duplicate keys rejected without discovery repair")
	b.persistent_key = original
	var cue := scene.get_node("Mono") as SpatialFabricPlaybackCue
	check(not cue.try_play() and not cue.is_playing() and cue.prepare_source()==ERR_UNAVAILABLE and cue.refresh_devices()==ERR_UNAVAILABLE,"native backend fails closed without mixer fallback")
	cue.stop()
	check(not cue.is_playing(),"stop never invents Playing state")
	var world := scene.get_world_3d().direct_space_state
	for z in [-6.0,14.0,21.0,28.0]:
		var query := PhysicsRayQueryParameters3D.create(Vector3(-11.5,1,z),Vector3(-11.5,-1,z))
		check(not world.intersect_ray(query).is_empty(),"hall foundation / "+str(z))
		var capsule := CapsuleShape3D.new()
		capsule.radius = 0.3; capsule.height = 1.8
		var shape_query := PhysicsShapeQueryParameters3D.new()
		shape_query.shape = capsule
		shape_query.transform = Transform3D(Basis.IDENTITY,Vector3(-9,1.0,0.0 if z==-6.0 else z))
		check(world.intersect_shape(shape_query).is_empty(),"capsule door clear / "+str(z))
	var visitor := scene.get_node("Visitor") as CharacterBody3D
	var visitor_origin := visitor.position
	for z in [0.0,14.0,21.0,28.0]:
		visitor.position = Vector3(-11.5,0.08,z)
		for step in 45:
			visitor.move_and_collide(Vector3(0.1,0,0))
		check(visitor.position.x > -8.0,"actual capsule crosses doorway / "+str(z))
	visitor.position = Vector3(-11.5,0.08,5)
	for step in 45:
		visitor.move_and_collide(Vector3(0.1,0,0))
	check(visitor.position.x < -9.25,"actual capsule blocked by solid wall")
	visitor.position = visitor_origin
	manager.spatial_input_port = 18300
	manager.playback_input_port = 18301
	manager.adm_enabled = false
	var second := SpatialFabricTransport.new()
	check(manager.start_networking()==OK and manager.is_listening(),"explicit network start binds exactly")
	check(second.open([18300,18399],"127.0.0.1")!=OK and not second.is_open(),"exclusive bind refuses a second owner and rolls back")
	var probe := SpatialFabricTransport.new()
	check(probe.open([18399],"127.0.0.1")==OK,"rollback left unrelated port free")
	probe.close()
	var client := PacketPeerUDP.new()
	check(client.bind(18310,"127.0.0.1")==OK,"client reply socket")
	client.set_dest_address("127.0.0.1",18300)
	client.put_packet(SpatialFabricOsc.encode(SpatialFabricSceneQuery.QUERY,["req-1",18310,4,4]))
	client.put_packet(SpatialFabricOsc.encode(SpatialFabricSceneQuery.QUERY,["bad id!",18310]))
	var pieces: Dictionary = {}
	var expected := 0
	var waited := 0
	while waited < 120 and (expected == 0 or pieces.size() < expected):
		await process_frame
		waited += 1
		while client.get_available_packet_count() > 0:
			var reply := SpatialFabricOsc.decode(client.get_packet())
			if reply.ok and reply.messages[0].address == SpatialFabricSceneQuery.RESPONSE:
				var args: Array = reply.messages[0].args
				pieces[args[1]] = args[3]
				expected = args[2]
	var json := ""
	for i in expected:
		json += pieces.get(i,"")
	var paged = JSON.parse_string(json)
	check(expected > 0 and paged is Dictionary and paged.offset == 4 and paged.returned == 4 and paged.next_offset == 8,"real UDP scene query reassembles page")
	check(manager.queries_answered == 1 and manager.queries_ignored == 1,"invalid request ignored without reply")
	check(manager.get_scene_page().playback_network.listening == true,"scene reports observed listening state")
	manager.adm_enabled = true
	var adm := PacketPeerUDP.new()
	manager.adm_host = "127.0.0.1"
	manager.adm_port = 18320
	check(adm.bind(18320,"127.0.0.1")==OK,"ADM capture socket")
	manager.adm_mode = 2
	for i in 20:
		await process_frame
		await create_timer(0.02).timeout
	var seen: Dictionary = {}
	while adm.get_available_packet_count() > 0:
		var m := SpatialFabricOsc.decode(adm.get_packet())
		if m.ok:
			seen[m.messages[0].address] = m.messages[0].args
	check(seen.has("/adm/obj/4/xyz") and seen.has("/adm/obj/4/aed") and seen.has("/adm/obj/1/xyz"),"ADM xyz and aed emitted over UDP")
	check(seen.get("/adm/obj/1/xyz",[0,0,0]).size() == 3 and absf(seen["/adm/obj/1/xyz"][0]) <= 1.0,"ADM values are unit-sphere limited")
	manager.stop_networking()
	check(not manager.is_listening() and probe.open([18300],"127.0.0.1")==OK,"stop releases sockets")
	probe.close()
	adm.close()
	client.close()
	var report := {"status":"passed" if failed.is_empty() else "failed", "passed":passed, "failed":failed, "scope":"Godot port: codec, explicit loopback UDP, scene query and ADM verified; no native audio or hardware certification."}
	var args := OS.get_cmdline_user_args()
	if args.size()>0:
		var file := FileAccess.open(args[0],FileAccess.WRITE)
		if file == null:
			push_error("Cannot write test evidence")
			quit(1)
			return
		file.store_string(JSON.stringify(report,"\t"))
	print(JSON.stringify(report))
	quit(0 if failed.is_empty() else 1)
