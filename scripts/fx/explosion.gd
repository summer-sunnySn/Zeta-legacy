## Zeta Legacy — One-shot Explosion: particle burst + light flash + shockwave ring.
extends Node3D

@onready var particles: CPUParticles3D = $Particles
@onready var flash: OmniLight3D = $Flash
@onready var shock: MeshInstance3D = $Shockwave

func _ready() -> void:
	if particles:
		particles.emitting = true
	if flash:
		flash.light_energy = 11.0
		create_tween().tween_property(flash, "light_energy", 0.0, 0.35)
	if shock:
		shock.scale = Vector3.ONE * 0.3
		var mat := shock.get_surface_override_material(0)
		var tw := create_tween()
		tw.set_parallel(true)
		tw.tween_property(shock, "scale", Vector3.ONE * 7.0, 0.45)
		if mat is StandardMaterial3D:
			tw.tween_property(mat, "albedo_color:a", 0.0, 0.45)
	await get_tree().create_timer(1.4).timeout
	queue_free()
