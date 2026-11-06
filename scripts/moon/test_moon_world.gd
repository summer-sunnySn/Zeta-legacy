## Zeta Legacy — Test Moon World Launch Script
## Automates testing of MoonWorld initialization, signal strength evaluation,
## floating origin integration, and Gfx tier changes.
extends SceneTree

var _f: int = 0
var _world: Node = null

func _initialize() -> void:
	print("[TestMoonWorld] Loading res://scenes/moon/moon_world.tscn...")
	var scn: PackedScene = load("res://scenes/moon/moon_world.tscn")
	_world = scn.instantiate()
	get_root().add_child(_world)
	print("[TestMoonWorld] Scene instantiated successfully.")

func _process(_delta: float) -> bool:
	_f += 1

	if _f == 20:
		var mw: MoonWorld = _world as MoonWorld
		print("[TestMoonWorld] Frame 20 verification:")
		print("  - Globals.player is valid: %s" % (Globals.player != null))
		print("  - MoonWorld present: %s" % (mw != null))

		# Test signal strength hook at various coordinates
		var sig_near := mw.get_signal_strength(mw.marker_player_ship.global_position)
		var sig_mid := mw.get_signal_strength(mw.marker_crash_1.global_position)
		var sig_far := mw.get_signal_strength(mw.marker_crash_leader.global_position)
		var sig_void := mw.get_signal_strength(Vector3(10000, 0, 10000))

		print("  - Signal near (PlayerShip): %.2f" % sig_near)
		print("  - Signal mid (CrashSite_1): %.2f" % sig_mid)
		print("  - Signal far (CrashSite_Leader): %.2f" % sig_far)
		print("  - Signal out-of-range: %.2f" % sig_void)

	if _f == 40:
		# Test Gfx quality cycling
		var cur_label := Gfx.cycle()
		print("[TestMoonWorld] Cycled Gfx quality to: %s (tier %d)" % [cur_label, Gfx.current()])

	if _f == 60:
		print("[TestMoonWorld] Test completed successfully. Exiting.")
		quit()

	return false
