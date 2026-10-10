extends Node
## Player settings: which keys drive the car, and whether the controls are shown on screen.
## Kept in GameState.SETTINGS_PATH next to the player name, and applied to the InputMap on start.

## Emitted after a key of a control changed, including a reset to the defaults.
signal controls_changed
signal show_controls_changed(shown: bool)

## The controls that can be rebound, in the order the settings screen lists them.
const CONTROLS := [
	{"action": Inputs.MOVE_UP, "name": "Accelerate"},
	{"action": Inputs.MOVE_DOWN, "name": "Brake / reverse"},
	{"action": Inputs.MOVE_LEFT, "name": "Tilt back"},
	{"action": Inputs.MOVE_RIGHT, "name": "Tilt forward"},
	{"action": Inputs.BOOST, "name": "Boost"},
	{"action": Inputs.INTERACT, "name": "Reset to start"},
	{"action": Inputs.CANCEL, "name": "Pause / back"},
]
## Keys each control can have.
const SLOTS := 2
const CONTROLS_SECTION := "controls"
const DISPLAY_SECTION := "display"

var show_controls: bool:
	get:
		return _show_controls
	set(value):
		if value == _show_controls:
			return
		_show_controls = value
		_save_value(DISPLAY_SECTION, "show_controls", value)
		show_controls_changed.emit(value)

var _show_controls := true

# The keys from project.godot, as {action: Array of physical keycodes}, for reset_controls().
var _default_keys := {}


func _ready() -> void:
	for control: Dictionary in CONTROLS:
		_default_keys[control["action"]] = _read_keys(control["action"])

	var settings := ConfigFile.new()
	if settings.load(GameState.SETTINGS_PATH) != OK:
		return
	var saved_show: Variant = settings.get_value(DISPLAY_SECTION, "show_controls", true)
	if saved_show is bool:
		_show_controls = saved_show
	for control: Dictionary in CONTROLS:
		var saved: Variant = settings.get_value(CONTROLS_SECTION, control["action"], [])
		if saved is Array and settings.has_section_key(CONTROLS_SECTION, control["action"]):
			var keys: Array[Key] = []
			for code: Variant in saved:
				if code is int and code > 0 and keys.size() < SLOTS:
					keys.append(code as Key)
			_write_keys(control["action"], keys)


## The physical keycodes of `action`, one per slot, with KEY_NONE for empty slots.
func get_keys(action: String) -> Array[Key]:
	var keys := _read_keys(action)
	while keys.size() < SLOTS:
		keys.append(KEY_NONE)
	return keys


## Puts the physical key `key` in `slot` of `action`, or empties the slot with KEY_NONE.
## A key belongs to one control only: if another control had it, that one gets the key this
## slot had before, or loses it. Returns the action of that other control, or "".
func set_key(action: String, slot: int, key: Key) -> String:
	var keys := get_keys(action)
	var old_key := keys[slot]
	var changed := ""
	if key != KEY_NONE:
		for control: Dictionary in CONTROLS:
			var other: String = control["action"]
			var other_keys := get_keys(other)
			var index := other_keys.find(key)
			if index == -1 or (other == action and index == slot):
				continue
			if other == action:
				keys[index] = old_key # Swapped between this control's own slots.
				continue
			other_keys[index] = old_key
			_write_keys(other, other_keys)
			_save_keys(other)
			changed = other
	keys[slot] = key
	_write_keys(action, keys)
	_save_keys(action)
	controls_changed.emit()
	return changed


func reset_controls() -> void:
	for control: Dictionary in CONTROLS:
		_write_keys(control["action"], _default_keys[control["action"]])
	var settings := ConfigFile.new()
	settings.load(GameState.SETTINGS_PATH) # Keeps other settings; missing on first use.
	if settings.has_section(CONTROLS_SECTION):
		settings.erase_section(CONTROLS_SECTION)
	_save(settings)
	controls_changed.emit()


## The keys of `action` for showing on screen, like "W / Up", or "no key".
func describe(action: String) -> String:
	var names := PackedStringArray()
	for key in _read_keys(action):
		names.append(key_name(key))
	return " / ".join(names) if not names.is_empty() else "no key"


## The name of a physical key, as printed on the player's keyboard where the platform tells.
func key_name(key: Key) -> String:
	if key == KEY_NONE:
		return ""
	# Only desktop platforms know the keyboard layout; the others print an error for asking.
	if OS.has_feature("pc") and not OS.has_feature("web"):
		key = DisplayServer.keyboard_get_keycode_from_physical(key)
	return OS.get_keycode_string(key)


func _read_keys(action: String) -> Array[Key]:
	var keys: Array[Key] = []
	for event in InputMap.action_get_events(action):
		var key_event := event as InputEventKey
		if key_event and key_event.physical_keycode != KEY_NONE:
			keys.append(key_event.physical_keycode)
	return keys


## Replaces the events of `action` with the keys, skipping empty slots.
func _write_keys(action: String, keys: Array[Key]) -> void:
	InputMap.action_erase_events(action)
	for key in keys:
		if key == KEY_NONE:
			continue
		var event := InputEventKey.new()
		event.physical_keycode = key
		InputMap.action_add_event(action, event)


func _save_keys(action: String) -> void:
	_save_value(CONTROLS_SECTION, action, _read_keys(action).map(func(key: Key) -> int: return key))


func _save_value(section: String, key: String, value: Variant) -> void:
	var settings := ConfigFile.new()
	settings.load(GameState.SETTINGS_PATH) # Keeps other settings; missing on first use.
	settings.set_value(section, key, value)
	_save(settings)


func _save(settings: ConfigFile) -> void:
	var error := settings.save(GameState.SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save the settings: %s" % error_string(error))
