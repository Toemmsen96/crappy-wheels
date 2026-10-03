class_name LevelRepository
extends Node
## Fetches levels from the public crappy-wheels-levels GitHub repository.
##
## Levels are submitted there with pull requests. Every .json file directly
## inside one of FOLDERS is listed, so merged levels show up without an index.
## Methods are coroutines: `await` them, then check last_error.

const FOLDERS: Array[String] = ["Base", "Community"]
## Larger files are skipped. Levels at LevelData.MAX_OBJECTS are around 200 KB.
const MAX_LEVEL_BYTES := 1024 * 1024
## The file tree lists every file in the repository, so it gets more room.
const MAX_TREE_BYTES := 8 * 1024 * 1024
const TIMEOUT_SECONDS := 15.0

## GitHub repository to read levels from. Point these at a fork to test level submissions.
@export var repo_owner := "Toemmsen96"
@export var repository := "crappy-wheels-levels"
@export var branch := "main"

## Why the last call failed, or empty if it succeeded.
var last_error := ""


## Returns the repository paths of all levels, e.g. "Community/loop.json", sorted.
func fetch_level_paths() -> PackedStringArray:
	last_error = ""
	var paths := PackedStringArray()
	var url := "https://api.github.com/repos/%s/%s/git/trees/%s?recursive=1" % [repo_owner, repository, branch]
	var body: Variant = await _http_get(url, MAX_TREE_BYTES)
	if body == null:
		return paths

	var json := JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK or not (json.data is Dictionary and json.data.get("tree") is Array):
		last_error = "Unexpected response from GitHub."
		return paths
	for entry: Variant in json.data["tree"]:
		if not (entry is Dictionary and entry.get("type") == "blob" and entry.get("path") is String):
			continue
		var path: String = entry["path"]
		var size: Variant = entry.get("size", 0)
		if path.get_extension() == LevelLibrary.FILE_EXTENSION and path.get_base_dir() in FOLDERS \
				and (size is int or size is float) and size <= MAX_LEVEL_BYTES:
			paths.append(path)
	paths.sort()
	return paths


## Downloads and validates the level at `path`. Returns null on failure.
func download_level(path: String) -> LevelData:
	last_error = ""
	var encoded_path := "/".join(Array(path.split("/")).map(func(part: String) -> String: return part.uri_encode()))
	var url := "https://raw.githubusercontent.com/%s/%s/%s/%s" % [repo_owner, repository, branch, encoded_path]
	var body: Variant = await _http_get(url, MAX_LEVEL_BYTES)
	if body == null:
		return null

	var level := LevelData.from_json(body.get_string_from_utf8())
	if level == null:
		last_error = "Not a valid level file."
		return null
	level.id = download_id(path)
	return level


## The id a downloaded level is saved under, based on where it is in the repository,
## so downloading it again replaces the old copy.
static func download_id(path: String) -> String:
	var id := ""
	for character in path.get_basename().replace("/", "-"):
		id += character if LevelData.is_valid_id(character) else "_"
	return id.left(64)


## Returns the response body as a PackedByteArray, or null and sets last_error.
func _http_get(url: String, max_bytes: int) -> Variant:
	var request := HTTPRequest.new()
	request.body_size_limit = max_bytes
	request.timeout = TIMEOUT_SECONDS
	add_child(request)
	var error := request.request(url)
	if error != OK:
		request.queue_free()
		last_error = "Could not start the download (%s)." % error_string(error)
		return null

	# [result, response_code, headers, body]
	var response: Array = await request.request_completed
	request.queue_free()
	var result: int = response[0]
	var status: int = response[1]
	if result == HTTPRequest.RESULT_BODY_SIZE_LIMIT_EXCEEDED:
		last_error = "The file is too large."
	elif result != HTTPRequest.RESULT_SUCCESS:
		last_error = "Could not connect. Check your internet connection."
	elif status == 403 or status == 429:
		last_error = "GitHub's download limit was reached. Try again later."
	elif status == 404:
		last_error = "Not found. Is the level repository public?"
	elif status != 200:
		last_error = "The server answered with error %d." % status
	else:
		return response[3]
	return null
