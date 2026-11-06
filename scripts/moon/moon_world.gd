## Zeta Legacy — Moon World Controller
## Manages environment setup, Gfx quality integration, crash site markers:
## - PlayerShip (crashed inside the central crater bowl)
## - CrashSite_1..4 (teammate wreckage spread across sectors)
## - CrashSite_Leader (farthest wreckage outside the crater bowl)
## - get_signal_strength(target: Vector3) -> float (0..1 by distance)
class_name MoonWorld
extends Node3D

@onready var world_env: WorldEnvironment = $WorldEnvironment
@onready var sun: DirectionalLight3D = $Celestial/Sun
@onready var terrain: LunarTerrain = $Terrain
@onready var player: LunarPlayer = $Player

# Markers
@onready var marker_player_ship: Marker3D = $Markers/PlayerShip
@onready var marker_crash_1: Marker3D = $Markers/CrashSite_1
@onready var marker_crash_2: Marker3D = $Markers/CrashSite_2
@onready var marker_crash_3: Marker3D = $Markers/CrashSite_3
@onready var marker_crash_4: Marker3D = $Markers/CrashSite_4
@onready var marker_crash_leader: Marker3D = $Markers/CrashSite_Leader

## Maximum detection radius for signal meters (e.g. 2500m)
@export var max_signal_range: float = 2500.0

func _ready() -> void:
	# 1. Integrate with Gfx quality manager
	Gfx.apply(world_env, sun)
	_apply_quality_tier()

	# 2. Register player in Globals
	if player:
		Globals.player = player
		if terrain:
			terrain.set_player(player)

	# 3. Setup wreckage visuals on markers
	_setup_crash_sites()

## Calculates distance-based signal strength [0.0..1.0] from player to target
func get_signal_strength(target: Vector3) -> float:
	var player_pos := Vector3.ZERO
	if player and is_instance_valid(player):
		player_pos = player.global_position
	elif Globals.player and is_instance_valid(Globals.player):
		player_pos = Globals.player.global_position

	var dist := player_pos.distance_to(target)
	if dist >= max_signal_range:
		return 0.0

	# Normalized curve with slight falloff curve
	var t := clampf(1.0 - (dist / max_signal_range), 0.0, 1.0)
	return pow(t, 1.3)

## Quality tier hook to tune particle counts, shadow splits, and terrain LOD ranges
## Handles low/med/high tiers seamlessly (Gfx.LOW=0, Gfx.MEDIUM=1, Gfx.ULTRA=2 / high)
func _apply_quality_tier() -> void:
	var q := Gfx.current()
	if terrain:
		if q <= 0: # Low
			terrain.grid_radius = 5
			terrain.collision_radius = 1
		elif q == 1: # Medium
			terrain.grid_radius = 7
			terrain.collision_radius = 2
		else: # High / Ultra
			terrain.grid_radius = 9
			terrain.collision_radius = 3

	# Adapt Sun shadow splits according to quality
	if sun and sun.shadow_enabled:
		if q <= 0:
			sun.shadow_enabled = false
		elif q == 1:
			sun.directional_shadow_split_1 = 0.08
			sun.directional_shadow_split_2 = 0.25
			sun.directional_shadow_max_distance = 180.0
		else:
			sun.directional_shadow_split_1 = 0.05
			sun.directional_shadow_split_2 = 0.15
			sun.directional_shadow_max_distance = 320.0

func _setup_crash_sites() -> void:
	var sites := [
		{"marker": marker_player_ship, "color": Color(0.2, 0.4, 0.8), "name": "PlayerShip"},
		{"marker": marker_crash_1, "color": Color(0.8, 0.3, 0.2), "name": "Recon Wing Alpha"},
		{"marker": marker_crash_2, "color": Color(0.7, 0.6, 0.2), "name": "Heavy Hauler Beta"},
		{"marker": marker_crash_3, "color": Color(0.2, 0.7, 0.4), "name": "Scout Delta"},
		{"marker": marker_crash_4, "color": Color(0.5, 0.2, 0.7), "name": "Interceptor Gamma"},
		{"marker": marker_crash_leader, "color": Color(0.9, 0.8, 0.1), "name": "Flagship Command"}
	]

	for site in sites:
		var m: Marker3D = site["marker"]
		if m == null:
			continue

		# Snap marker to terrain elevation
		if terrain:
			var h := terrain.get_height(m.global_position.x, m.global_position.z)
			m.global_position.y = h

		# Spawn placeholder wreckage geometry
		var wreck := _create_wreckage_mesh(site["color"])
		m.add_child(wreck)

		# Add smoke/dust column from LunarScatter helper
		var smoke := LunarScatter.create_crash_smoke()
		smoke.position = Vector3(0, 0.5, 0)
		m.add_child(smoke)

func _create_wreckage_mesh(tint: Color) -> Node3D:
	var root := Node3D.new()

	var hull := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(3.5, 1.2, 7.0)
	hull.mesh = box

	var mat := StandardMaterial3D.new()
	mat.albedo_color = tint.darkened(0.3)
	mat.metallic = 0.85
	mat.roughness = 0.45
	hull.material_override = mat
	hull.position = Vector3(0, 0.6, 0)
	hull.rotation = Vector3(0.2, 0.4, -0.15)
	root.add_child(hull)

	var sheared_wing := MeshInstance3D.new()
	var wbox := BoxMesh.new()
	wbox.size = Vector3(4.0, 0.2, 2.0)
	sheared_wing.mesh = wbox
	sheared_wing.material_override = mat
	sheared_wing.position = Vector3(2.5, 0.2, -0.5)
	sheared_wing.rotation = Vector3(0.1, -0.5, -0.3)
	root.add_child(sheared_wing)

	return root
