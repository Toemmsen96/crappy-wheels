extends CanvasLayer
## Lists the levels in the online level repository and downloads them.

@export var repository: LevelRepository
@export var level_list: VBoxContainer
@export var status_label: Label
@export var refresh_button: Button
@export var download_all_button: Button

var _paths := PackedStringArray()
## Set while talking to the server, so only one download runs at a time.
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
			failure = "%s: %s" % [_paths[i].get_file(), repository.last_error]
	_set_busy(false)
	if failed == 0:
		status_label.text = "Downloaded all %d levels." % _paths.size()
	else:
		status_label.text = "%d of %d levels could not be downloaded. Last failure: %s" % [failed, _paths.size(), failure]
	_populate()


func _on_BackButton_pressed() -> void:
	get_tree().change_scene_to_file(ScenePaths.LEVEL_SELECTOR)


func _refresh() -> void:
	if _busy:
		return
	_set_busy(true)
	status_label.text = "Loading levels..."
	_paths = await repository.fetch_level_paths()
	_set_busy(false)
	if not repository.last_error.is_empty():
		status_label.text = "Could not load levels: %s" % repository.last_error
	elif _paths.is_empty():
		status_label.text = "There are no levels online yet."
	else:
		status_label.text = "%d levels online. Downloaded levels appear in the level selector." % _paths.size()
	download_all_button.disabled = _paths.is_empty()
	_populate()


func _populate() -> void:
	for child in level_list.get_children():
		child.queue_free()
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
		level_list.add_child(_create_row(path, downloaded.get(LevelRepository.download_id(path))))


func _create_row(path: String, downloaded_level: LevelData) -> HBoxContainer:
	var row := HBoxContainer.new()

	var name_label := Label.new()
	name_label.text = downloaded_level.name if downloaded_level else path.get_file().get_basename()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)

	var download_button := Button.new()
	download_button.text = "Update" if downloaded_level else "Download"
	download_button.pressed.connect(_on_download_button_pressed.bind(path))
	row.add_child(download_button)

	return row


func _on_download_button_pressed(path: String) -> void:
	if _busy:
		return
	_set_busy(true)
	status_label.text = "Downloading %s..." % path.get_file()
	if await _download(path):
		status_label.text = "Downloaded %s." % path.get_file()
	else:
		status_label.text = "Could not download %s: %s" % [path.get_file(), repository.last_error]
	_set_busy(false)
	_populate()


## Downloads the level at `path` into the downloads folder. Returns whether it worked.
func _download(path: String) -> bool:
	var level := await repository.download_level(path)
	if level == null:
		return false
	var error := LevelLibrary.save_level(level, LevelLibrary.DOWNLOADS_DIR)
	if error != OK:
		repository.last_error = "Could not save it (%s)." % error_string(error)
		return false
	return true


func _set_busy(busy: bool) -> void:
	_busy = busy
	refresh_button.disabled = busy
	download_all_button.disabled = busy or _paths.is_empty()
