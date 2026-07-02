## Zeta Legacy — On-foot HUD (holographic wrist panel)
## Owns touch input for Alina's Moon mission and draws the suit read-outs.
## Exposed to alina.gd / foot_camera.gd:
##   get_move_vector() -> Vector2   left stick (y+ = forward)
##   consume_look()     -> Vector2   right-drag camera delta (then resets)
##   consume_jump()     -> bool      one-shot
##   consume_shield()   -> bool      one-shot
##   firing             : bool       FIRE held
##   fly_held           : bool       FLY held
extends Control

signal restart_pressed

# Public input state.
var firing: bool = false
var fly_held: bool = false

# Internal input.
var _move_vec: Vector2 = Vector2.ZERO
var _look_accum: Vector2 = Vector2.ZERO
var _jump_q: bool = false
var _shield_q: bool = false

var _move_touch: int = -1
var _move_origin: Vector2 = Vector2.ZERO
var _look_touch: int = -1
var _look_last: Vector2 = Vector2.ZERO
var _fire_touch: int = -1
var _fly_touch: int = -1

@export var stick_radius: float = 110.0
@export var fire_radius: float = 68.0
@export var btn_radius: float = 50.0

var _objective: String = ""
var _state: int = 0           ## 0 play, 1 win, 2 lose
var _banner_t: float = 0.0

# Colors — cyan holographic.
const C_HOLO := Color(0.4, 0.9, 1.0)
const C_DIM := Color(0.4, 0.9, 1.0, 0.35)
const C_HP := Color(0.4, 1.0, 0.55)
const C_EN := Color(0.5, 0.8, 1.0)
const C_O2 := Color(0.7, 0.95, 1.0)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP

func _process(_delta: float) -> void:
	queue_redraw()
	if _banner_t > 0.0:
		_banner_t = maxf(0.0, _banner_t - _delta)

# ─── Public API ─────────────────────────────────────────────────────────
func get_move_vector() -> Vector2:
	return Vector2(_move_vec.x, -_move_vec.y)

func consume_look() -> Vector2:
	var v := _look_accum
	_look_accum = Vector2.ZERO
	return v

func consume_jump() -> bool:
	var v := _jump_q
	_jump_q = false
	return v

func consume_shield() -> bool:
	var v := _shield_q
	_shield_q = false
	return v

func show_objective(text: String) -> void:
	_objective = text
	_banner_t = 3.5

func show_win() -> void:
	_state = 1
	firing = false; fly_held = false

func show_lose() -> void:
	_state = 2
	firing = false; fly_held = false

# ─── Button anchors ─────────────────────────────────────────────────────
func _stick_base() -> Vector2:
	return Vector2(150.0, size.y - 150.0)
func _fire_center() -> Vector2:
	return Vector2(size.x - 110.0, size.y - 110.0)
func _fly_center() -> Vector2:
	return Vector2(size.x - 110.0, size.y - 256.0)
func _shield_center() -> Vector2:
	return Vector2(size.x - 252.0, size.y - 110.0)
func _jump_center() -> Vector2:
	return Vector2(size.x - 252.0, size.y - 250.0)

# ─── Input ──────────────────────────────────────────────────────────────
func _gui_input(event: InputEvent) -> void:
	if _state != 0:
		var tap: bool = (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed)
		if tap:
			restart_pressed.emit()
		return

	if event is InputEventScreenTouch:
		_touch(event.index, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position, event.relative)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_touch(0, event.position, event.pressed)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT):
		_drag(0, event.position, event.relative)

func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		if pos.distance_to(_fire_center()) <= fire_radius and _fire_touch == -1:
			_fire_touch = index; firing = true; return
		if pos.distance_to(_fly_center()) <= btn_radius and _fly_touch == -1:
			_fly_touch = index; fly_held = true; return
		if pos.distance_to(_shield_center()) <= btn_radius:
			_shield_q = true; return
		if pos.distance_to(_jump_center()) <= btn_radius:
			_jump_q = true; return
		# Left half → move stick. Right half → camera look.
		if pos.x < size.x * 0.5 and _move_touch == -1:
			_move_touch = index; _move_origin = pos; _move_vec = Vector2.ZERO
		elif _look_touch == -1:
			_look_touch = index; _look_last = pos
	else:
		if index == _fire_touch:
			_fire_touch = -1; firing = false
		elif index == _fly_touch:
			_fly_touch = -1; fly_held = false
		elif index == _move_touch:
			_move_touch = -1; _move_vec = Vector2.ZERO
		elif index == _look_touch:
			_look_touch = -1

func _drag(index: int, pos: Vector2, rel: Vector2) -> void:
	if index == _move_touch:
		_move_vec = ((pos - _move_origin) / stick_radius).limit_length(1.0)
	elif index == _look_touch:
		_look_accum += rel

# ─── Draw ───────────────────────────────────────────────────────────────
func _draw() -> void:
	_draw_stick()
	_draw_fire()
	_draw_round_btn(_fly_center(), "FLY", C_HOLO, fly_held)
	_draw_round_btn(_shield_center(), "SHIELD", Color(0.5, 0.7, 1.0), _player_shielding())
	_draw_round_btn(_jump_center(), "JUMP", Color(0.6, 0.9, 1.0), false)
	_draw_suit_panel()
	_draw_banner()
	_draw_state()

func _player_shielding() -> bool:
	var p := Globals.player
	return p != null and is_instance_valid(p) and p.has_method("is_shielding") and p.is_shielding()

func _draw_stick() -> void:
	var base := _stick_base()
	if _move_touch != -1:
		base = _move_origin
	draw_arc(base, stick_radius, 0, TAU, 40, C_DIM, 2.0)
	draw_circle(base, stick_radius, Color(0.4, 0.9, 1.0, 0.06))
	draw_circle(base + _move_vec * stick_radius, 30.0, Color(0.4, 0.9, 1.0, 0.6))

func _draw_fire() -> void:
	var c := _fire_center()
	var col := Color(1.0, 0.4, 0.35) if firing else Color(1.0, 0.5, 0.4, 0.7)
	draw_circle(c, fire_radius, Color(col.r, col.g, col.b, 0.14))
	draw_arc(c, fire_radius, 0, TAU, 36, col, 3.0)
	_text_center("FIRE", c, 20, col)

func _draw_round_btn(c: Vector2, label: String, accent: Color, active: bool) -> void:
	var a := 0.9 if active else 0.55
	var col := Color(accent.r, accent.g, accent.b, a)
	draw_circle(c, btn_radius, Color(accent.r, accent.g, accent.b, 0.16 if active else 0.08))
	draw_arc(c, btn_radius, 0, TAU, 32, col, 2.5)
	_text_center(label, c, 15, col)

## Holographic suit read-out top-left: health pips, ENERGY, OXYGEN.
func _draw_suit_panel() -> void:
	var p := Globals.player
	var hp := 8
	var maxhp := 8
	var en := 1.0
	var o2 := 1.0
	if p and is_instance_valid(p):
		if "health" in p: hp = p.health
		if "max_health" in p: maxhp = p.max_health
		if p.has_method("energy_fraction"): en = p.energy_fraction()
		if p.has_method("oxygen_fraction"): o2 = p.oxygen_fraction()

	var font := get_theme_default_font()
	var x := 26.0
	var y := 28.0
	draw_string(font, Vector2(x, y), "ALINA · ARIA", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_HOLO)
	# Health pips.
	for i in maxhp:
		var col := C_HP if i < hp else Color(0.2, 0.3, 0.35, 0.6)
		draw_rect(Rect2(Vector2(x + i * 22.0, y + 10.0), Vector2(18.0, 7.0)), col)
	# Energy + oxygen bars.
	_bar(Vector2(x, y + 28.0), 180.0, en, C_EN, "ENERGY")
	_bar(Vector2(x, y + 50.0), 180.0, o2, C_O2, "O₂")
	# Score (reuses Globals).
	draw_string(font, Vector2(x, y + 86.0), "SCORE  %d" % Globals.score, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, C_HOLO)

func _bar(pos: Vector2, w: float, frac: float, col: Color, label: String) -> void:
	draw_rect(Rect2(pos, Vector2(w, 12.0)), Color(0.1, 0.16, 0.2, 0.6))
	draw_rect(Rect2(pos, Vector2(w * clampf(frac, 0.0, 1.0), 12.0)), col)
	var font := get_theme_default_font()
	draw_string(font, pos + Vector2(w + 8.0, 11.0), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 12, col)

func _draw_banner() -> void:
	if _banner_t <= 0.0 or _objective == "":
		return
	var a := clampf(_banner_t, 0.0, 1.0)
	_text_center("OBJECTIVE", Vector2(size.x * 0.5, 50.0), 14, Color(0.5, 0.8, 1.0, a))
	_text_center(_objective, Vector2(size.x * 0.5, 74.0), 22, Color(0.9, 0.97, 1.0, a))

func _draw_state() -> void:
	if _state == 0:
		return
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.0, 0.02, 0.05, 0.6))
	if _state == 1:
		_text_center("AREA SECURED", size * 0.5 + Vector2(0, -20), 40, C_HP)
		_text_center("Alina lives to fight on.", size * 0.5 + Vector2(0, 20), 18, C_HOLO)
	else:
		_text_center("ALINA DOWN", size * 0.5 + Vector2(0, -20), 40, Color(1.0, 0.4, 0.4))
		_text_center("TAP TO RETRY", size * 0.5 + Vector2(0, 24), 18, C_HOLO)

func _text_center(text: String, pos: Vector2, fs: int, col: Color) -> void:
	var font := get_theme_default_font()
	var ss := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, pos - ss * 0.5 + Vector2(0, ss.y * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
