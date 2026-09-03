extends Sprite2D
class_name StrikeGauge

## Visualizes a wizard's banked strikes as a liquid level rising inside the
## SAME circular footprint the old scaling bead used to occupy, drawn
## entirely by strike_gauge_vial.gdshader - the disc shape and the rising
## fill are all computed per-pixel from the shader's fill_level uniform, so
## this node's own sprite texture is only ever used for sizing/UV and never
## actually shown. Not a literal glass vial - just the old bead, still the
## same size and shape, filling by rising liquid level instead of by
## scaling up from a point. See wizard.gd's
## _update_strike_gauge()/_max_banked_strikes() for how the ratio is
## computed. Purely cosmetic - carries no gameplay data itself, just
## reflects whatever ratio it's told to show.
##
## Opt-in per shield scene, same pattern the ability composition hierarchy
## uses: wizard.gd looks for a child node named "StrikeGauge" on whatever
## shield is currently spawned and does nothing if it isn't there, so adding
## this to one class's shield never affects any other class, and no shield
## is forced to carry a gauge it doesn't want. A fresh ShaderMaterial is
## built per-instance in _ready() rather than authored on the node in the
## .tscn, so every wizard's gauge gets its own independent fill/slosh state
## instead of accidentally sharing one material resource across every
## instance of the shield scene.

## Tint of the liquid itself.
@export var liquid_color: Color = Color(1.0, 0.85, 0.3, 1.0)

## Radius (in the sprite's own 0..0.5-from-center UV units) of the disc the
## liquid fills - matches the old bead texture's own solid zone by default,
## so the fill occupies the same footprint the old scaling bead did. Tune
## per shield scene to fit its own art, same spirit as the old
## min_scale/max_scale knobs.
@export var radius: float = 0.425

## Width of the soft fade at the disc's edge (in the same UV units as
## radius) - matches the old bead texture's own fade band by default.
@export var edge_softness: float = 0.075

## A fixed rest-state curve on the liquid's surface, separate from the
## transient slosh wave above - a real meniscus, for a little extra depth
## even when the gauge is sitting still. Positive curves it concave (the
## center dips slightly below the edges, like liquid climbing a glass
## wall); negative curves it convex (the center domes slightly above the
## edges, like mercury). 0 is perfectly flat.
@export var meniscus_amount: float = 0.05

## Seconds for the gauge to visually catch up to a new fill ratio, rather
## than snapping instantly - reads more like a liquid pouring in than a bar
## jumping. 0 snaps instantly.
@export var fill_tween_time: float = 0.25

## How hard a deflected ball kicks the liquid's surface - see
## slosh_from_impact(). Tuned to read clearly against `radius` above; if it
## ever looks too violent or too subtle, scale this rather than
## slosh_stiffness/slosh_damping.
@export var deflect_slosh_kick: float = 1.6

## How hard summoning a fresh shield kicks the liquid's surface - see
## slosh_from_summon(). Deliberately gentler than deflect_slosh_kick: a cast
## is a quieter moment than getting struck by the ball, so its "bloop"
## should read as a settling-in rather than a jolt.
@export var summon_slosh_kick: float = 0.5

## Spring constant pulling the sloshing surface back toward flat - controls
## how FAST each individual wobble is, not how long they last. Higher =
## quicker, tighter oscillation; lower = a slower, lazier wave.
@export var slosh_stiffness: float = 60.0

## Velocity damping on the slosh spring per second - controls how LONG the
## slosh takes to settle, not its speed. Higher = dies out in a wobble or
## two; lower = keeps visibly rocking back and forth for longer before
## coming to rest. This is the knob for "more/less gradual."
@export var slosh_damping: float = 2.2

var _material: ShaderMaterial
var _fill_tween: Tween
var _fill_ratio: float = 0.0

var _slosh_offset: float = 0.0
var _slosh_velocity: float = 0.0


func _ready() -> void:
	_material = ShaderMaterial.new()
	_material.shader = preload("res://PLAYERS/strike_gauge_vial.gdshader")
	material = _material
	_material.set_shader_parameter("liquid_color", liquid_color)
	_material.set_shader_parameter("meniscus_amount", meniscus_amount)
	_material.set_shader_parameter("radius", radius)
	_material.set_shader_parameter("edge_softness", edge_softness)
	_material.set_shader_parameter("fill_level", 0.0)
	_material.set_shader_parameter("wobble_amount", 0.0)


func _process(delta: float) -> void:
	# Cheap damped spring, not an actual fluid sim: slosh_from_impact()/
	# slosh_from_summon() nudge the velocity, this pulls the offset back
	# toward 0 and bleeds the velocity off, so a strike (or a cast) reads as
	# a jolt that rings down to still liquid on its own rather than needing
	# to be reset anywhere.
	if _slosh_offset == 0.0 and _slosh_velocity == 0.0:
		return
	_slosh_velocity -= _slosh_offset * slosh_stiffness * delta
	_slosh_velocity *= clampf(1.0 - slosh_damping * delta, 0.0, 1.0)
	_slosh_offset += _slosh_velocity * delta
	if absf(_slosh_offset) < 0.001 and absf(_slosh_velocity) < 0.001:
		_slosh_offset = 0.0
		_slosh_velocity = 0.0
	_material.set_shader_parameter("wobble_amount", _slosh_offset)


## Sets how full the gauge should look, 0.0 (empty) to 1.0 (full). Safe to
## call every time strikes change - out-of-range ratios are clamped rather
## than trusted.
func set_fill_ratio(ratio: float) -> void:
	var target := clampf(ratio, 0.0, 1.0)
	if _fill_tween:
		_fill_tween.kill()
	if fill_tween_time <= 0.0:
		_fill_ratio = target
		_material.set_shader_parameter("fill_level", _fill_ratio)
		return
	_fill_tween = create_tween()
	_fill_tween.tween_method(_apply_fill_level, _fill_ratio, target, fill_tween_time)


func _apply_fill_level(value: float) -> void:
	_fill_ratio = value
	_material.set_shader_parameter("fill_level", value)


## Kicks the liquid's surface with deflect_slosh_kick, as if it just got
## struck - call this whenever the shield actually deflects something (see
## wizard.gd's _on_shield_deflected()). Purely additive so back-to-back
## strikes pile the impulse on rather than resetting it, and it decays on
## its own in _process() - no matching "stop" call needed anywhere.
func slosh_from_impact(strength: float = 1.0) -> void:
	_slosh_velocity += deflect_slosh_kick * strength


## Kicks the liquid's surface with the gentler summon_slosh_kick, as if it
## just settled into place - call this whenever a fresh shield is cast (see
## wizard.gd's create_new_instance()). Same additive/self-decaying shape as
## slosh_from_impact(), just a softer kick.
func slosh_from_summon(strength: float = 1.0) -> void:
	_slosh_velocity += summon_slosh_kick * strength
