extends Node
## Player settings: which keys drive the car, how loud the sounds are, whether the controls
## are shown on screen, and whether particles are. Kept in GameState.SETTINGS_PATH next to the player name, and applied to
## the InputMap and the AudioServer on start.

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
## The audio buses with a volume setting, in the order the settings screen lists them.
const VOLUMES := [
	{"bus": AudioBuses.MASTER, "name": "Master"},
	{"bus": AudioBuses.EFFECTS, "name": "Sound effects"},
	{"bus": AudioBuses.ENGINE, "name": "Engine"},
	{"bus": AudioBuses.MUSIC, "name": "Music"},
]
const CONTROLS_SECTION := "controls"
const AUDIO_SECTION := "audio"
const DISPLAY_SECTION := "display"
## Every particle node in the tree, so turning particles off reaches them all.
const PARTICLES_GROUP := &"particles"

var show_controls: bool:
	get:
		return _show_controls
	set(value):
		if value == _show_controls:
			return
		_show_controls = value
		_save_value(DISPLAY_SECTION, "show_controls", value)
		show_controls_changed.emit(value)

## Whether particles, such as the exhaust smoke, are shown. Turning them off also
## stops simulating them.
var particles: bool:
	get:
		return _particles
	set(value):
		if value == _particles:
			return
		_particles = value
		_save_value(DISPLAY_SECTION, "particles", value)
		for node in get_tree().get_nodes_in_group(PARTICLES_GROUP):
			_apply_particles(node)

var _show_controls := true
var _particles := true

# The keys from project.godot, as {action: Array of physical keycodes}, for reset_controls().
var _default_keys := {}


func _ready() -> void:
	for control: Dictionary in CONTROLS:
		_default_keys[control["action"]] = _read_keys(control["action"])
	# Every particle node follows the setting, including the ones scenes make in code.
	get_tree().node_added.connect(_on_node_added)

	var settings := ConfigFile.new()
	if settings.load(GameState.SETTINGS_PATH) != OK:
		return
	var saved_show: Variant = settings.get_value(DISPLAY_SECTION, "show_controls", true)
	if saved_show is bool:
		_show_controls = saved_show
	var saved_particles: Variant = settings.get_value(DISPLAY_SECTION, "particles", true)
	if saved_particles is bool:
		_particles = saved_particles
	for volume: Dictionary in VOLUMES:
		var saved_volume: Variant = settings.get_value(AUDIO_SECTION, volume["bus"], 1.0)
		if saved_volume is float or saved_volume is int:
			_apply_volume(volume["bus"], saved_volume)
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


## The volume of `bus`, from 0 (silent) to 1 (as loud as the sounds were mixed).
func get_volume(bus: StringName) -> float:
	var index := AudioServer.get_bus_index(bus)
	return 0.0 if AudioServer.is_bus_mute(index) else AudioServer.get_bus_volume_linear(index)


## Sets the volume of `bus`, from 0 (silent) to 1, and saves it.
func set_volume(bus: StringName, volume: float) -> void:
	_apply_volume(bus, volume)
	_save_value(AUDIO_SECTION, bus, get_volume(bus))


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


func _on_node_added(node: Node) -> void:
	if node is CPUParticles2D or node is GPUParticles2D:
		node.add_to_group(PARTICLES_GROUP)
		_apply_particles(node)


func _apply_particles(node: CanvasItem) -> void:
	node.visible = _particles
	node.process_mode = Node.PROCESS_MODE_INHERIT if _particles else Node.PROCESS_MODE_DISABLED


func _apply_volume(bus: StringName, volume: float) -> void:
	var index := AudioServer.get_bus_index(bus)
	volume = clampf(volume, 0.0, 1.0)
	# Muted at 0, since the volume in dB would be -inf.
	AudioServer.set_bus_mute(index, volume == 0.0)
	if volume > 0.0:
		AudioServer.set_bus_volume_linear(index, volume)


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
