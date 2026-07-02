## Zeta Legacy — Comic Cutscene Data
## Sequences of graphic-novel panels (image + caption) for Story Mode. Panels are
## AI-generated JPEGs under assets/comics/, runtime-loaded (the editor importer is
## broken on this device — see memory). Pure data, preloaded (no class_name).
##
## Each entry: { img, text, who? }.  `who` present = a spoken line (coloured by
## speaker); absent = narration.
extends RefCounted

const DIR := "res://assets/comics/"

# Chapter 1 — The Silent Moon (intro: Earth → launch → arrival).
const CHAPTER1_INTRO := [
	{"img": "01_prologue.jpg",
	 "text": "2089. Humanity has spread far beyond Earth. The Moon is no longer just a research outpost — it is our first permanent colony."},
	{"img": "02_colony.jpg",
	 "text": "Luna-1. Three hundred scientists, engineers, soldiers and miners. For six years, everything ran perfectly."},
	{"img": "03_blackout.jpg",
	 "text": "Then, one ordinary day, every signal from Luna-1 went dark. No distress call. No explosion. No warning."},
	{"img": "04_elena.jpg", "who": "CMDR ELENA",
	 "text": "If anyone receives this... do not come to the Moon. We found something beneath the surface... it's awake."},
	{"img": "05_aria.jpg",
	 "text": "You are Captain Aria — one of Earth's finest young pilots. Your orders: reach the Moon, find them, and bring them home."},
	{"img": "06_launch.jpg", "who": "COMMANDER",
	 "text": "Once you leave Earth, Captain, you are on your own. Bring our people home."},
	{"img": "07_silent_moon.jpg",
	 "text": "The long journey ends in silence. No radio. No satellites answer. The Moon is completely still..."},
]

# Chapter 1 — finale (after the surface mission): the discovery + the awakening.
const CHAPTER1_FINALE := [
	{"img": "08_ghostbase.jpg",
	 "text": "Luna-1 stands abandoned. Coffee still on the tables, computers still running. No bodies. No people. Only silence."},
	{"img": "09_crystal.jpg",
	 "text": "Beneath a forbidden crater, a black crystal taller than any tower pulses with cold blue light. Nothing here was built by human hands."},
	{"img": "10_awaken.jpg", "who": "???",
	 "text": "You should never have awakened us."},
]

# Mars Mission 1 — Black Box recovery briefing.
const MARS1_INTRO := [
	{"img": "12_mars_crash.jpg",
	 "text": "A relay satellite, dragged down from a decaying orbit, slams into the Martian desert. Somewhere out in the red, its black box still pulses."},
	{"img": "05_aria.jpg", "who": "ALINA",
	 "text": "One bike. One signal. I'll find what it was trying to tell us."},
]

static func get_sequence(id: String) -> Array:
	match id:
		"chapter1_finale":
			return CHAPTER1_FINALE
		"mars1_intro":
			return MARS1_INTRO
		_:
			return CHAPTER1_INTRO
