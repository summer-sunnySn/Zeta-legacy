## Zeta Legacy — Companion Bot "PIP"
## A small circular salvage-AI that boots up after Alina's ship crashes and
## sticks with her on the Moon.  It gently orbits around her, faces threats, and
## its little gun auto-fires at the nearest alien drone to help in a fight.
## Dialogue is spoken through the moon_surface director under the speaker "PIP".
##
## Reuses the shared player BulletPool (its shots hit the "enemy" group exactly
## like Alina's) and the spherical-Moon math (radial up = orbit + hover plane).
extends Node3D

const BOT_NAME := "PIP"
const ACCENT := Color(0.4, 0.9, 1.0)     ## subtitle accent for PIP's lines

# ─── Tuning ──────────────────────────────────────────────────────────────
@export var moon_center: Vector3 = Vector3.ZERO   ## set by moon_surface.gd
@export var hover_height: float = 1.9             ## metres above Alina (radial)
@export var orbit_radius: float = 1.15
@export var orbit_speed: float = 0.7
@export var follow_smooth: float = 4.0
@export var fire_range: float = 38.0
@export var fire_cooldown: float = 0.55
@export var bullet_speed: float = 52.0
@export var bullet_damage: int = 1

# ─── State ───────────────────────────────────────────────────────────────
var active: bool = false          ## true once gameplay starts (enables the gun)
var _orbit: float = 0.0
var _t: float = 0.0
var _fire_t: float = 0.0
var _scanning: bool = false       ## cute "working..." pulse during comms beats

@onready var model_pivot: Node3D = $ModelPivot
@onready var muzzle: Node3D = $ModelPivot/GunArm/Muzzle
@onready var eye: MeshInstance3D = $ModelPivot/Eye

const ROBOT_MODEL := "res://models/moon/robot_ball.glb"   # swap-in (see README)

func _ready() -> void:
	_orbit = randf() * TAU
	_install_model()

## If the player dropped a robot_ball.glb into models/moon/, use it for PIP's
## look (the procedural shell is hidden; Eye/Muzzle nodes stay for logic).
func _install_model() -> void:
	if model_pivot == null or not FileAccess.file_exists(ROBOT_MODEL):
		return
	var m: Node3D = ModelLib.instance_model(ROBOT_MODEL)
	if m == null:
		return
	for c in model_pivot.get_children():
		if c is MeshInstance3D:
			c.visible = false          # hide procedural shell/eye/ring
	model_pivot.add_child(m)
	m.transform = Transform3D.IDENTITY
	ModelLib.fit(m, 1.4)
	ModelLib.play_loop(m)              # plays a baked animation if the model has one

func _physics_process(delta: float) -> void:
	_t += delta
	var player: Node3D = Globals.player
	if player == null or not is_instance_valid(player):
		return

	# ── Hover / orbit around Alina on the tangent plane ──────────────────
	var up: Vector3 = Vector3.UP        # flat moon ground
	_orbit += delta * orbit_speed
	var t1: Vector3 = up.cross(Vector3.FORWARD)
	if t1.length_squared() < 0.001:
		t1 = up.cross(Vector3.RIGHT)
	t1 = t1.normalized()
	var t2: Vector3 = up.cross(t1).normalized()
	var offset: Vector3 = (t1 * cos(_orbit) + t2 * sin(_orbit)) * orbit_radius
	var target: Vector3 = player.global_position + up * hover_height + offset
	global_position = global_position.lerp(target, clampf(follow_smooth * delta, 0.0, 1.0))

	# ── Cute idle bob + eye pulse ────────────────────────────────────────
	if model_pivot:
		model_pivot.position.y = sin(_t * 2.5) * 0.05
	if eye:
		var pulse: float = 1.0 + (0.25 if _scanning else 0.08) * sin(_t * (9.0 if _scanning else 3.0))
		eye.scale = Vector3.ONE * pulse

	# ── Combat: face + shoot the nearest drone ───────────────────────────
	var tgt: Node3D = _nearest_enemy() if (active and not Globals.is_game_over) else null
	if tgt:
		_face(tgt, up, delta)
		_fire_t -= delta
		if _fire_t <= 0.0:
			_shoot(tgt)
			_fire_t = fire_cooldown
	elif model_pivot:
		# No target → slow, friendly idle spin.
		model_pivot.rotation.y += delta * 1.0

# ─── Targeting ─────────────────────────────────────────────────────────────
func _nearest_enemy() -> Node3D:
	var best: Node3D = null
	var best_d: float = fire_range
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var d: float = e.global_position.distance_to(global_position)
		if d < best_d:
			best_d = d
			best = e
	return best

func _face(tgt: Node3D, up: Vector3, delta: float) -> void:
	if model_pivot == null:
		return
	var look: Vector3 = tgt.global_position - global_position
	if look.length_squared() < 0.001:
		return
	look = look.normalized()
	if absf(look.dot(up)) > 0.98:
		up = up.cross(Vector3.FORWARD).normalized()
	var goal := Transform3D().looking_at(look, up)
	var cur := model_pivot.global_transform.basis.orthonormalized()
	model_pivot.global_transform.basis = cur.slerp(goal.basis, clampf(8.0 * delta, 0.0, 1.0))

func _shoot(tgt: Node3D) -> void:
	var b: Area3D = BulletPool.get_player_bullet()
	if b == null:
		return
	var origin: Vector3 = muzzle.global_position if muzzle else global_position
	var dir: Vector3 = (tgt.global_position + Vector3(0, 0.4, 0) - origin).normalized()
	b.global_position = origin
	b.direction = dir
	b.speed = bullet_speed
	b.damage = bullet_damage
	b.reset_lifetime()
	if b.has_method("orient_to_direction"):
		b.orient_to_direction()
	Audio.play("shoot", -14.0, 0.2)
	# Cute little recoil pop.
	if model_pivot:
		var tw := create_tween()
		tw.tween_property(model_pivot, "scale", Vector3(0.9, 0.9, 0.9), 0.04)
		tw.tween_property(model_pivot, "scale", Vector3.ONE, 0.1)

# ─── Cutscene hooks (called by moon_surface director) ──────────────────────
func set_active(v: bool) -> void:
	active = v

## Toggle the fast "working / scanning" eye pulse used during the comms beats.
func set_scanning(v: bool) -> void:
	_scanning = v

## One-off bright blink (e.g. on a failed connection retry).
func blink() -> void:
	if eye == null:
		return
	var tw := create_tween()
	tw.tween_property(eye, "scale", Vector3(1.6, 1.6, 1.6), 0.06)
	tw.tween_property(eye, "scale", Vector3.ONE, 0.18)
