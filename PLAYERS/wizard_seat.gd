extends Node2D
class_name WizardSeat

## Lives on the wizard chassis's ROOT node (see wizard.tscn), not on the
## CharacterBody2D child. That placement is deliberate, not cosmetic:
## Godot only reliably applies a property override written into an arena
## scene's `[node ... instance=...]` block when it targets that instance's
## ROOT node directly - the same way `position` is already overridden per
## placed instance. Overriding a value on one of the instance's *nested*
## children needs extra editor-side bookkeeping a hand-authored .tscn
## doesn't have, which is exactly the bug this file exists to avoid.
##
##  - seat: which physical player's input the CharacterBody2D child reads
##    (1-4).
##  - wizard_class: which WizardClass resource (color/sprite/shield) this
##    body is wearing.
##
## wizard.gd (on the CharacterBody2D child) reads both of these from its
## parent - this node - at _ready().
##
## class_name'd (WizardSeat) so wizard.gd's _spawn_blink_clone() can cast the
## fresh instance it gets back from preloading wizard.tscn and set `seat`
## directly, type-safely, instead of a dynamic set() call.

@export var seat: int = 1
@export var wizard_class: WizardClass
