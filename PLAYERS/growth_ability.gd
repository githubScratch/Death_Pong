extends StrikeScaledAbility
class_name GrowthAbility

## Hold-to-grow ability data (see wizard.gd's _update_growth_channel()) -
## Nature's kind of StrikeScaledAbility today, but any future class can opt
## in just by giving its ability .tres this script instead of the base
## WizardAbility one. Every other class's ability stays a plain
## WizardAbility and never sees any of these fields - wizard.gd checks
## `_current_ability() is GrowthAbility` rather than a flag on the shared
## base, so this tuning is opt-in per-class, not bloat on every class.
## strikes_per_tier, max_tiers and max_strikes live one level up on
## StrikeScaledAbility - see that file - since they're not really about
## growing, they're the strike bookkeeping any strike-scaled ability shares.
##
## Holding Up gates in once the wizard has banked at least strikes_per_tier
## strikes, then spends strikes_per_tier of them the instant each tier's
## growth starts (never after the fact - see wizard.gd's
## _try_pay_next_growth_step()), growing the current shield instance's scale
## by tier_scale_step per tier, up to max_tiers steps past 1.0, one step
## every growth_duration_per_tier seconds continuously held. Releasing - or
## running out of strikes before affording the next step - always snaps the
## shield back to 1.0; growth is a temporary, spent commitment, never a
## persistent upgrade, and strikes already spent on completed steps are
## never refunded.

## How much bigger each step makes the shield (e.g. 0.5 = +50% scale/tier).
@export var tier_scale_step: float = 0.5

## Seconds of continuous holding one tier's growth takes.
@export var growth_duration_per_tier: float = 0.5

## Seconds the shield takes to snap back to 1.0 once a channel ends.
@export var shrink_duration: float = 0.1

## How long Up must be held before a hold-to-grow channel actually commits
## (starts hovering and spending strikes), instead of being a normal jump.
## Without this, a plain jump tap that happens to span more than one
## physics frame - which is most taps, at typical physics tick rates - would
## get mistaken for the start of a hold and cut the jump short. This window
## is a pure safety buffer, not counted toward growth - growth_duration_per_tier
## for the first tier starts fresh once the channel actually commits, so
## raising this doesn't shrink the first tier's own growth time.
@export var hold_confirm_time: float = 0.1

## Brief pause in the visual growth right after each tier lands (strikes
## spent, scale steps up), before the lerp toward the next tier resumes.
## Purely cosmetic - gives a distinct "tick" each time a strikes_per_tier
## chunk gets spent, instead of the whole hold blurring into one continuous
## grow. 0 disables it.
@export var tier_stutter_time: float = 0.1

## How long the wizard keeps hovering at whatever scale it reached once it
## can no longer grow further - maxed out, or simply out of strikes for the
## next tier - before being forced to release and snap back. 0 means it's
## forced out the instant growth stops (no grace at all); raise this to let
## a fully- or partially-spent hold linger a bit longer as a reward/decoy,
## without ever letting it hover for free indefinitely.
@export var post_channel_hold_time: float = 0.3

## Optional VFX scene attached directly to the wizard as a child (not a
## one-shot world-space drop like BlinkAbility.vfx_scene) the instant a
## growth channel commits, and explicitly stopped and queue_free()'d the
## instant the channel ends for any reason - see wizard.gd's
## _start_growth_vfx()/_stop_growth_vfx(). Null/unset skips this entirely,
## same opt-in shape as BlinkAbility.vfx_scene.
@export var vfx_scene: PackedScene


## The full list of scales a hold steps through: 1.0 (base), then one entry
## per tier_scale_step for each of max_tiers steps. Computed from the
## tuning numbers above rather than hand-authored, so balancing the ceiling
## or the per-tier jump is a one- or two-field edit instead of resizing/
## re-typing a whole array.
func growth_tier_scales() -> Array[float]:
	var scales: Array[float] = [1.0]
	for i in max_tiers:
		scales.append(1.0 + tier_scale_step * (i + 1))
	return scales
