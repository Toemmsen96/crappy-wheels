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

var _time_ms := 0


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
	finish_ui.show()
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
	var answer := await backend.submit_score(GameState.leaderboard_id, player_name, _time_ms)
	if answer.is_empty():
		leaderboard_status.text = "Could not submit your time: %s" % backend.last_error
		submit_button.disabled = false
		# The board is still worth showing, e.g. after submitting too often.
		_load_scores()
		return
	var rank := int(answer["rank"])
	if answer.get("improved") == true:
		leaderboard_status.text = "New best time for %s! Rank %d." % [player_name, rank]
	else:
		leaderboard_status.text = "%s's best is still %s, rank %d." % [player_name, BackendClient.format_time(answer["best_time_ms"]), rank]
	_load_scores()


func _load_scores() -> void:
	var scores := await backend.fetch_scores(GameState.leaderboard_id)
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
	get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)

func _on_RestartButton_pressed() -> void:
	GameState.reset()
	get_tree().reload_current_scene()
