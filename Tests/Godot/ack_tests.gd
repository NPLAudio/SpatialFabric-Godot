extends RefCounted
## No device is opened: fake start requests feed the real cue observation/manager code.

class Playback extends SpatialFabricPlaybackCue:
	var accept := true
	func try_play() -> bool:
		if not accept:
			last_error = "no source"
			return false
		_start_pending = true
		return true

class Live extends SpatialFabricLiveInputCue:
	func try_start() -> bool:
		_start_pending = true
		return true

class Buffer extends RefCounted:
	func is_valid() -> bool:
		return true

class Worker extends RefCounted:
	var snapshot := {"state": 0, "reason": 0, "started_sequence": 0, "ended_sequence": 0, "error": ""}
	var accept := true
	func status() -> Dictionary:
		return snapshot.duplicate()
	func stop() -> void:
		if snapshot.state == 2:
			snapshot.ended_sequence += 1
		snapshot.state = 0
		snapshot.reason = 2
	func start(_buffer: Object, _device: String, _channel: int, _exclusive: bool, _ms: int, _loop: bool) -> int:
		snapshot.state = 1 if accept else 4
		snapshot.error = "" if accept else "invalid route"
		return 1 if accept else 0

static func drain(socket: PacketPeerUDP) -> Array:
	var messages: Array = []
	while socket.get_available_packet_count() > 0:
		var decoded := SpatialFabricOsc.decode(socket.get_packet())
		if decoded.ok:
			messages.append_array(decoded.messages)
	return messages

static func run(tree: SceneTree, check: Callable) -> void:
	var fixture: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://Tests/Fixtures/ack-v1.json"))
	for vector in fixture.vectors:
		var packet := SpatialFabricOsc.encode(vector.address, [vector.command, vector.result, int(vector.playing), vector.detail])
		check.call(packet.hex_encode() == vector.hex, "ack golden bytes / " + vector.name)
	for row in fixture.decisions:
		var args: Array = []
		for arg in row.args:
			args.append(float(arg[1]) if arg[0] == "f" else int(arg[1]) if arg[0] == "i" else str(arg[1]))
		var result := SpatialFabricPlaybackControl.decision(row.kind, row.op, args)
		check.call(result.result == row.result and (result.result == "received") == row.acts, "ack decision / " + row.kind + " " + row.op + " " + str(args))
	check.call(SpatialFabricPlaybackControl.decision("live", "status", [1]).result == "rejected", "status rejects arguments")
	check.call(SpatialFabricPlaybackControl.safe_command("bad\n日本/".repeat(10)).length() == 32 and not SpatialFabricPlaybackControl.safe_command("bad\n日本").contains("\n"), "ack suffix sanitized and bounded")
	var manager := SpatialFabricManager.new()
	var playback := Playback.new()
	playback.name = "Playback"
	playback.osc_base = "/test/playback"
	var live := Live.new()
	live.name = "Live"
	live.osc_base = "/test/live"
	manager.add_child(playback)
	manager.add_child(live)
	manager.cue_paths = [NodePath("Playback")]
	manager.live_paths = [NodePath("Live")]
	manager.spatial_input_port = 18400
	manager.playback_input_port = 18401
	manager.monitor_port = 18402
	tree.root.add_child(manager)
	var monitor := PacketPeerUDP.new()
	check.call(monitor.bind(18402, "127.0.0.1") == OK and manager.start_networking() == OK, "ack UDP monitor and manager bind")
	var sender := PacketPeerUDP.new()
	sender.set_dest_address("127.0.0.1", 18401)
	sender.put_packet(SpatialFabricOsc.encode(playback.osc_base + "/status", []))
	await tree.create_timer(0.05).timeout
	var status_reply := drain(monitor)
	check.call(status_reply.size() == 2 and status_reply[0].args == ["status", "received", 0, ""] and status_reply[1].args == [0.0], "real UDP status replies to monitor, not sender")
	sender.close()
	for row in fixture.decisions:
		var cue: Node = playback if row.kind == "playback" else live
		var args: Array = []
		for arg in row.args:
			args.append(float(arg[1]) if arg[0] == "f" else int(arg[1]) if arg[0] == "i" else str(arg[1]))
		manager._dispatch_playback({"address": cue.osc_base + "/" + row.op, "args": args})
		await tree.create_timer(0.01).timeout
		var replies := drain(monitor)
		var acks := replies.filter(func(m): return m.address.ends_with("/ack"))
		if row.op in ["ack", "state"]:
			check.call(replies.is_empty(), "feedback suppressed / " + row.op)
		else:
			check.call(acks.size() == 1 and acks[0].args == [row.op, row.result, 0, SpatialFabricPlaybackControl.decision(row.kind, row.op, args).detail], "ack dispatch / " + row.kind + " " + row.op + " " + str(args))
		# Each decision vector is independent, not a chain of replacement requests.
		manager._pending_starts.erase(cue)
		cue.stop()
	# Clear pending requests via explicit stops before testing lifecycle followups.
	for cue in [playback, live]:
		manager._dispatch_playback({"address": cue.osc_base + "/stop", "args": []})
	await tree.create_timer(0.02).timeout
	drain(monitor)
	for cue in [playback, live]:
		manager._dispatch_playback({"address": cue.osc_base + "/play", "args": []})
		cue.observe({"state": 4, "reason": 3, "started_sequence": 0, "ended_sequence": 0, "error": "device refused"})
		cue.observe({"state": 4, "reason": 3, "started_sequence": 0, "ended_sequence": 0, "error": "device refused"})
		await tree.create_timer(0.02).timeout
		var replies := drain(monitor)
		check.call(replies.size() == 2 and replies[0].args == ["play", "received", 0, ""] and replies[1].args == ["play", "failed", 0, "device refused"], "async failure exactly once, no false state / " + cue.name)
		manager._dispatch_playback({"address": cue.osc_base + "/play", "args": []})
		cue.observe({"state": 2, "reason": 0, "started_sequence": 1, "ended_sequence": 0, "error": ""})
		manager._dispatch_playback({"address": cue.osc_base + "/status", "args": []})
		await tree.create_timer(0.02).timeout
		replies = drain(monitor)
		check.call(replies.size() == 4 and replies[0].args == ["play", "received", 0, ""] and replies[1].args == [1.0] and replies[2].args == ["status", "received", 1, ""] and replies[3].args == [1.0], "received then observed start and status / " + cue.name)
		cue.observe({"state": 0, "reason": 1, "started_sequence": 1, "ended_sequence": 1, "error": ""})
		await tree.create_timer(0.02).timeout
		replies = drain(monitor)
		check.call(replies.size() == 1 and replies[0].args == [0.0], "natural end state / " + cue.name)
	playback.accept = false
	manager._dispatch_playback({"address": playback.osc_base + "/play", "args": []})
	manager._dispatch_playback({"address": "/unknown/play", "args": []})
	await tree.create_timer(0.02).timeout
	var replies := drain(monitor)
	check.call(replies.size() == 1 and replies[0].args == ["play", "failed", 0, "no source"], "sync refusal failed; unknown base silent")
	# Bindings can resolve after networking begins and must stop reporting once removed.
	for late in [Playback.new(), Live.new()]:
		late.name = "Late"
		late.osc_base = "/test/late"
		manager.add_child(late)
		if late is SpatialFabricLiveInputCue:
			manager.live_paths.append(NodePath("Late"))
		else:
			manager.cue_paths.append(NodePath("Late"))
		manager._dispatch_playback({"address": late.osc_base + "/play", "args": []})
		late.observe({"state": 4, "reason": 3, "started_sequence": 0, "ended_sequence": 0, "error": "late failure"})
		await tree.create_timer(0.02).timeout
		replies = drain(monitor)
		check.call(replies.size() == 2 and replies[1].args == ["play", "failed", 0, "late failure"], "late binding async failure / " + late.get_class())
		manager.cue_paths.erase(NodePath("Late"))
		manager.live_paths.erase(NodePath("Late"))
		manager._process(0.0)
		late.state_changed.emit(true)
		await tree.create_timer(0.02).timeout
		check.call(drain(monitor).is_empty(), "removed binding disconnected")
		manager.remove_child(late)
		late.free()
	var freed := Playback.new()
	freed.name = "Freed"
	manager.add_child(freed)
	manager.cue_paths.append(NodePath("Freed"))
	manager._sync_cue_signals()
	freed.free()
	manager._process(0.0)
	check.call(manager._wired_cues.size() == 2, "freed binding safely disconnected")
	manager.cue_paths.erase(NodePath("Freed"))
	# Exercise the real playback request code against a device-free worker, including
	# cumulative sequences from a previous worker and synchronous route refusal.
	var real := SpatialFabricPlaybackCue.new()
	real.name = "Real"
	real.osc_base = "/test/real"
	var worker := Worker.new()
	real._player = worker
	real._buffer = Buffer.new()
	manager.add_child(real)
	manager.stop_networking()
	manager.cue_paths.append(NodePath("Real"))
	check.call(manager.start_networking() == OK, "ack signal reconnect")
	manager._dispatch_playback({"address": real.osc_base + "/play", "args": []})
	# Worker A really started, but no regular cue poll has run yet.
	worker.snapshot.state = 2
	worker.snapshot.started_sequence = 1
	manager._dispatch_playback({"address": real.osc_base + "/play", "args": []})
	manager._dispatch_playback({"address": real.osc_base + "/status", "args": []})
	worker.snapshot.state = 4
	worker.snapshot.error = "replacement failed"
	real.poll_status()
	await tree.create_timer(0.02).timeout
	replies = drain(monitor)
	var failures := replies.filter(func(m): return m.address.ends_with("/ack") and m.args[1] == "failed")
	var statuses := replies.filter(func(m): return m.address.ends_with("/ack") and m.args[0] == "status")
	check.call(failures.size() == 1 and failures[0].args == ["play", "failed", 0, "replacement failed"] and statuses.size() == 1 and statuses[0].args == ["status", "received", 0, ""], "replacement failure survives status and cumulative old start")
	worker.snapshot.state = 2
	worker.snapshot.started_sequence = 2
	real.poll_status()
	worker.accept = false
	manager._dispatch_playback({"address": real.osc_base + "/play", "args": []})
	await tree.create_timer(0.02).timeout
	replies = drain(monitor)
	failures = replies.filter(func(m): return m.address.ends_with("/ack") and m.args[1] == "failed")
	check.call(not real.is_playing() and failures.size() == 1 and failures[0].args == ["play", "failed", 0, "invalid route"], "synchronous replacement refusal observes stop and native reason")
	manager.stop_networking()
	monitor.close()
	manager.free()
