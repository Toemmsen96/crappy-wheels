extends Control

@export var time_label: Label

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	time_label.text = str(GameState.time_elapsed).pad_decimals(2)
	pass
