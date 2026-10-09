class_name ReplayLibrary
## Keeps the player's replays as JSON text files, in a folder per level.
##
## Every finished run is saved. Only uploading one, from the finish screen,
## puts it online.

const REPLAYS_DIR := "user://replays"
## A level keeps this many of its latest replays, and its fastest on top.
const MAX_PER_LEVEL := 20


## Saves the replay and returns the file's path, or "" if that failed.
static func save_replay(replay: ReplayData) -> String:
	var dir_path := REPLAYS_DIR.path_join(replay.level_id if LevelData.is_valid_id(replay.level_id) else "other")
	var error := DirAccess.make_dir_recursive_absolute(dir_path)
	if error != OK:
		push_warning("Could not make the replay folder: %s" % error_string(error))
		return ""
	# Named after when it was recorded, so the files sort oldest first.
	var file_name := "%s_%d.%s" % [replay.recorded_at.replace(":", "-"), replay.time_ms, ReplayData.FILE_EXTENSION]
	var path := dir_path.path_join(file_name)
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_warning("Could not save the replay: %s" % error_string(FileAccess.get_open_error()))
		return ""
	file.store_string(replay.to_json())
	file.close()
	_prune(dir_path)
	return path


## Hands the replay file to the player. Downloads it in the web build, where user:// isn't
## reachable; shows it in the file manager elsewhere.
static func export_replay(path: String) -> void:
	if OS.has_feature("web"):
		JavaScriptBridge.download_buffer(FileAccess.get_file_as_bytes(path), path.get_file(), "application/json")
	else:
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(path))


## Deletes the oldest replays beyond MAX_PER_LEVEL, but never the fastest.
static func _prune(dir_path: String) -> void:
	var files := Array(DirAccess.get_files_at(dir_path)).filter(func(file_name: String) -> bool:
		return file_name.get_extension() == ReplayData.FILE_EXTENSION)
	if files.size() <= MAX_PER_LEVEL:
		return
	files.sort()
	var fastest: String = files[0]
	for file_name: String in files:
		if _time_in_name(file_name) < _time_in_name(fastest):
			fastest = file_name
	for file_name: String in files.slice(0, files.size() - MAX_PER_LEVEL):
		if file_name != fastest:
			DirAccess.remove_absolute(dir_path.path_join(file_name))


static func _time_in_name(file_name: String) -> int:
	return file_name.get_basename().get_slice("_", 1).to_int()
