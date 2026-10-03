extends Node2D
## Plays a level made with the level builder, taken from GameState.current_level.


func _ready() -> void:
	var level := GameState.current_level
	if level == null:
		push_error("No builder level selected to play.")
		# Deferred, since the tree is still busy adding this scene.
		get_tree().change_scene_to_file.call_deferred(ScenePaths.LEVEL_SELECTOR)
		return

	LevelSpawner.spawn_level(level, self)
	add_child(LevelSpawner.spawn_player(level.start))
	GameState.reset()
