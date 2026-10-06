extends RigidBody2D

const SPEED_MULTIPLIER := 15.0

@export var pin_joint_front: PinJoint2D
@export var pin_joint_back: PinJoint2D

## Torque applied to each wheel while accelerating or reversing.
@export var wheel_torque := 2500.0

## Top wheel spin in rad/s (wheel radius is ~5px, so 60 rad/s is ~300px/s).
@export var max_wheel_speed := 60.0

## Torque applied to the car body to tilt it forward/back.
@export var tilt_torque := 25000.0

## Loops while the level runs, faster and higher the faster the car goes.
@export var engine_sound: AudioStreamPlayer

## Car speed in px/s at which the engine sound reaches ENGINE_TOP_PITCH. Full
## throttle on flat ground gets the car to about this; boosts go beyond it.
const ENGINE_TOP_SPEED := 400.0
const ENGINE_IDLE_PITCH := 0.8
const ENGINE_TOP_PITCH := 2.0
const ENGINE_IDLE_DB := -8.0
const ENGINE_TOP_DB := -1.0
## How quickly the engine sound follows the car, per second.
const ENGINE_RESPONSE := 5.0

## Change in the body's speed (px/s) in a collision that makes a crash sound.
## Driving over bumps stays below it; ramming one or a hard landing does not.
const CRASH_IMPACT := 150.0
## The same for a hit on the roof, which makes a dong.
const ROOF_IMPACT := 100.0
## Impact at which those sounds are at full volume.
const LOUDEST_IMPACT := 600.0
## Shortest gap between two of those sounds, so one landing makes one sound.
const IMPACT_SOUND_GAP_MSEC := 300

var _wheel_front: RigidBody2D
var _wheel_back: RigidBody2D

var _initial_transform: Transform2D
var _initial_wheel_front_transform: Transform2D
var _initial_wheel_back_transform: Transform2D

# Held state of each control, updated from InputHandler signals.
var _right_held := false
var _left_held := false
var _up_held := false
var _down_held := false
var _boost_held := false

## Velocity before the latest physics step, to measure how hard a collision was.
var _velocity_before_step := Vector2.ZERO
var _last_impact_sound_msec := -IMPACT_SOUND_GAP_MSEC


func _ready() -> void:
	_wheel_front = pin_joint_front.get_node(pin_joint_front.node_b)
	_wheel_back = pin_joint_back.get_node(pin_joint_back.node_b)
	_initial_transform = global_transform
	_initial_wheel_front_transform = _wheel_front.global_transform
	_initial_wheel_back_transform = _wheel_back.global_transform

	# Connections to this node's methods are removed automatically when it's freed.
	InputHandler.move_right_just_pressed.connect(_on_move_right_just_pressed)
	InputHandler.move_right_released.connect(_on_move_right_released)
	InputHandler.move_left_just_pressed.connect(_on_move_left_just_pressed)
	InputHandler.move_left_released.connect(_on_move_left_released)
	InputHandler.move_up_just_pressed.connect(_on_move_up_just_pressed)
	InputHandler.move_up_released.connect(_on_move_up_released)
	InputHandler.move_down_just_pressed.connect(_on_move_down_just_pressed)
	InputHandler.move_down_released.connect(_on_move_down_released)
	InputHandler.boost_just_pressed.connect(_on_boost_just_pressed)
	InputHandler.boost_released.connect(_on_boost_released)
	InputHandler.interact_just_pressed.connect(_reset_position)

	# Report contacts, so hard hits can make a sound.
	contact_monitor = true
	max_contacts_reported = 4
	body_entered.connect(_on_body_entered)
	# A rev as the level starts, unless the trombone of a reset is still playing.
	if not Sfx.is_playing(Sfx.WAHWAH):
		Sfx.play(Sfx.REV)


func _on_move_right_just_pressed() -> void: _right_held = true
func _on_move_right_released() -> void: _right_held = false
func _on_move_left_just_pressed() -> void: _left_held = true
func _on_move_left_released() -> void: _left_held = false
func _on_move_up_just_pressed() -> void: _up_held = true
func _on_move_up_released() -> void: _up_held = false
func _on_move_down_just_pressed() -> void: _down_held = true
func _on_move_down_released() -> void: _down_held = false
func _on_boost_just_pressed() -> void:
	_boost_held = true
	Sfx.play(Sfx.WEEE)
func _on_boost_released() -> void: _boost_held = false


func _process(delta: float) -> void:
	var speed := clampf(linear_velocity.length() / ENGINE_TOP_SPEED, 0.0, 1.5)
	var pitch := lerpf(ENGINE_IDLE_PITCH, ENGINE_TOP_PITCH, speed)
	var volume := lerpf(ENGINE_IDLE_DB, ENGINE_TOP_DB, minf(speed, 1.0))
	if GameState.is_stopped:
		volume = -60.0 # The level is finished; the engine fades out.
	var weight := minf(1.0, delta * ENGINE_RESPONSE)
	engine_sound.pitch_scale = lerpf(engine_sound.pitch_scale, pitch, weight)
	engine_sound.volume_db = lerpf(engine_sound.volume_db, volume, weight)


func _physics_process(_delta: float) -> void:
	_velocity_before_step = linear_velocity
	var torque := wheel_torque
	var top_wheel_speed := max_wheel_speed

	# Handle Boost.
	if _boost_held:
		push(Vector2.RIGHT * SPEED_MULTIPLIER)

	# Up accelerates forward, down brakes and then reverses.
	# Positive angular velocity is clockwise, which rolls the car to the right.
	var throttle := (1.0 if _up_held else 0.0) - (1.0 if _down_held else 0.0)
	if throttle != 0:
		_drive_wheel(_wheel_front, throttle, torque, top_wheel_speed)
		_drive_wheel(_wheel_back, throttle, torque, top_wheel_speed)

	# Right tilts the car forward (nose down), left tilts it back (nose up).
	var tilt := (1.0 if _right_held else 0.0) - (1.0 if _left_held else 0.0)
	if tilt != 0:
		apply_torque(tilt * tilt_torque)


## Pushes the whole car: body and wheels share `impulse` by their mass, so all
## of it speeds up alike. Pushing only the body leaves the wheels behind and
## flips the car over them.
func push(impulse: Vector2) -> void:
	var total_mass := mass + _wheel_front.mass + _wheel_back.mass
	for body: RigidBody2D in [self, _wheel_front, _wheel_back]:
		body.apply_central_impulse(impulse * body.mass / total_mass)


static func _drive_wheel(wheel: RigidBody2D, throttle: float, torque: float, top_wheel_speed: float) -> void:
	# Stop adding torque once the wheel reaches top speed in the requested direction.
	if wheel.angular_velocity * throttle < top_wheel_speed:
		wheel.apply_torque(throttle * torque)


func _on_body_entered(body: Node) -> void:
	if body == _wheel_front or body == _wheel_back:
		return
	var impact := (_velocity_before_step - linear_velocity).length()
	# The car's up points downwards when it lands on its roof.
	var on_roof := -global_transform.y.normalized().y > 0.3
	if impact < (ROOF_IMPACT if on_roof else CRASH_IMPACT):
		return
	var now := Time.get_ticks_msec()
	if now - _last_impact_sound_msec < IMPACT_SOUND_GAP_MSEC:
		return
	_last_impact_sound_msec = now
	var volume := linear_to_db(clampf(impact / LOUDEST_IMPACT, 0.3, 1.0))
	Sfx.play(Sfx.DONG if on_roof else Sfx.CRASH, volume)


func _reset_position() -> void:
	Sfx.play(Sfx.WAHWAH)
	GameState.reset()
	get_tree().reload_current_scene()
