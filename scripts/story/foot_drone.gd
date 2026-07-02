## Zeta Legacy — On-foot Alien Drone (Spherical Moon)
## Floating hostile that hovers above the Moon surface, keeps a stand-off
## distance from Alina, strafes, fires, and melees on contact. Reuses the
## shared BulletPool and explosion FX. Area3D in the "enemy" group so player
## bullets (mask 2 → layer 2) hit it.
## Works on spherical Moon: movement on tangent planes, radial gravity.
extends Area3D

@export var move_speed: float = 7.0
@export var hover_height: float = 3.2        ## metres above the surface (radial)
@export var preferred_dist: float = 15.0     ## stand-off range while shooting
@export var strafe_speed: float = 2.2
@export var health: int = 3
@export var score_value: int = 120
@export var touch_damage: int = 1
@export var fire_cooldown: float = 1.5
@export var bullet_speed: float = 24.0
@export var moon_center: Vector3 = Vector3.ZERO  ## set by moon_surface.gd

const UFO_MODEL := "res://models/enemies/ufo.glb"   # animated alien (runtime-loaded)

@onready var model_pivot: Node3D = $ModelPivot
@onready var fire_timer: Timer = $FireTimer
var _ufo: Node3D = null

var _can_fire: bool = true
var _wobble: float = 0.0
var _strafe_dir: float = 1.0
var _t: float = 0.0

func _ready() -> void:
	add_to_group("enemy")
	Globals.on_enemy_spawned()
	_wobble = randf() * TAU
	_strafe_dir = 1.0 if randf() > 0.5 else -1.0
	fire_timer.wait_time = fire_cooldown
	fire_timer.one_shot = true
	if not fire_timer.timeout.is_connected(_on_fire_ready):
		fire_timer.timeout.connect(_on_fire_ready)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_install_ufo()

## Swap the placeholder drone mesh for the animated UFO.
func _install_ufo() -> void:
	if model_pivot == null:
		return
	var old := model_pivot.get_node_or_null("DroneModel")
	if old:
		old.free()
	var ufo: Node3D = ModelLib.instance_model(UFO_MODEL)
	if ufo == null:
		return
	ufo.name = "DroneModel"
	model_pivot.add_child(ufo)
	ufo.transform = Transform3D.IDENTITY
	ModelLib.fit(ufo, 3.2)
	# Cheap spin instead of the heavy baked AnimationPlayer (weak-phone safety).
	_ufo = ufo

func _physics_process(delta: float) -> void:
	if Globals.is_game_over:
		return
	var player := Globals.player
	if player == null or not is_instance_valid(player):
		return

	_t += delta
	var to_player: Vector3 = player.global_position - global_position
	var dist: float = to_player.length()
	if dist < 0.001:
		return

	# Flat moon ground: up is world-up.
	var my_normal: Vector3 = Vector3.UP

	# Direction toward player projected onto MY tangent plane.
	var to_tangent: Vector3 = (to_player - my_normal * to_player.dot(my_normal)).normalized()
	if to_tangent.length_squared() < 0.001:
		return

	# Close in / back off to hold the stand-off ring (tangential).
	var horiz := Vector3.ZERO
	if dist > preferred_dist + 1.5:
		horiz = to_tangent
	elif dist < preferred_dist - 1.5:
		horiz = -to_tangent * 0.6

	# Strafe perpendicular to to_tangent on tangent plane.
	var strafe_dir := my_normal.cross(to_tangent).normalized()
	var strafe := strafe_dir * _strafe_dir
	if int(_t * 0.5) % 3 == 0:
		_strafe_dir = -_strafe_dir

	# Hold hover_height above the flat ground (y = 0).
	var radial_vel := clampf(hover_height - global_position.y, -3.0, 3.0)

	# Move on tangent plane + radial correction.
	var motion := (horiz * move_speed + strafe * strafe_speed) + my_normal * radial_vel
	global_position += motion * delta

	# Bob + face the target.
	if model_pivot:
		model_pivot.position.y = sin(_t * 3.0 + _wobble) * 0.15
		_orient_model(player, delta)

	_maybe_fire(player, dist)

func _orient_model(player: Node3D, delta: float) -> void:
	var look := player.global_position - global_position
	if look.length_squared() < 0.001:
		return
	# Use local radial up for orientation (natural on sphere).
	var up := Vector3.UP
	if absf(look.normalized().dot(up)) > 0.98:
		up = up.cross(Vector3.FORWARD).normalized()
	var goal := Transform3D().looking_at(look.normalized(), up)
	var cur := model_pivot.global_transform.basis.orthonormalized()
	model_pivot.global_transform.basis = cur.slerp(goal.basis, clampf(7.0 * delta, 0.0, 1.0))
	if _ufo:
		_ufo.rotate_y(delta * 2.2)        # cheap spinning-UFO look

# ─── Shooting ───────────────────────────────────────────────────────────
func _maybe_fire(player: Node3D, dist: float) -> void:
	if not _can_fire or dist > preferred_dist * 1.8:
		return
	_fire_at(player)
	if randf() < 0.6:
		Audio.play("enemy_shoot", -15.0, 0.1)
	_can_fire = false
	fire_timer.start()

func _fire_at(player: Node3D) -> void:
	var bullet: Area3D = BulletPool.get_enemy_bullet()
	if bullet == null:
		return
	var dir_to_player := (player.global_position - global_position).normalized()
	var origin := global_position + dir_to_player * 1.5
	bullet.global_position = origin
	var aim := player.global_position + Vector3(0.0, 0.8, 0.0)
	bullet.direction = (aim - origin).normalized()
	bullet.speed = bullet_speed
	bullet.damage = touch_damage
	bullet.reset_lifetime()
	if bullet.has_method("orient_to_direction"):
		bullet.orient_to_direction()

func _on_fire_ready() -> void:
	_can_fire = true

# ─── Collisions / Damage ────────────────────────────────────────────────
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(touch_damage)
		_explode()

func take_damage(amount: int) -> void:
	health -= amount
	_flash_hit()
	if health <= 0:
		_explode()
	else:
		Audio.play("hit", -9.0, 0.1)

func _flash_hit() -> void:
	if model_pivot == null:
		return
	var tw := create_tween()
	tw.tween_property(model_pivot, "scale", Vector3(1.2, 1.2, 1.2), 0.04)
	tw.tween_property(model_pivot, "scale", Vector3.ONE, 0.12)

func _explode() -> void:
	Globals.register_kill(score_value, global_position)
	Audio.play("explosion", -3.0, 0.08)
	_spawn_explosion()
	queue_free()

func _spawn_explosion() -> void:
	var scene: PackedScene = load("res://scenes/fx/explosion.tscn")
	if scene == null:
		return
	var boom: Node3D = scene.instantiate()
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	host.add_child(boom)
	boom.global_position = global_position
