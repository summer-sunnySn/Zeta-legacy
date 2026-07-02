## Zeta Legacy — Cinematic Chase Camera Rig
## A standalone rig (NOT a child of the ship) that smoothly trails the player.
## The ship can snap-turn instantly while the camera lazily catches up, which
## gives the third-person dogfight its movie feel and avoids 1:1 motion sickness.
extends Node3D

# ─── Tuning ─────────────────────────────────────────────────────────────
@export var target_path: NodePath               ## optional; else uses Globals.player
@export var follow_distance: float = 11.0        ## how far behind the ship
@export var follow_height: float = 3.5           ## how far above the ship line
@export var look_ahead: float = 8.0              ## aim point ahead of the nose
@export var position_smooth: float = 5.0         ## lower = lazier / more cinematic
@export var rotation_smooth: float = 7.0
@export var speed_kick: float = 0.06             ## extra pull-back at speed (FOV/dolly)
@export var base_fov: float = 62.0
@export var boost_fov: float = 72.0

# ─── Nodes ──────────────────────────────────────────────────────────────
@onready var camera: Camera3D = $Camera3D

# ─── State ──────────────────────────────────────────────────────────────
@export var shake_decay: float = 5.0
var _target: Node3D = null
var _initialised: bool = false
var _shake: float = 0.0

func _ready() -> void:
	if camera:
		camera.fov = base_fov
		camera.current = true
	Globals.player_hit.connect(func(): add_shake(0.5))
	Globals.enemy_destroyed.connect(_on_enemy_destroyed)

func add_shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 1.2)

func _on_enemy_destroyed(pos: Vector3) -> void:
	var p := Globals.player
	if p == null or not is_instance_valid(p):
		return
	# Closer kills shake harder.
	var d := p.global_position.distance_to(pos)
	add_shake(clampf(remap(d, 0.0, 45.0, 0.55, 0.0), 0.0, 0.55))

func _resolve_target() -> Node3D:
	if target_path != NodePath() and has_node(target_path):
		return get_node(target_path)
	return Globals.player

func _physics_process(delta: float) -> void:
	if _target == null or not is_instance_valid(_target):
		_target = _resolve_target()
		if _target == null:
			return

	var basis := _target.global_transform.basis
	var forward := -basis.z
	var up := basis.y

	# Desired rig position: behind and above the ship along its own basis.
	var desired_pos := _target.global_position \
		- forward * follow_distance \
		+ up * follow_height

	# On the first valid frame, snap so we don't sweep in from the origin.
	if not _initialised:
		global_position = desired_pos
		_initialised = true
	else:
		var t := clampf(position_smooth * delta, 0.0, 1.0)
		global_position = global_position.lerp(desired_pos, t)

	# Look at a point ahead of the ship for lead-room, smoothed via the camera.
	var look_target := _target.global_position + forward * look_ahead
	_smooth_look_at(look_target, up, delta)

	# Subtle speed feedback through FOV.
	if camera:
		var want_fov := base_fov
		if "current_speed" in _target and "boost_speed" in _target:
			var spd: float = _target.current_speed
			if spd > _target.cruise_speed + 0.5:
				want_fov = boost_fov
		camera.fov = lerpf(camera.fov, want_fov, clampf(speed_kick * 60.0 * delta, 0.0, 1.0))

		# Screen shake — jitter the camera's local offset, then decay.
		if _shake > 0.001:
			camera.position = Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.5
			_shake = move_toward(_shake, 0.0, shake_decay * delta)
		else:
			camera.position = Vector3.ZERO

func _smooth_look_at(look_target: Vector3, up: Vector3, delta: float) -> void:
	var to_target := look_target - global_position
	if to_target.length_squared() < 0.0001:
		return
	# Build the goal orientation, then slerp the rig's basis toward it.
	var goal := Transform3D().looking_at(to_target, up)
	var t := clampf(rotation_smooth * delta, 0.0, 1.0)
	global_transform.basis = global_transform.basis.slerp(goal.basis, t).orthonormalized()
