class_name BackendClient
extends Node
## Talks to the Crappy-Wheels backend (github.com/Toemmsen96/crappy-wheels-backend),
## which keeps the leaderboards and puts shared levels into the level repository.
##
## Methods are coroutines: `await` them, then check last_error.

const TIMEOUT_SECONDS := 15.0
## Sharing a level or a replay, or a time with its replay, waits for the
## server to push it to GitHub, after any upload that is already in progress.
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
## has "you" set to true. Times with an uploaded replay have its path in the
## level repository as "replay", for LevelRepository.download_replay().
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
			if not (entry.get("replay") is String and LevelRepository.is_replay_path(entry["replay"])):
				entry.erase("replay")
			scores.append(entry)
	return scores


## Submits the time of a run with its replay, which the server checks against
## the level: only runs that start at its start, end at its finish and stay
## out of its floors count. The server keeps only each player's best time;
## player_id tells players apart, player_name is what the leaderboard shows.
## Returns its answer with "best_time_ms", "rank" and "improved", or {} on
## failure. A new best time's replay goes into the level repository, where
## everyone can watch it from the leaderboard: the answer then has its path as
## "replay", or why it couldn't go there as "replay_error", in which case
## submit_replay() can try again.
func submit_score(leaderboard_id: String, player_id: String, player_name: String, replay: ReplayData) -> Dictionary:
	var body := "{\"player_id\": %s, \"name\": %s, \"time_ms\": %d, \"replay\": %s}" % [
			JSON.stringify(player_id), JSON.stringify(player_name), replay.time_ms, replay.to_json()]
	var answer: Variant = await _request(HTTPClient.METHOD_POST, "/v1/levels/%s/scores" % leaderboard_id.uri_encode(), body, SHARE_TIMEOUT_SECONDS)
	if answer == null:
		return {}
	if not (_is_number(answer.get("best_time_ms")) and _is_number(answer.get("rank"))):
		last_error = "Unexpected answer from the server."
		return {}
	return answer


## Uploads the replay of the player's best time on a level, for when it
## couldn't go online with the time. The server puts it into the level
## repository, where everyone can watch it from the leaderboard, and removes
## the player's previous replay of the level. Returns its answer with "path"
## and "url", or {} on failure; last_status is 409 if the replay isn't of the
## player's best time.
func submit_replay(leaderboard_id: String, player_id: String, replay: ReplayData) -> Dictionary:
	var body := "{\"player_id\": %s, \"replay\": %s}" % [JSON.stringify(player_id), replay.to_json()]
	var answer: Variant = await _request(HTTPClient.METHOD_POST, "/v1/levels/%s/replays" % leaderboard_id.uri_encode(), body, SHARE_TIMEOUT_SECONDS)
	return answer if answer != null else {}


## Shares a level with everyone: the server adds it to the Community folder of
## the level repository. Returns its answer with "id", "path" and "url", or {}
## on failure. last_status is 409 if a level with this id was shared before.
func share_level(level: LevelData) -> Dictionary:
	var answer: Variant = await _request(HTTPClient.METHOD_POST, "/v1/levels", level.to_json(), SHARE_TIMEOUT_SECONDS)
	return answer if answer != null else {}


## Turns a message from the server, such as "too many scores submitted",
## into a sentence to show.
static func as_sentence(message: String) -> String:
	return message.left(1).to_upper() + message.substr(1) + "."


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
			last_error = as_sentence(json["error"])
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
