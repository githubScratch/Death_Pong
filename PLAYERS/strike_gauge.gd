extends Sprite2D
class_name StrikeGauge

## Visualizes a wizard's banked strikes as a fill level on its shield -
## starts as a small bead at min_scale (empty) and grows toward max_scale
## (full) as strikes climb toward whatever cap is active. See wizard.gd's
## _update_strike_gauge()/_max_banked_strikes() for how the ratio is
## computed. Purely cosmetic - carries no gameplay data itself, just
## reflects whatever ratio it's told to show.
##
## Opt-in per shield scene, same pattern the ability composition hierarchy
## uses: wizard.gd looks for a child node named "StrikeGauge" on whatever
## shield is currently spawned and does nothing if it isn't there, so adding
## this to one class's shield never affects any other class, and no shield
## is forced to carry a gauge it doesn't want. min_scale/max_scale are
## exported so each shield scene can size and tune its own gauge to fit its
## own art without touching this script - the "small bead expanding to the
## confines of the shield" feel is entirely a min/max scale choice per
## scene, not something baked in here.

## Scale at 0 strikes banked - the "small bead" starting point.
@export var min_scale: float = 0.1

## Scale once banked strikes hit the cap - how far the bead grows to reach
## the "full" look. Tune this per shield scene to taste (e.g. to just
## barely fill the existing core sprite's footprint, or to overflow past it).
@export var max_scale: float = 1.8

## Seconds for the gauge to visually catch up to a new fill ratio, rather
## than snapping instantly - reads more like a potion settling than a bar
## jumping. 0 snaps instantly.
@export var fill_tween_time: float = 0.25

var _fill_tween: Tween


func _ready() -> void:
	scale = Vector2.ONE * min_scale


## Sets how full the gauge should look, 0.0 (empty, min_scale) to 1.0 (full,
## max_scale). Safe to call every time strikes change - out-of-range ratios
## are clamped rather than trusted.
func set_fill_ratio(ratio: float) -> void:
	var target_scale := lerpf(min_scale, max_scale, clampf(ratio, 0.0, 1.0))
	if _fill_tween:
		_fill_tween.kill()
	if fill_tween_time <= 0.0:
		scale = Vector2.ONE * target_scale
		return
	_fill_tween = create_tween()
	_fill_tween.tween_property(self, "scale", Vector2.ONE * target_scale, fill_tween_time)
