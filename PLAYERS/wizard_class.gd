extends Resource
class_name WizardClass

## Pure data: one selectable wizard class' cosmetic identity and which
## abilities it casts. No logic lives here at all - that's the point. A
## WizardClass is a .tres file, not a scene, so listing every class (for a
## character-select screen) or adding a new one is just "point at another
## resource", never new code.
##
## abilities is a list, not a single ability, on purpose: today every class
## only has one entry in it (see wizard.gd's _current_ability(), which just
## returns abilities[0]), but the list is what makes a strike-count-gated
## kit, a Wild Mage that rerolls between several abilities, or a
## power-up-unlocked ability all possible later without changing this
## resource's shape again - they'd all just be different logic for
## *picking* an entry out of this same array.

## Shown to players (character select, HUD, etc). Free text for now.
@export var display_name: String = "Wizard"

## A 384x384 sheet cut into a 2x2 grid of 192x192 frames, same layout every
## class already uses - see wizard.gd's _build_sprite_frames().
@export var sprite_sheet: Texture2D

## This class's ability kit. See the class doc comment above for why this
## is an array even though only the first entry is used right now.
@export var abilities: Array[WizardAbility] = []
