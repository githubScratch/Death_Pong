# Ball.gd - Modified to respond better to force changes
extends RigidBody2D

class_name Ball

# Properties
@export var min_speed: float = 200.0
@export var max_speed: float = 1000.0

## Replaces max_speed as this ball's speed cap for as long as it's burning
## (see ignite()/_is_burning below) - a flat replacement, not added on top
## of max_speed, so raise or lower it independently of whatever this
## particular ball scene's own max_speed happens to be. A burning ball is
## meant to read as more dangerous/harder to control, so the intent is for
## this to sit above max_speed, but nothing enforces that ordering - it's
## just whatever the cap becomes while burning, same "one flat number" shape
## max_speed itself already is.
@export var burning_max_speed: float = 2400.0

var last_applied_force: Vector2 = Vector2.ZERO
@onready var sparks_player: AnimationPlayer = $SparksPlayer

@export var stretch_factor: float = 2.5  # How much the ball stretches
@export var min_velocity_for_stretch: float = 200.0  # Minimum velocity to start stretching
@export var max_stretch: float = 4.0  # Maximum stretch multiplier

var _original_scale: Vector2
var _velocity: Vector2 = Vector2.ZERO
var _previous_position: Vector2

## True while this ball is inside an Ice Zone (see PLAYERS/ice_zone.gd's
## _on_body_entered()) - mirrors Wizard's own freeze_in_place()/thaw() with
## the RigidBody2D-appropriate version below. Unlike the wizard's
## CharacterBody2D - fully script-driven via move_and_slide(), so simply not
## calling that each frame is enough to hold it still - the physics engine
## keeps integrating THIS body's gravity/collision response every physics
## step no matter what _physics_process() does or doesn't touch, so holding
## still here also needs gravity_scale itself dialed down, not just velocity
## zeroed once.
##
## Deliberately a SEPARATE flag from _frozen_remaining (see Wizard's own
## _is_frozen for the full reasoning) - the natural-timeout call to thaw()
## below happens the same frame _frozen_remaining is driven to <= 0, so
## thaw()'s own "was this even frozen" guard would otherwise see
## _frozen_remaining already at 0 and skip its own cleanup, silently leaving
## _frozen_overlay attached to the ball forever.
var _is_frozen: bool = false
var _frozen_remaining: float = 0.0
var _frozen_slow_amount: float = 0.0
var _frozen_base_gravity_scale: float = 0.0
var _frozen_overlay: Node2D = null

## True for as long as this ball is burning (see ignite()/
## _clear_burning_overlay() below) - the one gameplay effect burning
## actually has: _physics_process()'s own speed cap uses burning_max_speed
## instead of max_speed while this is true. Tracked as its own flag rather
## than just checking `is_instance_valid(_burning_overlay)` because
## burning_ball_vfx_scene (the overlay) is opt-in/nullable like every other
## vfx_scene field in this project - a class with no overlay art assigned
## yet should still get the speed-cap effect, same "the mechanic works even
## with no art" convention _spawn_frozen_overlay()'s own opt-in shape
## already follows. Set the instant ignite() is called (regardless of
## whether overlay_scene is valid), cleared by _clear_burning_overlay() -
## same lifetime as the overlay itself when there is one.
var _is_burning: bool = false

## The currently-attached "on fire" overlay, if any - see ignite()/
## _clear_burning_overlay() below. Independent of _frozen_overlay above in
## the same way _is_frozen/_is_burning are two separate flags - a frozen
## ball and a burning ball are unrelated states that could in principle
## overlap.
var _burning_overlay: Node2D = null

@onready var wall_impact: AudioStreamPlayer2D = $"../wall_impact"
var audio_pool = []
@export var pool_size = 3
@export var min_velocity_for_sound = 50.0  # Minimum velocity to play sound

## Hit Stop
##
## A brief, full-game freeze (SceneTree.paused - a true stop, not a
## slow-motion via Engine.time_scale) the instant a ball is struck by a
## wizard's deflection shield ("barrier" - see deflection_shield.gd, which
## groups its own Area2D under "barrier"), giving players a beat to
## actually register whatever effect just landed instead of it flashing
## past mid-bounce. Deliberately NOT triggered by ordinary paddle/wall/brick
## contact (see _on_sfx_area_body_entered() below) - those happen far too
## often for a freeze to read as anything but the game stuttering; a shield
## deflect is comparatively rare and already the moment worth a beat of
## emphasis. See trigger_hitstop()/_do_hitstop() below for the mechanism,
## and deflection_shield.gd's deflect_ball() for the one place it's
## actually triggered from.
##
## hitstop_cooldown exists because a ball can clip more than one barrier in
## quick succession - without a cooldown, each deflect would fire its own
## 0.05s freeze back to back, which reads exactly like the game hanging
## rather than a series of readable little punches. The cooldown measures
## from the START of the previous hitstop, so it can never be defeated by
## hits landing faster than it can refire.
##
## _last_hitstop_msec/_hitstop_active are STATIC - shared across every Ball
## instance, not per-instance state - deliberately, because this project
## supports more than one ball on screen at once (see ball_big.tscn,
## Yonder's enlarged ball, and paddle.gd's own
## get_tree().get_nodes_in_group("ball") handling). A per-instance cooldown
## would let two different balls each freely trigger their own hitstop
## within the same fraction of a second - exactly the "game freezes during
## a crazy rebound" failure this feature exists to prevent, just spread
## across two RigidBody2Ds instead of one. One shared clock means only one
## hitstop can ever be in effect or in cooldown game-wide, no matter which
## ball (or how many) caused it.
##
## Uses Time.get_ticks_msec() - real, unscaled, wall-clock time that keeps
## advancing even while the tree is paused (same clock deflection_shield.gd's
## own freeze_frame() already reads) - rather than anything _process-driven,
## since the whole point of a hitstop is that normal processing is paused
## for part of it.
@export_group("Hit Stop")
## How long the whole game freezes for on a hit, in seconds. 0 disables
## hitstop entirely.
@export_range(0.0, 0.5, 0.01, "suffix:s") var hitstop_duration: float = 0.05
## Minimum real time between the start of one hitstop and the next,
## game-wide - see the doc comment above for why this is shared rather than
## per-ball.
@export_range(0.0, 2.0, 0.05, "suffix:s") var hitstop_cooldown: float = 0.5

static var _last_hitstop_msec: int = -1000000
static var _hitstop_active: bool = false

## Call this any time THIS ball is struck. Silently does nothing if
## hitstop_duration is 0, a hitstop is already in progress, or the last one
## started less than hitstop_cooldown ago - see the class doc comment above.
func trigger_hitstop() -> void:
	if hitstop_duration <= 0.0 or _hitstop_active:
		return
	var now := Time.get_ticks_msec()
	if now - _last_hitstop_msec < int(hitstop_cooldown * 1000):
		return
	_last_hitstop_msec = now
	_do_hitstop()

func _do_hitstop() -> void:
	_hitstop_active = true
	get_tree().paused = true
	# process_always defaults to true for SceneTree timers - this one keeps
	# counting down in real time despite the pause above, which is exactly
	# what unpauses the game again a moment later instead of freezing it for
	# good.
	await get_tree().create_timer(hitstop_duration).timeout
	get_tree().paused = false
	_hitstop_active = false

func _ready():
	add_to_group("ball")
	for i in range(pool_size):
		var player = AudioStreamPlayer.new()
		player.stream = wall_impact
		add_child(player)
		audio_pool.append(player)
	_original_scale = scale
	_previous_position = global_position
	
	# Physics setup
	contact_monitor = true
	max_contacts_reported = 4
	self.gravity_scale = gravity_scale
	self.linear_damp = linear_damp
	
	# Initial movement
	var initial_direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	apply_central_impulse(initial_direction * min_speed)
	
func _physics_process(_delta):
	if _is_frozen:
		_frozen_remaining -= _delta
		# No per-frame velocity damping here on top of that - freeze_in_place()
		# already cut linear_velocity/angular_velocity ONCE, at the moment of
		# catching this ball, and scaled gravity_scale down for the duration;
		# the physics engine is left to keep integrating normally from there
		# under that already-reduced gravity. Re-damping velocity every frame
		# on top of that (the old behavior) crushed any residual motion back
		# toward zero within a couple physics frames regardless of how
		# partial slow_amount was set to - a slow_amount below 1.0 read as a
		# full freeze anyway. Leaving the engine alone here is what makes a
		# partial slow_amount actually look slowed rather than frozen.
		# Keep this in step with a frozen ball's stationary-or-slowly-moving
		# position so the first frame after thawing doesn't read a huge
		# one-frame jump as velocity and trigger a stretch-effect glitch.
		_previous_position = global_position
		# Belt-and-suspenders alongside freeze_in_place()'s own one-time
		# scale/rotation reset: pin it back to rest EVERY frame this branch
		# runs, not just once at the instant of catching. freeze_in_place()
		# already resets it once, which should be enough on its own - but if
		# anything else this file hasn't accounted for ever touches scale/
		# rotation while _is_frozen is true, holding it here every frame
		# means a frozen ball can never visibly drift away from its correct
		# rest size/orientation for the rest of the freeze, no matter what.
		scale = _original_scale
		rotation = 0.0
		if _frozen_remaining <= 0.0:
			thaw()
		return

	_velocity = (global_position - _previous_position) / _delta
	_previous_position = global_position
	
	# Apply stretch effect based on velocity
	if _velocity.length() > min_velocity_for_stretch:
		# Normalize direction
		var direction = _velocity.normalized()
		
		# Calculate stretch along movement direction
		var stretch_amount = clamp(_velocity.length() * stretch_factor / 1000.0, 1.0, max_stretch)
		
		# Create a basis for the transformation
		var x_axis = direction
		var y_axis = Vector2(-direction.y, direction.x)  # Perpendicular to direction
		
		# Apply stretch - expand in direction of movement, compress in perpendicular direction
		var new_scale_x = _original_scale.x * stretch_amount
		var new_scale_y = _original_scale.y / sqrt(stretch_amount)  # Inverse square root for volume preservation
		
		# Update the scale and rotation
		scale = Vector2(new_scale_x, new_scale_y)
		rotation = direction.angle()
	else:
		# Reset to original scale when velocity is low
		scale = _original_scale
		rotation = 0

	# Cap maximum speed - burning_max_speed replaces the normal cap outright
	# for as long as _is_burning is true (see that flag's own doc comment),
	# rather than being added on top of it.
	var effective_max_speed := burning_max_speed if _is_burning else max_speed
	if linear_velocity.length() > effective_max_speed:
		linear_velocity = linear_velocity.normalized() * effective_max_speed


func apply_deflection(force_vector):
	# Store for debugging
	last_applied_force = force_vector

	# Stop current movement
	linear_velocity = Vector2.ZERO
	
	# Apply the force directly
	apply_central_force(force_vector * 100)  # Multiply by 100 to amplify the effect
	
	# Alternative: Try impulse with higher value
	apply_central_impulse(force_vector)

	
	# Create visual effect
	create_impact_effect()

##debug this to ensure its working
func create_impact_effect():
	var original_color = modulate
	modulate = Color(0.2, 0.2, 0.2, 1.0)
	
	var tween = create_tween()
	tween.tween_property(self, "modulate", original_color, 0.4)

func _on_sfx_area_body_entered(body):  # Changed function name to match signal
	sparks_player.stop()
	sparks_player.play("sparks")
	if body is StaticBody2D and linear_velocity.length() > min_velocity_for_sound:
		# Play sound with volume based on impact velocity
		var impact_force = min(linear_velocity.length() / 1000.0, 1.0)
		play_collision_sound(impact_force)  # Pass the volume scale, not the audio player
	if body is RigidBody2D and linear_velocity.length() > min_velocity_for_sound:

		#var impact_force = min(linear_velocity.length() / 1000.0, 1.0)
		#play_collision_sound(impact_force)  # Pass the volume scale, not the audio player
		if body.is_in_group("brick") and is_instance_valid(body):
			body.hit()
		
func play_collision_sound(volume_scale = 1.0):
	wall_impact.pitch_scale = randf_range(0.9, 1.1)
	wall_impact.play()
	for player in audio_pool:
		if not player.playing:
			player.pitch_scale = randf_range(0.9, 1.1)
			player.volume_db = linear_to_db(volume_scale)
			player.play()
			wall_impact.pitch_scale = randf_range(0.9, 1.1)
			wall_impact.play()
			return
	
	# If all players are busy, use the first one
	audio_pool[0].pitch_scale = randf_range(0.9, 1.1)
	audio_pool[0].volume_db = linear_to_db(volume_scale)
	audio_pool[0].play()


## Called by whichever Ice Zone (PLAYERS/ice_zone.gd) this ball just
## entered. Cuts this ball's CURRENT velocity/spin by slow_amount once,
## right here at the moment of catching it, and scales gravity_scale down
## by the same fraction for the rest of the freeze (gravity_scale rather
## than a per-frame velocity re-damp, since the physics engine integrates a
## RigidBody2D's gravity independent of _physics_process() no matter what
## that function does or doesn't touch - see _physics_process()'s frozen
## branch, which deliberately leaves the engine alone from here on rather
## than fighting it every frame). 1.0 (the default) zeroes velocity/spin
## outright and stops gravity outright, so it holds perfectly still
## ("remains in place"); lower values leave some of its existing motion to
## carry through and keep falling/drifting at a reduced rate for the whole
## freeze, an actual slow-motion catch rather than a hard stop. duration is
## passed in far larger than any zone could actually live (see
## IceZone._NEVER_EXPIRES) - the zone calls thaw() explicitly the moment
## this ball actually leaves it (or the zone itself despawns), rather than
## this ever timing out on its own. overlay_scene (if assigned on the
## IceAbility that owns the zone - see IceAbility.frozen_ball_overlay) is
## spawned as a child for as long as that lasts; null skips spawning
## anything, same opt-in shape used elsewhere in this project.
##
## Accepts (and ignores) a trailing lock_actions_while_frozen parameter a
## ball has no use for - see wizard.gd's own freeze_in_place() for what it
## actually does there. It only exists here so IceZone's shared, duck-typed
## _on_body_entered() can call body.freeze_in_place(...) with one identical
## argument list regardless of whether body is a Ball or a Wizard.
func freeze_in_place(duration: float, slow_amount: float, overlay_scene: PackedScene = null, _lock_actions_while_frozen: bool = true) -> void:
	if not _is_frozen:
		_frozen_base_gravity_scale = gravity_scale
	_is_frozen = true
	_frozen_remaining = duration
	_frozen_slow_amount = clampf(slow_amount, 0.0, 1.0)
	gravity_scale = _frozen_base_gravity_scale * (1.0 - _frozen_slow_amount)
	linear_velocity *= (1.0 - _frozen_slow_amount)
	angular_velocity *= (1.0 - _frozen_slow_amount)
	# _physics_process()'s own `if _is_frozen:` branch returns immediately,
	# before it ever reaches the stretch-effect code further down that
	# ordinarily resets scale/rotation back to rest every frame the ball
	# isn't moving fast - so once frozen, NOTHING touches scale/rotation
	# again for the rest of the freeze; whatever shape the ball happened to
	# be mid-stretch in at the exact instant it got caught (elongated along
	# its direction of travel, squeezed thinner perpendicular to it, tilted
	# to match) just holds there, frozen, for the whole duration. A ball is
	# almost always moving fast enough to be mid-stretch at the moment an
	# Ice Zone catches it, so this fired on nearly every catch - normally
	# invisible since the real stretch only ever lasts a fraction of a
	# second during motion, but held perfectly still for a multi-second
	# freeze it reads as the ball having visibly shrunk/squished, worst on
	# ball_big.tscn (Yonder's enlarged ball) simply because the same
	# percentage squeeze is far more pixels there. Snapping back to rest
	# here, once, at the same moment velocity/spin above get their own
	# one-time freeze treatment, is what _physics_process()'s stretch code
	# would have done itself on the very next unfrozen frame - this just
	# does it before the freeze holds the ball still instead of after.
	scale = _original_scale
	rotation = 0.0
	_spawn_frozen_overlay(overlay_scene)


## Ends a freeze early - either from freeze_in_place()'s own countdown
## reaching 0 in _physics_process() (a natural thaw, i.e. IceZone._despawn())
## or from IceZone._on_body_exited() the moment this ball actually leaves the
## zone, or from another shield's deflect touching this ball while it's
## still frozen (see deflection_shield.gd's deflect_ball(), which calls this
## on any ball it hits before applying its own new velocity). Does NOT zero
## velocity/spin - whatever this ball was already doing the instant it
## thaws (its slowed velocity/spin, still being acted on the whole time by
## the reduced gravity_scale freeze_in_place() set below) just keeps going
## once gravity_scale is restored to normal here: same direction, same spin,
## now accelerating back toward full speed instead of restarting from
## nothing. This is what makes the zone read as a localized, temporary time
## slow rather than a hard catch-and-drop - exiting (or the zone despawning)
## resumes normal time for this ball, it doesn't erase the momentum time was
## already carrying while slowed. An earlier version zeroed both here
## unconditionally, which read as the zone deleting the ball's momentum
## outright rather than just slowing it - "a complete remover of external
## forces" instead of "a temporary slowing magic zone." A deflect overwrites
## this ball's velocity with its own immediately after calling thaw()
## anyway, so what thaw() itself leaves velocity/spin at never actually
## matters on that path. No-op if this ball wasn't actually frozen (guards
## against deflect_ball() calling this unconditionally on every ball it ever
## hits) - gated on _is_frozen rather than _frozen_remaining, since the
## natural-timeout call from _physics_process() happens the same frame
## _frozen_remaining already reads <= 0 (see _is_frozen's doc comment).
func thaw() -> void:
	if not _is_frozen:
		return
	_is_frozen = false
	_frozen_remaining = 0.0
	_frozen_slow_amount = 0.0
	gravity_scale = _frozen_base_gravity_scale
	_clear_frozen_overlay()


## Called by whichever Meteor's attached barrier just touched this ball (see
## wizard.gd's _on_meteor_barrier_touched_ball()) - "Burning_Ball." Used to
## be purely cosmetic (no slow, no lockout of anything, matching
## freeze_in_place()'s gameplay weight); now also raises this ball's speed
## cap to burning_max_speed for as long as it's burning (see _is_burning's
## own doc comment) - a burning ball reads as faster/harder to control, not
## just visually on fire. Restarts the timer and swaps in a fresh overlay
## instance if this ball was already burning rather than stacking a second
## one on top - same "clear whatever was there first" shape
## _spawn_frozen_overlay() already uses. duration <= 0 skips the auto-clear
## entirely, leaving both the overlay AND the raised speed cap in effect
## until something else removes it (nothing does today - see
## MeteorAbility.burn_duration's own doc comment). A null overlay_scene
## still sets _is_burning true and still raises the speed cap - only the
## VISUAL half of this is a no-op then, same opt-in convention every other
## vfx_scene field in this project follows for its own purely-cosmetic half.
func ignite(duration: float, overlay_scene: PackedScene) -> void:
	_clear_burning_overlay()
	_is_burning = true
	if not is_instance_valid(overlay_scene):
		return
	var overlay: Node2D = overlay_scene.instantiate()
	add_child(overlay)
	_burning_overlay = overlay
	if duration <= 0.0:
		return
	await get_tree().create_timer(duration).timeout
	# Only clear if THIS call's overlay is still the live one - a second
	# ignite() re-lighting the ball while this timer was still counting down
	# already cleared and replaced it (see _clear_burning_overlay() below),
	# so this stale timer firing later must not reach in and free the NEW
	# overlay out from under it.
	if _burning_overlay == overlay:
		_clear_burning_overlay()


## Ends this ball's current burning overlay (if any) - called both by a fresh
## ignite() clearing out whatever was there before attaching a new instance,
## and by ignite()'s own duration timer once burn_duration elapses. Plays the
## overlay's one-shot "fade" clip first if it has one, same safe-before-the-
## clip-exists shape _clear_frozen_overlay() already uses just above. Also
## clears _is_burning - harmless when this runs from the TOP of ignite()
## (that call sets it true again immediately after, same frame, before
## anything else can read it), and what actually ends the raised speed cap
## when this runs from the duration timer instead.
func _clear_burning_overlay() -> void:
	var overlay := _burning_overlay
	_burning_overlay = null
	_is_burning = false
	if not is_instance_valid(overlay):
		return
	var anim := overlay.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if anim != null and anim.has_animation("fade"):
		anim.play("fade")
		await anim.animation_finished
	if is_instance_valid(overlay):
		overlay.queue_free()


func _spawn_frozen_overlay(overlay_scene: PackedScene) -> void:
	_clear_frozen_overlay()
	if not is_instance_valid(overlay_scene):
		return
	var overlay: Node2D = overlay_scene.instantiate()
	add_child(overlay)
	_frozen_overlay = overlay


## Ends this ball's current frozen overlay (if any) - called both by thaw()
## (this ball just exited the ice ability) and by _spawn_frozen_overlay()
## clearing out whatever was there before attaching a fresh one. Plays the
## overlay's own one-shot "fade" clip first, if it has one (VFX/Frozen_Ball.
## tscn's own AnimationPlayer - guarded with has_animation(), same
## safe-before-the-clip-exists shape deflection_shield.gd's start_fade()
## already uses), so the overlay visibly fades out instead of popping off
## instantly the moment this ball leaves the zone. Reads _frozen_overlay
## into a local and clears the field immediately (rather than after the
## fade finishes), so a fresh freeze that re-spawns a new overlay while this
## one is still fading never clobbers or double-frees it - the old overlay
## just finishes fading and frees itself independently, fire-and-forget,
## same pattern IceZone._despawn()'s own await already uses in this project.
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
