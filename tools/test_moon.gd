extends SceneTree

var _f := 0
var _main: Node
var G: Node

func _initialize() -> void:
	_main = load("res://scenes/story/moon_surface.tscn").instantiate()
	get_root().add_child(_main)

func _G() -> Node:
	if G == null:
		G = get_root().get_node_or_null("Globals")
	return G

func _process(_d: float) -> bool:
	_f += 1
	var alina := get_first_node_in_group("player")
	var enemies := get_nodes_in_group("enemy")

	if _f == 60:
		print("alina_present=%s  active=%s  enemies_spawned=%d" % [
			alina != null, (alina != null and alina.active), enemies.size()])
		print("energy=%.0f oxygen=%.0f health=%d" % [
			alina.energy, alina.oxygen, alina.health])

	if _f == 90 and enemies.size() > 0:
		# Kill one drone to exercise win/score path.
		enemies[0].take_damage(999)
		print("killed one drone -> score=%d" % _G().score)

	if _f == 120 and alina:
		# Test shield blocks damage.
		alina.shield_active = true
		var hp_before: int = alina.health
		alina.take_damage(3)
		print("shield_block: hp %d -> %d (should be equal)" % [hp_before, alina.health])
		alina.shield_active = false

	if _f == 150 and alina:
		var hp_before: int = alina.health
		alina.take_damage(2)
		print("normal_damage: hp %d -> %d (should drop)" % [hp_before, alina.health])

	if _f == 180:
		print("final: enemies_alive=%d score=%d game_over=%s" % [
			get_nodes_in_group("enemy").size(), _G().score, _G().is_game_over])
		quit()
	return false
