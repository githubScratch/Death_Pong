# Ball.gd - Modified to respond better to force changes
extends RigidBody2D

class_name Ball

# Properties
@export var min_speed: float = 200.0
@export var max_speed: float = 800.0


# Debug variables to track forces
var last_applied_force: Vector2 = Vector2.ZERO
var debug_label: Label

func _ready():
	# Add to ball group
	add_to_group("ball")
	
	# Physics setup
	contact_monitor = true
	max_contacts_reported = 4
	self.gravity_scale = gravity_scale
	self.linear_damp = linear_damp
	
	# Create physics material
	#var physics_material = PhysicsMaterial.new()
	#physics_material.bounce = 0.7
	#physics_material.friction = 0.2
	#self.physics_material_override = physics_material
	
	# Add debug label
	#debug_label = Label.new()
	#debug_label.position = Vector2(-20, -30)
	#add_child(debug_label)
	
	# Initial movement
	var initial_direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	apply_central_impulse(initial_direction * min_speed)

func _physics_process(delta):
	# Update debug label
	#debug_label.text = "Speed: " + str(int(linear_velocity.length()))
	#debug_label.modulate = Color.WHITE
	
	# Cap maximum speed
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed

# This method is called from DeflectionShield
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
	
	# Update debug label
	#debug_label.text = "Force: " + str(int(force_vector.length()))
	#debug_label.modulate = Color.RED
	
	# Create visual effect
	create_impact_effect()

func create_impact_effect():
	var original_color = modulate
	modulate = Color(2.0, 2.0, 2.0, 1.0)
	
	var tween = create_tween()
	tween.tween_property(self, "modulate", original_color, 0.4)
