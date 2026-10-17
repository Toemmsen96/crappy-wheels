extends TextureRect


@export var flames: AnimatedSprite2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	flames.visible = false


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _toggle_flames(visible: bool) -> void:
	flames.visible = visible
	if visible:
		flames.play()
	else:
		flames.stop()
