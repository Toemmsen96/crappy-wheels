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
## Tells this player's times apart from those of others with the same name.
## Made on the first submitted time and remembered in SETTINGS_PATH, which the
## web build keeps in the browser's storage for the site. Empty until then.
## Only ever sent to the backend, which doesn't hand it out.
var player_id := ""

const SETTINGS_PATH := "user://settings.cfg"
## Leaderboard of the built-in Level 1. Downloaded levels use their id, which
## comes from their place in the level repository.
const LEVEL1_LEADERBOARD := "level1"

static var _player_id_regex := RegEx.create_from_string("^[0-9a-f]{32}$")


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# The theme's handwritten fonts only have Latin letters. Godot's own font
	# takes over for the rest, e.g. Cyrillic or Greek in a player's name.
	var font := ThemeDB.get_project_theme().default_font
	font.fallbacks = font.fallbacks + [ThemeDB.fallback_font]

	var settings := ConfigFile.new()
	if settings.load(SETTINGS_PATH) == OK:
		var saved_name: Variant = settings.get_value("player", "name", "")
		if saved_name is String:
			player_name = saved_name
		var saved_id: Variant = settings.get_value("player", "id", "")
		if saved_id is String and _player_id_regex.search(saved_id) != null:
			player_id = saved_id


func set_player_name(new_name: String) -> void:
	if new_name == player_name:
		return
	player_name = new_name
	_save_player_setting("name", player_name)


## Returns player_id, making and saving one first if there is none yet.
func ensure_player_id() -> String:
	if player_id.is_empty():
		player_id = Crypto.new().generate_random_bytes(16).hex_encode()
		_save_player_setting("id", player_id)
	return player_id


func _save_player_setting(key: String, value: Variant) -> void:
	var settings := ConfigFile.new()
	settings.load(SETTINGS_PATH) # Keeps other settings; missing on first use.
	settings.set_value("player", key, value)
	var error := settings.save(SETTINGS_PATH)
	if error != OK:
		push_warning("Could not save the player %s: %s" % [key, error_string(error)])


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