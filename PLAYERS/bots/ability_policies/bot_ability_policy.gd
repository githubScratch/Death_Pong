extends Resource
class_name BotAbilityPolicy

## Base for Phase 5's ability-usage policies (see the project's
## bot-implementation-roadmap doc) - one subclass per equipped ability class,
## mirroring this project's own WizardAbility -> StrikeScaledAbility ->
## GrowthAbility composition, so a 5th class later is a new policy file, not
## an edit to a shared one.
##
## Deliberately holds only TUNABLE THRESHOLDS as @export fields, never
## mutable per-cast state - same "pure data, cached and shared" rule
## WizardAbility's own doc comment lays out for ability resources, since a
## policy Resource could in principle be shared across more than one
## BotController the same way an ability .tres is shared across every wizard
## wearing that class. Any state that changes moment-to-moment (cooldown
## timers, in-flight gesture progress) lives on BotController itself, never
## here - see that file's _ability_cooldown_remaining/_ability_gesture_step/
## _up_hold_seconds_remaining.
##
## Subclasses only implement should_use() - a pure, stateless read of the
## bot's current perception that returns whether to use the ability RIGHT
## NOW. BotController is responsible for actually executing whichever
## gesture that ability needs (double-tap, hold, etc.) once should_use()
## says yes - see its _update_ability_usage()/_execute_growth().
##
## should_use() takes the owning BotController directly and reads its
## "private" (underscore-prefixed) perception fields (_own_wizard,
## _target_x, _delayed_ball_state()) rather than going through public
## accessors - a policy is an internal collaborator of one specific
## BotController, not an external API consumer, so that's an accepted
## tight coupling here, not an encapsulation slip.

## Minimum seconds between two uses of this ability - a human wouldn't
## re-trigger the same ability every physics frame either, and this also
## naturally throttles how often should_use() needs to be re-evaluated.
@export var cooldown: float = 1.0


## Returns true if this bot should use its ability right now. Base
## implementation never fires; every concrete policy overrides this with its
## own simple threshold (see the roadmap doc's own explicit "don't
## utility-score all four yet" guidance for why these stay simple for now).
func should_use(_bot: BotController) -> bool:
	return false
