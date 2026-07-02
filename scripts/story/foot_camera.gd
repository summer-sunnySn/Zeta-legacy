## Zeta Legacy — On-foot Over-the-Shoulder Camera (Spherical Moon)
## Standalone rig (not a child of Alina). The rig node carries the yaw/pitch the
## player drags; Alina reads this rig's basis for camera-relative movement.
## The Camera3D child sits behind + above and looks at the character.
## Works on spherical Moon: rig up aligns with surface normal.
extends Node3D

@export var distance: float = 5.5
@export var height: float = 2.2
@export var look_height: float = 1.5
@export var follow_smooth: float = 12.0
@export var look_sensitivity: float = 0.005
@export var pitch_min: float = -0.55
@export var pitch_max: float = 0.65
@export var shake_decay: float = 5.0

var target: Node3D = null
var hud: Node = null

var yaw: float = 0.0
var pitch: float = -0.12
var _shake: float = 0.0
var _initialised: bool = false

@onready var camera: Camera3D = $Camera3D

func _ready() -> void:
	if camera:
		camera.current = true
	Globals.player_hit.connect(func(): add_shake(0.45))
	Globals.enemy_destroyed.connect(_on_enemy_destroyed)

func add_shake(amount: float) -> void:
	_shake = clampf(maxf(_shake, amount), 0.0, 1.2)

func _on_enemy_destroyed(pos: Vector3) -> void:
	if target == null or not is_instance_valid(target):
		return
	var d := target.global_position.distance_to(pos)
	add_shake(clampf(remap(d, 0.0, 40.0, 0.5, 0.0), 0.0, 0.5))

func _physics_process(delta: float) -> void:
	# Apply right-drag look.
	if hud and hud.has_method("consume_look"):
		var ld: Vector2 = hud.consume_look()
		yaw -= ld.x * look_sensitivity
		pitch = clampf(pitch - ld.y * look_sensitivity, pitch_min, pitch_max)

	if target == null or not is_instance_valid(target):
		return

	# Flat moon ground — up is world-up.
	var n := Vector3.UP
	var pivot := target.global_position + n * look_height
	if not _initialised:
		global_position = pivot
		_initialised = true
	else:
		global_position = global_position.lerp(pivot, clampf(follow_smooth * delta, 0.0, 1.0))

	# A tangent "forward" reference, spun by the player's yaw drag around the up
	# normal. This is the direction the camera looks along (and the rig hands to
	# Alina for camera-relative movement via cam.global_transform.basis).
	var ref := Vector3.FORWARD
	var fwd := ref - n * ref.dot(n)
	if fwd.length_squared() < 0.001:
		fwd = Vector3.RIGHT - n * Vector3.RIGHT.dot(n)
	fwd = fwd.normalized().rotated(n, yaw)
	var right := fwd.cross(n).normalized()

	# Rig faces `fwd` (so -basis.z == fwd) with up == n.
	global_transform.basis = Basis.looking_at(fwd, n)

	if camera:
		# Behind the character and above it, tilted by pitch around the right axis.
		var offset := (-fwd * distance + n * height).rotated(right, pitch)
		var cam_pos := pivot + offset
		if _shake > 0.001:
			cam_pos += Vector3(randf_range(-1, 1), randf_range(-1, 1), randf_range(-1, 1)) * _shake * 0.3
			_shake = move_toward(_shake, 0.0, shake_decay * delta)
		camera.global_position = cam_pos
		camera.look_at(pivot + n * 0.2, n)
