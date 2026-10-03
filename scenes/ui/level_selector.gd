extends CanvasLayer


@export var level1: PackedScene
## Gets a row for each level saved with the level builder.
@export var custom_levels_list: VBoxContainer
@export var no_levels_label: Label
@export var delete_dialog: ConfirmationDialog

var _level_to_delete: LevelData


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_populate_custom_levels()


func _on_LevelButton_pressed() -> void:
	GameState.reset()
	get_tree().change_scene_to_packed(level1)


func _on_BackButton_pressed() -> void:
	get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)


func _on_DeleteDialog_confirmed() -> void:
	var error := LevelLibrary.delete_level(_level_to_delete)
	if error != OK:
		push_error("Could not delete level \"%s\": %s" % [_level_to_delete.name, error_string(error)])
	_level_to_delete = null
	_populate_custom_levels()


func _populate_custom_levels() -> void:
	for child in custom_levels_list.get_children():
		child.queue_free()
	var levels := LevelLibrary.list_levels()
	no_levels_label.visible = levels.is_empty()
	for level in levels:
		custom_levels_list.add_child(_create_level_row(level))


func _create_level_row(level: LevelData) -> HBoxContainer:
	var row := HBoxContainer.new()

	var play_button := Button.new()
	play_button.text = level.name
	play_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	play_button.pressed.connect(_play_custom_level.bind(level))
	row.add_child(play_button)

	var edit_button := Button.new()
	edit_button.text = "Edit"
	edit_button.pressed.connect(_edit_custom_level.bind(level))
	row.add_child(edit_button)

	var delete_button := Button.new()
	delete_button.text = "Delete"
	delete_button.pressed.connect(_confirm_delete.bind(level))
	row.add_child(delete_button)

	return row


func _play_custom_level(level: LevelData) -> void:
	GameState.current_level = level
	GameState.testing_in_builder = false
	get_tree().change_scene_to_file(ScenePaths.CUSTOM_LEVEL)


func _edit_custom_level(level: LevelData) -> void:
	GameState.current_level = level
	get_tree().change_scene_to_file(ScenePaths.LEVEL_BUILDER)


func _confirm_delete(level: LevelData) -> void:
	_level_to_delete = level
	delete_dialog.dialog_text = "Delete \"%s\"? This can't be undone." % level.name
	delete_dialog.popup_centered()
