## Zeta Legacy — Graphics Quality Manager (autoload "Gfx")
## One place that applies the look of the whole game. Each gameplay scene calls
## `Gfx.apply(world_environment, directional_light)` in its _ready().
##
## IMPORTANT: the game ships on Godot's **Mobile** renderer for device
## compatibility — many phones' Vulkan drivers fail to create the compute
## pipelines that SDFGI / SSIL / SSR / SSAO / volumetric fog need (VkResult
## errors / crashes). So those effects are kept OFF on every tier here; we only
## use what the Mobile renderer supports reliably: glow/bloom, ACES tonemapping
## and directional shadows. The tiers mainly trade shadow + glow cost so weak
## phones can still hit a smooth frame rate.
extends Node

enum { LOW, MEDIUM, ULTRA }

## Human labels for the settings UI.
const LABELS := ["Low", "Medium", "Ultra"]

func current() -> int:
	return clampi(Save.quality, 0, 2)

## Apply the current tier to a scene's WorldEnvironment (+ optional sun).
## Safe to call with nulls.
func apply(world_env: WorldEnvironment, sun: DirectionalLight3D = null) -> void:
	if world_env == null or world_env.environment == null:
		return
	var env: Environment = world_env.environment
	var q := current()

	# ── Tonemapping + base exposure (cinematic on every tier) ─────────────
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0

	# ── Glow / bloom — the neon space sheen (Mobile-supported) ────────────
	env.glow_enabled = q >= MEDIUM
	env.glow_intensity = 0.85 if q == ULTRA else 0.6
	env.glow_bloom = 0.25 if q == ULTRA else 0.12
	env.glow_hdr_threshold = 0.9
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN

	# ── Heavy compute effects: OFF on every tier (Mobile renderer) ────────
	# Enabling any of these can crash the Vulkan driver on many phones.
	env.ssao_enabled = false
	env.ssil_enabled = false
	env.ssr_enabled = false
	env.sdfgi_enabled = false
	env.volumetric_fog_enabled = false

	# ── Directional shadows scale with tier (Low = off for speed) ─────────
	if sun:
		sun.shadow_enabled = q >= MEDIUM
		sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_4_SPLITS

## Cycle to the next tier (used by the settings button), persist, return label.
func cycle() -> String:
	Save.set_quality((current() + 1) % 3)
	return LABELS[current()]
