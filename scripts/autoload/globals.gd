## Zeta Legacy — Global Game State Autoload
## Manages score, wave state, the spherical arena, and shared signals.
extends Node

# ─── Signals ────────────────────────────────────────────────────────────
signal score_changed(new_score: int)
signal wave_started(wave_number: int)
signal wave_cleared(wave_number: int)
signal player_hit
signal player_destroyed
signal enemy_destroyed(position: Vector3)
signal combo_changed(combo: int)
signal smart_bomb_used
signal boss_spawned(boss: Node3D)
signal boss_defeated
signal score_popup(world_pos: Vector3, amount: int)

# ─── State ──────────────────────────────────────────────────────────────
var score: int = 0:
	set(value):
		score = value
		score_changed.emit(score)

var current_wave: int = 0
var enemies_alive: int = 0
var is_game_over: bool = false

# ─── Combo ──────────────────────────────────────────────────────────────
const COMBO_WINDOW := 3.5      ## seconds before the chain resets
const COMBO_MAX := 10
var combo: int = 0
var _combo_time: float = 0.0

## Live reference to the player ship, set by the player on _ready().
## Enemies and the camera read this instead of searching the tree every frame.
var player: Node3D = null
var boss: Node3D = null

## Mission Mode selection (set by planet_select before loading the mission).
## Not cleared by reset() — they carry the choice across the scene change.
var mission_planet: int = 0
var mission_index: int = 0

## Comic cutscene routing (set before loading comic_cutscene.tscn). comic_id
## picks the sequence (see comic_data.gd); comic_next is the scene to load after.
var comic_id: String = ""
var comic_next: String = ""

# ─── Spherical Arena ────────────────────────────────────────────────────
## The playfield is a sphere centred on the world origin. The player flies
## freely inside it; drifting past the edge applies a soft pull-back, and
## projectiles are culled once they leave it.
var arena_center: Vector3 = Vector3.ZERO
var arena_radius: float = 90.0

# ─── Methods ────────────────────────────────────────────────────────────
func reset() -> void:
	score = 0
	current_wave = 0
	enemies_alive = 0
	is_game_over = false
	combo = 0
	_combo_time = 0.0
	_hs_token += 1
	Engine.time_scale = 1.0   # clear any lingering hitstop on restart

func _process(delta: float) -> void:
	if combo > 0 and not is_game_over:
		_combo_time -= delta
		if _combo_time <= 0.0:
			combo = 0
			combo_changed.emit(0)

## Record a kill: grows the combo chain, awards combo-multiplied points.
func register_kill(base_points: int, pos: Vector3) -> void:
	combo = mini(combo + 1, 9999)
	_combo_time = COMBO_WINDOW
	combo_changed.emit(combo)
	var gained := base_points * mini(combo, COMBO_MAX)
	add_score(gained)
	score_popup.emit(pos, gained)
	on_enemy_destroyed(pos)

# ─── Hitstop (brief freeze-frame for impact) ────────────────────────────
var _hs_token: int = 0
func hitstop(scale: float = 0.06, dur: float = 0.08) -> void:
	_hs_token += 1
	var tok := _hs_token
	Engine.time_scale = scale
	# Real-time timer (ignore_time_scale) so it restores even while frozen.
	await get_tree().create_timer(dur, true, false, true).timeout
	if tok == _hs_token:
		Engine.time_scale = 1.0

func reset_combo() -> void:
	if combo > 0:
		combo = 0
		combo_changed.emit(0)

func add_score(points: int) -> void:
	score += points

func on_enemy_spawned() -> void:
	enemies_alive += 1

func on_enemy_destroyed(pos: Vector3) -> void:
	enemies_alive -= 1
	enemy_destroyed.emit(pos)
	if enemies_alive <= 0:
		wave_cleared.emit(current_wave)

# ─── Arena Helpers ──────────────────────────────────────────────────────
## How far outside the arena a point is (0.0 = inside, >0 = past the edge).
func distance_outside_arena(pos: Vector3) -> float:
	var d := arena_center.distance_to(pos) - arena_radius
	return maxf(0.0, d)

## True while a point is within the arena (+ optional margin for culling).
func is_in_arena(pos: Vector3, margin: float = 0.0) -> bool:
	return arena_center.distance_to(pos) <= arena_radius + margin

## Direction that pulls a stray point back toward the arena centre.
func pull_back_dir(pos: Vector3) -> Vector3:
	return (arena_center - pos).normalized()

## A random point on a shell around the player, used to spawn drones so they
## appear from every side rather than a flat wall ahead.
func random_shell_point(center: Vector3, min_dist: float, max_dist: float) -> Vector3:
	var dir := Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-0.6, 0.6),   # bias toward the horizontal plane
		randf_range(-1.0, 1.0)
	).normalized()
	if dir == Vector3.ZERO:
		dir = Vector3.FORWARD
	var dist := randf_range(min_dist, max_dist)
	var point := center + dir * dist
	# Keep spawns inside the arena.
	if not is_in_arena(point):
		point = arena_center + (point - arena_center).normalized() * (arena_radius * 0.9)
	return point
