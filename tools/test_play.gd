extends SceneTree

var _frames := 0

func _initialize() -> void:
	OS.set_environment("ZETA_AUTOSTART", "1")
	var ps: PackedScene = load("res://scenes/main.tscn")
	var main: Node = ps.instantiate()
	get_root().add_child(main)

func _process(_delta: float) -> bool:
	_frames += 1
	if _frames == 180 or _frames == 420 or _frames == 650:
		var g: Node = get_root().get_node_or_null("Globals")
		var wave: int = g.current_wave if g else -1
		var alive: int = g.enemies_alive if g else -1
		var score: int = g.score if g else -1

		var p: Node3D = get_first_node_in_group("player") as Node3D
		var ppos := "nil"
		var pactive := "?"
		var phealth := -1
		if p and is_instance_valid(p):
			ppos = str(p.global_position.snapped(Vector3.ONE * 0.1))
			pactive = str(p.active)
			phealth = p.health

		var drones := 0
		for n in get_nodes_in_group("enemy"):
			if is_instance_valid(n): drones += 1

		print("@%d  wave=%d  alive=%d  drones_in_tree=%d  score=%d  player[active=%s hp=%d pos=%s]" % [
			_frames, wave, alive, drones, score, pactive, phealth, ppos])
	if _frames == 90:
		var pd := get_first_node_in_group("player")
		if pd and pd.has_method("try_dash"):
			pd.try_dash(); print("dash triggered")
	if _frames == 230:
		var pb := get_first_node_in_group("player")
		if pb and pb.has_method("use_smart_bomb"):
			pb.use_smart_bomb(); print("bomb triggered")
	if _frames >= 660:
		quit()
	return false
