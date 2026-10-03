class_name LevelData
extends RefCounted
## A level made with the level builder.
##
## Levels are stored as plain JSON rather than as Godot scenes or resources,
## because loading those can run scripts embedded in them. As long as every
## level, local or downloaded, is read through from_json()/from_dict(), levels
## shared by other players are safe to load.

const FORMAT_VERSION := 1
const MAX_NAME_LENGTH := 64
const MAX_AUTHOR_LENGTH := 64
const MAX_OBJECTS := 2000
const MAX_COORDINATE := 100000.0
const MIN_TILE_LENGTH := 5.0
const MAX_TILE_LENGTH := 5000.0
const MIN_BALL_SCALE := 0.1
const MAX_BALL_SCALE := 10.0
const MIN_BOOST_SCALE := 0.25
const MAX_BOOST_SCALE := 5.0
const DEFAULT_BOOST_STRENGTH := 1000.0
const MIN_BOOST_STRENGTH := 0.0
const MAX_BOOST_STRENGTH := 10000.0

static var _id_regex := RegEx.create_from_string("^[A-Za-z0-9_-]{1,64}$")

## Unique id, also used as the file name. Lets an uploaded copy be matched to its original.
var id := ""
var name := ""
var author := ""
var start := Vector2.ZERO
var finish := Vector2.ZERO
## Floor tiles as {"position": Vector2, "rotation": float, "length": float, "collision": bool}.
## Tiles and balls with collision off are only decoration: the car passes through them.
var tiles: Array[Dictionary] = []
## Balls as {"position": Vector2, "scale": float, "collision": bool}.
var balls: Array[Dictionary] = []
## Boosts as {"position": Vector2, "rotation": float, "scale": float, "strength": float}.
## Rotation 0 pushes right; strength is the impulse given to the car.
var boosts: Array[Dictionary] = []
## Not saved: whether the builder has changes that aren't written to disk yet.
var has_unsaved_changes := false


static func create_default() -> LevelData:
	var level := LevelData.new()
	level.id = generate_id()
	level.finish = Vector2(220, -10)
	level.tiles.append(make_tile(Vector2(-80, 23), Vector2(300, 23)))
	return level


static func generate_id() -> String:
	return Crypto.new().generate_random_bytes(8).hex_encode()


static func is_valid_id(value: String) -> bool:
	return _id_regex.search(value) != null


## Makes a floor tile that runs along the line from `from` to `to`.
static func make_tile(from: Vector2, to: Vector2) -> Dictionary:
	return {
		"position": (from + to) / 2.0,
		"rotation": (to - from).angle(),
		"length": clampf(from.distance_to(to), MIN_TILE_LENGTH, MAX_TILE_LENGTH),
		"collision": true,
	}


static func make_ball(position: Vector2, scale: float, collision := true) -> Dictionary:
	return {
		"position": position,
		"scale": clampf(scale, MIN_BALL_SCALE, MAX_BALL_SCALE),
		"collision": collision,
	}


static func make_boost(position: Vector2, rotation: float, scale := 1.0, strength := DEFAULT_BOOST_STRENGTH) -> Dictionary:
	return {
		"position": position,
		"rotation": wrapf(rotation, -PI, PI),
		"scale": clampf(scale, MIN_BOOST_SCALE, MAX_BOOST_SCALE),
		"strength": clampf(strength, MIN_BOOST_STRENGTH, MAX_BOOST_STRENGTH),
	}


func object_count() -> int:
	return tiles.size() + balls.size() + boosts.size()


func to_dict() -> Dictionary:
	var tile_dicts: Array[Dictionary] = []
	for tile in tiles:
		tile_dicts.append({
			"x": _round(tile["position"].x),
			"y": _round(tile["position"].y),
			"rotation": _round(tile["rotation"]),
			"length": _round(tile["length"]),
			"collision": tile["collision"],
		})
	var ball_dicts: Array[Dictionary] = []
	for ball in balls:
		ball_dicts.append({
			"x": _round(ball["position"].x),
			"y": _round(ball["position"].y),
			"scale": _round(ball["scale"]),
			"collision": ball["collision"],
		})
	var boost_dicts: Array[Dictionary] = []
	for boost in boosts:
		boost_dicts.append({
			"x": _round(boost["position"].x),
			"y": _round(boost["position"].y),
			"rotation": _round(boost["rotation"]),
			"scale": _round(boost["scale"]),
			"strength": _round(boost["strength"]),
		})
	return {
		"format_version": FORMAT_VERSION,
		"id": id,
		"name": name,
		"author": author,
		"start": _vector_to_dict(start),
		"finish": _vector_to_dict(finish),
		"tiles": tile_dicts,
		"balls": ball_dicts,
		"boosts": boost_dicts,
	}


func to_json() -> String:
	return JSON.stringify(to_dict(), "\t")


static func from_json(text: String) -> LevelData:
	var json := JSON.new()
	if json.parse(text) != OK:
		return null
	return from_dict(json.data)


## Builds a level from untrusted data, such as a file or a download.
## Returns null if the data isn't a level. Out of range values are clamped
## and malformed objects are skipped.
static func from_dict(data: Variant) -> LevelData:
	if not (data is Dictionary):
		return null
	var version: Variant = data.get("format_version")
	if not _is_number(version) or version > FORMAT_VERSION:
		return null

	var start_position: Variant = _read_vector(data.get("start"))
	var finish_position: Variant = _read_vector(data.get("finish"))
	var raw_tiles: Variant = data.get("tiles", [])
	var raw_balls: Variant = data.get("balls", [])
	# Added after the first levels were published, so it's optional.
	var raw_boosts: Variant = data.get("boosts", [])
	if start_position == null or finish_position == null:
		return null
	if not (raw_tiles is Array and raw_balls is Array and raw_boosts is Array):
		return null

	var level := LevelData.new()
	var raw_id: Variant = data.get("id")
	level.id = raw_id if raw_id is String and is_valid_id(raw_id) else generate_id()
	level.name = _read_string(data.get("name"), MAX_NAME_LENGTH)
	if level.name.is_empty():
		level.name = "Untitled"
	level.author = _read_string(data.get("author"), MAX_AUTHOR_LENGTH)
	level.start = start_position
	level.finish = finish_position

	for raw_tile: Variant in raw_tiles:
		if level.object_count() >= MAX_OBJECTS:
			break
		if raw_tile is Dictionary and _is_number(raw_tile.get("rotation")) and _is_number(raw_tile.get("length")):
			var position: Variant = _read_vector(raw_tile)
			if position != null:
				level.tiles.append({
					"position": position,
					"rotation": wrapf(raw_tile["rotation"], -PI, PI),
					"length": clampf(raw_tile["length"], MIN_TILE_LENGTH, MAX_TILE_LENGTH),
					"collision": _read_collision(raw_tile),
				})

	for raw_ball: Variant in raw_balls:
		if level.object_count() >= MAX_OBJECTS:
			break
		if raw_ball is Dictionary and _is_number(raw_ball.get("scale")):
			var position: Variant = _read_vector(raw_ball)
			if position != null:
				level.balls.append(make_ball(position, raw_ball["scale"], _read_collision(raw_ball)))

	for raw_boost: Variant in raw_boosts:
		if level.object_count() >= MAX_OBJECTS:
			break
		if raw_boost is Dictionary and _is_number(raw_boost.get("rotation")):
			var position: Variant = _read_vector(raw_boost)
			# Boost size and strength were added later, so older boosts have neither.
			var boost_scale: Variant = raw_boost.get("scale", 1.0)
			var strength: Variant = raw_boost.get("strength", DEFAULT_BOOST_STRENGTH)
			if position != null and _is_number(boost_scale) and _is_number(strength):
				level.boosts.append(make_boost(position, raw_boost["rotation"], boost_scale, strength))

	return level


static func _vector_to_dict(vector: Vector2) -> Dictionary:
	return {"x": _round(vector.x), "y": _round(vector.y)}


## Rounds away float noise like 0.400000005960464, so level files stay readable and diff cleanly.
static func _round(value: float) -> float:
	return snappedf(value, 0.0001)


## Returns a Vector2 from a dictionary with numeric "x" and "y", or null.
static func _read_vector(raw: Variant) -> Variant:
	if not (raw is Dictionary and _is_number(raw.get("x")) and _is_number(raw.get("y"))):
		return null
	return Vector2(
		clampf(raw["x"], -MAX_COORDINATE, MAX_COORDINATE),
		clampf(raw["y"], -MAX_COORDINATE, MAX_COORDINATE),
	)


## Collision was added later, so objects without it are solid.
static func _read_collision(raw: Dictionary) -> bool:
	var collision: Variant = raw.get("collision", true)
	return collision if collision is bool else true


static func _read_string(raw: Variant, max_length: int) -> String:
	if not (raw is String):
		return ""
	return raw.replace("\n", " ").strip_edges().left(max_length)


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
