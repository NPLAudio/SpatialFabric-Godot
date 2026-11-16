@tool
class_name SpatialFabricWav
extends RefCounted
## Bounded RIFF/WAVE decoder: PCM8/16/24/32, float32/64 and WAVE_FORMAT_EXTENSIBLE.
## Returns {ok, error, channels, rate, samples(PackedFloat32Array interleaved)}.

const MAX_BYTES := 256 * 1024 * 1024
const MAX_SAMPLES := 64 * 1024 * 1024

static func _fail(message: String) -> Dictionary:
	return {"ok": false, "error": message, "channels": 0, "rate": 0, "samples": PackedFloat32Array()}

static func load_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return _fail("Source file not found: " + path)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null or file.get_length() > MAX_BYTES:
		return _fail("Source unreadable or larger than the 256 MiB bound.")
	return decode(file.get_buffer(file.get_length()))

static func decode(data: PackedByteArray) -> Dictionary:
	if data.size() < 44 or data.size() > MAX_BYTES or data.slice(0, 4).get_string_from_ascii() != "RIFF" or data.slice(8, 12).get_string_from_ascii() != "WAVE":
		return _fail("Not a RIFF/WAVE file.")
	var pos := 12
	var tag := 0
	var channels := 0
	var rate := 0
	var align := 0
	var bits := 0
	var valid_bits := 0
	var data_start := -1
	var data_size := 0
	while pos + 8 <= data.size():
		var id := data.slice(pos, pos + 4).get_string_from_ascii()
		var size := data.decode_u32(pos + 4)
		var body := pos + 8
		if body + size > data.size():
			if id == "data":
				size = data.size() - body # tolerate a truncated final data chunk
			else:
				return _fail("Truncated " + id + " chunk.")
		if id == "fmt " and size >= 16:
			tag = data.decode_u16(body)
			channels = data.decode_u16(body + 2)
			rate = data.decode_u32(body + 4)
			align = data.decode_u16(body + 12)
			bits = data.decode_u16(body + 14)
			valid_bits = bits
			if tag == 0xFFFE:
				if size < 40:
					return _fail("Invalid WAVE_FORMAT_EXTENSIBLE chunk.")
				valid_bits = data.decode_u16(body + 18)
				tag = data.decode_u16(body + 24) # first two GUID bytes carry PCM(1)/float(3)
		elif id == "data" and data_start < 0:
			data_start = body
			data_size = size
		pos = body + size + (size & 1)
	if data_start < 0 or channels < 1 or channels > 32 or rate < 8000 or rate > 384000:
		return _fail("Missing data or unsupported channel count/sample rate.")
	if tag != 1 and tag != 3:
		return _fail("Unsupported WAVE format tag %d." % tag)
	var bytes_per := bits / 8
	var supported := (tag == 1 and (bits == 8 or bits == 16 or bits == 24 or bits == 32)) or (tag == 3 and (bits == 32 or bits == 64))
	if not supported or bits % 8 != 0 or align != bytes_per * channels or valid_bits < 1 or valid_bits > bits:
		return _fail("Unsupported or inconsistent sample layout.")
	var total := data_size / bytes_per
	total -= total % channels
	if total < channels or total > MAX_SAMPLES:
		return _fail("No audio frames or more than 64M samples.")
	var out := PackedFloat32Array()
	out.resize(total)
	var cursor := data_start
	for i in total:
		var v := 0.0
		if tag == 3:
			v = data.decode_float(cursor) if bits == 32 else data.decode_double(cursor)
		elif bits == 8:
			v = (float(data[cursor]) - 128.0) / 128.0
		elif bits == 16:
			v = data.decode_s16(cursor) / 32768.0
		elif bits == 24:
			var raw := data[cursor] | (data[cursor + 1] << 8) | (data[cursor + 2] << 16)
			if raw >= 0x800000:
				raw -= 0x1000000
			v = raw / 8388608.0
		else:
			v = data.decode_s32(cursor) / 2147483648.0
		if is_nan(v) or is_inf(v):
			return _fail("Non-finite sample.")
		out[i] = clampf(v, -1.0, 1.0)
		cursor += bytes_per
	return {"ok": true, "error": "", "channels": channels, "rate": rate, "samples": out}
