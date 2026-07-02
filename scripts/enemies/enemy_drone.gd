## Zeta Legacy — Alien Drone (combat AI)
## Designed to be KILLABLE. Instead of orbiting behind the player (where it can
## never be shot), a drone sets up AHEAD of the player, makes a firing attack
## pass straight at them, whooshes by, then loops back to the front for another
## pass. The player keeps seeing drones in their forward arc.
extends Area3D

# ─── States / Types ─────────────────────────────────────────────────────
enum State { SETUP, ATTACK, PASS }
enum Arche { GUNNER, RUSHER, TANK }
@export var archetype: int = Arche.GUNNER

## All aliens use the animated UFO model (runtime-loaded via ModelLib — the
## editor importer is broken on this device).
const UFO_MODEL := "res://models/enemies/ufo.glb"
var _model_scale: float = 1.0
var _ufo: Node3D = null      ## the UFO model; spun cheaply (no baked AnimationPlayer)

# ─── Tuning ─────────────────────────────────────────────────────────────
@export_group("Movement")
@export var move_speed: float = 12.0
@export var turn_speed: float = 2.8
@export var engage_distance: float = 26.0    ## how far ahead of the player it sets up
@export var pass_distance: float = 8.0       ## this close → whoosh past
@export var catchup_sprint: float = 1.4

@export_group("Combat")
@export var health: int = 3
@export var score_value: int = 100
@export var touch_damage: int = 1
@export var can_shoot: bool = true
@export var fire_cooldown: float = 1.3
@export var bullet_speed: float = 32.0

# ─── Nodes ──────────────────────────────────────────────────────────────
@onready var model_pivot: Node3D = $ModelPivot
@onready var fire_timer: Timer   = $FireTimer

# ─── State ──────────────────────────────────────────────────────────────
var _state: int = State.SETUP
var _state_time: float = 0.0
var _heading: Vector3 = Vector3.FORWARD
var _spread: Vector3 = Vector3.ZERO          ## lateral offset so drones fan out
var _wobble_seed: float = 0.0
var _can_fire: bool = true

## Mission Mode: when set to an allied unit, the drone hunts and shoots THAT
## instead of the player (defend/escort missions). Default null = chase player,
## so Arcade mode is completely unaffected.
var attack_target: Node3D = null

func _ready() -> void:
	add_to_group("enemy")
	_apply_archetype()
	_install_ufo()
	_wobble_seed = randf() * TAU
	_heading = -global_transform.basis.z
	_new_spread()

	fire_timer.wait_time = fire_cooldown
	fire_timer.one_shot = true
	if not fire_timer.timeout.is_connected(_on_fire_ready):
		fire_timer.timeout.connect(_on_fire_ready)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

## Configure stats, size and colour-coded core for this drone's archetype.
## Called after the spawner has applied wave-scaled base stats.
func _apply_archetype() -> void:
	var core_col := Color(0.3, 0.9, 1.0)   # GUNNER cyan
	var model_scale := 1.0
	match archetype:
		Arche.RUSHER:
			move_speed *= 1.8
			health = 1
			can_shoot = false
			score_value = 80
			touch_damage = 1
			model_scale = 0.7
			core_col = Color(1.0, 0.5, 0.1)   # orange
		Arche.TANK:
			move_speed *= 0.6
			health = maxi(health, 1) * 3
			fire_cooldown = 1.8
			score_value = 250
			touch_damage = 2
			model_scale = 1.5
			core_col = Color(1.0, 0.3, 1.0)   # magenta
	_model_scale = model_scale
	# Core glow keeps the archetype colour-coding (cyan/orange/magenta), shrunk
	# so it reads as an inner light under the UFO shell.
	var core := model_pivot.get_node_or_null("Core") as MeshInstance3D
	if core:
		core.scale = Vector3.ONE * 0.5 * model_scale
		var m := core.get_surface_override_material(0)
		if m is StandardMaterial3D:
			m.albedo_color = core_col
			m.emission = core_col

## Replace the placeholder drone mesh with the animated UFO (rings spinning).
func _install_ufo() -> void:
	if model_pivot == null:
		return
	var old := model_pivot.get_node_or_null("DroneModel")
	if old:
		old.free()
	var ufo: Node3D = ModelLib.instance_model(UFO_MODEL)
	if ufo == null:
		return
	ufo.name = "DroneModel"
	model_pivot.add_child(ufo)
	ufo.transform = Transform3D.IDENTITY
	ModelLib.fit(ufo, 3.4 * _model_scale)
	# NOTE: we deliberately do NOT play the baked AnimationPlayer here — animating
	# ~110 nodes per drone across a swarm is what tanks weak phones. A single
	# cheap rotate_y in _orient_model gives the spinning-UFO look for free.
	_ufo = ufo

func _new_spread() -> void:
	_spread = Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1))
	if _spread == Vector3.ZERO:
		_spread = Vector3.RIGHT
	_spread = _spread.normalized() * randf_range(6.0, 16.0)

func _physics_process(delta: float) -> void:
	if Globals.is_game_over:
		return
	# Resolve who we're hunting: an assigned ally target (mission mode) takes
	# priority, otherwise the player.
	var target: Node3D = null
	if attack_target != null and is_instance_valid(attack_target):
		target = attack_target
	elif Globals.player != null and is_instance_valid(Globals.player):
		target = Globals.player
	if target == null:
		global_position += _heading * move_speed * 0.4 * delta
		return

	var to_player: Vector3 = target.global_position - global_position
	var dist := to_player.length()
	var dir_to_player := to_player / maxf(dist, 0.001)

	_state_time += delta
	var goal := _steer(target, dir_to_player, dist)
	_heading = _heading.slerp(goal, clampf(turn_speed * delta, 0.0, 1.0)).normalized()

	# Sprint to close big gaps so drones don't trail off; commit on a pass.
	var spd := move_speed
	if _state == State.SETUP and dist > engage_distance * 1.6:
		spd = move_speed * catchup_sprint
	elif _state == State.ATTACK:
		spd = move_speed * 1.15
	global_position += _heading * spd * delta

	# Arena containment (guarded against a degenerate zero heading).
	var outside := Globals.distance_outside_arena(global_position)
	if outside > 0.0:
		var pull := Globals.pull_back_dir(global_position)
		var blended := _heading.lerp(pull, clampf(outside / 20.0, 0, 1))
		_heading = blended.normalized() if blended.length_squared() > 0.0001 else pull

	_orient_model(delta)
	_maybe_fire(target, dist)

# ─── State Machine ──────────────────────────────────────────────────────
func _player_forward(player: Node3D) -> Vector3:
	return -player.global_transform.basis.z

func _steer(player: Node3D, dir_to_player: Vector3, dist: float) -> Vector3:
	# Rushers are kamikazes — just bore straight at the player and ram.
	# Drones assigned an ally target also bore straight in (the target has no
	# meaningful "forward" to set up ahead of).
	if archetype == Arche.RUSHER or (attack_target != null and is_instance_valid(attack_target)):
		return dir_to_player

	match _state:
		State.SETUP:
			# Fly to a point ahead of the player so we surface in their view.
			var front: Vector3 = player.global_position + _player_forward(player) * engage_distance + _spread
			var to_front := front - global_position
			var d := to_front.length()
			if d < 8.0:
				_state = State.ATTACK
				_state_time = 0.0
			return to_front.normalized() if d > 0.01 else dir_to_player

		State.ATTACK:
			# Bore straight at the player, firing, then peel into a pass.
			if dist < pass_distance or _state_time > 3.0:
				_state = State.PASS
				_state_time = 0.0
			return dir_to_player

		State.PASS:
			# Keep the current heading briefly (whoosh by), then loop to the front.
			if _state_time > 0.6:
				_state = State.SETUP
				_state_time = 0.0
				_new_spread()
			return _heading

	return dir_to_player

# ─── Model Orientation & Wobble ─────────────────────────────────────────
func _orient_model(delta: float) -> void:
	if model_pivot == null:
		return
	var up := Vector3.UP
	if absf(_heading.dot(up)) > 0.98:
		up = Vector3.RIGHT
	var goal := Transform3D().looking_at(_heading, up)
	var cur := model_pivot.global_transform.basis.orthonormalized()
	model_pivot.global_transform.basis = cur.slerp(goal.basis, clampf(8.0 * delta, 0, 1))
	model_pivot.position.y = sin(_state_time * 4.0 + _wobble_seed) * 0.12
	if _ufo:
		_ufo.rotate_y(delta * 2.2)        # cheap "spinning UFO" look (no AnimationPlayer)

# ─── Shooting ───────────────────────────────────────────────────────────
func _maybe_fire(player: Node3D, dist: float) -> void:
	if not can_shoot or not _can_fire or _state == State.PASS:
		return
	if dist > engage_distance * 1.5:
		return
	_fire_at(player)
	if randf() < 0.5:
		Audio.play("enemy_shoot", -16.0, 0.1)   ## thinned out so a swarm isn't noisy
	_can_fire = false
	fire_timer.start()

func _fire_at(player: Node3D) -> void:
	var bullet: Area3D = BulletPool.get_enemy_bullet()
	if bullet == null:
		return
	var origin := global_position + dir_to(player) * 1.6
	bullet.global_position = origin
	var aim := player.global_position
	if "velocity" in player:
		aim += player.velocity * 0.2
	bullet.direction = (aim - origin).normalized()
	bullet.speed = bullet_speed
	bullet.damage = touch_damage
	bullet.reset_lifetime()
	if bullet.has_method("orient_to_direction"):
		bullet.orient_to_direction()

func dir_to(node: Node3D) -> Vector3:
	return (node.global_position - global_position).normalized()

func _on_fire_ready() -> void:
	_can_fire = true

# ─── Collisions ─────────────────────────────────────────────────────────
func _on_body_entered(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(touch_damage)
		_explode()

# ─── Damage / Death ─────────────────────────────────────────────────────
func take_damage(amount: int) -> void:
	health -= amount
	_flash_hit()
	if health <= 0:
		_explode()
	else:
		Audio.play("hit", -9.0, 0.1)

func _flash_hit() -> void:
	if model_pivot == null:
		return
	var tw := create_tween()
	tw.tween_property(model_pivot, "scale", Vector3(1.25, 1.25, 1.25), 0.04)
	tw.tween_property(model_pivot, "scale", Vector3.ONE, 0.12)

func _explode() -> void:
	Globals.register_kill(score_value, global_position)
	Audio.play("explosion", -3.0, 0.08)
	_spawn_explosion()
	_maybe_drop_powerup()
	queue_free()

## ~17% chance to drop a power-up; utility kinds are commoner than weapons.
func _maybe_drop_powerup() -> void:
	if randf() > 0.17:
		return
	var roll := randf()
	var kind := "health"
	if roll > 0.78:
		kind = "spread"
	elif roll > 0.55:
		kind = "rapid"
	elif roll > 0.28:
		kind = "shield"
	var scene: PackedScene = load("res://scenes/fx/powerup.tscn")
	if scene == null:
		return
	var pu: Area3D = scene.instantiate()
	pu.kind = kind
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	host.add_child(pu)
	pu.global_position = global_position

func _spawn_explosion() -> void:
	var scene: PackedScene = load("res://scenes/fx/explosion.tscn")
	if scene == null:
		return
	var boom: Node3D = scene.instantiate()
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	host.add_child(boom)
	boom.global_position = global_position
