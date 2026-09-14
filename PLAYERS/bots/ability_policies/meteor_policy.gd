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
##
## Playtesting turned up exactly the failure mode "opportunistic" was meant
## to avoid: with min_tiers_banked satisfied, "airborne" alone was cheap
## enough to hit constantly - _update_cast_decision()'s close-range/
## stationary-standoff triggers and ordinary obstacle-clearing jumps both
## produce frequent, ankle-high hops that barely leave the floor, and every
## single one of those was a fresh "should I Meteor" opportunity. Starting
## the double-tap gesture on one of those tiny hops suspends normal
## movement/casting for its full 5-frame window (see BotController.
## _advance_ability_gesture()) for a jump that's often already landing again
## before the gesture even finishes - visibly indistinguishable from the
## bot just bunny-hopping in place, and for no payoff since a meteor cast
## from ankle height isn't the "well-timed dive bomb" this is meant to be.
## min_airborne_height below is the fix: require this wizard to actually be
## up at a meaningful height above wherever it last stood, not merely
## off the floor by any amount.

## Minimum tiers of strikes banked before this is even considered - a
## fraction of a tier is never enough payoff to justify committing to an
## uninterruptible fall (see class4_ability.gd's own landing-tier payoff
## table for what different banked amounts actually buy).
@export var min_tiers_banked: int = 2

## Ball ETA (seconds) ABOVE which the ball counts as "not an immediate
## threat" - below this, ordinary defense takes priority and Meteor is
## skipped this tick no matter how much is banked.
@export var min_safe_eta: float = 0.6

## Minimum pixels above BotController._last_grounded_y (this wizard's own
## Y the last time it was actually on the floor - see that field's own doc
## comment) before an airborne moment counts as worth considering Meteor
## for at all. Distinguishes a genuine jump/climb (vertical engagement's
## chained air-jumps, or a real human-style leap) from the ankle-high hop an
## ordinary shield-cast or obstacle-clearing jump produces, which is airborne
## in the strict is_on_floor() sense for only a few frames and was never
## going anywhere worth a dive-bomb finisher from.
@export var min_airborne_height: float = 90.0


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
	var airborne_height: float = bot._last_grounded_y - bot._own_wizard.global_position.y
	if airborne_height < min_airborne_height:
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
