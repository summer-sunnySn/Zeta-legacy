## Zeta Legacy — Lunar Rocks Scatter & Particles
## Places rock and boulder fields using MultiMeshInstance3D with LOD and distance culling.
## Provides cheap GPUParticles3D footprint/dust emitters for moving player and crash sites.
## Zero per-frame allocations during gameplay.
class_name LunarScatter
extends Node3D

@export var terrain: LunarTerrain = null
@export var scatter_radius: float = 600.0
@export var boulder_count: int = 150
@export var rock_count: int = 400
@export var pebble_count: int = 800

var _boulders_mm: MultiMeshInstance3D = null
var _rocks_mm: MultiMeshInstance3D = null
var _pebbles_mm: MultiMeshInstance3D = null

func _ready() -> void:
	if terrain == null:
		terrain = get_parent().get_node_or_null("Terrain") as LunarTerrain
	_setup_rock_tiers()

func _setup_rock_tiers() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 2026

	# 1. Large Boulders
	_boulders_mm = _create_tier("Boulders", boulder_count, 2.5, 6.0, Color(0.28, 0.28, 0.30), rng)
	add_child(_boulders_mm)

	# 2. Medium Rocks
	_rocks_mm = _create_tier("MediumRocks", rock_count, 0.8, 2.2, Color(0.33, 0.33, 0.35), rng)
	add_child(_rocks_mm)

	# 3. Small Pebble Field
	_pebbles_mm = _create_tier("Pebbles", pebble_count, 0.25, 0.7, Color(0.38, 0.38, 0.40), rng)
	add_child(_pebbles_mm)

func _create_tier(tier_name: String, count: int, min_scale: float, max_scale: float, tint: Color, rng: RandomNumberGenerator) -> MultiMeshInstance3D:
	var mmi := MultiMeshInstance3D.new()
	mmi.name = tier_name

	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _build_faceted_rock_mesh(tint)
	mm.instance_count = count

	mmi.multimesh = mm
	# Mobile distance culling
	mmi.visibility_range_end = 450.0 if count > 500 else 750.0
	mmi.visibility_range_end_margin = 50.0
	mmi.visibility_range_fade_mode = GeometryInstance3D.VISIBILITY_RANGE_FADE_SELF

	for i in count:
		# Scatter in polar coordinates with inner exclusion zone (keep immediate crash site clear)
		var angle := rng.randf() * TAU
		var dist := sqrt(rng.randf_range(16.0 * 16.0, scatter_radius * scatter_radius))
		var wx := cos(angle) * dist
		var wz := sin(angle) * dist
		var wy := 0.0
		if terrain:
			wy = terrain.get_height(wx, wz)

		var s := rng.randf_range(min_scale, max_scale)
		var scale_vec := Vector3(
			s * rng.randf_range(0.8, 1.3),
			s * rng.randf_range(0.6, 1.1),
			s * rng.randf_range(0.8, 1.3)
		)

		var rot := Basis.from_euler(Vector3(
			rng.randf_range(-0.3, 0.3),
			rng.randf() * TAU,
			rng.randf_range(-0.3, 0.3)
		))

		var xform := Transform3D(rot.scaled(scale_vec), Vector3(wx, wy - s * 0.15, wz))
		mm.set_instance_transform(i, xform)

		# Vary color slightly for natural mineral appearance
		var shade := rng.randf_range(0.85, 1.15)
		mm.set_instance_color(i, Color(tint.r * shade, tint.g * shade, tint.b * shade, 1.0))

	return mmi

## Procedural faceted rock mesh (low poly, mobile-friendly, no texture fetch overhead)
func _build_faceted_rock_mesh(tint: Color) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 0.5
	sphere.height = 1.0
	sphere.radial_segments = 5
	sphere.rings = 3

	var arrays: Array = sphere.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]

	# Jitter vertices to create natural sharp boulder facets
	var rng := RandomNumberGenerator.new()
	rng.seed = 99
	for i in verts.size():
		var v := verts[i]
		var jitter := Vector3(rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12), rng.randf_range(-0.12, 0.12))
		verts[i] = v + jitter

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for idx in indices:
		st.add_vertex(verts[idx])
	st.generate_normals()

	var mesh: ArrayMesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.95
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_SCHLICK_GGX
	mesh.surface_set_material(0, mat)
	return mesh

## Helper to create cheap GPUParticles3D for footstep regolith puffs
static func create_footstep_particles() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 16
	p.lifetime = 1.2
	p.explosiveness = 0.8
	p.randomness = 0.5
	p.emitting = false

	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	ppm.emission_sphere_radius = 0.2
	ppm.direction = Vector3(0.0, 1.0, 0.0)
	ppm.spread = 45.0
	ppm.initial_velocity_min = 0.8
	ppm.initial_velocity_max = 2.2
	ppm.gravity = Vector3(0.0, -1.62, 0.0) # Lunar gravity
	ppm.scale_min = 0.4
	ppm.scale_max = 1.1
	ppm.color = Color(0.65, 0.65, 0.68, 0.25)
	p.process_material = ppm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.2, 0.2)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.65, 0.65, 0.68, 0.3)
	quad.material = mat
	p.draw_pass_1 = quad

	return p

## Helper to create cheap smoke/dust column for crashed ships
static func create_crash_smoke() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	p.amount = 24
	p.lifetime = 3.5
	p.explosiveness = 0.05
	p.randomness = 0.4
	p.visibility_aabb = AABB(Vector3(-10, 0, -10), Vector3(20, 30, 20))

	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	ppm.emission_box_extents = Vector3(1.0, 0.2, 1.0)
	ppm.direction = Vector3(0.1, 1.0, 0.0)
	ppm.spread = 20.0
	ppm.initial_velocity_min = 1.2
	ppm.initial_velocity_max = 3.0
	ppm.gravity = Vector3(0.0, 0.2, 0.0) # Slow drift in vacuum / micro draft
	ppm.scale_min = 0.8
	ppm.scale_max = 3.0
	ppm.color = Color(0.25, 0.25, 0.28, 0.35)
	p.process_material = ppm

	var quad := QuadMesh.new()
	quad.size = Vector2(0.8, 0.8)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(0.3, 0.3, 0.32, 0.35)
	quad.material = mat
	p.draw_pass_1 = quad

	return p
