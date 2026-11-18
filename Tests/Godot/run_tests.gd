extends SceneTree

var passed: Array[String] = []
var failed: Array[String] = []

func check(value: bool, label: String) -> void:
	(passed if value else failed).append(label)

func _initialize() -> void:
	call_deferred("run")

func run() -> void:
	preload("res://Tests/Godot/routing_tests.gd").run(self, check)
	preload("res://Tests/Godot/parity_tests.gd").run(self, check)
	await preload("res://Tests/Godot/ack_tests.gd").run(self, check)
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
	check(not page.has("error") and page.total==10,"ten local records")
	check(page.playback_network.listening==false and not manager.is_listening(),"no startup listener")
	check(manager.get_scene_page(0,4).returned==4 and manager.get_scene_page(4,4).next_offset==8 and manager.get_scene_page(8,4).returned==2,"bounded pagination")
	check(manager.get_scene_page(-1,4).has("error") and manager.get_scene_page(0,65).has("error"),"invalid page bounds rejected")
	var a := scene.get_node("Object1") as SpatialFabricObject
	var b := scene.get_node("Object2") as SpatialFabricObject
	var original := b.persistent_key
	b.persistent_key = a.persistent_key
	check(manager.get_scene_page().has("error") and b.persistent_key==a.persistent_key,"duplicate keys rejected without discovery repair")
	b.persistent_key = original
	var cue := scene.get_node("Mono") as SpatialFabricPlaybackCue
	cue.device_id = "godot-test-invalid-output" # Play prepares on demand, so keep every test start on an invalid device
	var bare := SpatialFabricPlaybackCue.new()
	check(not bare.try_play() and not bare.is_playing() and not bare.last_error.is_empty(), "cue without a source refuses to play (no mixer fallback)")
	bare.free()
	cue.stop()
	check(not cue.is_playing(), "stop never invents Playing state")
	check(SpatialFabricPlaybackControl.should_play([]) and SpatialFabricPlaybackControl.should_play([0.5]) and not SpatialFabricPlaybackControl.should_play([0.49]) and SpatialFabricPlaybackControl.should_play([1]) and not SpatialFabricPlaybackControl.should_play([0]) and not SpatialFabricPlaybackControl.should_play(["go"]), "play trigger semantics")
	check(SpatialFabricPlaybackControl.should_play([0, 0.9]) == true and SpatialFabricPlaybackControl.should_play([1, 0.1]) == false, "first float anywhere precedes first int")
	check(SpatialFabricPlaybackControl.loop_value([0.5]) == false and SpatialFabricPlaybackControl.loop_value([0.51]) == true and SpatialFabricPlaybackControl.loop_value([1]) == true and SpatialFabricPlaybackControl.loop_value([]) == false and SpatialFabricPlaybackControl.loop_value(["x"]) == null, "loop trigger semantics")
	var wavs := {"SW_SF_MonoCue.wav": 1, "SW_SF_StereoLoop.wav": 2, "SW_SF_ReplayCue.wav": 1}
	for name in wavs:
		var wav := SpatialFabricWav.load_file("res://examples/four_rooms/audio/" + name)
		check(wav.ok and wav.channels == wavs[name] and wav.rate == 48000 and wav.samples.size() > 4800, "WAV decode / " + name)
	check(not SpatialFabricWav.decode(PackedByteArray([1, 2, 3])).ok and not SpatialFabricWav.load_file("res://missing.wav").ok, "WAV rejects invalid input")
	var tiny := FileAccess.get_file_as_bytes("res://examples/four_rooms/audio/SW_SF_MonoCue.wav")
	var broken := tiny.slice(0, 30)
	check(not SpatialFabricWav.decode(broken).ok, "WAV rejects truncated header")
	var script: Script = scene.get_script()
	check(script._output_summary(-1.0, 0).contains("unavailable") and script._output_summary(7.25, 3).contains("7.25 ms") and script._output_summary(7.25, 3).contains("shared fallback"), "HUD displays OS latency and actual fallback mode without inventing inactive latency")
	check(script.cue_name_at(Vector3(-5, 1, 14)) == "Mono" and script.cue_name_at(Vector3(-5, 1, 21)) == "Stereo" and script.cue_name_at(Vector3(-5, 1, 28)) == "Replay" and script.cue_name_at(Vector3(-11.5, 1, 14)) == "" and script.cue_name_at(Vector3(0, 1, 0)) == "", "room-to-cue mapping")
	var replay := scene.get_node("Replay") as SpatialFabricPlaybackCue
	var events: Array = []
	replay.state_changed.connect(func(on: bool): events.append(on))
	replay.observe({"state": 2, "reason": 0, "started_sequence": 1, "ended_sequence": 0, "error": ""})
	check(replay.is_playing() and events == [true], "observed start becomes Playing")
	replay.observe({"state": 0, "reason": 1, "started_sequence": 1, "ended_sequence": 1, "error": ""})
	check(not replay.is_playing() and replay.replay_pending() and events == [true, false], "natural end schedules replay")
	replay.stop()
	check(not replay.replay_pending(), "stop cancels replay")
	replay.observe({"state": 0, "reason": 1, "started_sequence": 2, "ended_sequence": 2, "error": ""})
	check(events == [true, false, true, false] and replay.replay_pending(), "short clip start/end between polls is preserved")
	replay.stop()
	replay.observe({"state": 4, "reason": 3, "started_sequence": 2, "ended_sequence": 3, "error": "device lost"})
	check(not replay.replay_pending() and not replay.is_playing() and replay.last_error == "device lost", "device failure never replays or reports Playing")
	var live_cue := scene.get_node("Live") as SpatialFabricLiveInputCue
	var live_events: Array = []
	live_cue.state_changed.connect(func(on: bool): live_events.append(on))
	check(not live_cue.is_live(), "live input is off at startup")
	live_cue.observe({"state": 2, "reason": 0, "started_sequence": 1, "ended_sequence": 0, "error": "", "input_peak": 0.5, "input_rate": 48000, "latency_frames": 960})
	check(live_cue.is_live() and live_events == [true] and live_cue.input_peak == 0.5 and absf(live_cue.latency_ms - 20.0) < 0.01, "observed start becomes live with peak and latency")
	live_cue.observe({"state": 0, "reason": 2, "started_sequence": 1, "ended_sequence": 1, "error": ""})
	check(not live_cue.is_live() and live_events == [true, false], "observed end clears live")
	live_cue.observe({"state": 4, "reason": 3, "started_sequence": 1, "ended_sequence": 1, "error": "input lost"})
	check(not live_cue.is_live() and live_cue.last_error == "input lost" and live_events == [true, false], "device failure never reports live")
	check(not live_cue.set_gain(5.0) and not live_cue.set_gain(NAN) and not live_cue.set_gain(-0.1) and live_cue.gain == 1.0 and live_cue.set_gain(0.5) and live_cue.gain == 0.5, "live gain bounded")
	check(SpatialFabricPlaybackControl.gain_value([0.25]) == 0.25 and SpatialFabricPlaybackControl.gain_value([2]) == 2.0 and SpatialFabricPlaybackControl.gain_value([4.1]) == null and SpatialFabricPlaybackControl.gain_value([]) == null and SpatialFabricPlaybackControl.gain_value(["x"]) == null, "OSC live gain semantics")
	var live_row: Dictionary = manager.get_scene_page(8, 4).objects.filter(func(o): return o.kind == "live_input")[0]
	check(live_row.controls.gain == "/godot/live/input/gain" and live_row.playing == false and not manager.get_scene_page(8, 4).has("error"), "discovery reports live input read-only")
	if ClassDB.class_exists("SFNativeLive"):
		var input_inventory: Dictionary = ClassDB.instantiate("SFNativeLive").input_devices_json()
		check(input_inventory.ok and JSON.parse_string(input_inventory.json) != null and SpatialFabricLiveInputCue.native_available(), "explicit input inventory parses without opening a stream")
		check(live_cue.refresh_input_devices() == OK, "cue input refresh is explicit")
		live_cue.input_device_id = "godot-test-invalid-input"
		live_cue.output_device_id = "godot-test-invalid-output"
		check(live_cue.try_start(), "live start is a request")
		var live_waited := 0
		while live_waited < 120 and live_cue.last_error.is_empty():
			await create_timer(0.025).timeout
			live_waited += 1
		check(live_cue.worker_state == 4 and not live_cue.is_live() and live_cue.last_error.contains("no default fallback") and live_events == [true, false], "invalid input device fails without a false live state")
		live_cue.stop()
		check(not live_cue.is_live(), "live stop after failure")
	else:
		check(not live_cue.try_start() and not live_cue.is_live() and not live_cue.last_error.is_empty(), "live input fails closed without the native library")
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
	if ClassDB.class_exists("SFNativePlayer"):
		manager.monitor_port = 18302
		manager.stop_networking()
		check(manager.start_networking() == OK, "restart with monitor port")
		var monitor := PacketPeerUDP.new()
		check(monitor.bind(18302, "127.0.0.1") == OK, "monitor capture socket")
		var mono := scene.get_node("Mono") as SpatialFabricPlaybackCue
		mono.device_id = "godot-test-nonexistent-device"
		check(mono.prepare_source() == OK and mono.is_prepared() and mono.refresh_devices() == OK, "explicit prepare and device refresh")
		check(not mono.is_playing(), "preparation never plays")
		client.set_dest_address("127.0.0.1", 18301)
		client.put_packet(SpatialFabricOsc.encode("/godot/playback/mono/play", []))
		client.put_packet(SpatialFabricOsc.encode("/godot/playback/mono/loop", [1]))
		for i in 80:
			await create_timer(0.025).timeout
			if not mono.last_error.is_empty():
				break
		await create_timer(0.1).timeout
		var feedback := preload("res://Tests/Godot/ack_tests.gd").drain(monitor)
		var states := feedback.filter(func(m): return m.address.ends_with("/state"))
		var play_acks := feedback.filter(func(m): return m.address.ends_with("/ack") and m.args[0] == "play")
		check(mono.loop and not mono.is_playing() and states.is_empty() and not mono.last_error.is_empty(), "OSC play on an invalid device: loop applied, no false Playing or state")
		check(play_acks.size() == 2 and play_acks[0].args == ["play", "received", 0, ""] and play_acks[1].args[1] == "failed" and play_acks[1].args[2] == 0 and str(play_acks[1].args[3]).contains("no default fallback"), "native playback received then async failure ack")
		# The reported bug: OSC /play on a cue nobody prepared must prepare it on demand, then fail closed on a bad device.
		var stereo := scene.get_node("Stereo") as SpatialFabricPlaybackCue
		stereo.device_id = "godot-test-invalid-output"
		check(not stereo.is_prepared(), "stereo cue starts unprepared")
		client.put_packet(SpatialFabricOsc.encode("/godot/playback/stereo/play", []))
		for tick in 120:
			await create_timer(0.025).timeout
			if stereo.last_error.contains("no default fallback"):
				break
		check(stereo.is_prepared() and not stereo.is_playing() and stereo.last_error.contains("no default fallback"), "OSC play on an unprepared cue prepares it on demand and reaches the device (fails closed on a bad device)")
		await create_timer(0.05).timeout
		feedback = preload("res://Tests/Godot/ack_tests.gd").drain(monitor)
		play_acks = feedback.filter(func(m): return m.address.ends_with("/ack") and m.args[0] == "play")
		check(play_acks.size() == 2 and play_acks[0].args[1] == "received" and play_acks[1].args[1] == "failed", "on-demand preparation preserves received then async failure ack")
		if ClassDB.class_exists("SFNativeLive"):
			live_cue.input_device_id = "godot-test-invalid-input"
			live_cue.output_device_id = "godot-test-invalid-output"
			client.put_packet(SpatialFabricOsc.encode(live_cue.osc_base + "/play", []))
			await create_timer(0.3).timeout
			feedback = preload("res://Tests/Godot/ack_tests.gd").drain(monitor)
			play_acks = feedback.filter(func(m): return m.address == live_cue.osc_base + "/ack" and m.args[0] == "play")
			check(play_acks.size() == 2 and play_acks[0].args == ["play", "received", 0, ""] and play_acks[1].args[1] == "failed" and play_acks[1].args[2] == 0 and str(play_acks[1].args[3]).contains("no default fallback"), "native live received then async failure ack")
		monitor.close()
	manager.stop_networking()
	check(not manager.is_listening() and probe.open([18300],"127.0.0.1")==OK,"stop releases sockets")
	probe.close()
	adm.close()
	client.close()
	var require_native := OS.get_cmdline_user_args().has("--require-native")
	if not ClassDB.class_exists("SFNativeBuffer"):
		check(not require_native, "native extension loaded")
	else:
		check(ClassDB.instantiate("SFNativePlayer").abi_version() == 1, "native ABI v1")
		check(ClassDB.instantiate("SFNativePlayer").start(null, "godot-test-invalid-output", 0, false, 20, false) == 0, "native wrapper refuses missing buffer with zero")
		var pcm := PackedFloat32Array()
		for i in 480:
			pcm.append(sin(float(i) * 0.2) * 0.5 + 0.1)
		var native: Object = ClassDB.instantiate("SFNativeBuffer")
		check(native.create(pcm, 1, 48000) and native.is_valid(), "native immutable PCM copy")
		pcm.fill(0.0) # prove the native buffer does not alias the caller's array
		var routed: Dictionary = native.render(960, 2, 48000, 2, false, 0.0)
		var rs: PackedFloat32Array = routed.samples
		var left_silent := true
		var right_audible := false
		for f in 480:
			left_silent = left_silent and rs[f * 2] == 0.0
			right_audible = right_audible or absf(rs[f * 2 + 1]) > 0.05
		check(left_silent and right_audible, "native channel 2 routes source to one physical output")
		var tail_zero := true
		for f in range(500, 960):
			tail_zero = tail_zero and rs[f * 2] == 0.0 and rs[f * 2 + 1] == 0.0
		check(tail_zero, "native EOF is zero tailed")
		var bad := PackedFloat32Array([0.0, NAN])
		var rejected: Object = ClassDB.instantiate("SFNativeBuffer")
		check(not rejected.create(bad, 1, 48000) and not rejected.get_error().is_empty(), "native rejects non-finite PCM")
		check(not ClassDB.instantiate("SFNativeBuffer").create(PackedFloat32Array(), 1, 48000), "native rejects empty PCM")
		var inventory: Dictionary = ClassDB.instantiate("SFNativePlayer").devices_json()
		check(inventory.ok and JSON.parse_string(inventory.json) != null, "explicit device inventory parses")
		var native_player: Object = ClassDB.instantiate("SFNativePlayer")
		check(native_player.status().state == 0, "new native player stopped")
		native_player.start(native, "godot-test-nonexistent-device", 0, false, 20, false)
		var final_state := -1
		for tick in 120:
			await create_timer(0.025).timeout
			final_state = native_player.status().state
			if final_state == 4 or final_state == 2:
				break
		var final_status: Dictionary = native_player.status()
		check(final_state == 4 and final_status.started_sequence == 0 and not final_status.error.is_empty(), "invalid device fails without false Playing")
		native_player.stop()
		check(native_player.status().state != 2, "stop after failure stays not playing")
	# The example's N key: starting OSC must also enable ADM output, and the HUD must name where it goes.
	scene.manager.spatial_input_port = 18500
	scene.manager.playback_input_port = 19500
	scene.manager.adm_enabled = false
	check(not scene.manager.is_listening() and "OSC off" in scene._osc_summary(), "example starts with OSC off")
	check(scene.toggle_networking() == OK and scene.manager.is_listening() and scene.manager.adm_enabled, "N starts OSC and enables ADM output")
	var summary: String = scene._osc_summary()
	check("ADM xyz" in summary and ":%d" % scene.manager.adm_port in summary and ":%d" % scene.manager.monitor_port in summary, "HUD names the ADM and state output ports")
	var adm_sink := PacketPeerUDP.new()
	check(adm_sink.bind(scene.manager.adm_port, "127.0.0.1") == OK, "ADM destination socket")
	var got_adm := false
	for tick in 60:
		await create_timer(0.02).timeout
		if adm_sink.get_available_packet_count() > 0:
			got_adm = SpatialFabricOsc.decode(adm_sink.get_packet()).ok
			break
	check(got_adm, "toggling networking on really sends ADM packets to the configured port")
	# Static object 4 never moves: it must still be (re-)sent so a late-starting receiver learns it.
	scene.manager.adm_refresh_seconds = 0.2
	var object_4_packets := 0
	for tick in 70:
		await create_timer(0.02).timeout
		while adm_sink.get_available_packet_count() > 0:
			var decoded := SpatialFabricOsc.decode(adm_sink.get_packet())
			if decoded.ok and decoded.messages[0].address == "/adm/obj/4/xyz":
				object_4_packets += 1
	check(object_4_packets >= 2, "static object is refreshed periodically (%d packets)" % object_4_packets)
	adm_sink.close()
	check(scene.toggle_networking() == OK and not scene.manager.is_listening() and not scene.manager.adm_enabled, "N again stops OSC and ADM output")
	var report := {"status":"passed" if failed.is_empty() else "failed", "passed":passed, "failed":failed, "scope":"Godot port: codec, loopback UDP, scene query, ADM and silent native checks. No physical audio certification."}
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
