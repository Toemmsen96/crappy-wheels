class_name LevelSpawner
## Creates the scene nodes for the objects in a LevelData level.

const FLOOR_TILE_SCENE := preload("res://scenes/map/floortile.tscn")
const BALL_SCENE := preload("res://scenes/ball.tscn")
const FINISH_SCENE := preload("res://scenes/finish.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")

## Size of floortile.tscn at scale 1. Tiles are stretched along x to their length.
const TILE_SIZE := 20.0
## Collision radius of ball.tscn at scale 1.
const BALL_RADIUS := 19.31


## Adds all tiles, balls and the finish of `level` to `parent`. The player is left out.
static func spawn_level(level: LevelData, parent: Node) -> void:
	for tile in level.tiles:
		parent.add_child(spawn_tile(tile))
	for ball in level.balls:
		parent.add_child(spawn_ball(ball))
	parent.add_child(spawn_finish(level.finish))


static func spawn_tile(tile: Dictionary) -> Node2D:
	var node: Node2D = FLOOR_TILE_SCENE.instantiate()
	node.position = tile["position"]
	node.rotation = tile["rotation"]
	node.scale = Vector2(tile["length"] / TILE_SIZE, 1.0)
	return node


static func spawn_ball(ball: Dictionary) -> Node2D:
	var node: Node2D = BALL_SCENE.instantiate()
	node.position = ball["position"]
	node.scale = Vector2.ONE * ball["scale"]
	return node


static func spawn_finish(position: Vector2) -> Node2D:
	var node: Node2D = FINISH_SCENE.instantiate()
	node.position = position
	return node


static func spawn_player(position: Vector2) -> Node2D:
	var node: Node2D = PLAYER_SCENE.instantiate()
	node.position = position
	return node
