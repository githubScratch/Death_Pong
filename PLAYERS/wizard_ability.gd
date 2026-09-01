extends Resource
class_name WizardAbility

## Pure data: one entry in a WizardClass's ability list. Same reasoning as
## WizardClass - a .tres file loaded from disk is cached and shared by
## every wizard that references it, so nothing here can be mutable
## per-cast state. All of that (which shield instance is currently on the
## field, fading it out, cleaning up stale ones) stays on the wizard
## chassis itself in wizard.gd, same as before this file existed.
##
## Right now every ability is "spawn this shield scene" - that's the only
## kind of ability the game has. shield_scene is deliberately still just a
## PackedScene rather than something more elaborate, so this stays a
## faithful, working port of what WizardClass.shield_scene used to be,
## just renamed and pluralized. If a future ability needs to *do* more than
## spawn a scene (a cooldown, a resource cost, a non-shield effect), that's
## new fields here plus new handling in wizard.gd's create_new_instance() -
## this file is the seam, not the ceiling.

## Shown to players (character select, a future ability tooltip, etc).
@export var display_name: String = "Ability"

## The shield/spell scene this ability casts.
@export var shield_scene: PackedScene
