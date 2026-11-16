@tool
class_name SpatialFabricTransport
extends RefCounted
## Explicit exact-bind UDP receivers plus bounded nonblocking output.
## Nothing here runs until open() is called. Bind is transactional.

const MAX_PACKETS_PER_POLL := 128
const MAX_QUEUE := 512

var _inputs: Dictionary = {} # port -> PacketPeerUDP
var _sender := PacketPeerUDP.new()
var last_error := ""
var dropped_packets := 0
var dropped_invalid := 0

func is_open() -> bool:
	return not _inputs.is_empty()

func bound_ports() -> Array:
	var ports := _inputs.keys()
	ports.sort()
	return ports

## Binds every distinct port or none. Existing listeners are never rebound silently.
func open(ports: Array, address: String) -> Error:
	if is_open():
		last_error = "Already open; close explicitly before rebinding."
		return ERR_ALREADY_IN_USE
	var seen: Dictionary = {}
	for port in ports:
		seen[int(port)] = true
	var opened: Dictionary = {}
	for port in seen.keys():
		var peer := PacketPeerUDP.new()
		var result := peer.bind(port, address)
		if result != OK:
			for done in opened.values():
				done.close()
			last_error = "Could not exclusively bind %s:%d (%s)." % [address, port, error_string(result)]
			return result
		opened[port] = peer
	_inputs = opened
	last_error = ""
	return OK

func close() -> void:
	for peer in _inputs.values():
		peer.close()
	_inputs.clear()
	_sender.close()
	_sender = PacketPeerUDP.new()

## Returns [{port, ip, source_port, address, args}] decoded from at most MAX_PACKETS_PER_POLL packets.
func poll() -> Array:
	var out: Array = []
	var budget := MAX_PACKETS_PER_POLL
	for port in _inputs.keys():
		var peer: PacketPeerUDP = _inputs[port]
		while budget > 0 and peer.get_available_packet_count() > 0:
			budget -= 1
			var data := peer.get_packet()
			if peer.get_packet_error() != OK:
				dropped_invalid += 1
				continue
			var decoded := SpatialFabricOsc.decode(data)
			if not decoded.ok:
				dropped_invalid += 1
				continue
			for message in decoded.messages:
				if out.size() >= MAX_QUEUE:
					dropped_packets += 1
					continue
				out.append({"port": port, "ip": peer.get_packet_ip(), "source_port": peer.get_packet_port(), "address": message.address, "args": message.args})
	return out

## Nonblocking send; failure is reported, never retried or queued.
func send(address: String, port: int, packet: PackedByteArray) -> Error:
	if packet.is_empty() or port < 1 or port > 65535:
		return ERR_INVALID_PARAMETER
	var result := _sender.set_dest_address(address, port)
	if result != OK:
		last_error = "Bad destination %s:%d" % [address, port]
		return result
	result = _sender.put_packet(packet)
	if result != OK:
		last_error = "Send failed: " + error_string(result)
	return result
