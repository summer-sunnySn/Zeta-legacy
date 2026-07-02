## Zeta Legacy — Alien Bomber (Mission Mode: "intercept")
## A heavy, slow-ish dropship that ignores the player and dives straight for a
## ground target to seed the gas. The player must SHOOT IT DOWN before it lands.
## In group "enemy" so the player's bullets (and station fire) damage it via the
## existing projectile.gd logic. Does not shoot back — the threat is the timer.
extends Area3D

signal shot_down(bomber)     ## destroyed by the player
signal landed(bomber)        ## reached the ground = city takes damage

var health: int = 5
var move_speed: float = 14.0
var score_value: int = 150
var target_point: Vector3 = Vector3.ZERO
var accent: Color = Color(1.0, 0.45, 0.25)

const ARRIVE_RADIUS := 5.0
const ENEMY_LAYER := 2

var _done: bool = false
var _pivot: Node3D = null

func _ready() -> void:
	add_to_group("enemy")
	collision_layer = ENEMY_LAYER       # player bullets (mask 2) hit us
	collision_mask = 0
	monitorable = true
	_build_model()
	var col := CollisionShape3D.new()
	var sh := SphereShape3D.new()
	sh.radius = 2.6
	col.shape = sh
	add_child(col)

func _build_model() -> void:
	_pivot = Node3D.new()
	add_child(_pivot)
	# Bulky hull.
	var hull := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(3.4, 1.6, 4.4)
	hull.mesh = hb
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.22, 0.12, 0.12)
	mat.metallic = 0.5
	mat.roughness = 0.5
	hull.material_override = mat
	_pivot.add_child(hull)
	# Glowing payload underside — the gas canister.
	var pod := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 1.1
	sm.height = 2.2
	pod.mesh = sm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = accent
	gmat.emission_enabled = true
	gmat.emission = accent
	gmat.emission_energy_multiplier = 3.0
	pod.material_override = gmat
	pod.position = Vector3(0, -1.2, 0)
	_pivot.add_child(pod)
	var light := OmniLight3D.new()
	light.light_color = accent
	light.light_energy = 1.6
	light.omni_range = 8.0
	_pivot.add_child(light)

func _physics_process(delta: float) -> void:
	if _done or Globals.is_game_over:
		return
	var to_target := target_point - global_position
	var d := to_target.length()
	if d <= ARRIVE_RADIUS:
		_done = true
		landed.emit(self)
		_spawn_explosion()
		queue_free()
		return
	var dir := to_target / maxf(d, 0.001)
	global_position += dir * move_speed * delta
	if _pivot:
		var up := Vector3.UP
		if absf(dir.dot(up)) > 0.98:
			up = Vector3.RIGHT
		_pivot.look_at(_pivot.global_position + dir, up)

func take_damage(amount: int) -> void:
	if _done:
		return
	health -= amount
	_flash()
	if health <= 0:
		_done = true
		Globals.register_kill(score_value, global_position)
		Audio.play("explosion", -3.0, 0.08)
		_spawn_explosion()
		shot_down.emit(self)
		queue_free()
	else:
		Audio.play("hit", -9.0, 0.1)

func _flash() -> void:
	if _pivot == null:
		return
	var tw := create_tween()
	tw.tween_property(_pivot, "scale", Vector3(1.2, 1.2, 1.2), 0.04)
	tw.tween_property(_pivot, "scale", Vector3.ONE, 0.12)

func _spawn_explosion() -> void:
	var scene: PackedScene = load("res://scenes/fx/explosion.tscn")
	if scene == null:
		return
	var boom: Node3D = scene.instantiate()
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	if host:
		host.add_child(boom)
		boom.global_position = global_position
