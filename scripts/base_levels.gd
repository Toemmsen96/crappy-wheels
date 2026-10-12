class_name BaseLevels
## The levels that come with the game besides Level 1, which is a scene of its own.
##
## Their files are copies of Base/ in the online level repository (made with
## tools/gen_base_levels.py), and they get the ids a download of those files
## would get. So they share a leaderboard with downloaded copies, and the
## backend checks their runs against the files in the repository.

const DIR := "res://levels/base"
## File names in DIR, without the extension, in the order the levels are played.
const FILES: Array[String] = ["level2", "level3", "level4", "level5"]


## Returns the built-in levels in playing order.
static func list() -> Array[LevelData]:
	var levels: Array[LevelData] = []
	for file in FILES:
		var level := _load(file)
		if level != null:
			levels.append(level)
	return levels


## Returns the built-in level with the leaderboard `leaderboard_id`, or null.
static func find(leaderboard_id: String) -> LevelData:
	for file in FILES:
		if id_of(file) == leaderboard_id:
			return _load(file)
	return null


## Whether `leaderboard_id` belongs to a built-in level, Level 1 included.
static func ships_with(leaderboard_id: String) -> bool:
	return leaderboard_id == GameState.LEVEL1_LEADERBOARD \
			or FILES.any(func(file: String) -> bool: return id_of(file) == leaderboard_id)


## Whether `level_id` is a level from Base/ of the online level repository, which
## older versions of the game offered for download.
static func is_copy(level_id: String) -> bool:
	return level_id.begins_with("Base-") # LevelRepository.download_id() of Base/<file>.


## The level after `level` in playing order, or null if it is the last one or not built in.
static func next_after(level: LevelData) -> LevelData:
	if level == null:
		return _load(FILES[0]) # Level 1 is followed by the first of these.
	for i in FILES.size() - 1:
		if id_of(FILES[i]) == level.id:
			return _load(FILES[i + 1])
	return null


static func id_of(file: String) -> String:
	return LevelRepository.download_id("Base/%s.%s" % [file, LevelLibrary.FILE_EXTENSION])


static func _load(file: String) -> LevelData:
	var path := DIR.path_join("%s.%s" % [file, LevelLibrary.FILE_EXTENSION])
	var level := LevelData.from_json(FileAccess.get_file_as_string(path))
	if level == null:
		push_error("Built-in level %s is missing or invalid." % path)
		return null
	level.id = id_of(file)
	return level
