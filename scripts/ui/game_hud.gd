## Zeta Legacy — Game HUD & Touch Controls
## Owns all touch input and exposes a clean interface the player reads:
##   • get_steer_vector()  -> Vector2  flight steering (left thumb joystick)
##   • is_firing           -> bool     true while the scope is held
##   • reticle_position    -> Vector2  screen point the player is aiming at
##
## Drawing is fully procedural (no image assets): a left flight stick, a right
## draggable scope, a crosshair, health pips, score/wave text and off-screen
## enemy arrows. Multi-touch aware so you can steer and aim at the same time.
extends Control

# ─── Signals ────────────────────────────────────────────────────────────
signal start_pressed
signal restart_pressed

# ─── Tuning ─────────────────────────────────────────────────────────────
@export var stick_radius: float = 120.0     ## flight joystick travel
@export var stick_margin: float = 40.0
@export var reticle_radius: float = 26.0
@export var arrow_ring: float = 90.0         ## radius of the off-screen arrow ring

# ─── Public Interface (read by player.gd) ──────────────────────────────
var is_firing: bool = false
var reticle_position: Vector2 = Vector2.ZERO
var boost_held: bool = false
var brake_held: bool = false

# ─── Touch State ────────────────────────────────────────────────────────
var _stick_touch: int = -1
var _stick_origin: Vector2 = Vector2.ZERO
var _stick_vec: Vector2 = Vector2.ZERO

var _aim_touch: int = -1
var _boost_touch: int = -1
var _brake_touch: int = -1
var _bomb_touch: int = -1
var _dash_touch: int = -1

@export var throttle_btn_radius: float = 66.0
@export var bomb_btn_radius: float = 54.0
var _flash: float = 0.0
var _popups: Array = []          ## floating score numbers: {pos, amt, t}

# ─── Game-State Display ─────────────────────────────────────────────────
var _started: bool = false
var _game_over: bool = false
var health: int = 6
var max_health: int = 6

# Colors
const C_STICK_BASE := Color(0.3, 0.7, 1.0, 0.25)
const C_STICK_KNOB := Color(0.3, 0.8, 1.0, 0.7)
const C_RETICLE := Color(1.0, 0.3, 0.3, 0.9)
const C_RETICLE_IDLE := Color(0.5, 0.9, 1.0, 0.5)
const C_TEXT := Color(0.6, 0.95, 1.0, 1.0)
const C_HEALTH := Color(0.3, 1.0, 0.5, 0.9)
const C_HEALTH_EMPTY := Color(0.2, 0.25, 0.3, 0.6)
const C_ARROW := Color(1.0, 0.4, 0.2, 0.85)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_center_reticle()
	Globals.score_changed.connect(func(_s): queue_redraw())
	Globals.wave_started.connect(func(_w): Audio.play("wave", -6.0); queue_redraw())
	Globals.player_hit.connect(_sync_health)
	Globals.smart_bomb_used.connect(func(): _flash = 0.85)
	Globals.score_popup.connect(func(pos, amt): _popups.append({"pos": pos, "amt": amt, "t": 0.0}))

func _process(_delta: float) -> void:
	# Reticle aim point and off-screen arrows track moving targets, so the
	# overlay must repaint every frame while a round is live.
	if _started and not _game_over:
		queue_redraw()
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - _delta * 2.2)
		queue_redraw()
	if not _popups.is_empty():
		for p in _popups:
			p["t"] += _delta
		_popups = _popups.filter(func(p): return p["t"] < 1.0)

func _center_reticle() -> void:
	reticle_position = size * 0.5

# ─── Public API ─────────────────────────────────────────────────────────
func get_steer_vector() -> Vector2:
	# y inverted so dragging up = pitch up (nose up).
	return Vector2(_stick_vec.x, -_stick_vec.y)

# ─── Game Flow Hooks (called by main.gd) ────────────────────────────────
func show_started() -> void:
	_started = true
	_game_over = false
	_center_reticle()
	queue_redraw()

func show_game_over() -> void:
	_game_over = true
	is_firing = false
	queue_redraw()

func _sync_health() -> void:
	if Globals.player and "health" in Globals.player:
		health = Globals.player.health
		max_health = Globals.player.max_health
	queue_redraw()

# ─── Input ──────────────────────────────────────────────────────────────
func _gui_input(event: InputEvent) -> void:
	var tap_down: bool = (event is InputEventScreenTouch and event.pressed) \
		or (event is InputEventMouseButton and event.pressed)

	if _game_over:
		if tap_down:
			restart_pressed.emit()
		return

	if not _started:
		if tap_down:
			_handle_menu_tap(event.position)
		return

	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position)
	# Mouse fallback for desktop testing.
	elif event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_handle_touch(0, event.position, event.pressed)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_handle_drag(0, event.position)

func _is_left_half(pos: Vector2) -> bool:
	return pos.x < size.x * 0.5

func _bomb_center() -> Vector2:
	return Vector2(98.0, size.y - 98.0)

func _dash_center() -> Vector2:
	return Vector2(98.0, size.y - 250.0)

func _launch_rect() -> Rect2:
	return Rect2(size.x * 0.5 - 110.0, size.y - 108.0, 220.0, 60.0)

func _upg_row_rect(i: int) -> Rect2:
	return Rect2(size.x * 0.5 - 215.0, 188.0 + i * 60.0, 430.0, 50.0)

func _handle_menu_tap(pos: Vector2) -> void:
	if _launch_rect().has_point(pos):
		start_pressed.emit()
		return
	for i in Save.UPGRADES.size():
		if _upg_row_rect(i).has_point(pos):
			Save.buy(Save.UPGRADES[i])
			queue_redraw()
			return

func _handle_touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		# Smart-bomb button (one-shot on press).
		if pos.distance_to(_bomb_center()) <= bomb_btn_radius and _bomb_touch == -1:
			_bomb_touch = index
			var p := Globals.player
			if p and p.has_method("use_smart_bomb"):
				p.use_smart_bomb()
			queue_redraw()
			return
		# Dash button (one-shot on press).
		if pos.distance_to(_dash_center()) <= bomb_btn_radius and _dash_touch == -1:
			_dash_touch = index
			var pd := Globals.player
			if pd and pd.has_method("try_dash"):
				pd.try_dash()
			queue_redraw()
			return
		# Throttle buttons are checked first so they win over stick/aim zones.
		if pos.distance_to(_boost_center()) <= throttle_btn_radius and _boost_touch == -1:
			_boost_touch = index
			boost_held = true
		elif pos.distance_to(_brake_center()) <= throttle_btn_radius and _brake_touch == -1:
			_brake_touch = index
			brake_held = true
		# Left half drives the flight stick, right half grabs the scope.
		elif _is_left_half(pos) and _stick_touch == -1:
			_stick_touch = index
			_stick_origin = pos
			_stick_vec = Vector2.ZERO
		elif not _is_left_half(pos) and not _near_ui(pos) and _aim_touch == -1:
			_aim_touch = index
			is_firing = true
			reticle_position = pos
	else:
		if index == _bomb_touch:
			_bomb_touch = -1
		elif index == _dash_touch:
			_dash_touch = -1
		elif index == _boost_touch:
			_boost_touch = -1
			boost_held = false
		elif index == _brake_touch:
			_brake_touch = -1
			brake_held = false
		elif index == _stick_touch:
			_stick_touch = -1
			_stick_vec = Vector2.ZERO
		elif index == _aim_touch:
			_aim_touch = -1
			is_firing = false
	queue_redraw()

## True when a touch is on/near a throttle button — used to stop UI taps from
## also triggering the aim/fire zone.
func _near_ui(pos: Vector2) -> bool:
	var m := throttle_btn_radius + 24.0
	return pos.distance_to(_boost_center()) <= m or pos.distance_to(_brake_center()) <= m

func _boost_center() -> Vector2:
	return Vector2(size.x - 90.0, size.y - 90.0)

func _brake_center() -> Vector2:
	return Vector2(size.x - 90.0, size.y - 248.0)

func _handle_drag(index: int, pos: Vector2) -> void:
	if index == _stick_touch:
		var off := pos - _stick_origin
		_stick_vec = (off / stick_radius).limit_length(1.0)
	elif index == _aim_touch:
		reticle_position = pos.clamp(Vector2.ZERO, size)
	queue_redraw()

# ─── Drawing ────────────────────────────────────────────────────────────
func _draw() -> void:
	if not _started:
		_draw_start_menu()
		_draw_flash()
		return

	_draw_flight_stick()
	_draw_throttle_buttons()
	_draw_bomb_button()
	_draw_dash_button()
	_draw_popups()
	_draw_reticle()
	_draw_hud_text()
	_draw_health()
	_draw_powerups()
	_draw_speedo()
	_draw_combo()
	_draw_boss_bar()
	_draw_offscreen_arrows()

	if _game_over:
		_draw_centered_text("SHIP DESTROYED", size * 0.5 + Vector2(0, -28), 40, C_RETICLE)
		_draw_centered_text("HIGH SCORE  %d" % Save.high_score, size * 0.5 + Vector2(0, 14), 20, Color(1, 0.9, 0.4))
		_draw_centered_text("TAP TO RESTART", size * 0.5 + Vector2(0, 48), 18, C_TEXT)

	_draw_flash()

# ─── Start Menu (high score + upgrades) ─────────────────────────────────
func _draw_start_menu() -> void:
	var font := get_theme_default_font()
	_draw_centered_text("ZETA LEGACY", Vector2(size.x * 0.5, 86), 42, C_TEXT)
	_draw_centered_text("HIGH SCORE  %d        CREDITS  %d" % [Save.high_score, Save.credits],
		Vector2(size.x * 0.5, 138), 18, Color(1, 0.9, 0.4))

	var names := {"firerate": "FIRE RATE", "health": "MAX HEALTH", "damage": "DAMAGE", "bombs": "SMART BOMBS"}
	for i in Save.UPGRADES.size():
		var key: String = Save.UPGRADES[i]
		var r := _upg_row_rect(i)
		var lvl := Save.upgrade_level(key)
		var maxed := lvl >= Save.MAX_LEVEL
		var afford := Save.can_buy(key)
		var col := Color(0.4, 1.0, 0.6) if afford else (Color(0.55, 0.55, 0.6) if not maxed else Color(0.6, 0.75, 1.0))
		draw_rect(r, Color(0.09, 0.12, 0.17, 0.75))
		draw_rect(r, col, false, 2.0)
		draw_string(font, r.position + Vector2(16, 33), "%s   Lv %d/%d" % [names.get(key, key), lvl, Save.MAX_LEVEL],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, C_TEXT)
		var rtxt := "MAX" if maxed else ("BUY %d" % Save.upgrade_cost(key))
		draw_string(font, r.position + Vector2(r.size.x - 150, 33), rtxt, HORIZONTAL_ALIGNMENT_LEFT, 140, 19, col)

	var lr := _launch_rect()
	draw_rect(lr, Color(0.1, 0.4, 0.6, 0.85))
	draw_rect(lr, Color(0.3, 0.9, 1.0), false, 2.5)
	_draw_centered_text("LAUNCH", lr.position + lr.size * 0.5, 26, Color(0.85, 1.0, 1.0))
	_draw_centered_text("Left: fly  •  Right: aim/fire  •  BOMB / BOOST / BRAKE",
		Vector2(size.x * 0.5, size.y - 32), 14, C_RETICLE_IDLE)

func _draw_bomb_button() -> void:
	var p := Globals.player
	var bombs := 0
	if p and is_instance_valid(p) and "smart_bombs" in p:
		bombs = p.smart_bombs
	var c := _bomb_center()
	var col := Color(1.0, 0.85, 0.2, 0.95) if bombs > 0 else Color(0.4, 0.4, 0.45, 0.5)
	draw_circle(c, bomb_btn_radius, Color(col.r, col.g, col.b, 0.15))
	draw_arc(c, bomb_btn_radius, 0, TAU, 32, col, 2.5)
	_draw_centered_text("BOMB", c + Vector2(0, -8), 14, col)
	_draw_centered_text("x%d" % bombs, c + Vector2(0, 15), 19, col)

func _draw_dash_button() -> void:
	var p := Globals.player
	var ready := true
	if p and is_instance_valid(p) and p.has_method("dash_ready"):
		ready = p.dash_ready()
	var c := _dash_center()
	var col := Color(0.4, 1.0, 0.7, 0.95) if ready else Color(0.4, 0.45, 0.5, 0.5)
	draw_circle(c, bomb_btn_radius, Color(col.r, col.g, col.b, 0.15))
	draw_arc(c, bomb_btn_radius, 0, TAU, 32, col, 2.5)
	_draw_centered_text("DASH", c, 16, col)

func _draw_popups() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	for p in _popups:
		var wpos: Vector3 = p["pos"]
		if cam.is_position_behind(wpos):
			continue
		var t: float = p["t"]
		var sp := cam.unproject_position(wpos) - Vector2(0, t * 46.0)
		_draw_centered_text("+%d" % int(p["amt"]), sp, 20, Color(1.0, 0.95, 0.4, 1.0 - t))

func _draw_boss_bar() -> void:
	var b := Globals.boss
	if b == null or not is_instance_valid(b) or not b.has_method("health_fraction"):
		return
	var w := size.x * 0.5
	var o := Vector2(size.x * 0.5 - w * 0.5, 40.0)
	draw_rect(Rect2(o, Vector2(w, 15)), Color(0.16, 0.05, 0.07, 0.75))
	draw_rect(Rect2(o, Vector2(w * b.health_fraction(), 15)), Color(1.0, 0.25, 0.2))
	_draw_centered_text("◆ BOSS ◆", Vector2(size.x * 0.5, 33), 14, Color(1.0, 0.5, 0.4))

func _draw_flash() -> void:
	if _flash > 0.0:
		draw_rect(Rect2(Vector2.ZERO, size), Color(1, 1, 1, _flash * 0.7))

func _draw_combo() -> void:
	if Globals.combo < 2:
		return
	var mult: int = mini(Globals.combo, Globals.COMBO_MAX)
	var txt := "COMBO  x%d" % mult
	# Hotter color as the chain grows.
	var heat := clampf(float(mult) / float(Globals.COMBO_MAX), 0.0, 1.0)
	var col := Color(1.0, lerpf(0.9, 0.3, heat), lerpf(0.4, 0.1, heat), 1.0)
	var fs := 22 + mult
	_draw_centered_text(txt, Vector2(size.x * 0.5, 74), fs, col)

func _draw_speedo() -> void:
	var p := Globals.player
	if p == null or not is_instance_valid(p):
		return
	if not ("current_speed" in p):
		return
	var spd: float = p.current_speed
	var top: float = p.boost_speed if ("boost_speed" in p) else 40.0
	var frac := clampf(spd / maxf(top, 1.0), 0.0, 1.0)

	# Small gauge centered along the bottom.
	var w := 150.0
	var h := 8.0
	var origin := Vector2(size.x * 0.5 - w * 0.5, size.y - 26.0)
	draw_rect(Rect2(origin, Vector2(w, h)), Color(0.1, 0.15, 0.2, 0.6))
	var col := Color(0.3, 0.9, 1.0, 0.9)
	if frac > 0.75:
		col = Color(0.4, 1.0, 0.6, 0.95)   ## boost zone
	elif frac < 0.35:
		col = Color(1.0, 0.7, 0.3, 0.9)    ## brake zone
	draw_rect(Rect2(origin, Vector2(w * frac, h)), col)
	var font := get_theme_default_font()
	draw_string(font, origin + Vector2(0, -6), "SPD %d" % int(round(spd)), HORIZONTAL_ALIGNMENT_CENTER, w, 14, C_TEXT)

func _draw_throttle_buttons() -> void:
	var font := get_theme_default_font()
	# BOOST
	var bc := _boost_center()
	var bcol := Color(0.3, 1.0, 0.6, 0.9) if boost_held else Color(0.3, 0.8, 1.0, 0.45)
	draw_circle(bc, throttle_btn_radius, Color(bcol.r, bcol.g, bcol.b, 0.15))
	draw_arc(bc, throttle_btn_radius, 0, TAU, 32, bcol, 2.5)
	_draw_centered_text("BOOST", bc, 15, bcol)
	# BRAKE
	var kc := _brake_center()
	var kcol := Color(1.0, 0.6, 0.3, 0.9) if brake_held else Color(0.6, 0.7, 0.9, 0.4)
	draw_circle(kc, throttle_btn_radius, Color(kcol.r, kcol.g, kcol.b, 0.12))
	draw_arc(kc, throttle_btn_radius, 0, TAU, 32, kcol, 2.5)
	_draw_centered_text("BRAKE", kc, 15, kcol)

func _draw_flight_stick() -> void:
	var base := Vector2(stick_margin + stick_radius, size.y - stick_margin - stick_radius)
	if _stick_touch != -1:
		base = _stick_origin
	draw_circle(base, stick_radius, C_STICK_BASE)
	draw_arc(base, stick_radius, 0, TAU, 48, Color(0.4, 0.8, 1.0, 0.4), 2.0)
	var knob := base + _stick_vec * stick_radius
	draw_circle(knob, 30.0, C_STICK_KNOB)

func _draw_reticle() -> void:
	var col := C_RETICLE if is_firing else C_RETICLE_IDLE
	var r := reticle_radius
	var p := reticle_position
	draw_arc(p, r, 0, TAU, 32, col, 2.5)
	# Crosshair ticks.
	draw_line(p + Vector2(-r - 6, 0), p + Vector2(-r + 8, 0), col, 2.0)
	draw_line(p + Vector2(r - 8, 0), p + Vector2(r + 6, 0), col, 2.0)
	draw_line(p + Vector2(0, -r - 6), p + Vector2(0, -r + 8), col, 2.0)
	draw_line(p + Vector2(0, r - 8), p + Vector2(0, r + 6), col, 2.0)
	draw_circle(p, 2.5, col)

func _draw_hud_text() -> void:
	var font := get_theme_default_font()
	var fs := 20
	draw_string(font, Vector2(24, 34), "SCORE  %d" % Globals.score, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT)
	var wave_str := "WAVE  %d" % Globals.current_wave
	var wsize := font.get_string_size(wave_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, Vector2(size.x - wsize.x - 24, 34), wave_str, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, C_TEXT)

func _draw_health() -> void:
	# Read live from the player so heals/damage show instantly.
	var p := Globals.player
	if p and is_instance_valid(p) and "health" in p:
		health = p.health
		max_health = p.max_health
	var pip_w := 26.0
	var gap := 6.0
	var start := Vector2(24, 52)
	for i in max_health:
		var c := C_HEALTH if i < health else C_HEALTH_EMPTY
		draw_rect(Rect2(start + Vector2(i * (pip_w + gap), 0), Vector2(pip_w, 8)), c)

const PU_COLORS := {
	"rapid": Color(1.0, 0.6, 0.12),
	"spread": Color(0.2, 0.9, 1.0),
	"shield": Color(0.35, 0.55, 1.0),
}

func _draw_powerups() -> void:
	var p := Globals.player
	if p == null or not is_instance_valid(p) or not p.has_method("get_powerups"):
		return
	var pus: Dictionary = p.get_powerups()
	if pus.is_empty():
		return
	var font := get_theme_default_font()
	var i := 0
	for k in pus.keys():
		var frac: float = p.powerup_fraction(k)
		var col: Color = PU_COLORS.get(k, Color.WHITE)
		var by := 70.0 + i * 22.0
		draw_rect(Rect2(Vector2(24, by), Vector2(96, 13)), Color(0.1, 0.12, 0.16, 0.6))
		draw_rect(Rect2(Vector2(24, by), Vector2(96 * frac, 13)), col)
		draw_string(font, Vector2(128, by + 12), str(k).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, col)
		i += 1

## Arrows pointing toward drones that are currently off-screen, so the pilot
## always knows where the swarm is in 360° space.
func _draw_offscreen_arrows() -> void:
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var center := size * 0.5
	for drone in get_tree().get_nodes_in_group("enemy"):
		if not is_instance_valid(drone):
			continue
		var wpos: Vector3 = drone.global_position
		var behind := cam.is_position_behind(wpos)
		var screen := cam.unproject_position(wpos)
		var on_screen := not behind and Rect2(Vector2.ZERO, size).has_point(screen)
		if on_screen:
			continue
		# Direction from center toward the (possibly behind) target.
		var dir := (screen - center)
		if behind:
			dir = -dir
		if dir.length_squared() < 1.0:
			continue
		dir = dir.normalized()
		var at := center + dir * arrow_ring
		_draw_arrow(at, dir, C_ARROW)

func _draw_arrow(at: Vector2, dir: Vector2, col: Color) -> void:
	var perp := Vector2(-dir.y, dir.x)
	var tip := at + dir * 12.0
	var a := at - dir * 6.0 + perp * 7.0
	var b := at - dir * 6.0 - perp * 7.0
	draw_colored_polygon(PackedVector2Array([tip, a, b]), col)

func _draw_centered_text(text: String, pos: Vector2, font_size: int, col: Color) -> void:
	var font := get_theme_default_font()
	var ssize := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size)
	draw_string(font, pos - ssize * 0.5 + Vector2(0, ssize.y * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, col)
