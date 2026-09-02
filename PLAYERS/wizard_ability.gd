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
## a new subclass of this one (see GrowthAbility for the pattern) plus new
## handling in wizard.gd - this file is the seam, not the ceiling, and it
## stays this bare on purpose: fields specific to one kind of ability (like
## GrowthAbility's hold-to-grow tuning) belong on that subclass, not here,
## so every other class's ability resource doesn't carry fields it never
## uses.

## Shown to players (character select, a future ability tooltip, etc).
@export var display_name: String = "Ability"

## The shield/spell scene this ability casts.
@export var shield_scene: PackedScene
