@tool
class_name SpatialFabricOsc
extends RefCounted
## Strict bounded OSC 1.0 subset: int32 'i', float32 'f' (finite), string 's'.
## Malformed input is rejected atomically; bundles dispatch immediately (no scheduling).

const MAX_PACKET := 65507
const MAX_ARGUMENTS := 128
const MAX_MESSAGES := 128
const MAX_BUNDLE_DEPTH := 4
const MAX_STRING_BYTES := 4096

## Returns {"ok": bool, "messages": Array[{address, args}], "error": String}.
static func decode(data: PackedByteArray) -> Dictionary:
	var messages: Array = []
	var error := _decode_element(data, 0, data.size(), 0, messages)
	if error != "":
		return {"ok": false, "messages": [], "error": error}
	return {"ok": true, "messages": messages, "error": ""}

static func _read_string(data: PackedByteArray, pos: int, end: int) -> Dictionary:
	var stop := pos
	while stop < end and data[stop] != 0:
		stop += 1
	if stop >= end or stop - pos > MAX_STRING_BYTES:
		return {"error": "unterminated or oversized string"}
	var padded := pos + ((stop - pos) / 4 + 1) * 4
	if padded > end:
		return {"error": "string padding truncated"}
	for i in range(stop, padded):
		if data[i] != 0:
			return {"error": "nonzero string padding"}
	var raw := data.slice(pos, stop)
	var text := raw.get_string_from_utf8()
	if text.to_utf8_buffer() != raw:
		return {"error": "invalid UTF-8"}
	return {"value": text, "next": padded}

static func _decode_element(data: PackedByteArray, pos: int, end: int, depth: int, out: Array) -> String:
	if end - pos < 4 or end > MAX_PACKET:
		return "packet too short or too large"
	if data[pos] == 0x23: # '#bundle'
		if depth >= MAX_BUNDLE_DEPTH:
			return "bundle nesting too deep"
		var head := _read_string(data, pos, end)
		if head.has("error") or head.value != "#bundle" or end - head.next < 8:
			return "malformed bundle header"
		var cursor: int = head.next + 8 # timetag ignored: immediate dispatch
		while cursor < end:
			if end - cursor < 4:
				return "truncated bundle element size"
			var size := _be32(data, cursor)
			cursor += 4
			if size < 4 or size % 4 != 0 or cursor + size > end:
				return "invalid bundle element length"
			var failure := _decode_element(data, cursor, cursor + size, depth + 1, out)
			if failure != "":
				return failure
			cursor += size
		return ""
	if data[pos] != 0x2F:
		return "address must begin with /"
	var address := _read_string(data, pos, end)
	if address.has("error"):
		return "address: " + address.error
	var cursor: int = address.next
	var tags := _read_string(data, cursor, end) if cursor < end else {"value": ",", "next": cursor}
	if tags.has("error"):
		return "typetag: " + tags.error
	var tag_text: String = tags.value
	if tag_text.is_empty() or tag_text[0] != ",":
		return "missing typetag comma"
	if tag_text.length() - 1 > MAX_ARGUMENTS:
		return "too many arguments"
	cursor = tags.next
	var args: Array = []
	for i in range(1, tag_text.length()):
		match tag_text[i]:
			"i":
				if cursor + 4 > end:
					return "truncated int32"
				args.append(_be32(data, cursor))
				cursor += 4
			"f":
				if cursor + 4 > end:
					return "truncated float32"
				var value := _bef(data, cursor)
				if is_nan(value) or is_inf(value):
					return "non-finite float"
				args.append(value)
				cursor += 4
			"s":
				var item := _read_string(data, cursor, end)
				if item.has("error"):
					return "string argument: " + item.error
				args.append(item.value)
				cursor = item.next
			_:
				return "unsupported typetag " + tag_text[i]
	if cursor != end:
		return "trailing bytes"
	if out.size() >= MAX_MESSAGES:
		return "too many messages"
	out.append({"address": address.value, "args": args})
	return ""

static func _be32(data: PackedByteArray, pos: int) -> int:
	var v := (data[pos] << 24) | (data[pos + 1] << 16) | (data[pos + 2] << 8) | data[pos + 3]
	return v - 0x100000000 if v >= 0x80000000 else v

static func _bef(data: PackedByteArray, pos: int) -> float:
	var swapped := PackedByteArray([data[pos + 3], data[pos + 2], data[pos + 1], data[pos]])
	return swapped.decode_float(0)

## Encode one message. Returns empty array on any invalid input (never partial output).
static func encode(address: String, args: Array = []) -> PackedByteArray:
	if address.is_empty() or address[0] != "/" or args.size() > MAX_ARGUMENTS or address.to_utf8_buffer().has(0):
		return PackedByteArray()
	var tags := ","
	var body := PackedByteArray()
	for arg in args:
		match typeof(arg):
			TYPE_INT:
				if arg < -2147483648 or arg > 2147483647:
					return PackedByteArray()
				tags += "i"
				body.append_array(_put_be32(arg))
			TYPE_FLOAT:
				if is_nan(arg) or is_inf(arg) or absf(arg) > 3.4028234e38:
					return PackedByteArray()
				tags += "f"
				var le := PackedByteArray()
				le.resize(4)
				le.encode_float(0, arg)
				le.reverse()
				body.append_array(le)
			TYPE_STRING:
				var utf8 := String(arg).to_utf8_buffer()
				if utf8.has(0) or utf8.size() > MAX_STRING_BYTES:
					return PackedByteArray()
				tags += "s"
				body.append_array(_pad(utf8))
			_:
				return PackedByteArray()
	var packet := _pad(address.to_utf8_buffer())
	packet.append_array(_pad(tags.to_utf8_buffer()))
	packet.append_array(body)
	return packet if packet.size() <= MAX_PACKET else PackedByteArray()

static func _put_be32(value: int) -> PackedByteArray:
	var u := value & 0xFFFFFFFF
	return PackedByteArray([(u >> 24) & 255, (u >> 16) & 255, (u >> 8) & 255, u & 255])

static func _pad(raw: PackedByteArray) -> PackedByteArray:
	var out := raw.duplicate()
	out.append(0)
	while out.size() % 4 != 0:
		out.append(0)
	return out
