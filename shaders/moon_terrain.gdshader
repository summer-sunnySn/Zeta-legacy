shader_type spatial;
render_mode ensure_correct_normals, cull_back;

/// Zeta Legacy — Realistic Moon Terrain Shader
/// Displaces vertices using the NASA displacement map and composites
/// albedo / normal / roughness / AO for a photorealistic lunar regolith.
/// Optimised for the Godot Mobile renderer (single-pass, no branching).

// ─── Samplers ──────────────────────────────────────────────────────────────
uniform sampler2D albedo_texture : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_map       : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D roughness_map    : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D ao_map           : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D displacement_map : hint_default_black, filter_linear_mipmap_anisotropic;

// ─── Tuning ────────────────────────────────────────────────────────────────
uniform float texture_scale     : hint_range(0.1, 20.0) = 8.0;  // UV tiling
uniform float displacement_scale: hint_range(0.0, 15.0) = 3.5;
uniform float normal_strength   : hint_range(0.0, 3.0)  = 1.2;
uniform float detail_scale      : hint_range(1.0, 64.0) = 32.0;
uniform float detail_strength   : hint_range(0.0, 1.0)  = 0.35;

// Regolith dust scattering — fake subsurface in shadowed craters.
uniform float dust_brightness   : hint_range(0.0, 1.0) = 0.08;
uniform float dust_power        : hint_range(0.0, 4.0) = 1.5;

// Light direction (Sun) — passed from script for consistency.
uniform vec3  sun_direction     : source_color = vec3(0.50, 0.87, 0.30);

varying vec2 vuv;

void vertex() {
	// Moon UVs span the entire PlaneMesh.
	vuv = UV * texture_scale;

	// ── Vertex Displacement ───────────────────────────────────────────────
	float h = texture(displacement_map, vuv).r;
	VERTEX += NORMAL * h * displacement_scale;
}

void fragment() {
	vec2 uv = vuv;
	vec3 sun = normalize(sun_direction);

	// ── Albedo ─────────────────────────────────────────────────────────-
	vec3 alb = texture(albedo_texture, uv).rgb;
	ALBEDO = alb;

	// ── Normal (macro + micro detail) ────────────────────────────────────
	// Main macro normal from the NASA normal map.
	vec3 macro_n = texture(normal_map, uv).rgb;
	// Re-sample the same normal at high frequency for micro-detail.
	vec3 micro_n = texture(normal_map, uv * detail_scale).rgb;
	// Blend: high-frequency detail adds surface grit without overriding
	// the large-scale relief.
	vec3 blended = mix(macro_n, micro_n, detail_strength);
	// decode from [0,1] to [-1,1] inside NORMAL_MAP
	NORMAL_MAP = blended;
	NORMAL_MAP_DEPTH = normal_strength;

	// ── Roughness / Metallic ───────────────────────────────────────────
	ROUGHNESS = clamp(texture(roughness_map, uv).r, 0.85, 0.98);
	METALLIC  = 0.0;   // regolith is non-metallic

	// ── Ambient Occlusion ──────────────────────────────────────────────
	AO = texture(ao_map, uv).r;
	AO_LIGHT_AFFECT = 0.6;

	// ── Regolith Dust Scattering ───────────────────────────────────────
	// Shadowed crater interiors get a subtle warm bounce.
	float NdotL = max(dot(normalize(NORMAL), sun), 0.0);
	float shadow_term = pow(1.0 - NdotL, dust_power);
	ALBEDO += vec3(dust_brightness) * shadow_term;
}
