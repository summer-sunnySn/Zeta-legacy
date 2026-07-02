## Zeta Legacy — Cinematic Subtitle Box
## Bottom-screen speaker + line display for story cutscenes.  Fully procedural
## (no image assets): a translucent panel, speaker tag and a typewriter line.
## The director calls `show_line()`; voice-over audio is layered in later by
## matching each line's `key` to a future VO clip.
extends Control

# ─── Tuning ──────────────────────────────────────────────────────────────
@export var type_speed: float = 48.0        ## characters revealed per second
@export var fade_time: float = 0.25
@export var margin_bottom: float = 64.0
@export var box_width_frac: float = 0.82

# ─── State ───────────────────────────────────────────────────────────────
var _speaker: String = ""
var _line: String = ""
var _accent: Color = Color(0.4, 0.85, 1.0)
var _revealed: float = 0.0
var _alpha: float = 0.0
var _target_alpha: float = 0.0
var _hint: bool = false          ## show the blinking "tap to continue" arrow
var _blink: float = 0.0          ## time accumulator for the arrow blink

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false

func _process(delta: float) -> void:
	if _revealed < float(_line.length()):
		_revealed = minf(_revealed + type_speed * delta, float(_line.length()))
	_alpha = move_toward(_alpha, _target_alpha, delta / maxf(fade_time, 0.01))
	if _alpha <= 0.001 and _target_alpha <= 0.0:
		visible = false
	_blink += delta
	queue_redraw()

## Toggle the blinking "▼ tap" prompt shown once a line is fully typed and the
## director is waiting for the player to tap to advance.
func set_continue_hint(on: bool) -> void:
	_hint = on

## Show one subtitle line.  `accent` tints the speaker tag per character.
func show_line(speaker: String, line: String, accent: Color = Color(0.4, 0.85, 1.0)) -> void:
	_speaker = speaker
	_line = line
	_accent = accent
	_revealed = 0.0
	_target_alpha = 1.0
	visible = true

## Instantly reveal the full current line (used when the player skips ahead).
func reveal_now() -> void:
	_revealed = float(_line.length())

func hide_line() -> void:
	_target_alpha = 0.0

func is_typing() -> bool:
	return _revealed < float(_line.length())

# ─── Drawing ─────────────────────────────────────────────────────────────
func _draw() -> void:
	if _alpha <= 0.001:
		return
	var font := get_theme_default_font()
	var box_w := size.x * box_width_frac
	var box_h := 96.0
	var box_x := (size.x - box_w) * 0.5
	var box_y := size.y - margin_bottom - box_h

	# Panel backdrop.
	var bg := Color(0.02, 0.03, 0.06, 0.82 * _alpha)
	draw_rect(Rect2(box_x, box_y, box_w, box_h), bg)
	# Accent bar on the left edge.
	draw_rect(Rect2(box_x, box_y, 4.0, box_h), Color(_accent.r, _accent.g, _accent.b, _alpha))
	# Thin frame.
	draw_rect(Rect2(box_x, box_y, box_w, box_h), Color(_accent.r, _accent.g, _accent.b, 0.45 * _alpha), false, 1.5)

	# Speaker tag.
	if _speaker != "":
		draw_string(font, Vector2(box_x + 20.0, box_y + 28.0), _speaker,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(_accent.r, _accent.g, _accent.b, _alpha))

	# Typewriter line (clip to revealed character count).
	var shown := _line.substr(0, int(_revealed))
	draw_string(font, Vector2(box_x + 20.0, box_y + 60.0), shown,
		HORIZONTAL_ALIGNMENT_LEFT, box_w - 40.0, 20, Color(0.92, 0.96, 1.0, _alpha))

	# Blinking "tap to continue" prompt (bottom-right of the panel).
	if _hint:
		var pulse := 0.5 + 0.5 * sin(_blink * 6.0)
		var tx := box_x + box_w - 116.0
		var ty := box_y + box_h - 16.0
		draw_string(font, Vector2(tx, ty), "tap  ▼",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
			Color(_accent.r, _accent.g, _accent.b, _alpha * (0.35 + 0.65 * pulse)))
