extends Node
# gdlint: disable=class-definitions-order
# Declarations here are grouped for readability (constants beside the tables
# they describe, fields beside the build code that fills them) rather than
# strictly consts-before-vars. Ordering is a style rule with no runtime effect;
# see docs/ASSESSMENT.md.

## Autoloaded sound player.  Sounds are generated WAVs in res://audio — no
## external assets, so the project stays self-contained.

const SOUNDS := {
	"tap": "res://audio/tap.wav",
	"select": "res://audio/select.wav",
	"deal": "res://audio/deal.wav",
	"capture": "res://audio/capture.wav",
	"scopa": "res://audio/scopa.wav",
	"favor": "res://audio/favor.wav",
	"oath": "res://audio/oath.wav",
	"win": "res://audio/win.wav",
	"lose": "res://audio/lose.wav",
	"tick": "res://audio/tick.wav",
	"deny": "res://audio/deny.wav",
}

var _streams := {}
var _players: Array = []
var enabled := true
var _next := 0


func _ready() -> void:
	for i in range(8):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		p.volume_db = -6.0
		add_child(p)
		_players.append(p)
	for key in SOUNDS:
		var path: String = SOUNDS[key]
		if ResourceLoader.exists(path):
			_streams[key] = load(path)


func play(key: String, volume_db: float = -8.0, pitch: float = 1.0) -> void:
	if not enabled or not _streams.has(key):
		return
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[key]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()
