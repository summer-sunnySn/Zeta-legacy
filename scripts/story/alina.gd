## Zeta Legacy — Alina (on-foot third-person soldier)
## CharacterBody3D driven by the FootHUD. Spherical Moon gravity —
## movement projected onto tangent plane, radial jump/fall, camera-relative.
## JETPACK flight, ENERGY SHIELD, auto-aim gunfire. PLSS: energy + oxygen.
## Placeholder body mesh — a rigged Alina model swaps in later.
extends CharacterBody3D

# ─── Movement ───────────────────────────────────────────────────────────
@export var move_speed: float = 7.5
@export var gravity: float = 6.5            ## low — Moon feel
@export var jump_velocity: float = 6.5
@export var turn_speed: float = 12.0

# ─── Spherical Gravity ───────────────────────────────────────────────────
@export var moon_center: Vector3 = Vector3.ZERO  ## set by moon_surface.gd

# ─── Jetpack (FLY) ──────────────────────────────────────────────────────
@export var fly_thrust: float = 16.0        ## upward accel while held
@export var fly_max_rise: float = 9.0       ## cap on upward speed
@export var fly_drain: float = 28.0         ## energy/sec while thrusting

# ─── Energy Shield ──────────────────────────────────────────────────────
@export var shield_duration: float = 3.0
@export var shield_drain: float = 22.0      ## energy/sec while up
@export var shield_cooldown: float = 1.2

# ─── Suit cell / life support ───────────────────────────────────────────
@export var energy_max: float = 100.0
@export var energy_regen: float = 16.0      ## energy/sec when idle
@export var oxygen_max: float = 100.0
@export var oxygen_drain: float = 0.6       ## slow PLSS consumption

# ─── Guns ───────────────────────────────────────────────────────────────
@export var fire_cooldown: float = 0.16
@export var bullet_speed: float = 70.0
@export var bullet_damage: int = 1
@export var aim_range: float = 70.0
@export var aim_cone: float = 0.25
@export var max_health: int = 8

# ─── Wiring (set by moon_surface.gd) ────────────────────────────────────
var hud: Node = null
var cam: Node3D = null
var active: bool = false

# ─── State ──────────────────────────────────────────────────────────────
var health: int = 8
var energy: float = 100.0
var oxygen: float = 100.0
var shield_active: bool = false
var _shield_t: float = 0.0
var _shield_cd: float = 0.0
var _fire_t: float = 0.0
var _muzzle_flash_t: float = 0.0
var _hit_flash_t: float = 0.0

@onready var mesh_pivot: Node3D = $MeshPivot
@onready var muzzle: Node3D = $MeshPivot/Muzzle
@onready var muzzle_flash: MeshInstance3D = $MeshPivot/Muzzle/Flash
@onready var shield_mesh: MeshInstance3D = $ShieldBubble

func _ready() -> void:
	add_to_group("player")
	Globals.player = self
	health = max_health
	energy = energy_max
	oxygen = oxygen_max
	if muzzle_flash:
		muzzle_flash.visible = false
	if shield_mesh:
		shield_mesh.visible = false

# ─── Public read-outs (HUD) ─────────────────────────────────────────────
func current_speed_xz() -> float:
	# Tangential speed relative to Moon center.
	var surface_normal: Vector3 = Vector3.UP
	var radial_vel := velocity.dot(surface_normal)
	var tangential_vel := velocity - surface_normal * radial_vel
	return tangential_vel.length()
func energy_fraction() -> float:
	return clampf(energy / energy_max, 0.0, 1.0)
func oxygen_fraction() -> float:
	return clampf(oxygen / oxygen_max, 0.0, 1.0)
func is_shielding() -> bool:
	return shield_active
func is_flying() -> bool:
	return not is_on_floor()

# ─── Damage ─────────────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	if not active:
		return
	if shield_active:
		Audio.play("hit", -8.0, 0.15)       ## shield absorbs the hit
		energy = maxf(0.0, energy - 8.0)
		return
	health -= amount
	_hit_flash_t = 0.18
	Audio.play("player_hit", -4.0)
	Globals.player_hit.emit()
	if health <= 0:
		health = 0
		_die()

func _die() -> void:
	active = false
	Audio.play("explosion", -2.0)
	Globals.player_destroyed.emit()

# ─── Loop ───────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	if _muzzle_flash_t > 0.0:
		_muzzle_flash_t = maxf(0.0, _muzzle_flash_t - delta)
		if muzzle_flash:
			muzzle_flash.visible = _muzzle_flash_t > 0.0
	if _hit_flash_t > 0.0:
		_hit_flash_t = maxf(0.0, _hit_flash_t - delta)

	if not active:
		velocity = Vector3.ZERO
		return

	_update_suit(delta)

	# ── Spherical Gravity & Up Direction ────────────────────────────────
	# Surface normal = radial vector from Moon center to player.
	var surface_normal: Vector3 = Vector3.UP
	up_direction = surface_normal

	# Camera-relative movement projected onto tangent plane.
	var mv: Vector2 = Vector2.ZERO
	if hud and hud.has_method("get_move_vector"):
		mv = hud.get_move_vector()
	var basis_flat := _cam_flat_basis_spherical(surface_normal)
	var fwd: Vector3 = basis_flat[0]
	var right: Vector3 = basis_flat[1]
	var wish_3d := (fwd * mv.y + right * mv.x)
	if wish_3d.length() > 1.0:
		wish_3d = wish_3d.normalized()
	# Apply move speed along tangent plane.
	var wish_vel := wish_3d * move_speed

	# Gravity (skipped while jetpacking up).
	var flying: bool = hud and ("fly_held" in hud) and hud.fly_held and energy > 0.0
	if flying:
		# Jetpack thrust along surface normal (away from Moon).
		velocity += surface_normal * fly_thrust * delta
		# Clamp upward radial velocity.
		var radial_vel := velocity.dot(surface_normal)
		if radial_vel > fly_max_rise:
			velocity -= surface_normal * (radial_vel - fly_max_rise)
		energy = maxf(0.0, energy - fly_drain * delta)
	elif not is_on_floor():
		# Fall toward Moon center.
		velocity -= surface_normal * gravity * delta * 3.0
	else:
		# On floor: cancel radial velocity component, keep tangential.
		var radial_vel := velocity.dot(surface_normal)
		if radial_vel < 0.0:
			velocity -= surface_normal * radial_vel

	# Set tangential velocity components (preserve radial, replace tangential).
	var radial_comp := surface_normal * velocity.dot(surface_normal)
	velocity = radial_comp + wish_vel

	# Jump (magnetic boots release) — along surface normal.
	if hud and hud.has_method("consume_jump") and hud.consume_jump() and is_on_floor():
		velocity += surface_normal * jump_velocity

	move_and_slide()

	# Firing + facing.
	var target: Node3D = _acquire_target()
	_face(delta, wish_3d, target)
	_fire_t = maxf(0.0, _fire_t - delta)
	var firing: bool = hud and ("firing" in hud) and hud.firing
	if firing and _fire_t <= 0.0:
		_shoot(target)
		_fire_t = fire_cooldown

# ─── Suit systems: shield + energy + oxygen ─────────────────────────────
func _update_suit(delta: float) -> void:
	oxygen = maxf(0.0, oxygen - oxygen_drain * delta)

	_shield_cd = maxf(0.0, _shield_cd - delta)
	# Activate shield on request.
	if hud and hud.has_method("consume_shield") and hud.consume_shield():
		if not shield_active and _shield_cd <= 0.0 and energy > 12.0:
			shield_active = true
			_shield_t = shield_duration
			Audio.play("powerup", -6.0)
	# Maintain / drain shield.
	if shield_active:
		_shield_t -= delta
		energy = maxf(0.0, energy - shield_drain * delta)
		if _shield_t <= 0.0 or energy <= 0.0:
			shield_active = false
			_shield_cd = shield_cooldown
	if shield_mesh:
		shield_mesh.visible = shield_active

	# Regenerate energy when neither flying nor shielding.
	var flying: bool = hud and ("fly_held" in hud) and hud.fly_held
	if not shield_active and not flying:
		energy = minf(energy_max, energy + energy_regen * delta)

# ─── Helpers ────────────────────────────────────────────────────────────
func _cam_flat_basis() -> Array:
	var b: Basis = global_transform.basis
	if cam and is_instance_valid(cam):
		b = cam.global_transform.basis
	var fwd := -b.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()
	var right := b.x
	right.y = 0.0
	if right.length_squared() < 0.001:
		right = Vector3.RIGHT
	right = right.normalized()
	return [fwd, right]

## Camera-relative basis projected onto tangent plane of given surface normal.
func _cam_flat_basis_spherical(surface_normal: Vector3) -> Array:
	var b: Basis = global_transform.basis
	if cam and is_instance_valid(cam):
		b = cam.global_transform.basis
	# Camera forward projected onto tangent plane.
	var fwd := -b.z
	fwd = (fwd - surface_normal * fwd.dot(surface_normal)).normalized()
	if fwd.length_squared() < 0.001:
		# Fallback: arbitrary tangent vector.
		fwd = (Vector3.UP - surface_normal * surface_normal.dot(Vector3.UP)).normalized()
		if fwd.length_squared() < 0.001:
			fwd = Vector3.FORWARD
	# Camera right projected onto tangent plane.
	var right := b.x
	right = (right - surface_normal * right.dot(surface_normal)).normalized()
	if right.length_squared() < 0.001:
		right = surface_normal.cross(fwd)
	return [fwd, right]

func _acquire_target() -> Node3D:
	var surface_normal: Vector3 = Vector3.UP
	var face_dir := -mesh_pivot.global_transform.basis.z
	if cam and is_instance_valid(cam):
		var cf := -cam.global_transform.basis.z
		# Project camera forward onto tangent plane.
		cf = cf - surface_normal * cf.dot(surface_normal)
		if cf.length_squared() > 0.001:
			face_dir = cf.normalized()
	var best: Node3D = null
	var best_d := aim_range
	for e in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(e):
			continue
		var to: Vector3 = (e.global_position - global_position)
		var d := to.length()
		if d > aim_range or d < 0.1:
			continue
		# Project to->enemy vector onto tangent plane.
		var tangent_to := to - surface_normal * to.dot(surface_normal)
		if tangent_to.length_squared() < 0.001:
			continue
		tangent_to = tangent_to.normalized()
		if tangent_to.dot(face_dir) < aim_cone:
			continue
		if d < best_d:
			best_d = d
			best = e
	return best

func _face(delta: float, wish: Vector3, target: Node3D) -> void:
	var look: Vector3 = Vector3.ZERO
	var surface_normal: Vector3 = Vector3.UP
	if target and is_instance_valid(target):
		look = target.global_position - global_position
	elif wish.length_squared() > 0.01:
		look = wish
	# Project look onto tangent plane.
	look = look - surface_normal * look.dot(surface_normal)
	if look.length_squared() < 0.001:
		return
	look = look.normalized()
	var goal := Transform3D().looking_at(look, surface_normal)
	var cur := mesh_pivot.global_transform.basis.orthonormalized()
	mesh_pivot.global_transform.basis = cur.slerp(goal.basis, clampf(turn_speed * delta, 0.0, 1.0))

func _shoot(target: Node3D) -> void:
	var bullet: Area3D = BulletPool.get_player_bullet()
	if bullet == null:
		return
	var origin: Vector3 = muzzle.global_position
	var dir: Vector3 = -mesh_pivot.global_transform.basis.z
	if target and is_instance_valid(target):
		dir = (target.global_position + Vector3(0, 0.4, 0) - origin).normalized()
	bullet.global_position = origin
	bullet.direction = dir.normalized()
	bullet.speed = bullet_speed
	bullet.damage = bullet_damage
	bullet.reset_lifetime()
	if bullet.has_method("orient_to_direction"):
		bullet.orient_to_direction()
	_muzzle_flash_t = 0.05
	if muzzle_flash:
		muzzle_flash.visible = true
	Audio.play("shoot", -10.0, 0.12)
