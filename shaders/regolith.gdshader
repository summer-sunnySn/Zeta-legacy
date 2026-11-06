shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_burley, specular_schlick_ggx;

/// Zeta Legacy — Production Regolith Triplanar PBR Shader
/// Features:
/// 1. World-space triplanar mapping for albedo, normal, and roughness (prevents texture stretching on steep crater rims).
/// 2. Dual-scale normal mapping: macro terrain normal + high-frequency close-range micro grit.
/// 3. Slope-based darkening: steep crater walls and ejecta exhibit darker fractured bedrock.
/// 4. Lunar photometric opposition surge: intense retro-reflection brightening when viewing angle aligns with sun vector.
/// 5. Harsh lunar lighting: deep pitch-black shadows without atmospheric wash.
/// Mobile-tuned: optimized single-pass texture lookups with slope factor.

uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map     : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_map  : hint_default_white, filter_linear_mipmap_anisotropic;

uniform float uv_scale : hint_range(0.01, 1.0) = 0.08;
uniform float detail_scale : hint_range(1.0, 32.0) = 8.0;
uniform float detail_normal_strength : hint_range(0.0, 2.0) = 0.45;
uniform float triplanar_sharpness : hint_range(1.0, 16.0) = 4.0;

// Slope darkening tuning
uniform float slope_darken_start : hint_range(0.0, 1.0) = 0.65; // Cosine of slope angle
uniform float slope_darken_amount : hint_range(0.0, 1.0) = 0.40;

// Lunar opposition surge (He-Vasavada / Hapke effect approximation)
uniform vec3 sun_direction = vec3(0.5, 0.45, 0.74);
uniform float opposition_surge_strength : hint_range(0.0, 2.0) = 0.75;
uniform float opposition_surge_power : hint_range(2.0, 32.0) = 14.0;

varying vec3 v_world_pos;
varying vec3 v_world_normal;

void vertex() {
	v_world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	v_world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec3 n = normalize(v_world_normal);
	vec3 blend_weights = pow(abs(n), vec3(triplanar_sharpness));
	blend_weights /= (blend_weights.x + blend_weights.y + blend_weights.z);

	// Triplanar UV coordinates scaled to world dimensions
	vec2 uv_x = v_world_pos.zy * uv_scale;
	vec2 uv_y = v_world_pos.xz * uv_scale;
	vec2 uv_z = v_world_pos.xy * uv_scale;

	// Triplanar Albedo
	vec3 col_x = texture(albedo_texture, uv_x).rgb;
	vec3 col_y = texture(albedo_texture, uv_y).rgb;
	vec3 col_z = texture(albedo_texture, uv_z).rgb;
	vec3 base_albedo = col_x * blend_weights.x + col_y * blend_weights.y + col_z * blend_weights.z;

	// Macro Normal map triplanar sampling
	vec3 norm_x = texture(normal_map, uv_x).rgb * 2.0 - 1.0;
	vec3 norm_y = texture(normal_map, uv_y).rgb * 2.0 - 1.0;
	vec3 norm_z = texture(normal_map, uv_z).rgb * 2.0 - 1.0;
	vec3 macro_normal_sample = norm_x * blend_weights.x + norm_y * blend_weights.y + norm_z * blend_weights.z;

	// Micro detail normal map triplanar sampling (close range surface grit)
	vec3 det_x = texture(normal_map, uv_x * detail_scale).rgb * 2.0 - 1.0;
	vec3 det_y = texture(normal_map, uv_y * detail_scale).rgb * 2.0 - 1.0;
	vec3 det_z = texture(normal_map, uv_z * detail_scale).rgb * 2.0 - 1.0;
	vec3 micro_normal_sample = det_x * blend_weights.x + det_y * blend_weights.y + det_z * blend_weights.z;

	vec3 blended_normal_map = normalize(macro_normal_sample + micro_normal_sample * detail_normal_strength);
	NORMAL_MAP = blended_normal_map * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;

	// Triplanar Roughness
	float r_x = texture(roughness_map, uv_x).r;
	float r_y = texture(roughness_map, uv_y).r;
	float r_z = texture(roughness_map, uv_z).r;
	float rough = r_x * blend_weights.x + r_y * blend_weights.y + r_z * blend_weights.z;
	ROUGHNESS = clamp(rough, 0.82, 0.98); // High lunar regolith roughness
	METALLIC = 0.0;                       // Lunar regolith is completely dielectric

	// Slope-based darkening: vertical cliff walls expose darker basaltic rock
	float up_dot = clamp(n.y, 0.0, 1.0);
	float slope_factor = smoothstep(slope_darken_start, 1.0, up_dot);
	vec3 shaded_albedo = mix(base_albedo * (1.0 - slope_darken_amount), base_albedo, slope_factor);

	// Lunar Opposition Surge (retro-reflection spike when camera is inline with sun)
	vec3 view_dir = normalize(CAMERA_POSITION_WORLD - v_world_pos);
	vec3 sun_dir = normalize(sun_direction);
	float phase_angle = max(0.0, dot(view_dir, sun_dir));
	float opposition_surge = pow(phase_angle, opposition_surge_power) * opposition_surge_strength;

	// Apply surge only when illuminated by the sun (N.L > 0)
	float n_dot_l = max(0.0, dot(n, sun_dir));
	shaded_albedo += shaded_albedo * (opposition_surge * step(0.01, n_dot_l));

	ALBEDO = shaded_albedo;
	SPECULAR = 0.15;
}
