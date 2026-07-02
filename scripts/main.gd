## Zeta Legacy — Main Game Controller
## Wires the player, chase camera, spawner and HUD together and drives the
## start → fight → game-over → restart loop.
extends Node3D

# ─── Nodes ──────────────────────────────────────────────────────────────
@onready var player: CharacterBody3D = $Player
@onready var spawner: Node3D         = $EnemySpawner
@onready var hud: Control            = $HUDLayer/GameHUD
@onready var world_env: WorldEnvironment = $WorldEnvironment

var _started: bool = false
var _awaiting_restart: bool = false

## Background themes cycled per wave (boss waves go red). [top, horizon, fog, ambient]
const THEMES := [
	[Color(0.02, 0.01, 0.06), Color(0.08, 0.03, 0.15), Color(0.08, 0.05, 0.16), Color(0.42, 0.46, 0.62)],
	[Color(0.01, 0.03, 0.09), Color(0.03, 0.10, 0.20), Color(0.05, 0.10, 0.20), Color(0.40, 0.52, 0.66)],
	[Color(0.01, 0.05, 0.05), Color(0.03, 0.15, 0.12), Color(0.04, 0.15, 0.11), Color(0.42, 0.60, 0.52)],
	[Color(0.06, 0.03, 0.02), Color(0.16, 0.08, 0.04), Color(0.16, 0.09, 0.05), Color(0.60, 0.50, 0.40)],
]
const BOSS_THEME := [Color(0.08, 0.01, 0.02), Color(0.20, 0.03, 0.05), Color(0.18, 0.05, 0.06), Color(0.62, 0.40, 0.40)]

@onready var key_light: DirectionalLight3D = $KeyLight

func _ready() -> void:
	# Apply the player's chosen graphics tier to this scene.
	Gfx.apply(world_env, key_light)

	# Arena is centred where the player starts.
	Globals.reset()
	Globals.arena_center = player.global_position

	# Player reads its touch input from the HUD.
	player.hud = hud

	hud.start_pressed.connect(_on_start_pressed)
	hud.restart_pressed.connect(_on_restart_pressed)
	Globals.player_destroyed.connect(_on_player_destroyed)
	Globals.wave_started.connect(_on_wave_theme)

	# Headless validation hook — lets CLI test runs start without a tap.
	if OS.has_environment("ZETA_AUTOSTART"):
		_on_start_pressed.call_deferred()

func _on_start_pressed() -> void:
	if _started:
		return
	_started = true
	player.active = true
	hud.show_started()
	spawner.start_spawning()

func _on_wave_theme(wave: int) -> void:
	if world_env == null or world_env.environment == null:
		return
	var env := world_env.environment
	var theme: Array = BOSS_THEME if wave % 5 == 0 else THEMES[(wave - 1) % THEMES.size()]
	if env.sky and env.sky.sky_material is ProceduralSkyMaterial:
		var sky: ProceduralSkyMaterial = env.sky.sky_material
		sky.sky_top_color = theme[0]
		sky.sky_horizon_color = theme[1]
	env.fog_light_color = theme[2]
	env.ambient_light_color = theme[3]

func _on_player_destroyed() -> void:
	Save.on_run_ended(Globals.score)
	hud.show_game_over()
	# Allow a restart tap/key after a short beat.
	await get_tree().create_timer(1.5).timeout
	_awaiting_restart = true

func _on_restart_pressed() -> void:
	if _awaiting_restart:
		_awaiting_restart = false
		get_tree().reload_current_scene()

func _unhandled_input(event: InputEvent) -> void:
	# Keyboard restart fallback (desktop testing).
	if _awaiting_restart and event.is_action_pressed("fire"):
		_awaiting_restart = false
		get_tree().reload_current_scene()
