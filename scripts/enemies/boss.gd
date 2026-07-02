## Zeta Legacy — Boss
## A large, tanky alien that hovers in front of the player, strafes, and fires
## bullet volleys. Has its own health bar (HUD reads Globals.boss).
extends Area3D

@export var max_health: int = 60
@export var move_speed: float = 10.0
@export var fire_cooldown: float = 1.0
@export var bullet_speed: float = 30.0
@export var score_value: int = 2500
@export var touch_damage: int = 2

const UFO_MODEL := "res://models/enemies/ufo.glb"   # big animated alien carrier

@onready var model_pivot: Node3D = $ModelPivot
@onready var fire_timer: Timer = $FireTimer

var health: int
var _t: float = 0.0
var _can_fire: bool = true

func _ready() -> void:
	add_to_group("enemy")
	add_to_group("boss")
	health = max_health
	Globals.boss = self
	Globals.boss_spawned.emit(self)
	fire_timer.wait_time = fire_cooldown
	fire_timer.one_shot = true
	fire_timer.timeout.connect(func(): _can_fire = true)
	if not body_entered.is_connected(_on_body):
		body_entered.connect(_on_body)
	_install_ufo()

## The boss is a huge UFO carrier — same animated model, scaled way up.
func _install_ufo() -> void:
	if model_pivot == null:
		return
	var old := model_pivot.get_node_or_null("BossModel")
	if old:
		old.free()
	var ufo: Node3D = ModelLib.instance_model(UFO_MODEL)
	if ufo == null:
		return
	ufo.name = "BossModel"
	model_pivot.add_child(ufo)
	ufo.transform = Transform3D.IDENTITY
	ModelLib.fit(ufo, 14.0)
	ModelLib.play_loop(ufo, 0.6)

func _physics_process(delta: float) -> void:
	if Globals.is_game_over:
		return
	var p := Globals.player
	if p == null or not is_instance_valid(p):
		return
	_t += delta

	# Hover ahead of the player, weaving side to side and up/down.
	var b := p.global_transform.basis
	var target: Vector3 = p.global_position + (-b.z) * 34.0 \
		+ b.x * sin(_t * 0.6) * 18.0 + Vector3.UP * sin(_t * 0.45) * 7.0
	var to_t := target - global_position
	if to_t.length() > 1.0:
		global_position += to_t.normalized() * move_speed * delta

	var to_p := p.global_position - global_position
	if model_pivot and to_p.length() > 0.1:
		var up := Vector3.UP
		if absf(to_p.normalized().dot(up)) > 0.98:
			up = Vector3.RIGHT
		var goal := Transform3D().looking_at(to_p.normalized(), up)
		var cur := model_pivot.global_transform.basis.orthonormalized()
		model_pivot.global_transform.basis = cur.slerp(goal.basis, clampf(4.0 * delta, 0, 1))

	if _can_fire and to_p.length() < 75.0:
		_fire_volley(p)
		_can_fire = false
		fire_timer.start()

func _fire_volley(p: Node3D) -> void:
	var base := (p.global_position - global_position).normalized()
	for a in [-0.28, -0.14, 0.0, 0.14, 0.28]:
		var b: Area3D = BulletPool.get_enemy_bullet()
		if b == null:
			continue
		b.global_position = global_position + base * 4.0
		b.direction = base.rotated(Vector3.UP, a)
		b.speed = bullet_speed
		b.damage = 1
		b.reset_lifetime()
		if b.has_method("orient_to_direction"):
			b.orient_to_direction()

func take_damage(amount: int) -> void:
	health -= amount
	if model_pivot:
		var tw := create_tween()
		tw.tween_property(model_pivot, "scale", Vector3(1.06, 1.06, 1.06), 0.03)
		tw.tween_property(model_pivot, "scale", Vector3.ONE, 0.1)
	Audio.play("hit", -7.0, 0.1)
	if health <= 0:
		_die()

func _on_body(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("take_damage"):
		body.take_damage(touch_damage)

func _die() -> void:
	Globals.boss = null
	Globals.boss_defeated.emit()
	Globals.register_kill(score_value, global_position)
	Audio.play("explosion", 4.0, 0.05)
	Globals.hitstop(0.05, 0.12)   # satisfying freeze on the kill
	_big_boom()
	queue_free()

func _big_boom() -> void:
	var scene: PackedScene = load("res://scenes/fx/explosion.tscn")
	if scene == null:
		return
	var host: Node = get_tree().current_scene
	if host == null:
		host = get_parent()
	for i in 6:
		var b: Node3D = scene.instantiate()
		host.add_child(b)
		b.global_position = global_position + Vector3(randf_range(-5, 5), randf_range(-5, 5), randf_range(-5, 5))
		b.scale = Vector3.ONE * 2.2

func health_fraction() -> float:
	return clampf(float(health) / float(max_health), 0.0, 1.0)
