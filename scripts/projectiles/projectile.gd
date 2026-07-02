## Zeta Legacy — Projectile (shared for player & enemy bullets)
## Area3D with a trail. Pooled — do NOT queue_free, call BulletPool.return_bullet().
extends Area3D

# ─── Exports ────────────────────────────────────────────────────────────
@export var speed: float = 40.0
@export var damage: int = 1
@export var direction: Vector3 = Vector3.FORWARD
@export var max_lifetime: float = 3.0
@export var max_travel: float = 220.0     ## hard distance cap (arena ~ this big)

# ─── Node References ────────────────────────────────────────────────────
@onready var trail: MeshInstance3D = $TrailMesh

# ─── State ──────────────────────────────────────────────────────────────
var _lifetime: float = 0.0
var _travelled: float = 0.0

# ─── Lifecycle ──────────────────────────────────────────────────────────
func _ready() -> void:
	# Connect signals only if not already connected by the scene
	if not area_entered.is_connected(_on_area_entered):
		area_entered.connect(_on_area_entered)
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)

func _physics_process(delta: float) -> void:
	var step := direction * speed * delta
	global_position += step
	_lifetime += delta
	_travelled += step.length()

	# Stretch trail mesh along direction of travel for motion blur feel
	if trail:
		trail.scale.z = clampf(speed * 0.04, 0.3, 2.0)

	# Return to pool if expired, travelled too far, or left the arena
	if _lifetime >= max_lifetime or _travelled >= max_travel \
			or not Globals.is_in_arena(global_position, 6.0):
		_deactivate()

## Point the bullet (and its trail) along its travel direction.
func orient_to_direction() -> void:
	if direction.is_equal_approx(Vector3.ZERO):
		return
	# Trail box extends along local -Z, so look_at points it down-range.
	var up := Vector3.UP
	if absf(direction.dot(up)) > 0.99:
		up = Vector3.RIGHT   # avoid degenerate look_at when firing straight up/down
	look_at(global_position + direction, up)

# ─── Collision Callbacks ────────────────────────────────────────────────
func _on_area_entered(other: Area3D) -> void:
	# Player bullet hitting enemy
	if is_in_group("player_bullet") and other.is_in_group("enemy"):
		if other.has_method("take_damage"):
			other.take_damage(damage)
		_deactivate()

	# Enemy bullet hitting player
	elif is_in_group("enemy_bullet") and other.is_in_group("player"):
		if other.has_method("take_damage"):
			other.take_damage(damage)
		_deactivate()

	# Enemy bullet hitting a friendly unit (mission defend/escort target)
	elif is_in_group("enemy_bullet") and other.is_in_group("ally"):
		if other.has_method("take_damage"):
			other.take_damage(damage)
		_deactivate()

func _on_body_entered(body: Node3D) -> void:
	# Player bullet hitting an enemy CharacterBody3D (if any)
	if is_in_group("player_bullet") and body.is_in_group("enemy"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		_deactivate()

	# Enemy bullet hitting player CharacterBody3D
	elif is_in_group("enemy_bullet") and body.is_in_group("player"):
		if body.has_method("take_damage"):
			body.take_damage(damage)
		_deactivate()

# ─── Pool Return ────────────────────────────────────────────────────────
func reset_lifetime() -> void:
	_lifetime = 0.0
	_travelled = 0.0

func _deactivate() -> void:
	BulletPool.return_bullet(self)
