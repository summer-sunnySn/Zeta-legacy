## Zeta Legacy — Chapter 1 Intro: "Fallen Star"
## Scripted, cinematic space-battle cutscene that opens the story campaign.
##
## Beat sheet:
##   1. ARIA squad (Alina + 4 wingmates, 5 ships) approaches the alien fleet.
##   2. Alina briefs the squad; they engage with confidence.
##   3. The fight turns: a betrayal cripples the squad, ships fall one by one.
##   4. Alina is left alone; her ship is hit and tumbles toward the Moon.
##   5. Crash flare → fade to white → load the playable Moon mission.
##
## Direction (per the Godot "camera director" pattern): instead of one static
## camera we keep a virtual camera (_cam_pos / _cam_look) and cut or dolly it
## between hand-authored shots — wide establish, hero front-3/4, reverse angle,
## battle, and a follow on the crash.  Ships are oriented with look_at() so they
## can never end up upside-down.
##
## Dialogue is TAP-DRIVEN: a line types out (tap once to reveal it instantly),
## then waits for a tap to advance.  A SKIP button (top-right) jumps to gameplay.
## Each line keeps its speaker so recorded VO can be matched in by name later.
extends Node3D

# ─── Wiring ──────────────────────────────────────────────────────────────
const MOON_SCENE := "res://scenes/story/moon_surface.tscn"

@onready var cam: Camera3D = $Camera3D
@onready var subtitles: Control = $UILayer/SubtitleBox
@onready var fade: ColorRect = $UILayer/Fade
@onready var skip_hint: Label = $UILayer/SkipHint

var _ship_scene: PackedScene = preload("res://scenes/player/player.tscn")
var _drone_scene: PackedScene = preload("res://scenes/story/foot_drone.tscn")

# Real models (runtime-loaded — the editor importer is broken on this device).
# The squad ships strip their script, so we install these by hand.
const PLAYER_MODEL := "res://models/ships/intergalactic.glb"
const UFO_MODEL := "res://models/enemies/ufo.glb"

# Speaker accent colours.
const C_ALINA  := Color(0.35, 0.85, 1.0)
const C_SQUAD  := Color(0.55, 0.95, 0.70)
const C_ENEMY  := Color(1.0, 0.35, 0.40)
const C_SYS    := Color(0.85, 0.80, 0.45)

# The alien fleet sits down −Z; the squad flies in toward it.
const FLEET_AT := Vector3(0, 0, -60)

var _squad: Array[Node3D] = []          ## index 0 = Alina's ship
var _aliens: Array[Node3D] = []
var _mothership: Node3D = null
var _moon: Node3D = null                 ## big body Alina crashes into
var _moon_center := Vector3(20, -95, -70)
var _moon_radius := 60.0
var _skipped: bool = false
var _running: bool = true
var _t: float = 0.0

# Virtual camera state (driven every frame in _process).
var _cam_pos: Vector3 = Vector3(0, 3, 26)
var _cam_look: Vector3 = Vector3(0, 0, -10)

# One-shot tap latch, set from input and consumed by the dialogue driver.
var _tap_pending: bool = false

func _ready() -> void:
	Gfx.apply($WorldEnvironment, $Sun)
	# Start fully black, then fade in on the first beat.
	fade.color = Color(0, 0, 0, 1)
	skip_hint.text = "SKIP  ⏭"
	_build_scene()
	_run_sequence()

# ─── Scene construction ───────────────────────────────────────────────────
func _build_scene() -> void:
	_spawn_squad()
	_spawn_alien_fleet()
	_spawn_mothership()
	_spawn_moon()

func _spawn_squad() -> void:
	# Five ARIA ships in a loose V; Alina leads at the tip (nearest the fleet).
	var formation := [
		Vector3(0, 0, 12),         # Alina (lead)
		Vector3(-6, 1.2, 16),
		Vector3(6, 1.2, 16),
		Vector3(-11, -0.8, 20),
		Vector3(11, -0.8, 20),
	]
	for i in formation.size():
		var ship: Node3D = _ship_scene.instantiate()
		# Strip gameplay behaviour BEFORE entering the tree so its _ready()
		# (which claims Globals.player + joins the "player" group) never runs.
		ship.set_script(null)
		add_child(ship)
		ship.position = formation[i]
		# Install the real spaceship model (script is stripped, so player.gd
		# never runs to do it for us).
		var sm := _swap_model(ship.get_node_or_null("MeshPivot"), "SpaceshipModel",
			"ShipModel", PLAYER_MODEL, 4.2, false)
		if sm:
			sm.rotate_y(PI)
		# Orient by look_at so the nose (model −Z) points at the fleet and +Y
		# stays up — guarantees the ship is never upside-down.
		ship.look_at(FLEET_AT, Vector3.UP)
		_tint_engine(ship, C_ALINA if i == 0 else C_SQUAD)
		_squad.append(ship)

func _spawn_alien_fleet() -> void:
	# A wall of alien drones ahead in deep space.
	var rng := RandomNumberGenerator.new()
	rng.seed = 2031
	for i in 6:
		var d: Node3D = _drone_scene.instantiate()
		d.set_script(null)
		add_child(d)
		# Static (no baked animation) — distant cutscene props; keeps the weak
		# phone from choking on a fleet of fully-animated UFOs.
		_swap_model(d.get_node_or_null("ModelPivot"), "DroneModel", "DroneModel",
			UFO_MODEL, 3.0, false)
		d.position = Vector3(
			rng.randf_range(-22, 22),
			rng.randf_range(-8, 8),
			rng.randf_range(-78, -52)
		)
		d.scale = Vector3.ONE * rng.randf_range(1.4, 2.4)
		_aliens.append(d)

## Free a placeholder model node under `pivot` and install a runtime-loaded GLB
## in its place, auto-fitted. Returns the new model (or null).
func _swap_model(pivot: Node, old_name: String, new_name: String, path: String,
		target_len: float, animate: bool) -> Node3D:
	if pivot == null:
		return null
	var old := pivot.get_node_or_null(old_name)
	if old:
		old.free()
	var m: Node3D = ModelLib.instance_model(path)
	if m == null:
		return null
	m.name = new_name
	pivot.add_child(m)
	m.transform = Transform3D.IDENTITY
	ModelLib.fit(m, target_len)
	if animate:
		ModelLib.play_loop(m, randf_range(0.8, 1.2))
	return m

func _spawn_mothership() -> void:
	# Looming hull silhouette far behind the fleet.
	var hull := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(60, 14, 26)
	hull.mesh = box
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.04, 0.07)
	mat.metallic = 0.7
	mat.roughness = 0.4
	mat.emission_enabled = true
	mat.emission = Color(0.5, 0.08, 0.12)
	mat.emission_energy_multiplier = 0.5
	hull.material_override = mat
	hull.position = Vector3(0, -2, -130)
	add_child(hull)
	_mothership = hull

## A big spherical Moon (kept low/off-frame during dialogue) plus a distant
## Earth, so the crash beat can show Alina streaking down onto a curved world.
func _spawn_moon() -> void:
	# The Moon.
	var moon := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = _moon_radius
	sph.height = _moon_radius * 2.0
	sph.radial_segments = 48
	sph.rings = 24
	moon.mesh = sph
	var mmat := StandardMaterial3D.new()
	mmat.albedo_color = Color(0.42, 0.42, 0.46)
	mmat.roughness = 1.0
	mmat.metallic = 0.0
	# Faint blue earthshine on the dark side so the sphere always reads as round.
	mmat.emission_enabled = true
	mmat.emission = Color(0.05, 0.07, 0.12)
	mmat.emission_energy_multiplier = 0.25
	moon.material_override = mmat
	moon.position = _moon_center
	add_child(moon)
	_moon = moon

	# Distant Earth — pure eye-candy in the background.
	var earth := MeshInstance3D.new()
	var es := SphereMesh.new()
	es.radius = 16.0
	es.height = 32.0
	earth.mesh = es
	var emat := StandardMaterial3D.new()
	emat.albedo_color = Color(0.15, 0.35, 0.7)
	emat.emission_enabled = true
	emat.emission = Color(0.2, 0.45, 0.85)
	emat.emission_energy_multiplier = 0.6
	earth.material_override = emat
	earth.position = Vector3(-70, 34, -150)
	add_child(earth)

func _tint_engine(ship: Node3D, _col: Color) -> void:
	var trail := ship.get_node_or_null("MeshPivot/EngineTrail")
	if trail and trail is CPUParticles3D:
		trail.emitting = true

# ─── Per-frame camera + ship life ─────────────────────────────────────────
func _process(delta: float) -> void:
	_t += delta
	# Drive the virtual camera.
	cam.position = _cam_pos
	if (_cam_look - _cam_pos).length() > 0.001:
		cam.look_at(_cam_look, Vector3.UP)
	# Gentle idle bob + bank on each living ship (visual only, on MeshPivot so
	# it never fights the root-position tweens used for surges / the crash).
	for i in _squad.size():
		var ship := _squad[i]
		if not is_instance_valid(ship):
			continue
		var mp := ship.get_node_or_null("MeshPivot")
		if mp:
			mp.position.y = sin(_t * 1.8 + i * 1.3) * 0.12
			mp.rotation.z = sin(_t * 0.9 + i * 0.7) * 0.12

# ─── Sequence ─────────────────────────────────────────────────────────────
func _run_sequence() -> void:
	await _beat_approach()
	if not _running: return
	await _beat_briefing()
	if not _running: return
	await _beat_engage()
	if not _running: return
	await _beat_turning_point()
	if not _running: return
	await _beat_betrayal()
	if not _running: return
	await _beat_last_stand()
	if not _running: return
	await _beat_crash()
	_finish()

# Beat 1 — Approach. Wide establishing shot, fade in from black.
func _beat_approach() -> void:
	_cut_to(Vector3(24, 7, 30), Vector3(0, 0, -10))
	await _fade_to(0.0, 1.4)
	# Slow push toward the formation as the title card reads.
	_dolly_to(Vector3(16, 5, 26), Vector3(0, 0, -14), 6.0)
	await _line("SYSTEM", "LUNAR ORBIT — 2041. ARIA STRIKE WING.", C_SYS)

# Beat 2 — Briefing. Hero front-3/4 on Alina's ship, then a wing two-shot.
func _beat_briefing() -> void:
	_dolly_to(Vector3(-7, 2.0, 3.0), Vector3(0, 0.6, 14), 2.2)
	await _line("ALINA", "Squad, lock formation. The signal array is dead ahead.", C_ALINA)
	await _line("ALINA", "We knock out that relay, Earth gets to breathe again.", C_ALINA)
	_dolly_to(Vector3(9, 1.6, 12), Vector3(-3, 0.6, 18), 2.0)
	await _line("RAVEN", "Copy, lead. Wings green. Right behind you.", C_SQUAD)
	await _line("ALINA", "Stay tight, watch your spacing. We do this together.", C_ALINA)

# Beat 3 — Engage. Cut to a wide battle angle; the squad surges and opens fire.
func _beat_engage() -> void:
	_cut_to(Vector3(14, 6, 8), Vector3(0, 0, -24))
	await _line("ALINA", "Weapons free. Go, go, go!", C_ALINA)
	_surge_squad()
	_dolly_to(Vector3(10, 4, 0), Vector3(0, 0, -34), 3.2)
	for i in 6:
		if not _running: return
		_fire_volley()
		await _wait(0.35)
	await _line("RAVEN", "Splash two! We've got them on the back foot!", C_SQUAD)

# Beat 4 — Turning point. Reverse angle from the fleet; the trap is sprung.
func _beat_turning_point() -> void:
	_dolly_to(Vector3(0, 5, -36), Vector3(0, 0, 6), 2.6)
	await _line("ALINA", "Wait... that's too easy. Where's the rest of them?", C_ALINA)
	await _line("SYSTEM", "WARNING — MULTIPLE CONTACTS. ALL VECTORS.", C_SYS)
	_mothership_flare()
	await _line("ENEMY", "You were always meant to find us, little soldier.", C_ENEMY)

# Beat 5 — Betrayal. Tight on Alina, wingmates fall one by one.
func _beat_betrayal() -> void:
	_dolly_to(Vector3(5, 1.8, 9), Vector3(0, 0.4, 14), 1.6)
	await _line("RAVEN", "Lead, my targeting's locked from the outside — ARIA's locking ME!", C_SQUAD)
	await _line("ALINA", "Raven, break off! It's a friendly lock — break NOW!", C_ALINA)
	await _kill_wingmate(4)
	await _line("ALINA", "No— RAVEN!", C_ALINA)
	await _kill_wingmate(3)
	await _kill_wingmate(2)
	await _line("ALINA", "They sold us out. Command sold us ALL out.", C_ALINA)
	await _kill_wingmate(1)

# Beat 6 — Last stand. Alina alone, ship failing.
func _beat_last_stand() -> void:
	_dolly_to(Vector3(-4, 1.4, 8), Vector3(0, 0.4, 13), 2.0)
	await _line("ALINA", "I'm the last one. I still have the data — I have to get it home.", C_ALINA)
	await _line("ENEMY", "The data dies with you. Nowhere left to run.", C_ENEMY)
	_hit_alina()
	await _line("SYSTEM", "HULL BREACH. ENGINE FAILURE. ALTITUDE DROPPING.", C_SYS)
	await _line("ALINA", "Mayday, mayday — I'm going down over the far side!", C_ALINA)

# Beat 7 — Crash. A wide profile shot shows Alina streaking down a fiery arc
# onto the curved face of the Moon while alien fire chases her.
func _beat_crash() -> void:
	await _line("ALINA", "If anyone hears this... the enemy is already among us.", C_ALINA)
	await _line("ALINA", "Don't trust the signal. Don't trust ANYONE.", C_ALINA)
	subtitles.hide_line()

	var ship: Node3D = _squad[0] if _squad.size() > 0 and is_instance_valid(_squad[0]) else null

	# Swing out to a dramatic side angle that frames the whole curved Moon.
	_cut_to(Vector3(-50, -4, -4), Vector3(10, -34, -46))
	await _wait(0.7)

	if ship:
		_ignite_crash_trail(ship)
		# Impact point on the near-upper face of the Moon.
		var impact := _moon_center + Vector3(-0.2, 0.85, 0.45).normalized() * _moon_radius
		# Accelerating fall (gravity feel) + violent tumble.
		var tw := create_tween().set_parallel(true)
		tw.tween_property(ship, "position", impact, 3.0)\
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(ship, "rotation", ship.rotation + Vector3(10, 5, 14), 3.0)
		# Camera slowly pushes in along the descent.
		_dolly_to(Vector3(-42, -16, -14), Vector3(impact.x, impact.y + 4, impact.z), 3.0)
		# Parting alien shots chase her down (the attack stays on screen).
		for i in 4:
			if not _running: return
			var a := _pick_alive(_aliens)
			if a and is_instance_valid(ship):
				_beam(a.global_position, ship.global_position, C_ENEMY)
			await _wait(0.7)
		# Impact bloom on the lunar surface.
		_explosion_at(impact)
		_explosion_at(impact + Vector3(4, 1, 3))
		Audio.play("explosion", 0.0)
		_shake(1.3)
		if is_instance_valid(ship):
			ship.visible = false

	await _wait(0.6)
	await _fade_to(1.0, 1.2, Color(1, 1, 1))   # white-out flash
	await _wait(0.5)

## Turn the engine plume into a fiery re-entry trail for the crash.
func _ignite_crash_trail(ship: Node3D) -> void:
	var trail := ship.get_node_or_null("MeshPivot/EngineTrail")
	if trail and trail is CPUParticles3D:
		trail.amount = 90
		trail.lifetime = 1.2
		trail.initial_velocity_min = 12.0
		trail.initial_velocity_max = 22.0
		var m = trail.material_override
		if m is StandardMaterial3D:
			m.emission = Color(1.0, 0.5, 0.12)
			m.emission_energy_multiplier = 6.0

func _finish() -> void:
	_running = false
	get_tree().change_scene_to_file(MOON_SCENE)

# ─── Camera director ──────────────────────────────────────────────────────
## Instant cut to a shot.
func _cut_to(pos: Vector3, look: Vector3) -> void:
	_cam_pos = pos
	_cam_look = look

## Smoothly dolly to a shot over `dur` seconds (does not block the sequence).
func _dolly_to(pos: Vector3, look: Vector3, dur: float) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(self, "_cam_pos", pos, dur)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "_cam_look", look, dur)\
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)

# ─── Battle FX helpers ──────────────────────────────────────────────────
func _surge_squad() -> void:
	for ship in _squad:
		if not is_instance_valid(ship):
			continue
		var tw := create_tween()
		tw.tween_property(ship, "position", ship.position + Vector3(0, 0, -14), 1.6)\
			.set_trans(Tween.TRANS_SINE)

## Crisscross laser bolts between the squad and the fleet (cheap line beams).
func _fire_volley() -> void:
	Audio.play("shoot", -8.0, 0.15)
	for i in 3:
		var src: Node3D = _pick_alive(_squad)
		var dst: Node3D = _pick_alive(_aliens)
		if src and dst:
			_beam(src.global_position, dst.global_position, C_ALINA)
	if randf() < 0.7:
		var a: Node3D = _pick_alive(_aliens)
		var t: Node3D = _pick_alive(_squad)
		if a and t:
			_beam(a.global_position, t.global_position, C_ENEMY)

## Pick a random still-valid node from a list (null if none remain).
func _pick_alive(list: Array[Node3D]) -> Node3D:
	var alive: Array[Node3D] = []
	for n in list:
		if is_instance_valid(n):
			alive.append(n)
	if alive.is_empty():
		return null
	return alive[randi() % alive.size()]

func _beam(from: Vector3, to: Vector3, col: Color) -> void:
	var mesh := MeshInstance3D.new()
	var im := ImmediateMesh.new()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 4.0
	mat.albedo_color = col
	im.surface_begin(Mesh.PRIMITIVE_LINES, mat)
	im.surface_add_vertex(from)
	im.surface_add_vertex(to)
	im.surface_end()
	mesh.mesh = im
	add_child(mesh)
	var tw := create_tween()
	tw.tween_interval(0.08)
	tw.tween_callback(mesh.queue_free)

func _mothership_flare() -> void:
	Audio.play("powerup", -4.0)
	if _mothership and is_instance_valid(_mothership):
		var mat: StandardMaterial3D = _mothership.material_override
		if mat:
			var tw := create_tween()
			tw.tween_property(mat, "emission_energy_multiplier", 3.0, 0.6)
			tw.tween_property(mat, "emission_energy_multiplier", 0.8, 1.0)
	_shake(0.6)

## Destroy a wingmate ship index with an explosion flash.
func _kill_wingmate(idx: int) -> void:
	if idx < 0 or idx >= _squad.size():
		return
	var ship := _squad[idx]
	if ship == null or not is_instance_valid(ship):
		return
	_explosion_at(ship.global_position)
	Audio.play("explosion", -3.0, 0.1)
	_shake(0.4)
	ship.queue_free()
	await _wait(0.9)

func _hit_alina() -> void:
	if _squad.size() == 0 or not is_instance_valid(_squad[0]):
		return
	_explosion_at(_squad[0].global_position + Vector3(0, 1, -1))
	Audio.play("player_hit", -2.0)
	_shake(0.8)
	var trail := _squad[0].get_node_or_null("MeshPivot/EngineTrail")
	if trail and trail is CPUParticles3D:
		trail.amount = 60
		trail.lifetime = 0.9

func _explosion_at(pos: Vector3) -> void:
	var scene: PackedScene = load("res://scenes/fx/explosion.tscn")
	if scene == null:
		return
	var boom: Node3D = scene.instantiate()
	add_child(boom)
	boom.global_position = pos

# ─── Camera shake ─────────────────────────────────────────────────────────
var _shake_amt: float = 0.0
func _shake(amount: float) -> void:
	_shake_amt = maxf(_shake_amt, amount)

func _physics_process(delta: float) -> void:
	if _shake_amt > 0.001:
		cam.h_offset = randf_range(-1, 1) * _shake_amt * 0.3
		cam.v_offset = randf_range(-1, 1) * _shake_amt * 0.3
		_shake_amt = move_toward(_shake_amt, 0.0, 2.0 * delta)
	else:
		cam.h_offset = 0.0
		cam.v_offset = 0.0

# ─── Tap-driven dialogue ────────────────────────────────────────────────────
## Show a line, let the player tap once to reveal it, then tap again to advance.
func _line(speaker: String, text: String, accent: Color) -> void:
	if not _running:
		return
	_tap_pending = false                 # ignore stale taps from battle action
	subtitles.show_line(speaker, text, accent)
	subtitles.set_continue_hint(false)
	# Phase 1 — typing. A tap snaps the whole line in.
	while subtitles.is_typing() and _running:
		if _consume_tap():
			subtitles.reveal_now()
		await get_tree().process_frame
	if not _running:
		return
	# Phase 2 — hold for a tap to advance.
	subtitles.set_continue_hint(true)
	while _running and not _consume_tap():
		await get_tree().process_frame
	subtitles.set_continue_hint(false)

## True (once) if a tap is queued; clears the latch.
func _consume_tap() -> bool:
	if _tap_pending:
		_tap_pending = false
		return true
	return false

## Skip-aware wait used by timed battle action (not dialogue).
func _wait(seconds: float) -> void:
	if _skipped or not _running:
		return
	var t := 0.0
	while t < seconds and _running and not _skipped:
		await get_tree().process_frame
		t += get_process_delta_time()

func _fade_to(target_a: float, dur: float, col: Color = Color(0, 0, 0)) -> void:
	var start := fade.color
	var goal := Color(col.r, col.g, col.b, target_a)
	var t := 0.0
	while t < dur and _running:
		await get_tree().process_frame
		t += get_process_delta_time()
		fade.color = start.lerp(goal, clampf(t / dur, 0.0, 1.0))
	fade.color = goal

# ─── Input: tap = advance, SKIP button = jump to gameplay ───────────────────
func _unhandled_input(event: InputEvent) -> void:
	var pos := Vector2(-1, -1)
	var tapped := false
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position; tapped = true
	elif event is InputEventMouseButton and event.pressed:
		pos = event.position; tapped = true
	elif event is InputEventKey and event.pressed:
		tapped = true
	if not tapped or not _running:
		return
	# Top-right corner acts as a SKIP button.
	if pos.x >= 0 and _skip_rect().has_point(pos):
		_skip()
		return
	_tap_pending = true

## Hit-box for the SKIP affordance, in screen pixels.
func _skip_rect() -> Rect2:
	var vp := get_viewport().get_visible_rect().size
	return Rect2(vp.x - 168.0, 8.0, 160.0, 44.0)

func _skip() -> void:
	_skipped = true
	_running = false
	get_tree().change_scene_to_file(MOON_SCENE)
