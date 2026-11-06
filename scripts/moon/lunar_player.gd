## Zeta Legacy — Lunar Player CharacterBody3D
## Tuned for lunar surface traversal:
## - Low lunar gravity (1.62 m/s² realistic feel).
## - exported injury_speed_multiplier for suit damage and stamina mechanics.
## - can_climb = false (rigid lunar EVA suit forbids direct vertical climbing).
## - Footstep dust particle emissions during motion.
## - Responsive camera-relative movement.
class_name LunarPlayer
extends CharacterBody3D

@export var move_speed: float = 6.8
@export var lunar_gravity: float = 1.62
@export var jump_impulse: float = 4.2
@export var turn_speed: float = 10.0
@export var injury_speed_multiplier: float = 1.0  ## Exported hook: scales move speed if injured (e.g. 0.6)
@export var can_climb: bool = false               ## Lunar EVA suit cannot climb steep rock walls

@onready var mesh_pivot: Node3D = $MeshPivot
@onready var dust_particles: GPUParticles3D = $DustPuff

var active: bool = true
var _step_timer: float = 0.0

func _ready() -> void:
	add_to_group("player")
	Globals.player = self

func _physics_process(delta: float) -> void:
	if not active:
		velocity = Vector3.ZERO
		return

	# 1. Apply low lunar gravity
	if not is_on_floor():
		velocity.y -= lunar_gravity * delta * 2.5 # Slight gameplay snappy curve over pure 1.62
	else:
		if velocity.y < 0.0:
			velocity.y = 0.0

	# 2. Gather user input (move_forward, move_back, move_left, move_right)
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("move_forward"):
		input_dir.y += 1.0
	if Input.is_action_pressed("move_back"):
		input_dir.y -= 1.0
	if Input.is_action_pressed("move_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("move_right"):
		input_dir.x += 1.0

	# 3. Determine camera-relative movement vector
	var cam := get_viewport().get_camera_3d()
	var cam_fwd := Vector3.FORWARD
	var cam_right := Vector3.RIGHT
	if cam:
		cam_fwd = -cam.global_transform.basis.z
		cam_fwd.y = 0.0
		if cam_fwd.length_squared() > 0.001:
			cam_fwd = cam_fwd.normalized()
		cam_right = cam.global_transform.basis.x
		cam_right.y = 0.0
		if cam_right.length_squared() > 0.001:
			cam_right = cam_right.normalized()

	var move_vector := (cam_fwd * input_dir.y + cam_right * input_dir.x)
	if move_vector.length() > 1.0:
		move_vector = move_vector.normalized()

	# 4. Apply speed with injury multiplier
	var target_speed := move_speed * injury_speed_multiplier
	velocity.x = move_vector.x * target_speed
	velocity.z = move_vector.z * target_speed

	# 5. Lunar Jump
	if Input.is_action_just_pressed("fire") and is_on_floor():
		velocity.y = jump_impulse

	move_and_slide()

	# 6. Smooth Mesh Pivot Rotation
	if move_vector.length_squared() > 0.01 and mesh_pivot:
		var target_look := Basis.looking_at(move_vector, Vector3.UP)
		mesh_pivot.basis = mesh_pivot.basis.slerp(target_look, clampf(turn_speed * delta, 0.0, 1.0))

	# 7. Footstep regolith dust particles
	var horiz_speed := Vector2(velocity.x, velocity.z).length()
	if is_on_floor() and horiz_speed > 0.5:
		_step_timer += delta * (horiz_speed / move_speed)
		if _step_timer >= 0.35:
			_step_timer = 0.0
			if dust_particles:
				dust_particles.restart()
				dust_particles.emitting = true
