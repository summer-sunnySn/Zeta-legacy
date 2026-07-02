## Zeta Legacy — Enemy Wave Spawner
## Spawns drones on a 3D shell around the player so the swarm closes in from
## every side — above, below, behind — for a true 360° dogfight. Difficulty
## scales each wave; the next wave starts after the previous one is cleared.
extends Node3D

# ─── Tuning ─────────────────────────────────────────────────────────────
@export var enemy_scene: PackedScene = preload("res://scenes/enemies/enemy_drone.tscn")
@export var boss_scene: PackedScene = preload("res://scenes/enemies/boss.tscn")
@export var spawn_dist_min: float = 34.0      ## inner radius of the spawn shell
@export var spawn_dist_max: float = 52.0      ## outer radius of the spawn shell
@export var time_between_waves: float = 3.0
@export var base_drones: int = 4              ## wave 1 size
@export var drones_per_wave: float = 1.5      ## growth per wave
@export var max_drones: int = 22             ## hard cap for performance
@export var spawn_stagger: float = 0.25       ## delay between individual spawns
@export var health_per_wave: int = 1
@export var speed_per_wave: float = 0.8

# ─── Nodes ──────────────────────────────────────────────────────────────
@onready var wave_timer: Timer = $WaveTimer

# ─── State ──────────────────────────────────────────────────────────────
var _current_wave: int = 0
var _spawning: bool = false
var _pending: int = 0

func _ready() -> void:
	wave_timer.wait_time = time_between_waves
	wave_timer.one_shot = true
	if not wave_timer.timeout.is_connected(_on_wave_timer):
		wave_timer.timeout.connect(_on_wave_timer)
	if not Globals.wave_cleared.is_connected(_on_wave_cleared):
		Globals.wave_cleared.connect(_on_wave_cleared)

func start_spawning() -> void:
	_current_wave = 0
	_start_next_wave()

# ─── Wave Logic ─────────────────────────────────────────────────────────
func _start_next_wave() -> void:
	_current_wave += 1
	Globals.current_wave = _current_wave
	Globals.wave_started.emit(_current_wave)

	# Every 5th wave is a boss fight.
	if _current_wave % 5 == 0:
		_spawn_boss()
	else:
		var count := mini(max_drones, base_drones + int((_current_wave - 1) * drones_per_wave))
		_spawn_wave(count)

func _spawn_boss() -> void:
	_spawning = false
	var boss: Area3D = boss_scene.instantiate()
	boss.max_health = 60 + (int(_current_wave / 5) - 1) * 45
	var center := Globals.player.global_position if Globals.player else Vector3.ZERO
	var fwd := -Globals.player.global_transform.basis.z if Globals.player else Vector3.FORWARD
	add_child(boss)
	boss.global_position = center + fwd * 60.0
	Globals.on_enemy_spawned()

func _spawn_wave(count: int) -> void:
	_spawning = true
	_pending = count
	for i in count:
		_spawn_one(i * spawn_stagger)

## Mix in Rushers and Tanks as waves progress (0=Gunner, 1=Rusher, 2=Tank).
func _pick_archetype() -> int:
	var r := randf()
	if _current_wave >= 3 and r < 0.28:
		return 1   # Rusher
	if _current_wave >= 4 and r > 0.86:
		return 2   # Tank
	return 0       # Gunner

func _spawn_one(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if Globals.is_game_over:
		return

	var center := Globals.player.global_position if Globals.player else Vector3.ZERO
	# Bias spawns toward the player's forward arc so drones appear in view.
	var fwd := -Globals.player.global_transform.basis.z if Globals.player else Vector3.FORWARD
	var dir := (fwd * 1.3 + Vector3(randf_range(-1, 1), randf_range(-0.5, 0.5), randf_range(-1, 1))).normalized()
	if dir == Vector3.ZERO:
		dir = fwd
	var pos := center + dir * randf_range(spawn_dist_min, spawn_dist_max)
	if not Globals.is_in_arena(pos):
		pos = Globals.arena_center + (pos - Globals.arena_center).normalized() * (Globals.arena_radius * 0.9)

	var drone: Area3D = enemy_scene.instantiate()
	# Apply scaled difficulty before adding to tree so _ready() sees final stats.
	drone.archetype = _pick_archetype()
	drone.health = 3 + (_current_wave - 1) * health_per_wave
	drone.move_speed = 13.0 + (_current_wave - 1) * speed_per_wave
	add_child(drone)
	drone.global_position = pos
	# Face roughly toward the player on spawn.
	if Globals.player:
		var look_dir := (Globals.player.global_position - pos).normalized()
		if look_dir != Vector3.ZERO and absf(look_dir.dot(Vector3.UP)) < 0.98:
			drone.look_at(pos + look_dir, Vector3.UP)

	Globals.on_enemy_spawned()
	_pending -= 1
	if _pending <= 0:
		_spawning = false
		# If the player wiped the wave during spawn-in, the earlier
		# wave_cleared was ignored — start the next-wave timer now.
		if Globals.enemies_alive <= 0 and not Globals.is_game_over:
			wave_timer.start()

# ─── Wave Cleared ───────────────────────────────────────────────────────
func _on_wave_cleared(_wave: int) -> void:
	if _spawning:
		return  ## ignore early "cleared" while a wave is still spawning in
	wave_timer.start()

func _on_wave_timer() -> void:
	_start_next_wave()

# ─── Cleanup ────────────────────────────────────────────────────────────
func reset() -> void:
	_current_wave = 0
	_spawning = false
	_pending = 0
	for child in get_children():
		if child.is_in_group("enemy"):
			child.queue_free()
	wave_timer.stop()
