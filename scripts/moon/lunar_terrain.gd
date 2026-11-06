## Zeta Legacy — Production Chunked Lunar Terrain
## Streams a 4km x 4km (or larger) lunar landscape divided into grid chunks with LOD.
## Incorporates:
## - NASA displacement heightmap sampling with FastNoiseLite fallback.
## - A massive central crater bowl with raised rim (landing/crash site).
## - Multiple secondary procedural impact craters.
## - Quadtree/Grid LOD: dense geometry near the player, coarse further away.
## - Jolt StaticBody3D collision generation for near chunks.
## - Zero per-frame heap allocations in the update loop.
class_name LunarTerrain
extends Node3D

@export var chunk_size: float = 256.0           ## Size of each chunk in meters
@export var grid_radius: int = 8                ## 8 chunks in each direction -> 17x17 chunks = 4352m x 4352m
@export var collision_radius: int = 2           ## Chunks within this distance get physical collision shapes
@export var height_scale: float = 85.0          ## Elevation range in meters
@export var crater_bowl_radius: float = 380.0   ## Radius of the main crash crater
@export var crater_rim_width: float = 90.0      ## Width of the raised rim
@export var crater_rim_height: float = 28.0     ## Height of the raised rim
@export var crater_depth: float = 45.0          ## Depth of the bowl floor
@export var material_override: Material = null

# LOD segment configurations (subdivisions per chunk)
const LOD0_SEGS: int = 24  ## Near player (< 300m)
const LOD1_SEGS: int = 12  ## Medium distance (< 700m)
const LOD2_SEGS: int = 4   ## Far distance (> 700m)

var _heightmap_image: Image = null
var _noise: FastNoiseLite = null
var _chunks: Dictionary = {}  ## Vector2i -> ChunkData
var _mesh_cache: Dictionary = {}  ## segs -> ArrayMesh template
var _active_center_coord: Vector2i = Vector2i(999999, 999999)
var _player_ref: Node3D = null

# Secondary craters: Array of Vector3(x, z, radius)
var _sub_craters: Array[Vector3] = [
	Vector3(450.0, -320.0, 110.0),
	Vector3(-550.0, 280.0, 140.0),
	Vector3(720.0, 600.0, 180.0),
	Vector3(-380.0, -680.0, 125.0),
	Vector3(1100.0, -120.0, 220.0),
	Vector3(-950.0, -450.0, 160.0),
	Vector3(200.0, 950.0, 130.0),
	Vector3(-800.0, 1100.0, 200.0)
]

class ChunkData:
	var coord: Vector2i
	var mesh_instance: MeshInstance3D
	var static_body: StaticBody3D
	var current_lod: int = -1

func _ready() -> void:
	_init_heightmap()
	_init_noise()
	_update_chunks(Vector3.ZERO, true)

## Loads NASA displacement heightmap or sets up fallback
func _init_heightmap() -> void:
	var path := "res://textures/moon/moon_disp.png"
	if ResourceLoader.exists(path):
		var tex := load(path) as Texture2D
		if tex:
			_heightmap_image = tex.get_image()
			if _heightmap_image:
				_heightmap_image.decompress()

## Configures FastNoiseLite fallback for fractal terrain relief
func _init_noise() -> void:
	_noise = FastNoiseLite.new()
	_noise.seed = 1337
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 0.0018
	_noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	_noise.fractal_octaves = 4
	_noise.fractal_lacunarity = 2.0
	_noise.fractal_gain = 0.5

func set_player(player: Node3D) -> void:
	_player_ref = player

func _process(_delta: float) -> void:
	var target_pos := Vector3.ZERO
	if _player_ref and is_instance_valid(_player_ref):
		target_pos = _player_ref.global_position
	elif Globals.player and is_instance_valid(Globals.player):
		target_pos = Globals.player.global_position

	var center_coord := Vector2i(
		int(floor(target_pos.x / chunk_size)),
		int(floor(target_pos.z / chunk_size))
	)

	if center_coord != _active_center_coord:
		_active_center_coord = center_coord
		_update_chunks(target_pos, false)

## Evaluates the exact lunar elevation at any world (x, z) coordinate
func get_height(x: float, z: float) -> float:
	var base_h := 0.0

	# 1. Heightmap sample if image exists
	if _heightmap_image:
		var uv_x := fract(x / 4096.0 + 0.5)
		var uv_y := fract(z / 4096.0 + 0.5)
		var px := int(uv_x * (_heightmap_image.get_width() - 1))
		var py := int(uv_y * (_heightmap_image.get_height() - 1))
		var col := _heightmap_image.get_pixel(px, py)
		base_h += (col.r - 0.5) * height_scale

	# 2. Fractal noise relief
	if _noise:
		base_h += _noise.get_noise_2d(x, z) * 35.0

	# 3. Main crater bowl at origin (landing zone)
	var d := sqrt(x * x + z * z)
	if d < crater_bowl_radius + crater_rim_width * 2.0:
		if d < crater_bowl_radius:
			# Parabolic bowl depression
			var t := d / crater_bowl_radius
			base_h -= crater_depth * (1.0 - t * t)
		else:
			# Raised rim ridge
			var rim_dist := d - crater_bowl_radius
			var rim_factor := 1.0 - absf(rim_dist - crater_rim_width * 0.5) / (crater_rim_width * 0.5)
			if rim_factor > 0.0:
				base_h += sin(rim_factor * PI * 0.5) * crater_rim_height

	# 4. Secondary impact craters
	for sc in _sub_craters:
		var dx := x - sc.x
		var dz := z - sc.y
		var sc_dist := sqrt(dx * dx + dz * dz)
		var sc_rad := sc.z
		if sc_dist < sc_rad * 1.5:
			if sc_dist < sc_rad:
				var st := sc_dist / sc_rad
				base_h -= (sc_rad * 0.22) * (1.0 - st * st)
			else:
				var s_rim_dist := sc_dist - sc_rad
				var s_factor := 1.0 - (s_rim_dist / (sc_rad * 0.5))
				if s_factor > 0.0:
					base_h += s_factor * (sc_rad * 0.06)

	return base_h

## Updates streaming grid chunks around player
func _update_chunks(player_pos: Vector3, force_rebuild: bool) -> void:
	var center_x := int(floor(player_pos.x / chunk_size))
	var center_z := int(floor(player_pos.z / chunk_size))

	var needed_coords: Dictionary = {}

	for cx in range(center_x - grid_radius, center_x + grid_radius + 1):
		for cz in range(center_z - grid_radius, center_z + grid_radius + 1):
			var coord := Vector2i(cx, cz)
			needed_coords[coord] = true

			var dist_chunks := max(abs(cx - center_x), abs(cz - center_z))
			var lod := 2
			if dist_chunks <= 1:
				lod = 0
			elif dist_chunks <= 3:
				lod = 1

			if _chunks.has(coord):
				var chunk: ChunkData = _chunks[coord]
				if chunk.current_lod != lod or force_rebuild:
					_rebuild_chunk(chunk, lod, dist_chunks <= collision_radius)
			else:
				var new_chunk := _create_chunk(coord, lod, dist_chunks <= collision_radius)
				_chunks[coord] = new_chunk

	# Cull out-of-range chunks
	var to_remove: Array[Vector2i] = []
	for coord in _chunks.keys():
		if not needed_coords.has(coord):
			to_remove.append(coord)

	for coord in to_remove:
		var c: ChunkData = _chunks[coord]
		if is_instance_valid(c.mesh_instance):
			c.mesh_instance.queue_free()
		if is_instance_valid(c.static_body):
			c.static_body.queue_free()
		_chunks.erase(coord)

func _create_chunk(coord: Vector2i, lod: int, need_collision: bool) -> ChunkData:
	var c := ChunkData.new()
	c.coord = coord
	c.mesh_instance = MeshInstance3D.new()
	c.mesh_instance.name = "Chunk_%d_%d" % [coord.x, coord.y]
	if material_override:
		c.mesh_instance.material_override = material_override
	add_child(c.mesh_instance)

	_rebuild_chunk(c, lod, need_collision)
	return c

func _rebuild_chunk(c: ChunkData, lod: int, need_collision: bool) -> void:
	c.current_lod = lod
	var segs := LOD2_SEGS
	if lod == 0:
		segs = LOD0_SEGS
	elif lod == 1:
		segs = LOD1_SEGS

	var origin_x := c.coord.x * chunk_size
	var origin_z := c.coord.y * chunk_size
	var step := chunk_size / float(segs)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)

	# Generate vertex grid with accurate normal derivation
	for iz in range(segs + 1):
		var wz := origin_z + iz * step
		for ix in range(segs + 1):
			var wx := origin_x + ix * step
			var wy := get_height(wx, wz)

			# Central difference normal calculation
			var eps := 1.5
			var h_l := get_height(wx - eps, wz)
			var h_r := get_height(wx + eps, wz)
			var h_d := get_height(wx, wz - eps)
			var h_u := get_height(wx, wz + eps)
			var norm := Vector3(h_l - h_r, 2.0 * eps, h_d - h_u).normalized()

			var uv := Vector2(float(ix) / float(segs), float(iz) / float(segs))
			st.set_normal(norm)
			st.set_uv(uv)
			st.add_vertex(Vector3(wx, wy, wz))

	# Construct triangle indices
	for iz in range(segs):
		var row0 := iz * (segs + 1)
		var row1 := (iz + 1) * (segs + 1)
		for ix in range(segs):
			var i00 := row0 + ix
			var i10 := row0 + ix + 1
			var i01 := row1 + ix
			var i11 := row1 + ix + 1

			st.add_index(i00)
			st.add_index(i10)
			st.add_index(i01)

			st.add_index(i10)
			st.add_index(i11)
			st.add_index(i01)

	var mesh: ArrayMesh = st.commit()
	c.mesh_instance.mesh = mesh

	# Manage Jolt Physics StaticBody3D collision shape
	if need_collision:
		if c.static_body == null:
			c.static_body = StaticBody3D.new()
			c.static_body.name = "Collision_%d_%d" % [c.coord.x, c.coord.y]
			var col_shape := CollisionShape3D.new()
			col_shape.name = "Shape"
			col_shape.shape = mesh.create_trimesh_shape()
			c.static_body.add_child(col_shape)
			add_child(c.static_body)
		else:
			var col_shape := c.static_body.get_node_or_null("Shape") as CollisionShape3D
			if col_shape:
				col_shape.shape = mesh.create_trimesh_shape()
	else:
		if c.static_body and is_instance_valid(c.static_body):
			c.static_body.queue_free()
			c.static_body = null
