extends Node2D

@export var finishcollider: Area2D

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	finishcollider.body_entered.connect(_on_finishcollider_body_entered)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_finishcollider_body_entered(_body: Node) -> void:
	if _body.name == "Player":
		GameState.finish_level()
