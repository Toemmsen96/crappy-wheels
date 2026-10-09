@tool
class_name FloorTile
extends Node2D
## A floor piece. Change `length` rather than scaling the node, so the outline
## keeps its thickness and only the inside of the texture stretches.

## Height of the floor, and its length when nothing else is set.
const SIZE := 20.0
## How far the drawn outline reaches past the collision shape on each side.
const OUTLINE_OVERHANG := 1.0
## World units per texture pixel.
const PIXEL_SCALE := (SIZE + 2.0 * OUTLINE_OVERHANG) / 254.0

@export var shape: CollisionShape2D
@export var texture: NinePatchRect
@export_range(LevelData.MIN_TILE_LENGTH, LevelData.MAX_TILE_LENGTH, 0.1, "or_greater", "suffix:px")
var length := SIZE:
	set(value):
		length = value
		if is_node_ready():
			_resize()


func _ready() -> void:
	_resize()


func _resize() -> void:
	(shape.shape as RectangleShape2D).size = Vector2(length, SIZE)
	var drawn_size := Vector2(length, SIZE) + Vector2.ONE * 2.0 * OUTLINE_OVERHANG
	texture.scale = Vector2.ONE * PIXEL_SCALE
	texture.size = drawn_size / PIXEL_SCALE
	texture.position = -drawn_size / 2.0
