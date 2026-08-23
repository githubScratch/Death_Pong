extends Area2D

class_name DeflectionShield

# How powerful the deflection force should be
@export var deflection_force: float = 1200.0
@onready var deflect_sfx: AudioStreamPlayer2D = $"../deflect_SFX"
@onready var animation_player: AnimationPlayer = $"../AnimationPlayer"

var _freeze_queue = []
var _is_processing_freeze = false


func _ready():
	pass

func _on_body_entered(body):
	# Check if the colliding body is the ball
	if body.is_in_group("ball"):
		print("Shield hit by ball! Force: ", deflection_force)
		
		# Calculate direction from shield center to the ball
		var direction = (body.global_position - global_position).normalized()
		print("Direction vector: ", direction)
		
		# Apply the deflection force to the ball
		deflect_ball(body, direction)

func deflect_ball(ball, direction):
	print("Applying force: ", deflection_force, " in direction: ", direction)
	# Use apply_force instead of apply_impulse
	if ball is RigidBody2D:
		#####freeze_frame(0.1)
		# Calculate a velocity based on the deflection force
		var new_velocity = direction * deflection_force
		# Directly set the ball's velocity
		ball.linear_velocity = new_velocity
		print("Set velocity directly: ", new_velocity.length())
		deflect_sfx.pitch_scale = randf_range(0.9, 1.1)
		deflect_sfx.play()
		animation_player.stop()
		animation_player.play("deflect")


func freeze_frame(duration := 0.1):
	# Add this freeze request to the queue
	_freeze_queue.append(duration)
	
	# If we're not already processing a freeze, start processing
	if not _is_processing_freeze:
		_process_next_freeze()

func _process_next_freeze():
	# If queue is empty, nothing to do
	if _freeze_queue.size() == 0:
		_is_processing_freeze = false
		return
	
	# Mark as processing
	_is_processing_freeze = true
	
	# Get next duration from queue
	var duration = _freeze_queue.pop_front()
	
	# Store original time scale
	var original_time_scale = Engine.time_scale
	
	# Set time scale to almost zero 
	Engine.time_scale = 0.1
	
	# Wait for the specified duration using real time
	var start_time = Time.get_ticks_msec()
	var end_time = start_time + int(duration * 1000)
	
	while Time.get_ticks_msec() < end_time:
		await get_tree().process_frame
	
	# Always reset time scale to normal
	Engine.time_scale = 1.0
	
	# Process next freeze in queue if any
	_process_next_freeze()
