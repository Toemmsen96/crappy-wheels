extends Control
## Pauses the game while shown. Escape toggles it.
##
## Runs with process_mode ALWAYS (set in the scene) so it keeps working while the tree is paused.

@export var continue_button: Button
@export var main_menu_button: Button


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	InputHandler.cancel_just_pressed.connect(toggle_pause)
	continue_button.pressed.connect(toggle_pause)
	main_menu_button.pressed.connect(_on_main_menu_button_pressed)
	if GameState.testing_in_builder:
		main_menu_button.text = "Back to Level Builder"


func toggle_pause() -> void:
	visible = not visible
	get_tree().paused = visible


func _on_main_menu_button_pressed() -> void:
	# The pause would otherwise carry over into the next scene.
	get_tree().paused = false
	if GameState.testing_in_builder:
		get_tree().change_scene_to_file(ScenePaths.LEVEL_BUILDER)
	else:
		get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)
