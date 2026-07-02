extends SceneTree

var _f := 0
var _spawner: Node

func _initialize() -> void:
	OS.set_environment("ZETA_AUTOSTART", "1")
	var main: Node = load("res://scenes/main.tscn").instantiate()
	get_root().add_child(main)
	_spawner = main.get_node("EnemySpawner")

func _process(_d: float) -> bool:
	_f += 1
	if _f == 40:
		_spawner._current_wave = 4
		_spawner._start_next_wave()        # -> wave 5 -> boss
		print("forced boss wave")
	if _f == 150:
		var boss := get_first_node_in_group("boss")
		var g := get_root().get_node_or_null("Globals")
		print("boss_in_tree=%s  globals_boss=%s" % [boss != null, g != null and g.boss != null])
		if boss:
			boss.take_damage(15)
			print("boss_hp_after_hit=%d / %d" % [boss.health, boss.max_health])
	if _f == 230:
		var boss := get_first_node_in_group("boss")
		if boss:
			boss.take_damage(999999)       # kill it
		await_free()
	if _f >= 270:
		var g := get_root().get_node_or_null("Globals")
		print("after_kill boss_in_tree=%s  score=%d" % [get_first_node_in_group("boss") != null, g.score])
		quit()
	return false

func await_free() -> void:
	pass
