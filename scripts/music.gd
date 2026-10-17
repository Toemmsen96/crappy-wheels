extends Node
## Plays the music. An autoload, so a track carries on from one scene to the
## next that uses it instead of starting over, such as between menu screens or
## when retrying a race.

const MENU := preload("res://assets/audio/menu.wav")
const RACE := preload("res://assets/audio/race.wav")
## Gain of the music in dB, so it sits under the sound effects.
const GAIN := -20.0
## The track each scene plays. Scenes not listed are silent.
const SCENE_TRACKS := {
	ScenePaths.MAIN_MENU: MENU,
	ScenePaths.LEVEL_SELECTOR: MENU,
	ScenePaths.LEVEL_BROWSER: MENU,
	ScenePaths.LEADERBOARDS: MENU,
	ScenePaths.CREDITS: MENU,
	ScenePaths.SETTINGS: MENU,
	ScenePaths.LEVEL_1: RACE,
	ScenePaths.CUSTOM_LEVEL: RACE,
}

var _player := AudioStreamPlayer.new()


func _ready() -> void:
	# Keeps playing in the pause menu.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player.volume_db = GAIN
	_player.bus = AudioBuses.MUSIC
	add_child(_player)
	get_tree().scene_changed.connect(_on_scene_changed)
	# The first scene is already loaded before scene_changed can fire.
	_on_scene_changed.call_deferred()


func _on_scene_changed() -> void:
	var scene := get_tree().current_scene
	var track: AudioStream = SCENE_TRACKS.get(scene.scene_file_path) if scene else null
	if track == null:
		_player.stop()
	elif track != _player.stream or not _player.playing:
		_player.stream = track
		_player.play()
