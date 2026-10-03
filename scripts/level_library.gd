class_name LevelLibrary
## Stores levels made with the level builder as JSON files in user://levels.
##
## Each file is named after its level's id. Levels downloaded from other
## players can later be saved here too and will show up like any other level.

const LEVELS_DIR := "user://levels"
const FILE_EXTENSION := "json"


## Returns every saved level, sorted by name. Files that aren't valid levels are skipped.
static func list_levels() -> Array[LevelData]:
	var levels: Array[LevelData] = []
	var dir := DirAccess.open(LEVELS_DIR)
	if dir == null:
		return levels # Nothing has been saved yet.

	for file_name in dir.get_files():
		if file_name.get_extension() != FILE_EXTENSION:
			continue
		var file_id := file_name.get_basename()
		if not LevelData.is_valid_id(file_id):
			push_warning("Skipping level file with invalid name: %s" % file_name)
			continue
		var level := LevelData.from_json(FileAccess.get_file_as_string(LEVELS_DIR.path_join(file_name)))
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


static func save_level(level: LevelData) -> Error:
	var error := DirAccess.make_dir_recursive_absolute(LEVELS_DIR)
	if error != OK:
		return error
	var file := FileAccess.open(_path_for(level), FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(level.to_json())
	file.close()
	return OK


static func delete_level(level: LevelData) -> Error:
	return DirAccess.remove_absolute(_path_for(level))


static func _path_for(level: LevelData) -> String:
	return LEVELS_DIR.path_join("%s.%s" % [level.id, FILE_EXTENSION])
