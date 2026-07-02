## Zeta Legacy — Space Bike (Mars surface vehicle)
## A hover-bike Alina rides to search the Martian plain for the crashed satellite.
## Arcade driving: throttle accelerates along the bike's nose, steer yaws it, it
## hovers just above the flat ground and drifts with momentum. Input comes from
## the FootHUD (move.y = throttle, move.x = steer). Camera-independent heading.
##
## The bike model is runtime-loaded from models/mars/space_bike.glb if present
## (the editor importer is broken on this device), else a procedural placeholder
## is built — drop a CC0 bike there to swap it. See models/mars/README.txt.
extends CharacterBody3D

const SWAP_MODEL := "res://models/mars/space_bike.glb"

@export var max_speed: float = 30.0
@export var accel: float = 22.0
@export var reverse_accel: float = 12.0
@export var friction: float = 10.0
@export var steer_rate: float = 2.0          ## rad/sec yaw at speed
@export var gravity: float = 16.0
@export var hover_height: float = 0.9
@export var lean_max: float = 0.5

var hud: Node = null
var active: bool = false

var _model_pivot: Node3D = null
var _accent := Color(1.0, 0.55, 0.25)

func _ready() -> void:
	add_to_group("player")
	Globals.player = self
	motion_mode = CharacterBody3D.MOTION_MODE_GROUNDED
	up_direction = Vector3.UP
	_build_collision()
	_model_pivot = Node3D.new()
	add_child(_model_pivot)
	_install_model()

func current_speed_xz() -> float:
	return Vector2(velocity.x, velocity.z).length()

# ─── Build ───────────────────────────────────────────────────────────────────
func _build_collision() -> void:
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(1.2, 1.1, 3.0)
	col.shape = box
	col.position = Vector3(0, 0.7, 0)
	add_child(col)

func _install_model() -> void:
	if FileAccess.file_exists(SWAP_MODEL):
		var m: Node3D = ModelLib.instance_model(SWAP_MODEL)
		if m != null:
			_model_pivot.add_child(m)
			m.transform = Transform3D.IDENTITY
			ModelLib.fit(m, 3.2)
			m.position.y = 0.6
			m.rotate_y(PI)        # most models face +Z; point the nose to −Z
			return
	_build_procedural_bike()

## Sleek procedural hover-bike: nose cone, body, seat, two side thruster pods,
## and a glowing underside hover-jet.
func _build_procedural_bike() -> void:
	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.30, 0.32, 0.38)
	metal.metallic = 0.7
	metal.roughness = 0.4
	var glow := StandardMaterial3D.new()
	glow.albedo_color = _accent
	glow.emission_enabled = true
	glow.emission = _accent
	glow.emission_energy_multiplier = 2.4

	# Main body.
	var body := MeshInstance3D.new()
	var bm := BoxMesh.new(); bm.size = Vector3(0.7, 0.45, 2.4)
	body.mesh = bm; body.material_override = metal
	body.position = Vector3(0, 0.7, 0)
	_model_pivot.add_child(body)

	# Nose cone (points −Z, forward).
	var nose := MeshInstance3D.new()
	var pm := PrismMesh.new(); pm.size = Vector3(0.7, 0.45, 1.1)
	nose.mesh = pm
	nose.rotation = Vector3(deg_to_rad(-90), 0, 0)
	nose.position = Vector3(0, 0.7, -1.6)
	nose.material_override = metal
	_model_pivot.add_child(nose)

	# Handlebars / cockpit accent.
	var bar := MeshInstance3D.new()
	var cm := BoxMesh.new(); cm.size = Vector3(1.0, 0.1, 0.2)
	bar.mesh = cm; bar.material_override = glow
	bar.position = Vector3(0, 0.95, -0.7)
	_model_pivot.add_child(bar)

	# Side thruster pods.
	for s in [-1.0, 1.0]:
		var pod := MeshInstance3D.new()
		var pmm := CapsuleMesh.new(); pmm.radius = 0.18; pmm.height = 1.6
		pod.mesh = pmm
		pod.rotation = Vector3(deg_to_rad(90), 0, 0)
		pod.position = Vector3(s * 0.55, 0.6, 0.2)
		pod.material_override = metal
		_model_pivot.add_child(pod)
		var jet := MeshInstance3D.new()
		var jm := CylinderMesh.new(); jm.top_radius = 0.12; jm.bottom_radius = 0.2; jm.height = 0.25
		jet.mesh = jm
		jet.rotation = Vector3(deg_to_rad(90), 0, 0)
		jet.position = Vector3(s * 0.55, 0.6, 1.05)
		jet.material_override = glow
		_model_pivot.add_child(jet)

	# Glowing hover-jet underside light.
	var light := OmniLight3D.new()
	light.light_color = _accent
	light.light_energy = 1.6
	light.omni_range = 4.0
	light.position = Vector3(0, 0.2, 0)
	_model_pivot.add_child(light)

# ─── Drive ───────────────────────────────────────────────────────────────────
func _physics_process(delta: float) -> void:
	# Gravity + hover so the bike sits just above the ground.
	if not is_on_floor():
		velocity.y -= gravity * delta
	elif velocity.y < 0.0:
		velocity.y = 0.0

	if not active:
		# Coast to a stop while frozen (e.g. during briefing).
		var h0 := Vector3(velocity.x, 0, velocity.z).move_toward(Vector3.ZERO, friction * 2.0 * delta)
		velocity.x = h0.x; velocity.z = h0.z
		move_and_slide()
		return

	var mv: Vector2 = Vector2.ZERO
	if hud and hud.has_method("get_move_vector"):
		mv = hud.get_move_vector()

	var horiz := Vector3(velocity.x, 0.0, velocity.z)
	var speed := horiz.length()

	# Steering — scaled by how fast we're going (can't turn in place).
	if absf(mv.x) > 0.01 and speed > 0.6:
		var turn := -mv.x * steer_rate * delta * clampf(speed / 6.0, 0.3, 1.0)
		rotate_y(turn)
		horiz = horiz.rotated(Vector3.UP, turn)   # rotate momentum with the bike

	var fwd := -global_transform.basis.z
	if mv.y > 0.01:
		horiz += fwd * accel * mv.y * delta
	elif mv.y < -0.01:
		horiz += fwd * reverse_accel * mv.y * delta
	else:
		horiz = horiz.move_toward(Vector3.ZERO, friction * delta)
	horiz = horiz.limit_length(max_speed)

	velocity.x = horiz.x
	velocity.z = horiz.z
	move_and_slide()

	# Visual lean into the turn.
	if _model_pivot:
		var target_lean := -mv.x * lean_max * clampf(speed / max_speed, 0.0, 1.0)
		_model_pivot.rotation.z = lerp_angle(_model_pivot.rotation.z, target_lean, clampf(8.0 * delta, 0, 1))
