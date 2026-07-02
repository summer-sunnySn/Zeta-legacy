## Zeta Legacy — Comic Cutscene Player
## Plays a sequence of graphic-novel panels (image + caption) full-screen with a
## slow Ken-Burns drift, cinematic letterbox, a typed caption box and tap-to-
## advance. JPEG panels are runtime-loaded (the editor importer is broken on this
## device). Which sequence to play + where to go next come from Globals so the
## same scene is reusable for every chapter beat.
extends Control

const ComicData = preload("res://scripts/story/comic_data.gd")

@onready var panel: TextureRect = $Panel
@onready var fade: ColorRect = $Fade
@onready var caption: RichTextLabel = $CaptionBox/Caption
@onready var speaker: Label = $CaptionBox/Speaker
@onready var caption_box: Control = $CaptionBox
@onready var tap_hint: Label = $CaptionBox/TapHint
@onready var skip_btn: Button = $SkipButton

const SPEAKER_COL := {
	"CMDR ELENA": Color(1.0, 0.45, 0.45),
	"COMMANDER":  Color(0.95, 0.80, 0.40),
	"ARIA":       Color(0.40, 0.85, 1.0),
	"???":        Color(0.85, 0.45, 1.0),
}

var _seq: Array = []
var _next_scene: String = "res://scenes/story/moon_surface.tscn"
var _tap_pending: bool = false
var _skip: bool = false
var _done: bool = false

func _ready() -> void:
	clip_contents = true
	var id: String = ""
	if "comic_id" in Globals:
		id = Globals.comic_id
	if "comic_next" in Globals and Globals.comic_next != "":
		_next_scene = Globals.comic_next
	_seq = ComicData.get_sequence(id)
	skip_btn.pressed.connect(_on_skip)
	fade.color = Color(0, 0, 0, 1)
	caption_box.modulate.a = 0.0
	_play.call_deferred()

func _play() -> void:
	for i in _seq.size():
		if _skip:
			break
		await _show_panel(_seq[i])
		if _skip:
			break
	_finish()

func _show_panel(entry: Dictionary) -> void:
	# Load + assign the panel image (runtime JPEG).
	var tex := _load_tex(entry.get("img", ""))
	if tex:
		panel.texture = tex
	# Reset Ken-Burns transform and fade in from black.
	panel.pivot_offset = size * 0.5
	panel.scale = Vector2(1.04, 1.04)
	panel.position = Vector2.ZERO
	# Slow drift for the whole beat (zoom + gentle pan).
	var drift := create_tween().set_trans(Tween.TRANS_SINE)
	drift.tween_property(panel, "scale", Vector2(1.12, 1.12), 7.0)
	drift.parallel().tween_property(panel, "position", Vector2(-24, -14), 7.0)

	# Caption.
	var who := str(entry.get("who", ""))
	if who != "":
		speaker.text = who
		speaker.add_theme_color_override("font_color", SPEAKER_COL.get(who, Color.WHITE))
		speaker.visible = true
		caption.text = "[i]“%s”[/i]" % str(entry.get("text", ""))
	else:
		speaker.visible = false
		caption.text = str(entry.get("text", ""))

	# Fade picture in, then slide the caption up.
	await _fade_to(0.0, 0.6)
	create_tween().tween_property(caption_box, "modulate:a", 1.0, 0.4)
	tap_hint.visible = true

	# Hold for a tap (with a debounce so one tap can't skip two panels).
	_tap_pending = false
	await get_tree().create_timer(0.35).timeout
	while not _consume_tap() and not _skip:
		await get_tree().process_frame

	# Out: drop the caption, fade to black for the cut.
	create_tween().tween_property(caption_box, "modulate:a", 0.0, 0.25)
	if not _skip:
		await _fade_to(1.0, 0.45)

func _finish() -> void:
	if _done:
		return
	_done = true
	await _fade_to(1.0, 0.4)
	get_tree().change_scene_to_file(_next_scene)

# ─── Runtime JPEG/PNG loading ────────────────────────────────────────────────
func _load_tex(file: String) -> Texture2D:
	if file == "":
		return null
	var path := ComicData.DIR + file
	var bytes := FileAccess.get_file_as_bytes(path)
	if bytes.is_empty():
		push_warning("ComicCutscene: missing panel '%s'" % path)
		return null
	var img := Image.new()
	var err := img.load_jpg_from_buffer(bytes)
	if err != OK:
		err = img.load_png_from_buffer(bytes)
	if err != OK:
		return null
	return ImageTexture.create_from_image(img)

# ─── Transitions / input ─────────────────────────────────────────────────────
func _fade_to(target_a: float, dur: float) -> void:
	var tw := create_tween()
	tw.tween_property(fade, "color:a", target_a, dur)
	await tw.finished

func _consume_tap() -> bool:
	if _tap_pending:
		_tap_pending = false
		return true
	return false

func _input(event: InputEvent) -> void:
	if _done:
		return
	if (event is InputEventScreenTouch and event.pressed) \
			or (event is InputEventMouseButton and event.pressed) \
			or (event is InputEventKey and event.pressed):
		_tap_pending = true

func _on_skip() -> void:
	_skip = true
	_tap_pending = true
