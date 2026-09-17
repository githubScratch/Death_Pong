extends BotAbilityPolicy
class_name BlinkPolicy

## Blink used as an emergency REPOSITION, not a dodge (see the design-notes
## doc: "Best used as an emergency reposition/dodge... down a player, needing
## double coverage"). The base "would I actually miss without it" test is
## still the same shape it always was - ball about to arrive AND the bot too
## far from its own goal-side target X to get there by walking in time - but
## per the user's own explicit request (2026-09-17: "turn down the blink bot
## spamming... play more balanced and less spamming"), that test alone
## turned out to fire far too readily to read as a reserved, limited-charge
## tool - any ordinary "running a bit late" moment with no real stakes
## qualified just as easily as a genuine goal-saving/goal-securing sprint.
##
## Now gated on top by which of two tactical moments this actually is, per
## the user's own framing - "save the blinks for those moments where
## aggression is needed to chase a distant ball to secure a goal and race
## the enemy, or to hurry home to defend the goal... keeping a blink in the
## back pocket... doesn't have to always hold onto them, but play more
## balanced":
##   1. DEFEND: bot._goal_pressure is true (see that field's own doc
##      comment) - the ball is bearing down on this wizard's own net, so
##      hurrying home always justifies it, no opponent check needed.
##   2. RACE: this bot hasn't already given up on the ball (bot._defensive is
##      false - see that field's own doc comment) AND an opposing wizard is
##      genuinely close enough to the ball to be a real contest, mirroring
##      the exact same threat check _update_engagement_role() itself uses to
##      decide whether a race is even on. No opponent actually racing for it
##      = no reason to burn a charge over an unpressured "I'm a bit slow"
##      gap; ordinary walking (or a dash) already covers that.
## A bot that's already conceded this particular ball (bot._defensive true,
## and not a goal-pressure moment) never blinks for it either way - see
## _update_engagement_role()'s own doc comment for why that concession
## already happened, and there's nothing worth defending by teleporting
## toward a ball this bot decided wasn't winnable a moment ago.
##
## BotController executes this by tapping whichever of left/right actually
## closes the gap toward _target_x - TOWARD the correct defensive spot, not
## away from the ball - since the shield, not the wizard's body, is what
## actually blocks a shot (see deflection_shield.gd); teleporting away from
## the ball wouldn't help defend anything, it would just relocate the body
## somewhere unhelpful. See BotController._ability_direction_action().

## Ball ETA (seconds) at or below which a miss is considered imminent enough
## to justify spending a blink charge on it.
@export var emergency_eta: float = 0.2

## How far (pixels) from the goal-side target X counts as "too far to walk
## there in time" - below this, normal movement is expected to close the gap
## on its own before the ball arrives, so blinking would just waste a charge
## for no real gain over just walking. Raised from the original 120.0 per
## the same "reserve it, don't spend on marginal gaps" request - only a
## meaningfully large gap should ever be worth a charge, even once the
## defend/race gate below also passes.
@export var emergency_distance: float = 150.0


## Overrides BotAbilityPolicy's own 1.0s default - a limited-charge
## "reserve" tool shouldn't be able to re-fire the instant strikes are
## banked again and another qualifying moment rolls around a second later.
## 2.5s still comfortably allows one DEFEND and one RACE blink inside the
## same short volley if both genuinely come up, without letting either
## moment alone turn into a back-to-back double-tap on repeat.
func _init() -> void:
	cooldown = 2.5


func should_use(bot: BotController) -> bool:
	if bot._own_wizard == null or bot.target_ball == null:
		return false
	var ability := bot._own_wizard._current_ability() as BlinkAbility
	if ability == null or ability.strikes_per_tier <= 0:
		return false
	if bot._own_wizard.strikes < ability.strikes_per_tier:
		return false

	var ball_state := bot._delayed_ball_state()
	if ball_state.is_empty():
		return false
	var ball_pos: Vector2 = ball_state["position"]
	var to_ball: Vector2 = ball_pos - bot._own_wizard.global_position
	var speed: float = maxf((ball_state["velocity"] as Vector2).length(), bot.profile.min_ball_speed_for_eta)
	var eta: float = to_ball.length() / speed
	var distance_to_target := absf(bot._target_x - bot._own_wizard.global_position.x)

	if eta > emergency_eta or distance_to_target < emergency_distance:
		return false

	# DEFEND - the ball is closing in on this wizard's own goal. Always
	# worth it regardless of whether anyone's actually racing for the ball;
	# conceding a goal is worse than spending a charge that turns out
	# slightly early.
	if bot._goal_pressure:
		return true

	# Already given up on this particular ball (see _update_engagement_role())
	# and it's not a goal-pressure moment either - nothing here worth a
	# charge.
	if bot._defensive:
		return false

	# RACE - only a real contest if an opponent is actually close enough to
	# the ball to threaten winning it first, same threshold
	# _update_engagement_role() itself uses for the opposite call.
	for opponent in bot.other_wizards:
		if opponent.global_position.distance_to(ball_pos) <= bot.profile.opponent_threat_distance:
			return true
	return false
