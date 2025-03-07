extends CharacterBody2D


var SPEED = 400.0
var INIT_SPEED = 400.0
var DASH = 1400.0
var JUMP_VELOCITY = -800.0
var DBL_JUMP_VELOCITY = -600
var DIVE_VELOCITY = 1400

@export var instance_scene: PackedScene
var current_instance: Node = null

### WIZARD 1 ###

func _physics_process(delta: float) -> void:
	# Add the gravity.
	if not is_on_floor():
		velocity += get_gravity() * 2 * delta

	# Handle jump.
	if Input.is_action_just_pressed("up1"):
		create_new_instance()
		if not is_on_floor():
			velocity.y = DBL_JUMP_VELOCITY
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
	
	# Handle dive.
	if Input.is_action_just_pressed("down1"):
		if not is_on_floor():
			velocity.y = DIVE_VELOCITY
		if is_on_floor():
			SPEED = DASH
			await get_tree().create_timer(0.1).timeout
			SPEED = INIT_SPEED

	
	# Get the input direction and handle the movement/deceleration.
	# As good practice, you should replace UI actions with custom gameplay actions.
	var direction := Input.get_axis("left1", "right1")
	if direction:
		velocity.x = direction * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

func create_new_instance():
	# First, remove any existing instance
	if is_instance_valid(current_instance):
		current_instance.queue_free()
		current_instance = null
	
	# Check if scene is assigned using is_instance_valid
	if is_instance_valid(instance_scene):
		var instance = instance_scene.instantiate()
		instance.global_position = global_position
		get_tree().current_scene.add_child(instance)
		current_instance = instance
