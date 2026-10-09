class_name ReplayData
extends RefCounted
## A recorded run through a level: where the car was, how it and its wheels
## were turned, and which controls were held, every interval_ms from the start
## of the run. The last frame is the moment the car crossed the finish.
##
## Saved as JSON text with a frame per line. The backend reads the same format
## (crappy-wheels-backend/internal/replay); keep the two in sync.

const FORMAT_VERSION := 1
const FILE_EXTENSION := "json"
## Values per frame: x, y, rotation, front wheel rotation, rear wheel rotation, controls.
const FRAME_SIZE := 6
const DEFAULT_INTERVAL_MS := 50
const MIN_INTERVAL_MS := 10
const MAX_INTERVAL_MS := 200
## About 15 minutes at 50 ms, which keeps a file under the backend's 1 MiB.
## Longer runs are recorded no further and can't be uploaded.
const MAX_FRAMES := 18000
## Positions and rotations beyond this are not from a real run.
const MAX_VALUE := 1e7
## The longest run the leaderboards take, 24 hours.
const MAX_TIME_MS := 24 * 60 * 60 * 1000

# Bits of the controls value.
const UP := 1
const DOWN := 2
const LEFT := 4
const RIGHT := 8
const BOOST := 16
const ALL_CONTROLS := UP | DOWN | LEFT | RIGHT | BOOST

## The level's leaderboard id if it has one, else the id of the player's own level.
var level_id := ""
## Only in the player's own files; the backend leaves it out.
var level_name := ""
var player_name := ""
var time_ms := 0
## When the run was recorded, in UTC. Only in the player's own files.
var recorded_at := ""
var interval_ms := DEFAULT_INTERVAL_MS
## FRAME_SIZE values per frame. Rotations are in radians and not wrapped, so
## frames can be interpolated however fast the wheels spin.
var frames := PackedFloat64Array()
## Set when the run went on past MAX_FRAMES, so the end is missing.
var is_cut_off := false


func frame_count() -> int:
	@warning_ignore("integer_division")
	return frames.size() / FRAME_SIZE


## Adds a frame. Returns false, and sets is_cut_off, once the replay is full.
func add_frame(position: Vector2, rotation: float, front_wheel: float, rear_wheel: float, controls: int) -> bool:
	if frame_count() >= MAX_FRAMES:
		is_cut_off = true
		return false
	frames.append_array([position.x, position.y, rotation, front_wheel, rear_wheel, controls])
	return true


## How long the replay plays, in seconds.
func duration() -> float:
	return _frame_time(frame_count() - 1)


## Whether the backend takes this replay: the whole run, with as many frames as its time calls for.
func can_upload() -> bool:
	var expected := ceili(float(time_ms) / interval_ms) + 1
	return not is_cut_off and time_ms > 0 and absi(frame_count() - expected) <= 3


## The car at `seconds` into the run, between the frames around it: a dictionary with
## "position", "rotation", "front_wheel", "rear_wheel" and "controls".
func sample(seconds: float) -> Dictionary:
	var count := frame_count()
	# Frames are evenly spaced up to the last one, which is at the finish.
	var index := clampi(floori(seconds * 1000.0 / interval_ms), 0, maxi(count - 2, 0))
	var next := mini(index + 1, count - 1)
	var span := _frame_time(next) - _frame_time(index)
	var weight := clampf((seconds - _frame_time(index)) / span, 0.0, 1.0) if span > 0.0 else 0.0
	var a := index * FRAME_SIZE
	var b := next * FRAME_SIZE
	return {
		"position": Vector2(lerpf(frames[a], frames[b], weight), lerpf(frames[a + 1], frames[b + 1], weight)),
		"rotation": lerpf(frames[a + 2], frames[b + 2], weight),
		"front_wheel": lerpf(frames[a + 3], frames[b + 3], weight),
		"rear_wheel": lerpf(frames[a + 4], frames[b + 4], weight),
		"controls": int(frames[a + 5]),
	}


func to_json() -> String:
	var lines := PackedStringArray()
	for field: Array in [
			["format_version", FORMAT_VERSION],
			["interval_ms", interval_ms],
			["level_id", level_id],
			["level_name", level_name],
			["player_name", player_name],
			["recorded_at", recorded_at],
			["time_ms", time_ms]]:
		lines.append("\t%s: %s" % [JSON.stringify(field[0]), JSON.stringify(field[1])])
	var rows := PackedStringArray()
	for i in frame_count():
		var at := i * FRAME_SIZE
		# Tenths of a pixel and thousandths of a radian are plenty, and keep the file small.
		rows.append("\t\t[%s,%s,%s,%s,%s,%d]" % [_number(frames[at], 1), _number(frames[at + 1], 1),
				_number(frames[at + 2], 3), _number(frames[at + 3], 3), _number(frames[at + 4], 3), int(frames[at + 5])])
	lines.append("\t\"frames\": [\n%s\n\t]" % ",\n".join(rows))
	return "{\n%s\n}\n" % ",\n".join(lines)


## Reads a replay from JSON. Returns null if it isn't a valid one.
static func from_json(text: String) -> ReplayData:
	var data: Variant = JSON.parse_string(text)
	if not (data is Dictionary):
		return null
	if data.get("format_version") != float(FORMAT_VERSION):
		return null
	var replay := ReplayData.new()
	var time: Variant = data.get("time_ms")
	var interval: Variant = data.get("interval_ms")
	if not (_is_whole(time) and time >= 1 and time <= MAX_TIME_MS):
		return null
	if not (_is_whole(interval) and interval >= MIN_INTERVAL_MS and interval <= MAX_INTERVAL_MS):
		return null
	replay.time_ms = int(time)
	replay.interval_ms = int(interval)
	for key in ["level_id", "level_name", "player_name", "recorded_at"]:
		var value: Variant = data.get(key, "")
		if value is String:
			replay.set(key, LevelData.to_single_line(value).left(LevelData.MAX_NAME_LENGTH))

	var raw_frames: Variant = data.get("frames")
	if not (raw_frames is Array) or raw_frames.size() < 2 or raw_frames.size() > MAX_FRAMES:
		return null
	replay.frames.resize(raw_frames.size() * FRAME_SIZE)
	for i in raw_frames.size():
		var frame: Variant = raw_frames[i]
		if not (frame is Array and frame.size() == FRAME_SIZE):
			return null
		for j in FRAME_SIZE:
			var value: Variant = frame[j]
			if not ((value is float or value is int) and absf(value) <= MAX_VALUE):
				return null
			replay.frames[i * FRAME_SIZE + j] = value
		var controls: Variant = frame[FRAME_SIZE - 1]
		if not (_is_whole(controls) and controls >= 0 and controls <= ALL_CONTROLS):
			return null
	return replay


## Seconds into the run at which frame `index` was taken. The last frame is at the finish.
func _frame_time(index: int) -> float:
	if index >= frame_count() - 1:
		return time_ms / 1000.0
	return index * interval_ms / 1000.0


## Rounds to `decimals` and leaves off trailing zeros, as the backend writes numbers.
static func _number(value: float, decimals: int) -> String:
	var text := String.num(value, decimals)
	# Tiny negative values round to "-0" or "-0.0".
	return text.trim_prefix("-") if text.to_float() == 0.0 else text


static func _is_whole(value: Variant) -> bool:
	return (value is float or value is int) and value == floorf(value)
