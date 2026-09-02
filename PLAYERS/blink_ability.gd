extends StrikeScaledAbility
class_name BlinkAbility

## Double-tap-to-teleport ability data (see wizard.gd's _update_blink()) -
## class 1's kind of StrikeScaledAbility. Unlike GrowthAbility's continuous
## hold-and-spend, a blink is instant and discrete: double-tapping Left or
## Right spends exactly one tier's worth of strikes (strikes_per_tier,
## inherited from StrikeScaledAbility) all at once and teleports
## blink_distance pixels in that direction - but only if at least one
## tier's worth is currently banked. Anything banked beyond what's spent
## stays banked, so a player can save up multiple blinks (up to max_tiers,
## capped by max_strikes) and use them whenever they want, rather than
## being forced to spend the instant a tier is affordable the way growth
## is.
##
## Groundwork note: once a player has maxed out (max_tiers banked) and uses
## a blink from there, the plan is for it to also leave a temporary clone of
## the wizard that mirrors all of that player's inputs. Not implemented yet
## - deliberately out of scope for this pass - but wizard.gd's blink
## handling is the seam for it: _try_blink() is exactly where "did we just
## spend the last/max tier" is already known, so that's where the clone
## spawn would hook in later.

## Pixels teleported per blink.
@export var blink_distance: float = 300.0

## Max seconds between the first and second tap of a direction for it to
## count as a double-tap. Too long and it starts triggering on ordinary
## back-to-back taps during normal movement; too short and a genuine fast
## double-tap won't reliably register.
@export var double_tap_window: float = 0.25

## Seconds between the double-tap registering and the teleport actually
## firing - a wind-up window, purely for feel/telegraphing (a dodge/parry
## opportunity for whoever's about to get blinked past, an anticipation
## beat for the player). Strikes are spent the instant the double-tap
## registers, not when the teleport fires, same "pay at commit, not after"
## rule growth uses - see wizard.gd's _try_blink(). 0 fires instantly.
@export var blink_delay: float = 0.0

## If true, landing from a blink automatically casts a fresh shield and
## applies a jump impulse - exactly what pressing Up normally does - the
## instant the teleport lands. Lets a blink double as a re-cast/repositioning
## tool (drop the old shield and put a new one up somewhere else in one
## motion) instead of needing a separate Up press right after. See
## wizard.gd's _execute_blink()/_cast_and_jump().
@export var cast_on_blink: bool = false

## Optional VFX scene dropped at the CAST point (where the wizard blinked
## from, not where it lands) the instant a blink commits in wizard.gd's
## _try_blink() - before blink_delay's wind-up even starts, so it marks the
## spot the player left rather than trailing behind the teleport. Null/unset
## skips this entirely (see _spawn_blink_vfx()) - same opt-in shape as
## shield_scene on WizardAbility, no class is forced to carry a VFX it
## doesn't have yet.
@export var vfx_scene: PackedScene

## If true, holding Down through a fall and landing on the floor spends one
## tier (the same strikes_per_tier cost as a normal blink) and teleports
## the wizard straight up to the arena's ceiling instead of landing
## normally - a vertical counterpart to the left/right wall wrap. Only
## triggers off an actual airborne -> grounded landing transition (see
## wizard.gd's _try_slam_wrap()), so it can never fire from pressing Down
## while already standing on the floor - that stays the existing
## horizontal dash untouched.
@export var wrap_on_slam: bool = false
