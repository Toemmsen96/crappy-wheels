extends Control

@export var time_label: Label
## Lists the keys of the controls, unless the settings hide it.
@export var controls_box: Control
@export var controls_label: Label

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	controls_box.visible = Settings.show_controls
	var lines := PackedStringArray(["Controls:"])
	for control: Dictionary in Settings.CONTROLS:
		lines.append("%s - %s" % [Settings.describe(control["action"]), control["name"]])
	controls_label.text = "\n".join(lines)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	time_label.text = str(GameState.time_elapsed).pad_decimals(2)
	pass
