extends Node

# Signals for continuous press (held down, emitted every frame)
signal move_right_pressed
signal move_left_pressed
signal move_down_pressed
signal move_up_pressed
signal interact_pressed
signal cancel_pressed
signal boost_pressed
signal inventory_pressed

# Signals for "just pressed" (single frame)
signal move_right_just_pressed
signal move_left_just_pressed
signal move_down_just_pressed
signal move_up_just_pressed
signal interact_just_pressed
signal cancel_just_pressed
signal boost_just_pressed
signal inventory_just_pressed
signal dash_just_pressed

# Signals for "just released"
signal move_right_released
signal move_left_released
signal move_down_released
signal move_up_released
signal interact_released
signal cancel_released
signal boost_released
signal inventory_released


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS # Uncomment if needed, can cause bouncing issues


func _process(_delta: float) -> void:
	_check_inputs()


func _check_inputs() -> void:
	# Keys typed into a text field, such as the name on the finish screen,
	# must not also drive the car, reset the level or pause. Releases still
	# go out, so a key held while clicking into the field doesn't stick.
	if not _is_typing():
		# Check continuous press (held down)
		if Input.is_action_pressed(Inputs.MOVE_RIGHT):
			move_right_pressed.emit()
		if Input.is_action_pressed(Inputs.MOVE_LEFT):
			move_left_pressed.emit()
		if Input.is_action_pressed(Inputs.MOVE_DOWN):
			move_down_pressed.emit()
		if Input.is_action_pressed(Inputs.MOVE_UP):
			move_up_pressed.emit()
		if Input.is_action_pressed(Inputs.INTERACT):
			interact_pressed.emit()
		if Input.is_action_pressed(Inputs.CANCEL):
			cancel_pressed.emit()
		if Input.is_action_pressed(Inputs.BOOST):
			boost_pressed.emit()
		if Input.is_action_pressed(Inputs.INVENTORY):
			inventory_pressed.emit()

		# Check just pressed (single frame when pressed)
		if Input.is_action_just_pressed(Inputs.MOVE_RIGHT):
			move_right_just_pressed.emit()
		if Input.is_action_just_pressed(Inputs.MOVE_LEFT):
			move_left_just_pressed.emit()
		if Input.is_action_just_pressed(Inputs.MOVE_DOWN):
			move_down_just_pressed.emit()
		if Input.is_action_just_pressed(Inputs.MOVE_UP):
			move_up_just_pressed.emit()
		if Input.is_action_just_pressed(Inputs.INTERACT):
			interact_just_pressed.emit()
		if Input.is_action_just_pressed(Inputs.CANCEL):
			cancel_just_pressed.emit()
		if Input.is_action_just_pressed(Inputs.BOOST):
			boost_just_pressed.emit()
		if Input.is_action_just_pressed(Inputs.INVENTORY):
			inventory_just_pressed.emit()
		if Input.is_action_just_pressed(Inputs.DASH):
			dash_just_pressed.emit()

	# Check just released
	if Input.is_action_just_released(Inputs.MOVE_RIGHT):
		move_right_released.emit()
	if Input.is_action_just_released(Inputs.MOVE_LEFT):
		move_left_released.emit()
	if Input.is_action_just_released(Inputs.MOVE_DOWN):
		move_down_released.emit()
	if Input.is_action_just_released(Inputs.MOVE_UP):
		move_up_released.emit()
	if Input.is_action_just_released(Inputs.INTERACT):
		interact_released.emit()
	if Input.is_action_just_released(Inputs.CANCEL):
		cancel_released.emit()
	if Input.is_action_just_released(Inputs.BOOST):
		boost_released.emit()
	if Input.is_action_just_released(Inputs.INVENTORY):
		inventory_released.emit()


## Whether a text field has the keyboard.
func _is_typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit
