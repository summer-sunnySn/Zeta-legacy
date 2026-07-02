## Zeta Legacy — Moon Terrain Procedural Scatter (FLAT ground)
## Scatters rocks, crater rims and regolith dust across a flat lunar plain (y=0),
## keeping the centre landing zone clear. If the player drops real models into
## models/moon/ (rock.glb / crater.glb) those are used instead of the procedural
## placeholders — see models/moon/README.txt. Runs once, then frees itself.
extends Node

## Folder to look for swap-in crater.glb / rock.glb (Moon by default; set to
## res://models/mars/ for the Mars mission).
@export var model_dir: String = "res://models/moon/"

@export var scatter_radius: float = 240.0
@export var inner_clear_radius: float = 14.0

@export_group("Counts")
@export var large_rocks: int  = 40
@export var medium_rocks: int = 70
@export var small_debris: int = 110
@export var craters: int      = 14

const ROCK_TIER := {
	"large"  : {"embed": 1.4, "colour": Color(0.30, 0.28, 0.29)},
	"medium" : {"embed": 0.6, "colour": Color(0.32, 0.30, 0.31)},
	"small"  : {"embed": 0.3, "colour": Color(0.34, 0.32, 0.33)},
}
const RNG_SEED := 42

func _ready() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = RNG_SEED

	var container := Node3D.new()
	container.name = "LunarScenery"

	# ── Rocks: real model if supplied, else procedural multimesh tiers ──
	if FileAccess.file_exists(model_dir + "rock.glb"):
		_scatter_model(container, model_dir + "rock.glb", 28, rng, 1.5, 4.5, 0.4)
	else:
		_place_tier(container, large_rocks,  rng, "large")
		_place_tier(container, medium_rocks, rng, "medium")
		_place_tier(container, small_debris, rng, "small")

	# ── Craters: real model if supplied, else flat procedural discs ──
	if FileAccess.file_exists(model_dir + "crater.glb"):
		_scatter_model(container, model_dir + "crater.glb", craters, rng, 8.0, 22.0, 0.1)
	else:
		_scatter_craters(container, rng)

	_create_dust_field(container, rng)

	get_parent().add_child.call_deferred(container)
	queue_free()

# ─── Real-model scatter (swap-in) ────────────────────────────────────────────
## Drop `count` instances of a runtime-loaded .glb across the plain.
func _scatter_model(container: Node, path: String, count: int,
		rng: RandomNumberGenerator, min_len: float, max_len: float, sink: float) -> void:
	for i in count:
		var m: Node3D = ModelLib.instance_model(path)
		if m == null:
			return
		container.add_child(m)
		ModelLib.fit(m, rng.randf_range(min_len, max_len))   # centres at local origin
		var p := _random_polar(rng)
		m.position += Vector3(p.x, -sink, p.y)               # drop onto the ground
		m.rotate_y(rng.randf() * TAU)

# ─── Procedural rocks (MultiMesh, one draw call per tier) ────────────────────
func _place_tier(container: Node, count: int, rng: RandomNumberGenerator, tier: String) -> void:
	if count <= 0:
		return
	var tier_data: Dictionary = ROCK_TIER[tier]
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = _make_rock_mesh(tier_data["colour"])
	mm.instance_count = count

	var mi := MultiMeshInstance3D.new()
	mi.multimesh = mm
	mi.name = "RockTier_" + tier
	container.add_child(mi)

	for i in count:
		var p := _random_polar(rng)
		var pos := Vector3(p.x, -rng.randf_range(0.1, tier_data["embed"]), p.y)
		var rot := Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
		var sx := 1.0 + rng.randf_range(-0.3, 0.5)
		var sy := 0.6 + rng.randf_range(0.3, 1.2)
		var sz := 1.0 + rng.randf_range(-0.3, 0.5)
		var b := Basis.from_euler(rot).scaled(Vector3(sx, sy, sz))
		mm.set_instance_transform(i, Transform3D(b, pos))
		var shade := rng.randf_range(0.85, 1.1)
		mm.set_instance_color(i, Color(shade, shade * 0.97, shade * 0.95))

func _make_rock_mesh(tint: Color) -> ArrayMesh:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	sphere.radial_segments = 6
	sphere.rings = 4
	var arrays: Array = sphere.surface_get_arrays(0)
	var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	noise.frequency = 0.7
	for i in verts.size():
		var v := verts[i]
		verts[i] = v + v.normalized() * (noise.get_noise_3dv(v * 3.0) * 0.35)
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for idx in indices:
		st.add_vertex(verts[idx])
	st.generate_normals()
	var msh: ArrayMesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint
	mat.roughness = 0.95
	mat.metallic = 0.0
	msh.surface_set_material(0, mat)
	return msh

# ─── Procedural craters (flat discs lying on the ground) ─────────────────────
func _scatter_craters(container: Node, rng: RandomNumberGenerator) -> void:
	var parent := Node3D.new()
	parent.name = "Craters"
	container.add_child(parent)
	for i in craters:
		var ring := _make_crater_disc(rng.randf_range(6.0, 22.0))
		var p := _random_polar(rng)
		ring.position = Vector3(p.x, 0.02, p.y)
		parent.add_child(ring)

func _make_crater_disc(radius: float) -> MeshInstance3D:
	var disc := CylinderMesh.new()
	disc.top_radius = radius
	disc.bottom_radius = radius
	disc.height = 0.25
	disc.radial_segments = 24
	var mi := MeshInstance3D.new()
	mi.mesh = disc                       # cylinder axis is already +Y → lies flat
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.23, 0.24)
	mat.roughness = 1.0
	mi.material_override = mat
	return mi

# ─── Dust field ──────────────────────────────────────────────────────────────
func _create_dust_field(container: Node, _rng: RandomNumberGenerator) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "RegolithDust"
	particles.amount = 1200
	particles.lifetime = 12.0
	particles.visibility_aabb = AABB(Vector3(-200, 0, -200), Vector3(400, 6, 400))
	particles.process_material = _build_dust_ppm()
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE * 0.12
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.albedo_color = Color(0.55, 0.52, 0.50, 0.16)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	quad.surface_set_material(0, mat)
	particles.draw_pass_1 = quad
	container.add_child(particles)

func _build_dust_ppm() -> ParticleProcessMaterial:
	var ppm := ParticleProcessMaterial.new()
	ppm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	ppm.emission_box_extents = Vector3(200, 2.0, 200)
	ppm.gravity = Vector3.ZERO
	ppm.direction = Vector3.UP
	ppm.spread = 180.0
	ppm.initial_velocity_min = 0.0
	ppm.initial_velocity_max = 0.04
	ppm.scale_min = 0.5
	ppm.scale_max = 1.5
	ppm.color = Color(1.0, 1.0, 1.0, 0.22)
	return ppm

# ─── Helpers ─────────────────────────────────────────────────────────────────
## Uniform random point in the scatter annulus on the XZ plane.
func _random_polar(rng: RandomNumberGenerator) -> Vector2:
	var r := sqrt(rng.randf_range(
		inner_clear_radius * inner_clear_radius,
		scatter_radius * scatter_radius))
	var theta := rng.randf() * TAU
	return Vector2(r * cos(theta), r * sin(theta))
