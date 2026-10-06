extends CanvasLayer
## Lists the levels in the online level repository and downloads them.
##
## Shared levels are named after random ids in the repository, so every listed
## file is loaded right away to show the level's name, author and description.

## How many level files are loaded at the same time to fill in the list.
const MAX_PARALLEL_LOADS := 4
const DESCRIPTION_FONT_SIZE := 18

@export var repository: LevelRepository
@export var level_list: VBoxContainer
@export var status_label: Label
@export var refresh_button: Button
@export var download_all_button: Button

var _paths := PackedStringArray()
## Levels of the current listing that are loaded, by path.
var _levels := {}
## Rows of the current listing, by path.
var _rows := {}
## Paths of the current listing that are still to be loaded.
var _load_queue: Array[String] = []
## Counts listings, so loads that finish after a refresh are ignored.
var _listing := 0
## Set while listing or downloading levels, so only one of those runs at a time.
## Loading the list's names in the background doesn't count.
var _busy := false


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_refresh()


func _on_RefreshButton_pressed() -> void:
	_refresh()


func _on_DownloadAllButton_pressed() -> void:
	if _busy:
		return
	_set_busy(true)
	var failed := 0
	var failure := ""
	for i in _paths.size():
		status_label.text = "Downloading %d of %d..." % [i + 1, _paths.size()]
		if not await _download(_paths[i]):
			failed += 1
			failure = "%s: %s" % [_display_name(_paths[i]), repository.last_error]
	_set_busy(false)
	if failed == 0:
		status_label.text = "Downloaded all %d levels." % _paths.size()
	else:
		status_label.text = "%d of %d levels could not be downloaded. Last failure: %s" % [failed, _paths.size(), failure]


func _on_BackButton_pressed() -> void:
	get_tree().change_scene_to_file(ScenePaths.LEVEL_SELECTOR)


func _refresh() -> void:
	if _busy:
		return
	_set_busy(true)
	_listing += 1
	_load_queue.clear()
	status_label.text = "Loading levels..."
	_paths = await repository.fetch_level_paths()
	_levels.clear()
	_set_busy(false)
	if not repository.last_error.is_empty():
		status_label.text = "Could not load levels: %s" % repository.last_error
	elif _paths.is_empty():
		status_label.text = "There are no levels online yet."
	else:
		status_label.text = "%d levels online. Downloaded levels appear in the level selector." % _paths.size()
	_populate()
	_load_queue.assign(_paths)
	for i in mini(MAX_PARALLEL_LOADS, _paths.size()):
		_load_queued(_listing)


func _populate() -> void:
	for child in level_list.get_children():
		child.queue_free()
	_rows.clear()
	var downloaded := {}
	for level in LevelLibrary.list_levels(LevelLibrary.DOWNLOADS_DIR):
		downloaded[level.id] = level

	var folder := ""
	for path in _paths:
		if path.get_base_dir() != folder:
			folder = path.get_base_dir()
			var header := Label.new()
			header.text = folder
			header.add_theme_font_size_override("font_size", 32)
			level_list.add_child(header)
		var row := _create_row(path)
		# Until the online file arrives, show the copy downloaded earlier, if there is one.
		var downloaded_level: LevelData = downloaded.get(LevelRepository.download_id(path))
		if downloaded_level:
			_show_level(row, downloaded_level)
			row.button.text = "Update"
		else:
			row.title.text = path.get_file().get_basename()
			_show_details(row, "Loading...")
			row.button.text = "Download"
		_rows[path] = row
		level_list.add_child(row)


func _create_row(path: String) -> LevelRow:
	var row := LevelRow.new()

	var texts := VBoxContainer.new()
	texts.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(texts)
	row.title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	texts.add_child(row.title)
	row.details.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	row.details.add_theme_font_size_override("font_size", DESCRIPTION_FONT_SIZE)
	texts.add_child(row.details)

	row.button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.button.pressed.connect(_on_download_button_pressed.bind(path))
	row.add_child(row.button)

	return row


func _show_level(row: LevelRow, level: LevelData) -> void:
	row.title.text = level.name if level.author.is_empty() else "%s by %s" % [level.name, level.author]
	_show_details(row, level.description)


func _show_details(row: LevelRow, text: String) -> void:
	row.details.text = text
	row.details.visible = not text.is_empty()


## The level's name once it's loaded, otherwise its file name.
func _display_name(path: String) -> String:
	var level: LevelData = _levels.get(path)
	return "\"%s\"" % level.name if level else path.get_file()


func _on_download_button_pressed(path: String) -> void:
	if _busy:
		return
	_set_busy(true)
	status_label.text = "Downloading %s..." % _display_name(path)
	if await _download(path):
		status_label.text = "Downloaded %s." % _display_name(path)
	else:
		status_label.text = "Could not download %s: %s" % [_display_name(path), repository.last_error]
	_set_busy(false)


## Saves the level at `path` into the downloads folder, loading it first unless
## that happened already. Returns whether it worked.
func _download(path: String) -> bool:
	var level: LevelData = _levels.get(path)
	if level == null:
		level = await _load(path)
		if level == null:
			return false
	var error := LevelLibrary.save_level(level, LevelLibrary.DOWNLOADS_DIR)
	if error != OK:
		repository.last_error = "Could not save it (%s)." % error_string(error)
		return false
	var row: LevelRow = _rows.get(path)
	if row:
		row.button.text = "Update"
	return true


## Loads queued level files one after another, until the queue is empty or a
## refresh started a new listing.
func _load_queued(listing: int) -> void:
	while listing == _listing and not _load_queue.is_empty():
		var path: String = _load_queue.pop_front()
		if not _levels.has(path):
			await _load(path)


## Loads the level file at `path` and shows it in its row. Returns null if that
## failed, with the reason in repository.last_error.
func _load(path: String) -> LevelData:
	var listing := _listing
	var level := await repository.download_level(path)
	if listing != _listing:
		return null
	var row: LevelRow = _rows.get(path)
	if level:
		_levels[path] = level
		if row:
			_show_level(row, level)
	elif row:
		_show_details(row, "Could not load this level: %s" % repository.last_error)
	return level


func _set_busy(busy: bool) -> void:
	_busy = busy
	refresh_button.disabled = busy
	download_all_button.disabled = busy or _paths.is_empty()


## A level in the list: its name and author, a line for its description, and its download button.
class LevelRow extends HBoxContainer:
	var title := Label.new()
	var details := Label.new()
	var button := Button.new()
