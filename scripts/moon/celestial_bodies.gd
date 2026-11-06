## Zeta Legacy — Celestial Bodies Controller
## Configures Sun DirectionalLight3D with hard mobile-optimized PSSM cascades,
## billboard sun flare, distant scaled Earth proxy with slow axial rotation,
## and subtle Earthshine fill light cast onto the lunar landscape.
class_name CelestialBodies
extends Node3D

@export var sun_light: DirectionalLight3D = null
@export var earth_node: Node3D = null
@export var earthshine_light: DirectionalLight3D = null
@export var sun_lens_flare: MeshInstance3D = null

## Earth axial rotation speed (radians per second, e.g. 0.002 rad/s for slow majestic spin)
@export var earth_rotation_speed: float = 0.0035

## Earthshine color and intensity (bluish reflected earthlight on dark lunar ground)
@export var earthshine_color: Color = Color(0.12, 0.22, 0.38, 1.0)
@export var earthshine_energy: float = 0.12

func _ready() -> void:
	_configure_sun()
	_configure_earthshine()
	_configure_lens_flare()

func _process(delta: float) -> void:
	if earth_node and is_instance_valid(earth_node):
		earth_node.rotate_y(earth_rotation_speed * delta)

	# Ensure sun lens flare billboard always faces active camera if positioned along sun vector
	if sun_lens_flare and is_instance_valid(sun_lens_flare) and sun_light:
		var cam := get_viewport().get_camera_3d()
		if cam:
			var sun_fwd := -sun_light.global_transform.basis.z
			# Place flare along sun direction relative to camera
			sun_lens_flare.global_position = cam.global_position + sun_fwd * 1200.0

## Sets up PSSM 4-split cascades tuned for mid-range mobile Vulkan renderer
func _configure_sun() -> void:
	if sun_light == null:
		sun_light = get_node_or_null("Sun") as DirectionalLight3D
	if sun_light == null:
		return

	# Harsh lunar solar lighting (no atmosphere scattering, pitch black unlit shadows)
	sun_light.light_color = Color(1.0, 0.98, 0.95, 1.0)
	sun_light.light_energy = 2.4

	# Mobile PSSM shadow configuration
	sun_light.shadow_enabled = true
	sun_light.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS
	sun_light.directional_shadow_split_1 = 0.05
	sun_light.directional_shadow_split_2 = 0.15
	sun_light.directional_shadow_split_3 = 0.35
	sun_light.directional_shadow_fade_start = 0.8
	sun_light.directional_shadow_max_distance = 320.0
	sun_light.shadow_bias = 0.08
	sun_light.shadow_normal_bias = 1.2

func _configure_earthshine() -> void:
	if earthshine_light == null:
		earthshine_light = get_node_or_null("Earthshine") as DirectionalLight3D
	if earthshine_light == null:
		return

	# Faint indirect light from Earth hanging in the sky
	earthshine_light.light_color = earthshine_color
	earthshine_light.light_energy = earthshine_energy
	earthshine_light.shadow_enabled = false  # Earthshine does not cast hard shadows (diffuse fill)

func _configure_lens_flare() -> void:
	if sun_lens_flare == null:
		sun_lens_flare = get_node_or_null("SunFlare") as MeshInstance3D
	if sun_lens_flare == null:
		return

	# Ensure billboard flare stays unshaded and glow-reactive
	var mat := sun_lens_flare.material_override as StandardMaterial3D
	if mat == null:
		mat = StandardMaterial3D.new()
		sun_lens_flare.material_override = mat
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_color = Color(1.0, 0.95, 0.85, 0.8)
