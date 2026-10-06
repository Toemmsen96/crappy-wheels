extends CanvasLayer


@export var level1: PackedScene
## Gets a row for each level saved with the level builder.
@export var custom_levels_list: VBoxContainer
@export var no_levels_label: Label
## Gets a row for each level downloaded from the online level repository.
@export var downloaded_levels_list: VBoxContainer
@export var no_downloads_label: Label
@export var delete_dialog: ConfirmationDialog
@export var share_dialog: ConfirmationDialog
## Says how sharing a level went. Hidden until then.
@export var status_label: Label
@export var backend: BackendClient

var _level_to_delete: LevelData
var _level_to_delete_dir := ""
var _level_to_share: LevelData
## Set while a level is being uploaded, so only one upload runs at a time.
var _sharing := false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_populate_levels()


func _on_LevelButton_pressed() -> void:
	GameState.reset()
	GameState.leaderboard_id = GameState.LEVEL1_LEADERBOARD
	GameState.testing_in_builder = false
	get_tree().change_scene_to_packed(level1)


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


func _on_ShareDialog_confirmed() -> void:
	if _sharing or _level_to_share == null:
		return
	var level := _level_to_share
	_level_to_share = null
	_sharing = true
	_show_status("Sharing \"%s\"..." % level.name)
	var answer := await backend.share_level(level)
	_sharing = false
	if not answer.is_empty():
		_show_status("Shared \"%s\"! Everyone can get it under Browse Online Levels now." % level.name)
	elif backend.last_status == 409:
		_show_status("\"%s\" was already shared. Changes to a shared level can't be shared again yet." % level.name)
	else:
		_show_status("Could not share \"%s\": %s" % [level.name, backend.last_error])


func _populate_levels() -> void:
	_populate_list(custom_levels_list, no_levels_label, LevelLibrary.LEVELS_DIR)
	_populate_list(downloaded_levels_list, no_downloads_label, LevelLibrary.DOWNLOADS_DIR)


func _populate_list(list: VBoxContainer, empty_label: Label, dir_path: String) -> void:
	for child in list.get_children():
		child.queue_free()
	var levels := LevelLibrary.list_levels(dir_path)
	empty_label.visible = levels.is_empty()
	for level in levels:
		list.add_child(_create_level_row(level, dir_path))


func _create_level_row(level: LevelData, dir_path: String) -> HBoxContainer:
	var row := HBoxContainer.new()

	var play_button := Button.new()
	play_button.text = level.name
	play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
		share_button.text = "Share"
		share_button.tooltip_text = "Upload the level so everyone can play it."
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
	if _sharing:
		return
	_level_to_share = level
	share_dialog.dialog_text = ("Share \"%s\" with everyone? It goes into the online levels right away, " \
			+ "and changes you make to it afterwards can't be shared.") % level.name
	share_dialog.popup_centered()


func _show_status(text: String) -> void:
	status_label.text = text
	status_label.show()
