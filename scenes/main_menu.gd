extends CanvasLayer

@export var level_select_scene: PackedScene
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.



func _on_PlayButton_pressed() -> void:
	get_tree().change_scene_to_packed(level_select_scene)


func _on_LevelBuilderButton_pressed() -> void:
	# Start the builder with a new level.
	GameState.current_level = null
	get_tree().change_scene_to_file(ScenePaths.LEVEL_BUILDER)


func _on_LeaderboardsButton_pressed() -> void:
	get_tree().change_scene_to_file(ScenePaths.LEADERBOARDS)
