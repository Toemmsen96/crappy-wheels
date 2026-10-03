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
## Extra distance around objects that still counts as clicking them.
const PICK_MARGIN := 4.0
## Shorter boost drags than this keep the boost pointing right.
const MIN_BOOST_DRAG := 10.0
## Rotations snap to, and Q/E rotate by, this many degrees when snapping is on.
const SNAPPED_ANGLE_STEP := 15.0
## Q/E rotate by this many degrees when snapping is off.
const FREE_ANGLE_STEP := 1.0
## R/F multiply or divide the selected object's size by this.
const RESIZE_FACTOR := 1.1
# Size slider ranges for common sizes. Typing in the size box goes further, up to the LevelData limits.
const FLOOR_LENGTH_SLIDER_MIN := 10.0
const FLOOR_LENGTH_SLIDER_MAX := 1000.0
const BALL_SIZE_SLIDER_MIN := 0.2
const BALL_SIZE_SLIDER_MAX := 3.0
const BOOST_SIZE_SLIDER_MIN := 0.5
const BOOST_SIZE_SLIDER_MAX := 3.0
const GRID_COLOR := Color(1, 1, 1, 0.1)
const PREVIEW_COLOR := Color(1, 1, 1, 0.5)
const SELECT_COLOR := Color(1, 0.85, 0.2, 0.9)
const ERASE_COLOR := Color(1, 0.2, 0.2, 0.9)
## Opacity of objects with collision off, so they stand out from solid ones while building.
const NO_COLLISION_ALPHA := 0.4

@export var ui: MapBuilderUI
@export var camera: Camera2D
@export var objects_root: Node2D
@export var start_marker: Node2D
## Draws previews above the level objects.
@export var overlay: Node2D

var _level: LevelData
var _tool := MapBuilderUI.Tool.FLOOR
# Spawned nodes, in the same order as _level.tiles, _level.balls and _level.boosts.
var _tile_nodes: Array[Node2D] = []
var _ball_nodes: Array[Node2D] = []
var _boost_nodes: Array[Node2D] = []
var _finish_node: Node2D
# Objects placed in this session, most recent last, for undo.
var _placed_nodes: Array[Node2D] = []
# Floors and boosts are placed by dragging: floors from end to end, boosts from
# where they go towards the direction they push.
var _is_dragging := false
var _drag_start := Vector2.ZERO
# The object picked with the select tool, and whether it's being dragged around.
var _selected: Node2D = null
var _is_moving := false
var _move_from_position := Vector2.ZERO
var _move_from_mouse := Vector2.ZERO
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
	for boost in _level.boosts:
		_spawn_boost_node(boost)
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
	ui.selection_rotation_changed.connect(_on_selection_rotation_changed)
	ui.selection_size_changed.connect(_on_selection_size_changed)
	ui.selection_collision_toggled.connect(_on_selection_collision_toggled)
	ui.selection_strength_changed.connect(_on_selection_strength_changed)
	overlay.draw.connect(_draw_overlay)


func _process(delta: float) -> void:
	# Checked here rather than on release, since the button may be released over the UI.
	var left_held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _is_dragging and not left_held:
		_finish_drag()
	if _is_moving:
		if left_held:
			_move_selected()
		else:
			_is_moving = false

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
	elif key and key.pressed:
		_handle_key(key)


func _handle_key(key: InputEventKey) -> void:
	if key.keycode == KEY_Z and key.is_command_or_control_pressed():
		_undo()
	elif _selected == null or key.is_command_or_control_pressed():
		return
	else:
		var angle_step := deg_to_rad(SNAPPED_ANGLE_STEP if ui.snap_enabled else FREE_ANGLE_STEP)
		match key.keycode:
			KEY_Q:
				_rotate_selected(-angle_step)
			KEY_E:
				_rotate_selected(angle_step)
			KEY_R:
				_resize_selected(RESIZE_FACTOR)
			KEY_F:
				_resize_selected(1.0 / RESIZE_FACTOR)
			KEY_C:
				_set_selected_collision(not _data_of(_selected).get("collision", true))
			KEY_DELETE, KEY_BACKSPACE:
				_remove_object(_selected)
			_:
				return
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
			if _is_dragging:
				overlay.draw_line(_drag_start, _snap(mouse), PREVIEW_COLOR, LevelSpawner.TILE_SIZE)
		MapBuilderUI.Tool.BALL:
			var radius := LevelSpawner.BALL_RADIUS * ui.ball_size
			overlay.draw_arc(_snap(mouse), radius, 0.0, TAU, 32, PREVIEW_COLOR, line_width)
		MapBuilderUI.Tool.BOOST:
			if _is_dragging:
				_draw_boost_outline(_drag_start, _boost_rotation(_drag_start, _snap(mouse)), 1.0, PREVIEW_COLOR, line_width)
			else:
				_draw_boost_outline(_snap(mouse), 0.0, 1.0, PREVIEW_COLOR, line_width)
		MapBuilderUI.Tool.ERASE:
			var node := _object_at(mouse)
			if node != null:
				_draw_object_outline(node, ERASE_COLOR, line_width)
	if _selected != null:
		_draw_object_outline(_selected, SELECT_COLOR, line_width)


func _draw_object_outline(node: Node2D, color: Color, line_width: float) -> void:
	var data := _data_of(node)
	if _tile_nodes.has(node):
		var length: float = data["length"]
		overlay.draw_set_transform(data["position"], data["rotation"])
		overlay.draw_rect(Rect2(-length / 2.0, -LevelSpawner.TILE_SIZE / 2.0, length, LevelSpawner.TILE_SIZE), color, false, line_width)
		overlay.draw_set_transform(Vector2.ZERO)
	elif _ball_nodes.has(node):
		overlay.draw_arc(data["position"], LevelSpawner.BALL_RADIUS * data["scale"], 0.0, TAU, 32, color, line_width)
	else:
		_draw_boost_outline(data["position"], data["rotation"], data["scale"], color, line_width)


## Draws a boost's square with an arrow showing the direction it pushes.
func _draw_boost_outline(at: Vector2, angle: float, boost_scale: float, color: Color, line_width: float) -> void:
	var half := LevelSpawner.BOOST_SIZE * boost_scale / 2.0
	overlay.draw_set_transform(at, angle)
	overlay.draw_rect(Rect2(-half, -half, half * 2.0, half * 2.0), color, false, line_width)
	overlay.draw_line(Vector2(-half, 0), Vector2(half * 2.5, 0), color, line_width)
	overlay.draw_line(Vector2(half * 2.5, 0), Vector2(half * 1.7, -half * 0.6), color, line_width)
	overlay.draw_line(Vector2(half * 2.5, 0), Vector2(half * 1.7, half * 0.6), color, line_width)
	overlay.draw_set_transform(Vector2.ZERO)


func _use_tool(point: Vector2) -> void:
	var grid_point := _snap(point)
	match _tool:
		MapBuilderUI.Tool.SELECT:
			_select(_object_at(point))
			if _selected != null:
				_is_moving = true
				_move_from_position = _data_of(_selected)["position"]
				_move_from_mouse = point
		MapBuilderUI.Tool.FLOOR, MapBuilderUI.Tool.BOOST:
			_is_dragging = true
			_drag_start = grid_point
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


func _finish_drag() -> void:
	_is_dragging = false
	var end := _snap(get_global_mouse_position())
	match _tool:
		MapBuilderUI.Tool.FLOOR:
			if _drag_start.distance_to(end) >= LevelData.MIN_TILE_LENGTH:
				_add_tile(LevelData.make_tile(_drag_start, end))
		MapBuilderUI.Tool.BOOST:
			_add_boost(LevelData.make_boost(_drag_start, _boost_rotation(_drag_start, end)))


## Rotation for a boost at `from` that pushes towards `to`. Points right for short drags.
func _boost_rotation(from: Vector2, to: Vector2) -> float:
	if from.distance_to(to) < MIN_BOOST_DRAG:
		return 0.0
	return _snap_angle((to - from).angle())


func _select(node: Node2D) -> void:
	_selected = node
	_is_moving = false
	if node == null:
		ui.hide_selection()
	elif _tile_nodes.has(node):
		ui.show_selection("Floor", "Length", FLOOR_LENGTH_SLIDER_MIN, FLOOR_LENGTH_SLIDER_MAX, 1.0, true, true, false)
	elif _ball_nodes.has(node):
		ui.show_selection("Ball", "Size", BALL_SIZE_SLIDER_MIN, BALL_SIZE_SLIDER_MAX, 0.1, false, true, false)
	else:
		# Boosts have no solid body to turn off, only the area that triggers them.
		ui.show_selection("Boost", "Size", BOOST_SIZE_SLIDER_MIN, BOOST_SIZE_SLIDER_MAX, 0.1, true, false, true)
	_refresh_selection_ui()


## Moves the selected object with the mouse, keeping its offset from where it was grabbed.
func _move_selected() -> void:
	var data := _data_of(_selected)
	# Snapping the distance moved keeps objects that sit between grid points aligned with each other.
	var new_position := _move_from_position + _snap(get_global_mouse_position() - _move_from_mouse)
	if new_position != data["position"]:
		data["position"] = new_position
		_apply_to_node(_selected)


func _rotate_selected(angle: float) -> void:
	var data := _data_of(_selected)
	if data.has("rotation"):
		_set_selected_rotation(data["rotation"] + angle)


func _set_selected_rotation(angle: float) -> void:
	var data := _data_of(_selected)
	if not data.has("rotation"):
		return # Balls look the same at any rotation.
	data["rotation"] = wrapf(angle, -PI, PI)
	_apply_to_node(_selected)


func _resize_selected(factor: float) -> void:
	_set_selected_size(_size_of(_selected) * factor)


## Sets the length of a floor or the scale of a ball or boost, clamped to what levels allow.
func _set_selected_size(size: float) -> void:
	var data := _data_of(_selected)
	if _tile_nodes.has(_selected):
		data["length"] = clampf(size, LevelData.MIN_TILE_LENGTH, LevelData.MAX_TILE_LENGTH)
	elif _ball_nodes.has(_selected):
		data["scale"] = clampf(size, LevelData.MIN_BALL_SCALE, LevelData.MAX_BALL_SCALE)
	else:
		data["scale"] = clampf(size, LevelData.MIN_BOOST_SCALE, LevelData.MAX_BOOST_SCALE)
	_apply_to_node(_selected)


func _set_selected_collision(enabled: bool) -> void:
	var data := _data_of(_selected)
	if data.has("collision"):
		data["collision"] = enabled
		_apply_to_node(_selected)


func _set_selected_strength(strength: float) -> void:
	var data := _data_of(_selected)
	if data.has("strength"):
		data["strength"] = clampf(strength, LevelData.MIN_BOOST_STRENGTH, LevelData.MAX_BOOST_STRENGTH)
		_apply_to_node(_selected)


func _size_of(node: Node2D) -> float:
	var data := _data_of(node)
	return data["length"] if _tile_nodes.has(node) else data["scale"]


## Updates a node after its data changed, and the selection fields if it's selected.
func _apply_to_node(node: Node2D) -> void:
	var data := _data_of(node)
	if _tile_nodes.has(node):
		LevelSpawner.apply_tile(node, data)
	elif _ball_nodes.has(node):
		LevelSpawner.apply_ball(node, data)
	else:
		LevelSpawner.apply_boost(node, data)
	_show_collision(node, data)
	if node == _selected:
		_refresh_selection_ui()
	_mark_changed()


func _refresh_selection_ui() -> void:
	if _selected != null:
		var data := _data_of(_selected)
		ui.update_selection(rad_to_deg(data.get("rotation", 0.0)), _size_of(_selected), data.get("collision", true),
				data.get("strength", LevelData.DEFAULT_BOOST_STRENGTH))


## Fades objects with collision off, since they look the same as solid ones in the game.
func _show_collision(node: Node2D, data: Dictionary) -> void:
	node.modulate.a = 1.0 if data.get("collision", true) else NO_COLLISION_ALPHA


## Returns the level data of a tile, ball or boost node. Changing it changes the level.
func _data_of(node: Node2D) -> Dictionary:
	var index := _tile_nodes.find(node)
	if index != -1:
		return _level.tiles[index]
	index = _ball_nodes.find(node)
	if index != -1:
		return _level.balls[index]
	return _level.boosts[_boost_nodes.find(node)]


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


func _add_boost(boost: Dictionary) -> void:
	if not _has_room_for_object():
		return
	_level.boosts.append(boost)
	_placed_nodes.append(_spawn_boost_node(boost))
	_mark_changed()


func _spawn_tile_node(tile: Dictionary) -> Node2D:
	var node := LevelSpawner.spawn_tile(tile)
	_show_collision(node, tile)
	objects_root.add_child(node)
	_tile_nodes.append(node)
	return node


func _spawn_ball_node(ball: Dictionary) -> Node2D:
	var node := LevelSpawner.spawn_ball(ball)
	_show_collision(node, ball)
	objects_root.add_child(node)
	_ball_nodes.append(node)
	return node


func _spawn_boost_node(boost: Dictionary) -> Node2D:
	var node := LevelSpawner.spawn_boost(boost)
	objects_root.add_child(node)
	_boost_nodes.append(node)
	return node


func _has_room_for_object() -> bool:
	if _level.object_count() < LevelData.MAX_OBJECTS:
		return true
	ui.show_status("A level can have at most %d objects." % LevelData.MAX_OBJECTS)
	return false


## Removes a tile, ball or boost node and its data from the level.
func _remove_object(node: Node2D) -> void:
	if node == _selected:
		_select(null)
	var index := _tile_nodes.find(node)
	if index != -1:
		_tile_nodes.remove_at(index)
		_level.tiles.remove_at(index)
	elif _ball_nodes.has(node):
		index = _ball_nodes.find(node)
		_ball_nodes.remove_at(index)
		_level.balls.remove_at(index)
	else:
		index = _boost_nodes.find(node)
		_boost_nodes.remove_at(index)
		_level.boosts.remove_at(index)
	_placed_nodes.erase(node)
	node.queue_free()
	_mark_changed()


func _undo() -> void:
	if not _placed_nodes.is_empty():
		_remove_object(_placed_nodes.back())


## Returns the object node at `point`, preferring boosts, then balls, then recently placed objects.
func _object_at(point: Vector2) -> Node2D:
	for i in range(_level.boosts.size() - 1, -1, -1):
		var boost := _level.boosts[i]
		var half: float = LevelSpawner.BOOST_SIZE * boost["scale"] / 2.0 + PICK_MARGIN
		var local: Vector2 = (point - boost["position"]).rotated(-boost["rotation"])
		if absf(local.x) <= half and absf(local.y) <= half:
			return _boost_nodes[i]
	for i in range(_level.balls.size() - 1, -1, -1):
		var ball := _level.balls[i]
		if point.distance_to(ball["position"]) <= LevelSpawner.BALL_RADIUS * ball["scale"] + PICK_MARGIN:
			return _ball_nodes[i]
	for i in range(_level.tiles.size() - 1, -1, -1):
		var tile := _level.tiles[i]
		var local: Vector2 = (point - tile["position"]).rotated(-tile["rotation"])
		if absf(local.x) <= tile["length"] / 2.0 + PICK_MARGIN and absf(local.y) <= LevelSpawner.TILE_SIZE / 2.0 + PICK_MARGIN:
			return _tile_nodes[i]
	return null


func _snap(point: Vector2) -> Vector2:
	return point.snapped(Vector2.ONE * GRID_SIZE) if ui.snap_enabled else point


func _snap_angle(angle: float) -> float:
	if ui.snap_enabled:
		angle = snappedf(angle, deg_to_rad(SNAPPED_ANGLE_STEP))
	return wrapf(angle, -PI, PI)


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
	_is_dragging = false
	_select(null)


func _on_selection_rotation_changed(degrees: float) -> void:
	if _selected != null:
		_set_selected_rotation(deg_to_rad(degrees))


func _on_selection_size_changed(size: float) -> void:
	if _selected != null:
		_set_selected_size(size)


func _on_selection_collision_toggled(enabled: bool) -> void:
	if _selected != null:
		_set_selected_collision(enabled)


func _on_selection_strength_changed(strength: float) -> void:
	if _selected != null:
		_set_selected_strength(strength)


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
