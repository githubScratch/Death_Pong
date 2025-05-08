extends StaticBody2D

@export var speed = 250
@export var deflection_force: float = 1200.0
@export var friction: float = 1.0
@export var reaction_speed: float = 100.0 # How quickly the paddle reacts (higher = faster response)
@export var max_velocity: float = 400.0

@onready var deflect_sfx: AudioStreamPlayer2D = $"../../deflect_SFX"
@onready var paddle: AnimationPlayer = $Paddle

var ball = null
var screen_size
var paddle_height
var velocity := 0.0

func _ready():
	screen_size = get_viewport_rect().size
	paddle_height = $CollisionShape2D.shape.size.y

func _physics_process(delta):
	var balls = get_tree().get_nodes_in_group("ball")
	
	if balls.size() > 0:
		ball = balls[0]
		track_ball(delta)
	else:
		move_to_center(delta)

func track_ball(delta):
	if ball != null and is_instance_valid(ball):
		var target_y = ball.position.y
		var distance = (ball.position.y - position.y) + 100
		
		# Apply acceleration toward the ball
		velocity += distance * reaction_speed * delta

		# Apply friction to slow down over time
		velocity = clamp(velocity, -max_velocity, max_velocity)
		velocity = lerp(velocity, 0.0, delta * friction)

		position.y += velocity * delta
		clamp(position.y, 100.0, 550.0)

func move_to_center(delta):
	var center_y = screen_size.y / 2
	var distance = center_y - position.y

	velocity += distance * reaction_speed * delta
	velocity = clamp(velocity, -max_velocity, max_velocity)
	velocity = lerp(velocity, 0.0, delta * friction)

	position.y += velocity * delta
	position.y = clamp(position.y, paddle_height / 2, screen_size.y - paddle_height / 2)

func _on_paddle_deflection_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		var offset = body.global_position - global_position
		offset.x *= 3.0  
		var direction = offset.normalized()
		deflect_ball(body, direction)

func deflect_ball(ball, direction):
	if ball is RigidBody2D:
		ball.linear_velocity = direction * deflection_force
		deflect_sfx.pitch_scale = randf_range(0.9, 1.1)
		deflect_sfx.play()
		paddle.stop()
		paddle.play("Deflect")
