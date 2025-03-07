# DeflectionShield.gd - Debug version to find why force isn't working
extends Area2D

class_name DeflectionShield

# How powerful the deflection force should be
@export var deflection_force: float = 600.0

# Add a label to display debug info
var debug_label: Label

func _ready():
	# Create debug label
	#debug_label = Label.new()
	#debug_label.position = Vector2(0, -50)
	#debug_label.text = "Force: " + str(deflection_force)
	#add_child(debug_label)
	pass

func _on_body_entered(body):
	# Check if the colliding body is the ball
	if body.is_in_group("ball"):
		# Print debug info
		print("Shield hit by ball! Force: ", deflection_force)
		
		# Calculate direction from shield center to the ball
		var direction = (body.global_position - global_position).normalized()
		print("Direction vector: ", direction)
		
		# Apply the deflection force to the ball
		deflect_ball(body, direction)

func deflect_ball(ball, direction):
	# Print debug info
	print("Applying force: ", deflection_force, " in direction: ", direction)
		# Use apply_force instead of apply_impulse
	if ball is RigidBody2D:
# Calculate a velocity based on the deflection force
		var new_velocity = direction * deflection_force
# Directly set the ball's velocity
		ball.linear_velocity = new_velocity
		print("Set velocity directly: ", new_velocity.length())
		
		# Update debug label
		#debug_label.text = "Hit! Force: " + str(deflection_force)
		#debug_label.modulate = Color.GREEN
	else:
		print("Ball is not a RigidBody2D!")
