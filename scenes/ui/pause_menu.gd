extends Control
## Pauses the game while shown. Escape toggles it.
##
## Runs with process_mode ALWAYS (set in the scene) so it keeps working while the tree is paused.

@export var continue_button: Button
@export var settings_button: Button
@export var main_menu_button: Button
## The pause menu's own panel, hidden while the settings are open.
@export var card: Control

## The settings screen while it's open over the level.
var _settings: SettingsMenu


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	InputHandler.cancel_just_pressed.connect(toggle_pause)
	continue_button.pressed.connect(toggle_pause)
	settings_button.pressed.connect(_open_settings)
	main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	if GameState.testing_in_builder:
		main_menu_button.text = "Back to Level Builder"


func toggle_pause() -> void:
	# Escape backs out of the settings first, unless a control is waiting for it as its new key.
	if _settings:
		if not _settings.is_listening():
			_settings.close()
		return
	visible = not visible
	get_tree().paused = visible


func _open_settings() -> void:
	# Loaded by path, as the settings screen links back to the main menu.
	_settings = load(ScenePaths.SETTINGS).instantiate()
	_settings.opened_in_game = true
	# Above the in-game UI's layer.
	_settings.layer = 2
	_settings.closed.connect(_on_settings_closed)
	card.hide()
	add_child(_settings)


func _on_settings_closed() -> void:
	_settings = null
	card.show()
	settings_button.grab_focus()


func _on_main_menu_button_pressed() -> void:
	# The pause would otherwise carry over into the next scene.
	get_tree().paused = false
	if GameState.testing_in_builder:
		get_tree().change_scene_to_file(ScenePaths.LEVEL_BUILDER)
	else:
		get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)
