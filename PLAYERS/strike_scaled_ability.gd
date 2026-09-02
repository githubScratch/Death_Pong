extends WizardAbility
class_name StrikeScaledAbility

## Shared shape for any ability that gets more powerful the more strikes are
## banked when it's cast - Nature's barrier growth today, and very likely
## Blink's clone duration and other classes down the line too (this is the
## "power up based on strikes banked" idea from our original ability
## brainstorm). What a "tier" actually buys is still up to the subclass -
## GrowthAbility spends one on shield scale, a future BlinkAbility might
## spend it on clone lifetime instead - but the strike bookkeeping around
## that (cost per tier, how many tiers exist, the cap on banking strikes
## you'll never spend) is identical everywhere, so it lives here once
## instead of being re-declared per ability.
##
## This sits BETWEEN WizardAbility and a concrete ability like GrowthAbility
## on purpose, not folded into the shared base: a class whose ability
## doesn't scale with strikes at all keeps carrying nothing here, same as it
## carries none of GrowthAbility's fields today. Opt in by extending this
## (or a further subclass of it), not by flipping a flag on everyone.

## Strikes spent to buy one tier.
@export var strikes_per_tier: int = 3

## How many tiers past the base a fully-loaded cast can reach.
@export var max_tiers: int = 4

## The most strikes it's ever useful to have banked for this ability - the
## ceiling wizard.gd clamps banked strikes to (see _max_banked_strikes()).
## Defaults to strikes_per_tier * max_tiers (the cost of buying every tier
## from empty) but is its own field rather than only ever computed, in case
## a future ability wants a different relationship - a reserve buffer, a
## deliberately lower cap, etc. Keep it in sync with strikes_per_tier /
## max_tiers by hand if you change either.
@export var max_strikes: int = 12
