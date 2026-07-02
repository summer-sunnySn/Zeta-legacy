## Zeta Legacy — Ship Select Screen
## Browse the arcade ship roster with a live, rotating 3D preview lit by the
## full Forward+ environment, read each ship's stats, toggle graphics quality,
## then launch the arcade with the chosen ship. Reached from the main menu.
extends Node3D

const ShipRoster = preload("res://scripts/arcade/ship_roster.gd")

const ARCADE_SCENE := "res://scenes/main.tscn"
const MENU_SCENE := "res://scenes/boot/main_menu.tscn"

@onready var pedestal: Node3D = $Pedestal
@onready var name_label: Label = $UILayer/UI/Name
@onready var desc_label: Label = $UILayer/UI/Desc
@onready var stats_label: Label = $UILayer/UI/Stats
@onready var quality_btn: Button = $UILayer/UI/Quality

var _idx: int = 0
var _model: Node3D = null

func _ready() -> void:
	Gfx.apply($WorldEnvironment, $Sun)
	_idx = clampi(Save.selected_ship, 0, ShipRoster.count() - 1)
	$UILayer/UI/Prev.pressed.connect(func(): _step(-1))
	$UILayer/UI/Next.pressed.connect(func(): _step(1))
	$UILayer/UI/Launch.pressed.connect(_launch)
	$UILayer/UI/Back.pressed.connect(_back)
	quality_btn.pressed.connect(_cycle_quality)
	quality_btn.text = "Quality: " + Gfx.LABELS[Gfx.current()]
	_show()

func _process(delta: float) -> void:
	if pedestal:
		pedestal.rotate_y(delta * 0.6)

func _step(dir: int) -> void:
	_idx = wrapi(_idx + dir, 0, ShipRoster.count())
	Audio.play("shoot", -10.0, 0.2)
	_show()

func _show() -> void:
	var ship: Dictionary = ShipRoster.get_ship(_idx)
	name_label.text = ship.get("name", "SHIP")
	name_label.add_theme_color_override("font_color", ship.get("accent", Color.WHITE))
	desc_label.text = ship.get("desc", "")
	stats_label.text = _stat_bars(ship)

	# Rebuild the rotating preview.
	if _model and is_instance_valid(_model):
		_model.queue_free()
	_model = null
	var path: String = ship.get("model", "")
	if path != "" and ResourceLoader.exists(path):
		var packed: PackedScene = load(path)
		if packed:
			_model = packed.instantiate()
			pedestal.add_child(_model)
			_model.transform = Transform3D.IDENTITY
			_fit_model(_model, 3.6)
			_model.rotate_y(PI)

## Render each stat as a 5-pip bar relative to a sensible range.
func _stat_bars(ship: Dictionary) -> String:
	var spd := _pips(float(ship.get("speed", 1.0)), 0.7, 1.5)
	var fr := _pips(2.0 - float(ship.get("fire", 1.0)), 0.8, 1.3)   # lower fire = faster
	var hp := _pips(6.0 + float(ship.get("health", 0)), 4.0, 9.0)
	var dmg := _pips(1.0 + float(ship.get("damage", 0)), 1.0, 2.0)
	return "SPEED  %s\nFIRE   %s\nHEALTH %s\nDAMAGE %s" % [spd, fr, hp, dmg]

func _pips(v: float, lo: float, hi: float) -> String:
	var n := int(round(remap(clampf(v, lo, hi), lo, hi, 1.0, 5.0)))
	return "●".repeat(n) + "○".repeat(5 - n)

func _cycle_quality() -> void:
	quality_btn.text = "Quality: " + Gfx.cycle()
	Gfx.apply($WorldEnvironment, $Sun)
	Audio.play("powerup", -10.0, 0.2)

func _launch() -> void:
	Save.set_selected_ship(_idx)
	Audio.play("wave", -4.0)
	get_tree().change_scene_to_file(ARCADE_SCENE)

func _back() -> void:
	get_tree().change_scene_to_file(MENU_SCENE)

# ─── Model fitting (auto-centre + scale any GLB) ──────────────────────────
func _fit_model(model: Node3D, target_len: float) -> void:
	var inv := model.global_transform.affine_inverse()
	var merged := AABB()
	var first := true
	for mi in _all_mesh_instances(model):
		var rel: Transform3D = inv * mi.global_transform
		var a: AABB = rel * mi.get_aabb()
		if first:
			merged = a
			first = false
		else:
			merged = merged.merge(a)
	if first or merged.size == Vector3.ZERO:
		return
	var longest := maxf(merged.size.x, maxf(merged.size.y, merged.size.z))
	var s := target_len / maxf(longest, 0.001)
	model.scale = Vector3(s, s, s)
	model.position = -merged.get_center() * s

func _all_mesh_instances(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for c in node.get_children():
		out.append_array(_all_mesh_instances(c))
	return out
