@tool
class_name SpatialFabricPlaybackCue
extends Node3D
## Configuration wireframe only. No AudioStreamPlayer/mixer fallback, file loads or devices.

@export var persistent_key: String = ""
@export var osc_base: String = "/godot/playback/cue"
@export var source_path: String = ""
@export_range(0, 256) var output_channel: int = 0
var last_error: String = "Direct-device backend is not implemented."

func is_playing() -> bool:
	return false

func prepare_source() -> Error:
	last_error = "Direct-device backend is not implemented; no source was loaded."
	return ERR_UNAVAILABLE

func try_play() -> bool:
	last_error = "Direct-device backend is not implemented; playback refused."
	return false

func stop() -> void:
	# Idempotent no-op: there is no native worker or Godot mixer fallback.
	pass

func refresh_devices() -> Error:
	last_error = "Direct-device device inventory is not implemented."
	return ERR_UNAVAILABLE
