extends CanvasLayer


@export var level1: PackedScene


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.



func _on_LevelButton_pressed() -> void:
	get_tree().change_scene_to_packed(level1)