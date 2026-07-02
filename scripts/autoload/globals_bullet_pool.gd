## Zeta Legacy — Bullet Object Pool
## Pre-allocates bullet nodes to avoid runtime instantiation cost.
## Attach to the same autoload Globals node OR use as a child of the main scene.
extends Node

const MAX_PLAYER_BULLETS := 60
const MAX_ENEMY_BULLETS := 40

var _player_bullet_scene: PackedScene = preload("res://scenes/projectiles/player_bullet.tscn")
var _enemy_bullet_scene: PackedScene = preload("res://scenes/projectiles/enemy_bullet.tscn")

var _player_pool: Array[Area3D] = []
var _enemy_pool: Array[Area3D] = []

const SLEEP_POS := Vector3(99999, 99999, 99999)

func _ready() -> void:
	# Pre-warm pools
	for i in MAX_PLAYER_BULLETS:
		_player_pool.append(_make_bullet(_player_bullet_scene))
	for i in MAX_ENEMY_BULLETS:
		_enemy_pool.append(_make_bullet(_enemy_bullet_scene))

func _make_bullet(scene: PackedScene) -> Area3D:
	var b: Area3D = scene.instantiate()
	add_child(b)
	_sleep(b)
	return b

func _wake(b: Area3D) -> void:
	b.visible = true
	b.set_process(true)
	b.set_physics_process(true)
	# Deferred: toggling monitoring is illegal mid-collision-signal, and using
	# set_deferred in both wake/sleep keeps the ordering race-free.
	b.set_deferred("monitoring", true)
	b.set_deferred("monitorable", true)

func _sleep(b: Area3D) -> void:
	b.visible = false
	b.set_process(false)
	b.set_physics_process(false)
	# Teleport away immediately (legal in a signal) so it can't hit again, and
	# defer the monitoring toggle so it's safe when called from a hit callback.
	b.global_position = SLEEP_POS
	b.set_deferred("monitoring", false)
	b.set_deferred("monitorable", false)

## Get an inactive bullet from the player pool. Returns null if pool exhausted.
func get_player_bullet() -> Area3D:
	for b in _player_pool:
		if not b.visible:
			_wake(b)
			return b
	return null

## Get an inactive bullet from the enemy pool.
func get_enemy_bullet() -> Area3D:
	for b in _enemy_pool:
		if not b.visible:
			_wake(b)
			return b
	return null

## Return a bullet to its pool (called by projectile.gd when off-screen).
func return_bullet(bullet: Area3D) -> void:
	_sleep(bullet)
