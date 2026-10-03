class_name LevelBuilder
extends Node2D
## Editor for building levels in-game. Levels are saved with LevelLibrary.

const GRID_SIZE := 10.0
## Grid lines are drawn every this many grid cells.
const GRID_LINE_EVERY := 5
const ZOOM_STEP := 1.1
const MIN_ZOOM := 0.25
const MAX_ZOOM := 4.0
const PAN_SPEED := 600.0
## Extra distance around objects that still counts as clicking them when erasing.
const ERASE_MARGIN := 4.0
const GRID_COLOR := Color(1, 1, 1, 0.1)
const PREVIEW_COLOR := Color(1, 1, 1, 0.5)
const ERASE_COLOR := Color(1, 0.2, 0.2, 0.9)

@export var ui: MapBuilderUI
@export var camera: Camera2D
@export var objects_root: Node2D
@export var start_marker: Node2D
## Draws previews above the level objects.
@export var overlay: Node2D

var _level: LevelData
var _tool := MapBuilderUI.Tool.FLOOR
# Spawned nodes, in the same order as _level.tiles and _level.balls.
var _tile_nodes: Array[Node2D] = []
var _ball_nodes: Array[Node2D] = []
var _finish_node: Node2D
# Tiles and balls placed in this session, most recent last, for undo.
var _placed_nodes: Array[Node2D] = []
var _is_drawing_floor := false
var _floor_start := Vector2.ZERO
var _confirming_discard := false


func _ready() -> void:
	if GameState.current_level == null:
		GameState.current_level = LevelData.create_default()
	_level = GameState.current_level
	GameState.testing_in_builder = false
	GameState.stop()

	for tile in _level.tiles:
		_spawn_tile_node(tile)
	for ball in _level.balls:
		_spawn_ball_node(ball)
	_finish_node = LevelSpawner.spawn_finish(_level.finish)
	objects_root.add_child(_finish_node)
	start_marker.position = _level.start
	camera.position = _level.start

	ui.level_name = _level.name
	ui.tool_selected.connect(_on_tool_selected)
	ui.level_name_changed.connect(_on_level_name_changed)
	ui.save_pressed.connect(_save)
	ui.test_pressed.connect(_test)
	ui.back_pressed.connect(_back)
	overlay.draw.connect(_draw_overlay)


func _process(delta: float) -> void:
	# Checked here rather than on release, since the button may be released over the UI.
	if _is_drawing_floor and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_floor()

	if not (get_viewport().gui_get_focus_owner() is LineEdit):
		var direction := Input.get_vector(Inputs.MOVE_LEFT, Inputs.MOVE_RIGHT, Inputs.MOVE_UP, Inputs.MOVE_DOWN)
		camera.position += direction * PAN_SPEED * delta / camera.zoom.x

	queue_redraw()
	overlay.queue_redraw()


# Only gets input the UI didn't use, so clicks on the toolbar don't edit the level.
func _unhandled_input(event: InputEvent) -> void:
	var mouse_button := event as InputEventMouseButton
	var mouse_motion := event as InputEventMouseMotion
	var key := event as InputEventKey
	if mouse_button and mouse_button.pressed:
		match mouse_button.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_at(mouse_button.position, ZOOM_STEP)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_at(mouse_button.position, 1.0 / ZOOM_STEP)
			MOUSE_BUTTON_LEFT:
				get_viewport().gui_release_focus()
				_use_tool(get_global_mouse_position())
	elif mouse_motion and mouse_motion.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
		camera.position -= mouse_motion.relative / camera.zoom
	elif key and key.pressed and key.keycode == KEY_Z and key.is_command_or_control_pressed():
		_undo()
		get_viewport().set_input_as_handled()


func _draw() -> void:
	# Grid, drawn under the level objects since those are children of this node.
	var step := GRID_SIZE * GRID_LINE_EVERY
	if step * camera.zoom.x < 8.0:
		return # Too zoomed out for the grid to be useful.
	var view := get_canvas_transform().affine_inverse() * get_viewport_rect()
	var x := floorf(view.position.x / step) * step
	while x <= view.end.x:
		draw_line(Vector2(x, view.position.y), Vector2(x, view.end.y), GRID_COLOR)
		x += step
	var y := floorf(view.position.y / step) * step
	while y <= view.end.y:
		draw_line(Vector2(view.position.x, y), Vector2(view.end.x, y), GRID_COLOR)
		y += step


func _draw_overlay() -> void:
	var mouse := get_global_mouse_position()
	var line_width := 2.0 / camera.zoom.x
	match _tool:
		MapBuilderUI.Tool.FLOOR:
			if _is_drawing_floor:
				overlay.draw_line(_floor_start, _snap(mouse), PREVIEW_COLOR, LevelSpawner.TILE_SIZE)
		MapBuilderUI.Tool.BALL:
			var radius := LevelSpawner.BALL_RADIUS * ui.ball_size
			overlay.draw_arc(_snap(mouse), radius, 0.0, TAU, 32, PREVIEW_COLOR, line_width)
		MapBuilderUI.Tool.ERASE:
			var node := _object_at(mouse)
			var index := _tile_nodes.find(node)
			if index != -1:
				var tile := _level.tiles[index]
				var length: float = tile["length"]
				overlay.draw_set_transform(tile["position"], tile["rotation"])
				overlay.draw_rect(Rect2(-length / 2.0, -LevelSpawner.TILE_SIZE / 2.0, length, LevelSpawner.TILE_SIZE), ERASE_COLOR, false, line_width)
				overlay.draw_set_transform(Vector2.ZERO)
			index = _ball_nodes.find(node)
			if index != -1:
				var ball := _level.balls[index]
				overlay.draw_arc(ball["position"], LevelSpawner.BALL_RADIUS * ball["scale"], 0.0, TAU, 32, ERASE_COLOR, line_width)


func _use_tool(point: Vector2) -> void:
	var grid_point := _snap(point)
	match _tool:
		MapBuilderUI.Tool.FLOOR:
			_is_drawing_floor = true
			_floor_start = grid_point
		MapBuilderUI.Tool.BALL:
			_add_ball(LevelData.make_ball(grid_point, ui.ball_size))
		MapBuilderUI.Tool.START:
			_level.start = grid_point
			start_marker.position = grid_point
			_mark_changed()
		MapBuilderUI.Tool.FINISH:
			_level.finish = grid_point
			_finish_node.position = grid_point
			_mark_changed()
		MapBuilderUI.Tool.ERASE:
			var node := _object_at(point)
			if node != null:
				_remove_object(node)


func _finish_floor() -> void:
	_is_drawing_floor = false
	var end := _snap(get_global_mouse_position())
	if _floor_start.distance_to(end) >= LevelData.MIN_TILE_LENGTH:
		_add_tile(LevelData.make_tile(_floor_start, end))


func _add_tile(tile: Dictionary) -> void:
	if not _has_room_for_object():
		return
	_level.tiles.append(tile)
	_placed_nodes.append(_spawn_tile_node(tile))
	_mark_changed()


func _add_ball(ball: Dictionary) -> void:
	if not _has_room_for_object():
		return
	_level.balls.append(ball)
	_placed_nodes.append(_spawn_ball_node(ball))
	_mark_changed()


func _spawn_tile_node(tile: Dictionary) -> Node2D:
	var node := LevelSpawner.spawn_tile(tile)
	objects_root.add_child(node)
	_tile_nodes.append(node)
	return node


func _spawn_ball_node(ball: Dictionary) -> Node2D:
	var node := LevelSpawner.spawn_ball(ball)
	objects_root.add_child(node)
	_ball_nodes.append(node)
	return node


func _has_room_for_object() -> bool:
	if _level.object_count() < LevelData.MAX_OBJECTS:
		return true
	ui.show_status("A level can have at most %d objects." % LevelData.MAX_OBJECTS)
	return false


## Removes a tile or ball node and its data from the level.
func _remove_object(node: Node2D) -> void:
	var index := _tile_nodes.find(node)
	if index != -1:
		_tile_nodes.remove_at(index)
		_level.tiles.remove_at(index)
	else:
		index = _ball_nodes.find(node)
		_ball_nodes.remove_at(index)
		_level.balls.remove_at(index)
	_placed_nodes.erase(node)
	node.queue_free()
	_mark_changed()


func _undo() -> void:
	if not _placed_nodes.is_empty():
		_remove_object(_placed_nodes.back())


## Returns the tile or ball node at `point`, preferring balls and recently placed objects.
func _object_at(point: Vector2) -> Node2D:
	for i in range(_level.balls.size() - 1, -1, -1):
		var ball := _level.balls[i]
		if point.distance_to(ball["position"]) <= LevelSpawner.BALL_RADIUS * ball["scale"] + ERASE_MARGIN:
			return _ball_nodes[i]
	for i in range(_level.tiles.size() - 1, -1, -1):
		var tile := _level.tiles[i]
		var local: Vector2 = (point - tile["position"]).rotated(-tile["rotation"])
		if absf(local.x) <= tile["length"] / 2.0 + ERASE_MARGIN and absf(local.y) <= LevelSpawner.TILE_SIZE / 2.0 + ERASE_MARGIN:
			return _tile_nodes[i]
	return null


func _snap(point: Vector2) -> Vector2:
	return point.snapped(Vector2.ONE * GRID_SIZE) if ui.snap_enabled else point


## Zooms by `factor` while keeping the world point under `screen_position` in place.
func _zoom_at(screen_position: Vector2, factor: float) -> void:
	var old_zoom := camera.zoom.x
	var new_zoom := clampf(old_zoom * factor, MIN_ZOOM, MAX_ZOOM)
	var offset := screen_position - get_viewport_rect().size / 2.0
	camera.position += offset / old_zoom - offset / new_zoom
	camera.zoom = Vector2.ONE * new_zoom


func _mark_changed() -> void:
	_level.has_unsaved_changes = true
	_confirming_discard = false


func _on_tool_selected(tool: MapBuilderUI.Tool) -> void:
	_tool = tool
	_is_drawing_floor = false


func _on_level_name_changed(new_name: String) -> void:
	_level.name = new_name
	_mark_changed()


func _save() -> void:
	if _level.name.is_empty():
		ui.show_status("Give your level a name before saving.")
		return
	var error := LevelLibrary.save_level(_level)
	if error != OK:
		ui.show_status("Could not save the level: %s" % error_string(error))
		return
	_level.has_unsaved_changes = false
	ui.show_status("Saved \"%s\"." % _level.name)


func _test() -> void:
	GameState.testing_in_builder = true
	get_tree().change_scene_to_file(ScenePaths.CUSTOM_LEVEL)


func _back() -> void:
	if _level.has_unsaved_changes and not _confirming_discard:
		_confirming_discard = true
		ui.show_status("You have unsaved changes. Press Back again to discard them.")
		return
	GameState.current_level = null
	get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)
