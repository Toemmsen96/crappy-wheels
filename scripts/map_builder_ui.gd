class_name MapBuilderUI
extends CanvasLayer
## Toolbar for the level builder. Reports what the user picks; LevelBuilder does the editing.

signal tool_selected(tool: Tool)
signal level_name_changed(new_name: String)
signal save_pressed
signal test_pressed
signal back_pressed
signal discard_confirmed
signal save_and_leave_pressed
signal rotation_changed(degrees: float)
signal size_changed(size: float)
signal collision_toggled(enabled: bool)
signal strength_changed(strength: float)

enum Tool { SELECT, FLOOR, BALL, BOOST, START, FINISH, ERASE }

const TOOL_HINTS := {
	Tool.SELECT: "Select: click an object, or drag a box around several, then drag to move them. Shift adds to the selection, Ctrl+A selects everything, Delete removes the selection.",
	Tool.FLOOR: "Floor: click and drag to draw a floor.",
	Tool.BALL: "Ball: click to place a ball with the settings above.",
	Tool.BOOST: "Boost: click to place a boost with the settings above, or drag towards the direction it should push.",
	Tool.START: "Start: click to move where the car spawns.",
	Tool.FINISH: "Finish: click to move the finish flag.",
	Tool.ERASE: "Erase: click a floor, ball or boost to remove it.",
}
const CONTROLS_HINT := "Q/E rotate, R/F resize, C toggles collision. Right-drag or WASD/arrows to pan, mouse wheel to zoom, Ctrl+Z to undo. Esc pauses a test run."
const SAVE_AND_LEAVE_ACTION := "save_and_leave"

@export var select_button: Button
@export var floor_button: Button
@export var ball_button: Button
@export var boost_button: Button
@export var start_button: Button
@export var finish_button: Button
@export var erase_button: Button
@export var snap_check: CheckBox
@export var name_edit: LineEdit
@export var save_button: Button
@export var test_button: Button
@export var back_button: Button
@export var status_label: Label
@export var hint_label: Label
## Asks before leaving the builder with unsaved changes.
@export var unsaved_dialog: ConfirmationDialog
@export_group("Settings")
## Edits the selected objects, or the next object the current tool places.
## Wraps onto more lines when its fields don't fit next to each other.
@export var settings_row: Control
@export var settings_label: Label
## The fields group their label, input and slider, so they're hidden and wrapped together.
@export var rotation_field: Control
@export var rotation_input: SpinBox
@export var size_field: Control
@export var size_label: Label
@export var size_input: SpinBox
## The sliders share their value and range with the inputs next to them, so
## dragging one reports a change through the input's signal. The inputs accept
## values past the ends of the sliders, for the rare object that needs them.
@export var rotation_slider: HSlider
@export var size_slider: HSlider
@export var collision_check: CheckBox
@export var strength_field: Control
@export var strength_input: SpinBox
@export var strength_slider: HSlider

var snap_enabled: bool:
	get:
		return snap_check.button_pressed

var level_name: String:
	get:
		return name_edit.text.strip_edges()
	set(value):
		name_edit.text = value

## True while a dialog is open, so the level shouldn't react to input.
var is_dialog_open: bool:
	get:
		return unsaved_dialog.visible


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
	unsaved_dialog.add_button("Save and leave", true, SAVE_AND_LEAVE_ACTION)
	unsaved_dialog.confirmed.connect(discard_confirmed.emit)
	unsaved_dialog.custom_action.connect(_on_unsaved_dialog_action)
	# The sliders take over the inputs' ranges (-180 to 180 for rotation), not the other way around.
	rotation_input.share(rotation_slider)
	size_input.share(size_slider)
	strength_input.share(strength_slider)
	rotation_input.value_changed.connect(rotation_changed.emit)
	size_input.value_changed.connect(size_changed.emit)
	collision_check.toggled.connect(collision_toggled.emit)
	strength_input.value_changed.connect(strength_changed.emit)
	hide_settings()
	_show_hint(Tool.FLOOR)


func show_status(text: String) -> void:
	status_label.text = text


## Asks whether to leave without saving. Reports the answer with discard_confirmed or save_and_leave_pressed.
func ask_to_discard() -> void:
	unsaved_dialog.popup_centered()


## Shows the settings row with only the fields that apply. An empty `size_name` hides the size field.
## The size slider spans `slider_min` to `slider_max`; the input also accepts values beyond that.
## Call update_settings() to fill in the values.
func show_settings(title: String, can_rotate: bool, size_name: String, slider_min: float, slider_max: float,
		size_step: float, can_toggle_collision: bool, has_strength: bool) -> void:
	settings_label.text = title
	rotation_field.visible = can_rotate
	var has_size := not size_name.is_empty()
	size_field.visible = has_size
	collision_check.visible = can_toggle_collision
	strength_field.visible = has_strength
	if has_size:
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
	settings_row.show()


## Shows the current values without emitting the change signals.
func update_settings(rotation_degrees: float, size: float, collision: bool, strength: float) -> void:
	rotation_input.set_value_no_signal(rotation_degrees)
	size_input.set_value_no_signal(size)
	collision_check.set_pressed_no_signal(collision)
	strength_input.set_value_no_signal(strength)


func hide_settings() -> void:
	settings_row.hide()


func _on_tool_button_pressed(tool: Tool) -> void:
	_show_hint(tool)
	tool_selected.emit(tool)


func _on_unsaved_dialog_action(action: StringName) -> void:
	if action == SAVE_AND_LEAVE_ACTION:
		unsaved_dialog.hide()
		save_and_leave_pressed.emit()


func _show_hint(tool: Tool) -> void:
	hint_label.text = "%s\n%s" % [TOOL_HINTS[tool], CONTROLS_HINT]
