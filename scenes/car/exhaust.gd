class_name Exhaust
extends TextureRect
## The car's exhaust pipe: puffs smoke all the time, and shoots flames while boosting.

@export var flames: AnimatedSprite2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	flames.visible = false


## Shows the flames and plays their animation, or hides and stops them.
func toggle_flames(on: bool) -> void:
	flames.visible = on
	if on:
		flames.play()
	else:
		flames.stop()
