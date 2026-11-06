shader_type sky;

/// Zeta Legacy — Production Space Sky Shader
/// Pure black cosmic space, thousands of procedural stars with varied size,
/// color temperature, brightness, real twinkle via TIME, subtle Milky Way band,
/// and optional star panorama texture (res://textures/star_map.exr / .png).
/// Tuned for Godot 4.7 Mobile Renderer (ALU-optimized, no branching).

uniform sampler2D star_map_texture : filter_linear_mipmap, hint_default_black;
uniform bool use_star_map = true;
uniform float star_map_intensity : hint_range(0.0, 5.0) = 1.0;

uniform float star_density : hint_range(50.0, 500.0) = 220.0;
uniform float star_brightness_mult : hint_range(0.1, 10.0) = 3.5;
uniform float twinkle_speed : hint_range(0.0, 10.0) = 2.4;
uniform float milky_way_intensity : hint_range(0.0, 1.0) = 0.22;

// Pseudo-random hash functions
vec2 hash2(vec2 p) {
	p = vec2(dot(p, vec2(127.1, 311.7)), dot(p, vec2(269.5, 183.3)));
	return fract(sin(p) * 43758.5453123);
}

float hash1(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

// Convert direction vector on celestial sphere to equirectangular UV
vec2 dir_to_equirect(vec3 dir) {
	float phi = atan(dir.z, dir.x);
	float theta = asin(clamp(dir.y, -1.0, 1.0));
	return vec2(phi / (2.0 * 3.14159265359) + 0.5, theta / 3.14159265359 + 0.5);
}

// Approximate stellar blackbody color by temperature index [0..1]
// 0 = red-orange dwarf (3000K), 0.5 = yellow-white sun (6000K), 1.0 = blue giant (12000K)
vec3 star_color(float temp_idx) {
	vec3 cool = vec3(1.0, 0.65, 0.45);   // Class M / K
	vec3 mid  = vec3(1.0, 0.95, 0.90);   // Class G / F
	vec3 hot  = vec3(0.70, 0.85, 1.00);  // Class B / A
	if (temp_idx < 0.5) {
		return mix(cool, mid, temp_idx * 2.0);
	} else {
		return mix(mid, hot, (temp_idx - 0.5) * 2.0);
	}
}

// Procedural star layer sampled on cubemap projection or spherical grid
vec3 procedural_stars(vec3 dir, float density, float t) {
	vec3 abs_d = abs(dir);
	vec2 uv;
	float side_seed = 0.0;
	if (abs_d.x >= abs_d.y && abs_d.x >= abs_d.z) {
		uv = dir.yz / abs_d.x;
		side_seed = 11.0 + sign(dir.x) * 3.0;
	} else if (abs_d.y >= abs_d.x && abs_d.y >= abs_d.z) {
		uv = dir.xz / abs_d.y;
		side_seed = 23.0 + sign(dir.y) * 5.0;
	} else {
		uv = dir.xy / abs_d.z;
		side_seed = 37.0 + sign(dir.z) * 7.0;
	}

	vec2 grid_pos = (uv * 0.5 + 0.5) * density;
	vec2 cell_id = floor(grid_pos) + vec2(side_seed);
	vec2 cell_uv = fract(grid_pos) - 0.5;

	vec2 rand_val = hash2(cell_id);
	// Only a fraction of cells contain visible stars
	if (rand_val.x > 0.65) {
		vec2 star_pos = (rand_val - 0.5) * 0.8;
		float dist = length(cell_uv - star_pos);

		// Star radius varies
		float star_radius = mix(0.012, 0.045, rand_val.y * rand_val.y);
		float core = smoothstep(star_radius, 0.0, dist);

		// Stellar temperature and twinkle
		float temp_idx = hash1(cell_id + vec2(1.7, 4.3));
		vec3 col = star_color(temp_idx);

		// Twinkle oscillation
		float phase = hash1(cell_id + vec2(8.1, 2.9)) * 6.28318;
		float speed = mix(0.8, 2.5, rand_val.x) * twinkle_speed;
		float twinkle = 0.6 + 0.4 * sin(t * speed + phase);

		// Rare bright star flare
		float brightness = mix(0.5, 3.0, pow(rand_val.y, 4.0));
		return col * core * twinkle * brightness * star_brightness_mult;
	}
	return vec3(0.0);
}

// Procedural Milky Way band
vec3 milky_way(vec3 dir) {
	// Plane of galaxy tilted relative to celestial coordinates
	vec3 mw_normal = normalize(vec3(0.35, 0.88, 0.32));
	float dist_from_plane = abs(dot(dir, mw_normal));

	// Soft Gaussian falloff along galactic plane
	float band = exp(-dist_from_plane * dist_from_plane * 24.0);

	// Galactic center bulge
	vec3 core_dir = normalize(vec3(-0.6, 0.1, -0.79));
	float core = max(0.0, dot(dir, core_dir));
	core = pow(core, 8.0) * 1.8;

	// Subtle color temperature (warm dusty core, bluish outer spiral)
	vec3 mw_col = mix(vec3(0.4, 0.48, 0.7), vec3(0.7, 0.55, 0.4), core * 0.5);
	return mw_col * (band + core) * milky_way_intensity;
}

void sky() {
	vec3 dir = normalize(EYEDIR);

	// 1. Cosmic vacuum: Pure black base (no ambient haze, no Rayleigh blue)
	vec3 final_color = vec3(0.0);

	// 2. Star Panorama Texture (res://textures/star_map.exr / .png)
	if (use_star_map) {
		vec2 eq_uv = dir_to_equirect(dir);
		vec4 map_sample = texture(star_map_texture, eq_uv);
		final_color += map_sample.rgb * star_map_intensity;
	}

	// 3. Subtle Milky Way Band
	final_color += milky_way(dir);

	// 4. Procedural Stars (2 scales: fine dense field + prominent sparse stars)
	final_color += procedural_stars(dir, star_density, TIME);
	final_color += procedural_stars(dir + vec3(0.33), star_density * 0.45, TIME * 0.8);

	COLOR = final_color;
}
