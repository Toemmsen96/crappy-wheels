extends Node2D
## Plays GameState.replay: the level it was recorded on, with the car moving
## the way it did in the run.

const PARALLAX_SCENE := preload("res://scenes/parallax.tscn")
## Playback speeds the speed button steps through.
const SPEEDS: Array[float] = [0.25, 0.5, 1.0, 2.0]
const NORMAL_SPEED_INDEX := 2
## The car's speed for the engine sound is measured over this many seconds of the run.
const SPEED_SAMPLE_SECONDS := 0.1

@export var car: ReplayCar
@export var engine_sound: AudioStreamPlayer
@export var title_label: Label
@export var time_label: Label
## Shows how far into the run the replay is; dragging it jumps there.
@export var time_slider: HSlider
@export var play_button: Button
@export var restart_button: Button
@export var speed_button: Button
@export var back_button: Button

var _replay: ReplayData
## Seconds into the run being shown.
var _time := 0.0
var _is_playing := true
var _speed_index := NORMAL_SPEED_INDEX
var _last_controls := 0


func _ready() -> void:
	_replay = GameState.replay
	if _replay == null:
		push_error("No replay to play.")
		# Deferred, since the tree is still busy adding this scene.
		get_tree().change_scene_to_file.call_deferred(ScenePaths.MAIN_MENU)
		return
	_add_level()
	# Nothing here is a run: the clock stays still and the finish ignores the car.
	GameState.stop()

	var who := _replay.player_name if not _replay.player_name.is_empty() else "Replay"
	title_label.text = "%s: %s" % [who, BackendClient.format_time(_replay.time_ms)]
	if not _replay.level_name.is_empty():
		title_label.text += " on %s" % _replay.level_name
	time_slider.max_value = _replay.duration()
	time_slider.step = 0.01
	time_slider.value_changed.connect(_jump_to)
	play_button.pressed.connect(_toggle_playing)
	restart_button.pressed.connect(_restart)
	speed_button.pressed.connect(_next_speed)
	back_button.pressed.connect(_back)
	InputHandler.cancel_just_pressed.connect(_back)
	_update_buttons()
	_show_frame()


func _process(delta: float) -> void:
	if _is_playing:
		_time = minf(_time + delta * SPEEDS[_speed_index], _replay.duration())
		if _time >= _replay.duration():
			_is_playing = false
			_update_buttons()
	_show_frame()
	_update_engine_sound(delta)


func _add_level() -> void:
	var level: Node
	if GameState.replay_level == null:
		level = load(ScenePaths.LEVEL_1).instantiate()
		# Only the track: the player's car would bring its camera, controls and timer along.
		var player := level.get_node_or_null("Player")
		if player != null:
			level.remove_child(player)
			player.free()
	else:
		level = Node2D.new()
		level.add_child(PARALLAX_SCENE.instantiate())
		LevelSpawner.spawn_level(GameState.replay_level, level)
	add_child(level)
	move_child(level, 0)


func _show_frame() -> void:
	var frame := _replay.sample(_time)
	car.show_frame(frame)
	time_slider.set_value_no_signal(_time)
	time_label.text = "%s / %s" % [BackendClient.format_time(_time * 1000.0), BackendClient.format_time(_replay.time_ms)]
	# The boost makes its sound, as in the run, when it's pressed.
	var controls: int = frame["controls"]
	if _is_playing and controls & ReplayData.BOOST and not _last_controls & ReplayData.BOOST:
		Sfx.play(Sfx.WEEE)
	_last_controls = controls


## Pitches the engine up with the car's speed, like the player's car does.
func _update_engine_sound(delta: float) -> void:
	var before: Vector2 = _replay.sample(_time - SPEED_SAMPLE_SECONDS)["position"]
	var after: Vector2 = _replay.sample(_time)["position"]
	var speed := clampf(before.distance_to(after) / SPEED_SAMPLE_SECONDS / Player.ENGINE_TOP_SPEED, 0.0, 1.5)
	var pitch := lerpf(Player.ENGINE_IDLE_PITCH, Player.ENGINE_TOP_PITCH, speed)
	var volume := lerpf(Player.ENGINE_IDLE_DB, Player.ENGINE_TOP_DB, minf(speed, 1.0))
	if not _is_playing:
		volume = -60.0
	var weight := minf(1.0, delta * Player.ENGINE_RESPONSE)
	engine_sound.pitch_scale = lerpf(engine_sound.pitch_scale, pitch * SPEEDS[_speed_index] if _is_playing else pitch, weight)
	engine_sound.volume_db = lerpf(engine_sound.volume_db, volume, weight)


func _jump_to(seconds: float) -> void:
	_time = seconds
	_last_controls = _replay.sample(_time)["controls"]


func _toggle_playing() -> void:
	if not _is_playing and _time >= _replay.duration():
		_time = 0.0 # Played to the end: play from the start again.
	_is_playing = not _is_playing
	_update_buttons()


func _restart() -> void:
	_time = 0.0
	_is_playing = true
	_update_buttons()


func _next_speed() -> void:
	_speed_index = (_speed_index + 1) % SPEEDS.size()
	_update_buttons()


func _update_buttons() -> void:
	play_button.text = "Pause" if _is_playing else "Play"
	speed_button.text = "%sx" % String.num(SPEEDS[_speed_index], 2)


func _back() -> void:
	# A level gone back to starts a new run.
	GameState.reset()
	var scene := GameState.replay_return_scene if not GameState.replay_return_scene.is_empty() else ScenePaths.MAIN_MENU
	get_tree().change_scene_to_file(scene)
