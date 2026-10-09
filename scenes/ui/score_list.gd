class_name ScoreList
extends GridContainer
## Shows scores from BackendClient.fetch_scores() in four columns: rank, name,
## time, and a button to watch the time's replay if one was uploaded.

## A Watch button was pressed. `replay_path` is the replay's path in the level repository.
signal replay_requested(replay_path: String)


func _ready() -> void:
	columns = 4


## Replaces the rows with `scores`. Returns the row of the player's own score,
## which the backend marks with "you", or null if it isn't among them.
func show_scores(scores: Array[Dictionary]) -> Control:
	for child in get_children():
		child.queue_free()
	var own_row: Control = null
	for score in scores:
		var own: bool = score.get("you") == true
		_add_label("%d." % int(score["rank"]))
		var name_label := _add_label(score["name"] + (" (you)" if own else ""))
		# The name column takes the free space.
		name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_add_label(BackendClient.format_time(score["time_ms"]))
		if score.has("replay"):
			var watch_button := Button.new()
			watch_button.text = "Watch"
			watch_button.tooltip_text = "Watch the replay of this time."
			watch_button.pressed.connect(replay_requested.emit.bind(score["replay"]))
			add_child(watch_button)
		else:
			add_child(Control.new()) # Keeps the grid's columns in line.
		if own:
			own_row = name_label
	return own_row


## Turns the Watch buttons on or off, e.g. while a replay downloads.
func set_watch_disabled(disabled: bool) -> void:
	for child in get_children():
		if child is Button:
			child.disabled = disabled


func _add_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	add_child(label)
	return label
