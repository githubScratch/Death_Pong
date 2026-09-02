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

## How many successful shield deflections this wizard has banked so far -
## core, shared per-wizard state every class's shield reports into (see
## _on_shield_deflected() and DeflectionShield.deflected in
## PLAYERS/deflection_shield.gd), even though only some classes' abilities
## currently spend it (see GrowthAbility). Accumulates for the whole match -
## nothing resets it today.
var strikes: int = 0

## Hold-to-grow state (see _update_growth_channel()) - only meaningful for a
## class whose ability is a GrowthAbility, but lives here rather than on the
## ability resource since it's about *this wizard's* current hold, not the
## shared/cached ability data itself.
var _is_channeling: bool = false
var _channel_locked_out: bool = false
var _channel_tier: int = 0
var _channel_hold_time: float = 0.0
var _shield_scale_tween: Tween

## Seconds Up has been continuously held while otherwise eligible to grow,
## but not yet committed to an actual channel - see _update_growth_channel().
## Reset to 0 the moment Up is released or eligibility is lost.
var _candidate_hold_time: float = 0.0

## Seconds left in the visual "stutter" pause right after a tier lands - see
## _update_growth_channel().
var _channel_stutter_remaining: float = 0.0

## True once a channel has hit ability.post_channel_hold_time's grace period
## because it can no longer grow (maxed out, or out of strikes) - see
## _update_growth_channel(). _channel_grace_remaining counts that grace
## period down to 0, at which point the channel is forced to end.
var _channel_growth_exhausted: bool = false
var _channel_grace_remaining: float = 0.0

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
	_update_growth_channel(delta)

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

	# Handle jump. The cast always happens on press. The jump impulse always
	# fires too, even for a class whose ability grows on hold - a channel
	# never touches velocity until it's held past ability.hold_confirm_time
	# (see _update_growth_channel()), which is well past the one-or-two-frame
	# span a plain tap occupies, so a tap always jumps normally and only a
	# hold that survives the confirm window goes on to hover instead.
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
	if Input.is_action_just_pressed(_action_down) and not _is_channeling:
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

	# Hold-to-grow hovers in place - whatever gravity/jump/dive/movement
	# code above just computed for this frame gets overridden here, every
	# frame, for as long as the channel is active. Gravity still technically
	# accumulates into velocity.y above while this is true, but since it's
	# zeroed again right here before move_and_slide(), it never actually
	# moves the wizard - each frame effectively starts fresh.
	if _is_channeling:
		velocity = Vector2.ZERO

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
		_connect_shield_deflected(instance)

	# Clean up any stale instances in the fading list (run occasionally)
	if fading_instances.size() > 10 or randf() < 0.1:
		for old_instance in fading_instances.duplicate():
			if !is_instance_valid(old_instance):
				fading_instances.erase(old_instance)


## Every class's shield reports its own successful deflections back here via
## a `deflected` signal on DeflectionShield (PLAYERS/deflection_shield.gd) -
## strikes are core wizard/shield infrastructure now, not something specific
## to whichever class currently knows what to do with them. The signal
## lives on the shield's Area2D child, not the scene root instantiate()
## hands back, so it has to be looked up first.
func _connect_shield_deflected(instance: Node) -> void:
	var shield := instance.get_node_or_null("Area2D")
	if shield != null and shield.has_signal("deflected"):
		shield.deflected.connect(_on_shield_deflected)
	else:
		# TEMP DEBUG - remove once strikes are confirmed working. If this
		# ever prints, the shield's Area2D child either wasn't found or
		# doesn't have the `deflected` signal, so strikes for this cast
		# can't be counted at all.
		print("[DEBUG seat %d] could not find a deflectable Area2D on this shield instance - strikes will not count this cast" % seat)

func _on_shield_deflected() -> void:
	strikes += 1
	var cap := _max_banked_strikes(_current_ability())
	if cap >= 0 and strikes > cap:
		strikes = cap
	# TEMP DEBUG - remove once strikes are confirmed working.
	print("[DEBUG seat %d] strike banked - strikes now %d" % [seat, strikes])


## The most strikes it's ever useful to have banked at once for the given
## ability, or -1 if that ability doesn't define a ceiling (i.e. isn't a
## StrikeScaledAbility) - past ability.max_strikes, banking further strikes
## couldn't buy anything more for THIS ability, so there's no reason to let
## the count climb indefinitely. Non-scaled classes are uncapped for now
## since nothing they have yet spends strikes at all.
func _max_banked_strikes(ability: WizardAbility) -> int:
	var scaled_ability := ability as StrikeScaledAbility
	if scaled_ability == null:
		return -1
	return scaled_ability.max_strikes


## Hold-to-grow: gates in once strikes >= ability.strikes_per_tier, then
## grows current_instance's scale one step through ability.growth_tier_scales()
## at a time, one step per growth_duration_per_tier seconds Up stays
## continuously held. Every step is PAID FOR THE INSTANT IT STARTS, not when
## it finishes - see _try_pay_next_growth_step() - so the player never gets
## to see (even briefly) growth they can't actually afford; if a step can't
## be paid for, the channel ends right there instead of previewing it. Runs
## every physics frame regardless of class - it's a no-op unless the current
## ability is a GrowthAbility, so it costs nothing for classes that don't
## use it (and their WizardAbility resources don't carry any of these fields
## at all - see GrowthAbility for why that split exists).
func _update_growth_channel(delta: float) -> void:
	var up_held := Input.is_action_pressed(_action_up)

	# TEMP DEBUG - remove once strikes/growth are confirmed working. Prints
	# once per press (not every held frame) so it's readable: which class
	# you're actually wearing, whether that class's ability has growth
	# turned on at all, how many strikes are currently banked, and whether
	# there's a valid shield instance to grow.
	if Input.is_action_just_pressed(_action_up):
		var dbg_ability := _current_ability()
		print("[DEBUG seat %d] Up pressed - class=%s ability=%s is_growth_ability=%s strikes=%d current_instance_valid=%s" % [
			seat,
			wizard_class.display_name if wizard_class else "null",
			dbg_ability.display_name if dbg_ability else "null",
			dbg_ability is GrowthAbility,
			strikes,
			is_instance_valid(current_instance),
		])

	if not up_held:
		_channel_locked_out = false
		_candidate_hold_time = 0.0
		if _is_channeling:
			_end_growth_channel()
		return

	var ability := _current_ability() as GrowthAbility
	var can_grow := ability != null and is_instance_valid(current_instance)
	if not can_grow or _channel_locked_out:
		_candidate_hold_time = 0.0
		if _is_channeling:
			_end_growth_channel()
		return

	if not _is_channeling:
		# Not gated in yet - holding Up just stays the normal cast/jump
		# handled elsewhere in _physics_process(), nothing more happens.
		if strikes < ability.strikes_per_tier:
			_candidate_hold_time = 0.0
			return

		# Don't commit to a channel - and don't touch velocity - until Up
		# has been held for hold_confirm_time. A plain jump tap only ever
		# lasts a frame or two of _physics_process, well short of this, so
		# waiting reliably tells a real hold apart from a tap. This window
		# is a pure safety buffer and isn't counted toward growth - the
		# first tier's own growth_duration_per_tier starts fresh below, the
		# instant the channel actually commits.
		_candidate_hold_time += delta
		if _candidate_hold_time < ability.hold_confirm_time:
			return

		_is_channeling = true
		_channel_tier = 0
		_channel_hold_time = 0.0
		_channel_stutter_remaining = 0.0
		_channel_growth_exhausted = false
		_channel_grace_remaining = 0.0
		_candidate_hold_time = 0.0
		if _shield_scale_tween:
			_shield_scale_tween.kill()
		# Pay for the very first step (base -> tier 1) right now, before any
		# of it is shown - same rule every later step follows below.
		strikes -= ability.strikes_per_tier
		# TEMP DEBUG - remove once tier costs are confirmed working.
		print("[DEBUG seat %d] channel committed - paid %d strikes for tier 1, %d remain" % [seat, ability.strikes_per_tier, strikes])
	elif _channel_growth_exhausted:
		# Can't grow any further (maxed out, or out of strikes for the next
		# tier) - keep hovering at whatever scale was last reached for
		# ability.post_channel_hold_time as a grace period, then force out.
		# 0 means no grace at all: forced out the very next frame.
		_channel_grace_remaining -= delta
		if _channel_grace_remaining <= 0.0:
			# TEMP DEBUG - remove once tier costs are confirmed working.
			print("[DEBUG seat %d] post-channel grace expired - snapping back" % seat)
			_end_growth_channel()
			_channel_locked_out = true
			return
	elif _channel_stutter_remaining > 0.0:
		# Briefly freeze visual progress right after a tier lands, so each
		# strikes_per_tier chunk spent reads as its own distinct "tick"
		# instead of blurring into one continuous grow.
		_channel_stutter_remaining = maxf(_channel_stutter_remaining - delta, 0.0)
		if _channel_stutter_remaining <= 0.0 and not _try_pay_next_growth_step(ability):
			# Nothing left to buy (or couldn't afford it) - don't end
			# outright, hand off to the grace period above instead.
			_channel_growth_exhausted = true
			_channel_grace_remaining = ability.post_channel_hold_time
			if _channel_grace_remaining <= 0.0:
				_end_growth_channel()
				_channel_locked_out = true
				return
	else:
		_channel_hold_time += delta
		if _channel_hold_time >= ability.growth_duration_per_tier:
			# This step is fully grown into and already paid for - land on
			# it, then pause briefly before trying to pay for the next one.
			_channel_tier += 1
			_channel_hold_time = 0.0
			_channel_stutter_remaining = ability.tier_stutter_time
			# TEMP DEBUG - remove once tier costs are confirmed working.
			print("[DEBUG seat %d] tier -> %d (scale %.2f) reached" % [seat, _channel_tier, ability.growth_tier_scales()[_channel_tier]])

	var tier_scales := ability.growth_tier_scales()
	var base_scale: float = tier_scales[_channel_tier]
	var next_scale: float = tier_scales[min(_channel_tier + 1, tier_scales.size() - 1)]
	var t := clampf(_channel_hold_time / ability.growth_duration_per_tier, 0.0, 1.0)
	if _channel_stutter_remaining > 0.0:
		t = 0.0  # hold right at the tier we just reached during the stutter
	current_instance.scale = Vector2.ONE * lerpf(base_scale, next_scale, t)


## Tries to pay for growing from the current tier to the next one, right as
## that growth is about to start (never after the fact). Returns true and
## deducts the cost if there's a next tier and strikes to afford it. Returns
## false - leaving the caller to start the post-channel grace period, see
## _update_growth_channel() - if this was the final tier (nothing left to
## buy) or the bank can't cover it. Either way, the caller must never show
## growth this rejected: no visual preview of a step that wasn't paid for.
func _try_pay_next_growth_step(ability: GrowthAbility) -> bool:
	var at_final_tier := _channel_tier >= ability.max_tiers
	if at_final_tier:
		# TEMP DEBUG - remove once tier costs are confirmed working.
		print("[DEBUG seat %d] maxed out at tier %d" % [seat, _channel_tier])
		return false
	if strikes < ability.strikes_per_tier:
		# TEMP DEBUG - remove once tier costs are confirmed working.
		print("[DEBUG seat %d] can't afford tier %d - only %d strikes banked, need %d" % [seat, _channel_tier + 1, strikes, ability.strikes_per_tier])
		return false
	strikes -= ability.strikes_per_tier
	# TEMP DEBUG - remove once tier costs are confirmed working.
	print("[DEBUG seat %d] paid %d strikes for tier %d, %d remain" % [seat, ability.strikes_per_tier, _channel_tier + 1, strikes])
	return true


## Ends the current channel and snaps the shield back to its base scale -
## called on release, and also when strikes run out mid-hold. Whatever
## scale was reached is never kept; only the strikes already spent on fully
## completed steps stay spent.
func _end_growth_channel() -> void:
	_is_channeling = false
	_channel_tier = 0
	_channel_hold_time = 0.0
	_channel_stutter_remaining = 0.0
	_channel_growth_exhausted = false
	_channel_grace_remaining = 0.0
	if is_instance_valid(current_instance):
		var ability := _current_ability() as GrowthAbility
		var shrink_time: float = ability.shrink_duration if ability != null else 0.1
		if _shield_scale_tween:
			_shield_scale_tween.kill()
		_shield_scale_tween = create_tween()
		_shield_scale_tween.tween_property(current_instance, "scale", Vector2.ONE, shrink_time)
