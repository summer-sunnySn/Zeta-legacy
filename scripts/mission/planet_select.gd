## Zeta Legacy — Planet / Mission Select (Mission Mode)
## Browse the four solar-system fronts with a live rotating anime planet, pick a
## mission (showing which are already cleared), then launch it. Reached from the
## main menu's MISSION button.
extends Node3D

const MissionData = preload("res://scripts/mission/mission_data.gd")
const MISSION_SCENE := "res://scenes/mission/mission.tscn"
const MENU_SCENE := "res://scenes/boot/main_menu.tscn"

@onready var preview: Node3D = $Preview
@onready var name_label: Label = $UILayer/UI/PlanetName
@onready var subtitle: Label = $UILayer/UI/Subtitle
@onready var desc: Label = $UILayer/UI/MDesc

var _p: int = 0
var _btns: Array[Button] = []

func _ready() -> void:
	Gfx.apply($WorldEnvironment, $Sun)
	_p = clampi(Globals.mission_planet, 0, MissionData.planet_count() - 1)
	_btns = [$UILayer/UI/M0, $UILayer/UI/M1, $UILayer/UI/M2, $UILayer/UI/M3, $UILayer/UI/M4]
	for i in _btns.size():
		_btns[i].pressed.connect(_play.bind(i))
	$UILayer/UI/Prev.pressed.connect(func(): _step())
	$UILayer/UI/Back.pressed.connect(func(): get_tree().change_scene_to_file(MENU_SCENE))
	_show()

func _process(delta: float) -> void:
	if preview:
		preview.rotate_y(delta * 0.5)

func _step() -> void:
	_p = wrapi(_p + 1, 0, MissionData.planet_count())
	Audio.play("shoot", -10.0, 0.2)
	_show()

func _show() -> void:
	var pl: Dictionary = MissionData.get_planet(_p)
	name_label.text = pl.get("name", "PLANET")
	name_label.add_theme_color_override("font_color", pl.get("atmo", Color.WHITE))
	subtitle.text = pl.get("subtitle", "")
	desc.text = ""

	# Rebuild the rotating preview planet.
	for c in preview.get_children():
		c.queue_free()
	preview.configure(pl, 3.0)

	# Fill the mission buttons (lock missions until the previous one is done).
	var missions: Array = pl.get("missions", [])
	for i in _btns.size():
		var b := _btns[i]
		if i >= missions.size():
			b.visible = false
			continue
		b.visible = true
		var done: bool = Save.is_mission_done(MissionData.mission_key(_p, i))
		var locked: bool = i > 0 and not Save.is_mission_done(MissionData.mission_key(_p, i - 1))
		var tag := "✓ " if done else ("🔒 " if locked else "")
		b.text = "%s%d. %s" % [tag, i + 1, missions[i].get("name", "Mission")]
		b.disabled = locked

func _play(m: int) -> void:
	var pl: Dictionary = MissionData.get_planet(_p)
	if m >= pl.get("missions", []).size():
		return
	if _btns[m].disabled:
		return
	Globals.mission_planet = _p
	Globals.mission_index = m
	Audio.play("wave", -4.0)
	# A mission can supply its own bespoke scene (e.g. the Mars bike recovery);
	# otherwise the shared flight-mission scene runs. An optional comic briefing
	# plays first.
	var mission: Dictionary = MissionData.get_mission(_p, m)
	var scene: String = mission.get("scene", "")
	var dest: String = scene if (scene != "" and ResourceLoader.exists(scene)) else MISSION_SCENE
	var comic: String = mission.get("comic", "")
	if comic != "":
		Globals.comic_id = comic
		Globals.comic_next = dest
		get_tree().change_scene_to_file("res://scenes/story/comic_cutscene.tscn")
	else:
		get_tree().change_scene_to_file(dest)
