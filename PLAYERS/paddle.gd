extends StaticBody2D

# Movement speed
@export var speed = 300

# References
var ball = null
var screen_size
var paddle_height
@export var deflection_force: float = 1200.0
@onready var deflect_sfx: AudioStreamPlayer2D = $"../../deflect_SFX"
@onready var paddle: AnimationPlayer = $"../../Paddle"


func _ready():
	screen_size = get_viewport_rect().size
	paddle_height = $CollisionShape2D.shape.size.y # Adjust based on your paddle's collision shape

func _physics_process(delta):
	# Find a ball in the "ball" group
	var balls = get_tree().get_nodes_in_group("ball")
	
	# If there's at least one ball, track it
	if balls.size() > 0:
		ball = balls[0]
		track_ball(delta)
	else:
		# No ball found, return to center
		move_to_center(delta)

func track_ball(delta):
	if ball != null and is_instance_valid(ball):
		# Simply move toward the ball's y position
		var target_y = ball.position.y
		
		# Determine direction
		var direction = 0
		if abs(position.y - target_y) > 5: # Small threshold to prevent jitter
			direction = 1 if target_y > position.y else -1
		
		# Move paddle
		position.y += direction * speed * delta
		
		# Clamp to keep paddle on screen
		position.y = clamp(position.y, paddle_height/2, screen_size.y - paddle_height/2)

func move_to_center(delta):
	# Move toward the center when no ball is found
	var center_y = screen_size.y / 2
	
	var direction = 0
	if abs(position.y - center_y) > 5:
		direction = 1 if center_y > position.y else -1
	
	position.y += direction * speed * delta
	position.y = clamp(position.y, paddle_height/2, screen_size.y - paddle_height/2)


func _on_paddle_deflection_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		var direction = (body.global_position - global_position).normalized()
		deflect_ball(body, direction)

func deflect_ball(ball, direction):
	if ball is RigidBody2D:
		# Calculate a velocity based on the deflection force
		var new_velocity = direction * deflection_force
		# Directly set the ball's velocity
		ball.linear_velocity = new_velocity
		deflect_sfx.pitch_scale = randf_range(0.9, 1.1)
		deflect_sfx.play()
		paddle.stop()
		paddle.play("Deflect")
		#if speed <= 1000:
			#speed += 10
		#if deflection_force <= 3600:
			#deflection_force += 1200
