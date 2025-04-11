# DeflectionShield.gd - Debug version to find why force isn't working
extends Area2D

class_name DeflectionShield

# How powerful the deflection force should be
@export var deflection_force: float = 1200.0
@onready var deflect_sfx: AudioStreamPlayer2D = $"../deflect_SFX"
@onready var animation_player: AnimationPlayer = $"../AnimatedSprite2D/AnimationPlayer"

# Add a label to display debug info
var debug_label: Label

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
		# Calculate a velocity based on the deflection force
		var new_velocity = direction * deflection_force
		# Directly set the ball's velocity
		ball.linear_velocity = new_velocity
		print("Set velocity directly: ", new_velocity.length())
		deflect_sfx.pitch_scale = randf_range(0.9, 1.1)
		deflect_sfx.play()
		animation_player.stop()
		animation_player.play("deflect")
