class_name ShareDialog
extends ConfirmationDialog
## Asks whether to share one of the player's levels with everyone, lets them
## write its description, and then saves and uploads it. A level the player
## shared before is updated instead, which resets its leaderboard, so the
## dialog says so. Used by the level selector and the level builder.

## Tells the screen that opened the dialog how sharing goes, to show it.
signal status_changed(text: String)
## The level was saved with the description from the dialog, or whether it
## counts as shared changed, so what shows it, such as its Share button,
## should be refreshed.
signal level_changed(level: LevelData)

## Remembers the ids of the levels this player shared, so their Share buttons
## can say that sharing again updates them. Not in GameState.SETTINGS_PATH,
## which is about the player rather than their levels.
const SHARED_LEVELS_PATH := "user://shared_levels.cfg"

@export var share_label: Label
## Where the player writes the level's description before sharing it.
@export var description_edit: TextEdit
@export var backend: BackendClient

## True while a level is being uploaded; only one upload runs at a time.
var is_sharing := false

var _level: LevelData
## Whether _level was shared before and is to be updated.
var _update := false


func _ready() -> void:
	confirmed.connect(_on_confirmed)
	description_edit.text_changed.connect(_on_description_edit_text_changed)


## Whether this player shared the level before, as far as this copy of the game knows.
static func is_shared(level: LevelData) -> bool:
	var shared := ConfigFile.new()
	return shared.load(SHARED_LEVELS_PATH) == OK and shared.has_section_key("shared", level.id)


## The text for a Share button of `level`.
static func button_text(level: LevelData) -> String:
	return "Update" if is_shared(level) else "Share"


## The tooltip for a Share button of `level`.
static func button_tooltip(level: LevelData) -> String:
	if is_shared(level):
		return "Upload your changes to the shared level. Its leaderboard and replays start over."
	return "Upload the level so everyone can play it."


## Opens the dialog for `level`, which should be saved already. Does nothing
## while another level is being uploaded.
func ask(level: LevelData) -> void:
	if is_sharing:
		return
	_level = level
	_update = is_shared(level)
	if _update:
		title = "Update shared level?"
		ok_button_text = "Update and reset leaderboard"
		share_label.text = ("Update \"%s\" for everyone? Your changes replace the shared version right away. " \
				+ "Its leaderboard starts over: all times and replays on it are deleted, yours too, " \
				+ "and this can't be undone. Shared levels are published under CC BY-NC-SA 4.0.") % level.name
	else:
		title = "Share level?"
		ok_button_text = "Share"
		share_label.text = ("Share \"%s\" with everyone? It goes into the online levels right away. " \
				+ "You can update it later from this copy of the game, which resets its leaderboard. " \
				+ "Shared levels are published under CC BY-NC-SA 4.0.") % level.name
	description_edit.text = level.description
	description_edit.set_caret_column(level.description.length())
	popup_centered()


func _on_confirmed() -> void:
	if is_sharing or _level == null:
		return
	var level := _level
	var update := _update
	_level = null
	level.description = description_edit.text.strip_edges()
	var error := LevelLibrary.save_level(level)
	if error != OK:
		push_error("Could not save level \"%s\": %s" % [level.name, error_string(error)])
	level_changed.emit(level)

	is_sharing = true
	status_changed.emit(("Updating \"%s\"..." if update else "Sharing \"%s\"...") % level.name)
	var answer := await backend.share_level(level, GameState.ensure_player_id(), update)
	is_sharing = false
	if not answer.is_empty():
		_remember_shared(level, true)
		if answer.get("updated") == true:
			status_changed.emit(("Updated \"%s\"! Its leaderboard starts over. " \
					+ "Players get the new version with Update under Browse Online Levels.") % level.name)
		else:
			status_changed.emit("Shared \"%s\"! Everyone can get it under Browse Online Levels now." % level.name)
		return

	var reason: Variant = backend.last_error_answer.get("reason")
	if reason == "already_shared":
		# Shared from this copy of the game before it remembered shared
		# levels, or with its storage cleared since. Ask again, with the
		# warning that updating resets the leaderboard.
		_remember_shared(level, true)
		status_changed.emit("\"%s\" was shared before. Sharing it again updates it." % level.name)
		ask(level)
	elif reason == "not_owner":
		_remember_shared(level, false)
		status_changed.emit(("\"%s\" was shared by another player, or from another device or browser. " \
				+ "Only whoever shared it can update it.") % level.name)
	elif reason == "no_owner":
		_remember_shared(level, false)
		status_changed.emit("\"%s\" was shared before shared levels could be updated, so it can't be updated." % level.name)
	elif reason == "removed":
		_remember_shared(level, false)
		status_changed.emit("\"%s\" was taken out of the online levels, so it can't be updated." % level.name)
	else:
		status_changed.emit(("Could not update \"%s\": %s" if update else "Could not share \"%s\": %s") \
				% [level.name, backend.last_error])


## TextEdit has no length limit, and the level file keeps descriptions on one line anyway.
func _on_description_edit_text_changed() -> void:
	var text := description_edit.text
	var cleaned := LevelData.to_single_line(text).left(LevelData.MAX_DESCRIPTION_LENGTH)
	if cleaned == text:
		return
	var caret := description_edit.get_caret_column()
	for line in description_edit.get_caret_line():
		caret += description_edit.get_line(line).length() + 1
	description_edit.text = cleaned
	description_edit.set_caret_column(mini(caret, cleaned.length()))


## Remembers whether this player can update `level`, i.e. shared it.
func _remember_shared(level: LevelData, shared_by_player: bool) -> void:
	var shared := ConfigFile.new()
	shared.load(SHARED_LEVELS_PATH) # Missing until the first level is shared.
	if shared_by_player:
		shared.set_value("shared", level.id, true)
	elif shared.has_section_key("shared", level.id):
		shared.erase_section_key("shared", level.id)
	else:
		return
	var error := shared.save(SHARED_LEVELS_PATH)
	if error != OK:
		push_warning("Could not remember that \"%s\" was shared: %s" % [level.name, error_string(error)])
	level_changed.emit(level)
