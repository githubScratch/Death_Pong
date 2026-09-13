extends BotAbilityPolicy
class_name IcePolicy

## Ice used to slow the ball and buy repositioning time when it's closing in
## faster than the bot can walk into position - same "imminent miss" shape
## BlinkPolicy uses, but the response here slows the BALL down instead of
## teleporting the bot's own body, since a thrown zone is a battlefield
## object, not a self-move. Needs at least one tier banked, same as any
## other double-tap ability's own affordability gate (see wizard.gd's
## _cast_ice_zone()).
##
## BotController executes this by tapping TOWARD the ball - dropping the
## zone in its actual path - not away from it. See
## BotController._ability_direction_action().

@export var emergency_eta: float = 0.25
@export var emergency_distance: float = 100.0


func should_use(bot: BotController) -> bool:
	if bot._own_wizard == null or bot.target_ball == null:
		return false
	var ability := bot._own_wizard._current_ability() as IceAbility
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
