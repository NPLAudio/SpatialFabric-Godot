@tool
class_name SpatialFabricObject
extends Node3D

@export var persistent_key: String = ""
@export_range(1, 2147483647) var object_id: int = 1
@export var display_label: String = ""
@export var bound_transform: NodePath

func pose() -> Node3D:
	if bound_transform.is_empty():
		return self
	return get_node_or_null(bound_transform) as Node3D
