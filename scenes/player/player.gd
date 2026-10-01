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


func _on_move_right_just_pressed() -> void: _right_held = true
func _on_move_right_released() -> void: _right_held = false
func _on_move_left_just_pressed() -> void: _left_held = true
func _on_move_left_released() -> void: _left_held = false
func _on_move_up_just_pressed() -> void: _up_held = true
func _on_move_up_released() -> void: _up_held = false
func _on_move_down_just_pressed() -> void: _down_held = true
func _on_move_down_released() -> void: _down_held = false
func _on_boost_just_pressed() -> void: _boost_held = true
func _on_boost_released() -> void: _boost_held = false


func _physics_process(_delta: float) -> void:
	var torque := wheel_torque
	var top_wheel_speed := max_wheel_speed

	# Handle Boost.
	if _boost_held:
		apply_impulse(Vector2.RIGHT * SPEED_MULTIPLIER)

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


static func _drive_wheel(wheel: RigidBody2D, throttle: float, torque: float, top_wheel_speed: float) -> void:
	# Stop adding torque once the wheel reaches top speed in the requested direction.
	if wheel.angular_velocity * throttle < top_wheel_speed:
		wheel.apply_torque(throttle * torque)


func _reset_position() -> void:
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_wheel_front.linear_velocity = Vector2.ZERO
	_wheel_front.angular_velocity = 0.0
	_wheel_back.linear_velocity = Vector2.ZERO
	_wheel_back.angular_velocity = 0.0
	global_transform = _initial_transform
	_wheel_front.global_transform = _initial_wheel_front_transform
	_wheel_back.global_transform = _initial_wheel_back_transform
	GameState.reset()
