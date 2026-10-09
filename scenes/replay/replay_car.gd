class_name ReplayCar
extends Node2D
## The car as a replay shows it: the player's car without physics, put where a ReplayData frame says.

@export var front_wheel: Node2D
@export var rear_wheel: Node2D


## Shows a frame from ReplayData.sample().
func show_frame(frame: Dictionary) -> void:
	position = frame["position"]
	rotation = frame["rotation"]
	# Wheel rotations are recorded in world space; the wheels turn with the car.
	front_wheel.rotation = frame["front_wheel"] - frame["rotation"]
	rear_wheel.rotation = frame["rear_wheel"] - frame["rotation"]
