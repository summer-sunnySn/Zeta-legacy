## Zeta Legacy — Floating Origin System
## Keeps the active world coordinate space centered around the player or camera.
## In large-scale space environments, standard 32-bit float precision degrades
## beyond ~2,000 to 5,000 meters from the origin (causing jitter, physics wobble,
## and shadow flickering). This node shifts registered world nodes back when
## the tracked target exceeds the shift threshold.
class_name FloatingOrigin
extends Node

signal origin_shifted(offset: Vector3)

## Distance from origin before recentering occurs.
## Set to 2000.0m so normal playable 4km x 4km crater bowl stays in pristine 32-bit float precision
@export var threshold: float = 2000.0

## Target node to keep near (0, 0, 0). Defaults to player in Globals or assigned node.
@export var target: Node3D = null

## World root container whose children (props, markers) get shifted.
@export var world_root: Node3D = null

## Cumulative world offset since scene start (useful for true coordinate tracking).
var total_offset: Vector3 = Vector3.ZERO

func _ready() -> void:
	if target == null and Globals.player != null:
		target = Globals.player

func _physics_process(_delta: float) -> void:
	if target == null:
		if Globals.player != null and is_instance_valid(Globals.player):
			target = Globals.player
		else:
			return

	var pos: Vector3 = target.global_position
	# Check horizontal displacement exceeding threshold
	if Vector2(pos.x, pos.z).length_squared() >= threshold * threshold:
		recenter_around(pos)

## Shifts the world by -shift_vector so that target lands near Vector3.ZERO.
func recenter_around(target_pos: Vector3) -> void:
	var shift := Vector3(target_pos.x, 0.0, target_pos.z)
	if shift.length_squared() < 0.01:
		return

	total_offset += shift

	# 1. Shift player and any tracked dynamic entities
	if target and is_instance_valid(target):
		target.global_position -= shift

	# 2. Shift world root or its children (except static procedural world generators like Terrain which listen to origin_shifted)
	if world_root and is_instance_valid(world_root):
		for child in world_root.get_children():
			if child is Node3D and child != target and not (child is LunarTerrain):
				child.global_position -= shift

	# 3. Notify chunk managers, particles, and markers to compensate
	origin_shifted.emit(shift)
