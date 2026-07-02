## Zeta Legacy — Mission Controller
## Runs one prequel mission: reuses the arcade flight engine (player + camera +
## HUD) but drives a specific, hand-authored OBJECTIVE against an anime/real
## planet backdrop, plays a short tap-to-advance briefing first, then resolves
## win/lose and returns to the planet-select.
##
## Earth's redesigned objective types (each a genuinely different mechanic):
##   patrol        — fly through patrol waypoints, then survive the ambush
##   defend_target — keep the ARIA station (real HP bar) alive for the timer
##   escort        — usher civilian shuttles (self-flying, killable) to the gate
##   intercept     — shoot down gas bombers before they crater the city
##   boss          — destroy the carrier, then the campaign-hook reveal
## Legacy types kept so the other planets still run:
##   destroy / defend(survive) / scan / chase / gauntlet
extends Node3D

const MissionData = preload("res://scripts/mission/mission_data.gd")
const AlliedUnit  = preload("res://scripts/mission/allied_unit.gd")
const Bomber      = preload("res://scripts/mission/bomber.gd")
const SELECT_SCENE := "res://scenes/mission/planet_select.tscn"

var _enemy_scene: PackedScene = preload("res://scenes/enemies/enemy_drone.tscn")
var _boss_scene: PackedScene = preload("res://scenes/enemies/boss.tscn")

@onready var player: CharacterBody3D = $Player
@onready var hud: Control = $HUDLayer/GameHUD
@onready var planet: Node3D = $Planet
@onready var objective_label: Label = $ObjectiveLayer/Objective
@onready var banner: Label = $ObjectiveLayer/Banner

# Briefing dialogue UI (added to mission.tscn).
@onready var dlg_box: Control = get_node_or_null("DialogueLayer/Box")
@onready var dlg_speaker: Label = get_node_or_null("DialogueLayer/Box/Speaker")
@onready var dlg_line: Label = get_node_or_null("DialogueLayer/Box/Line")
@onready var dlg_hint: Label = get_node_or_null("DialogueLayer/Box/Hint")

const SPEAKER_COL := {
	"REYES":  Color(0.95, 0.80, 0.40),
	"ALINA":  Color(0.35, 0.85, 1.00),
	"SYSTEM": Color(0.85, 0.80, 0.45),
	"ENEMY":  Color(1.00, 0.35, 0.40),
}

# Fixed objective anchors (player spawns at origin facing -Z).
const STATION_POS := Vector3(0, 6, -48)
const GATE_POS    := Vector3(0, 0, -95)
const CITY_POINT  := Vector3(0, -65, -25)

# Hard cap on concurrent enemies. The alien model is a detailed animated UFO, so
# a big simultaneous swarm tanks the framerate / crashes weak phones. We keep a
# small number alive at once and respawn as they die — total kill counts are
# unchanged, the screen just never floods.
const MAX_ALIVE := 5

var _planet_cfg: Dictionary
var _mission: Dictionary
var _type: String = "destroy"
var _target: int = 6
var _accent: Color = Color(0.4, 0.8, 1.0)
var _resolved: bool = false

# Shared counters.
var _killed: int = 0
var _spawned: int = 0
var _scanned: int = 0
var _defend_left: float = 0.0
var _boss: Node3D = null

# Patrol.
var _phase: String = ""          # "patrol" → "fight"
var _waypoints_needed: int = 0

# Defend target.
var _station: Node3D = null

# Escort.
var _shuttles: Array = []
var _shuttles_saved: int = 0
var _shuttles_lost: int = 0
var _shuttles_total: int = 0

# Intercept.
var _city_hp: int = 6
var _city_max: int = 6
var _bombers_down: int = 0
var _bombers_spawned: int = 0
var _spawn_accum: float = 0.0

# Briefing.
var _in_dialogue: bool = false
var _tap_pending: bool = false
var _started: bool = false        # objective is live (gates _process)

func _ready() -> void:
	Gfx.apply($WorldEnvironment, $KeyLight)
	Globals.reset()
	Globals.arena_center = Vector3.ZERO
	Globals.arena_radius = 110.0

	_planet_cfg = MissionData.get_planet(Globals.mission_planet)
	_mission = MissionData.get_mission(Globals.mission_planet, Globals.mission_index)
	_type = _mission.get("type", "destroy")
	_target = int(_mission.get("target", 6))
	_accent = _planet_cfg.get("atmo", Color(0.4, 0.8, 1.0))

	# Build + place the planet as a backdrop.
	planet.configure(_planet_cfg, 80.0)
	planet.position = Vector3(95, -55, -205)

	objective_label.add_theme_color_override("font_color", _accent)
	if dlg_box:
		dlg_box.visible = false

	player.hud = hud
	hud.restart_pressed.connect(_on_restart)
	Globals.player_destroyed.connect(_on_lose)
	Globals.enemy_destroyed.connect(_on_enemy_killed)
	Globals.boss_defeated.connect(_on_boss_defeated)

	# Skip the arcade start menu — missions begin after the briefing.
	if hud.has_method("show_started"):
		hud.show_started()
	player.active = false

	_begin.call_deferred()

func _begin() -> void:
	await get_tree().create_timer(0.3).timeout
	if _resolved:
		return
	await _briefing(_mission.get("brief", []))
	if _resolved:
		return
	player.active = true
	_start_objective()
	_update_objective()
	_started = true

# ─── Briefing dialogue ──────────────────────────────────────────────────────
func _briefing(lines: Array) -> void:
	if lines.is_empty() or dlg_box == null:
		return
	_in_dialogue = true
	dlg_box.visible = true
	hud.visible = false
	for ln in lines:
		if _resolved:
			break
		var who := str(ln.get("who", ""))
		if dlg_speaker:
			dlg_speaker.text = who
			dlg_speaker.add_theme_color_override("font_color", SPEAKER_COL.get(who, Color.WHITE))
		if dlg_line:
			dlg_line.text = str(ln.get("text", ""))
		if dlg_hint:
			dlg_hint.visible = true
		_tap_pending = false
		await get_tree().create_timer(0.25).timeout      # debounce
		while not _consume_tap() and not _resolved:
			await get_tree().process_frame
	dlg_box.visible = false
	hud.visible = true
	_in_dialogue = false

func _consume_tap() -> bool:
	if _tap_pending:
		_tap_pending = false
		return true
	return false

func _input(event: InputEvent) -> void:
	# _input (not _unhandled_input) so the dialogue panel can't swallow the tap.
	if not _in_dialogue:
		return
	if (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventKey and event.pressed):
		_tap_pending = true

# ─── Objective start (per type) ─────────────────────────────────────────────
func _start_objective() -> void:
	match _type:
		"patrol":
			_phase = "patrol"
			_waypoints_needed = int(_mission.get("waypoints", 3))
			_spawn_scan_markers(_waypoints_needed)
		"defend_target":
			_defend_left = float(_mission.get("time", 50))
			_spawn_station()
			_spawn_some_at_station(4)
		"escort":
			_spawn_shuttles(int(_mission.get("shuttles", 3)))
			_spawn_some(2)
		"intercept":
			_city_max = int(_mission.get("city", 6))
			_city_hp = _city_max
			_spawn_accum = 2.4      # first bomber appears right away
		"boss":
			_spawn_boss()
		# ── legacy (other planets) ──
		"defend":
			_defend_left = float(_mission.get("time", 45))
			_spawn_some(4)
		"scan", "gauntlet":
			_scanned = 0
			_spawn_scan_markers(_target)
			_spawn_some(3)
		_:  # destroy / chase
			_spawn_some(mini(4, _target))

# ─── Spawning ───────────────────────────────────────────────────────────────
func _spawn_some(n: int) -> void:
	for i in n:
		_spawn_one(i * 0.3)

func _alive_enemies() -> int:
	return get_tree().get_nodes_in_group("enemy").size()

func _spawn_one(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if _resolved or Globals.player == null or _alive_enemies() >= MAX_ALIVE:
		return
	var d: Area3D = _enemy_scene.instantiate()
	if "archetype" in d:
		d.archetype = randi() % 3
	var center: Vector3 = player.global_position
	var fwd: Vector3 = -player.global_transform.basis.z
	var dir := (fwd * 1.2 + Vector3(randf_range(-1, 1), randf_range(-0.6, 0.6), randf_range(-1, 1))).normalized()
	if dir == Vector3.ZERO:
		dir = fwd
	add_child(d)
	d.global_position = center + dir * randf_range(36.0, 54.0)
	# Escort: send the attacker after a random surviving shuttle.
	if _type == "escort":
		var s := _random_shuttle()
		if s != null and "attack_target" in d:
			d.attack_target = s
	Globals.on_enemy_spawned()
	_spawned += 1

## Drone that hunts the station (defend_target).
func _spawn_some_at_station(n: int) -> void:
	for i in n:
		_spawn_attacker_at_station(i * 0.4)

func _spawn_attacker_at_station(delay: float) -> void:
	await get_tree().create_timer(delay).timeout
	if _resolved or _station == null or not is_instance_valid(_station) or _alive_enemies() >= MAX_ALIVE:
		return
	var d: Area3D = _enemy_scene.instantiate()
	# Shooters only (rushers can't damage the area-only station).
	if "archetype" in d:
		d.archetype = 0 if randf() < 0.7 else 2     # GUNNER or TANK
	var ang := randf() * TAU
	var pit := randf_range(-0.4, 0.6)
	var off := Vector3(cos(ang) * cos(pit), sin(pit), sin(ang) * cos(pit)) * randf_range(40.0, 60.0)
	add_child(d)
	d.global_position = _station.global_position + off
	if "attack_target" in d:
		d.attack_target = _station
	Globals.on_enemy_spawned()
	_spawned += 1

func _spawn_station() -> void:
	var s := AlliedUnit.new()
	s.configure({
		"mode": "station", "max_health": int(_mission.get("station_hp", 40)),
		"accent": Color(0.4, 0.85, 1.0), "defends": true, "name": "ARIA RELAY",
	})
	add_child(s)
	s.global_position = STATION_POS
	s.destroyed.connect(_on_station_lost)
	_station = s

func _spawn_shuttles(n: int) -> void:
	_shuttles_total = n
	for i in n:
		var sh := AlliedUnit.new()
		sh.configure({
			"mode": "mover", "max_health": 16, "move_speed": 12.0,
			"accent": Color(0.5, 1.0, 0.7), "name": "SHUTTLE",
			"goal": GATE_POS + Vector3(randf_range(-8, 8), randf_range(-4, 4), 0),
		})
		add_child(sh)
		# Spread the convoy out behind/around the player.
		sh.global_position = Vector3(randf_range(-18, 18), randf_range(-6, 6), randf_range(10, 34))
		sh.destroyed.connect(_on_shuttle_lost)
		sh.reached_goal.connect(_on_shuttle_saved)
		_shuttles.append(sh)
	_spawn_gate_marker()

## A glowing ring at the escort destination so the player can see the goal.
func _spawn_gate_marker() -> void:
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 7.0
	tm.outer_radius = 9.0
	ring.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = Color(0.5, 1.0, 0.7)
	mat.emission_energy_multiplier = 3.0
	mat.albedo_color = Color(0.5, 1.0, 0.7)
	ring.material_override = mat
	add_child(ring)
	ring.global_position = GATE_POS
	ring.rotation = Vector3(PI / 2, 0, 0)

func _random_shuttle() -> Node3D:
	var alive: Array = []
	for s in _shuttles:
		if is_instance_valid(s):
			alive.append(s)
	if alive.is_empty():
		return null
	return alive[randi() % alive.size()]

func _spawn_boss() -> void:
	var b: Area3D = _boss_scene.instantiate()
	if "max_health" in b:
		b.max_health = int(_mission.get("boss_hp", 80))
	var center: Vector3 = player.global_position
	var fwd: Vector3 = -player.global_transform.basis.z
	add_child(b)
	b.global_position = center + fwd * 60.0
	Globals.on_enemy_spawned()
	_boss = b

func _spawn_bomber() -> void:
	if _resolved:
		return
	var b: Area3D = Bomber.new()
	b.health = int(_mission.get("bomber_hp", 5))
	b.target_point = CITY_POINT + Vector3(randf_range(-10, 10), 0, randf_range(-8, 8))
	add_child(b)
	# High above the city, fanned out, so they streak down past the player.
	b.global_position = CITY_POINT + Vector3(randf_range(-45, 45), 92.0, randf_range(-32, 32))
	b.shot_down.connect(_on_bomber_down)
	b.landed.connect(_on_bomber_landed)
	Globals.on_enemy_spawned()
	_bombers_spawned += 1

func _spawn_scan_markers(n: int) -> void:
	for i in n:
		var m := Area3D.new()
		m.collision_layer = 0
		m.collision_mask = 1            # detect the player (layer 1)
		m.add_to_group("scan_marker")
		var mesh := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 2.2
		sm.height = 4.4
		mesh.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(_accent.r, _accent.g, _accent.b, 0.45)
		mat.emission_enabled = true
		mat.emission = _accent
		mat.emission_energy_multiplier = 4.0
		mesh.material_override = mat
		m.add_child(mesh)
		var col := CollisionShape3D.new()
		var sh := SphereShape3D.new()
		sh.radius = 3.0
		col.shape = sh
		m.add_child(col)
		add_child(m)
		var ang := randf() * TAU
		var pit := randf_range(-0.5, 0.5)
		m.global_position = Vector3(cos(ang) * cos(pit), sin(pit), sin(ang) * cos(pit)) * randf_range(45.0, 85.0)
		m.body_entered.connect(_on_marker_entered.bind(m))

func _on_marker_entered(body: Node, marker: Area3D) -> void:
	if _resolved or not body.is_in_group("player"):
		return
	if not is_instance_valid(marker):
		return
	Audio.play("powerup", -4.0)
	marker.queue_free()
	if _type == "patrol":
		_scanned += 1
		_update_objective()
		if _scanned >= _waypoints_needed:
			_begin_ambush()
	else:  # scan / gauntlet
		_scanned += 1
		_update_objective()
		if _scanned >= _target:
			_win()

## Patrol → the "routine" turns into Alina's first real fight.
func _begin_ambush() -> void:
	if _phase == "fight":
		return
	_phase = "fight"
	Audio.play("powerup", -6.0)
	_spawn_some(mini(4, _target))
	_update_objective()

# ─── Objective tracking ─────────────────────────────────────────────────────
func _on_enemy_killed(_pos: Vector3) -> void:
	if _resolved:
		return
	_killed += 1
	match _type:
		"patrol":
			if _phase == "fight":
				if _killed >= _target:
					_win()
				elif _spawned < _target:
					_spawn_one(randf_range(0.2, 0.8))
		"defend_target":
			# Keep the swarm pressing the station until the timer runs out.
			if _spawned - _killed < 4:
				_spawn_some_at_station(2)
		"escort":
			if _spawned - _killed < 3 and _escort_unresolved() > 0:
				_spawn_one(randf_range(0.4, 1.0))
		"intercept":
			pass   # bombers drive their own win/lose
		"defend":
			if _spawned - _killed < 3:
				_spawn_some(2)
		"scan", "gauntlet":
			if randf() < 0.5:
				_spawn_one(0.0)
		"boss":
			pass   # handled by _on_boss_defeated
		_:  # destroy / chase
			if _killed >= _target:
				_win()
			elif _spawned < _target:
				_spawn_one(randf_range(0.2, 0.8))
	_update_objective()

func _on_boss_defeated() -> void:
	if _type == "boss":
		_win()

# ─── Defend target ──────────────────────────────────────────────────────────
func _on_station_lost(_unit) -> void:
	if _resolved:
		return
	_show_banner_lose("STATION LOST")

# ─── Escort ─────────────────────────────────────────────────────────────────
func _escort_unresolved() -> int:
	return _shuttles_total - _shuttles_saved - _shuttles_lost

func _on_shuttle_saved(unit) -> void:
	_shuttles.erase(unit)
	_shuttles_saved += 1
	Audio.play("wave", -8.0)
	_resolve_escort()

func _on_shuttle_lost(unit) -> void:
	_shuttles.erase(unit)
	_shuttles_lost += 1
	_resolve_escort()

func _resolve_escort() -> void:
	if _resolved:
		return
	_update_objective()
	if _escort_unresolved() > 0:
		return
	# All shuttles accounted for.
	if _shuttles_saved >= int(_mission.get("target", 1)):
		_win()
	else:
		_show_banner_lose("ALL SHUTTLES LOST")

# ─── Intercept ──────────────────────────────────────────────────────────────
func _on_bomber_down(_b) -> void:
	if _resolved:
		return
	_bombers_down += 1
	_update_objective()
	if _bombers_down >= _target:
		_win()

func _on_bomber_landed(_b) -> void:
	if _resolved:
		return
	_city_hp -= 1
	Globals.hitstop(0.12, 0.08)
	Audio.play("explosion", -2.0)
	_update_objective()
	if _city_hp <= 0:
		_show_banner_lose("THE CITY HAS FALLEN")

# ─── Per-frame ───────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	if _resolved or not _started:
		return
	match _type:
		"defend_target":
			_defend_left -= delta
			_update_objective()
			if _defend_left <= 0.0:
				_win()
		"defend":
			_defend_left -= delta
			_update_objective()
			if _defend_left <= 0.0:
				_win()
		"intercept":
			# Spawn bombers in a steady stream until enough are shot down — but
			# never more than a few on screen at once (weak-phone safety).
			_spawn_accum += delta
			var cadence := 2.4
			if _spawn_accum >= cadence and _bombers_spawned < _target + _city_max \
					and _alive_enemies() < 4:
				_spawn_accum = 0.0
				_spawn_bomber()

func _update_objective() -> void:
	if _resolved:
		return
	var name_s: String = _mission.get("name", "")
	var t := ""
	match _type:
		"patrol":
			if _phase == "patrol":
				t = "%s  —  PATROL  %d / %d" % [name_s, _scanned, _waypoints_needed]
			else:
				t = "%s  —  CONTACT! DESTROY  %d / %d" % [name_s, mini(_killed, _target), _target]
		"defend_target":
			var hp := 0
			if _station != null and is_instance_valid(_station):
				hp = _station.health
			t = "%s  —  HOLD %02d:%02d   STATION %d%%" % [
				name_s, int(_defend_left) / 60, int(_defend_left) % 60, _station_pct(hp)]
		"escort":
			t = "%s  —  SAVED %d / %d   (lost %d)" % [name_s, _shuttles_saved, _shuttles_total, _shuttles_lost]
		"intercept":
			t = "%s  —  DOWNED %d / %d   CITY %d/%d" % [name_s, _bombers_down, _target, _city_hp, _city_max]
		"boss":
			t = "%s  —  DESTROY THE CARRIER" % name_s
		"defend":
			t = "%s  —  SURVIVE  %02d:%02d" % [name_s, int(_defend_left) / 60, int(_defend_left) % 60]
		"scan", "gauntlet":
			t = "%s  —  SCAN  %d / %d" % [name_s, _scanned, _target]
		_:
			t = "%s  —  DESTROY  %d / %d" % [name_s, mini(_killed, _target), _target]
	objective_label.text = t

func _station_pct(hp: int) -> int:
	var mx: int = int(_mission.get("station_hp", 40))
	return int(round(100.0 * float(hp) / float(maxi(mx, 1))))

# ─── Resolve ────────────────────────────────────────────────────────────────
func _win() -> void:
	if _resolved:
		return
	_resolved = true
	Globals.is_game_over = true
	player.active = false
	Audio.play("wave", -2.0)
	Save.mark_mission_done(MissionData.mission_key(Globals.mission_planet, Globals.mission_index))
	# Boss missions can carry a campaign-hook reveal after the kill.
	var outro: Array = _mission.get("outro", [])
	if not outro.is_empty():
		await _play_outro(outro)
	_show_banner("MISSION COMPLETE", Color(0.5, 1.0, 0.6))
	await get_tree().create_timer(2.4).timeout
	get_tree().change_scene_to_file(SELECT_SCENE)

## Post-win reveal — reuses the briefing UI but stays on the win path.
func _play_outro(lines: Array) -> void:
	_in_dialogue = true
	if dlg_box:
		dlg_box.visible = true
	hud.visible = false
	for ln in lines:
		var who := str(ln.get("who", ""))
		if dlg_speaker:
			dlg_speaker.text = who
			dlg_speaker.add_theme_color_override("font_color", SPEAKER_COL.get(who, Color.WHITE))
		if dlg_line:
			dlg_line.text = str(ln.get("text", ""))
		if dlg_hint:
			dlg_hint.visible = true
		_tap_pending = false
		await get_tree().create_timer(0.25).timeout
		var waited := 0.0
		while not _consume_tap() and waited < 8.0:
			await get_tree().process_frame
			waited += get_process_delta_time()
	if dlg_box:
		dlg_box.visible = false
	_in_dialogue = false

func _on_lose() -> void:
	_show_banner_lose("MISSION FAILED")

func _show_banner_lose(text: String) -> void:
	if _resolved:
		return
	_resolved = true
	Globals.is_game_over = true
	if player:
		player.active = false
	_show_banner(text, Color(1.0, 0.4, 0.4))
	await get_tree().create_timer(2.4).timeout
	get_tree().change_scene_to_file(SELECT_SCENE)

func _on_restart(_a = null) -> void:
	get_tree().change_scene_to_file(SELECT_SCENE)

func _show_banner(text: String, col: Color) -> void:
	banner.text = text
	banner.add_theme_color_override("font_color", col)
	banner.visible = true
