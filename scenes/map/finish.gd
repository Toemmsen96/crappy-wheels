extends Node2D

## The backend cuts longer names to this length.
const MAX_PLAYER_NAME := 24
## Rows of the leaderboard shown at once. The list scrolls to the rest, so the
## screen still fits in a low window, such as a phone held sideways.
const VISIBLE_SCORES := 4

@export var finishcollider: Area2D
@export var time_label: Label
@export var finish_ui: CanvasLayer
@export var backend: BackendClient
## Holds the leaderboard and the name entry; hidden for levels without a leaderboard.
@export var leaderboard_section: Control
## Shown in place of the scores while there are none: loading, empty, failed.
@export var score_message: Label
@export var score_scroll: ScrollContainer
@export var score_list: ScoreList
@export var name_edit: LineEdit
@export var submit_button: Button
@export var leaderboard_status: Label
@export var return_button: Button
@export_group("Replay")
@export var level_repository: LevelRepository
@export var watch_replay_button: Button
## Puts the replay online. Only the replay of the player's best time can go
## there, so it waits until the leaderboard has the time.
@export var upload_replay_button: Button
@export var replay_file_button: Button
## Says how uploading the replay went. Hidden until then.
@export var replay_status: Label

var _time_ms := 0
## The run that just finished, and where it was saved, or "" if saving failed.
var _replay: ReplayData = null
var _replay_file := ""
## Whether the leaderboard holds this run's time as the player's best.
var _is_best_time := false
var _is_uploading := false
var _is_uploaded := false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	finishcollider.body_entered.connect(_on_finishcollider_body_entered)
	finish_ui.hide()
	leaderboard_section.hide()
	name_edit.max_length = MAX_PLAYER_NAME
	name_edit.text_submitted.connect(func(_text: String) -> void: _submit_time())
	# Changing the name allows submitting the time under the new one.
	name_edit.text_changed.connect(func(_text: String) -> void: submit_button.disabled = false)
	submit_button.pressed.connect(_submit_time)
	watch_replay_button.pressed.connect(_watch_own_replay)
	upload_replay_button.pressed.connect(_upload_replay)
	replay_file_button.pressed.connect(func() -> void: ReplayLibrary.export_replay(_replay_file))
	score_list.replay_requested.connect(_watch_leaderboard_replay)
	# Until the run has a replay.
	watch_replay_button.disabled = true
	replay_file_button.disabled = true
	if GameState.testing_in_builder:
		return_button.text = "Back to Level Builder"


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _on_finishcollider_body_entered(_body: Node) -> void:
	# The car can touch the flag again after finishing; the time is already taken.
	if _body.name != "Player" or GameState.is_stopped:
		return
	GameState.finish_level()
	Sfx.play(Sfx.FINISH)
	# Rounded like the time that goes to the leaderboard, so both show the same.
	_time_ms = roundi(GameState.time_elapsed * 1000.0)
	time_label.text = "Time: %s" % BackendClient.format_time(_time_ms)
	_save_replay(_body.get_node_or_null("ReplayRecorder") as ReplayRecorder)
	finish_ui.show()
	upload_replay_button.visible = GameState.has_leaderboard()
	if not GameState.has_leaderboard():
		return

	leaderboard_section.show()
	name_edit.text = GameState.player_name
	if GameState.player_name.is_empty():
		leaderboard_status.text = "Enter a name to put your time on the leaderboard."
		_load_scores()
	else:
		_submit_time()


func _submit_time() -> void:
	# Disabled while a time is on its way and once it has arrived.
	if submit_button.disabled:
		return
	var player_name := name_edit.text.strip_edges()
	if player_name.is_empty():
		leaderboard_status.text = "Enter a name first."
		return
	GameState.set_player_name(player_name)
	submit_button.disabled = true
	leaderboard_status.text = "Submitting your time..."
	var answer := await backend.submit_score(GameState.leaderboard_id, GameState.ensure_player_id(), player_name, _time_ms)
	if answer.is_empty():
		leaderboard_status.text = "Could not submit your time: %s" % backend.last_error
		submit_button.disabled = false
		# The board is still worth showing, e.g. after submitting too often.
		_load_scores()
		return
	_is_best_time = int(answer["best_time_ms"]) == _time_ms
	_update_upload_button()
	var rank := int(answer["rank"])
	if answer.get("improved") == true:
		leaderboard_status.text = "New best time for %s! Rank %d." % [player_name, rank]
	else:
		leaderboard_status.text = "%s's best is still %s, rank %d." % [player_name, BackendClient.format_time(answer["best_time_ms"]), rank]
	_load_scores()


## Takes the replay from the car's recorder and saves it as a file.
func _save_replay(recorder: ReplayRecorder) -> void:
	if recorder == null:
		return
	_replay = recorder.finish(_time_ms)
	var level := _played_level()
	if GameState.has_leaderboard() or level == null:
		_replay.level_id = GameState.leaderboard_id if not GameState.leaderboard_id.is_empty() else GameState.LEVEL1_LEADERBOARD
	else:
		_replay.level_id = level.id
	_replay.level_name = level.name if level != null else "Level 1"
	_replay.player_name = GameState.player_name
	_replay_file = ReplayLibrary.save_replay(_replay)
	watch_replay_button.disabled = false
	replay_file_button.disabled = _replay_file.is_empty()


func _update_upload_button() -> void:
	var can_upload := _replay != null and _replay.can_upload() and _is_best_time
	upload_replay_button.disabled = not can_upload or _is_uploading or _is_uploaded
	if _replay == null or _is_uploaded or _is_uploading:
		return
	if not _replay.can_upload():
		_show_replay_status("This run is too long to upload its replay.")
	elif not _is_best_time:
		_show_replay_status("You were faster before. Only the replay of your best time can be uploaded.")
	else:
		_show_replay_status("")


func _upload_replay() -> void:
	if upload_replay_button.disabled:
		return
	_is_uploading = true
	_update_upload_button()
	_show_replay_status("Uploading the replay...")
	_replay.player_name = GameState.player_name
	var answer := await backend.submit_replay(GameState.leaderboard_id, GameState.ensure_player_id(), _replay)
	_is_uploading = false
	if answer.is_empty():
		var error := backend.last_error
		if backend.last_status == 409:
			# Not the best time after all, e.g. beaten on another device meanwhile.
			_is_best_time = false
		_update_upload_button()
		_show_replay_status("Could not upload the replay: %s" % error)
		return
	_is_uploaded = true
	_update_upload_button()
	_show_replay_status("Replay uploaded! Everyone can watch it from the leaderboard now.")
	_load_scores()


func _watch_own_replay() -> void:
	if _replay != null:
		GameState.watch_replay(_replay, _played_level(), get_tree().current_scene.scene_file_path)


func _watch_leaderboard_replay(replay_path: String) -> void:
	score_list.set_watch_disabled(true)
	leaderboard_status.text = "Loading the replay..."
	var replay := await level_repository.download_replay(replay_path)
	if replay == null:
		leaderboard_status.text = "Could not load the replay: %s" % level_repository.last_error
		score_list.set_watch_disabled(false)
		return
	GameState.watch_replay(replay, _played_level(), get_tree().current_scene.scene_file_path)


## The builder level being played, or null for Level 1, which is a scene of its own.
func _played_level() -> LevelData:
	if get_tree().current_scene.scene_file_path == ScenePaths.CUSTOM_LEVEL:
		return GameState.current_level
	return null


func _show_replay_status(text: String) -> void:
	replay_status.text = text
	replay_status.visible = not text.is_empty()


func _load_scores() -> void:
	var scores := await backend.fetch_scores(GameState.leaderboard_id, 10, GameState.player_id)
	var own_row := score_list.show_scores(scores)
	if not backend.last_error.is_empty():
		score_message.text = "Could not load the leaderboard: %s" % backend.last_error
	elif scores.is_empty():
		score_message.text = "No times yet."
	score_message.visible = scores.is_empty()
	score_scroll.visible = not scores.is_empty()
	if scores.is_empty():
		return

	var rows := mini(scores.size(), VISIBLE_SCORES)
	var row_height: float = score_list.get_child(-1).get_combined_minimum_size().y
	score_scroll.custom_minimum_size.y = rows * row_height + (rows - 1) * score_list.get_theme_constant("v_separation")
	if own_row != null:
		# Deferred, so the new rows have their places by then.
		score_scroll.ensure_control_visible.call_deferred(own_row)


func _on_ReturnToMenuButton_pressed() -> void:
	if GameState.testing_in_builder:
		get_tree().change_scene_to_file(ScenePaths.LEVEL_BUILDER)
	else:
		get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)

func _on_RestartButton_pressed() -> void:
	GameState.reset()
	get_tree().reload_current_scene()
