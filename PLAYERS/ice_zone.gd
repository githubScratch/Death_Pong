extends Area2D
class_name IceZone

## Spawned by wizard.gd's _cast_ice_zone() the instant a double-tap commits
## on a wizard whose ability is an IceAbility (PLAYERS/ice_ability.gd) -
## the "double tap left/right to drop a slowing zone" replacement for the
## old hold-to-grow trap. Fully independent once spawned: nothing in
## wizard.gd keeps a reference to this after add_child(), it doesn't
## follow or grow, and it cleans itself up entirely on its own timeline.
##
## Slows (or, at slow_amount 1.0, fully stops - same convention
## IceAbility.slow_amount and Ball/Wizard.freeze_in_place() already use)
## anything overlapping it for as long as it's actually inside,
## continuously - not a one-time catch. Reuses Ball/Wizard's existing
## freeze_in_place()/thaw() pair as-is (same duck-typed has_method() shape
## deflection_shield.gd already relies on) rather than inventing a second
## slow mechanism: freeze_in_place() is called the instant a body enters,
## with a duration far longer than this zone could ever live, so a body's
## own internal countdown never naturally expires while inside - thaw() is
## instead called explicitly BY THIS ZONE, the moment a body exits
## (_on_body_exited) or the moment the zone itself despawns while a body is
## still inside (_despawn()). That's what actually makes "stays slowed only
## while inside" true, rather than a timer on the body.
##
## Configured entirely by whoever spawns it (see configure()) - nothing
## here is meant to be hand-tuned per-instance in the Inspector, every knob
## lives on IceAbility instead and flows through wizard.gd's
## _cast_ice_zone().
##
## The visual (self_vfx_scene, IceAbility.self_vfx_scene) is instantiated
## here IN CODE at _ready() time, the same way every other VFX attachment in
## this project works (_start_growth_vfx(), _spawn_blink_vfx(),
## _spawn_frozen_overlay(), ...), rather than being baked into ice_zone.tscn
## as a static instanced-scene child the way an earlier version of this file
## had it (that static version turned out to just not show up at all - the
## Area2D/CollisionShape2D, authored directly in ice_zone.tscn rather than
## instanced, kept working fine regardless). It's added as a child of THIS
## zone (so it still scales with the zone's own tier-based size - see
## configure()), but its POSITION is overridden to the caster's own
## global_position at the moment of casting, not this zone's - "self," not
## "zone": it reads as a burst on the wizard casting the spell, not a marker
## for where the zone itself is. It does not follow the wizard afterward
## (same drop-and-forget snapshot _spawn_blink_vfx() already uses elsewhere
## in this project) - just positioned once, here, at _ready() time.

## The CollisionShape2D's authored CircleShape2D radius this scene was
## built at - IceAbility.zone_size/zone_size_per_tier are scale
## MULTIPLIERS of this baseline (see configure()), not raw pixel radii, so
## retuning the base shape here changes what "1.0" means everywhere without
## touching any other script.
const BASE_RADIUS := 56.0

# Comfortably longer than any zone_duration/zone_duration_per_tier
# combination could plausibly reach. freeze_in_place()'s own duration
# argument is irrelevant to this zone's actual lifetime - this zone calls
# thaw() explicitly rather than ever letting a caught body's own countdown
# expire on its own (see this file's doc comment above), so this constant
# only needs to be "large enough that it never fires first."
const _NEVER_EXPIRES := 1.0e9

var caster: Node = null
var affects_caster: bool = false
var affects_other_wizards: bool = true
var slow_amount: float = 0.5
var duration: float = 2.0
var despawn_delay: float = 0.3
var frozen_ball_overlay: PackedScene
var frozen_wizard_overlay: PackedScene
var self_vfx_scene: PackedScene

## The direction this zone was thrown in (-1.0 left, 1.0 right - same sign
## wizard.gd's _cast_ice_zone() itself uses) - purely so self_vfx_scene can
## be mirrored to actually face the cast direction instead of always
## rendering however its art was originally authored (right-facing, here).
## Doesn't affect this zone's own collision/slow behavior at all - a circle
## looks the same either way - only _ready()'s vfx flip below reads this.
var cast_direction: float = 1.0

var _vfx: Node2D = null
var _vfx_anim: AnimationPlayer = null

var _remaining: float = 0.0
var _bodies_inside: Array = []
var _despawning: bool = false


## Sets every knob on this zone before it's added to the tree - call this
## right after instantiate(), before add_child(). p_scale is a multiplier
## on BASE_RADIUS (see that const's doc comment), applied as this node's
## own Node2D scale so the collision shape and the (code-instantiated)
## self_vfx_scene visual both grow together for free, no separate sizing
## math needed per child.
func configure(p_scale: float, p_slow_amount: float, p_duration: float, p_despawn_delay: float, p_caster: Node, p_affects_caster: bool, p_affects_other_wizards: bool, p_frozen_ball_overlay: PackedScene, p_frozen_wizard_overlay: PackedScene, p_self_vfx_scene: PackedScene, p_cast_direction: float) -> void:
	scale = Vector2.ONE * p_scale
	slow_amount = p_slow_amount
	duration = p_duration
	despawn_delay = p_despawn_delay
	caster = p_caster
	affects_caster = p_affects_caster
	affects_other_wizards = p_affects_other_wizards
	frozen_ball_overlay = p_frozen_ball_overlay
	frozen_wizard_overlay = p_frozen_wizard_overlay
	self_vfx_scene = p_self_vfx_scene
	cast_direction = p_cast_direction


func _ready() -> void:
	monitoring = true
	_remaining = duration
	body_entered.connect(_on_body_entered)
	body_exited.connect(_on_body_exited)
	if is_instance_valid(self_vfx_scene):
		_vfx = self_vfx_scene.instantiate()
		add_child(_vfx)
		# Positioned at the CASTER, not left at this zone's own origin - see
		# this file's doc comment above for why. caster can in principle be
		# gone already (freed) by the time this runs; if so the vfx just
		# stays at this zone's own position instead, rather than erroring.
		if is_instance_valid(caster):
			_vfx.global_position = caster.global_position
		# self_vfx_scene's art is authored facing right - mirror it on a
		# left cast so it actually points the way the zone was thrown
		# instead of always rendering right-facing regardless of
		# cast_direction. Flips the WHOLE instanced vfx root (not a
		# specific Sprite2D/AnimatedSprite2D's flip_h), since a vfx scene
		# built from particles or multiple layered nodes has no single
		# "the sprite" to flip - negating Node2D.scale.x mirrors everything
		# under it at once regardless of what it's actually made of.
		if cast_direction < 0.0:
			_vfx.scale.x = -absf(_vfx.scale.x)
		_vfx_anim = _vfx.get_node_or_null("AnimationPlayer") as AnimationPlayer
	if _vfx_anim != null and _vfx_anim.has_animation("hold"):
		_vfx_anim.play("hold")


func _physics_process(delta: float) -> void:
	if _despawning:
		return
	_remaining -= delta
	if _remaining <= 0.0:
		_despawn()


## A body neither in the "ball" nor "wizard" group, or without
## freeze_in_place() at all, is never touched - same duck-typed opt-in
## shape used everywhere else in this project. The caster is excluded
## entirely unless affects_caster is true (see IceAbility.self_affected).
## A wizard that ISN'T the caster is further gated by affects_other_wizards
## (IceAbility.affects_other_wizards) - false turns this into a ball-only
## zone, letting every other wizard walk through untouched, same as if they
## weren't in the "wizard" group at all; balls are never affected by this
## knob either way.
func _eligible(body: Node) -> bool:
	if body == caster and not affects_caster:
		return false
	if not body.has_method("freeze_in_place"):
		return false
	if body.is_in_group("wizard") and body != caster and not affects_other_wizards:
		return false
	return body.is_in_group("ball") or body.is_in_group("wizard")


func _on_body_entered(body: Node) -> void:
	if _despawning or not _eligible(body):
		return
	if not _bodies_inside.has(body):
		_bodies_inside.append(body)
	var overlay := frozen_ball_overlay if body.is_in_group("ball") else frozen_wizard_overlay
	body.freeze_in_place(_NEVER_EXPIRES, slow_amount, overlay)


## Ends this body's slow the moment it actually leaves the zone - not on a
## timer - which is the whole point of this zone reusing freeze_in_place()
## with a duration that never naturally expires (see this file's doc
## comment above). No-op (via thaw()'s own guard) for a body this zone
## never actually froze in the first place - e.g. the caster grazing the
## Area2D while affects_caster is false, which _on_body_entered() already
## skipped freezing.
func _on_body_exited(body: Node) -> void:
	_bodies_inside.erase(body)
	if body.has_method("thaw"):
		body.thaw()


## Ends this zone's life: stops catching anything new, thaws out whatever's
## still inside right now (so nothing stays frozen forever just because it
## happened to still be standing in the zone when duration ran out), plays
## the vfx's one-shot outro clip if it has one, then waits despawn_delay
## before actually queue_free()ing - purely so that outro has room to
## finish playing instead of the zone vanishing mid-animation.
func _despawn() -> void:
	_despawning = true
	monitoring = false
	for body in _bodies_inside.duplicate():
		if is_instance_valid(body) and body.has_method("thaw"):
			body.thaw()
	_bodies_inside.clear()
	if _vfx_anim != null and _vfx_anim.has_animation("trap release"):
		_vfx_anim.play("trap release")
	if despawn_delay > 0.0:
		await get_tree().create_timer(despawn_delay).timeout
	queue_free()
