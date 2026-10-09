class_name LevelLibrary
## Stores levels as JSON files, one per level, named after the level's id.
##
## The player's own levels live in LEVELS_DIR. Levels downloaded from the
## online level repository live in DOWNLOADS_DIR, so they can't overwrite
## the player's own levels and re-downloading one updates it.

const LEVELS_DIR := "user://levels"
const DOWNLOADS_DIR := "user://downloads"
const FILE_EXTENSION := "json"


## Returns every level in `dir`, sorted by name. Files that aren't valid levels are skipped.
static func list_levels(dir_path := LEVELS_DIR) -> Array[LevelData]:
	var levels: Array[LevelData] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return levels # Nothing has been saved yet.

	for file_name in dir.get_files():
		if file_name.get_extension() != FILE_EXTENSION:
			continue
		var file_id := file_name.get_basename()
		if not LevelData.is_valid_id(file_id):
			push_warning("Skipping level file with invalid name: %s" % file_name)
			continue
		var level := LevelData.from_json(FileAccess.get_file_as_string(dir_path.path_join(file_name)))
		if level == null:
			push_warning("Skipping invalid level file: %s" % file_name)
			continue
		# The file name wins over the id inside the file, so deleting and
		# overwriting always hits this file.
		level.id = file_id
		levels.append(level)

	levels.sort_custom(func(a: LevelData, b: LevelData) -> bool:
		return a.name.naturalnocasecmp_to(b.name) < 0)
	return levels


## Returns the level with this id in `dir_path`, or null if there is none.
static func load_level(id: String, dir_path := LEVELS_DIR) -> LevelData:
	if not LevelData.is_valid_id(id):
		return null
	var path := dir_path.path_join("%s.%s" % [id, FILE_EXTENSION])
	if not FileAccess.file_exists(path):
		return null
	var level := LevelData.from_json(FileAccess.get_file_as_string(path))
	if level != null:
		level.id = id
	return level


static func save_level(level: LevelData, dir_path := LEVELS_DIR) -> Error:
	var error := DirAccess.make_dir_recursive_absolute(dir_path)
	if error != OK:
		return error
	var file := FileAccess.open(_path_for(level, dir_path), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(level.to_json())
	file.close()
	return OK


static func delete_level(level: LevelData, dir_path := LEVELS_DIR) -> Error:
	return DirAccess.remove_absolute(_path_for(level, dir_path))


## Hands the level's file to the player, e.g. to submit it to the level repository.
## Downloads it in the web build, where user:// isn't reachable; shows it in the file manager elsewhere.
static func export_level(level: LevelData) -> void:
	if OS.has_feature("web"):
		var file_name := "%s.%s" % [level.name.validate_filename(), FILE_EXTENSION]
		JavaScriptBridge.download_buffer(level.to_json().to_utf8_buffer(), file_name, "application/json")
	else:
		OS.shell_show_in_file_manager(ProjectSettings.globalize_path(_path_for(level, LEVELS_DIR)))


static func _path_for(level: LevelData, dir_path: String) -> String:
	return dir_path.path_join("%s.%s" % [level.id, FILE_EXTENSION])
