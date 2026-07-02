## Zeta Legacy — Mission Mode Data (prequel campaign)
## Alina's missions BEFORE the Moon operation: her rise from rookie ARIA pilot
## across the solar-system fronts. Pure data; preloaded (no class_name) so it
## works reliably in headless runs.
##
## Visuals are ANIME-styled — bright saturated planets with glowing atmospheres,
## NOT photoreal. Colours below drive the procedural planet builder (planet.gd).
##
## Mission `type` values handled by mission.gd:
##   destroy  — wipe out `target` enemies
##   defend   — keep the guarded object alive for `time` seconds (waves)
##   escort   — keep the convoy alive until it reaches the goal
##   chase    — destroy `target` fleeing enemies before they escape
##   gauntlet — survive/clear the obstacle field, reach the end
##   scan     — fly to `target` scan markers (combat in between)
##   boss     — defeat the planet's alien boss
extends RefCounted

const PLANETS := [
	{
		"id": "earth",
		"name": "EARTH",
		"subtitle": "Home Front — Orbital Defense",
		"color": Color(0.18, 0.52, 1.0),
		"atmo": Color(0.40, 0.80, 1.0),
		"rings": false,
		"model": "res://models/planets/earth.glb",   # real textured 3D Earth
		"missions": [
			# 1 — Patrol that turns into Alina's first real dogfight.
			{"name": "First Flight", "type": "patrol", "target": 5, "waypoints": 3,
			 "desc": "Fly the patrol line over the Pacific grid — then survive your first contact.",
			 "brief": [
				{"who": "REYES", "text": "Rookie Vega, welcome to ARIA. This is a routine patrol over the Pacific grid."},
				{"who": "ALINA", "text": "Copy, Commander. First time flying the line for real."},
				{"who": "REYES", "text": "Hit your patrol markers, keep your eyes open. Easy does it."},
			 ]},
			# 2 — Defend a real station with its own health bar.
			{"name": "Orbital Guard", "type": "defend_target", "time": 50, "station_hp": 40,
			 "desc": "Hold the ARIA relay station against the swarm. If it falls, Earth goes blind.",
			 "brief": [
				{"who": "REYES", "text": "That relay coordinates every gun on the seaboard. Lose it and we go blind."},
				{"who": "ALINA", "text": "Then nothing gets past me."},
				{"who": "SYSTEM", "text": "WARNING — ALIEN SWARM CONVERGING ON RELAY."},
			 ]},
			# 3 — Escort civilian shuttles that fly themselves to the gate.
			{"name": "Evacuation", "type": "escort", "shuttles": 4, "target": 1,
			 "desc": "Escort the civilian shuttles to the orbital gate. Save as many as you can.",
			 "brief": [
				{"who": "REYES", "text": "The gas is rolling over Habitat Seven. Civilian shuttles are punching for orbit."},
				{"who": "ALINA", "text": "Kids on those shuttles, Commander?"},
				{"who": "REYES", "text": "Get them to the gate, Vega. All of them if you can."},
			 ]},
			# 4 — Intercept bombers before they crater a city.
			{"name": "Skyfall", "type": "intercept", "target": 8, "city": 6, "bomber_hp": 5,
			 "desc": "Shoot down the gas bombers before they reach the city below.",
			 "brief": [
				{"who": "SYSTEM", "text": "MULTIPLE BOMBERS INBOUND — TRAJECTORY: NEW CAIRO."},
				{"who": "REYES", "text": "Those bombers carry the gas. One lands, a city block dies."},
				{"who": "ALINA", "text": "Not on my watch. Vectoring to intercept."},
			 ]},
			# 5 — First boss + the reveal that hooks the whole campaign.
			{"name": "The Harbinger", "type": "boss", "target": 1, "boss_hp": 90,
			 "desc": "A carrier has reached Earth. Bring it down — and learn what it was carrying.",
			 "brief": [
				{"who": "SYSTEM", "text": "CONTACT — MASS SIGNATURE BEYOND ANYTHING ON RECORD."},
				{"who": "REYES", "text": "That's a carrier. They sent a carrier to Earth. Vega, you're all we've got up there."},
				{"who": "ALINA", "text": "One rookie against that thing. Okay — let's make history."},
			 ],
			 "outro": [
				{"who": "SYSTEM", "text": "CARRIER DESTROYED. SALVAGING DATA CORE..."},
				{"who": "ALINA", "text": "Commander... the gas isn't made here. It's seeded from orbit — from somewhere past Mars."},
				{"who": "REYES", "text": "Then the war doesn't start on Earth. Pack your gear, Vega. We're going up the gravity well."},
			 ]},
		],
	},
	{
		"id": "mars",
		"name": "MARS",
		"subtitle": "Red Front — Supply Lines",
		"color": Color(0.90, 0.34, 0.16),
		"atmo": Color(1.0, 0.5, 0.30),
		"rings": false,
		"missions": [
			{"name": "Black Box", "type": "recover", "scene": "res://scenes/mars/mars_recovery.tscn",
			 "comic": "mars1_intro",
			 "desc": "Ride the Martian surface and recover the black box from the crashed satellite.",
			 "brief": [
				{"who": "REYES", "text": "Mars, Vega. A relay satellite fell out of orbit and went down on the surface."},
				{"who": "ALINA", "text": "And its black box has whatever it recorded before it died."},
				{"who": "REYES", "text": "Take the bike, follow the scanner, bring that box home."},
			 ]},
			{"name": "Convoy Run", "type": "escort", "shuttles": 4, "target": 2,
			 "desc": "Escort the ore convoy to the orbital lift through the ambush.",
			 "brief": [
				{"who": "REYES", "text": "Those freighters carry the ore that arms the whole front. Get them to the lift."},
				{"who": "ALINA", "text": "Stay on my wing, I'll clear the lane."},
			 ]},
			{"name": "Dome Siege", "type": "defend_target", "time": 55, "station_hp": 45,
			 "desc": "Hold Colony Dome Ares against the swarm until reinforcements arrive.",
			 "brief": [
				{"who": "SYSTEM", "text": "DOME ARES UNDER ASSAULT — SHIELDS DROPPING."},
				{"who": "ALINA", "text": "Civilians in that dome. They are NOT dying today."},
			 ]},
			{"name": "Red Rain", "type": "intercept", "target": 9, "city": 6, "bomber_hp": 5,
			 "desc": "Shoot down the bombers before they crater the colony.",
			 "brief": [
				{"who": "SYSTEM", "text": "BOMBER WAVE INBOUND — TARGET: COLONY SPRAWL."},
				{"who": "REYES", "text": "Same gas, new world. Don't let a single one land, Vega."},
			 ]},
			{"name": "Crimson Titan", "type": "boss", "target": 1, "boss_hp": 100,
			 "desc": "Destroy the Martian alien war-titan.",
			 "brief": [
				{"who": "SYSTEM", "text": "WARLORD-CLASS SIGNATURE RISING FROM OLYMPUS."},
				{"who": "ALINA", "text": "Bigger than the Earth carrier. Good. More to aim at."},
			 ]},
		],
	},
	{
		"id": "venus",
		"name": "VENUS",
		"subtitle": "Acid Front — Cloud War",
		"color": Color(0.96, 0.80, 0.34),
		"atmo": Color(1.0, 0.92, 0.55),
		"rings": false,
		"missions": [
			{"name": "Acid Skies", "type": "scan", "target": 4,
			 "desc": "Scan the alien jammers hidden in the toxic clouds."},
			{"name": "Harvest Halt", "type": "defend", "time": 50, "target": 12,
			 "desc": "Stop the harvester from draining the atmosphere."},
			{"name": "Venusian Wraith", "type": "boss", "target": 1,
			 "desc": "Slay the cloaked cloud-wraith."},
		],
	},
	{
		"id": "saturn",
		"name": "SATURN",
		"subtitle": "Ring Front — The Discovery",
		"color": Color(0.86, 0.72, 0.42),
		"atmo": Color(1.0, 0.90, 0.62),
		"rings": true,
		"missions": [
			{"name": "Ring Runner", "type": "gauntlet", "target": 1,
			 "desc": "Race the alien pack through the ice rings."},
			{"name": "Signal Hunt", "type": "scan", "target": 5,
			 "desc": "Track the source of the colonization signal."},
			{"name": "The Truth", "type": "boss", "target": 1,
			 "desc": "Destroy the relay — and learn what waits on the Moon."},
		],
	},
]

static func planet_count() -> int:
	return PLANETS.size()

static func get_planet(p: int) -> Dictionary:
	return PLANETS[clampi(p, 0, PLANETS.size() - 1)]

static func get_mission(p: int, m: int) -> Dictionary:
	var pl: Dictionary = get_planet(p)
	var ms: Array = pl["missions"]
	return ms[clampi(m, 0, ms.size() - 1)]

static func mission_count(p: int) -> int:
	return get_planet(p)["missions"].size()

## Stable key for save/progress, e.g. "earth:1".
static func mission_key(p: int, m: int) -> String:
	return "%s:%d" % [get_planet(p)["id"], m]
