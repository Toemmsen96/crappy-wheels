extends Node

var time_elapsed := 0.0
# You don't really need this
var counter = 1
var is_stopped := false
## Builder level to edit or play. The builder starts a new level when this is null.
var current_level: LevelData = null
## Whether current_level is being test-played from the level builder.
var testing_in_builder := false
## Leaderboard of the level being played, the same on every player's machine,
## or empty if it has none. The player's own levels have none, since they can
## still be edited.
var leaderboard_id := ""
## Name the player's times are submitted under. Remembered in SETTINGS_PATH.
var player_name := ""

const SETTINGS_PATH := "user://settings.cfg"
## Leaderboard of the built-in Level 1. Downloaded levels use their id, which
## comes from their place in the level repository.
const LEVEL1_LEADERBOARD := "level1"


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		var saved_name: Variant = settings.get_value("player", "name", "")
		if saved_name is String:
			player_name = saved_name


func set_player_name(new_name: String) -> void:
	if new_name == player_name:
		return
	player_name = new_name
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH) # Keeps other settings; missing on first use.
	settings.set_value("player", "name", player_name)
	var error := settings.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save the player name: %s" % error_string(error))


## Whether the level being played has a leaderboard to submit times to.
func has_leaderboard() -> bool:
	return not leaderboard_id.is_empty() and not testing_in_builder


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