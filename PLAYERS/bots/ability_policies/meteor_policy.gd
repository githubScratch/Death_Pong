extends BotAbilityPolicy
class_name MeteorPolicy

## Meteor as an opportunistic OFFENSIVE finisher, not a panic move (see the
## design-notes doc: "High-commitment finisher; gate on banked-tier count
## and how punishable being grounded/exposed would be if it whiffs"). Fires
## only when: enough strikes are banked to make the uninterruptible commit
## worthwhile, the ball is NOT an immediate threat (this is deliberately
## never a defensive reaction), and the bot happens to already be airborne -
## wizard.gd's own trigger (see _update_meteor()) requires not is_on_floor()
## at the moment of the second Down tap, full stop, no exception.
##
## This simple v1 never jumps deliberately just to become airborne for this;
## it only opportunistically fires in whatever airborne windows a normal
## jump/cast already produces (every Up press jumps - see wizard.gd's
## _cast_and_jump()). Deliberately jumping first to use this more often is a
## natural follow-up once this simple version is confirmed working in
## practice, not built speculatively before that.

## Minimum tiers of strikes banked before this is even considered - a
## fraction of a tier is never enough payoff to justify committing to an
## uninterruptible fall (see class4_ability.gd's own landing-tier payoff
## table for what different banked amounts actually buy).
@export var min_tiers_banked: int = 2

## Ball ETA (seconds) ABOVE which the ball counts as "not an immediate
## threat" - below this, ordinary defense takes priority and Meteor is
## skipped this tick no matter how much is banked.
@export var min_safe_eta: float = 0.6


func should_use(bot: BotController) -> bool:
	if bot._own_wizard == null:
		return false
	var ability := bot._own_wizard._current_ability() as MeteorAbility
	if ability == null or ability.strikes_per_tier <= 0:
		return false
	var tiers_banked := bot._own_wizard.strikes / ability.strikes_per_tier
	if tiers_banked < min_tiers_banked:
		return false
	if bot._own_wizard.is_on_floor():
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
