extends StrikeScaledAbility
class_name IceAbility

## Class 3's Ice Zone - see wizard.gd's _update_ice_zone()/_cast_ice_zone().
## This is a ground-up replacement for the previous hold-to-trap version:
## the shield (shield_scene, spell_3.tscn) is back to being a plain,
## always-functioning barrier exactly like every other class's - nothing
## about casting or holding it does anything special for Ice anymore.
##
## Instead, double-tapping Left or Right (same double-tap shape
## BlinkAbility already uses, own separate state on wizard.gd rather than
## sharing Blink's - see wizard.gd's _ice_left_tap_window_remaining/
## _ice_right_tap_window_remaining) drops a slowing, circle-shaped zone
## (zone_scene, PLAYERS/ice_zone.tscn) at a fixed point in the tapped
## direction. Unlike the old trap this isn't attached to the wizard or the
## shield at all - once spawned it's a fully independent object with its
## own lifetime (zone_duration, +despawn_delay - see IceZone) that slows
## anything overlapping it for as long as that body actually stays inside,
## continuously, not a one-time catch.
##
## Same "pay at commit" strikes rule every other ability in this project
## uses, just spent all at once instead of ticking up over a hold: a
## double-tap spends every currently-banked tier at once (up to
## max_tiers), and the zone's size/slow/duration all scale up with however
## many tiers that was - see zone_scale_for_tier()/zone_slow_for_tier()/
## zone_duration_for_tier() and wizard.gd's _cast_ice_zone(). Needs at
## least one full tier banked (strikes_per_tier) to do anything at all - a
## double-tap with nothing banked just doesn't cast, same as Blink denying
## an unaffordable blink.
##
## Also gives the caster a bit of recoil on cast - see self_knockback/
## knockback_lock_time below.

## Seconds between the first and second tap of Left/Right to count as a
## double-tap rather than two separate single taps - same shape/purpose as
## BlinkAbility.double_tap_window, kept as Ice's own field since this
## ability doesn't extend BlinkAbility.
@export var double_tap_window: float = 0.3

## The zone's scale multiplier the instant it's spawned on a single spent
## tier - "size." Applied as IceZone's own Node2D scale, which scales its
## collision radius and its Ice_Trap visual together for free - see
## IceZone.BASE_RADIUS for what 1.0 actually measures.
@export var zone_size: float = 1.0

## How much bigger each additional spent tier makes the zone, on top of
## zone_size - "additional size per tier." A cast spending N tiers gets
## zone_size + zone_size_per_tier * (N - 1) - see zone_scale_for_tier().
@export var zone_size_per_tier: float = 0.3

## How strongly the zone slows anything inside it - 0..1, where 1.0 means
## fully stopped for as long as a body stays inside ("at 1 we have stopped
## entirely state"), same convention Ball/Wizard.freeze_in_place() already
## uses. Passed straight through to IceZone, which reuses freeze_in_place()
## as-is to apply it - see that function's own doc comment for exactly how
## a given value reads as "slowed" vs "frozen."
@export_range(0.0, 1.0) var slow_amount: float = 0.5

## How much stronger the slow gets per additional spent tier, on top of
## slow_amount - "additional slow per tier." Clamped back to 0..1 after
## adding, same as slow_amount alone - see zone_slow_for_tier().
@export var slow_amount_per_tier: float = 0.15

## How long the zone itself exists and keeps catching/holding bodies -
## "duration of slow area." Not a per-body freeze timer - see IceZone's own
## doc comment for why a body's slow instead ends the moment it leaves the
## zone, or when the zone itself expires, whichever comes first.
@export var zone_duration: float = 2.0

## How much longer each additional spent tier keeps the zone alive, on top
## of zone_duration - "additional duration per tier." See
## zone_duration_for_tier().
@export var zone_duration_per_tier: float = 0.5

## Extra seconds the zone scene sticks around, no longer catching anything
## (monitoring off, every body inside already thaw()'d), after
## zone_duration runs out - "time to queue_free the object after the
## duration," purely so IceZone's outro vfx (Ice_Trap.tscn's "trap release"
## clip, if present) has room to actually finish playing before the node is
## gone. 0 means an instant queue_free() the moment the zone's own duration
## ends, cutting off (or entirely skipping) any outro animation.
@export var despawn_delay: float = 0.3

## Force of the recoil jolt applied to the wizard, once, at the instant of
## casting, in the OPPOSITE direction from whichever way the zone was
## thrown - "self knockback." Set as a single hard velocity.x value (not
## added to whatever velocity.x the wizard already had) the instant of
## cast, the same "one impact, one new velocity" way ball.gd's deflect
## works off a shield (deflection_shield.gd's deflect_ball()) - then eased
## back down to 0 over knockback_lock_time below by a Tween, rather than
## holding at full force or being cut off abruptly. See wizard.gd's
## _apply_ice_knockback(). 0 disables it outright.
@export var self_knockback: float = 250.0

## Seconds wizard.gd's normal LEFT/RIGHT movement-input handling is
## suppressed after a zone cast, so self_knockback's jolt (and the Tween
## easing it back to 0 - see _apply_ice_knockback()) isn't instantly fought
## and overwritten the same physics frame by whatever direction the player's
## still holding from the double-tap that triggered it - the "competing
## commands" a knockback with no lock at all was losing to. Doesn't touch
## jumping, diving, or casting - only the direction-based movement code.
## An earlier version paused gravity too (a "hover"), but that conflicted
## with the wizard's own jump/dive/landing logic and was dropped; only
## movement input is held off now. 0 disables it outright, so the jolt is
## just as vulnerable to being immediately overwritten as it always was.
@export var knockback_lock_time: float = 0.2

## Whether the ice mage's own zones can slow the ice mage that cast them -
## the checkbox. False (the default) matches every other class's "never
## affects the caster" convention (Growth's own hold, Blink's own
## teleport, and the old trap's freeze query all skipped the caster
## outright); flip true to let an Ice mage get caught in their own zone
## like anyone else.
@export var self_affected: bool = false

## The interactive zone spawned by a cast - PLAYERS/ice_zone.tscn (an
## Area2D wrapping VFX/Ice_Trap.tscn's visuals with the slow-while-inside
## logic described above). Not a purely cosmetic vfx_scene like
## GrowthAbility/BlinkAbility use elsewhere in this project - this one IS
## the ability's actual gameplay object, not an optional visual layer on
## top of something else, so it's not null-able/opt-out the way those are.
@export var zone_scene: PackedScene

## The purely cosmetic vfx (VFX/Ice_Trap.tscn) IceZone instantiates in code
## at its own _ready() time and attaches as a child of itself - see
## ice_zone.gd's doc comment for why it's instantiated in code rather than
## baked into zone_scene's own .tscn as a static instanced child (that
## approach turned out to just not show up at all). Separate field from
## zone_scene above since zone_scene is the actual gameplay object
## (Area2D + collision) while this is only ever the look of it - null skips
## spawning any visual at all but the zone still slows normally, same
## opt-in shape frozen_ball_overlay/frozen_wizard_overlay below use.
@export var zone_vfx_scene: PackedScene

## Placeholder overlay spawned on a frozen ball for as long as it stays
## inside the zone - same PackedScene passed straight through to
## freeze_in_place(), same opt-in shape used everywhere else in this
## project (null skips spawning anything). Carried over unchanged from the
## old trap version.
@export var frozen_ball_overlay: PackedScene

## Same as frozen_ball_overlay, for a frozen wizard.
@export var frozen_wizard_overlay: PackedScene


## The zone's scale multiplier for a cast that spent tiers_spent tiers
## (always >= 1 - see wizard.gd's _cast_ice_zone(), which never casts at
## all below 1). Tier 1 is exactly zone_size; each tier after that adds
## another zone_size_per_tier.
func zone_scale_for_tier(tiers_spent: int) -> float:
	return zone_size + zone_size_per_tier * float(tiers_spent - 1)


## The zone's slow_amount for a cast that spent tiers_spent tiers, clamped
## back to 0..1 the same way the base slow_amount already is.
func zone_slow_for_tier(tiers_spent: int) -> float:
	return clampf(slow_amount + slow_amount_per_tier * float(tiers_spent - 1), 0.0, 1.0)


## The zone's own lifetime for a cast that spent tiers_spent tiers.
func zone_duration_for_tier(tiers_spent: int) -> float:
	return zone_duration + zone_duration_per_tier * float(tiers_spent - 1)
