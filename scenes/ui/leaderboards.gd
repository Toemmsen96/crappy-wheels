extends CanvasLayer
## Shows the leaderboard of each level that has one: Level 1 and the downloaded levels.

## The most scores the backend hands out at once.
const SCORE_LIMIT := 100

@export var backend: BackendClient
@export var level_picker: OptionButton
@export var refresh_button: Button
## Says that the scores are loading, missing or could not be loaded. Hidden otherwise.
@export var status_label: Label
@export var score_scroll: ScrollContainer
@export var score_list: ScoreList
## Downloads the replays the leaderboards link to.
@export var level_repository: LevelRepository

## Leaderboard of each item in level_picker.
var _leaderboard_ids := PackedStringArray()


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_add_level("Level 1", GameState.LEVEL1_LEADERBOARD)
	for level in LevelLibrary.list_levels(LevelLibrary.DOWNLOADS_DIR):
		_add_level(level.name, level.id)
	# Start with the level played last, if it has a leaderboard.
	level_picker.select(maxi(_leaderboard_ids.find(GameState.leaderboard_id), 0))
	score_list.replay_requested.connect(_watch_replay)
	_load_scores()


func _on_LevelPicker_item_selected(_index: int) -> void:
	_load_scores()


func _on_RefreshButton_pressed() -> void:
	_load_scores()


func _on_BackButton_pressed() -> void:
	get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)


func _add_level(level_name: String, leaderboard_id: String) -> void:
	level_picker.add_item(level_name)
	_leaderboard_ids.append(leaderboard_id)


func _load_scores() -> void:
	# One load at a time: the picker and the button stay off until the answer is in.
	_set_busy(true)
	_show_status("Loading the leaderboard...")
	var scores := await backend.fetch_scores(_leaderboard_ids[level_picker.selected], SCORE_LIMIT, GameState.player_id)
	_set_busy(false)
	var own_row := score_list.show_scores(scores)
	if not backend.last_error.is_empty():
		_show_status("Could not load the leaderboard: %s" % backend.last_error)
	elif scores.is_empty():
		_show_status("No times yet. Finish the level to set the first one!")
	else:
		_show_status("")
	score_scroll.scroll_vertical = 0
	if own_row != null:
		# Deferred, so the new rows have their places by then.
		score_scroll.ensure_control_visible.call_deferred(own_row)


func _watch_replay(replay_path: String) -> void:
	var leaderboard_id := _leaderboard_ids[level_picker.selected]
	var level: LevelData = null
	if leaderboard_id != GameState.LEVEL1_LEADERBOARD:
		level = LevelLibrary.load_level(leaderboard_id, LevelLibrary.DOWNLOADS_DIR)
		if level == null:
			_show_status("The level isn't downloaded anymore, so its replays can't be shown.")
			return
	_set_busy(true)
	_show_status("Loading the replay...")
	var replay := await level_repository.download_replay(replay_path)
	_set_busy(false)
	if replay == null:
		_show_status("Could not load the replay: %s" % level_repository.last_error)
		return
	# Coming back, the leaderboard of this level is shown again.
	GameState.leaderboard_id = leaderboard_id
	GameState.watch_replay(replay, level, ScenePaths.LEADERBOARDS)


func _show_status(text: String) -> void:
	status_label.text = text
	status_label.visible = not text.is_empty()


func _set_busy(busy: bool) -> void:
	level_picker.disabled = busy
	refresh_button.disabled = busy
	score_list.set_watch_disabled(busy)
