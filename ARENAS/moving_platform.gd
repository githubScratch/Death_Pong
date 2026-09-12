extends StaticBody2D
class_name MovingPlatform

## Lets this platform's own AnimationPlayer keep driving its position exactly
## as authored (see arena.tscn's "Platforms" AnimationPlayer / "platforms"
## animation - Arena/Left_Plat and Arena/Right_Plat's position keyframes)
## for most of a match, but hands Y over to a script-driven ball-follow for
## a limited stretch of time in between - armed and disarmed by two Call
## Method Track keys placed directly on that SAME AnimationPlayer's
## timeline (see enable_ball_follow()/disable_ball_follow() below), so the
## window's start and length are both authored right there on the timeline
## rather than as separate exported numbers here. The follow itself is the
## same acceleration/friction-based tracking training mode's own paddle.gd
## uses for its whole-match ball-follow (see its track_ball()), just gated
## to a window instead of running always. X (and rotation, scale, whatever
## else the animation drives) is left completely alone throughout - only Y
## ever gets overridden, and only while armed.
##
## To wire this up in the editor: select the "Platforms" AnimationPlayer,
## open the "platforms" animation, add a Call Method Track for this
## platform node, and place one key calling enable_ball_follow at the time
## the follow window should start and another calling disable_ball_follow
## at the time it should end. Do this on BOTH Left_Plat and Right_Plat's
## Call Method Tracks if both should follow together.

## How aggressively this platform accelerates toward the ball's Y position
## while following - same knob/feel as paddle.gd's own reaction_speed.
@export var reaction_speed: float = 10.0

## Caps how fast this platform can move while following, so it can't
## teleport to the ball's Y the instant a follow window opens - same knob
## as paddle.gd's own max_velocity.
@export var max_velocity: float = 400.0

## Higher bleeds off velocity faster once the ball stops pulling it in a
## direction (e.g. after the ball changes direction, or right as a follow
## window ends) - same knob as paddle.gd's own friction.
@export var friction: float = 1.0

var _following_ball: bool = false
var _velocity: float = 0.0

## Call Method Track target: place a key calling this at the moment the
## ball-follow window should START. Resets _velocity so a stale value left
## over from a PREVIOUS follow window (or one that just ended a moment ago)
## never carries into this one.
func enable_ball_follow() -> void:
	_following_ball = true
	_velocity = 0.0

## Call Method Track target: place a key calling this at the moment the
## ball-follow window should END. Nothing here needs to "hand back"
## control - this never touched the animation itself, only ever overwrote
## its result for position.y (see _process() below), so the very next
## frame the "platforms" animation's own Y keyframes simply apply
## uninterrupted again, exactly where they'd naturally be by then.
func disable_ball_follow() -> void:
	_following_ball = false

func _process(delta: float) -> void:
	if not _following_ball:
		return
	var balls := get_tree().get_nodes_in_group("ball")
	if balls.is_empty():
		return
	var ball: Node2D = balls[0]
	var distance: float = ball.global_position.y - global_position.y
	_velocity += distance * reaction_speed * delta
	_velocity = clamp(_velocity, -max_velocity, max_velocity)
	_velocity = lerp(_velocity, 0.0, delta * friction)
	# Deferred, not applied directly here: the "Platforms" AnimationPlayer
	# drives this same node's position from its own _process() call this
	# same frame (Godot 4's default AnimationPlayer processing is idle -
	# i.e. _process(), not physics, and nothing here overrides that), so
	# whichever of the two runs last for this node this frame wins
	# position.y outright - and relying on which node happens to come
	# first/second in the scene tree for that is fragile. Queuing the
	# actual write with call_deferred() instead guarantees it always lands
	# AFTER every _process() call this frame - including the animation's -
	# has already run: the same trick deflection_shield.gd already uses to
	# win an equivalent race against an AnimationPlayer (see its own
	# _apply_deflect_animation()).
	call_deferred("_apply_follow_y", global_position.y + _velocity * delta)

## Deferred target for _process() above - see its own comment for why this
## can't just set global_position.y directly. Re-checks _following_ball at
## the moment this actually runs, not just when it was scheduled a moment
## earlier in the same frame - a window that ends via disable_ball_follow()
## in between can never leave one last stray write landing after the
## hand-back, same "state can change between scheduling and running" gap
## deflection_shield.gd's own deferred call guards against.
func _apply_follow_y(y: float) -> void:
	if _following_ball:
		global_position.y = y
