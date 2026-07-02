## Zeta Legacy — Audio Manager (autoload)
## Pools AudioStreamPlayers for SFX and loops the ambient music track.
## Sounds are synthesized WAVs in res://audio/ (see tools/gen_sfx.py).
extends Node

const POOL_SIZE := 14

var _players: Array[AudioStreamPlayer] = []
var _next: int = 0
var _streams: Dictionary = {}
var _music: AudioStreamPlayer

func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)

	_streams = {
		"shoot": _try_load("res://audio/shoot.wav"),
		"enemy_shoot": _try_load("res://audio/enemy_shoot.wav"),
		"explosion": _try_load("res://audio/explosion.wav"),
		"hit": _try_load("res://audio/hit.wav"),
		"player_hit": _try_load("res://audio/player_hit.wav"),
		"wave": _try_load("res://audio/wave.wav"),
		"powerup": _try_load("res://audio/powerup.wav"),
	}

	_music = AudioStreamPlayer.new()
	add_child(_music)
	var mstream := _try_load("res://audio/music.wav")
	if mstream:
		_music.stream = mstream
		_music.volume_db = -13.0
		# Loop by replaying on finish (robust regardless of import loop flags).
		_music.finished.connect(func(): _music.play())
		_music.play()

func _try_load(path: String) -> AudioStream:
	if ResourceLoader.exists(path):
		return load(path)
	return null

## Play a one-shot sound by key, with optional volume (dB) and pitch jitter.
func play(key: String, volume_db: float = 0.0, pitch_jitter: float = 0.0) -> void:
	var stream: AudioStream = _streams.get(key)
	if stream == null:
		return
	var p := _players[_next]
	_next = (_next + 1) % POOL_SIZE
	p.stream = stream
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()
