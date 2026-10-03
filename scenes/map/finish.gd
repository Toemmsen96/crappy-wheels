extends Node2D

@export var finishcollider: Area2D
@export var time_label: Label
@export var finish_ui: CanvasLayer

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	finishcollider.body_entered.connect(_on_finishcollider_body_entered)
	finish_ui.hide()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	pass

func _on_finishcollider_body_entered(_body: Node) -> void:
	if _body.name == "Player":
		GameState.finish_level()
		time_label.text = str(GameState.time_elapsed).pad_decimals(3)
		finish_ui.show()


func _on_ReturnToMenuButton_pressed() -> void:
	get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)

func _on_RestartButton_pressed() -> void:
	GameState.reset()
	get_tree().reload_current_scene()