class_name MapBuilderUI
extends CanvasLayer
## Toolbar for the level builder. Reports what the user picks; LevelBuilder does the editing.

signal tool_selected(tool: Tool)
signal level_name_changed(new_name: String)
signal save_pressed
signal test_pressed
signal back_pressed

enum Tool { FLOOR, BALL, START, FINISH, ERASE }

const TOOL_HINTS := {
	Tool.FLOOR: "Floor: click and drag to draw a floor.",
	Tool.BALL: "Ball: click to place a ball of the chosen size.",
	Tool.START: "Start: click to move where the car spawns.",
	Tool.FINISH: "Finish: click to move the finish flag.",
	Tool.ERASE: "Erase: click a floor or ball to remove it.",
}
const CONTROLS_HINT := "Right-drag or WASD/arrows to pan, mouse wheel to zoom, Ctrl+Z to undo. Esc pauses a test run."

@export var floor_button: Button
@export var ball_button: Button
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
		floor_button: Tool.FLOOR,
		ball_button: Tool.BALL,
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
	_show_hint(Tool.FLOOR)


func show_status(text: String) -> void:
	status_label.text = text


func _on_tool_button_pressed(tool: Tool) -> void:
	_show_hint(tool)
	tool_selected.emit(tool)


func _show_hint(tool: Tool) -> void:
	hint_label.text = "%s\n%s" % [TOOL_HINTS[tool], CONTROLS_HINT]
