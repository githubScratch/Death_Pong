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

## Double-tap-to-blink state (see _update_blink()) - only meaningful for a
## class whose ability is a BlinkAbility. Each counts down from
## ability.double_tap_window after the first tap of its direction; a second
## tap of the same direction while its window is still > 0 triggers a
## blink. Left and right are tracked independently of each other.
var _left_tap_window_remaining: float = 0.0
var _right_tap_window_remaining: float = 0.0

## True while a blink is queued - strikes already spent, direction already
## locked in - and counting down ability.blink_delay before it actually
## fires. See _update_blink()/_execute_blink().
var _blink_pending: bool = false
var _blink_pending_direction: float = 0.0
var _blink_delay_remaining: float = 0.0

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
	_update_blink(delta)

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
		_try_slam_wrap()

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
		_cast_and_jump()

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


## Casts a fresh shield and applies a jump impulse - exactly what pressing Up
## normally does (see _physics_process()). Pulled out into its own function
## so BlinkAbility's cast_on_blink can reuse the identical behavior from
## _execute_blink() instead of duplicating it - same cast, same jump impulse,
## same sounds, whether it's triggered by an Up press or a landed blink.
func _cast_and_jump() -> void:
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
		# Sync the fresh shield's gauge to whatever's already banked, rather
		# than letting it start empty until the next strike/spend event.
		_update_strike_gauge()

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
	_update_strike_gauge()
	# TEMP DEBUG - remove once strikes are confirmed working.
	print("[DEBUG seat %d] strike banked - strikes now %d" % [seat, strikes])


## Reflects currently banked TIERS (not raw strikes) onto the active
## shield's StrikeGauge, if it has one (see strike_gauge.gd) - a no-op for
## any shield that doesn't, same opt-in shape as the rest of this file's
## per-class hooks (GrowthAbility/BlinkAbility casts). Deliberately floors to
## whole tiers rather than showing a smooth per-strike ratio: a partial
## tier's worth of strikes isn't spendable yet, so it shouldn't visually
## read as partial progress on the gauge either - only a completed tier
## moves the fill. This matters once an ability's strikes_per_tier is ever
## greater than 1 (today it's 1 for both classes, so the two ratios happen
## to coincide, but this stays correct as that changes). Call this any time
## `strikes` actually changes, or a fresh shield is spawned. An ability
## that isn't a StrikeScaledAbility (no tiers to speak of) reports the gauge
## empty rather than showing a meaningless ratio.
func _update_strike_gauge() -> void:
	if not is_instance_valid(current_instance):
		return
	var gauge := current_instance.get_node_or_null("StrikeGauge") as StrikeGauge
	if gauge == null:
		return
	var scaled_ability := _current_ability() as StrikeScaledAbility
	if scaled_ability == null or scaled_ability.max_tiers <= 0 or scaled_ability.strikes_per_tier <= 0:
		gauge.set_fill_ratio(0.0)
		return
	var tiers_banked := strikes / scaled_ability.strikes_per_tier  # int division - floors
	gauge.set_fill_ratio(float(tiers_banked) / float(scaled_ability.max_tiers))


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
		_update_strike_gauge()
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
		# Purely cosmetic pause - payment for the NEXT step already happened
		# the instant this one landed (see the else branch below), so this
		# never gates anything. It just holds the visual still for a beat
		# so each strikes_per_tier chunk spent reads as its own distinct
		# "tick" instead of blurring into one continuous grow. Setting
		# tier_stutter_time to 0 only removes that beat - it can never skip
		# a payment, because payment was never behind it in the first place.
		_channel_stutter_remaining = maxf(_channel_stutter_remaining - delta, 0.0)
	else:
		_channel_hold_time += delta
		if _channel_hold_time >= ability.growth_duration_per_tier:
			# This step is fully grown into and already paid for - land on
			# it, then IMMEDIATELY try to pay for the next one, before
			# anything is shown of it. This must happen right here, not
			# deferred behind the stutter countdown above - a stutter of 0
			# would otherwise skip straight past that check every time.
			_channel_tier += 1
			_channel_hold_time = 0.0
			# TEMP DEBUG - remove once tier costs are confirmed working.
			print("[DEBUG seat %d] tier -> %d (scale %.2f) reached" % [seat, _channel_tier, ability.growth_tier_scales()[_channel_tier]])
			if _try_pay_next_growth_step(ability):
				_channel_stutter_remaining = ability.tier_stutter_time
			else:
				# Nothing left to buy (maxed out, or can't afford it) - hand
				# off to the grace period instead of ending outright.
				_channel_growth_exhausted = true
				_channel_grace_remaining = ability.post_channel_hold_time
				if _channel_grace_remaining <= 0.0:
					_end_growth_channel()
					_channel_locked_out = true
					return

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
	_update_strike_gauge()
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


## Double-tap-to-blink: double-tapping Left or Right within
## ability.double_tap_window queues a blink (see _try_blink()) that actually
## fires ability.blink_delay seconds later (see _execute_blink()). No-op
## unless the current ability is a BlinkAbility - same shape as
## _update_growth_channel() being a no-op for classes that aren't a
## GrowthAbility, and costs nothing for classes that aren't a BlinkAbility
## either. Runs every physics frame regardless of class.
func _update_blink(delta: float) -> void:
	var ability := _current_ability() as BlinkAbility
	if ability == null:
		# Not this class's ability - nothing to track, and nothing should
		# be left armed if the class ever changed mid-game.
		_left_tap_window_remaining = 0.0
		_right_tap_window_remaining = 0.0
		_blink_pending = false
		return

	if _blink_pending:
		# A blink is already queued (strikes already spent, direction
		# already locked in) - just count down to it firing. Ignore any
		# taps that happen in the meantime rather than trying to queue,
		# overwrite, or stack a second one.
		_blink_delay_remaining -= delta
		if _blink_delay_remaining <= 0.0:
			_execute_blink(ability, _blink_pending_direction)
			_blink_pending = false
		return

	if _left_tap_window_remaining > 0.0:
		_left_tap_window_remaining = maxf(_left_tap_window_remaining - delta, 0.0)
	if _right_tap_window_remaining > 0.0:
		_right_tap_window_remaining = maxf(_right_tap_window_remaining - delta, 0.0)

	if Input.is_action_just_pressed(_action_left):
		if _left_tap_window_remaining > 0.0:
			_left_tap_window_remaining = 0.0
			_try_blink(ability, -1.0)
		else:
			_left_tap_window_remaining = ability.double_tap_window
	if Input.is_action_just_pressed(_action_right):
		if _right_tap_window_remaining > 0.0:
			_right_tap_window_remaining = 0.0
			_try_blink(ability, 1.0)
		else:
			_right_tap_window_remaining = ability.double_tap_window


## Spends one tier's worth of strikes (ability.strikes_per_tier) - but only
## if that much is currently banked - and queues the actual teleport to
## fire ability.blink_delay seconds from now (instantly, if blink_delay is
## 0). Strikes are spent right here, the instant the double-tap registers,
## not when the teleport actually fires - same "pay at commit, not after"
## rule growth uses. Strikes banked beyond one tier are left untouched, so
## a maxed-out player can queue up to ability.max_tiers blinks back to
## back if they want, or save them for later.
func _try_blink(ability: BlinkAbility, direction: float) -> void:
	if strikes < ability.strikes_per_tier:
		# TEMP DEBUG - remove once blink charges are confirmed working.
		print("[DEBUG seat %d] blink denied - only %d strikes banked, need %d" % [seat, strikes, ability.strikes_per_tier])
		return
	strikes -= ability.strikes_per_tier
	_update_strike_gauge()
	_spawn_blink_vfx(ability, direction)
	if ability.blink_delay <= 0.0:
		_execute_blink(ability, direction)
		return
	_blink_pending = true
	_blink_pending_direction = direction
	_blink_delay_remaining = ability.blink_delay
	# TEMP DEBUG - remove once blink charges are confirmed working.
	print("[DEBUG seat %d] blink queued %s - spent %d strikes, %d remain, firing in %.2fs" % [seat, ("left" if direction < 0.0 else "right"), ability.strikes_per_tier, strikes, ability.blink_delay])


## Drops ability.vfx_scene (if assigned) at the wizard's CURRENT position -
## whatever that is at the moment this is called, so where it ends up
## depends entirely on the caller and when in its flow it calls this.
## Every blink now spawns one at each end of the teleport: _try_blink()
## calls it at the CAST point (before blink_delay's wind-up even starts),
## _execute_blink() calls it again once global_position is fully settled
## (the landing point, wrapped or not), and _try_slam_wrap() calls it twice
## the same way for its own vertical teleport (ground strike point, then
## the ceiling). Purely cosmetic and entirely opt-in, same shape as
## _update_strike_gauge(): an ability with no vfx_scene assigned skips this
## silently. Plays the instanced scene's AnimatedSprite2D once (flipped to
## face `direction` - pass 0.0 for no flip, e.g. a vertical teleport with no
## left/right equivalent) and frees the instance itself the moment that
## animation ends - or after a fallback timeout if the scene doesn't have
## one - so drop-and-forget VFX never pile up as clutter.
func _spawn_blink_vfx(ability: BlinkAbility, direction: float) -> void:
	if not is_instance_valid(ability.vfx_scene):
		return
	var vfx: Node2D = ability.vfx_scene.instantiate()
	vfx.global_position = global_position
	get_tree().current_scene.add_child(vfx)
	var anim := vfx.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		anim.flip_h = direction < 0.0
		anim.play()
		await anim.animation_finished
	else:
		await get_tree().create_timer(1.0).timeout
	if is_instance_valid(vfx):
		vfx.queue_free()


## Actually performs the teleport - immediately from _try_blink() if
## blink_delay is 0, otherwise once _update_blink()'s countdown reaches 0.
## Uses test_move() rather than blindly offsetting position, so a blink can
## never tunnel the wizard partway (or fully) into a wall or the arena edge
## - it sweeps the wizard's own collision shape along the blink, using the
## same collision_mask that already governs normal movement, and if
## anything solid is in the way, only the clear portion of the motion is
## taken instead of the full blink_distance. A raycast alone would miss
## this: it's a single infinitely-thin line, but the wizard's actual body
## has width, so a ray down the center could clear a wall's edge that the
## wizard's shoulders would still clip - test_move() checks the real shape,
## not a point, so no separate collision geometry is needed for this.
## Also handles landing feel: if ability.cast_on_blink is true, lands exactly
## like an Up press - a fresh shield plus the normal jump impulse, via
## _cast_and_jump() - letting a blink double as a re-cast/repositioning move
## in one motion. Otherwise (the default) just zeroes vertical velocity, so
## the wizard doesn't land in the new spot still carrying whatever fall speed
## it had built up right before blinking - a clean reset instead of
## instantly resuming a fast fall that visually has nothing to do with the
## teleport that just happened.
func _execute_blink(ability: BlinkAbility, direction: float) -> void:
	var motion := Vector2(direction * ability.blink_distance, 0.0)
	var collision := KinematicCollision2D.new()
	if test_move(global_transform, motion, collision):
		var wrap_target := _wrap_destination(collision.get_collider())
		if wrap_target != null:
			# Hit a wall tagged as a wrap boundary (see arena.tscn's
			# map_wall_left/map_wall_right groups) - reappear at that wall's
			# own WrapDestination marker instead of stopping short. Only X
			# moves; Y is left untouched - this is a left/right wrap only,
			# vertical wrap is a separate planned mechanic (the down-dash
			# landing one), not this one.
			global_position.x = wrap_target.global_position.x
			# TEMP DEBUG - remove once blink charges are confirmed working.
			print("[DEBUG seat %d] blink %s wrapped to the opposite side" % [seat, ("left" if direction < 0.0 else "right")])
		else:
			# Blocked by something that isn't a wrap boundary (another
			# wizard, an untagged wall, a mid-arena platform) - only take
			# the portion of the motion that's actually clear, so the
			# wizard stops flush against whatever it hit instead of ending
			# up inside it.
			motion = collision.get_travel()
			global_position += motion
			# TEMP DEBUG - remove once blink charges are confirmed working.
			print("[DEBUG seat %d] blink %s blocked - only %.1f of %.1f px clear" % [seat, ("left" if direction < 0.0 else "right"), motion.length(), ability.blink_distance])
	else:
		global_position += motion
	# global_position is fully settled by this point in every branch above
	# (wrapped, blocked-and-clipped, or the full unblocked distance) -
	# _spawn_blink_vfx() reads it live, so calling it here drops a second
	# VFX at wherever the wizard actually ended up (the landing point),
	# matching _try_blink()'s existing spawn at the cast point - same
	# "one at each end" treatment _try_slam_wrap() uses.
	_spawn_blink_vfx(ability, direction)
	if ability.cast_on_blink:
		_cast_and_jump()
	else:
		velocity.y = 0.0
	# TEMP DEBUG - remove once blink charges are confirmed working.
	print("[DEBUG seat %d] blinked %s" % [seat, ("left" if direction < 0.0 else "right")])


## Returns the WrapDestination marker for a blocked blink's collider, or
## null if that collider isn't tagged as a wrap boundary. Only
## map_wall_left/map_wall_right (currently just Arena's left/right walls -
## see arena.tscn) opt in; anything else - another wizard, a mid-arena
## platform, an arena with no wrap walls tagged at all - returns null and
## _execute_blink() falls back to its normal stop-short behavior. Keeping
## this as a group lookup rather than a hardcoded node path means adding
## wrap walls to another arena later is a scene-only change, no script
## change needed here.
func _wrap_destination(collider: Node) -> Node2D:
	if collider == null:
		return null
	if not (collider.is_in_group("map_wall_left") or collider.is_in_group("map_wall_right")):
		return null
	return collider.get_node_or_null("WrapDestination") as Node2D


## Blink's floor-to-ceiling counterpart to the left/right wall wrap above -
## called only from the airborne -> grounded landing transition in
## _physics_process(), so "only while airborne" falls out for free: this is
## never reached from pressing Down while already standing on the floor,
## since hit_the_ground is already true by then and that block never runs.
## Requires the current ability to be a BlinkAbility with wrap_on_slam
## enabled, Down still held at the moment of landing, and a full tier's
## worth of strikes banked (same strikes_per_tier cost as a normal blink,
## paid the same "pay at commit" way) - any of those failing just leaves
## the landing as a normal landing. The destination is looked up by group
## (map_wall_top's WrapDestination child - see arena.tscn) rather than a
## hardcoded node, same reasoning as _wrap_destination(): an arena with no
## ceiling tagged simply doesn't support this yet, no crash.
func _try_slam_wrap() -> void:
	var ability := _current_ability() as BlinkAbility
	if ability == null or not ability.wrap_on_slam:
		return
	if not Input.is_action_pressed(_action_down):
		return
	if strikes < ability.strikes_per_tier:
		# TEMP DEBUG - remove once slam wrap is confirmed working.
		print("[DEBUG seat %d] slam wrap denied - only %d strikes banked, need %d" % [seat, strikes, ability.strikes_per_tier])
		return
	var ceiling_wall := get_tree().get_first_node_in_group("map_wall_top")
	var wrap_target: Node2D = null
	if ceiling_wall != null:
		wrap_target = ceiling_wall.get_node_or_null("WrapDestination") as Node2D
	if wrap_target == null:
		return
	strikes -= ability.strikes_per_tier
	_update_strike_gauge()
	# _spawn_blink_vfx() reads global_position at call time, so calling it
	# once here (before moving global_position) drops a VFX at the ground
	# strike point, and once more below (after the teleport) drops a
	# second one at the landing point - the ceiling. direction is passed
	# as 0.0 (no flip) both times: the flip is a left/right thing and
	# doesn't have an equivalent for a vertical teleport.
	_spawn_blink_vfx(ability, 0.0)
	global_position.y = wrap_target.global_position.y
	velocity.y = 0.0
	_spawn_blink_vfx(ability, 0.0)
	# TEMP DEBUG - remove once slam wrap is confirmed working.
	print("[DEBUG seat %d] slam-wrapped floor to ceiling - spent %d strikes, %d remain" % [seat, ability.strikes_per_tier, strikes])
