extends Node

var time_elapsed := 0.0
# You don't really need this
var counter = 1
var is_stopped := false
## Builder level to edit or play. The builder starts a new level when this is null.
var current_level: LevelData = null
## Whether current_level is being test-played from the level builder.
var testing_in_builder := false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	
	pass


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if !is_stopped:
		time_elapsed += _delta

func finish_level() -> void:
	print("Level finished!")
	stop()
	pass


func reset() -> void:
	# possibly save time_elapsed somewhere else before overriding it
	time_elapsed = 0.0
	is_stopped = false

func stop() -> void:
	is_stopped = true