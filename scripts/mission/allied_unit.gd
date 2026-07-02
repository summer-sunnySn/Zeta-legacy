## Zeta Legacy — Allied Unit (Mission Mode)
## A friendly object the player must protect: an ARIA station to DEFEND, or a
## civilian shuttle to ESCORT. Has its own health bar and dies if overwhelmed.
## Built procedurally (no imported assets — the editor importer is broken on this
## device; see project memory). Enemy bullets damage it via the "ally" group
## (see projectile.gd); the player's bullets pass through it (no friendly fire).
##
## Two modes, driven by configure():
##   "station" — holds position, slowly bobs, fires defensive shots at the swarm.
##   "mover"   — flies toward `goal`; emits reached_goal() on arrival.
extends Area3D

signal destroyed(unit)
signal reached_goal(unit)

# ─── Config / state ─────────────────────────────────────────────────────────
var max_health: int = 30
var health: int = 30
var mode: String = "station"          # "station" | "mover"
var goal: Vector3 = Vector3.ZERO       # destination for movers
var move_speed: float = 16.0
var accent: Color = Color(0.45, 0.85, 1.0)
var defends: bool = false              # station fires back at enemies
var unit_name: String = "ALLY"

const ALLY_LAYER := 16                  # collision layer 5 (enemy bullets mask this)
const ARRIVE_RADIUS := 6.0

var _dead: bool = false
var _arrived: bool = false
var _fire_cd: float = 0.0
var _bob_seed: float = 0.0
var _fill: MeshInstance3D = null
var _body_pivot: Node3D = null

# ─── Build ──────────────────────────────────────────────────────────────────
## `cfg` keys: mode, max_health, move_speed, accent, defends, name, goal.
func configure(cfg: Dictionary) -> void:
	mode = cfg.get("mode", "station")
	max_health = int(cfg.get("max_health", 30))
	health = max_health
	move_speed = float(cfg.get("move_speed", 16.0))
	accent = cfg.get("accent", Color(0.45, 0.85, 1.0))
	defends = bool(cfg.get("defends", false))
	unit_name = cfg.get("name", "ALLY")
	goal = cfg.get("goal", Vector3.ZERO)

func _ready() -> void:
	add_to_group("ally")
	collision_layer = ALLY_LAYER
	collision_mask = 0                  # we don't need to detect anything ourselves
	monitorable = true
	_bob_seed = randf() * TAU

	_body_pivot = Node3D.new()
	add_child(_body_pivot)
	if mode == "mover":
		_build_shuttle()
	else:
		_build_station()
	_build_collision()
	_build_health_bar()

func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 4.0 if mode == "mover" else 6.5
	col.shape = sh
	add_child(col)

## Chunky ARIA station: core block, a glowing ring of panels, antennae.
func _build_station() -> void:
	var core := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(6.0, 4.0, 6.0)
	core.mesh = bm
	core.material_override = _metal_mat()
	_body_pivot.add_child(core)

	# Glowing accent collar.
	var collar := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 5.2
	cyl.bottom_radius = 5.2
	cyl.height = 0.8
	collar.mesh = cyl
	collar.material_override = _glow_mat(2.0)
	_body_pivot.add_child(collar)

	# Solar panels left/right.
	for s in [-1.0, 1.0]:
		var panel := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(5.0, 0.2, 2.6)
		panel.mesh = pb
		panel.material_override = _glow_mat(0.6)
		panel.position = Vector3(s * 6.0, 0, 0)
		_body_pivot.add_child(panel)

	var light := OmniLight3D.new()
	light.light_color = accent
	light.light_energy = 2.0
	light.omni_range = 18.0
	_body_pivot.add_child(light)

## Small sleek civilian shuttle: body + swept wings + engine glow.
func _build_shuttle() -> void:
	var body := MeshInstance3D.new()
	var pm := PrismMesh.new()
	pm.size = Vector3(2.0, 1.4, 4.2)
	body.mesh = pm
	body.rotation = Vector3(deg_to_rad(-90.0), 0, 0)   # nose forward (-Z)
	body.material_override = _metal_mat()
	_body_pivot.add_child(body)

	for s in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var wb := BoxMesh.new()
		wb.size = Vector3(2.2, 0.16, 1.4)
		wing.mesh = wb
		wing.position = Vector3(s * 1.4, -0.1, 0.4)
		wing.rotation = Vector3(0, 0, s * 0.4)
		wing.material_override = _metal_mat()
		_body_pivot.add_child(wing)

	var engine := MeshInstance3D.new()
	var eb := BoxMesh.new()
	eb.size = Vector3(1.2, 0.6, 0.5)
	engine.mesh = eb
	engine.position = Vector3(0, 0, 2.0)
	engine.material_override = _glow_mat(3.0)
	_body_pivot.add_child(engine)

func _metal_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.7, 0.75, 0.82)
	m.metallic = 0.6
	m.roughness = 0.45
	return m

func _glow_mat(energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = accent
	m.emission_enabled = true
	m.emission = accent
	m.emission_energy_multiplier = energy
	return m

## Floating health bar (billboarded back plate + accent fill that shrinks).
func _build_health_bar() -> void:
	var bar := Node3D.new()
	bar.position = Vector3(0, 7.0 if mode != "mover" else 3.2, 0)
	add_child(bar)

	var back := MeshInstance3D.new()
	var bq := QuadMesh.new()
	bq.size = Vector2(8.0, 0.7)
	back.mesh = bq
	var bmat := StandardMaterial3D.new()
	bmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bmat.albedo_color = Color(0.05, 0.05, 0.08, 0.85)
	bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	bmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	back.mesh.material = bmat
	bar.add_child(back)

	_fill = MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(7.6, 0.5)
	_fill.mesh = fq
	var fmat := StandardMaterial3D.new()
	fmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fmat.albedo_color = accent
	fmat.emission_enabled = true
	fmat.emission = accent
	fmat.emission_energy_multiplier = 1.5
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_fill.mesh.material = fmat
	_fill.position = Vector3(0, 0, 0.02)
	bar.add_child(_fill)
	_update_bar()

func _update_bar() -> void:
	if _fill == null:
		return
	var frac := clampf(float(health) / float(max_health), 0.0, 1.0)
	_fill.scale.x = frac
	var mat := _fill.mesh.material as StandardMaterial3D
	if mat:
		# Green → orange → red as it drops.
		var col := Color(1.0 - frac, 0.2 + 0.7 * frac, 0.25).clamp()
		mat.albedo_color = col
		mat.emission = col

# ─── Per-frame ───────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _dead:
		return
	if mode == "mover":
		_advance(delta)
	else:
		# Gentle idle bob + slow spin for life.
		_body_pivot.position.y = sin((_bob_seed + Time.get_ticks_msec() * 0.001) * 1.2) * 0.3
		_body_pivot.rotate_y(delta * 0.3)
		if defends:
			_defensive_fire(delta)

func _advance(delta: float) -> void:
	if _arrived:
		return
	var to_goal := goal - global_position
	var d := to_goal.length()
	if d <= ARRIVE_RADIUS:
		_arrived = true
		reached_goal.emit(self)
		queue_free()
		return
	var dir := to_goal / maxf(d, 0.001)
	global_position += dir * move_speed * delta
	# Face travel direction.
	var up := Vector3.UP
	if absf(dir.dot(up)) > 0.98:
		up = Vector3.RIGHT
	_body_pivot.look_at(_body_pivot.global_position + dir, up)

## Station auto-defense — lob a player-team bolt at the nearest enemy.
func _defensive_fire(delta: float) -> void:
	_fire_cd -= delta
	if _fire_cd > 0.0:
		return
	var target := _nearest_enemy()
	if target == null:
		return
	_fire_cd = 1.4
	var bullet: Area3D = BulletPool.get_player_bullet()
	if bullet == null:
		return
	var origin := global_position + Vector3(0, 1.5, 0)
	bullet.global_position = origin
	bullet.direction = (target.global_position - origin).normalized()
	bullet.speed = 60.0
	bullet.damage = 1
	bullet.reset_lifetime()
	if bullet.has_method("orient_to_direction"):
		bullet.orient_to_direction()
	Audio.play("shoot", -18.0, 0.1)

func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_d := 90.0
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var d: float = global_position.distance_to((e as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

# ─── Damage / death ──────────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if _dead:
		return
	health -= amount
	_update_bar()
	_flash()
	if health <= 0:
		_die()
	else:
		Audio.play("hit", -10.0, 0.1)

func _flash() -> void:
	if _body_pivot == null:
		return
	var tw := create_tween()
	tw.tween_property(_body_pivot, "scale", Vector3(1.12, 1.12, 1.12), 0.05)
	tw.tween_property(_body_pivot, "scale", Vector3.ONE, 0.14)

func _die() -> void:
	if _dead:
		return
	_dead = true
	Audio.play("explosion", -2.0, 0.06)
	_spawn_explosion()
	destroyed.emit(self)
	queue_free()

func _spawn_explosion() -> void:
	var scene: PackedScene = load("res://scenes/fx/explosion.tscn")
	if scene == null:
		return
	var boom: Node3D = scene.instantiate()
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	if host:
		host.add_child(boom)
		boom.global_position = global_position
