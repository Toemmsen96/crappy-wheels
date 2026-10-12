extends CanvasLayer

## Tooltips don't wrap, so descriptions are broken into lines of about this many characters.
const TOOLTIP_LINE_LENGTH := 50

@export var level1: PackedScene
## Holds the Level 1 button; gets a row for each of BaseLevels after it.
@export var built_in_levels: Container
## Gets a row for each level saved with the level builder.
@export var custom_levels_list: VBoxContainer
@export var no_levels_label: Label
## Gets a row for each level downloaded from the online level repository.
@export var downloaded_levels_list: VBoxContainer
@export var no_downloads_label: Label
@export var delete_dialog: ConfirmationDialog
## Asks before sharing or updating one of the player's levels, then uploads it.
@export var share_dialog: ShareDialog
## Says how sharing a level went. Hidden until then.
@export var status_label: Label

var _level_to_delete: LevelData
var _level_to_delete_dir := ""


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	for level in BaseLevels.list():
		var button := Button.new()
		button.text = level.name
		button.tooltip_text = _wrap(level.description, TOOLTIP_LINE_LENGTH)
		button.pressed.connect(_play_built_in_level.bind(level))
		built_in_levels.add_child(button)
	_populate_levels()


func _on_LevelButton_pressed() -> void:
	GameState.reset()
	GameState.leaderboard_id = GameState.LEVEL1_LEADERBOARD
	GameState.testing_in_builder = false
	get_tree().change_scene_to_packed(level1)


func _play_built_in_level(level: LevelData) -> void:
	GameState.current_level = level
	GameState.testing_in_builder = false
	GameState.leaderboard_id = level.id
	get_tree().change_scene_to_file(ScenePaths.CUSTOM_LEVEL)


func _on_BrowseButton_pressed() -> void:
	get_tree().change_scene_to_file(ScenePaths.LEVEL_BROWSER)


func _on_BackButton_pressed() -> void:
	get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)


func _on_DeleteDialog_confirmed() -> void:
	var error := LevelLibrary.delete_level(_level_to_delete, _level_to_delete_dir)
	if error != OK:
		push_error("Could not delete level \"%s\": %s" % [_level_to_delete.name, error_string(error)])
	_level_to_delete = null
	_populate_levels()


## The share dialog saved a level with its new description, or found out
## whether it was shared, which the level's row shows.
func _on_ShareDialog_level_changed(_level: LevelData) -> void:
	_populate_levels()


func _populate_levels() -> void:
	_populate_list(custom_levels_list, no_levels_label, LevelLibrary.LEVELS_DIR)
	_populate_list(downloaded_levels_list, no_downloads_label, LevelLibrary.DOWNLOADS_DIR)


func _populate_list(list: VBoxContainer, empty_label: Label, dir_path: String) -> void:
	for child in list.get_children():
		child.queue_free()
	var levels := LevelLibrary.list_levels(dir_path)
	# Copies of Base/ downloaded by older versions of the game: the game comes with
	# those levels, and their own leaderboards stay with the built-in ones.
	levels = levels.filter(func(level: LevelData) -> bool: return not BaseLevels.is_copy(level.id))
	empty_label.visible = levels.is_empty()
	for level in levels:
		list.add_child(_create_level_row(level, dir_path))


func _create_level_row(level: LevelData, dir_path: String) -> HBoxContainer:
	var row := HBoxContainer.new()

	var play_button := Button.new()
	play_button.text = level.name
	play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_button.tooltip_text = _wrap(level.description, TOOLTIP_LINE_LENGTH)
	play_button.pressed.connect(_play_custom_level.bind(level, dir_path))
	row.add_child(play_button)

	# Downloaded levels are replaced on update, so only the player's own levels are editable.
	if dir_path == LevelLibrary.LEVELS_DIR:
		var edit_button := Button.new()
		edit_button.text = "Edit"
		edit_button.pressed.connect(_edit_custom_level.bind(level))
		row.add_child(edit_button)

		var export_button := Button.new()
		export_button.text = "Export"
		export_button.tooltip_text = "Get the level file, e.g. to submit it to the level repository."
		export_button.pressed.connect(LevelLibrary.export_level.bind(level))
		row.add_child(export_button)

		var share_button := Button.new()
		share_button.text = ShareDialog.button_text(level)
		share_button.tooltip_text = ShareDialog.button_tooltip(level)
		share_button.pressed.connect(_confirm_share.bind(level))
		row.add_child(share_button)

	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.pressed.connect(_confirm_delete.bind(level, dir_path))
	row.add_child(delete_button)

	return row


func _play_custom_level(level: LevelData, dir_path: String) -> void:
	GameState.current_level = level
	GameState.testing_in_builder = false
	# Downloaded levels are the same for everyone; the player's own can still change.
	GameState.leaderboard_id = level.id if dir_path == LevelLibrary.DOWNLOADS_DIR else ""
	get_tree().change_scene_to_file(ScenePaths.CUSTOM_LEVEL)


func _edit_custom_level(level: LevelData) -> void:
	GameState.current_level = level
	get_tree().change_scene_to_file(ScenePaths.LEVEL_BUILDER)


func _confirm_delete(level: LevelData, dir_path: String) -> void:
	_level_to_delete = level
	_level_to_delete_dir = dir_path
	delete_dialog.dialog_text = "Delete \"%s\"? This can't be undone." % level.name
	delete_dialog.popup_centered()


func _confirm_share(level: LevelData) -> void:
	share_dialog.ask(level)


func _show_status(text: String) -> void:
	status_label.text = text
	status_label.show()


## Breaks `text` into lines of at most `line_length` characters at spaces, where it can.
static func _wrap(text: String, line_length: int) -> String:
	var lines := PackedStringArray()
	var line := ""
	for word in text.split(" ", false):
		if not line.is_empty() and line.length() + 1 + word.length() > line_length:
			lines.append(line)
			line = ""
		line = word if line.is_empty() else line + " " + word
	if not line.is_empty():
		lines.append(line)
	return "\n".join(lines)
