## Zeta Legacy — Persistent Save Data (autoload "Save")
## High score, credits (meta-currency), and permanent upgrade levels.
extends Node

const PATH := "user://zeta_save.cfg"
const MAX_LEVEL := 5
const UPGRADES := ["firerate", "health", "damage", "bombs"]

var high_score: int = 0
var credits: int = 0
var upgrades: Dictionary = {"firerate": 0, "health": 0, "damage": 0, "bombs": 0}

# Player settings.
var quality: int = 2          ## 0 = Low, 1 = Medium, 2 = Ultra (default)
var selected_ship: int = 0    ## index into the arcade ship roster

# Mission Mode progress: set of completed mission keys ("earth:0", ...).
var missions_done: Dictionary = {}

func _ready() -> void:
	load_data()

func load_data() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(PATH) != OK:
		return
	high_score = int(cfg.get_value("data", "high_score", 0))
	credits = int(cfg.get_value("data", "credits", 0))
	for k in UPGRADES:
		upgrades[k] = int(cfg.get_value("upg", k, 0))
	quality = int(cfg.get_value("settings", "quality", 2))
	selected_ship = int(cfg.get_value("settings", "selected_ship", 0))
	missions_done = cfg.get_value("missions", "done", {})

func save_data() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("data", "high_score", high_score)
	cfg.set_value("data", "credits", credits)
	for k in UPGRADES:
		cfg.set_value("upg", k, upgrades[k])
	cfg.set_value("settings", "quality", quality)
	cfg.set_value("settings", "selected_ship", selected_ship)
	cfg.set_value("missions", "done", missions_done)
	cfg.save(PATH)

func mark_mission_done(key: String) -> void:
	missions_done[key] = true
	save_data()

func is_mission_done(key: String) -> bool:
	return missions_done.get(key, false)

func set_quality(q: int) -> void:
	quality = clampi(q, 0, 2)
	save_data()

func set_selected_ship(idx: int) -> void:
	selected_ship = maxi(0, idx)
	save_data()

## Call when a run ends: bank credits and update the high score.
func on_run_ended(score: int) -> void:
	credits += int(score / 10.0)
	if score > high_score:
		high_score = score
	save_data()

func upgrade_cost(key: String) -> int:
	return 120 * (int(upgrades.get(key, 0)) + 1)

func upgrade_level(key: String) -> int:
	return int(upgrades.get(key, 0))

func can_buy(key: String) -> bool:
	return upgrade_level(key) < MAX_LEVEL and credits >= upgrade_cost(key)

func buy(key: String) -> bool:
	if not can_buy(key):
		return false
	credits -= upgrade_cost(key)
	upgrades[key] = upgrade_level(key) + 1
	save_data()
	return true
