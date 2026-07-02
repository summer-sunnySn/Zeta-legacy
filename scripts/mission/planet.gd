## Zeta Legacy — Anime-style Procedural Planet (backdrop for Mission Mode)
## Builds a big, glowing, rim-lit planet from a config dict (no photoreal
## textures): a saturated emissive core, a soft additive atmosphere halo, and —
## for Saturn — a procedural ring band. Mobile-safe (StandardMaterial3D only,
## no compute effects). Slowly self-rotates for life.
extends Node3D

var _spin: float = 0.04

# Cache of meshes loaded from real .glb files (keyed by res:// path) so that
# switching planets in the select screen doesn't re-parse the multi-MB file.
static var _model_cache: Dictionary = {}

## Build the planet. `cfg` is an entry from MissionData.PLANETS.
func configure(cfg: Dictionary, radius: float = 60.0) -> void:
	var col: Color = cfg.get("color", Color(0.4, 0.6, 1.0))
	var atmo: Color = cfg.get("atmo", Color(0.5, 0.8, 1.0))

	# ── Core ──────────────────────────────────────────────────────────────
	# A real downloaded 3D model (e.g. textured Earth) if one is supplied,
	# otherwise the bright anime-style procedural sphere.
	var model_path: String = cfg.get("model", "")
	if model_path != "" and _build_real_core(model_path, radius):
		pass
	else:
		_build_procedural_core(col, radius)

	# ── Atmosphere halo (slightly larger additive shell) ──────────────────
	var halo := MeshInstance3D.new()
	var hm := SphereMesh.new()
	hm.radius = radius * 1.06
	hm.height = radius * 2.12
	hm.radial_segments = 48
	hm.rings = 24
	halo.mesh = hm
	var hmat := StandardMaterial3D.new()
	hmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hmat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	hmat.cull_mode = BaseMaterial3D.CULL_FRONT      # render back faces → edge glow
	hmat.albedo_color = Color(atmo.r, atmo.g, atmo.b, 0.25)
	hmat.emission_enabled = true
	hmat.emission = atmo
	hmat.emission_energy_multiplier = 1.2
	halo.material_override = hmat
	add_child(halo)

	# ── Rings (Saturn) ────────────────────────────────────────────────────
	if cfg.get("rings", false):
		var ring := MeshInstance3D.new()
		ring.mesh = _make_ring(radius * 1.35, radius * 2.3, 96, atmo)
		var rmat := StandardMaterial3D.new()
		rmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		rmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		rmat.cull_mode = BaseMaterial3D.CULL_DISABLED
		rmat.vertex_color_use_as_albedo = true
		rmat.emission_enabled = true
		rmat.emission = atmo
		rmat.emission_energy_multiplier = 0.6
		ring.material_override = rmat
		ring.rotation = Vector3(0.42, 0.0, 0.18)     # iconic tilt
		add_child(ring)

## Bright anime-style procedural core (glowing, rim-lit sphere).
func _build_procedural_core(col: Color, radius: float) -> void:
	var core := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = radius
	sm.height = radius * 2.0
	sm.radial_segments = 64
	sm.rings = 32
	core.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.roughness = 0.85
	mat.metallic = 0.0
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.45     # glows even on the dark side
	mat.rim_enabled = true
	mat.rim = 1.0
	mat.rim_tint = 0.4
	core.material_override = mat
	add_child(core)

## Real textured model core, loaded at RUNTIME via GLTFDocument (the editor
## import pipeline is unusable on this device — its help-cache regen segfaults).
## The source model is a unit sphere (radius 1), so we scale it to `radius`.
## Returns false on failure so configure() can fall back to procedural.
func _build_real_core(path: String, radius: float) -> bool:
	var mesh: Mesh = _load_model_mesh(path)
	if mesh == null:
		push_warning("Planet: could not load model '%s' — using procedural." % path)
		return false
	var core := MeshInstance3D.new()
	core.mesh = mesh
	core.scale = Vector3.ONE * radius        # unit sphere → target radius
	# Lift the night side out of pure black so it still reads against space,
	# while keeping the realistic daytime texture intact.
	var surf := mesh.surface_get_material(0)
	if surf is StandardMaterial3D and not (surf as StandardMaterial3D).emission_enabled:
		var m: StandardMaterial3D = (surf as StandardMaterial3D).duplicate()
		m.emission_enabled = true
		if m.albedo_texture != null:
			m.emission_texture = m.albedo_texture
		m.emission = Color(0.6, 0.7, 0.9)
		m.emission_energy_multiplier = 0.12
		core.set_surface_override_material(0, m)
	add_child(core)
	return true

## Load (and cache) the first mesh out of a .glb at runtime. Returns null on
## any failure.
func _load_model_mesh(path: String) -> Mesh:
	if _model_cache.has(path):
		return _model_cache[path]
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_file(path, state) != OK:
		return null
	var scn: Node = doc.generate_scene(state)
	if scn == null:
		return null
	var found: Mesh = null
	var stack: Array = [scn]
	while stack.size() > 0:
		var n: Node = stack.pop_back()
		if n is MeshInstance3D and (n as MeshInstance3D).mesh != null:
			found = (n as MeshInstance3D).mesh
			break
		for c in n.get_children():
			stack.append(c)
	scn.queue_free()
	if found != null:
		_model_cache[path] = found
	return found

func _process(delta: float) -> void:
	rotate_y(delta * _spin)

## Flat annulus (ring) in the XZ plane, with a soft brightness gradient baked
## into vertex colours (brighter in the middle of the band).
func _make_ring(inner: float, outer: float, segs: int, tint: Color) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var mid := Color(tint.r, tint.g, tint.b, 0.85)
	var edge := Color(tint.r, tint.g, tint.b, 0.15)
	for i in segs:
		var a0 := TAU * float(i) / float(segs)
		var a1 := TAU * float(i + 1) / float(segs)
		var in_a := Vector3(cos(a0) * inner, 0, sin(a0) * inner)
		var in_b := Vector3(cos(a1) * inner, 0, sin(a1) * inner)
		var out_a := Vector3(cos(a0) * outer, 0, sin(a0) * outer)
		var out_b := Vector3(cos(a1) * outer, 0, sin(a1) * outer)
		# Inner edge faint, mid bright — approximate by colouring inner verts
		# edge and outer verts mid (a simple two-tone band).
		for entry in [[in_a, edge], [out_a, mid], [out_b, mid],
					  [in_a, edge], [out_b, mid], [in_b, edge]]:
			st.set_color(entry[1])
			st.set_normal(Vector3.UP)
			st.add_vertex(entry[0])
	return st.commit()
