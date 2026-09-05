extends Area2D
class_name DeflectionShield

## Shared deflection-shield behavior for every wizard class - previously
## four separate, nearly-identical scripts (DeflectionShield1-4, one per
## class, differing only in class_name). Every class's shield scene now
## points at this single script instead; whatever makes one class's shield
## feel different (deflection force, sfx stream, animations) still lives on
## that class's own scene, not here.
##
## Emits `deflected` on every successful ball hit - wizard.gd listens for
## this on whatever instance it just spawned (see create_new_instance()) to
## grow that wizard's banked strike count. Strikes are core, shared
## infrastructure now: every class's shield reports them the same way, even
## though only some classes' abilities currently do anything with the count
## (see GrowthAbility).

signal deflected

@export var deflection_force: float = 1200.0
@onready var deflect_sfx: AudioStreamPlayer2D = $"../deflect_SFX"
@onready var animation_player: AnimationPlayer = $"../AnimationPlayer"

## True while this shield is a "trap" mid-formation (see wizard.gd's
## _update_ice_trap()/_set_trap_pass_through()) - only ever set by an
## IceAbility hold today, but lives here rather than gated behind a class
## check so any future ability could reuse the same "let balls fly through,
## don't deflect" behavior without this shared script needing to know who's
## asking. There's nothing here to physically block a ball anyway - this
## Area2D is a sensor, not a solid body - so this flag only stops the
## SCRIPTED deflection (new velocity, sfx, animation, the `deflected`
## signal) from firing on top of that; a ball already sails straight through
## whether pass_through is true or not, this just decides whether it also
## gets bounced.
var pass_through: bool = false

var _freeze_queue = []
var _is_processing_freeze = false

## Groups every barrier's Area2D by "barrier", the same way "ball"/"wizard"
## already work everywhere else in this project - not read by anything
## currently (an earlier version of Meteor looked barriers up this way to
## knock them around on contact; that's gone now, replaced by attaching the
## real barrier to the falling wizard instead - see wizard.gd's
## _attach_meteor_barrier()), kept as cheap, reusable infra for whatever
## wants to find every standing barrier in the scene next.
func _ready():
	add_to_group("barrier")

func _on_body_entered(body):
	# A frozen target (ball or wizard - see their freeze_in_place()/thaw())
	# thaws the instant ANY shield touches it, trap-forming or not - that's
	# the "until hit by another spell" half of the ice trap's freeze/thaw
	# doc comment (see ice_ability.gd). Checked before the pass_through
	# early-out below since thawing is never skipped, only the deflection
	# itself is.
	if body.is_in_group("wizard") and body.has_method("thaw"):
		body.thaw()
	if pass_through:
		return
	if body.is_in_group("ball"):
		var direction = (body.global_position - global_position).normalized()
		deflect_ball(body, direction)

func deflect_ball(ball, direction):
	if ball is RigidBody2D:
		# Thaw before applying the new deflect velocity, not after - a
		# frozen ball caught by a deflect should fly off with THIS impact's
		# velocity, never its stale pre-freeze one. No-op if it wasn't
		# frozen to begin with (see Ball.thaw()).
		if ball.has_method("thaw"):
			ball.thaw()
		var new_velocity = direction * deflection_force
		ball.linear_velocity = new_velocity
		deflect_sfx.pitch_scale = randf_range(0.9, 1.1)
		deflect_sfx.play()
		# Deferred, not called directly: deflect_ball() runs from
		# _on_body_entered(), which fires while THIS Area2D's physics state
		# is still locked mid-step. The "fade" clip (see start_fade()) has
		# its own tracks/../Area2D:monitoring track, so stopping/restarting
		# playback while fade happens to be the current animation can make
		# the AnimationPlayer try to reapply that track's value right away -
		# i.e. call Area2D.set_monitoring() - while still locked, which
		# Godot refuses ("Function blocked during in/out signal. Use
		# set_deferred"). Deferring both calls to the next idle frame avoids
		# that entirely without changing what's visible: still stop-then-
		# play, just a fraction of a frame later.
		animation_player.call_deferred("stop")
		animation_player.call_deferred("play", "deflect")
		deflected.emit()

## Shoves this barrier's position `distance` pixels away from wherever it was
## hit from, eased back to a stop over a short fixed duration - not called by
## anything currently (an earlier version of Meteor's landing explosion used
## this to knock barriers around; both that explosion and the separate
## falling hitbox that could shove a barrier via this are gone now), kept as
## reusable infra since a barrier has no velocity to speak of - this Area2D
## is a sensor, not a solid body, and its parent (the shield root every
## class's spell_N.tscn shares - see create_new_instance() in wizard.gd)
## never moves on its own once cast - so unlike a wizard/ball knockback (a
## hard, instant velocity - see wizard.gd's apply_knockback()/deflection_
## shield.gd's own deflect_ball()) this is a one-shot Tween straight to a new
## POSITION instead. `direction` is expected already normalized; this
## doesn't defend against a zero vector - any future caller should derive it
## from an actual impact/landing point that's never exactly on top of this
## barrier.
func knockback(direction: Vector2, distance: float) -> void:
	var barrier := get_parent()
	if barrier == null:
		return
	var target: Vector2 = barrier.global_position + direction * distance
	var tween := create_tween()
	tween.tween_property(barrier, "global_position", target, 0.35).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


## Politely used to wait for whatever else was already playing (e.g. a
## "deflect" bounce) to finish on its own before cutting over to "fade" -
## dropped because that wait had no timeout: every fresh "deflect" restarts
## the SAME clip from 0 without ever completing it, so a barrier getting hit
## repeatedly (exactly what an attached meteor barrier riding along a fall/
## lingering for real seconds is likely to do) could keep this stuck
## awaiting an animation_finished that would never come - the barrier never
## fades, never frees, and just rides along on the wizard indefinitely.
## Stopping outright before playing "fade" (same "always interrupt whatever
## was playing" rule deflect_ball() already follows for its own "deflect")
## guarantees this actually starts the instant it's called instead.
func start_fade() -> void:
	animation_player.stop()
	if animation_player.has_animation("fade"):
		animation_player.play("fade")
		await animation_player.animation_finished
	queue_free()

func freeze_frame(duration := 0.1):
	_freeze_queue.append(duration)
	if not _is_processing_freeze:
		_process_next_freeze()

func _process_next_freeze():
	if _freeze_queue.size() == 0:
		_is_processing_freeze = false
		return
	_is_processing_freeze = true
	var duration = _freeze_queue.pop_front()
	var original_time_scale = Engine.time_scale
	Engine.time_scale = 0.1
	var start_time = Time.get_ticks_msec()
	var end_time = start_time + int(duration * 1000)
	while Time.get_ticks_msec() < end_time:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	_process_next_freeze()
