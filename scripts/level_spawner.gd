class_name LevelSpawner
## Creates the scene nodes for the objects in a LevelData level.

const FLOOR_TILE_SCENE := preload("res://scenes/map/floortile.tscn")
const BALL_SCENE := preload("res://scenes/ball.tscn")
const FINISH_SCENE := preload("res://scenes/finish.tscn")
const BOOST_SCENE := preload("res://scenes/map/boost.tscn")
const PLAYER_SCENE := preload("res://scenes/player.tscn")

## Height of floortile.tscn. Tiles are made as long as their length, not scaled.
const TILE_SIZE := FloorTile.SIZE
## Collision radius of ball.tscn at scale 1.
const BALL_RADIUS := 19.31
## Size of the square boost.tscn at scale 1.
const BOOST_SIZE := 20.0


## Adds all tiles, balls, boosts and the finish of `level` to `parent`. The player is left out.
static func spawn_level(level: LevelData, parent: Node) -> void:
	for tile in level.tiles:
		parent.add_child(spawn_tile(tile))
	for ball in level.balls:
		parent.add_child(spawn_ball(ball))
	for boost in level.boosts:
		parent.add_child(spawn_boost(boost))
	parent.add_child(spawn_finish(level.finish))


static func spawn_tile(tile: Dictionary) -> Node2D:
	var node: Node2D = FLOOR_TILE_SCENE.instantiate()
	apply_tile(node, tile)
	return node


static func spawn_ball(ball: Dictionary) -> Node2D:
	var node: Node2D = BALL_SCENE.instantiate()
	apply_ball(node, ball)
	return node


static func spawn_boost(boost: Dictionary) -> Node2D:
	var node: Node2D = BOOST_SCENE.instantiate()
	apply_boost(node, boost)
	return node


## Updates a spawned tile after its data changed.
static func apply_tile(node: Node2D, tile: Dictionary) -> void:
	node.position = tile["position"]
	node.rotation = tile["rotation"]
	(node as FloorTile).length = tile["length"]
	_set_collision(node, tile["collision"])


static func apply_ball(node: Node2D, ball: Dictionary) -> void:
	node.position = ball["position"]
	node.scale = Vector2.ONE * ball["scale"]
	_set_collision(node, ball["collision"])


static func apply_boost(node: Node2D, boost: Dictionary) -> void:
	node.position = boost["position"]
	node.rotation = boost["rotation"]
	node.scale = Vector2.ONE * boost["scale"]
	(node as Boost).strength = boost["strength"]


## Turns the object's collision shapes on or off. Without them the car passes through.
static func _set_collision(node: Node, enabled: bool) -> void:
	for shape: CollisionShape2D in node.find_children("*", "CollisionShape2D", true, false):
		shape.disabled = not enabled


static func spawn_finish(position: Vector2) -> Node2D:
	var node: Node2D = FINISH_SCENE.instantiate()
	node.position = position
	return node


static func spawn_player(position: Vector2) -> Node2D:
	var node: Node2D = PLAYER_SCENE.instantiate()
	node.position = position
	return node
