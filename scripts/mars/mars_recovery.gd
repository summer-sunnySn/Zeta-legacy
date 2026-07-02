## Zeta Legacy — Mission: Mars Black-Box Recovery
## Alina rides a hover-bike across the Martian plain to find a satellite that
## crashed in orbit-decay, then recovers its black box. A scanner HUD points the
## way (direction + distance); driving close enough to the wreck lets her grab
## the box. Reuses the flat-ground terrain scatter, the FootHUD, and the comic
## briefing. A short approach beat plays first.
extends Node3D

const C_ALINA := Color(0.35, 0.85, 1.0)
const C_SYS   := Color(0.85, 0.80, 0.45)

@onready var bike: CharacterBody3D = $Bike
@onready var cam: Node3D = $ChaseCamera
@onready var hud: Control = $HUDLayer/FootHUD
@onready var scanner: Label = $HUDLayer/Scanner
@onready var objective: Label = $HUDLayer/Objective
@onready var fade: ColorRect = $CinematicLayer/Fade
@onready var subtitles: Control = $CinematicLayer/SubtitleBox
@onready var skip_hint: Label = $CinematicLayer/SkipHint

var _wreck: Node3D = null
var _box: Node3D = null
var _wreck_pos := Vector3.ZERO
var _recovered: bool = false
var _resolved: bool = false
var _started: bool = false

const RECOVER_RADIUS := 6.0
const WRECK_MIN := 120.0
const WRECK_MAX := 200.0

# cutscene plumbing (mirrors moon_surface)
var _cutscene: bool = true
var _cut_skip: bool = false
var _tap_pending: bool = false

func _ready() -> void:
	Gfx.apply($WorldEnvironment, $Sun)
	_install_ground_texture()
	Globals.reset()
	Globals.arena_center = Vector3.ZERO
	Globals.arena_radius = 320.0
	Globals.player = bike

	bike.hud = hud
	cam.target = bike

	hud.restart_pressed.connect(_on_restart)

	_spawn_wreck()
	_begin.call_deferred()

func _begin() -> void:
	await get_tree().create_timer(0.3).timeout
	create_tween().tween_property(fade, "color", Color(0, 0, 0, 0), 1.0)
	await _approach_cutscene()
	if _resolved:
		return
	bike.active = true
	_started = true
	_update_objective()

# ─── Approach cutscene ───────────────────────────────────────────────────────
func _approach_cutscene() -> void:
	bike.active = false
	hud.visible = false
	skip_hint.visible = true
	subtitles.modulate = Color(1, 1, 1, 1)
	await _cut_wait(0.8)
	await _cut_line("SYSTEM", "MARS SURFACE — TELEMETRY: SATELLITE DOWN, BEARING UNKNOWN.", C_SYS, 2.0)
	await _cut_line("ALINA", "So this is Mars. Cold, red, and quiet. Just me and the bike.", C_ALINA, 2.8)
	await _cut_line("ALINA", "The satellite carried the black box from the lost relay. I find it, we learn the truth.", C_ALINA, 3.0)
	await _cut_line("SYSTEM", "SCANNER ONLINE. FOLLOW THE SIGNAL TO THE WRECK.", C_SYS, 2.0)
	await _cut_line("ALINA", "Let's ride.", C_ALINA, 1.6)
	subtitles.hide_line()
	await _cut_wait(0.4)
	skip_hint.visible = false
	hud.visible = true
	_cut_skip = false
	_cutscene = false

# ─── Ground texture (realistic Mars regolith) ────────────────────────────────
func _install_ground_texture() -> void:
	var ground := get_node_or_null("Terrain/TerrainMesh") as MeshInstance3D
	if ground == null:
		return
	var path := "res://assets/mars/ground.jpg"
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		return
	var img := Image.new()
	if img.load_jpg_from_buffer(bytes) != OK:
		return
	var tex := ImageTexture.create_from_image(img)
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.uv1_scale = Vector3(40, 40, 1)      # tile across the big plain
	mat.roughness = 1.0
	mat.metallic = 0.0
	ground.material_override = mat

# ─── Wreck + black box ───────────────────────────────────────────────────────
func _spawn_wreck() -> void:
	var ang := randf() * TAU
	var d := randf_range(WRECK_MIN, WRECK_MAX)
	_wreck_pos = Vector3(cos(ang) * d, 0.0, sin(ang) * d)

	_wreck = Node3D.new()
	add_child(_wreck)
	_wreck.global_position = _wreck_pos
	_wreck.rotation.y = randf() * TAU

	var metal := StandardMaterial3D.new()
	metal.albedo_color = Color(0.55, 0.57, 0.62)
	metal.metallic = 0.6
	metal.roughness = 0.5

	# Crashed satellite body — a battered hull half-buried, broken solar wings.
	var hull := MeshInstance3D.new()
	var hb := BoxMesh.new(); hb.size = Vector3(3.0, 1.6, 4.5)
	hull.mesh = hb; hull.material_override = metal
	hull.position = Vector3(0, 0.7, 0)
	hull.rotation = Vector3(0.2, 0, 0.15)
	_wreck.add_child(hull)
	for s in [-1.0, 1.0]:
		var wing := MeshInstance3D.new()
		var wb := BoxMesh.new(); wb.size = Vector3(4.0, 0.1, 2.0)
		wing.mesh = wb
		var wm := StandardMaterial3D.new()
		wm.albedo_color = Color(0.1, 0.15, 0.35)
		wm.emission_enabled = true
		wm.emission = Color(0.15, 0.25, 0.5)
		wm.emission_energy_multiplier = 0.4
		wing.material_override = wm
		wing.position = Vector3(s * 3.2, 0.9, 0.5)
		wing.rotation = Vector3(0, 0, s * 0.6)
		_wreck.add_child(wing)
	# Smoke / sparks so it reads as a fresh crash.
	var sp := CPUParticles3D.new()
	sp.amount = 24; sp.lifetime = 1.4
	sp.position = Vector3(0, 1.4, 0)
	sp.direction = Vector3(0, 1, 0); sp.spread = 35.0
	sp.gravity = Vector3(0, 1.5, 0)
	sp.initial_velocity_min = 1.0; sp.initial_velocity_max = 3.0
	var qm := QuadMesh.new(); qm.size = Vector2(0.6, 0.6)
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.albedo_color = Color(0.3, 0.25, 0.22, 0.5)
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	qm.material = smat
	sp.mesh = qm; sp.emitting = true
	_wreck.add_child(sp)

	# The black box — a glowing orange beacon cube on the hull.
	_box = MeshInstance3D.new()
	var cb := BoxMesh.new(); cb.size = Vector3(0.8, 0.6, 0.8)
	(_box as MeshInstance3D).mesh = cb
	var bxm := StandardMaterial3D.new()
	bxm.albedo_color = Color(1.0, 0.5, 0.1)
	bxm.emission_enabled = true
	bxm.emission = Color(1.0, 0.55, 0.15)
	bxm.emission_energy_multiplier = 3.0
	(_box as MeshInstance3D).material_override = bxm
	_box.position = Vector3(0, 1.8, 0)
	_wreck.add_child(_box)
	var bl := OmniLight3D.new()
	bl.light_color = Color(1.0, 0.55, 0.2); bl.light_energy = 2.5; bl.omni_range = 12.0
	bl.position = Vector3(0, 2.2, 0)
	_wreck.add_child(bl)

# ─── Per-frame: scanner + recovery check ─────────────────────────────────────
func _process(delta: float) -> void:
	if _resolved or not _started:
		return
	if _box:
		_box.rotate_y(delta * 1.5)
	var to := _wreck_pos - bike.global_position
	to.y = 0.0
	var dist := to.length()
	_update_scanner(to, dist)
	if not _recovered and dist <= RECOVER_RADIUS:
		_recover()

func _update_scanner(to: Vector3, dist: float) -> void:
	if scanner == null:
		return
	# Bearing relative to the bike's facing → a clock-style arrow.
	var fwd := -bike.global_transform.basis.z
	fwd.y = 0.0
	var ang := rad_to_deg(fwd.signed_angle_to(to.normalized(), Vector3.UP))
	var arrow := "▲"
	if ang > 25.0: arrow = "▶"
	elif ang < -25.0: arrow = "◀"
	if absf(ang) > 150.0: arrow = "▼"
	scanner.text = "◎ SIGNAL  %s   %dm" % [arrow, int(dist)]
	# Tint hotter as you close in.
	var t := clampf(1.0 - dist / WRECK_MAX, 0.0, 1.0)
	scanner.add_theme_color_override("font_color", Color(1.0, 0.9 - 0.6 * t, 0.3 - 0.2 * t))

func _update_objective() -> void:
	if objective:
		objective.text = "RECOVER THE BLACK BOX — find the crashed satellite"

# ─── Recover → win ───────────────────────────────────────────────────────────
func _recover() -> void:
	_recovered = true
	_started = false
	bike.active = false
	Audio.play("powerup", -2.0)
	if scanner: scanner.visible = false
	await _recover_cutscene()
	_win()

func _recover_cutscene() -> void:
	_cut_skip = false
	_cutscene = true
	hud.visible = false
	skip_hint.visible = true
	subtitles.modulate = Color(1, 1, 1, 1)
	# Float the black box up to the bike.
	if _box:
		var tw := create_tween()
		tw.tween_property(_box, "global_position", bike.global_position + Vector3(0, 2.0, 0), 1.0)
	await _cut_wait(0.6)
	await _cut_line("ALINA", "There it is. Black box, intact. Recovering now...", C_ALINA, 2.6)
	await _cut_line("SYSTEM", "DATA CORE SECURED. TRANSMITTING TO COMMAND.", C_SYS, 2.0)
	await _cut_line("ALINA", "Whatever this thing recorded before it fell... it's ours now.", C_ALINA, 2.8)
	subtitles.hide_line()
	await _cut_wait(0.4)
	_cutscene = false

func _win() -> void:
	if _resolved:
		return
	_resolved = true
	Globals.is_game_over = true
	if hud and hud.has_method("show_win"):
		hud.show_win()
	await get_tree().create_timer(2.2).timeout
	get_tree().change_scene_to_file("res://scenes/mission/planet_select.tscn")

func _on_restart(_a = null) -> void:
	get_tree().change_scene_to_file("res://scenes/mission/planet_select.tscn")

# ─── Cutscene primitives (shared style with moon_surface) ────────────────────
func _cut_line(speaker: String, text: String, accent: Color, _hold: float) -> void:
	if _resolved:
		return
	_tap_pending = false
	subtitles.show_line(speaker, text, accent)
	subtitles.set_continue_hint(false)
	while subtitles.is_typing() and not _cut_skip and not _resolved:
		if _consume_tap():
			subtitles.reveal_now()
		await get_tree().process_frame
	if _cut_skip or _resolved:
		return
	subtitles.set_continue_hint(true)
	while not _consume_tap() and not _cut_skip and not _resolved:
		await get_tree().process_frame
	subtitles.set_continue_hint(false)

func _cut_wait(seconds: float) -> void:
	if _cut_skip or _resolved:
		return
	var t := 0.0
	while t < seconds and not _cut_skip and not _resolved:
		await get_tree().process_frame
		t += get_process_delta_time()

func _consume_tap() -> bool:
	if _tap_pending:
		_tap_pending = false
		return true
	return false

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
	var vp := get_viewport().get_visible_rect().size
	if pos.x >= 0 and Rect2(vp.x - 168.0, 8.0, 160.0, 44.0).has_point(pos):
		_cut_skip = true
		fade.color.a = 0.0
		subtitles.hide_line()
		return
	_tap_pending = true
