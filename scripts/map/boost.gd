class_name Boost
extends Node2D


@export var collider: Area2D
## Impulse given to the player when it touches the boost.
@export var strength := 1000.0


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	collider.body_entered.connect(_on_collider_body_entered)

func _on_collider_body_entered(_body: Node) -> void:
	if _body.name == "Player":
		# Push the way the arrows on the texture point (right when unrotated), so rotating the boost rotates the push.
		_body.push(Vector2.RIGHT.rotated(global_rotation) * strength)
		Sfx.play(Sfx.WEEE)

