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
## Once a player has maxed out (max_tiers banked) and cashes in a teleport
## from there - an ordinary left/right blink OR a slam-wrap landing (see
## wrap_on_slam below), whichever happens to fire first - that teleport
## cashes in EVERYTHING banked instead of the usual flat one-tier cost, and
## - if clone_on_max_tier is true - also leaves a temporary clone of the
## wizard behind that mirrors all of that player's inputs (mirroring is
## free: both wizards read the same seat's input actions off the same
## physical button presses, in lockstep, with no recording/playback needed -
## see wizard.gd's _spawn_blink_clone()). See wizard.gd's _try_blink() and
## _try_slam_wrap() for exactly where "did we just cash in at the max tier"
## is detected and this hooks in - both go through the identical check, so
## a maxed-out player gets the same payoff no matter which of the two they
## use to spend it.
##
## A THIRD max-tier bonus, swap_locations_at_max_tier below, only applies to
## the ordinary left/right blink (not the slam-wrap landing) - if true, that
## teleport swaps this wizard's position with the nearest enemy wizard's
## instead of moving in `direction` by blink_distance. Fully independent of
## clone_on_max_tier: either, both, or neither can be on at once.

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
## wizard.gd's _execute_blink()/_cast_and_jump(). Takes priority over
## jump_on_blink just below when both are somehow on, since this already
## includes the jump that one adds on its own.
@export var barrier_on_blink: bool = false

## If true, landing from a LEFT/RIGHT blink (not the ceiling-wrap slam
## wrap - see _execute_blink() vs _try_slam_wrap()) immediately applies a
## jump impulse, same feel as an Up press or cast_on_blink's own jump - but
## WITHOUT summoning a fresh shield the way cast_on_blink does. For a class
## that wants blink to double as an aerial repositioning/extra-jump tool
## without also forcing a shield recast (and the strike-gauge reset that
## comes with dropping the old one) every time. Ignored outright while
## cast_on_blink is true, since that already jumps as part of its own,
## bigger effect - see wizard.gd's _execute_blink()/_apply_jump_impulse().
@export var jump_on_blink: bool = false

## Scales the jump impulse jump_on_blink applies above - 1.0 is full
## strength, exactly as strong as an ordinary jump; 0.5 is a half-height
## hop. Only touches jump_on_blink's own jump: cast_on_blink's jump (and a
## normal Up press) always jump at full strength regardless of this knob,
## and this is read-but-unused while jump_on_blink is false. See wizard.gd's
## _apply_jump_impulse().
@export_range(0.0, 2.0, 0.05) var jump_on_blink_strength: float = 1.0

## Optional VFX scene dropped at the CAST point (where the wizard blinked
## from, not where it lands) the instant a blink commits in wizard.gd's
## _try_blink() - before blink_delay's wind-up even starts, so it marks the
## spot the player left rather than trailing behind the teleport. Null/unset
## skips this entirely (see _spawn_blink_vfx()) - same opt-in shape as
## shield_scene on WizardAbility, no class is forced to carry a VFX it
## doesn't have yet. Only covers the ordinary left/right blink - the
## ceiling-wrap slam wrap (see wrap_on_slam below) uses its own
## vertical_vfx_scene instead, not this one.
@export var vfx_scene: PackedScene

## Optional VFX scene ("blink2vfx") dropped at BOTH ends of a slam-wrap's
## ground-to-ceiling teleport (see wizard.gd's _try_slam_wrap()) in place of
## vfx_scene above - the vertical teleport reads better with its own effect
## than reusing the plain left/right blink's, since that one's art is
## oriented for a horizontal read. Same opt-in shape as vfx_scene: null/
## unset skips this entirely (see _spawn_blink_vfx()).
@export var vertical_vfx_scene: PackedScene

## If true, double-tapping Down and continuing to HOLD it on that second
## press - same gesture MeteorAbility's own double-tap-and-hold uses, see
## wizard.gd's _update_slam_wrap() - arms a slam-wrap for as long as it stays
## held and this wizard is airborne. Landing on the floor with it still armed
## spends one tier (the same strikes_per_tier cost as a normal blink) and
## teleports the wizard straight up to the arena's ceiling instead of
## landing normally - a vertical counterpart to the left/right wall wrap.
## Releasing Down before landing cancels the arm outright, same as never
## double-tapping it in the first place - a plain fall/dive (Down held once,
## never double-tapped) never arms this at all, so it no longer fires on
## every ordinary Down-held landing. Only ever resolves from an actual
## airborne -> grounded landing transition (see wizard.gd's
## _try_slam_wrap()), so it can never fire while already standing on the
## floor - that stays the existing horizontal dash untouched.
@export var wrap_on_slam: bool = false

## Only matters when wrap_on_slam is true. If true (the default - matches
## the original behavior), arming a slam-wrap takes the full double-tap-and-
## hold gesture described above: tap Down, tap it again within
## double_tap_window while still airborne, and keep holding that second
## press through to landing. If false, a single press-and-hold of Down while
## airborne arms it outright - no double-tap needed, see wizard.gd's
## _update_slam_wrap(). Either way, releasing Down before landing still
## cancels the arm, and it's still gated on being airborne when Down is
## first pressed (pressing Down while already grounded just falls through
## to the ordinary dash, same as always) - this knob only changes how many
## presses of Down it takes to arm, not any of the other rules around it.
## Exists because double-tap-and-hold reads as a deliberate, hard-to-
## trigger-by-accident input (matching MeteorAbility's own gesture), while a
## plain hold is faster/twitchier to use - which one feels right is a
## per-class, per-feel call, not a single right answer.
@export var slam_wrap_requires_double_tap: bool = true

## How close this wizard must already be to a wrap-tagged wall (map_wall_
## left/map_wall_right - see wizard.gd's _wrap_destination()) for a blink
## that reaches it to actually wrap to the opposite side, rather than just
## stopping short flush against that wall like blinking into any other
## obstacle. Measured as the clear distance the blink actually travels
## before hitting the wall (see wizard.gd's _execute_blink()), i.e. "was this
## wizard already standing within this many pixels of the wall" - not
## blink_distance itself. Without this, a long blink_distance thrown from
## anywhere near a wrap wall - mid-arena, mid-fight - immediately launches
## the wizard clean across the map, which reads as an accident far more
## often than a deliberate play; keeping this small means only a blink
## thrown from genuinely close to the wall - sneaking through for a clean
## strike on the other side - actually wraps, and everything farther out
## just blinks the wizard up to the wall like normal.
@export var wrap_activation_distance: float = 80.0

## If true, a blink OR a slam-wrap landing cast while max_tiers is already
## fully banked cashes in ALL of it (not just one tier's worth - see
## wizard.gd's _try_blink() and _try_slam_wrap()) and spawns a temporary
## clone of the wizard that mirrors every input the player makes for as
## long as it lasts (clone_duration). False just leaves a maxed-out
## teleport as a plain flat one-tier spend, same as any other blink or slam
## wrap. A clone itself never triggers this again even at ITS OWN max tier -
## see _is_clone's doc comment in wizard.gd - so this can never chain into a
## second clone.
@export var clone_on_max_tier: bool = true

## If true, a blink cast while max_tiers is already fully banked swaps this
## wizard's position with the NEAREST ENEMY wizard's (team read the same way
## GameSettings.team_color_for_seat() already colors outlines - never a
## teammate, even in a 4-player 2v2 match) instead of the ordinary
## directional teleport (`direction` * blink_distance) - see wizard.gd's
## _execute_blink()/_nearest_enemy_wizard(). Completely independent of
## clone_on_max_tier above: both can be on at once (spend everything, leave
## a clone behind at the old spot, AND swap into the enemy's position), or
## just this one on its own (no clone, but the max-tier payoff is landing
## square where an enemy was standing rather than a longer/further blink).
## False (the default) leaves a maxed-out blink exactly as it always
## was - just a bigger flat spend if clone_on_max_tier is also on, otherwise
## indistinguishable from any other blink. Like clone_on_max_tier, a clone's
## own maxed-out cast (_is_clone) never triggers this either - see
## wizard.gd's _try_blink() doc comment. If there's no enemy wizard to swap
## with at all (Training's single-seat scene, or every other wizard already
## gone), falls back to the ordinary directional teleport instead of doing
## nothing.
@export var swap_locations_at_max_tier: bool = false

## Seconds a clone spawned by a maxed-out blink or slam wrap sticks around
## before despawning - see wizard.gd's _spawn_blink_clone()/_despawn_clone(). Any
## barrier the clone cast while it was up fades out via its own
## AnimationPlayer (the same "fade" animation/queue_free() every other
## barrier teardown in this project uses) the instant the clone despawns,
## rather than being left standing after the clone that cast it is gone.
@export var clone_duration: float = 5.0

## Alpha (0.0-1.0) applied to the clone's modulate the instant it spawns, so
## it reads as a clone at a glance instead of an indistinguishable second
## copy of the real player. 1.0 makes it fully opaque/identical.
@export var clone_transparency: float = 0.5

## Optional alternate sprite sheet for the clone only - same 2x2, 192x192-
## per-frame layout every wizard_class.sprite_sheet already uses (see
## wizard.gd's _build_sprite_frames()), just a different texture. Lets a
## clone read as visually distinct from the real wizard at a glance (on top
## of clone_transparency above) instead of only differing by opacity - a
## ghostly/desaturated recolor of the class's sheet, say. Null/unset (the
## default) skips this entirely and the clone just uses the same
## wizard_class.sprite_sheet as the real wizard, exactly like before this
## knob existed. See wizard.gd's _spawn_blink_clone().
@export var clone_sprite_sheet: Texture2D

## Seconds spent tweening the clone's modulate.a from clone_transparency
## down to 0 right before its chassis is freed - see wizard.gd's
## _despawn_clone(). 0 skips the tween and frees the clone immediately, the
## original "just disappears" behavior - same "0 opts out" convention every
## other timing knob on this resource already uses (blink_delay, etc).
@export var clone_fade_duration: float = 0.5

## The actual "decay curve" shape applied to that fade - Tween's own
## TransitionType/EaseType vocabulary, same pair every other decay/return
## tween in this project already exposes as a feel knob (see
## deflection_shield.gd's shield-return tween and wizard.gd's own
## knockback-decay tweens) rather than introducing a separate Curve
## resource just for this one spot. TRANS_LINEAR/EASE_IN is a plain,
## constant-speed fade; swap in something like TRANS_CUBIC/EASE_IN for a
## fade that lingers early and drops off fast at the end, or TRANS_SINE/
## EASE_OUT for the reverse.
@export var clone_fade_trans: Tween.TransitionType = Tween.TRANS_LINEAR
@export var clone_fade_ease: Tween.EaseType = Tween.EASE_IN

## If true, any strike the clone's own shield deflects is credited back to
## the player who cast it (see wizard.gd's _on_shield_deflected()) instead
## of being banked on the clone itself, which despawns after clone_duration
## and would otherwise just discard whatever it earned. False (the default)
## means strikes the clone earns are the clone's own and vanish with it -
## the clone is purely a decoy/distraction, not a second source of banked
## strikes for the player.
@export var clone_strikes_count_for_player: bool = false
