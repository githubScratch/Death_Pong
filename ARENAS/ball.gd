# Ball.gd - Modified to respond better to force changes
extends RigidBody2D

class_name Ball

# Properties
@export var min_speed: float = 200.0
@export var max_speed: float = 1000.0
var last_applied_force: Vector2 = Vector2.ZERO

@export var stretch_factor: float = 2.5  # How much the ball stretches
@export var min_velocity_for_stretch: float = 200.0  # Minimum velocity to start stretching
@export var max_stretch: float = 4.0  # Maximum stretch multiplier

var _original_scale: Vector2
var _velocity: Vector2 = Vector2.ZERO
var _previous_position: Vector2

@onready var wall_impact: AudioStreamPlayer2D = $"../wall_impact"
var audio_pool = []
@export var pool_size = 3
@export var min_velocity_for_sound = 50.0  # Minimum velocity to play sound

func _ready():
	add_to_group("ball")
	for i in range(pool_size):
		var player = AudioStreamPlayer.new()
		player.stream = wall_impact
		add_child(player)
		audio_pool.append(player)
		print("Created ", audio_pool.size(), " audio players")
	_original_scale = scale
	_previous_position = global_position
	
	# Physics setup
	contact_monitor = true
	max_contacts_reported = 4
	self.gravity_scale = gravity_scale
	self.linear_damp = linear_damp
	
	# Initial movement
	var initial_direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	apply_central_impulse(initial_direction * min_speed)
	
func _physics_process(_delta):
	
	_velocity = (global_position - _previous_position) / _delta
	_previous_position = global_position
	
	# Apply stretch effect based on velocity
	if _velocity.length() > min_velocity_for_stretch:
		# Normalize direction
		var direction = _velocity.normalized()
		
		# Calculate stretch along movement direction
		var stretch_amount = clamp(_velocity.length() * stretch_factor / 1000.0, 1.0, max_stretch)
		
		# Create a basis for the transformation
		var x_axis = direction
		var y_axis = Vector2(-direction.y, direction.x)  # Perpendicular to direction
		
		# Apply stretch - expand in direction of movement, compress in perpendicular direction
		var new_scale_x = _original_scale.x * stretch_amount
		var new_scale_y = _original_scale.y / sqrt(stretch_amount)  # Inverse square root for volume preservation
		
		# Update the scale and rotation
		scale = Vector2(new_scale_x, new_scale_y)
		rotation = direction.angle()
	else:
		# Reset to original scale when velocity is low
		scale = _original_scale
		rotation = 0

	# Cap maximum speed
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed


func apply_deflection(force_vector):
	# Store for debugging
	last_applied_force = force_vector
	print("Ball received force: ", force_vector.length())
	
	# Stop current movement
	linear_velocity = Vector2.ZERO
	
	# Apply the force directly
	apply_central_force(force_vector * 100)  # Multiply by 100 to amplify the effect
	
	# Alternative: Try impulse with higher value
	apply_central_impulse(force_vector)

	
	# Create visual effect
	create_impact_effect()

##debug this to ensure its working
func create_impact_effect():
	var original_color = modulate
	modulate = Color(0.2, 0.2, 0.2, 1.0)
	
	var tween = create_tween()
	tween.tween_property(self, "modulate", original_color, 0.4)

func _on_sfx_area_body_entered(body):  # Changed function name to match signal
	print("Collision detected with: ", body.name)
	print("Body type: ", body.get_class())
	
	if body is StaticBody2D and linear_velocity.length() > min_velocity_for_sound:
		# Play sound with volume based on impact velocity
		var impact_force = min(linear_velocity.length() / 1000.0, 1.0)
		play_collision_sound(impact_force)  # Pass the volume scale, not the audio player
	if body is RigidBody2D and linear_velocity.length() > min_velocity_for_sound:
		var impact_force = min(linear_velocity.length() / 1000.0, 1.0)
		#play_collision_sound(impact_force)  # Pass the volume scale, not the audio player
		if body.is_in_group("brick") and is_instance_valid(body):
			body.hit()
		
func play_collision_sound(volume_scale = 1.0):
	print("Bwomp!")
	wall_impact.pitch_scale = randf_range(0.9, 1.1)
	wall_impact.play()
	print("Audio pool size: ", audio_pool.size())  # Should be > 0
	for player in audio_pool:
		if not player.playing:
			player.pitch_scale = randf_range(0.9, 1.1)
			player.volume_db = linear_to_db(volume_scale)
			player.play()
			print("Bwomp!2")
			wall_impact.pitch_scale = randf_range(0.9, 1.1)
			wall_impact.play()
			return
	
	# If all players are busy, use the first one
	audio_pool[0].pitch_scale = randf_range(0.9, 1.1)
	audio_pool[0].volume_db = linear_to_db(volume_scale)
	audio_pool[0].play()
