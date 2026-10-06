extends CanvasLayer
## Credits and licenses: the game, its fonts, and Godot Engine with its third-party components.
##
## The Godot part follows "Complying with licenses" in the Godot docs and comes from the engine
## itself, so it always matches the engine the game runs on.

## The full Open Font License; both font files carry the same text below their own copyright lines.
const OFL_PATH := "res://assets/fonts/OFL-GochiHand.txt"
## Font size of the long license texts.
const SMALL_FONT_SIZE := 18
## Font size of the headings inside a panel.
const HEADING_FONT_SIZE := 32
## Sets the copyright lines of a component apart from its name.
const INDENT := "    "
## Long texts are split into labels of about this many characters, so that the renderer can skip
## the labels that are scrolled out of view, and so that the text can be laid out a bit at a time.
const CHUNK_CHARS := 2000
## About how much text is added per frame while the screen fills in.
const CHARS_PER_FRAME := 2000

## Gets the full Open Font License below the font copyright lines.
@export var fonts_content: VBoxContainer
## Gets the Godot license, the third-party components and their licenses.
@export var engine_content: VBoxContainer

## Steps that add the long texts, run a few per frame so that the screen opens at once.
## Each one is [Callable, number of characters it adds].
var _pending: Array[Array] = []


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_queue_text(fonts_content, _load_ofl(), SMALL_FONT_SIZE)
	_queue_engine_credits()


func _process(_delta: float) -> void:
	var added := 0
	while not _pending.is_empty() and added < CHARS_PER_FRAME:
		var step: Array = _pending.pop_front()
		(step[0] as Callable).call()
		added += step[1] as int
	if _pending.is_empty():
		set_process(false)


func _on_BackButton_pressed() -> void:
	get_tree().change_scene_to_file(ScenePaths.MAIN_MENU)


## The license part of the OFL file, without the copyright lines of that one font.
func _load_ofl() -> String:
	var text := FileAccess.get_file_as_string(OFL_PATH)
	if text.is_empty():
		push_error("Could not read %s: %s" % [OFL_PATH, error_string(FileAccess.get_open_error())])
		return "The license is available at https://openfontlicense.org"
	var start := text.find("-----")
	return text.substr(maxi(start, 0)).strip_edges()


func _queue_engine_credits() -> void:
	_queue_text(engine_content, "This game uses Godot Engine, available under the following license:", 0)
	_queue_text(engine_content, Engine.get_license_text(), SMALL_FONT_SIZE)

	var components := Engine.get_copyright_info()
	_queue_text(engine_content, "Third-party components", HEADING_FONT_SIZE)
	var notes := "Godot Engine includes the following third-party components."
	var freetype := _freetype_years(components)
	if not freetype.is_empty():
		# The FreeType License asks for this sentence in the documentation.
		notes += "\nPortions of this software are copyright © %s The FreeType Project (www.freetype.org). All rights reserved." % freetype
	_queue_text(engine_content, notes, 0)
	var entries := PackedStringArray()
	for component: Dictionary in components:
		var lines := PackedStringArray([component["name"]])
		for part: Dictionary in component["parts"]:
			for holder: String in part["copyright"]:
				lines.append(INDENT + "© " + holder)
			lines.append(INDENT + "License: " + part["license"])
		entries.append("\n".join(lines))
	_queue_text(engine_content, "\n\n".join(entries), SMALL_FONT_SIZE)

	_queue_text(engine_content, "Third-party licenses", HEADING_FONT_SIZE)
	var licenses := Engine.get_license_info()
	for license_name: String in licenses:
		_queue_text(engine_content, license_name, 0)
		_queue_text(engine_content, licenses[license_name], SMALL_FONT_SIZE)


## The years of the FreeType copyright, e.g. "1996-2025", or "" if the engine has no FreeType.
func _freetype_years(components: Array[Dictionary]) -> String:
	for component in components:
		if component["name"] == "The FreeType Project":
			var holder: String = component["parts"][0]["copyright"][0]
			return holder.get_slice(",", 0)
	return ""


## Queues adding text to content, in chunks if it is long. A font_size of 0 keeps the theme's size.
func _queue_text(content: VBoxContainer, text: String, font_size: int) -> void:
	# Some license texts end with empty lines, which would widen the gap before the next one.
	text = text.strip_edges(false, true)
	if text.length() <= CHUNK_CHARS:
		_pending.append([_add_text.bind(content, content, text, font_size), text.length()])
		return
	# The chunks of one text share a box without separation, and every chunk but the last ends
	# with an empty line, so the text reads as if it were one label.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 0)
	_pending.append([content.add_child.bind(box), 0])
	var chunks := _split(text)
	for i in chunks.size():
		var chunk := chunks[i] + ("\n" if i < chunks.size() - 1 else "")
		_pending.append([_add_text.bind(box, content, chunk, font_size), chunk.length()])


## Splits text at empty lines into pieces of at most about CHUNK_CHARS characters.
func _split(text: String) -> PackedStringArray:
	var chunks := PackedStringArray()
	var current := ""
	for paragraph in text.split("\n\n"):
		if not current.is_empty() and current.length() + paragraph.length() > CHUNK_CHARS:
			chunks.append(current)
			current = ""
		current = paragraph if current.is_empty() else current + "\n\n" + paragraph
	if not current.is_empty():
		chunks.append(current)
	return chunks


## Adds a label to parent that will be as wide as content.
func _add_text(parent: Container, content: Control, text: String, font_size: int) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# The theme's paper outline is for text on the background; these sit on paper already,
	# and an outline around tens of KB of text would cost a lot to draw.
	label.add_theme_constant_override("outline_size", 0)
	if font_size > 0:
		label.add_theme_font_size_override("font_size", font_size)
	# Given its width now, the label wraps its text once; otherwise it would first wrap it at
	# almost no width, which takes several times longer, before the container widens it.
	label.size.x = content.size.x
	parent.add_child(label)
