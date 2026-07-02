## Zeta Legacy — Moon Surface Mission Controller (on-foot)
## Wires Alina, the follow camera, the HUD and the lunar terrain, spawns waves
## of alien drones on the Moon surface and resolves win / lose.
extends Node3D

@export_group("Enemies")
@export var total_enemies: int = 12
@export var max_alive: int = 3
@export var spawn_min_dist: float = 22.0
@export var spawn_max_dist: float = 36.0

var _enemy_scene: PackedScene = preload("res://scenes/story/foot_drone.tscn")
var _bot_scene: PackedScene = preload("res://scenes/story/companion_bot.tscn")
var bot: Node3D = null            ## PIP, Alina's salvage companion
var _spawned: int = 0
var _killed: int = 0
var _resolved: bool = false

@onready var alina: CharacterBody3D = $Alina
@onready var cam: Node3D = $FootCamera
@onready var hud: Control = $HUDLayer/FootHUD
@onready var fade: ColorRect = $CinematicLayer/Fade
@onready var subtitles: Control = $CinematicLayer/SubtitleBox
@onready var skip_hint: Label = $CinematicLayer/SkipHint

# Subtitle accent colours (match the Chapter 1 intro cutscene).
const C_ALINA := Color(0.35, 0.85, 1.0)
const C_SYS   := Color(0.85, 0.80, 0.45)
const C_ENEMY := Color(1.0, 0.35, 0.40)
const C_PIP   := Color(0.4, 0.9, 1.0)

## Crash-arrival cutscene state.
var _cutscene: bool = true       ## true while a story cutscene is playing
var _cut_skip: bool = false      ## player hit the SKIP corner — end the cutscene
var _tap_pending: bool = false   ## one-shot tap latch for advancing dialogue

func _ready() -> void:
	Gfx.apply($WorldEnvironment, $Sun)
	_install_earth()
	Globals.reset()
	Globals.arena_center = Vector3.ZERO
	# Large arena for story mode — bullets stay alive out here.
	Globals.arena_radius = 1000.0  # Moon radius
	Globals.player = alina

	# Set Alina's moon center for spherical gravity.
	alina.moon_center = Vector3.ZERO

	alina.hud = hud
	alina.cam = cam
	cam.target = alina
	cam.hud = hud

	# Crashed-ship wreck Alina wakes up beside.
	_spawn_wreck()

	# Spawn PIP — Alina's companion bot — hovering at her shoulder.
	bot = _bot_scene.instantiate()
	add_child(bot)
	bot.moon_center = Vector3.ZERO
	bot.global_position = Vector3(1.5, 2.0, 0.5)   # flat ground: just above Alina
	bot.set_active(false)

	hud.restart_pressed.connect(_on_restart)
	Globals.player_destroyed.connect(_on_lose)
	Globals.enemy_destroyed.connect(_on_enemy_killed)

	# Short delay so terrain setup has finished before we spawn anything.
	_begin.call_deferred()

## Swap the flat blue placeholder sphere for the real textured Earth model
## hanging in the lunar sky (runtime-loaded; the importer is broken on device).
func _install_earth() -> void:
	var e := get_node_or_null("Earth") as Node3D
	if e == null:
		return
	var model: Node3D = ModelLib.instance_model("res://models/planets/earth.glb")
	if model == null:
		return                       # keep the placeholder sphere as a fallback
	e.visible = false
	add_child(model)
	ModelLib.fit(model, 150.0)       # diameter in metres (big, far away in the sky)
	model.position += e.position     # move its centre to the placeholder's spot
	model.set_meta("earth", true)

func _begin() -> void:
	await get_tree().create_timer(0.4).timeout
	if alina == null:
		return
	# Guaranteed fade-in from black — runs independently of the cutscene logic,
	# so the surface ALWAYS becomes visible even if a beat hiccups.
	create_tween().tween_property(fade, "color", Color(0, 0, 0, 0), 1.2)
	# Play the crash-arrival cutscene, THEN hand control to the player.
	await _arrival_cutscene()
	if alina == null or _resolved:
		return
	alina.active = true
	for i in mini(max_alive, total_enemies):
		_spawn_one()

# ─── Crash-arrival cutscene ─────────────────────────────────────────────────
## Continues straight out of the intro's white crash-flash: Alina comes to in
## the wreckage, her suit reboots, and she spots the first aliens closing in.
## Subtitles only for now — VO can be matched to each line later by speaker.
func _arrival_cutscene() -> void:
	# Keep the player locked and the touch HUD hidden during the cutscene.
	alina.active = false
	hud.visible = false
	skip_hint.visible = true
	subtitles.modulate = Color(1, 1, 1, 1)

	# Surface is already fading in (see _begin); just hold a beat before talking.
	await _cut_wait(1.0)

	await _cut_line("SYSTEM", "LANDING SEQUENCE COMPLETE. LUNA-1 PERIMETER.", C_SYS, 1.8)
	await _cut_line("ARIA", "Touchdown. So this is Luna-1... why is it so dark?", C_ALINA, 2.4)
	await _cut_line("ARIA", "No lights. No traffic. Three hundred people and not a single signal.", C_ALINA, 2.8)

	# PIP, Aria's recon drone, boots up.
	if bot: bot.blink()
	Audio.play("powerup", -8.0)
	await _cut_line("PIP", "Recon unit PIP, online. Atmosphere's breathable, Captain.", C_PIP, 2.2)
	await _cut_line("PIP", "But I'm not reading any crew life signs. Not one. Anywhere.", C_PIP, 3.0)

	# Aria orders the uplink — PIP tries and fails, five times.
	await _cut_line("ARIA", "PIP, raise Earth Command. Tell them we've reached the base.", C_ALINA, 2.8)
	await _cut_line("PIP", "On it. Establishing uplink to Earth...", C_PIP, 2.0)
	if bot: bot.set_scanning(true)
	for i in 5:
		if _cut_skip or _resolved:
			break
		if bot: bot.blink()
		Audio.play("hit", -16.0, 0.1)
		await _cut_status("PIP", "Uplink retry %d / 5 — the relay is dead." % (i + 1), C_PIP, 0.85)
	if bot: bot.set_scanning(false)
	await _cut_line("PIP", "Uplink failed. Whatever silenced this base... silenced us too.", C_PIP, 3.0)
	await _cut_line("ARIA", "Commander Elena said they found something. That it was awake.", C_ALINA, 2.8)

	# Threat appears.
	Audio.play("powerup", -6.0)
	_cam_kick()
	await _cut_line("SYSTEM", "WARNING — MOVEMENT IN SECTOR 7. RISING FAST.", C_SYS, 1.8)
	await _cut_line("PIP", "Contacts! They came up from beneath the surface — weapons hot, Captain!", C_PIP, 2.2)
	await _cut_line("ARIA", "So that's what 'awake' means. Stay close, PIP.", C_ALINA, 2.4)

	subtitles.hide_line()
	await _cut_wait(0.5)
	skip_hint.visible = false
	hud.visible = true
	if bot: bot.set_active(true)
	if hud.has_method("show_objective"):
		hud.show_objective("SURVIVE — whatever woke beneath Luna-1")
	# Done — clear the skip latch so a later cutscene isn't auto-skipped.
	_cut_skip = false
	_cutscene = false

## Build the crashed-ship wreck Alina wakes up beside — a scorched hull, a
## cracked cockpit, a snapped wing, and a shower of electrical sparks.
func _spawn_wreck() -> void:
	var wreck := Node3D.new()
	add_child(wreck)
	wreck.global_position = Vector3(8.0, 0.0, 6.0)   # flat ground
	wreck.rotation = Vector3(0.18, 0.7, 0.30)        # skidded / half-buried tilt

	var hull_mat := StandardMaterial3D.new()
	hull_mat.albedo_color = Color(0.14, 0.14, 0.17)
	hull_mat.metallic = 0.7
	hull_mat.roughness = 0.5

	var hull := MeshInstance3D.new()
	var hb := BoxMesh.new()
	hb.size = Vector3(2.2, 0.9, 5.0)
	hull.mesh = hb
	hull.material_override = hull_mat
	hull.position = Vector3(0, 0.5, 0)
	wreck.add_child(hull)

	var cock := MeshInstance3D.new()
	var cb := BoxMesh.new()
	cb.size = Vector3(1.5, 0.8, 1.5)
	cock.mesh = cb
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.1, 0.28, 0.4)
	cmat.emission_enabled = true
	cmat.emission = Color(0.2, 0.6, 0.85)
	cmat.emission_energy_multiplier = 0.7
	cock.material_override = cmat
	cock.position = Vector3(0, 0.75, -1.9)
	wreck.add_child(cock)

	var wing := MeshInstance3D.new()
	var wb := BoxMesh.new()
	wb.size = Vector3(3.4, 0.16, 1.5)
	wing.mesh = wb
	wing.material_override = hull_mat
	wing.position = Vector3(1.7, 0.45, 0.7)
	wing.rotation = Vector3(0, 0, -0.5)
	wreck.add_child(wing)

	# Electrical sparks (the "short-circuit" damage).
	var sp := CPUParticles3D.new()
	sp.amount = 26
	sp.lifetime = 0.5
	sp.position = Vector3(-0.4, 0.95, -1.2)
	sp.direction = Vector3(0, 1, 0)
	sp.spread = 55.0
	sp.gravity = Vector3(0, -4, 0)
	sp.initial_velocity_min = 2.0
	sp.initial_velocity_max = 5.5
	var qm := QuadMesh.new()
	qm.size = Vector2(0.07, 0.07)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.emission_enabled = true
	smat.emission = Color(1.0, 0.7, 0.25)
	smat.albedo_color = Color(1.0, 0.85, 0.4)
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.material = smat
	sp.mesh = qm
	sp.emitting = true
	wreck.add_child(sp)

	var glow := OmniLight3D.new()
	glow.light_color = Color(1.0, 0.6, 0.25)
	glow.light_energy = 1.4
	glow.omni_range = 6.0
	glow.position = Vector3(-0.4, 0.95, -1.2)
	wreck.add_child(glow)

## Spawn a single foot drone hovering above the flat lunar plain, ringed around
## Alina at a random bearing.
func _spawn_one() -> void:
	if _spawned >= total_enemies:
		return
	_spawned += 1

	var center: Vector3 = alina.global_position if (alina and is_instance_valid(alina)) else Vector3.ZERO
	var ang := randf() * TAU
	var d := randf_range(spawn_min_dist, spawn_max_dist)
	var pos := center + Vector3(cos(ang) * d, 3.0 + randf_range(0.0, 2.0), sin(ang) * d)

	var drone: Area3D = _enemy_scene.instantiate()
	add_child(drone)
	drone.global_position = pos
	if "moon_center" in drone:
		drone.moon_center = Vector3.ZERO

func _on_enemy_killed(_pos: Vector3) -> void:
	if _resolved:
		return
	_killed += 1
	if _killed >= total_enemies:
		_win()
	elif _spawned < total_enemies:
		await get_tree().create_timer(randf_range(0.6, 1.4)).timeout
		if not _resolved:
			_spawn_one()

func _win() -> void:
	if _resolved:
		return
	_resolved = true
	Globals.is_game_over = true
	alina.active = false
	Audio.play("wave", -4.0)
	await get_tree().create_timer(0.9).timeout
	# Chapter 1 closes with the comic finale: the ghost base, the buried crystal,
	# and the thing that wakes beneath the Moon.
	Globals.comic_id = "chapter1_finale"
	Globals.comic_next = "res://scenes/boot/main_menu.tscn"
	get_tree().change_scene_to_file("res://scenes/story/comic_cutscene.tscn")

func _on_lose() -> void:
	if _resolved:
		return
	_resolved = true
	Globals.is_game_over = true
	if hud and hud.has_method("show_lose"):
		hud.show_lose()

func _on_restart() -> void:
	get_tree().reload_current_scene()

# ─── Cutscene primitives ────────────────────────────────────────────────────
## Show one subtitle line: tap once to reveal it, tap again to advance.
## `_hold` is kept for call-site compatibility but advancing is now tap-driven.
func _cut_line(speaker: String, text: String, accent: Color, _hold: float) -> void:
	if _resolved:
		return
	_tap_pending = false
	subtitles.show_line(speaker, text, accent)
	subtitles.set_continue_hint(false)
	# Phase 1 — typing. A tap snaps the whole line in.
	while subtitles.is_typing() and not _cut_skip and not _resolved:
		if _consume_cut_tap():
			subtitles.reveal_now()
		await get_tree().process_frame
	if _cut_skip or _resolved:
		return
	# Phase 2 — hold for a tap to advance.
	subtitles.set_continue_hint(true)
	while not _consume_cut_tap() and not _cut_skip and not _resolved:
		await get_tree().process_frame
	subtitles.set_continue_hint(false)

## True (once) if a tap is queued; clears the latch.
func _consume_cut_tap() -> bool:
	if _tap_pending:
		_tap_pending = false
		return true
	return false

## Quick auto-advancing status blip (no tap) — used for PIP's uplink retries.
func _cut_status(speaker: String, text: String, accent: Color, hold: float) -> void:
	if _resolved or _cut_skip:
		return
	subtitles.show_line(speaker, text, accent)
	subtitles.reveal_now()
	subtitles.set_continue_hint(false)
	await _cut_wait(hold)

## Skip-aware wait in real seconds (collapses instantly if the player skipped).
func _cut_wait(seconds: float) -> void:
	if _cut_skip or _resolved:
		return
	var t := 0.0
	while t < seconds and not _cut_skip and not _resolved:
		await get_tree().process_frame
		t += get_process_delta_time()

## Fade the cinematic overlay toward `target_a` over `dur` seconds.
func _cut_fade(target_a: float, dur: float) -> void:
	var start := fade.color.a
	var t := 0.0
	while t < dur and not _cut_skip and not _resolved:
		await get_tree().process_frame
		t += get_process_delta_time()
		fade.color.a = lerpf(start, target_a, clampf(t / dur, 0.0, 1.0))
	fade.color.a = target_a

## Small one-off camera jolt when the threat appears.
func _cam_kick() -> void:
	var c := cam.get_node_or_null("Camera3D")
	if c == null:
		return
	var tw := create_tween()
	tw.tween_property(c, "h_offset", 0.25, 0.05)
	tw.tween_property(c, "h_offset", 0.0, 0.25)

## During a cutscene: tap = advance dialogue, top-right corner = SKIP the scene.
func _unhandled_input(event: InputEvent) -> void:
	if not _cutscene or _cut_skip:
		return
	var pos := Vector2(-1, -1)
	var tapped := false
	if event is InputEventScreenTouch and event.pressed:
		pos = event.position; tapped = true
	elif event is InputEventMouseButton and event.pressed:
		pos = event.position; tapped = true
	elif event is InputEventKey and event.pressed:
		tapped = true
	if not tapped:
		return
	# Top-right corner skips the rest of the cutscene.
	var vp := get_viewport().get_visible_rect().size
	if pos.x >= 0 and Rect2(vp.x - 168.0, 8.0, 160.0, 44.0).has_point(pos):
		_cut_skip = true
		fade.color.a = 0.0
		subtitles.hide_line()
		return
	_tap_pending = true

# ─── Terrain height helper ─────────────────────────────────────────────────
## Spherical Moon: ground is at constant radius from center.
## (Shader displacement_scale = 0 so visual matches collision sphere exactly.)
func _ground_height(_x: float, _z: float) -> float:
	return 1000.0
