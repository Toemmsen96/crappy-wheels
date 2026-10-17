extends Control

@export var time_label: Label
## Lists the keys of the controls, unless the settings hide it.
@export var controls_box: Control
@export var controls_label: Label

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	controls_box.visible = Settings.show_controls
	# The settings can change from the pause menu during the level.
	Settings.show_controls_changed.connect(controls_box.set_visible)
	Settings.controls_changed.connect(_list_controls)
	_list_controls()


func _list_controls() -> void:
	var lines := PackedStringArray(["Controls:"])
	for control: Dictionary in Settings.CONTROLS:
		lines.append("%s - %s" % [Settings.describe(control["action"]), control["name"]])
	controls_label.text = "\n".join(lines)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	time_label.text = str(GameState.time_elapsed).pad_decimals(2)
	pass
