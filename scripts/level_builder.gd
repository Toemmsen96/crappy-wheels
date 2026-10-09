class_name LevelBuilder
extends Node2D
## Editor for building levels in-game. Levels are saved with LevelLibrary.

enum Kind { TILE, BALL, BOOST }

const GRID_SIZE := 10.0
## Grid lines are drawn every this many grid cells.
const GRID_LINE_EVERY := 5
const ZOOM_STEP := 1.1
const MIN_ZOOM := 0.25
const MAX_ZOOM := 4.0
const PAN_SPEED := 600.0
## Extra distance around objects that still counts as clicking them.
const PICK_MARGIN := 4.0
## Shorter boost drags than this place the boost with the rotation from the settings.
const MIN_BOOST_DRAG := 10.0
## Selection boxes smaller than this many pixels on screen count as a click on empty space.
const MIN_BOX_SELECT_SIZE := 4.0
## Rotations snap to, and Q/E rotate by, this many degrees when snapping is on.
const SNAPPED_ANGLE_STEP := 15.0
## Q/E rotate by this many degrees when snapping is off.
const FREE_ANGLE_STEP := 1.0
## R/F multiply or divide the size by this.
const RESIZE_FACTOR := 1.1
# Size slider ranges for common sizes. Typing in the size box goes further, up to the LevelData limits.
const FLOOR_LENGTH_SLIDER_MIN := 10.0
const FLOOR_LENGTH_SLIDER_MAX := 1000.0
const BALL_SIZE_SLIDER_MIN := 0.2
const BALL_SIZE_SLIDER_MAX := 3.0
const BOOST_SIZE_SLIDER_MIN := 0.5
const BOOST_SIZE_SLIDER_MAX := 3.0
## How each kind of object is shown in the settings row.
const KIND_SETTINGS := {
	Kind.TILE: {"name": "Floor", "plural": "floors", "size": "Length",
			"min": FLOOR_LENGTH_SLIDER_MIN, "max": FLOOR_LENGTH_SLIDER_MAX, "step": 1.0},
	Kind.BALL: {"name": "Ball", "plural": "balls", "size": "Size",
			"min": BALL_SIZE_SLIDER_MIN, "max": BALL_SIZE_SLIDER_MAX, "step": 0.1},
	Kind.BOOST: {"name": "Boost", "plural": "boosts", "size": "Size",
			"min": BOOST_SIZE_SLIDER_MIN, "max": BOOST_SIZE_SLIDER_MAX, "step": 0.1},
}
## The kind of object each placing tool adds.
const TOOL_KINDS := {
	MapBuilderUI.Tool.FLOOR: Kind.TILE,
	MapBuilderUI.Tool.BALL: Kind.BALL,
	MapBuilderUI.Tool.BOOST: Kind.BOOST,
}
const GRID_COLOR := Color(1, 1, 1, 0.1)
const PREVIEW_COLOR := Color(1, 1, 1, 0.5)
const SELECT_COLOR := Color(1, 0.85, 0.2, 0.9)
const SELECT_BOX_COLOR := Color(1, 0.85, 0.2, 0.15)
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
# What the placing tools add next, edited in the settings row while that tool is picked.
# Floors get their rotation and length from the drag, so only collision is set here.
var _new_objects := {
	Kind.TILE: {"collision": true},
	Kind.BALL: {"scale": 1.0, "collision": true},
	Kind.BOOST: {"rotation": 0.0, "scale": 1.0, "strength": LevelData.DEFAULT_BOOST_STRENGTH},
}
# Floors and boosts are placed by dragging: floors from end to end, boosts from
# where they go towards the direction they push.
var _is_dragging := false
var _drag_start := Vector2.ZERO
# The objects picked with the select tool, and whether they're being dragged around.
var _selected: Array[Node2D] = []
var _is_moving := false
var _move_from_positions: Array[Vector2] = []
var _move_from_mouse := Vector2.ZERO
# Dragging over empty space with the select tool draws a box that selects everything it touches.
var _is_box_selecting := false
var _box_start := Vector2.ZERO
# What was selected when a box was started with Shift held, which stays selected.
var _box_kept: Array[Node2D] = []


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
	ui.discard_confirmed.connect(_leave)
	ui.save_and_leave_pressed.connect(_save_and_leave)
	ui.rotation_changed.connect(func(degrees: float) -> void:
		_edit_settings_targets(_set_rotation.bind(deg_to_rad(degrees))))
	ui.size_changed.connect(func(size: float) -> void:
		_edit_settings_targets(_set_size.bind(size)))
	ui.collision_toggled.connect(func(enabled: bool) -> void:
		_edit_settings_targets(_set_collision.bind(enabled)))
	ui.strength_changed.connect(func(strength: float) -> void:
		_edit_settings_targets(_set_strength.bind(strength)))
	overlay.draw.connect(_draw_overlay)
	_show_settings()


func _process(delta: float) -> void:
	# Checked here rather than on release, since the button may be released over the UI.
	var left_held := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	if _is_dragging and not left_held:
		_finish_drag()
	if _is_box_selecting and not left_held:
		_finish_box_select()
	if _is_moving:
		if left_held:
			_move_selected()
		else:
			_is_moving = false

	if not ui.is_dialog_open and not (get_viewport().gui_get_focus_owner() is LineEdit):
		var direction := Input.get_vector(Inputs.MOVE_LEFT, Inputs.MOVE_RIGHT, Inputs.MOVE_UP, Inputs.MOVE_DOWN)
		camera.position += direction * PAN_SPEED * delta / camera.zoom.x

	queue_redraw()
	overlay.queue_redraw()


# Only gets input the UI didn't use, so clicks on the toolbar don't edit the level.
func _unhandled_input(event: InputEvent) -> void:
	if ui.is_dialog_open:
		return
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
				_use_tool(get_global_mouse_position(), mouse_button.shift_pressed)
	elif mouse_motion and mouse_motion.button_mask & (MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE):
		camera.position -= mouse_motion.relative / camera.zoom
	elif key and key.pressed:
		_handle_key(key)


func _handle_key(key: InputEventKey) -> void:
	if key.is_command_or_control_pressed():
		match key.keycode:
			KEY_Z:
				_undo()
			KEY_A:
				if _tool != MapBuilderUI.Tool.SELECT:
					return
				_select(_all_objects())
			_:
				return
	else:
		var angle_step := deg_to_rad(SNAPPED_ANGLE_STEP if ui.snap_enabled else FREE_ANGLE_STEP)
		match key.keycode:
			KEY_Q:
				_edit_settings_targets(_rotate_by.bind(-angle_step))
			KEY_E:
				_edit_settings_targets(_rotate_by.bind(angle_step))
			KEY_R:
				_edit_settings_targets(_resize_by.bind(RESIZE_FACTOR))
			KEY_F:
				_edit_settings_targets(_resize_by.bind(1.0 / RESIZE_FACTOR))
			KEY_C:
				_toggle_collision()
			KEY_DELETE, KEY_BACKSPACE:
				if _selected.is_empty():
					return
				var nodes := _selected
				_select([])
				for node in nodes:
					_remove_object(node)
			KEY_ESCAPE:
				if _selected.is_empty():
					return
				_select([])
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
		MapBuilderUI.Tool.SELECT:
			if _is_box_selecting:
				var box := _selection_box()
				overlay.draw_rect(box, SELECT_BOX_COLOR)
				overlay.draw_rect(box, SELECT_COLOR, false, line_width)
				for node in _objects_in_box():
					_draw_object_outline(node, PREVIEW_COLOR, line_width)
		MapBuilderUI.Tool.FLOOR:
			if _is_dragging:
				overlay.draw_line(_drag_start, _snap(mouse), PREVIEW_COLOR, LevelSpawner.TILE_SIZE)
		MapBuilderUI.Tool.BALL:
			var radius: float = LevelSpawner.BALL_RADIUS * _new_objects[Kind.BALL]["scale"]
			overlay.draw_arc(_snap(mouse), radius, 0.0, TAU, 32, PREVIEW_COLOR, line_width)
		MapBuilderUI.Tool.BOOST:
			var boost_scale: float = _new_objects[Kind.BOOST]["scale"]
			if _is_dragging:
				_draw_boost_outline(_drag_start, _boost_rotation(_drag_start, _snap(mouse)), boost_scale, PREVIEW_COLOR, line_width)
			else:
				_draw_boost_outline(_snap(mouse), _new_objects[Kind.BOOST]["rotation"], boost_scale, PREVIEW_COLOR, line_width)
		MapBuilderUI.Tool.ERASE:
			var node := _object_at(mouse)
			if node != null:
				_draw_object_outline(node, ERASE_COLOR, line_width)
	for node in _selected:
		_draw_object_outline(node, SELECT_COLOR, line_width)


func _draw_object_outline(node: Node2D, color: Color, line_width: float) -> void:
	var data := _data_of(node)
	match _kind_of(node):
		Kind.TILE:
			var length: float = data["length"]
			overlay.draw_set_transform(data["position"], data["rotation"])
			overlay.draw_rect(Rect2(-length / 2.0, -LevelSpawner.TILE_SIZE / 2.0, length, LevelSpawner.TILE_SIZE), color, false, line_width)
			overlay.draw_set_transform(Vector2.ZERO)
		Kind.BALL:
			overlay.draw_arc(data["position"], LevelSpawner.BALL_RADIUS * data["scale"], 0.0, TAU, 32, color, line_width)
		Kind.BOOST:
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


## Uses the current tool at `point`. With `shift` held, the select tool adds to the selection.
func _use_tool(point: Vector2, shift: bool) -> void:
	var grid_point := _snap(point)
	match _tool:
		MapBuilderUI.Tool.SELECT:
			_start_selecting(point, shift)
		MapBuilderUI.Tool.FLOOR, MapBuilderUI.Tool.BOOST:
			_is_dragging = true
			_drag_start = grid_point
		MapBuilderUI.Tool.BALL:
			var ball: Dictionary = _new_objects[Kind.BALL]
			_add_ball(LevelData.make_ball(grid_point, ball["scale"], ball["collision"]))
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
				var tile := LevelData.make_tile(_drag_start, end)
				tile["collision"] = _new_objects[Kind.TILE]["collision"]
				_add_tile(tile)
		MapBuilderUI.Tool.BOOST:
			var boost: Dictionary = _new_objects[Kind.BOOST]
			_add_boost(LevelData.make_boost(_drag_start, _boost_rotation(_drag_start, end), boost["scale"], boost["strength"]))


## Rotation for a boost at `from` that pushes towards `to`. Short drags keep the rotation from the settings.
func _boost_rotation(from: Vector2, to: Vector2) -> float:
	if from.distance_to(to) < MIN_BOOST_DRAG:
		return _new_objects[Kind.BOOST]["rotation"]
	return _snap_angle((to - from).angle())


## Clicking an object selects it and starts moving the selection, and clicking empty space starts a
## selection box. With `add`, clicks add or remove single objects and boxes add to the selection.
func _start_selecting(point: Vector2, add: bool) -> void:
	var node := _object_at(point)
	if node == null:
		_is_box_selecting = true
		_box_start = point
		_box_kept.clear()
		if add:
			_box_kept.append_array(_selected)
		else:
			_select([])
		return
	if add:
		var nodes := _selected.duplicate()
		if nodes.has(node):
			nodes.erase(node)
		else:
			nodes.append(node)
		_select(nodes)
		return
	if not _selected.has(node):
		_select([node])
	_is_moving = true
	_move_from_mouse = point
	_move_from_positions.clear()
	for selected in _selected:
		_move_from_positions.append(_data_of(selected)["position"])


func _finish_box_select() -> void:
	_is_box_selecting = false
	var nodes := _box_kept.duplicate()
	for node in _objects_in_box():
		if not nodes.has(node):
			nodes.append(node)
	_select(nodes)


func _selection_box() -> Rect2:
	return Rect2(_box_start, get_global_mouse_position() - _box_start).abs()


## Returns the objects touching the selection box being dragged out.
func _objects_in_box() -> Array[Node2D]:
	var nodes: Array[Node2D] = []
	var box := _selection_box()
	if box.size.length() * camera.zoom.x < MIN_BOX_SELECT_SIZE:
		return nodes # Too small to be a box, so it's a click on empty space.
	var box_polygon := _rect_polygon(box.get_center(), 0.0, box.size)
	for i in _level.tiles.size():
		var tile := _level.tiles[i]
		var tile_size := Vector2(tile["length"], LevelSpawner.TILE_SIZE)
		if not Geometry2D.intersect_polygons(box_polygon, _rect_polygon(tile["position"], tile["rotation"], tile_size)).is_empty():
			nodes.append(_tile_nodes[i])
	for i in _level.balls.size():
		var ball := _level.balls[i]
		var center: Vector2 = ball["position"]
		if center.distance_to(center.clamp(box.position, box.end)) <= LevelSpawner.BALL_RADIUS * ball["scale"]:
			nodes.append(_ball_nodes[i])
	for i in _level.boosts.size():
		var boost := _level.boosts[i]
		var boost_size: Vector2 = Vector2.ONE * LevelSpawner.BOOST_SIZE * boost["scale"]
		if not Geometry2D.intersect_polygons(box_polygon, _rect_polygon(boost["position"], boost["rotation"], boost_size)).is_empty():
			nodes.append(_boost_nodes[i])
	return nodes


## The corners of a rectangle of `size` centered on `center` and rotated by `angle`.
func _rect_polygon(center: Vector2, angle: float, size: Vector2) -> PackedVector2Array:
	var half := size / 2.0
	var polygon := PackedVector2Array()
	for corner in [Vector2(-half.x, -half.y), Vector2(half.x, -half.y), Vector2(half.x, half.y), Vector2(-half.x, half.y)]:
		polygon.append(center + (corner as Vector2).rotated(angle))
	return polygon


func _all_objects() -> Array[Node2D]:
	var nodes: Array[Node2D] = []
	nodes.append_array(_tile_nodes)
	nodes.append_array(_ball_nodes)
	nodes.append_array(_boost_nodes)
	return nodes


func _select(nodes: Array[Node2D]) -> void:
	_selected = nodes
	_is_moving = false
	_show_settings()


## Moves the selected objects with the mouse, keeping their offset from where they were grabbed.
func _move_selected() -> void:
	# Snapping the distance moved keeps objects that sit between grid points aligned with each other.
	var offset := _snap(get_global_mouse_position() - _move_from_mouse)
	for i in _selected.size():
		var data := _data_of(_selected[i])
		var new_position := _move_from_positions[i] + offset
		if new_position != data["position"]:
			data["position"] = new_position
			_apply_to_node(_selected[i])


## Shows the settings row for the selection, or with nothing selected, for what the current tool places.
## Fields only show up if every object being edited has them.
func _show_settings() -> void:
	var targets := _settings_targets()
	if targets.is_empty():
		ui.hide_settings()
		return
	var kind: int
	var title: String
	if _selected.is_empty():
		kind = TOOL_KINDS[_tool]
		title = "New %s" % KIND_SETTINGS[kind]["name"].to_lower()
	else:
		kind = _kind_of(_selected[0])
		for node in _selected:
			if _kind_of(node) != kind:
				kind = -1
				break
		if kind == -1:
			title = "%d objects" % _selected.size()
		elif _selected.size() == 1:
			title = KIND_SETTINGS[kind]["name"]
		else:
			title = "%d %s" % [_selected.size(), KIND_SETTINGS[kind]["plural"]]
	var can_rotate := targets.all(func(data: Dictionary) -> bool: return data.has("rotation"))
	var can_toggle_collision := targets.all(func(data: Dictionary) -> bool: return data.has("collision"))
	var has_strength := targets.all(func(data: Dictionary) -> bool: return data.has("strength"))
	# Floors and balls measure their size differently, so mixed selections can't share a size.
	if kind != -1 and targets[0].has(_size_key(kind)):
		var settings: Dictionary = KIND_SETTINGS[kind]
		ui.show_settings(title, can_rotate, settings["size"], settings["min"], settings["max"], settings["step"],
				can_toggle_collision, has_strength)
	else:
		ui.show_settings(title, can_rotate, "", 0.0, 0.0, 0.0, can_toggle_collision, has_strength)
	_refresh_settings_values()


## Shows the values of the first object being edited in the settings row.
func _refresh_settings_values() -> void:
	var targets := _settings_targets()
	if targets.is_empty():
		return
	var data := targets[0]
	ui.update_settings(rad_to_deg(data.get("rotation", 0.0)), data.get("length", data.get("scale", 1.0)),
			data.get("collision", true), data.get("strength", LevelData.DEFAULT_BOOST_STRENGTH))


## The data the settings row edits: the selected objects, or with nothing selected, what the current tool places.
func _settings_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	if not _selected.is_empty():
		for node in _selected:
			targets.append(_data_of(node))
	elif TOOL_KINDS.has(_tool):
		targets.append(_new_objects[TOOL_KINDS[_tool]])
	return targets


## Calls `edit` with the data and Kind of everything the settings row edits, and updates the
## objects it changed. `edit` returns whether it changed anything.
func _edit_settings_targets(edit: Callable) -> void:
	if not _selected.is_empty():
		for node in _selected:
			if edit.call(_data_of(node), _kind_of(node)):
				_apply_to_node(node)
	elif TOOL_KINDS.has(_tool):
		var kind: Kind = TOOL_KINDS[_tool]
		edit.call(_new_objects[kind], kind)
	_refresh_settings_values()


func _set_rotation(data: Dictionary, _kind: Kind, angle: float) -> bool:
	if not data.has("rotation"):
		return false # Balls look the same at any rotation.
	data["rotation"] = wrapf(angle, -PI, PI)
	return true


func _rotate_by(data: Dictionary, kind: Kind, angle: float) -> bool:
	return data.has("rotation") and _set_rotation(data, kind, data["rotation"] + angle)


## Sets the length of a floor or the scale of a ball or boost, clamped to what levels allow.
func _set_size(data: Dictionary, kind: Kind, size: float) -> bool:
	var key := _size_key(kind)
	if not data.has(key):
		return false # New floors get their length from the drag.
	match kind:
		Kind.TILE:
			data[key] = clampf(size, LevelData.MIN_TILE_LENGTH, LevelData.MAX_TILE_LENGTH)
		Kind.BALL:
			data[key] = clampf(size, LevelData.MIN_BALL_SCALE, LevelData.MAX_BALL_SCALE)
		Kind.BOOST:
			data[key] = clampf(size, LevelData.MIN_BOOST_SCALE, LevelData.MAX_BOOST_SCALE)
	return true


func _resize_by(data: Dictionary, kind: Kind, factor: float) -> bool:
	var key := _size_key(kind)
	return data.has(key) and _set_size(data, kind, data[key] * factor)


func _set_collision(data: Dictionary, _kind: Kind, enabled: bool) -> bool:
	if not data.has("collision"):
		return false # Boosts have no solid body to turn off, only the area that triggers them.
	data["collision"] = enabled
	return true


func _set_strength(data: Dictionary, _kind: Kind, strength: float) -> bool:
	if not data.has("strength"):
		return false
	data["strength"] = clampf(strength, LevelData.MIN_BOOST_STRENGTH, LevelData.MAX_BOOST_STRENGTH)
	return true


## Flips collision for everything being edited, based on the first object that has it.
func _toggle_collision() -> void:
	for data in _settings_targets():
		if data.has("collision"):
			_edit_settings_targets(_set_collision.bind(not data["collision"]))
			return


func _size_key(kind: Kind) -> String:
	return "length" if kind == Kind.TILE else "scale"


func _kind_of(node: Node2D) -> Kind:
	if _tile_nodes.has(node):
		return Kind.TILE
	if _ball_nodes.has(node):
		return Kind.BALL
	return Kind.BOOST


## Updates a node after its data changed.
func _apply_to_node(node: Node2D) -> void:
	var data := _data_of(node)
	match _kind_of(node):
		Kind.TILE:
			LevelSpawner.apply_tile(node, data)
		Kind.BALL:
			LevelSpawner.apply_ball(node, data)
		Kind.BOOST:
			LevelSpawner.apply_boost(node, data)
	_show_collision(node, data)
	_mark_changed()


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
	if _selected.has(node):
		var nodes := _selected.duplicate()
		nodes.erase(node)
		_select(nodes)
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


func _on_tool_selected(tool: MapBuilderUI.Tool) -> void:
	_tool = tool
	_is_dragging = false
	_is_box_selecting = false
	_select([])


func _on_level_name_changed(new_name: String) -> void:
	_level.name = new_name
	_mark_changed()


## Saves the level and returns whether that worked.
func _save() -> bool:
	if _level.name.is_empty():
		ui.show_status("Give your level a name before saving.")
		return false
	var error := LevelLibrary.save_level(_level)
	if error != OK:
		ui.show_status("Could not save the level: %s" % error_string(error))
		return false
	_level.has_unsaved_changes = false
	ui.show_status("Saved \"%s\"." % _level.name)
	return true


func _test() -> void:
	GameState.testing_in_builder = true
	get_tree().change_scene_to_file(ScenePaths.CUSTOM_LEVEL)


func _back() -> void:
	if _level.has_unsaved_changes:
		ui.ask_to_discard()
	else:
		_leave()


func _save_and_leave() -> void:
	if _save():
		_leave()


func _leave() -> void:
	GameState.current_level = null
	get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)
