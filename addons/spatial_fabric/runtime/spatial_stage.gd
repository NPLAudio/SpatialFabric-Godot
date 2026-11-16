@tool
class_name SpatialFabricStage
extends Node3D
## Canonical dimensions: front/right/up METERS, not Godot XYZ.

@export var persistent_key: String = ""
@export var dimensions_meters := Vector3(18, 18, 6)

func is_valid_stage() -> bool:
	return (
		dimensions_meters.is_finite()
		and dimensions_meters.x > 0.0
		and dimensions_meters.y > 0.0
		and dimensions_meters.z > 0.0
		and global_transform.is_finite()
		and global_basis.determinant() > 0.0
		and global_basis.is_conformal()
		and global_basis.get_scale().is_equal_approx(Vector3.ONE)
	)

static func canonical_world_meters(point: Vector3) -> Vector3:
	return Vector3(-point.z, point.x, point.y)

func normalize_world(point: Vector3) -> Variant:
	if not is_valid_stage() or not point.is_finite():
		return null
	var local := global_basis.inverse() * (point - global_position)
	var normalized := canonical_world_meters(local) / (dimensions_meters * 0.5)
	return normalized if normalized.is_finite() else null

static func adm_xyz(canonical: Vector3) -> Vector3:
	var limited := canonical.limit_length(1.0)
	return Vector3(limited.y, limited.x, limited.z)

static func adm_aed(canonical: Vector3) -> Vector3:
	var limited := canonical.limit_length(1.0)
	var radius := limited.length()
	if radius <= 0.000001:
		return Vector3.ZERO
	return Vector3(rad_to_deg(atan2(-limited.y, limited.x)), rad_to_deg(asin(clampf(limited.z / radius, -1.0, 1.0))), radius)
