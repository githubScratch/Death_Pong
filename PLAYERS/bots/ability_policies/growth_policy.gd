extends BotAbilityPolicy
class_name GrowthPolicy

## Growth used proactively to cover a wide/uncertain angle BEFORE the ball
## actually needs it (see the design-notes doc: "Trade mobility for a bigger
## interception radius when covering an uncertain/wide angle") - never as a
## panic response, since a fresh channel needs GrowthAbility.hold_confirm_time
## just to gate in, by which point a truly imminent shot would already be
## missed. Fires only when strikes are banked AND the ball is comfortably
## far away.
##
## Execution is fundamentally different from the other three policies:
## instead of a quick double-tap gesture, BotController holds Up for
## roughly hold_confirm_time + tiers_to_grow * growth_duration_per_tier
## seconds (see BotController._execute_growth()) - a real commitment that
## also hovers the wizard in place for its duration (wizard.gd's own
## _is_channeling override zeroes velocity every frame), so this should only
## ever fire when nothing urgent needs that mobility back soon.

@export var min_safe_eta: float = 0.6

## How many growth tiers to aim for each time this triggers - clamped to
## whatever's actually affordable by the equipped GrowthAbility at execution
## time (see BotController._execute_growth()); this is just the aspiration,
## not a guarantee (the channel can still be cut short by running out of
## banked strikes mid-hold, same as it would for a human).
@export var tiers_to_grow: int = 1


func should_use(bot: BotController) -> bool:
	if bot._own_wizard == null:
		return false
	var ability := bot._own_wizard._current_ability() as GrowthAbility
	if ability == null or ability.strikes_per_tier <= 0:
		return false
	if bot._own_wizard.strikes < ability.strikes_per_tier:
		return false

	if bot.target_ball == null:
		return true
	var ball_state := bot._delayed_ball_state()
	if ball_state.is_empty():
		return true
	var to_ball: Vector2 = ball_state["position"] - bot._own_wizard.global_position
	var speed: float = maxf((ball_state["velocity"] as Vector2).length(), bot.profile.min_ball_speed_for_eta)
	var eta: float = to_ball.length() / speed

	return eta >= min_safe_eta
