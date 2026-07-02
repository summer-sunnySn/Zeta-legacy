## Zeta Legacy — Arcade Ship Roster (data)
## Shared definition of every player-selectable ship: its CC0 Kenney model plus
## stat modifiers. Both the ship-select screen and player.gd read from here, so
## adding a ship is a one-entry change.
##
## Stat fields (multipliers/bonuses applied on top of the base player tuning):
##   speed  — cruise-speed multiplier
##   fire   — fire-interval multiplier (LOWER = shoots faster)
##   health — flat bonus hit points
##   damage — flat bonus bullet damage
##
## Loaded via preload (const ShipRoster = preload(...)) so it works in headless
## runs without depending on global class-name registration timing.
extends RefCounted

const SHIPS := [
	{
		"id": "interceptor",
		"name": "INTERCEPTOR",
		"desc": "Balanced all-rounder. Good first ship.",
		"model": "res://models/arcade/ship_a.glb",
		"accent": Color(0.40, 0.80, 1.0),
		"speed": 1.0, "fire": 1.0, "health": 0, "damage": 0,
	},
	{
		"id": "scout",
		"name": "SCOUT",
		"desc": "Fast and nimble, lighter armour.",
		"model": "res://models/arcade/ship_b.glb",
		"accent": Color(0.40, 1.0, 0.70),
		"speed": 1.22, "fire": 0.95, "health": -1, "damage": 0,
	},
	{
		"id": "striker",
		"name": "STRIKER",
		"desc": "Rapid-fire specialist.",
		"model": "res://models/arcade/ship_c.glb",
		"accent": Color(1.0, 0.80, 0.35),
		"speed": 1.0, "fire": 0.72, "health": 0, "damage": 0,
	},
	{
		"id": "vanguard",
		"name": "VANGUARD",
		"desc": "Tougher hull, steady speed.",
		"model": "res://models/arcade/ship_d.glb",
		"accent": Color(0.70, 0.65, 1.0),
		"speed": 0.95, "fire": 1.0, "health": 2, "damage": 0,
	},
	{
		"id": "racer",
		"name": "RACER",
		"desc": "Blistering speed, glass cannon.",
		"model": "res://models/arcade/ship_racer.glb",
		"accent": Color(1.0, 0.45, 0.55),
		"speed": 1.42, "fire": 1.08, "health": -1, "damage": 0,
	},
	{
		"id": "juggernaut",
		"name": "JUGGERNAUT",
		"desc": "Heavy tank. Slow but hits hard.",
		"model": "res://models/arcade/ship_heavy.glb",
		"accent": Color(1.0, 0.55, 0.25),
		"speed": 0.8, "fire": 1.15, "health": 3, "damage": 1,
	},
]

static func count() -> int:
	return SHIPS.size()

static func get_ship(idx: int) -> Dictionary:
	return SHIPS[clampi(idx, 0, SHIPS.size() - 1)]
