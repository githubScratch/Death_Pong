extends BotAbilityPolicy
class_name BlinkPolicy

## Blink used as an emergency REPOSITION, not a dodge (see the design-notes
## doc: "Best used as an emergency reposition/dodge... down a player, needing
## double coverage"). Fires only when the ball is about to arrive AND the
## bot is too far from its own goal-side target X to get there by walking in
## time - a genuine imminent miss, not "ball is merely somewhere nearby."
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
## for no real gain over just walking.
@export var emergency_distance: float = 120.0


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
	var to_ball: Vector2 = ball_state["position"] - bot._own_wizard.global_position
	var speed: float = maxf((ball_state["velocity"] as Vector2).length(), bot.profile.min_ball_speed_for_eta)
	var eta: float = to_ball.length() / speed
	var distance_to_target := absf(bot._target_x - bot._own_wizard.global_position.x)

	return eta <= emergency_eta and distance_to_target >= emergency_distance
