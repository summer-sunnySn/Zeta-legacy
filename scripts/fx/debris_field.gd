## Zeta Legacy — Parallax Asteroid Field
## Real 3D rocks (a noise-displaced, faceted mesh — not billboards) scattered
## through and around the arena. These are the reference points that make flying
## FEEL fast; near rocks whip past while distant stars barely move. One MultiMesh
## = one draw call. Purely visual (no collision).
extends MultiMeshInstance3D

@export var count: int = 120
@export var inner_radius: float = 34.0     ## keep the immediate play space clear
@export var outer_radius: float = 195.0
@export var min_size: float = 0.5
@export var max_size: float = 3.6

func _ready() -> void:
	var rock := _make_rock_mesh()

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.40, 0.37, 0.40)
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.vertex_color_use_as_albedo = true
	rock.surface_set_material(0, mat)

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = rock
	mm.instance_count = count

	var r_in3 := pow(inner_radius, 3.0)
	var r_out3 := pow(outer_radius, 3.0)
	for i in count:
		var dir := Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)).normalized()
		if dir == Vector3.ZERO:
			dir = Vector3.FORWARD
		# Cube-root radius → uniform density through the whole shell (no clustering).
		var dist: float = pow(r_in3 + (r_out3 - r_in3) * randf(), 1.0 / 3.0)
		# Bias toward small rocks; only occasional larger ones, spread out.
		var size: float = lerpf(min_size, max_size, randf() * randf())
		var pos := dir * dist

		var b := Basis.from_euler(Vector3(randf() * TAU, randf() * TAU, randf() * TAU))
		b = b.scaled(Vector3(
			size * randf_range(0.7, 1.3),
			size * randf_range(0.6, 1.1),
			size * randf_range(0.7, 1.3)))
		mm.set_instance_transform(i, Transform3D(b, pos))

		var shade := randf_range(0.65, 1.15)
		mm.set_instance_color(i, Color(0.42 * shade, 0.38 * shade, 0.40 * shade))

	multimesh = mm

## Build a faceted asteroid: a sphere displaced by 3D noise, de-indexed so
## generate_normals() gives flat per-face shading (the rocky low-poly look).
func _make_rock_mesh() -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 12
	sphere.rings = 8
	var arrays: Array = sphere.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.55

	# Displace each vertex along its outward normal.
	for i in verts.size():
		var v := verts[i]
		var n := v.normalized()
		var d := noise.get_noise_3dv(v * 2.0)        # -1..1
		var d2 := noise.get_noise_3dv(v * 5.0) * 0.4
		verts[i] = v + n * (d * 0.4 + d2)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for idx in indices:
		st.add_vertex(verts[idx])                    # de-indexed → faceted
	st.generate_normals()
	return st.commit()
