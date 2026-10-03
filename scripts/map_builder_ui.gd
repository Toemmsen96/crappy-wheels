class_name MapBuilderUI
extends CanvasLayer
## Toolbar for the level builder. Reports what the user picks; LevelBuilder does the editing.

signal tool_selected(tool: Tool)
signal level_name_changed(new_name: String)
signal save_pressed
signal test_pressed
signal back_pressed
signal selection_rotation_changed(degrees: float)
signal selection_size_changed(size: float)
signal selection_collision_toggled(enabled: bool)
signal selection_strength_changed(strength: float)

enum Tool { SELECT, FLOOR, BALL, BOOST, START, FINISH, ERASE }

const TOOL_HINTS := {
	Tool.SELECT: "Select: click an object to select it and drag to move it. Q/E rotate, R/F resize, C toggles collision, Delete removes it.",
	Tool.FLOOR: "Floor: click and drag to draw a floor.",
	Tool.BALL: "Ball: click to place a ball of the chosen size.",
	Tool.BOOST: "Boost: click to place a boost pushing right, or drag towards the direction it should push.",
	Tool.START: "Start: click to move where the car spawns.",
	Tool.FINISH: "Finish: click to move the finish flag.",
	Tool.ERASE: "Erase: click a floor, ball or boost to remove it.",
}
const CONTROLS_HINT := "Right-drag or WASD/arrows to pan, mouse wheel to zoom, Ctrl+Z to undo. Esc pauses a test run."

@export var select_button: Button
@export var floor_button: Button
@export var ball_button: Button
@export var boost_button: Button
@export var start_button: Button
@export var finish_button: Button
@export var erase_button: Button
@export var ball_size_input: SpinBox
@export var snap_check: CheckBox
@export var name_edit: LineEdit
@export var save_button: Button
@export var test_button: Button
@export var back_button: Button
@export var status_label: Label
@export var hint_label: Label
@export_group("Selection")
## Shown while an object is selected, to edit its rotation, size, collision and strength.
@export var selection_row: Control
@export var selection_label: Label
@export var rotation_label: Label
@export var rotation_input: SpinBox
@export var size_label: Label
@export var size_input: SpinBox
## The sliders share their value and range with the inputs next to them, so
## dragging one reports a change through the input's signal. The inputs accept
## values past the ends of the sliders, for the rare object that needs them.
@export var rotation_slider: HSlider
@export var size_slider: HSlider
@export var collision_check: CheckBox
@export var strength_label: Label
@export var strength_input: SpinBox
@export var strength_slider: HSlider

var ball_size: float:
	get:
		return ball_size_input.value

var snap_enabled: bool:
	get:
		return snap_check.button_pressed

var level_name: String:
	get:
		return name_edit.text.strip_edges()
	set(value):
		name_edit.text = value


func _ready() -> void:
	var tool_buttons := {
		select_button: Tool.SELECT,
		floor_button: Tool.FLOOR,
		ball_button: Tool.BALL,
		boost_button: Tool.BOOST,
		start_button: Tool.START,
		finish_button: Tool.FINISH,
		erase_button: Tool.ERASE,
	}
	for button: Button in tool_buttons:
		button.pressed.connect(_on_tool_button_pressed.bind(tool_buttons[button]))
	name_edit.max_length = LevelData.MAX_NAME_LENGTH
	name_edit.text_changed.connect(func(new_text: String) -> void:
		level_name_changed.emit(new_text.strip_edges()))
	save_button.pressed.connect(save_pressed.emit)
	test_button.pressed.connect(test_pressed.emit)
	back_button.pressed.connect(back_pressed.emit)
	# The sliders take over the inputs' ranges (-180 to 180 for rotation), not the other way around.
	rotation_input.share(rotation_slider)
	size_input.share(size_slider)
	strength_input.share(strength_slider)
	rotation_input.value_changed.connect(selection_rotation_changed.emit)
	size_input.value_changed.connect(selection_size_changed.emit)
	collision_check.toggled.connect(selection_collision_toggled.emit)
	strength_input.value_changed.connect(selection_strength_changed.emit)
	hide_selection()
	_show_hint(Tool.FLOOR)


func show_status(text: String) -> void:
	status_label.text = text


## Shows the selection row for a newly selected object, hiding fields for properties it doesn't have.
## The size slider spans `slider_min` to `slider_max`; the input also accepts values beyond that.
## Call update_selection() to fill in the values.
func show_selection(title: String, size_name: String, slider_min: float, slider_max: float, size_step: float,
		can_rotate: bool, can_toggle_collision: bool, has_strength: bool) -> void:
	selection_label.text = title
	rotation_label.visible = can_rotate
	rotation_input.visible = can_rotate
	rotation_slider.visible = can_rotate
	collision_check.visible = can_toggle_collision
	strength_label.visible = has_strength
	strength_input.visible = has_strength
	strength_slider.visible = has_strength
	size_label.text = size_name
	# Changing the range clamps the old value, which would otherwise be reported as a resize.
	size_input.set_block_signals(true)
	size_input.min_value = slider_min
	size_input.max_value = slider_max
	size_input.step = size_step
	size_input.allow_lesser = true
	size_input.allow_greater = true
	# Floors are anywhere from tiny to thousands long, so the slider moves exponentially.
	size_input.exp_edit = true
	size_input.set_block_signals(false)
	selection_row.show()


## Shows the selected object's current values without emitting the change signals.
func update_selection(rotation_degrees: float, size: float, collision: bool, strength: float) -> void:
	rotation_input.set_value_no_signal(rotation_degrees)
	size_input.set_value_no_signal(size)
	collision_check.set_pressed_no_signal(collision)
	strength_input.set_value_no_signal(strength)


func hide_selection() -> void:
	selection_row.hide()


func _on_tool_button_pressed(tool: Tool) -> void:
	_show_hint(tool)
	tool_selected.emit(tool)


func _show_hint(tool: Tool) -> void:
	hint_label.text = "%s\n%s" % [TOOL_HINTS[tool], CONTROLS_HINT]
