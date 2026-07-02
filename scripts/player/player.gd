## Zeta Legacy — Player Ship Controller (Zeta Interceptor)
## Full 360° third-person flight. The ship cruises forward along its own
## heading; the pilot pitches and yaws to fly anywhere in the arena. Aiming is
## decoupled from flight — you can fly one way and shoot another (strafe fire).
##
## Input comes from EITHER the keyboard/gamepad OR a touch HUD assigned to
## `hud`. Everything HUD-related is null-guarded so the ship flies standalone.
extends CharacterBody3D

const ShipRoster = preload("res://scripts/arcade/ship_roster.gd")
## The player always flies the Intergalactic spaceship (runtime-loaded via
## ModelLib — the editor importer is broken on this device). Roster choice still
## drives stats/handling.
const PLAYER_MODEL := "res://models/ships/intergalactic.glb"
@export var model_target_len: float = 4.2
@export var model_yaw: float = PI        ## spin so the nose points down −Z (game forward)

# ─── Flight Tuning ──────────────────────────────────────────────────────
@export_group("Flight")
@export var cruise_speed: float = 16.0       ## default forward velocity (m/s)
@export var boost_speed: float = 28.0        ## hold boost
@export var brake_speed: float = 8.0         ## hold brake
@export var throttle_smooth: float = 3.0
@export var dash_speed: float = 56.0         ## burst dodge
@export var dash_time: float = 0.28
@export var dash_cooldown: float = 1.3
@export var yaw_rate: float = 1.8            ## radians/sec turn (left/right)
@export var pitch_rate: float = 1.5         ## radians/sec turn (up/down)
@export var max_bank: float = 0.7           ## visual roll into a turn (radians)
@export var bank_smooth: float = 6.0
@export var turn_smooth: float = 7.0        ## how quickly steering ramps in
@export var invert_pitch: bool = false

# ─── Combat Tuning ──────────────────────────────────────────────────────
@export_group("Combat")
@export var fire_rate: float = 0.1          ## seconds between shots
@export var bullet_speed: float = 90.0
@export var bullet_damage: int = 1
@export var aim_distance: float = 120.0     ## how far down the aim ray bullets converge
@export var aim_assist_cone: float = 0.14   ## radians; drones within this of the reticle get locked
@export var max_health: int = 6

# ─── External Wiring ────────────────────────────────────────────────────
## Assigned by main.gd. Provides steer vector, fire state and reticle position.
var hud: Node = null

# ─── Node References ────────────────────────────────────────────────────
@onready var mesh_pivot: Node3D = $MeshPivot         ## holds the ship model; rolls for banking
@onready var muzzles: Node3D    = $MeshPivot/Muzzles ## one or more Marker3D children
@onready var muzzle_flash: OmniLight3D = $MeshPivot/MuzzleFlash
@onready var shield_fx: MeshInstance3D = $Shield

## Active power-ups: kind -> seconds remaining. Durations below.
const POWERUP_DURATION := {"rapid": 8.0, "spread": 11.0, "shield": 7.0}
var _powerups: Dictionary = {}
@onready var inv_timer: Timer   = $InvincibilityTimer
@onready var fire_timer: Timer  = $FireTimer

# ─── State ──────────────────────────────────────────────────────────────
@export var base_smart_bombs: int = 2
var active: bool = false                    ## set true by main.gd when the round starts
var health: int
var smart_bombs: int = 2
var is_invincible: bool = false
var current_speed: float = 0.0
var _dash_t: float = 0.0
var _dash_cd: float = 0.0
var _dash_iframes: bool = false
var _steer: Vector2 = Vector2.ZERO          ## smoothed (x = yaw, y = pitch)
var _muzzle_list: Array[Marker3D] = []

# ─── Lifecycle ──────────────────────────────────────────────────────────
func _ready() -> void:
	# Free flight — no gravity, no floor snapping.
	motion_mode = CharacterBody3D.MOTION_MODE_FLOATING

	# Apply the chosen arcade ship (model + stat modifiers) BEFORE upgrades.
	_apply_selected_ship()

	# Apply permanent upgrades from the meta-progression.
	fire_rate *= pow(0.88, Save.upgrade_level("firerate"))
	max_health += Save.upgrade_level("health")
	bullet_damage += Save.upgrade_level("damage")
	smart_bombs = base_smart_bombs + Save.upgrade_level("bombs")

	health = max_health
	current_speed = cruise_speed
	Globals.player = self

	fire_timer.wait_time = fire_rate
	fire_timer.one_shot = true
	inv_timer.wait_time = 1.2
	inv_timer.one_shot = true
	if not inv_timer.timeout.is_connected(_on_invincibility_end):
		inv_timer.timeout.connect(_on_invincibility_end)

	_collect_muzzles()

func _physics_process(delta: float) -> void:
	if not active or Globals.is_game_over:
		return

	_update_steer(delta)
	_update_throttle(delta)
	_update_dash(delta)
	_fly(delta)
	_bank(delta)
	_handle_fire()

	# Decay the muzzle flash each frame (set to peak in _fire).
	if muzzle_flash and muzzle_flash.light_energy > 0.01:
		muzzle_flash.light_energy = move_toward(muzzle_flash.light_energy, 0.0, 28.0 * delta)

	_update_powerups(delta)

# ─── Power-ups ──────────────────────────────────────────────────────────
func _update_powerups(delta: float) -> void:
	for k in _powerups.keys():
		_powerups[k] -= delta
		if _powerups[k] <= 0.0:
			_powerups.erase(k)
	# Shield bubble — visible + pulsing while active.
	if shield_fx:
		var on := _powerups.has("shield")
		shield_fx.visible = on
		if on:
			var s := 1.0 + sin(Time.get_ticks_msec() * 0.008) * 0.05
			shield_fx.scale = Vector3(s, s, s)

func activate_powerup(kind: String) -> void:
	match kind:
		"health":
			health = mini(health + 2, max_health)
			_flash_damage()   ## quick pulse as feedback
		_:
			_powerups[kind] = POWERUP_DURATION.get(kind, 8.0)

## Read by the HUD to draw active-power-up timers.
func get_powerups() -> Dictionary:
	return _powerups

func powerup_fraction(kind: String) -> float:
	return clampf(float(_powerups.get(kind, 0.0)) / float(POWERUP_DURATION.get(kind, 8.0)), 0.0, 1.0)

## Smart bomb — emergency screen-clear. Big damage to everything on field.
func use_smart_bomb() -> void:
	if smart_bombs <= 0 or Globals.is_game_over or not active:
		return
	smart_bombs -= 1
	Globals.smart_bomb_used.emit()
	Audio.play("explosion", 1.0, 0.05)
	for e in get_tree().get_nodes_in_group("enemy"):
		if is_instance_valid(e) and e.has_method("take_damage"):
			e.take_damage(50)

# ─── Throttle (boost / brake) ───────────────────────────────────────────
func _update_throttle(delta: float) -> void:
	var target := cruise_speed
	if _boost_input():
		target = boost_speed
	elif _brake_input():
		target = brake_speed
	current_speed = lerpf(current_speed, target, clampf(throttle_smooth * delta, 0.0, 1.0))

# ─── Dash (skill dodge with brief i-frames) ─────────────────────────────
func _update_dash(delta: float) -> void:
	if _dash_cd > 0.0:
		_dash_cd -= delta
	if _dash_t > 0.0:
		_dash_t -= delta
		if _dash_t <= 0.0:
			_dash_iframes = false

func try_dash() -> void:
	if _dash_cd > 0.0 or not active or Globals.is_game_over:
		return
	_dash_t = dash_time
	_dash_cd = dash_cooldown
	_dash_iframes = true
	Audio.play("powerup", -10.0, 0.25)

func dash_ready() -> bool:
	return _dash_cd <= 0.0

func _boost_input() -> bool:
	if hud and "boost_held" in hud and hud.boost_held:
		return true
	return Input.is_key_pressed(KEY_SHIFT)

func _brake_input() -> bool:
	if hud and "brake_held" in hud and hud.brake_held:
		return true
	return Input.is_key_pressed(KEY_CTRL)

# ─── Steering Input ─────────────────────────────────────────────────────
## Returns raw steer: x = yaw (-1 left .. 1 right), y = pitch (-1 .. 1).
func _read_steer_input() -> Vector2:
	# Touch HUD takes priority when actively steering.
	if hud and hud.has_method("get_steer_vector"):
		var v: Vector2 = hud.get_steer_vector()
		if v.length_squared() > 0.01:
			return v.limit_length(1.0)
	# Keyboard / gamepad fallback.
	var yaw := Input.get_axis("move_left", "move_right")
	var pitch := Input.get_axis("move_back", "move_forward")
	return Vector2(yaw, pitch).limit_length(1.0)

func _update_steer(delta: float) -> void:
	var raw := _read_steer_input()
	_steer = _steer.lerp(raw, clampf(turn_smooth * delta, 0.0, 1.0))

# ─── Flight ─────────────────────────────────────────────────────────────
func _fly(delta: float) -> void:
	var pitch_sign := -1.0 if invert_pitch else 1.0

	# Rotate heading: yaw about local up, pitch about local right.
	rotate_object_local(Vector3.UP, -_steer.x * yaw_rate * delta)
	rotate_object_local(Vector3.RIGHT, _steer.y * pitch_rate * delta * pitch_sign)
	# Keep the basis clean so accumulated rotations never skew the ship.
	transform.basis = transform.basis.orthonormalized()

	# Soft arena containment — TURN the nose back toward center instead of
	# cancelling velocity (which would dead-stop a ship flying straight out).
	var outside := Globals.distance_outside_arena(global_position)
	if outside > 0.0:
		var to_center := Globals.pull_back_dir(global_position)
		var fwd := -transform.basis.z
		var angle := fwd.angle_to(to_center)
		if angle > 0.001:
			var axis := fwd.cross(to_center)
			if axis.length_squared() < 0.0001:
				axis = transform.basis.y   # antipodal: pick a sane turn axis
			axis = axis.normalized()
			var turn_amt := minf(angle, clampf(outside / 8.0, 0.25, 1.0) * 2.5 * delta)
			transform.basis = transform.basis.rotated(axis, turn_amt).orthonormalized()

	# Constant forward cruise along the (possibly redirected) nose (-Z).
	var forward := -transform.basis.z
	velocity = forward * (dash_speed if _dash_t > 0.0 else current_speed)
	move_and_slide()

# ─── Banking (visual roll only) ─────────────────────────────────────────
func _bank(delta: float) -> void:
	if mesh_pivot == null:
		return
	var target_roll := -_steer.x * max_bank
	mesh_pivot.rotation.z = lerp_angle(mesh_pivot.rotation.z, target_roll, clampf(bank_smooth * delta, 0.0, 1.0))

# ─── Firing ─────────────────────────────────────────────────────────────
func _is_firing() -> bool:
	if hud and "is_firing" in hud and hud.is_firing:
		return true
	return Input.is_action_pressed("fire")

func _handle_fire() -> void:
	if not _is_firing():
		return
	if not fire_timer.is_stopped():
		return
	# Rapid-fire power-up shortens the interval.
	fire_timer.wait_time = fire_rate * (0.4 if _powerups.has("rapid") else 1.0)
	fire_timer.start()
	_fire()

## Spawn bullets, aimed through the reticle. Spread power-up adds a fan.
func _fire() -> void:
	if muzzle_flash:
		muzzle_flash.light_energy = 4.5
	Audio.play("shoot", -7.0, 0.06)
	var aim_point := _get_aim_point()

	if _powerups.has("spread"):
		var origin: Vector3 = _muzzle_list[0].global_position
		var base := (aim_point - origin).normalized()
		for a in [-0.16, -0.05, 0.05, 0.16]:
			_spawn_bullet(origin, base.rotated(transform.basis.y, a))
	else:
		for m in _muzzle_list:
			_spawn_bullet(m.global_position, (aim_point - m.global_position).normalized())

func _spawn_bullet(origin: Vector3, dir: Vector3) -> void:
	var bullet: Area3D = BulletPool.get_player_bullet()
	if bullet == null:
		return
	bullet.global_position = origin
	bullet.direction = dir
	bullet.speed = bullet_speed
	bullet.damage = bullet_damage
	bullet.reset_lifetime()
	if bullet.has_method("orient_to_direction"):
		bullet.orient_to_direction()

## World point the player is aiming at: a fixed distance down the camera ray
## that passes through the on-screen reticle. No reticle → straight ahead.
func _get_aim_point() -> Vector3:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return global_position - transform.basis.z * aim_distance

	var screen_pos := get_viewport().get_visible_rect().size * 0.5
	if hud and "reticle_position" in hud:
		screen_pos = hud.reticle_position

	var ray_from := cam.project_ray_origin(screen_pos)
	var ray_dir := cam.project_ray_normal(screen_pos)

	# Soft aim-assist: if a drone sits near the aim ray, lock bullets onto it.
	var best: Node3D = null
	var best_ang := aim_assist_cone
	for d in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(d):
			continue
		var to_d: Vector3 = (d.global_position - ray_from)
		if to_d.dot(ray_dir) <= 0.0:
			continue  ## behind the camera
		var ang := ray_dir.angle_to(to_d.normalized())
		if ang < best_ang:
			best_ang = ang
			best = d
	if best != null:
		return best.global_position

	return ray_from + ray_dir * aim_distance

# ─── Damage / Health ────────────────────────────────────────────────────
func take_damage(amount: int = 1) -> void:
	if is_invincible or _dash_iframes or Globals.is_game_over:
		return
	# Shield power-up absorbs the hit entirely.
	if _powerups.has("shield"):
		Audio.play("hit", -5.0)
		return
	health -= amount
	Globals.player_hit.emit()
	Globals.reset_combo()
	Audio.play("player_hit", -3.0)
	_flash_damage()

	if health <= 0:
		_die()
	else:
		is_invincible = true
		inv_timer.start()

func _on_invincibility_end() -> void:
	is_invincible = false

func _flash_damage() -> void:
	if mesh_pivot == null:
		return
	# Scale pulse — safe for 3D nodes (no modulate on 3D).
	var tw := create_tween()
	tw.tween_property(mesh_pivot, "scale", Vector3(0.8, 0.8, 0.8), 0.05)
	tw.tween_property(mesh_pivot, "scale", Vector3.ONE, 0.15)

func _die() -> void:
	Globals.is_game_over = true
	Globals.player_destroyed.emit()
	hide()
	set_physics_process(false)

# ─── Ship selection (model + stats) ──────────────────────────────────────
## Swap in the player's chosen Kenney ship model and apply its stat modifiers.
func _apply_selected_ship() -> void:
	var ship: Dictionary = ShipRoster.get_ship(Save.selected_ship)
	# Stat modifiers.
	cruise_speed *= float(ship.get("speed", 1.0))
	boost_speed  *= float(ship.get("speed", 1.0))
	fire_rate    *= float(ship.get("fire", 1.0))
	max_health   += int(ship.get("health", 0))
	bullet_damage += int(ship.get("damage", 0))

	# Visual model — always the Intergalactic spaceship, runtime-loaded and
	# auto-fitted so it can't end up giant/tiny/off-centre. Free any default or
	# previously-installed model first.
	for n in ["SpaceshipModel", "ShipModel"]:
		var old := mesh_pivot.get_node_or_null(n)
		if old:
			old.free()
	var model: Node3D = ModelLib.instance_model(PLAYER_MODEL)
	if model == null:
		return
	model.name = "ShipModel"
	mesh_pivot.add_child(model)
	model.transform = Transform3D.IDENTITY
	ModelLib.fit(model, model_target_len)
	model.rotate_y(model_yaw)
	# Tint the engine accent light to the ship colour.
	if muzzle_flash:
		muzzle_flash.light_color = ship.get("accent", Color.WHITE)

## Auto-centre + uniform-scale any instanced GLB to a target length so every
## ship sits correctly on the pivot regardless of how it was authored.
func _fit_model(model: Node3D, target_len: float) -> void:
	var inv := model.global_transform.affine_inverse()
	var merged := AABB()
	var first := true
	for mi in _all_mesh_instances(model):
		var rel: Transform3D = inv * mi.global_transform
		var a: AABB = rel * mi.get_aabb()
		if first:
			merged = a
			first = false
		else:
			merged = merged.merge(a)
	if first or merged.size == Vector3.ZERO:
		return
	var longest := maxf(merged.size.x, maxf(merged.size.y, merged.size.z))
	var s := target_len / maxf(longest, 0.001)
	model.scale = Vector3(s, s, s)
	model.position = -merged.get_center() * s

func _all_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_mesh_instances(c))
	return out

# ─── Helpers ────────────────────────────────────────────────────────────
func _collect_muzzles() -> void:
	_muzzle_list.clear()
	if muzzles == null:
		return
	for c in muzzles.get_children():
		if c is Marker3D:
			_muzzle_list.append(c)
	# Fallback so the ship can always shoot even if no markers were placed.
	if _muzzle_list.is_empty():
		var fallback := Marker3D.new()
		mesh_pivot.add_child(fallback)
		fallback.position = Vector3(0, 0, -2.0)
		_muzzle_list.append(fallback)
