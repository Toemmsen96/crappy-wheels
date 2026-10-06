class_name ScoreList
extends GridContainer
## Shows scores from BackendClient.fetch_scores() in three columns: rank, name, time.


func _ready() -> void:
	columns = 3


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
		if own:
			own_row = name_label
	return own_row


func _add_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	add_child(label)
	return label
