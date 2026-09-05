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

## The currently-attached GrowthAbility.vfx_scene instance, if any - see
## _start_growth_vfx()/_stop_growth_vfx(). Attached to current_instance (the
## growing shield itself), not the wizard, so it both follows the shield's
## position for free AND grows/shrinks along with it as _shield_scale_tween
## and the per-tier scale steps run - instead of a one-shot burst like
## Blink's VFX this stays alive for as long as the channel does and is
## queue_free()'d the instant it ends, rather than living for the whole match.
var _growth_vfx: Node2D = null

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

## Double-tap-to-zone state (see _update_ice_zone()/_cast_ice_zone()) -
## only meaningful for a class whose ability is an IceAbility. Own separate
## double-tap tracking from _update_blink()'s _left_tap_window_remaining/
## _right_tap_window_remaining, even though the detection shape is
## identical - same "each mechanic gets its own state" split this file
## already follows elsewhere, so an unrelated ability's timing never gets
## tangled up with this one's.
var _ice_left_tap_window_remaining: float = 0.0
var _ice_right_tap_window_remaining: float = 0.0

## Seconds normal LEFT/RIGHT movement-input handling is suppressed after the
## most recent zone cast - see _cast_ice_zone()/IceAbility.knockback_lock_time.
## Exists purely so that cast's single jolt of self_knockback (set once,
## then eased back to 0 by a Tween - see _cast_ice_zone()) isn't instantly
## fought and overwritten the very same physics frame by whatever direction
## the player's still holding from the double-tap that triggered it - the
## "competing commands" this whole knob is here to avoid. An earlier version
## also suspended GRAVITY for this same window (a "hover"), but that fought
## this wizard's own jump/dive/landing logic (which assumes gravity is never
## paused) and was dropped - gravity is always normal now, only horizontal
## movement input is briefly held off. Never locks out jumping/diving/
## casting themselves, unlike Growth's full velocity-zero channel hover.
var _ice_input_lock_remaining: float = 0.0

## Double-tap-and-hold-to-meteor state (see _update_meteor()/_start_meteor()) -
## only meaningful for a class whose ability is a MeteorAbility. Own separate
## double-tap tracking from every other ability's (_left_tap_window_remaining/
## _right_tap_window_remaining/_ice_left_tap_window_remaining/
## _ice_right_tap_window_remaining), even though the detection shape is
## identical, same "each mechanic gets its own state" split this file already
## follows everywhere else - Down is never in danger of double-tap state
## meant for Left/Right (or vice versa) getting tangled up with this one.
var _meteor_down_tap_window_remaining: float = 0.0

## True for as long as this wizard is currently falling as a meteor - set by
## _start_meteor() the instant a qualifying double-tap-and-hold registers,
## cleared by _cancel_meteor() (only ever an external interrupt now, like a
## freeze catching the fall mid-plunge - the fall itself is deliberately
## uninterruptible by input once it starts, see _update_meteor()'s own doc
## comment) or _land_meteor() (actually reaching the ground).
## _physics_process() reads this near the very end of its own function, the
## same place _is_channeling's override lives, to force velocity to a
## straight-down plunge every frame regardless of whatever the normal
## gravity/movement code above it just computed.
var _is_meteor: bool = false

## The currently-attached MeteorAbility.meteor_fall_vfx_scene instance, if
## any - see _spawn_meteor_vfx()/_clear_meteor_vfx(). A child of the WIZARD
## itself (not a shield instance - that's _meteor_barrier below), same
## "attach directly to self" shape _spawn_frozen_overlay() already uses, so
## it rides along with the fall for free without needing to be repositioned
## every frame.
var _meteor_vfx: Node2D = null

## This wizard's own standing shield (current_instance), reparented onto the
## wizard itself for as long as this meteor form lasts - see
## _attach_meteor_barrier()/_end_meteor_barrier(). Gives the ability a real,
## visible collision shape riding along with the fall (and, at tier 2, still
## standing afterward) instead of an invisible hitbox, which doubles as an
## honest cue for how far this actually reaches - see MeteorAbility.
## meteor_barrier_deflection_bonus's own doc comment for how it hits harder
## while attached. Tracked separately from current_instance (rather than
## just reading that directly) so a jump's own create_new_instance()
## legitimately reassigning current_instance to a fresh barrier mid-tier-2-
## lingering (possible when MeteorAbility.tier2_meteor_form_blocks_barrier is
## false) never gets its fresh barrier wrongly torn away by this ability's
## own end-of-form cleanup - see _end_meteor_barrier()'s own doc comment.
var _meteor_barrier: Node2D = null

## True while THIS wizard is standing inside someone ELSE's Ice Zone (see
## IceZone._on_body_entered(), which always skips the caster's own zone
## unless IceAbility.self_affected is true) - mirrors Ball.freeze_in_place()/
## thaw() with the CharacterBody2D-appropriate version below. Jump, dive,
## casting, and every hold-based ability are still fully locked out while
## this is true (_physics_process()'s frozen branch returns before reaching
## any of that), but LEFT/RIGHT movement is NOT - it's read and applied right
## there in the frozen branch too, just scaled by (1.0 - _frozen_slow_amount),
## so a partial slow_amount actually reads as reduced walking speed instead
## of a full lockout regardless of the knob's value. Only at slow_amount 1.0
## does movement input stop mattering at all.
##
## Deliberately a SEPARATE flag from _frozen_remaining, rather than just
## checking _frozen_remaining > 0.0 everywhere (which an earlier version of
## this file did) - the natural-timeout call to thaw() below happens the
## same frame _frozen_remaining is driven to <= 0, so thaw()'s own "was this
## even frozen" guard (see thaw()'s doc comment - it has to no-op when
## called on an already-normal wizard, since deflection_shield.gd calls it
## unconditionally on every wizard any shield touches) would otherwise see
## _frozen_remaining already at 0 and skip its own cleanup - silently
## leaving _frozen_overlay attached forever, which is exactly the "sprites
## stuck on wizards permanently" bug this flag fixes.
var _is_frozen: bool = false
var _frozen_remaining: float = 0.0
var _frozen_slow_amount: float = 0.0
var _frozen_overlay: Node2D = null

## Counts down MeteorAbility.tier2_meteor_form_duration seconds after a
## TIER-2 landing (see _land_meteor()'s tiers_banked >= 2 branch) while
## MeteorAbility.tier2_meteor_form_enabled is true - set the moment that
## branch fires, instead of the usual end-of-fall cleanup that branch would
## otherwise run. _physics_process() decrements this every frame, same shape
## _ice_input_lock_remaining above already uses, and runs the normal end-of-
## fall cleanup (vfx end, barrier fade) the instant it reaches 0 (see
## _end_meteor_form_lingering()) - until then, _meteor_vfx and
## _meteor_barrier are simply left exactly as the fall itself set them up,
## still riding along and the barrier still dealing its usual boosted
## deflection, as if the fall had never actually ended. create_new_instance()
## also reads this directly to decide whether to suppress a jump's usual
## shield summon for the same window, gated by MeteorAbility.
## tier2_meteor_form_blocks_barrier - see that function's own doc comment.
## Not specially reconciled against a FRESH meteor fall re-triggered (and
## then cancelled by an external interrupt) while this is still counting
## down from an earlier landing - _cancel_meteor()'s own vfx/barrier cleanup
## wins in that corner case, same as it always has; this timer just keeps
## ticking harmlessly in the background either way.
var _meteor_form_lock_remaining: float = 0.0

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
	# Frozen still locks out jumping, diving, casting, and growth/blink/zone
	# holds unconditionally - a slowed wizard can't burst out of it with a
	# jump-dash or interrupt it with a fresh cast, no matter how partial
	# _frozen_slow_amount is. LEFT/RIGHT movement is the one thing that
	# actually scales with that knob now: at 0.0 it's full walking speed
	# (caught, but not hindered at all), at 1.0 it's genuinely 0 ("remains
	# in place" - "at 1 we have stopped entirely state"), and anything
	# between moves at that fraction of normal SPEED - a wizard slowed by,
	# say, 0.5 visibly keeps shuffling around at half speed instead of
	# reading as fully frozen regardless of the knob, which is what made a
	# partial slow_amount invisible before (no input at all ever reached
	# movement, only gravity's pull scaled). Gravity gets the same
	# (1.0 - _frozen_slow_amount) treatment it always did: freeze_in_place()
	# already cut whatever velocity this wizard had once, at the moment of
	# catching it (see that function), so from here it's just how much of
	# gravity's ongoing pull gets through each frame - 0 at slow_amount 1.0,
	# the same 2x gravity the normal branch below uses at slow_amount 0.0,
	# something in between otherwise.
	if _is_frozen:
		# A meteor fall caught mid-plunge by someone else's ice zone shouldn't
		# leave its vfx/barrier dangling on a now-frozen wizard forever -
		# cancel it the instant freezing takes over. Checked here, at the
		# very top of this branch, since a frozen wizard never reaches
		# _update_meteor() below at all (this whole branch returns before
		# that point).
		if _is_meteor:
			_cancel_meteor()
		_frozen_remaining -= delta
		# Deliberately NOT gated behind is_on_floor(), unlike the identical-
		# looking check in the normal branch below. Ball.freeze_in_place()
		# gives a partially-slowed ball a persistent gravity_scale that the
		# physics engine just keeps integrating regardless of whether the
		# ball happens to be resting against anything at any given instant
		# (a RigidBody2D has no is_on_floor() to gate on in the first place),
		# so a caught ball always visibly reflects a mid slow_amount setting.
		# Gating this the same way the normal branch does meant a wizard
		# caught while already standing on solid ground got NO gravity term
		# at all, at ANY slow_amount - 0.5 and 1.0 looked identical (fully
		# frozen), since there was nothing pulling it down either way. move_
		# and_slide() below still keeps a grounded wizard pinned to the floor
		# exactly like it always does outside a freeze, so this doesn't let
		# one sink through the ground - it just means a value below 1.0 now
		# actually reads as "slowed" rather than "frozen" even for a wizard
		# that was standing still the instant it got caught.
		velocity += get_gravity() * 2 * delta * (1.0 - _frozen_slow_amount)
		if velocity.y > max_fall_speed:
			velocity.y = max_fall_speed

		var frozen_move_scale := 1.0 - _frozen_slow_amount
		var frozen_direction := Input.get_axis(_action_left, _action_right)
		if frozen_direction:
			velocity.x = frozen_direction * SPEED * frozen_move_scale
			if frozen_direction > 0:
				sprite.flip_h = false
			elif frozen_direction < 0:
				sprite.flip_h = true
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED * frozen_move_scale)

		move_and_slide()
		if _frozen_remaining <= 0.0:
			thaw()
		return

	_update_growth_channel(delta)
	_update_blink(delta)
	_update_ice_zone(delta)
	_update_meteor(delta)

	if _ice_input_lock_remaining > 0.0:
		_ice_input_lock_remaining = maxf(_ice_input_lock_remaining - delta, 0.0)

	if _meteor_form_lock_remaining > 0.0:
		_meteor_form_lock_remaining = maxf(_meteor_form_lock_remaining - delta, 0.0)
		if _meteor_form_lock_remaining <= 0.0:
			_end_meteor_form_lingering()

	# Add the gravity and stretch. Always active, every frame - an earlier
	# version of Ice's knockback suspended gravity here for a short window
	# (a "hover") so the recoil would carry, but that fought this wizard's
	# own jump/dive/landing logic (all of which assumes gravity is never
	# paused) and was dropped; see _ice_input_lock_remaining's doc comment
	# for what replaced it.
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
		if _is_meteor:
			_land_meteor()
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
	if Input.is_action_just_pressed(_action_up) and not _is_meteor:
		_cast_and_jump()

	# Handle dive.
	if Input.is_action_just_pressed(_action_down) and not _is_channeling and not _is_meteor:
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

	# Get the input direction and handle the movement/deceleration. Skipped
	# entirely while _ice_input_lock_remaining is still counting down, so a
	# zone cast's self_knockback jolt (set once, then eased back to 0 by a
	# Tween - see _cast_ice_zone()) actually reads as a visible burst for
	# the whole of ability.knockback_lock_time instead of being instantly
	# overwritten this same frame by whatever direction the player's still
	# holding from the double-tap that triggered it.
	if _ice_input_lock_remaining <= 0.0:
		var direction := Input.get_axis(_action_left, _action_right)
		if direction:
			velocity.x = direction * SPEED
			if direction > 0:
				sprite.flip_h = false  # Face right
			elif direction < 0:
				sprite.flip_h = true   # Face left
		else:
			velocity.x = move_toward(velocity.x, 0, SPEED)

	# Hold-to-grow hovers in place - whatever gravity/jump/dive/movement code
	# above just computed for this frame gets overridden here, every frame,
	# for as long as a growth channel is active. Gravity still technically
	# accumulates into velocity.y above while this is true, but since it's
	# zeroed again right here before move_and_slide(), it never actually
	# moves the wizard - each frame effectively starts fresh. Doesn't touch
	# Ice's own knockback jolt at all - that's a one-time velocity.x set
	# (plus a Tween easing it back down - see _cast_ice_zone()), not a
	# per-frame hover, and the two abilities are never active at once.
	if _is_channeling:
		velocity = Vector2.ZERO

	# Meteor's own full override, same "replace whatever the normal code
	# above just computed" shape _is_channeling's hover uses just above -
	# every physics frame this is true, velocity is forced to a straight
	# drop at ability.fall_speed regardless of gravity, held direction, or
	# whatever the Down-press dive/dash block above happened to just set
	# this same frame (that block is also gated off while _is_meteor is
	# true - see its own condition - but this still needs to win outright on
	# the very frame _start_meteor() itself runs).
	if _is_meteor:
		velocity = Vector2(0.0, _meteor_fall_speed())

	move_and_slide()


## Called the instant _meteor_form_lock_remaining above counts down to 0 -
## runs the normal end-of-fall cleanup that the tier-2 landing branch of
## _land_meteor() skipped when it started this lingering window in the first
## place: _meteor_vfx ended (via _end_meteor_vfx(), so
## meteor_fall_vfx_despawn_delay still applies same as any other fall
## ending) and _meteor_barrier faded out (via _end_meteor_barrier()) -
## exactly what a normal landing does, just deferred by
## tier2_meteor_form_duration seconds. Guarded behind `not _is_meteor` so a
## fresh fall re-triggered before the old lingering window even finished
## isn't stomped back down to normal out from under it - that fall's own
## _start_meteor()/_cancel_meteor()/_land_meteor() own the vfx/barrier
## entirely once _is_meteor is true again, this function just stays out of
## the way in that case.
func _end_meteor_form_lingering() -> void:
	if _is_meteor:
		return
	_end_meteor_vfx(_current_ability() as MeteorAbility)
	_end_meteor_barrier()


## Reparents this wizard's current standing barrier (current_instance, if
## any) onto the wizard itself for as long as this meteor form lasts - see
## _meteor_barrier's own doc comment for why it's tracked separately, and
## _end_meteor_barrier() for the matching cleanup. Snaps it to this wizard's
## own position first via reparent()'s default keep_global_transform (it
## could otherwise be sitting well away from here if the player walked off
## after casting it), then forces its LOCAL position to zero so it reads as
## centered on the wizard the instant the fall begins and just rides along
## for free from there since it's now a child of a moving CharacterBody2D.
## Boosts the shield's own deflection_force by ability.
## meteor_barrier_deflection_bonus for as long as it's attached, and connects
## _on_meteor_barrier_touched_ball() to its Area2D.body_entered so a touched
## ball still gets ignited (see that function's own doc comment for why this
## is a separate listener rather than folded into deflection_shield.gd) -
## this ability's whole "hits harder" payoff now lives entirely on the real
## barrier instead of a separate invisible hitbox, so the barrier's own
## visible collision radius doubles as an honest cue for how far this
## actually reaches. A no-op if there's no current_instance to attach -
## nothing summoned yet, or a previous meteor already consumed the last one
## via _end_meteor_barrier() - the fall still happens, just without a
## barrier riding along that time.
func _attach_meteor_barrier(ability: MeteorAbility) -> void:
	if not is_instance_valid(current_instance):
		return
	# current_instance is declared as a bare `Node` (every class's shield
	# scene root, whatever type that happens to be) - `position` below is a
	# Node2D/CanvasItem property, not a Node one, so this needs its own
	# narrower local before touching it, same reasoning every other
	# global_position/linear_velocity cast in this file already follows.
	var barrier := current_instance as Node2D
	if barrier == null:
		return
	var shield := barrier.get_node_or_null("Area2D") as DeflectionShield
	if shield != null:
		shield.deflection_force += ability.meteor_barrier_deflection_bonus
		shield.body_entered.connect(_on_meteor_barrier_touched_ball.bind(ability))
	barrier.reparent(self)
	barrier.position = Vector2.ZERO
	_meteor_barrier = barrier


## Ends whatever _attach_meteor_barrier() attached - called by
## _cancel_meteor(), _land_meteor()'s own normal-landing branch, and
## _end_meteor_form_lingering() alike, same "the effect is over, fade the
## barrier" cleanup every one of those needs. Tracked via the dedicated
## _meteor_barrier reference rather than just reusing current_instance
## directly, since a tier-2 lingering window with MeteorAbility.
## tier2_meteor_form_blocks_barrier left false lets a jump's own
## create_new_instance() legitimately fade THIS barrier out and reassign
## current_instance to a brand new one while still lingering -
## is_instance_valid() below already returns false for a barrier
## create_new_instance() got to first, so this just quietly no-ops rather
## than double-fading it, and the `current_instance == barrier_root` guard
## means a fresh legitimate barrier from that jump is never wrongly cleared
## out from under the player. Uses DeflectionShield.start_fade() (the
## Area2D's own public "play fade, then queue_free" method - its "fade"
## animation clip already frees the whole barrier root on its own, same as
## create_new_instance()'s inline fade logic relies on for a normal shield
## swap) rather than duplicating that logic here.
func _end_meteor_barrier() -> void:
	if not is_instance_valid(_meteor_barrier):
		_meteor_barrier = null
		return
	var barrier_root := _meteor_barrier
	_meteor_barrier = null
	if current_instance == barrier_root:
		current_instance = null
	var shield := barrier_root.get_node_or_null("Area2D") as DeflectionShield
	if shield != null:
		shield.start_fade()
	else:
		barrier_root.queue_free()


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
	# Tier-2 lingering meteor form (see _meteor_form_lock_remaining's own doc
	# comment) can suppress a jump's usual shield summon entirely for its
	# duration - MeteorAbility.tier2_meteor_form_blocks_barrier is the knob.
	# Checked as its own MeteorAbility-typed lookup (separate from the plain
	# `ability` this function already looks up a few lines down) since
	# _meteor_form_lock_remaining is only ever > 0.0 for a fire wizard mid-
	# lingering in the first place - every other class always skips this
	# whole block for free. Returns immediately, before touching
	# current_instance at all, so whatever barrier was already standing stays
	# exactly as it was - the jump impulse/sounds in _cast_and_jump() still
	# happen normally either way, only this function's own work is skipped.
	if _meteor_form_lock_remaining > 0.0:
		var lingering_ability := _current_ability() as MeteorAbility
		if lingering_ability != null and lingering_ability.tier2_meteor_form_blocks_barrier:
			return

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
	# Any growth VFX riding on the outgoing shield (see _start_growth_vfx())
	# is a child of it, not of the wizard, so it keeps playing right through
	# whatever fade/queue_free just happened above instead of being cut off
	# here - just forget the reference so the next _start_growth_vfx() call
	# doesn't try to stop/reuse a VFX that now belongs to a retired shield.
	_growth_vfx = null

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
		# Give the gauge a little "bloop" the instant the shield is summoned -
		# a gentler kick than a deflect gets (see StrikeGauge.summon_slosh_kick)
		# - only actually visible when strikes carried over into this cast,
		# since an empty gauge has no liquid to slosh, but that's exactly
		# when it's worth celebrating (nothing lost on a fresh cast).
		var new_gauge := instance.get_node_or_null("StrikeGauge") as StrikeGauge
		if new_gauge != null:
			new_gauge.slosh_from_summon()

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
	# MeteorAbility.disable_strikes_while_meteor_form can turn this whole
	# function into a no-op for as long as this wizard is in ANY part of
	# meteor form - falling (_is_meteor) or tier-2 lingering (_meteor_form_
	# lock_remaining > 0.0) alike. The barrier still physically deflects the
	# ball either way (plain DeflectionShield behavior, independent of
	# strikes entirely) - this only decides whether that deflection also
	# grows this wizard's own banked count for a FUTURE meteor. Non-meteor
	# classes always see `meteor_ability` come back null here and skip this
	# check for free.
	var meteor_ability := _current_ability() as MeteorAbility
	if meteor_ability != null and meteor_ability.disable_strikes_while_meteor_form:
		if _is_meteor or _meteor_form_lock_remaining > 0.0:
			return
	strikes += 1
	var cap := _max_banked_strikes(_current_ability())
	if cap >= 0 and strikes > cap:
		strikes = cap
	_update_strike_gauge()
	if is_instance_valid(current_instance):
		var gauge := current_instance.get_node_or_null("StrikeGauge") as StrikeGauge
		if gauge != null:
			gauge.slosh_from_impact()
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
		_start_growth_vfx(ability)
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
## completed steps stay spent. Deliberately does NOT touch the growth VFX -
## that's tied to the shield (the "barrier") persisting, not to the channel
## itself, so it keeps riding current_instance right through the shrink
## tween below and stays alive until the shield is actually replaced/faded
## out in create_new_instance(). See _start_growth_vfx()'s doc comment.
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


## Attaches ability.vfx_scene (if assigned) directly to current_instance
## (the growing shield) the instant a growth channel commits - a continuous
## ambient effect meant to last as long as channeling does, not a one-shot
## burst like Blink's VFX, so it's parented to the shield itself (not the
## wizard, not the top-level scene) to both follow its position for free AND
## scale up/down along with it as it grows, rather than needing to be
## repositioned or rescaled every frame. Plays the instanced scene's
## AnimationPlayer "grow" animation if present. Purely cosmetic and entirely
## opt-in, same shape as _spawn_blink_vfx(): an ability with no vfx_scene
## assigned, or no live shield to attach to, does nothing. See
## _stop_growth_vfx() for the other half of this.
func _start_growth_vfx(ability: GrowthAbility) -> void:
	if not is_instance_valid(ability.vfx_scene) or not is_instance_valid(current_instance):
		return
	_stop_growth_vfx()
	var vfx: Node2D = ability.vfx_scene.instantiate()
	current_instance.add_child(vfx)
	var anim := vfx.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim != null and anim.has_animation("grow"):
		anim.play("grow")
	_growth_vfx = vfx


## Stops and removes whatever _start_growth_vfx() previously attached to the
## STILL-LIVE current_instance - only ever needed when a fresh channel
## commits again on a shield that already has one running (belt and
## suspenders against back-to-back channels), since a channel ending on its
## own no longer calls this (see _end_growth_channel()) and a retired shield
## just carries its VFX away with it as a child (see create_new_instance()).
## Explicitly stops the AnimationPlayer first (cutting off its
## particles/audio immediately) before queue_free()ing the instance itself.
func _stop_growth_vfx() -> void:
	if not is_instance_valid(_growth_vfx):
		_growth_vfx = null
		return
	var anim := _growth_vfx.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim != null:
		anim.stop()
	_growth_vfx.queue_free()
	_growth_vfx = null


## Double-tap-to-zone: double-tapping Left or Right within
## ability.double_tap_window drops a slowing zone (see _cast_ice_zone()) -
## own separate double-tap tracking from _update_blink()'s, even though the
## detection shape is identical, same "each hold-mechanic gets its own
## state" split the growth-channel block above already follows. No-op
## unless the current ability is an IceAbility. Runs every physics frame
## regardless of class, same as the other _update_*() functions.
func _update_ice_zone(delta: float) -> void:
	var ability := _current_ability() as IceAbility
	if ability == null:
		# Not this class's ability - nothing to track, and nothing should
		# be left armed if the class ever changed mid-game.
		_ice_left_tap_window_remaining = 0.0
		_ice_right_tap_window_remaining = 0.0
		return

	if _ice_left_tap_window_remaining > 0.0:
		_ice_left_tap_window_remaining = maxf(_ice_left_tap_window_remaining - delta, 0.0)
	if _ice_right_tap_window_remaining > 0.0:
		_ice_right_tap_window_remaining = maxf(_ice_right_tap_window_remaining - delta, 0.0)

	if Input.is_action_just_pressed(_action_left):
		if _ice_left_tap_window_remaining > 0.0:
			_ice_left_tap_window_remaining = 0.0
			_cast_ice_zone(ability, -1.0)
		else:
			_ice_left_tap_window_remaining = ability.double_tap_window
	if Input.is_action_just_pressed(_action_right):
		if _ice_right_tap_window_remaining > 0.0:
			_ice_right_tap_window_remaining = 0.0
			_cast_ice_zone(ability, 1.0)
		else:
			_ice_right_tap_window_remaining = ability.double_tap_window


## Spends every currently-banked tier at once (up to ability.max_tiers) -
## needs at least one full ability.strikes_per_tier banked, or this just
## doesn't cast at all, same as Blink denying an unaffordable blink - and
## drops ability.zone_scene (see IceZone) at a fixed point in `direction`
## (-1.0 left, 1.0 right): just past the zone's own spawn-time radius from
## the wizard's CURRENT position, so a bigger zone (more tiers spent)
## naturally reaches further out without needing its own separate distance
## knob. Also applies this cast's recoil - see _apply_ice_knockback().
func _cast_ice_zone(ability: IceAbility, direction: float) -> void:
	var tiers_spent: int = clampi(strikes / ability.strikes_per_tier, 0, ability.max_tiers)
	if tiers_spent < 1:
		# TEMP DEBUG - remove once ice zone strikes are confirmed working.
		print("[DEBUG seat %d] ice zone denied - only %d strikes banked, need %d" % [seat, strikes, ability.strikes_per_tier])
		return
	strikes -= tiers_spent * ability.strikes_per_tier
	_update_strike_gauge()

	if is_instance_valid(ability.zone_scene):
		var zone_scale := ability.zone_scale_for_tier(tiers_spent)
		var zone: Node2D = ability.zone_scene.instantiate()
		zone.global_position = global_position + Vector2(direction * IceZone.BASE_RADIUS * zone_scale, 0.0)
		zone.configure(
			zone_scale,
			ability.zone_slow_for_tier(tiers_spent),
			ability.zone_duration_for_tier(tiers_spent),
			ability.despawn_delay,
			self,
			ability.self_affected,
			ability.frozen_ball_overlay,
			ability.frozen_wizard_overlay,
			ability.self_vfx_scene,
			direction,
		)
		get_tree().current_scene.add_child(zone)

	_apply_ice_knockback(-direction * ability.self_knockback, ability.knockback_lock_time)

	# TEMP DEBUG - remove once ice zone strikes are confirmed working.
	print("[DEBUG seat %d] ice zone cast %s - spent %d tiers (%d strikes), %d strikes remain" % [seat, ("left" if direction < 0.0 else "right"), tiers_spent, tiers_spent * ability.strikes_per_tier, strikes])


## Applies a zone cast's recoil as a single, instant jolt of velocity.x
## (`jolt_x`, IceAbility.self_knockback signed opposite the cast direction) -
## deliberately a hard, one-time set here (not additive, not per-frame),
## same "one impact, one new velocity" shape ball.gd's deflect gets off a
## shield (deflection_shield.gd's deflect_ball(): `linear_velocity =
## direction * deflection_force`) - rather than the wizard's own held-input
## movement code fighting it frame-by-frame, which is what made the old
## additive version still read as "off." A Tween then eases that jolt back
## down to 0 over `lock_time` (IceAbility.knockback_lock_time) - ease-out,
## so it decays the way an impact naturally would instead of holding at full
## speed for the whole window and then snapping to whatever's held - and
## _ice_input_lock_remaining is set for that same `lock_time`, so
## _physics_process()'s normal LEFT/RIGHT movement-input handling stays out
## of the way for exactly as long as the Tween owns velocity.x. Those two
## windows finishing on the same frame is what hands control back to the
## player cleanly right as the burst finishes reading, instead of the two
## "competing commands" (this jolt vs. whatever direction is held) fighting
## every frame in between the way they used to.
func _apply_ice_knockback(jolt_x: float, lock_time: float) -> void:
	velocity.x = jolt_x
	_ice_input_lock_remaining = lock_time
	if lock_time <= 0.0:
		return
	var tween := create_tween()
	tween.tween_method(_set_ice_knockback_velocity_x, jolt_x, 0.0, lock_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## Tween callback for _apply_ice_knockback() - Tween.tween_method() needs an
## actual callable to drive, it can't write to the `velocity.x` property
## directly.
func _set_ice_knockback_velocity_x(value: float) -> void:
	velocity.x = value


## Called by whichever OTHER wizard's Ice Zone this wizard is currently
## standing inside (see IceZone._on_body_entered() - it excludes the
## caster's own zone entirely unless IceAbility.self_affected is true).
## Cuts this wizard's CURRENT velocity by slow_amount once, right here at
## the moment of catching it - 1.0 (the default) zeroes it outright, so it
## holds perfectly still, "remains in place"; lower values leave some of
## whatever it was already doing to carry through, more of a slow-motion
## catch than a hard stop. From here on, how much gravity keeps acting on
## it each frame while frozen ALSO scales with slow_amount - see the
## _physics_process() early-out above - so a partial slow_amount reads as
## genuinely slowed motion throughout the freeze, not just at the instant
## it started. Jump/dive/casting/hold-based abilities are locked out
## entirely regardless of slow_amount, but LEFT/RIGHT movement input is NOT -
## see that same _physics_process() early-out, which reads it and moves at
## SPEED * (1.0 - slow_amount). duration is passed in far larger than any
## zone could actually live (see IceZone._NEVER_EXPIRES) - the zone itself
## calls thaw() explicitly the moment this wizard actually leaves it (or the
## zone itself despawns), rather than this ever timing out on its own;
## overlay_scene (if assigned on the IceAbility that owns this zone - see
## IceAbility.frozen_wizard_overlay) is spawned as a child for as long as
## that lasts, same opt-in vfx shape used everywhere else in this file. Null
## skips spawning anything.
func freeze_in_place(duration: float, slow_amount: float, overlay_scene: PackedScene = null) -> void:
	_is_frozen = true
	_frozen_remaining = duration
	_frozen_slow_amount = clampf(slow_amount, 0.0, 1.0)
	velocity *= (1.0 - _frozen_slow_amount)
	_spawn_frozen_overlay(overlay_scene)


## Ends a freeze early - either from freeze_in_place()'s own countdown
## reaching 0 in the _physics_process() early-out (a natural thaw) or from
## IceZone._on_body_exited() the moment this wizard actually leaves the zone,
## or from another shield's deflect touching this wizard while it's still
## frozen (see deflection_shield.gd's _on_body_entered(), which calls this
## on anything with a thaw() method it hits). Does NOT zero velocity -
## whatever velocity this wizard already had the instant it thaws (its
## slowed velocity, still being acted on by scaled-down gravity the whole
## time it was frozen - see the _physics_process() early-out) just keeps
## going from here, so a wizard caught mid-fall or mid-knockback resumes
## that same fall/knockback at full strength once thawed instead of getting
## reset to a dead stop first. An earlier version zeroed velocity
## unconditionally here, which read as the zone deleting momentum outright
## (a hard catch-and-drop) rather than just slowing time locally - see
## Ball.thaw()'s doc comment for the same reasoning on the ball side. No-op
## if this wizard wasn't actually frozen (guards against _on_body_entered()
## calling this unconditionally on every wizard any shield ever touches) -
## gated on _is_frozen rather than _frozen_remaining, since the
## natural-timeout call from _physics_process() happens the same frame
## _frozen_remaining already reads <= 0 (see _is_frozen's doc comment for why
## that distinction matters).
func thaw() -> void:
	if not _is_frozen:
		return
	_is_frozen = false
	_frozen_remaining = 0.0
	_frozen_slow_amount = 0.0
	_clear_frozen_overlay()


func _spawn_frozen_overlay(overlay_scene: PackedScene) -> void:
	_clear_frozen_overlay()
	if not is_instance_valid(overlay_scene):
		return
	var overlay: Node2D = overlay_scene.instantiate()
	add_child(overlay)
	_frozen_overlay = overlay


## Ends this wizard's current frozen overlay (if any) - called both by
## thaw() (this wizard just exited the ice ability) and by
## _spawn_frozen_overlay() clearing out whatever was there before attaching
## a fresh one. Plays the overlay's own one-shot "fade" clip first, if it
## has one (VFX/Frozen_Wizard.tscn's own AnimationPlayer - guarded with
## has_animation(), same safe-before-the-clip-exists shape
## deflection_shield.gd's start_fade() already uses), so the overlay
## visibly fades out instead of popping off instantly the moment this
## wizard leaves the zone. Reads _frozen_overlay into a local and clears the
## field immediately (rather than after the fade finishes), so a fresh
## freeze that re-spawns a new overlay while this one is still fading never
## clobbers or double-frees it - the old overlay just finishes fading and
## frees itself independently, fire-and-forget, same pattern
## IceZone._despawn()'s own await already uses in this project.
func _clear_frozen_overlay() -> void:
	var overlay := _frozen_overlay
	_frozen_overlay = null
	if not is_instance_valid(overlay):
		return
	var anim := overlay.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim != null and anim.has_animation("fade"):
		anim.play("fade")
		await anim.animation_finished
	if is_instance_valid(overlay):
		overlay.queue_free()


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


## Double-tap-and-hold-to-meteor: double-tapping Down and continuing to hold
## it on that second press turns this wizard into a fast-falling meteor for
## as long as Down stays held (see _start_meteor()/_cancel_meteor()/
## _land_meteor()) - own separate double-tap tracking from every other
## ability's, same shape _update_blink()/_update_ice_zone() already use. No-op
## unless the current ability is a MeteorAbility, same "costs nothing for
## classes that don't use it" convention every other _update_*() function
## here follows. Runs every physics frame regardless of class.
func _update_meteor(delta: float) -> void:
	var ability := _current_ability() as MeteorAbility
	if ability == null:
		# Not this class's ability - nothing to track, and nothing should be
		# left armed (or mid-fall) if the class ever changed mid-game.
		_meteor_down_tap_window_remaining = 0.0
		if _is_meteor:
			_cancel_meteor()
		return

	if _meteor_down_tap_window_remaining > 0.0:
		_meteor_down_tap_window_remaining = maxf(_meteor_down_tap_window_remaining - delta, 0.0)

	if not _is_meteor:
		if Input.is_action_just_pressed(_action_down):
			if _meteor_down_tap_window_remaining > 0.0 and not is_on_floor():
				# Second tap, still airborne, and it's a HOLD (Down is still
				# down this same frame it was just pressed) - the "double tap
				# and hold on the second tap" gesture. Grounded is excluded
				# outright: there's no fall left to speed up standing on the
				# floor already, so a double-tap-hold there just falls through
				# to the ordinary dash instead (see that block's own
				# `and not _is_meteor` guard, which only matters once this IS
				# true - it never blocks the tap that gets it there).
				_meteor_down_tap_window_remaining = 0.0
				# Needs at least one full tier banked to activate at all -
				# see MeteorAbility's own doc comment - spent right here, the
				# instant the gesture registers, same "pay at commit, not
				# refunded on cancel" rule every other ability in this file
				# follows (see _try_blink()/_cast_ice_zone()).
				if ability.strikes_per_tier > 0 and strikes >= ability.strikes_per_tier:
					strikes -= ability.strikes_per_tier
					_update_strike_gauge()
					_start_meteor(ability)
				else:
					# TEMP DEBUG - remove once meteor strikes are confirmed working.
					print("[DEBUG seat %d] meteor denied - only %d strikes banked, need %d" % [seat, strikes, ability.strikes_per_tier])
			else:
				_meteor_down_tap_window_remaining = ability.double_tap_window
		return

	# Deliberately nothing else here - once a fall actually starts, it's
	# uninterruptible by input on purpose (an earlier version cancelled early
	# on releasing Down, same as Growth's hold ending the instant Up
	# releases; that's gone now). The ONLY way out early is an external
	# interrupt like a freeze catching this wizard mid-plunge (see
	# _physics_process()'s frozen branch, which still calls _cancel_meteor()
	# itself). Landing is handled separately, from _physics_process()'s own
	# airborne-to-grounded transition (see _land_meteor()), not from here.


## Begins a meteor fall: forces this wizard into a straight-down plunge (see
## _physics_process()'s own `if _is_meteor:` override, right before
## move_and_slide()), attaches ability.meteor_fall_vfx_scene for the ride,
## and reparents this wizard's own standing barrier onto him for the same
## duration (see _attach_meteor_barrier()) - that barrier, not a separate
## hitbox, is what actually does the fall's hitting now. Free to call - no
## strike cost to become a meteor at all; see MeteorAbility's own doc
## comment for why.
func _start_meteor(ability: MeteorAbility) -> void:
	_is_meteor = true
	velocity = Vector2(0.0, ability.fall_speed)
	_attach_meteor_barrier(ability)
	_spawn_meteor_vfx(ability)


## Ends a meteor fall WITHOUT any landing effect - only ever an external
## interrupt now, like a freeze catching this wizard mid-plunge (see
## _physics_process()'s frozen branch) - see _update_meteor()'s own doc
## comment for why input can no longer get here at all. Normal gravity/
## movement resumes on its own the very next frame simply because
## _is_meteor's override in _physics_process() no longer fires; nothing here
## needs to touch velocity itself.
func _cancel_meteor() -> void:
	_is_meteor = false
	_end_meteor_vfx(_current_ability() as MeteorAbility)
	_end_meteor_barrier()


## Called from _physics_process()'s own airborne-to-grounded transition the
## instant a meteor fall actually reaches the floor - the ONE place this
## fires, never from _update_meteor() itself. Reads (rather than spends,
## unless the tier-2 payoff actually triggers) whatever strikes are
## CURRENTLY banked to decide which of the two landings plays - see
## MeteorAbility's own doc comment for the full reasoning. A normal landing
## (fewer than 2 tiers banked, or the tier2_meteor_form_enabled knob off)
## runs the usual end-of-fall cleanup right here, same as _cancel_meteor()
## does; a qualifying tier-2 landing deliberately skips all of that instead -
## see the branch below.
func _land_meteor() -> void:
	_is_meteor = false
	var ability := _current_ability() as MeteorAbility
	if ability == null:
		_end_meteor_vfx(null)
		_end_meteor_barrier()
		return

	var tiers_banked := 0
	if ability.strikes_per_tier > 0:
		tiers_banked = clampi(strikes / ability.strikes_per_tier, 0, ability.max_tiers)

	if tiers_banked >= 2 and ability.tier2_meteor_form_enabled:
		# Tier-2 payoff: the fall just keeps going instead of ending here -
		# _meteor_vfx and _meteor_barrier are deliberately left untouched
		# (still attached/live exactly as the fall itself set them up, the
		# barrier still dealing its usual boosted deflection) for
		# tier2_meteor_form_duration more seconds via
		# _meteor_form_lock_remaining, which _physics_process() ticks down
		# and which runs the normal end-of-fall cleanup on its own once it
		# expires (see _end_meteor_form_lingering()). Consumes EVERY
		# currently-banked strike outright rather than just tiers_banked *
		# strikes_per_tier - unlike every other spend in this file, tier 2
		# is all-or-nothing, no partial-tier remainder banked for next time.
		strikes = 0
		_update_strike_gauge()
		_meteor_form_lock_remaining = ability.tier2_meteor_form_duration
		# TEMP DEBUG - remove once meteor strikes are confirmed working.
		print("[DEBUG seat %d] meteor tier-2 landing - barrier extended %.1fs, all charges consumed" % [seat, ability.tier2_meteor_form_duration])
	else:
		_end_meteor_vfx(ability)
		_end_meteor_barrier()
		_play_dropped_vfx(ability.meteor_lands_vfx_scene, ability.meteor_lands_vfx_lifetime)


## Attaches ability.meteor_fall_vfx_scene (if assigned) directly to this
## wizard for the duration of the fall - see _meteor_vfx's own doc comment
## for why it's parented to the wizard itself rather than anywhere else.
## Plays the instanced scene's AnimationPlayer "hold" clip if present, same
## convention IceZone's self_vfx_scene already uses.
func _spawn_meteor_vfx(ability: MeteorAbility) -> void:
	_clear_meteor_vfx()
	if not is_instance_valid(ability.meteor_fall_vfx_scene):
		return
	var vfx: Node2D = ability.meteor_fall_vfx_scene.instantiate()
	add_child(vfx)
	var anim := vfx.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim != null and anim.has_animation("hold"):
		anim.play("hold")
	_meteor_vfx = vfx


## Stops and removes whatever _spawn_meteor_vfx() attached - called by both
## _cancel_meteor() and _land_meteor(), same "the fall is over, one way or
## another" cleanup either path needs.
func _clear_meteor_vfx() -> void:
	if not is_instance_valid(_meteor_vfx):
		_meteor_vfx = null
		return
	var anim := _meteor_vfx.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim != null:
		anim.stop()
	_meteor_vfx.queue_free()
	_meteor_vfx = null


## Ends the fall's attached vfx via ability.meteor_fall_vfx_despawn_delay
## instead of freeing it instantly - called by both _cancel_meteor() and
## _land_meteor() now, in place of a direct _clear_meteor_vfx() call (that
## function still exists and still does the instant version - _spawn_
## meteor_vfx() above still calls it directly to clear out a stale instance
## before attaching a fresh one, no delay wanted there). Plays an "end" or
## "fade" outro clip on the vfx's own AnimationPlayer first if either exists
## (same has_animation() opt-in the "hold" clip already uses), then waits out
## the delay before handing off to _clear_meteor_vfx() for the actual
## queue_free(). ability may be null (no ability resolvable when the fall
## ended, shouldn't normally happen) - falls back to the old instant clear in
## that case rather than waiting forever.
func _end_meteor_vfx(ability: MeteorAbility) -> void:
	if not is_instance_valid(_meteor_vfx):
		_meteor_vfx = null
		return
	if ability == null:
		_clear_meteor_vfx()
		return
	var vfx := _meteor_vfx
	var anim := vfx.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim != null and anim.has_animation("end"):
		anim.play("end")
	elif anim != null and anim.has_animation("fade"):
		anim.play("fade")
	if ability.meteor_fall_vfx_despawn_delay > 0.0:
		await get_tree().create_timer(ability.meteor_fall_vfx_despawn_delay).timeout
	# _meteor_vfx may already have moved on to a fresh instance (a new fall
	# started mid-wait) - only clear it here if it's still the same one this
	# call started waiting on, so we never free out from under a later fall.
	if _meteor_vfx == vfx:
		_clear_meteor_vfx()


## Drops ability's meteor_lands_vfx_scene (a plain, sub-tier-2 landing - see
## _land_meteor()) at this wizard's CURRENT position and frees it after
## lifetime (meteor_lands_vfx_lifetime) seconds - a manual, explicit knob
## rather than waiting on the scene's own AnimatedSprite2D.animation_finished,
## which only ever matched whatever frame count/FPS the art happened to be
## authored with and had no way to account for SFX outlasting the sprite
## animation. Same drop-and-forget shape _spawn_blink_vfx() already uses for
## Blink's own teleport vfx, minus the left/right flip (a landing has no
## directional equivalent). Safe no-op if scene is null, same opt-in
## convention every vfx_scene field here follows. Generic over `scene`/
## `lifetime` rather than hardcoded to meteor_lands_vfx_scene specifically in
## case a future landing-style vfx ever wants the same drop-and-forget
## treatment.
func _play_dropped_vfx(scene: PackedScene, lifetime: float) -> void:
	if not is_instance_valid(scene):
		return
	var vfx: Node2D = scene.instantiate()
	vfx.global_position = global_position
	get_tree().current_scene.add_child(vfx)
	var anim := vfx.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if anim != null:
		anim.play()
	if lifetime > 0.0:
		await get_tree().create_timer(lifetime).timeout
	if is_instance_valid(vfx):
		vfx.queue_free()


## Ignites a ball the ATTACHED meteor barrier just touched - connected to the
## barrier's own Area2D.body_entered signal by _attach_meteor_barrier() for
## as long as it's riding along, on top of (not instead of) that Area2D's
## own built-in deflection_shield.gd handling of the same signal (which
## independently sets the ball's new velocity/plays sfx/emits `deflected` -
## Godot signals fan out to every connected listener, so both just run off
## the one touch with no conflict). Kept as its own separate listener rather
## than folded into deflection_shield.gd itself since ignite-on-touch is a
## Meteor-only flourish, not something every class's shield should do.
## Purely cosmetic/status-effect, opt-in like every other vfx_scene field
## here - a no-op if body isn't a ball or doesn't support ignite().
func _on_meteor_barrier_touched_ball(body: Node2D, ability: MeteorAbility) -> void:
	if not is_instance_valid(body) or not body.is_in_group("ball"):
		return
	if body.has_method("ignite"):
		body.ignite(ability.burn_duration, ability.burning_ball_vfx_scene)


## Generic external-impact knockback, callable on ANY wizard by anything that
## hits it - currently unused (an earlier version of Meteor had its own
## invisible hitbox that called this on contact; that's gone now, replaced
## by the attached barrier's own deflection), but exposed as a public,
## duck-typed method (like freeze_in_place()/thaw())
## rather than kept private, so any future ability that wants to knock
## another wizard around can reuse it too. Same "hard jolt, eased back down
## by a Tween" shape _apply_ice_knockback() already uses for a caster's own
## recoil off their own cast, generalized here to a full 2D `jolt` (ice's own
## recoil is always horizontal-only, so it never needed that) - and reuses
## _ice_input_lock_remaining for the same reason _apply_ice_knockback() needs
## it: without briefly holding off normal LEFT/RIGHT input handling, whatever
## direction the STRUCK wizard happens to be holding themselves would
## instantly overwrite this jolt the very same physics frame. The name is
## ice-specific from when this project only had one kind of knockback; what
## it actually DOES (suppress LEFT/RIGHT input reading for a bit) is exactly
## as useful here, so this reuses the field rather than introducing a second
## one that would just be the same lock under a different name.
func apply_knockback(jolt: Vector2, lock_time: float = 0.2) -> void:
	velocity = jolt
	_ice_input_lock_remaining = maxf(_ice_input_lock_remaining, lock_time)
	if lock_time <= 0.0:
		return
	var tween := create_tween()
	tween.tween_method(_set_knockback_velocity, jolt, Vector2.ZERO, lock_time).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## Tween callback for apply_knockback() - Tween.tween_method() needs an
## actual callable to drive, it can't write to the `velocity` property
## directly, same reason _set_ice_knockback_velocity_x() exists.
func _set_knockback_velocity(value: Vector2) -> void:
	velocity = value


## Fall-speed lookup for _physics_process()'s own `if _is_meteor:` override -
## pulled into its own function so that override reads as a single line
## rather than repeating the `_current_ability() as MeteorAbility` cast
## inline. Should never actually see ability == null in practice (nothing
## sets _is_meteor true without a live MeteorAbility to read from - see
## _start_meteor()), but returns a harmless 0.0 rather than crashing if that
## invariant is ever broken.
func _meteor_fall_speed() -> float:
	var ability := _current_ability() as MeteorAbility
	return ability.fall_speed if ability != null else 0.0
