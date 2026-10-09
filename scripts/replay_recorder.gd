class_name ReplayRecorder
extends Node
## Records the car it belongs to into a ReplayData while the level runs.
## The finish ends the recording with finish().

@export var car: Player
@export var front_wheel: Node2D
@export var rear_wheel: Node2D

var replay := ReplayData.new()
# When the next frame is due, in GameState.time_elapsed. Following the run's
# clock rather than the physics ticks keeps the frames in step with its time.
var _next_frame_seconds := 0.0
var _is_finished := false
# Rotations of the car and its wheels, kept unwrapped: a full turn adds TAU
# instead of jumping back to 0, so frames can be interpolated.
var _rotations := PackedFloat64Array([0.0, 0.0, 0.0])
var _last_rotations := PackedFloat64Array()


func _ready() -> void:
	_last_rotations = _current_rotations()
	_rotations = _last_rotations.duplicate()


func _physics_process(_delta: float) -> void:
	if _is_finished or GameState.is_stopped:
		return
	_track_rotations()
	while GameState.time_elapsed >= _next_frame_seconds and not replay.is_cut_off:
		_add_frame()


## Ends the recording as the car crosses the finish, `time_ms` into the run, and returns it.
func finish(time_ms: int) -> ReplayData:
	if _is_finished:
		return replay
	_is_finished = true
	_track_rotations()
	# The frames due up to the finish, then the finish itself.
	while _next_frame_seconds < time_ms / 1000.0 and not replay.is_cut_off:
		_add_frame()
	replay.add_frame(car.global_position, _rotations[0], _rotations[1], _rotations[2], car.held_controls())
	replay.time_ms = time_ms
	replay.recorded_at = Time.get_datetime_string_from_system(true) + "Z"
	return replay


func _add_frame() -> void:
	replay.add_frame(car.global_position, _rotations[0], _rotations[1], _rotations[2], car.held_controls())
	_next_frame_seconds += replay.interval_ms / 1000.0


func _track_rotations() -> void:
	var current := _current_rotations()
	for i in current.size():
		_rotations[i] += angle_difference(_last_rotations[i], current[i])
	_last_rotations = current


func _current_rotations() -> PackedFloat64Array:
	return PackedFloat64Array([car.global_rotation, front_wheel.global_rotation, rear_wheel.global_rotation])
