extends CanvasLayer
## Settings screen: rebinds the controls of the car and turns the on-screen controls on or off.

## Shown on a slot button while it waits for a key.
const LISTENING_TEXT := "Press a key..."
const EMPTY_SLOT_TEXT := "(none)"
const SLOT_BUTTON_WIDTH := 200.0

## Gets a row per control: its name, then a button per key slot.
@export var controls_grid: GridContainer
@export var reset_button: Button
@export var show_controls_check: CheckBox
@export var status_label: Label
@export var back_button: Button

# The slot buttons of each control, as {action: Array of Button}.
var _slot_buttons := {}
# The action and slot waiting for a key, or "" when none is.
var _listening_action := ""
var _listening_slot := 0


func _ready() -> void:
	controls_grid.columns = 1 + Settings.SLOTS
	for control: Dictionary in Settings.CONTROLS:
		var action: String = control["action"]
		var label := Label.new()
		label.text = control["name"]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		controls_grid.add_child(label)
		var buttons: Array[Button] = []
		for slot in Settings.SLOTS:
			var button := Button.new()
			button.custom_minimum_size.x = SLOT_BUTTON_WIDTH
			button.tooltip_text = "Click, then press a key. Right-click to remove the key."
			button.pressed.connect(_on_slot_pressed.bind(action, slot))
			button.gui_input.connect(_on_slot_gui_input.bind(action, slot))
			controls_grid.add_child(button)
			buttons.append(button)
		_slot_buttons[action] = buttons
	_refresh()

	show_controls_check.button_pressed = Settings.show_controls
	show_controls_check.toggled.connect(func(pressed: bool) -> void: Settings.show_controls = pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	back_button.pressed.connect(_on_back_pressed)
	status_label.text = ""


# Runs before the GUI, so the key that is being bound doesn't also press a focused button.
func _input(event: InputEvent) -> void:
	if _listening_action.is_empty():
		return
	var key := event as InputEventKey
	if key and key.pressed and not key.echo:
		get_viewport().set_input_as_handled()
		var physical := key.physical_keycode if key.physical_keycode != KEY_NONE else key.keycode
		_bind(_listening_action, _listening_slot, physical)
	elif event is InputEventMouseButton and event.pressed:
		# Clicking stops waiting without changing the key. The click goes on, so clicking
		# another slot starts waiting there.
		_stop_listening()
		status_label.text = ""


func _on_slot_pressed(action: String, slot: int) -> void:
	_stop_listening()
	_listening_action = action
	_listening_slot = slot
	_slot_buttons[action][slot].text = LISTENING_TEXT
	status_label.text = "Press the new key for %s." % _control_name(action)


func _on_slot_gui_input(event: InputEvent, action: String, slot: int) -> void:
	var mouse_button := event as InputEventMouseButton
	if mouse_button and mouse_button.pressed and mouse_button.button_index == MOUSE_BUTTON_RIGHT:
		if Settings.get_keys(action)[slot] == KEY_NONE:
			return
		Settings.set_key(action, slot, KEY_NONE)
		_refresh()
		if Settings.get_keys(action).all(func(key: Key) -> bool: return key == KEY_NONE):
			status_label.text = "%s has no key now." % _control_name(action)
		else:
			status_label.text = "Removed a key from %s." % _control_name(action)


func _bind(action: String, slot: int, key: Key) -> void:
	_stop_listening()
	var other := Settings.set_key(action, slot, key)
	_refresh()
	var text := "%s is now %s." % [_control_name(action), Settings.describe(action)]
	if not other.is_empty():
		# Keys belong to one control, so the one that had it got this slot's old key or nothing.
		text += " %s is now %s." % [_control_name(other), Settings.describe(other)]
	status_label.text = text


func _stop_listening() -> void:
	_listening_action = ""
	_refresh()


func _refresh() -> void:
	for action: String in _slot_buttons:
		var keys := Settings.get_keys(action)
		for slot in Settings.SLOTS:
			var key := keys[slot]
			_slot_buttons[action][slot].text = Settings.key_name(key) if key != KEY_NONE else EMPTY_SLOT_TEXT


func _control_name(action: String) -> String:
	for control: Dictionary in Settings.CONTROLS:
		if control["action"] == action:
			return control["name"]
	return action


func _on_reset_pressed() -> void:
	_stop_listening()
	Settings.reset_controls()
	_refresh()
	status_label.text = "The controls are back to the defaults."


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)
