extends Resource
class_name WizardClass

## Pure data: one selectable wizard class' cosmetic identity and which
## shield/spell scene it casts when it "jumps". No logic lives here at all -
## that's the point. A WizardClass is a .tres file, not a scene, so listing
## every class (for a character-select screen) or adding a new one is just
## "point at another resource", never new code.
##
## Ability kits (the strike-gated abilities from the roadmap) will be added
## here once the ability-component system exists - that's the next slice,
## after this chassis/class split is proven out.

## Shown to players (character select, HUD, etc). Free text for now.
@export var display_name: String = "Wizard"

## A 384x384 sheet cut into a 2x2 grid of 192x192 frames, same layout every
## class already uses - see wizard.gd's _build_sprite_frames().
@export var sprite_sheet: Texture2D

## The shield/spell scene this class casts (what used to be each
## wizard_N.tscn's own hardcoded `instance_scene` export).
@export var shield_scene: PackedScene
