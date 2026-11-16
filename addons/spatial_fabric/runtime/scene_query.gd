@tool
class_name SpatialFabricSceneQuery
extends RefCounted
## Read-only schema-v1 discovery: validation and UTF-8 chunking only.

const QUERY := "/spatialfabric/scene/query"
const RESPONSE := "/spatialfabric/scene/response"
const MAX_CHUNK_BYTES := 900
const MAX_CHUNKS := 128

## Returns {} for anything invalid (the caller stays silent: no reflection amplification).
static func parse(args: Array) -> Dictionary:
	if args.size() != 2 and args.size() != 4:
		return {}
	if typeof(args[0]) != TYPE_STRING or typeof(args[1]) != TYPE_INT:
		return {}
	var request_id: String = args[0]
	var regex := RegEx.new()
	regex.compile("^[A-Za-z0-9_-]{1,64}$")
	if regex.search(request_id) == null:
		return {}
	var reply_port: int = args[1]
	var offset := 0
	var limit := 64
	if args.size() == 4:
		if typeof(args[2]) != TYPE_INT or typeof(args[3]) != TYPE_INT:
			return {}
		offset = args[2]
		limit = args[3]
	if reply_port < 1024 or reply_port > 65535 or offset < 0 or offset > 16384 or limit < 1 or limit > 64:
		return {}
	return {"id": request_id, "reply_port": reply_port, "offset": offset, "limit": limit}

static func is_loopback(ip: String) -> bool:
	return ip == "127.0.0.1" or ip == "::1" or ip == "::ffff:127.0.0.1"

## Splits JSON on character boundaries so every chunk is <=900 UTF-8 bytes.
static func chunk(json: String) -> Array:
	var chunks: Array = []
	var current := ""
	var bytes := 0
	for i in json.length():
		var ch := json[i]
		var size := ch.to_utf8_buffer().size()
		if bytes + size > MAX_CHUNK_BYTES:
			chunks.append(current)
			current = ""
			bytes = 0
		current += ch
		bytes += size
	if not current.is_empty() or chunks.is_empty():
		chunks.append(current)
	return chunks if chunks.size() <= MAX_CHUNKS else []

## Packets for one validated request, or [] when the page cannot be framed.
static func response_packets(request: Dictionary, page: Dictionary) -> Array:
	var chunks := chunk(JSON.stringify(page))
	if chunks.is_empty():
		return []
	var packets: Array = []
	for i in chunks.size():
		var packet := SpatialFabricOsc.encode(RESPONSE, [request.id, i, chunks.size(), chunks[i]])
		if packet.is_empty():
			return []
		packets.append(packet)
	return packets
