## Zeta Legacy — Chase Camera (Mars bike)
## Sits behind + above the target's heading and looks ahead of it. Smoothed so
## it swings around naturally as the bike turns. The Camera3D is a child.
extends Node3D

@export var distance: float = 7.5
@export var height: float = 3.2
@export var look_ahead: float = 4.0
@export var pos_smooth: float = 6.0
@export var rot_smooth: float = 5.0

var target: Node3D = null

@onready var camera: Camera3D = $Camera3D

var _initialised: bool = false

func _ready() -> void:
	if camera:
		camera.current = true

func _physics_process(delta: float) -> void:
	if target == null or not is_instance_valid(target):
		return
	var fwd: Vector3 = -target.global_transform.basis.z
	fwd.y = 0.0
	if fwd.length_squared() < 0.001:
		fwd = Vector3.FORWARD
	fwd = fwd.normalized()

	var desired := target.global_position - fwd * distance + Vector3.UP * height
	if not _initialised:
		global_position = desired
		_initialised = true
	else:
		global_position = global_position.lerp(desired, clampf(pos_smooth * delta, 0.0, 1.0))

	if camera:
		var look := target.global_position + fwd * look_ahead + Vector3.UP * 0.8
		var cur := camera.global_transform
		var goal := cur.looking_at(look, Vector3.UP)
		camera.global_transform.basis = cur.basis.slerp(goal.basis, clampf(rot_smooth * delta, 0.0, 1.0))
		camera.global_position = global_position
