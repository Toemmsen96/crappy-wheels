class_name BackendClient
extends Node
## Talks to the Crappy-Wheels backend (github.com/Toemmsen96/crappy-wheels-backend),
## which keeps the leaderboards and puts shared levels into the level repository.
##
## Methods are coroutines: `await` them, then check last_error.

const TIMEOUT_SECONDS := 15.0
## Sharing waits for the server to push the level to GitHub, after any share
## that is already in progress.
const SHARE_TIMEOUT_SECONDS := 60.0
## Answers are small JSON documents; anything bigger is not from the backend.
const MAX_RESPONSE_BYTES := 64 * 1024

## File with the backend's address. It is not in the repository: the deploy
## workflow writes it from the BACKEND_URL secret, and backend.cfg.example
## shows how to write your own.
const CONFIG_PATH := "res://backend.cfg"

## Where the backend runs. Left empty, it is read from CONFIG_PATH.
@export var base_url := ""

## Why the last call failed, or empty if it succeeded.
var last_error := ""
## HTTP status of the last answer, or 0 if the server wasn't reached.
var last_status := 0


func _ready() -> void:
	if base_url.is_empty():
		base_url = _configured_url()


## Returns the fastest times on a level, best first, as dictionaries with
## "rank", "name" and "time_ms". With a player_id, that player's score also
## has "you" set to true.
func fetch_scores(leaderboard_id: String, limit := 10, player_id := "") -> Array[Dictionary]:
	var scores: Array[Dictionary] = []
	var path := "/v1/levels/%s/scores?limit=%d" % [leaderboard_id.uri_encode(), limit]
	if not player_id.is_empty():
		path += "&player=" + player_id.uri_encode()
	var answer: Variant = await _request(HTTPClient.METHOD_GET, path)
	if answer == null:
		return scores
	if not (answer.get("scores") is Array):
		last_error = "Unexpected answer from the server."
		return scores
	for entry: Variant in answer["scores"]:
		if entry is Dictionary and entry.get("name") is String and _is_number(entry.get("time_ms")) and _is_number(entry.get("rank")):
			scores.append(entry)
	return scores


## Submits a finishing time. The server keeps only each player's best time;
## player_id tells players apart, player_name is what the leaderboard shows.
## Returns its answer with "best_time_ms", "rank" and "improved", or {} on failure.
func submit_score(leaderboard_id: String, player_id: String, player_name: String, time_ms: int) -> Dictionary:
	var body := JSON.stringify({"player_id": player_id, "name": player_name, "time_ms": time_ms})
	var answer: Variant = await _request(HTTPClient.METHOD_POST, "/v1/levels/%s/scores" % leaderboard_id.uri_encode(), body)
	if answer == null:
		return {}
	if not (_is_number(answer.get("best_time_ms")) and _is_number(answer.get("rank"))):
		last_error = "Unexpected answer from the server."
		return {}
	return answer


## Shares a level with everyone: the server adds it to the Community folder of
## the level repository. Returns its answer with "id", "path" and "url", or {}
## on failure. last_status is 409 if a level with this id was shared before.
func share_level(level: LevelData) -> Dictionary:
	var answer: Variant = await _request(HTTPClient.METHOD_POST, "/v1/levels", level.to_json(), SHARE_TIMEOUT_SECONDS)
	return answer if answer != null else {}


## Formats a time from the server like the finish screen shows times.
static func format_time(time_ms: float) -> String:
	return "%.3f s" % (time_ms / 1000.0)


## Returns the answer as a Dictionary, or null and sets last_error.
func _request(method: HTTPClient.Method, path: String, body := "", timeout := TIMEOUT_SECONDS) -> Variant:
	last_error = ""
	last_status = 0
	if base_url.is_empty():
		last_error = "This copy of the game has no server set up."
		return null
	var request := HTTPRequest.new()
	request.body_size_limit = MAX_RESPONSE_BYTES
	request.timeout = timeout
	add_child(request)
	var headers := PackedStringArray()
	if not body.is_empty():
		headers.append("Content-Type: application/json")
	var error := request.request(base_url.trim_suffix("/") + path, headers, method, body)
	if error != OK:
		request.queue_free()
		last_error = "Could not start the request (%s)." % error_string(error)
		return null

	# [result, response_code, headers, body]
	var response: Array = await request.request_completed
	request.queue_free()
	if response[0] != HTTPRequest.RESULT_SUCCESS:
		last_error = "Could not reach the server. Check your internet connection."
		return null
	last_status = response[1]
	var json: Variant = JSON.parse_string(response[3].get_string_from_utf8())
	if last_status < 200 or last_status >= 300:
		# The server explains its errors as {"error": "..."}.
		if json is Dictionary and json.get("error") is String and not json["error"].is_empty():
			var message: String = json["error"]
			last_error = message.left(1).to_upper() + message.substr(1) + "."
		else:
			last_error = "The server answered with error %d." % last_status
		return null
	if not (json is Dictionary):
		last_error = "Unexpected answer from the server."
		return null
	return json


## Returns the address in CONFIG_PATH, or "" if the file is missing or has none.
static func _configured_url() -> String:
	var config := ConfigFile.new()
	if config.load(CONFIG_PATH) != OK:
		return ""
	var url: Variant = config.get_value("backend", "url", "")
	if not (url is String) or url.strip_edges().is_empty():
		return ""
	var address: String = url.strip_edges()
	# A bare host name, such as example.org, is taken to mean HTTPS.
	return address if address.contains("://") else "https://" + address


static func _is_number(value: Variant) -> bool:
	return value is int or value is float
