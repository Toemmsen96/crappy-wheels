extends Node
## Plays the sound effects. An autoload, so a sound keeps playing when the
## scene changes, such as the click of a button that opens another screen.

const CLICK := preload("res://assets/audio/click.wav")
## A hard hit on the car.
const CRASH := preload("res://assets/audio/crash.wav")
## The car's roof bonking the ground.
const DONG := preload("res://assets/audio/dong.wav")
const FINISH := preload("res://assets/audio/finish.wav")
## Resetting to the start.
const WAHWAH := preload("res://assets/audio/wahwah.wav")
## The engine revving as a level starts.
const REV := preload("res://assets/audio/wroooo.wav")
## A boost kicking in, from the boost key or a boost pad.
const WEEE := preload("res://assets/audio/weee.wav")

## Gain of each sound in dB. The recordings differ in loudness by up to 19 dB;
## these were measured to even them out without going over full scale.
var _gain := {CLICK: 9.0, CRASH: 8.0, DONG: 5.0, FINISH: 13.0, WAHWAH: 17.0, REV: 5.0, WEEE: -2.0}
## One player per sound, each able to overlap itself.
var _players := {}


func _ready() -> void:
	# Buttons in the pause menu click too.
	process_mode = Node.PROCESS_MODE_ALWAYS
	for stream: AudioStream in _gain:
		var player := AudioStreamPlayer.new()
		player.stream = stream
		player.max_polyphony = 3
		add_child(player)
		_players[stream] = player
	# Every button clicks, including the ones scenes make in code.
	get_tree().node_added.connect(_on_node_added)


## Plays `stream`, one of the constants above, `volume_db` louder than usual
## (or quieter, if negative).
func play(stream: AudioStream, volume_db := 0.0) -> void:
	var player: AudioStreamPlayer = _players[stream]
	player.volume_db = _gain[stream] + volume_db
	player.play()


func is_playing(stream: AudioStream) -> bool:
	return _players[stream].playing


func _on_node_added(node: Node) -> void:
	if node is BaseButton:
		node.pressed.connect(play.bind(CLICK))
