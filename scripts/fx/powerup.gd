## Zeta Legacy — Power-up Pickup
## Floats, glows, and magnetically flies to the player when near. On touch it
## activates its effect on the ship. Color-coded by kind.
extends Area3D

@export var kind: String = "rapid"        ## rapid / spread / shield / health
@export var attract_range: float = 17.0
@export var attract_speed: float = 34.0
@export var life: float = 13.0

@onready var mesh: MeshInstance3D = $Mesh
@onready var light: OmniLight3D = $Light

var _t: float = 0.0

const COLORS := {
	"rapid": Color(1.0, 0.6, 0.12),
	"spread": Color(0.2, 0.9, 1.0),
	"shield": Color(0.35, 0.55, 1.0),
	"health": Color(0.3, 1.0, 0.45),
}

func _ready() -> void:
	add_to_group("powerup")
	var c: Color = COLORS.get(kind, Color.WHITE)
	var m := mesh.get_surface_override_material(0)
	if m is StandardMaterial3D:
		m.albedo_color = c
		m.emission = c
	if light:
		light.light_color = c
	if not body_entered.is_connected(_on_body):
		body_entered.connect(_on_body)

func _physics_process(delta: float) -> void:
	_t += delta
	life -= delta
	if life <= 0.0:
		queue_free()
		return

	# Spin + bob.
	if mesh:
		mesh.rotation.y += 2.2 * delta
		mesh.position.y = sin(_t * 3.0) * 0.3

	# Magnetic pull toward the player.
	var player := Globals.player
	if player and is_instance_valid(player):
		var to_p: Vector3 = player.global_position - global_position
		var d := to_p.length()
		if d < attract_range and d > 0.01:
			var pull := clampf((attract_range - d) / attract_range + 0.35, 0.35, 1.6)
			global_position += to_p.normalized() * attract_speed * pull * delta

func _on_body(body: Node3D) -> void:
	if body.is_in_group("player") and body.has_method("activate_powerup"):
		body.activate_powerup(kind)
		Audio.play("powerup", -4.0)
		queue_free()
