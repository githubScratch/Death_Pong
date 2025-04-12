extends CharacterBody2D


var SPEED = 400.0
var INIT_SPEED = 400.0
var DASH = 1400.0
var JUMP_VELOCITY = -800.0
var DBL_JUMP_VELOCITY = -700
var DIVE_VELOCITY = 1400

@onready var shape: CollisionShape2D = $shape
@onready var sprite: AnimatedSprite2D = $sprite
@export var instance_scene: PackedScene

@onready var jump: AudioStreamPlayer2D = $"../jump"
@onready var spell: AudioStreamPlayer2D = $"../spell"
@onready var dash: AudioStreamPlayer2D = $"../dash"
@onready var land: AudioStreamPlayer2D = $"../land"


var current_instance: Node = null
var hit_the_ground = false
var fading_instances = []

### WIZARD 1 ###

func _physics_process(delta: float) -> void:
	
	# Add the gravity and stretch.
	if not is_on_floor():
		velocity += get_gravity() * 2 * delta
		if abs(velocity.y) > 350.0:
			sprite.scale.y = 0.4
			sprite.scale.x = 0.25
			hit_the_ground = false
	if not hit_the_ground and is_on_floor():
		hit_the_ground = true
		land.pitch_scale = randf_range(0.9, 1.1)
		land.play()
		sprite.scale.y = 0.15
		sprite.scale.x = 0.6
		
	#Reset Stretch over time
	sprite.scale.x = lerpf(sprite.scale.x, 0.333, 1 - pow(0.01, delta))
	sprite.scale.y = lerpf(sprite.scale.y, 0.333, 1 - pow(0.01, delta))
	shape.scale.x = lerpf(sprite.scale.x, 1, 1 - pow(0.01, delta))
	shape.scale.y = lerpf(sprite.scale.y, 1, 1 - pow(0.01, delta))
	
	# Handle jump.
	if Input.is_action_just_pressed("up1"):
		create_new_instance()
		if not is_on_floor():
			velocity.y = DBL_JUMP_VELOCITY
			spell.pitch_scale = randf_range(0.9, 1.1)
			spell.play()
		if is_on_floor():
			velocity.y = JUMP_VELOCITY
			spell.pitch_scale = randf_range(0.9, 1.1)
			spell.play()
			jump.pitch_scale = randf_range(0.9, 1.1)
			jump.play()
	
	# Handle dive.
	if Input.is_action_just_pressed("down1"):
		if not is_on_floor():
			velocity.y = DIVE_VELOCITY
			dash.pitch_scale = randf_range(0.9, 1.1)
			dash.play()
		if is_on_floor():
			dash.pitch_scale = randf_range(0.9, 1.1)
			dash.play()
			SPEED = DASH
			sprite.scale.y = 0.15
			sprite.scale.x = 0.6
			#set_collision_layer(2)
			await get_tree().create_timer(0.1).timeout
			#set_collision_layer(1)
			SPEED = INIT_SPEED

	
	# Get the input direction and handle the movement/deceleration.
	var direction := Input.get_axis("left1", "right1")
	if direction:
		velocity.x = direction * SPEED
		if direction > 0:
			sprite.flip_h = false  # Face right
		elif direction < 0:
			sprite.flip_h = true   # Face left
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)

	move_and_slide()

func create_new_instance():
	# If there's a current instance, start its fade animation
	if is_instance_valid(current_instance):
		# Get reference to animation player (assuming it's a direct child of the instance)
		var anim_player = current_instance.get_node_or_null("AnimationPlayer")
		
		if is_instance_valid(anim_player) and anim_player.has_animation("fade"):
			# Track this instance as fading
			fading_instances.append(current_instance)
			# Play fade animation
			anim_player.play("fade")
		else:
			# No animation player or animation, just queue_free
			current_instance.queue_free()
	
	# Reset current instance reference before creating new one
	current_instance = null
	
	# Immediately create new instance without delay
	if is_instance_valid(instance_scene):
		var instance = instance_scene.instantiate()
		instance.global_position = global_position
		get_tree().current_scene.add_child(instance)
		current_instance = instance
	
	# Clean up any stale instances in the fading list (run occasionally)
	if fading_instances.size() > 10 or randf() < 0.1:
		for old_instance in fading_instances.duplicate():
			if !is_instance_valid(old_instance):
				fading_instances.erase(old_instance)
