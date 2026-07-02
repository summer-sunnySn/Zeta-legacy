## Zeta Legacy — Main Menu / Mode Select
## The new entry point. Routes to the Story campaign or the Arcade dogfight.
## Fully procedural (no image assets): animated starfield, glowing title,
## two big touch/click buttons.
extends Control

# Story routes to the Chapter 1 intro once built; falls back to the playable
# Moon mission so the button is never dead during development.
const STORY_SCENE := "res://scenes/story/comic_cutscene.tscn"
const STORY_FALLBACK := "res://scenes/story/moon_surface.tscn"
const ARCADE_SCENE := "res://scenes/arcade/ship_select.tscn"
const MISSION_SCENE := "res://scenes/mission/planet_select.tscn"

var _t: float = 0.0
var _stars: Array = []          ## {x, y, z, tw}
var _hover: int = -1            ## which button the pointer is over (0 story, 1 arcade)

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_seed_stars()

func _seed_stars() -> void:
	_stars.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 150:
		_stars.append({
			"x": rng.randf(), "y": rng.randf(),
			"z": rng.randf_range(0.2, 1.0),
			"tw": rng.randf_range(0.0, TAU),
		})

func _process(delta: float) -> void:
	_t += delta
	queue_redraw()

# ─── Layout ─────────────────────────────────────────────────────────────
func _btn_rect(row: int) -> Rect2:
	var w := minf(420.0, size.x - 80.0)
	return Rect2(size.x * 0.5 - w * 0.5, size.y * 0.50 + row * 76.0, w, 60.0)

func _story_rect() -> Rect2:   return _btn_rect(0)
func _mission_rect() -> Rect2: return _btn_rect(1)
func _arcade_rect() -> Rect2:  return _btn_rect(2)

# ─── Input ──────────────────────────────────────────────────────────────
func _gui_input(event: InputEvent) -> void:
	var p := Vector2.ZERO
	var down := false
	if event is InputEventScreenTouch and event.pressed:
		p = event.position; down = true
	elif event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		p = event.position; down = true
	elif event is InputEventMouseMotion:
		_hover = _button_at(event.position)
		return
	if down:
		var b := _button_at(p)
		if b == 0:
			# Always start Story at the Chapter 1 intro comic → moon mission.
			Globals.comic_id = "chapter1_intro"
			Globals.comic_next = "res://scenes/story/moon_surface.tscn"
			_launch(STORY_SCENE if ResourceLoader.exists(STORY_SCENE) else STORY_FALLBACK)
		elif b == 1:
			_launch(MISSION_SCENE)
		elif b == 2:
			_launch(ARCADE_SCENE)

func _button_at(p: Vector2) -> int:
	if _story_rect().has_point(p): return 0
	if _mission_rect().has_point(p): return 1
	if _arcade_rect().has_point(p): return 2
	return -1

func _launch(path: String) -> void:
	if ResourceLoader.exists(path):
		Audio.play("wave", -4.0)
		get_tree().change_scene_to_file(path)
	else:
		push_warning("Scene not found yet: " + path)

# ─── Drawing ────────────────────────────────────────────────────────────
func _draw() -> void:
	# Backdrop gradient.
	draw_rect(Rect2(Vector2.ZERO, size), Color(0.02, 0.02, 0.06))
	# Aurora glow.
	_draw_glow(Vector2(size.x * 0.3, size.y * 0.25), 320.0, Color(0.3, 0.2, 0.7, 0.18))
	_draw_glow(Vector2(size.x * 0.75, size.y * 0.2), 280.0, Color(0.15, 0.5, 0.9, 0.16))
	_draw_stars()
	_draw_title()
	_draw_button(_story_rect(), "STORY MODE", "Chapter 1 — The Silent Moon", Color(0.3, 0.85, 1.0), _hover == 0)
	_draw_button(_mission_rect(), "MISSION MODE", "Alina's rise — 4 planets, 12 missions", Color(1.0, 0.7, 0.3), _hover == 1)
	_draw_button(_arcade_rect(), "ARCADE", "Endless space dogfight", Color(0.6, 0.7, 1.0), _hover == 2)

	var font := get_theme_default_font()
	_center(font, "2031 · Earth's last hope", Vector2(size.x * 0.5, size.y - 36.0), 14, Color(0.5, 0.6, 0.8, 0.7))

func _draw_glow(c: Vector2, r: float, col: Color) -> void:
	for i in 6:
		var f := 1.0 - float(i) / 6.0
		draw_circle(c, r * (0.4 + 0.6 * (float(i) / 6.0)), Color(col.r, col.g, col.b, col.a * f * 0.4))

func _draw_stars() -> void:
	for s in _stars:
		var px: float = s["x"] * size.x
		var py: float = fmod(s["y"] * size.y + _t * s["z"] * 12.0, size.y)
		var tw: float = 0.55 + 0.45 * sin(_t * 1.6 + s["tw"])
		var r: float = s["z"] * 1.7
		draw_circle(Vector2(px, py), r, Color(0.7, 0.85, 1.0, 0.25 + s["z"] * 0.55 * tw))

func _draw_title() -> void:
	var font := get_theme_default_font()
	var cx := size.x * 0.5
	var bob := sin(_t * 1.2) * 3.0
	# Glow pass.
	for i in 3:
		var a := 0.10 - i * 0.03
		_center(font, "ZETA LEGACY", Vector2(cx, size.y * 0.30 + bob), 72 + i * 4, Color(0.3, 0.8, 1.0, a))
	_center(font, "ZETA LEGACY", Vector2(cx, size.y * 0.30 + bob), 72, Color(0.85, 0.95, 1.0))
	_center(font, "◆  A 360° CINEMATIC SPACE WAR  ◆", Vector2(cx, size.y * 0.30 + 56.0 + bob), 17, Color(0.4, 0.7, 0.95, 0.8))

func _draw_button(r: Rect2, label: String, sub: String, accent: Color, hover: bool) -> void:
	var bg := Color(accent.r, accent.g, accent.b, 0.16 if hover else 0.09)
	draw_rect(r, bg)
	draw_rect(r, accent if hover else Color(accent.r, accent.g, accent.b, 0.6), false, 2.5)
	var font := get_theme_default_font()
	# Accent bar on the left.
	draw_rect(Rect2(r.position, Vector2(5, r.size.y)), accent)
	draw_string(font, r.position + Vector2(26, 34), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color(0.92, 0.98, 1.0))
	draw_string(font, r.position + Vector2(26, 54), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.72, 0.9, 0.85))
	# Play chevron.
	var cy := r.position.y + r.size.y * 0.5
	var cx := r.position.x + r.size.x - 30.0
	draw_colored_polygon(PackedVector2Array([
		Vector2(cx, cy - 9), Vector2(cx + 13, cy), Vector2(cx, cy + 9)
	]), accent)

func _center(font: Font, text: String, pos: Vector2, fs: int, col: Color) -> void:
	var ss := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs)
	draw_string(font, pos - ss * 0.5 + Vector2(0, ss.y * 0.5), text, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, col)
