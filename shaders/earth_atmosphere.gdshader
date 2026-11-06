shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

/// Zeta Legacy — Earth Sphere & Atmospheric Scattering Rim Shader
/// Renders the terrestrial globe with daytime albedo texture, realistic
/// night-side terminator, and an authentic Rayleigh scattering limb/rim glow.
/// Fully compatible with Godot 4.7 Mobile Renderer.

uniform sampler2D day_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 atmosphere_color : source_color = vec4(0.24, 0.58, 1.0, 1.0);
uniform vec4 atmosphere_edge_color : source_color = vec4(0.45, 0.75, 1.0, 1.0);
uniform float rim_power : hint_range(0.5, 8.0) = 3.2;
uniform float rim_intensity : hint_range(0.0, 5.0) = 1.8;
uniform float night_terminator_softness : hint_range(0.01, 0.5) = 0.15;
uniform vec3 sun_direction = vec3(0.5, 0.3, 0.8);

varying vec3 v_world_normal;
varying vec3 v_world_pos;

void vertex() {
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = UV;
	vec3 base_color = texture(day_texture, uv).rgb;

	vec3 n = normalize(v_world_normal);
	vec3 v = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 l = normalize(sun_direction);

	// Solar illumination term (terminator transition)
	float n_dot_l = dot(n, l);
	float day_term = smoothstep(-night_terminator_softness, night_terminator_softness, n_dot_l);

	// Fresnel / limb rim glow (atmospheric shell scattering)
	float n_dot_v = max(0.0, dot(n, v));
	float rim = pow(1.0 - n_dot_v, rim_power);

	// Atmosphere illuminates stronger on the sunlit half of the limb
	float sunlit_rim_boost = max(0.05, dot(v, l) * 0.5 + 0.5);
	vec3 rim_glow = mix(atmosphere_color.rgb, atmosphere_edge_color.rgb, rim) * (rim * rim_intensity * sunlit_rim_boost);

	// Surface albedo with sunlit day factor
	ALBEDO = base_color * (day_term * 0.95 + 0.05) + rim_glow * day_term;
	ROUGHNESS = 0.65;
	METALLIC = 0.05;
	SPECULAR = 0.25;

	// Emission adds subtle self-lit outer halo for the atmosphere glow
	EMISSION = rim_glow * (day_term * 0.8 + 0.1);
}
