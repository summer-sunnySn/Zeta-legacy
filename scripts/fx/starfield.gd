## Zeta Legacy — Procedural Starfield
## Scatters thousands of billboarded star quads on a large sphere using a single
## MultiMesh (one draw call). Follows the camera so the player never flies out
## of the stars. Cheap and reliable on the Compatibility/mobile renderer.
extends MultiMeshInstance3D

@export var star_count: int = 650
@export var shell_radius: float = 400.0
@export var min_size: float = 0.6
@export var max_size: float = 2.4

func _ready() -> void:
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE

	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.emission_enabled = true
	mat.emission_energy_multiplier = 1.5
	mat.disable_receive_shadows = true
	quad.surface_set_material(0, mat)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = quad
	mm.instance_count = star_count

	for i in star_count:
		var dir := Vector3(
			randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)
		).normalized()
		if dir == Vector3.ZERO:
			dir = Vector3.FORWARD
		var pos := dir * shell_radius * randf_range(0.7, 1.0)
		var s := randf_range(min_size, max_size)
		var xform := Transform3D(Basis().scaled(Vector3(s, s, s)), pos)
		mm.set_instance_transform(i, xform)
		# Slight colour variety: white / blue / faint amber stars.
		var tint := randf()
		var col := Color(0.85, 0.92, 1.0)
		if tint > 0.85:
			col = Color(1.0, 0.85, 0.6)
		elif tint > 0.6:
			col = Color(0.7, 0.8, 1.0)
		col.a = randf_range(0.5, 1.0)
		mm.set_instance_color(i, col)

	multimesh = mm

func _process(_delta: float) -> void:
	# Keep the starfield centred on the camera so stars feel infinitely distant.
	var cam := get_viewport().get_camera_3d()
	if cam:
		global_position = cam.global_position
