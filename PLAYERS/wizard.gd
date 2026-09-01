extends CharacterBody2D

## Generic wizard chassis - the movement/physics/casting "core" every
## seat/class combination shares. This replaces wizard_1.gd/wizard_2.gd/
## wizard_3.gd/wizard_4.gd, which were four copy-pasted scripts differing
## only in which player's input actions they read.
##
## Two independent dials, both meant to be set by whatever spawns this
## scene:
##  - seat: which physical player's input this body reads (1-4). Currently
##    set once per placed instance in each arena scene, same way `position`
##    already is. Once character select exists, whatever assigns seats will
##    set this the same way, just at runtime instead of in the editor.
##  - wizard_class: a WizardClass resource - which color/sprite/ability kit
##    this body is wearing. Also seat-independent: any class can go on any
##    seat, which is the whole point of splitting this out.

## Set on the parent (wizard_seat.gd), not here - see that file for why.
## Copied into these plain vars in _ready() so the rest of this script can
## keep reading `seat`/`wizard_class` exactly as before.
var seat: int = 1
var wizard_class: WizardClass

var SPEED = 400.0
var INIT_SPEED = 400.0
var DASH = 1400.0
var JUMP_VELOCITY = -800.0
var DBL_JUMP_VELOCITY = -700
var DIVE_VELOCITY = 1400

@onready var shape: CollisionShape2D = $shape
@onready var sprite: AnimatedSprite2D = $sprite

@onready var jump: AudioStreamPlayer2D = $"../jump"
@onready var spell: AudioStreamPlayer2D = $"../spell"
@onready var dash: AudioStreamPlayer2D = $"../dash"
@onready var land: AudioStreamPlayer2D = $"../land"

var current_instance: Node = null
var hit_the_ground = false
var fading_instances = []
var max_fall_speed = 6000

# Cached per-seat action names, so the hot path in _physics_process isn't
# rebuilding strings ("p%d_up" % seat) every frame.
var _action_up: String
var _action_down: String
var _action_left: String
var _action_right: String



func _ready() -> void:
	var seat_node := get_parent()
	var seat_value = seat_node.get("seat")
	if seat_value != null:
		seat = seat_value
	var class_value = seat_node.get("wizard_class")
	if class_value != null:
		wizard_class = class_value

	# Character select (MENUS/character_select.gd) always keeps a chosen
	# class for every seat in GameSettings, defaulting to the same per-seat
	# class every arena scene already hardcoded before that screen existed -
	# so preferring it here, when present, is safe even for a scene opened
	# directly (e.g. in the editor) without ever visiting character select.
	if seat >= 1 and seat <= GameSettings.selected_classes.size():
		var chosen = GameSettings.selected_classes[seat - 1]
		if chosen != null:
			wizard_class = chosen

	_action_up = InputRemap.action_for(seat, "up")
	_action_down = InputRemap.action_for(seat, "down")
	_action_left = InputRemap.action_for(seat, "left")
	_action_right = InputRemap.action_for(seat, "right")
	_apply_class()


## Applies the assigned WizardClass's cosmetic/shield pieces onto this
## chassis. Safe to call again later - e.g. a future character-select
## "live preview", or mid-game class changes if that's ever a thing.
func _apply_class() -> void:
	if wizard_class == null:
		push_warning("Wizard (seat %d) has no wizard_class assigned." % seat)
		return
	if wizard_class.sprite_sheet:
		sprite.sprite_frames = _build_sprite_frames(wizard_class.sprite_sheet)
		sprite.play("default")
	if wizard_class.abilities.is_empty():
		push_warning("Wizard (seat %d)'s class '%s' has no abilities assigned." % [seat, wizard_class.display_name])


## Returns the ability this wizard casts right now. Called fresh on every
## cast rather than cached once, on purpose - that's the one seam a future
## Wild Mage (reroll a random ability every cast) or a power-up-unlock mode
## (grow the available pool at runtime) needs to hook. Neither would have
## to touch anything else in this file: override/extend this method alone.
## For every class today, that's just "the class's one ability".
func _current_ability() -> WizardAbility:
	if wizard_class == null or wizard_class.abilities.is_empty():
		return null
	return wizard_class.abilities[0]


## Every class's sprite sheet uses the same layout: a 2x2 grid of 192x192
## frames, animated as one 4-frame "default" loop. Building this in code
## instead of baking a SpriteFrames sub-resource into the scene per class is
## what lets one wizard.tscn serve every class - swapping the look is just
## swapping which texture these regions are cut from.
func _build_sprite_frames(sheet: Texture2D) -> SpriteFrames:
	var frames := SpriteFrames.new()
	frames.set_animation_loop("default", true)
	frames.set_animation_speed("default", 6.0)
	var regions := [
		Rect2(0, 0, 192, 192),
		Rect2(192, 0, 192, 192),
		Rect2(0, 192, 192, 192),
		Rect2(192, 192, 192, 192),
	]
	for region in regions:
		var atlas := AtlasTexture.new()
		atlas.atlas = sheet
		atlas.region = region
		frames.add_frame("default", atlas)
	return frames


### CHASSIS - identical for every seat/class, ported as-is from the old
### wizard_N.gd scripts with p{N}_* swapped for the cached _action_* names.

func _physics_process(delta: float) -> void:

	# Add the gravity and stretch.
	if not is_on_floor():
		velocity += get_gravity() * 2 * delta
		if velocity.y > max_fall_speed:
			velocity.y = max_fall_speed
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
	if Input.is_action_just_pressed(_action_up):
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
	if Input.is_action_just_pressed(_action_down):
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
	var direction := Input.get_axis(_action_left, _action_right)
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
	var ability := _current_ability()
	if ability != null and is_instance_valid(ability.shield_scene):
		var instance = ability.shield_scene.instantiate()
		instance.global_position = global_position
		get_tree().current_scene.add_child(instance)
		current_instance = instance

	# Clean up any stale instances in the fading list (run occasionally)
	if fading_instances.size() > 10 or randf() < 0.1:
		for old_instance in fading_instances.duplicate():
			if !is_instance_valid(old_instance):
				fading_instances.erase(old_instance)
