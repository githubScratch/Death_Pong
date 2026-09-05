# Death Pong ("Wizard Balls") - working notes for Claude

Godot 4.4 local-multiplayer Pong/brawler hybrid. These are conventions this
project has settled on, mainly so a future session (or the same one, later)
doesn't relitigate them.

## Don't revert hand-tuned values

Numeric fields on ability `.tres` resources (strike costs, durations, scale
steps, hold buffers, etc.) get hand-tuned directly in the Godot inspector
for balance, outside of any conversation with Claude. When editing a
`.tres` (or the script whose defaults back it), always re-read the CURRENT
live file first and preserve whatever values are already there - never
reset a field to an earlier value from memory or to a script default,
unless the user explicitly asks for that value to change. Only add/remove/
restructure fields as needed for the actual request; leave every value you
aren't specifically asked to touch exactly as found.

## Ability composition pattern

`WizardAbility` (`PLAYERS/wizard_ability.gd`) is the bare base every class's
ability resource uses - just `display_name` and `shield_scene`. Fields
specific to one *kind* of ability live on a subclass, never on the shared
base, so classes that don't use a mechanic don't carry its fields in the
inspector:

- `StrikeScaledAbility` (`PLAYERS/strike_scaled_ability.gd`) - shared shape
  for any ability that scales with banked strikes: `strikes_per_tier`,
  `max_tiers`, `max_strikes`. Extend this, don't re-declare these fields per
  ability, whenever a new class's ability spends banked strikes in chunks.
- `GrowthAbility` (`PLAYERS/growth_ability.gd`) extends `StrikeScaledAbility`
  - Nature's hold-to-grow barrier (`tier_scale_step`,
    `growth_duration_per_tier`, `shrink_duration`, `hold_confirm_time`,
    `tier_stutter_time`, `post_channel_hold_time`, plus a computed
    `growth_tier_scales()`). Continuous hold-and-spend: pays for each tier
    the instant its growth window starts, one tier at a time, while Up is
    held.
- `BlinkAbility` (`PLAYERS/blink_ability.gd`) extends `StrikeScaledAbility`
  - class 1's double-tap-to-teleport (`blink_distance`,
    `double_tap_window`). Instant and discrete instead of continuous: each
    activation spends exactly one tier's worth of strikes all at once, and
    unspent tiers just stay banked as charges rather than being forced out
    the way growth's are - see `wizard.gd`'s `_update_blink()` /
    `_try_blink()`. Cashing in a blink OR a slam-wrap landing (see below)
    while already sitting on a full `max_tiers` bank spends EVERYTHING
    banked instead of the usual flat one-tier cost, and - if
    `clone_on_max_tier` is true - spawns a temporary input-mirroring clone
    (`wizard.gd`'s `_spawn_blink_clone()`/`_despawn_clone()`, gated by the
    new `class_name Wizard`/`class_name WizardSeat` declarations added for
    it - see "Blink max-tier clone" below).

`wizard.gd` checks ability type with `is`/`as` (e.g. `ability is
GrowthAbility`), never a boolean flag on the shared base - that's the
mechanism that keeps this opt-in per-class instead of bloating every ability
resource. When a new ability needs its own scaling mechanic, follow this
same pattern: a focused subclass (of `StrikeScaledAbility` if it scales with
strikes, of `WizardAbility` directly if not) rather than adding fields to a
shared base.

### Class 3 - Ice (Ice Zone)

`IceAbility` (`PLAYERS/ice_ability.gd`) extends `StrikeScaledAbility`.
`ability_3.tres` points at it (`display_name = "Ice"`,
`strikes_per_tier`/`max_tiers`/`max_strikes` = 2/3/6), and `class_3.tres`'s
`display_name` is `"Ice"`, already wired into `character_select.gd`'s
`CLASSES` array.

`spell_3.tscn` (the shield scene) is a fully-built, ice-blue-tinted shield -
`deflect`/`fade`/`light` animations, particles, lights, a `StrikeGauge`
child tinted icy blue - using the shared `deflection_shield.gd`, same as
every other class. **This is back to being a plain, always-functioning
barrier** exactly like `spell_1`/`spell_2`/`spell_4`: an earlier version of
this session had Ice transform the shield itself into a hold-to-grow trap
(pass-through mode, a fading barrier, an attached trap VFX...) - that whole
approach was scrapped and rebuilt from scratch as the zone-based ability
below instead, because it wasn't feeling right in practice. Nothing about
casting or holding Up does anything Ice-specific anymore; `spell_3.tscn`'s
`"trap"` animation stub is back to being the empty placeholder it was before
that experiment (unused, harmless to leave there).

**The Ice Zone mechanic** (`wizard.gd`'s `_update_ice_zone()` /
`_cast_ice_zone()`, `PLAYERS/ice_zone.gd`/`ice_zone.tscn`, plus
`freeze_in_place()`/`thaw()` on both `wizard.gd` and `ARENAS/ball.gd`,
carried over unchanged from the scrapped trap version):

Double-tapping Left or Right (within `IceAbility.double_tap_window` of each
other - exact same detection shape `BlinkAbility` already uses for its own
double-tap, tracked with Ice's own separate
`_ice_left_tap_window_remaining`/`_ice_right_tap_window_remaining` rather
than sharing Blink's, same "each mechanic gets its own state" split this
file already follows elsewhere) drops a slowing, circle-shaped zone
(`IceAbility.zone_scene`, `PLAYERS/ice_zone.tscn`) at a fixed point in the
tapped direction. Spends every currently-banked tier at once, up to
`max_tiers` (`floor(strikes / strikes_per_tier)`, clamped) - needs at least
one full tier banked or the double-tap just doesn't cast anything, same as
Blink denying an unaffordable blink. The zone's size/slow-strength/lifetime
all scale up with however many tiers that cast spent -
`zone_scale_for_tier()`/`zone_slow_for_tier()`/`zone_duration_for_tier()` on
`IceAbility`, tier 1 exactly the base knob, each tier after adding another
step, same "tier N = base + step * (N-1)" shape the old trap's
`trap_tier_scales()` used.

The zone spawns at `global_position + direction * IceZone.BASE_RADIUS *
zone_scale` - just past its own spawn-time radius, so a bigger zone (more
tiers spent) naturally reaches further out without a separate distance
knob. It's a fully independent `Area2D` scene once spawned: nothing in
`wizard.gd` keeps a reference to it after `add_child()`, it doesn't follow
or grow, and `IceZone.configure()` (called once, right after
`instantiate()`, before `add_child()`) sets every knob on it - `zone_scale`
becomes its own `Node2D.scale`, which grows the `CollisionShape2D`'s
`CircleShape2D` (authored at `IceZone.BASE_RADIUS = 56.0`, matching the
shields' own collision radius) and `self_vfx_scene`'s visual together for
free.

`IceAbility.self_vfx_scene` (renamed from `zone_vfx_scene` - originally
`VFX/Ice_Trap.tscn`, now `VFX/Ice_Blast.tscn`) is instantiated in code,
inside `IceZone._ready()` (`self_vfx_scene.instantiate()` + `add_child()`,
then `get_node_or_null("AnimationPlayer")` for the `"hold"`/`"trap release"`
clips) - the same pattern every other VFX attachment in this project already
uses (`_start_growth_vfx()`, `_spawn_blink_vfx()`, `_spawn_frozen_overlay()`).
An earlier draft of `ice_zone.tscn` instead baked the vfx in as a static
instanced-scene child node (`[node ... instance=ExtResource(...)]`), the one
place in the codebase that diverged from that convention, and it just never
showed up in play - the Area2D/CollisionShape2D (authored directly in
`ice_zone.tscn`, not instanced) kept working fine, which is what let the
zone's slow effect work correctly while the visual stayed invisible.
`ice_zone.tscn` itself is back to just the bare `Area2D` + `CollisionShape2D`.

`self_vfx_scene` is added as a CHILD of the `IceZone` node (so it still
scales with the zone's tier-based size), but its `global_position` is then
overridden to the CASTING WIZARD's own position at the moment of casting,
not left at the zone's own spawn point - a "self" burst on the caster, not
a marker for where the zone itself is, matching the rename. It does not
follow the wizard afterward, same drop-and-forget snapshot positioning
`_spawn_blink_vfx()` already uses elsewhere in this project - just placed
once, at `IceZone._ready()` time. It's a separate field from `zone_scene`
above precisely because `zone_scene` is the actual gameplay object and
`self_vfx_scene` is only ever a cosmetic look - null skips spawning any
visual at all but the zone still slows normally.

`self_vfx_scene`'s art is authored facing right, so `IceZone.cast_direction`
(-1.0 left, 1.0 right - the same `direction` `_cast_ice_zone()` already
computes from which key was double-tapped, now threaded through
`configure()`'s new final argument) mirrors the WHOLE instanced vfx root by
negating its `Node2D.scale.x` on a left cast, rather than looking for one
specific `Sprite2D`/`AnimatedSprite2D` to flip - a vfx built from particles
or several layered nodes has no single "the sprite" the way
`_spawn_blink_vfx()`'s `flip_h` approach assumes, so mirroring the whole
root's scale works regardless of what `self_vfx_scene` actually contains.

**Continuous slow, not a one-time catch**: an object stays slowed for as
long as it's actually inside the zone, full stop, and goes right back to
normal the instant it leaves - not on a timer. This reuses
`freeze_in_place()`/`thaw()` exactly as the old trap left them (same
duck-typed `has_method()` shape `deflection_shield.gd` already relies on,
so a frozen ball and a frozen wizard are handled identically) rather than
inventing a second slow mechanism: `IceZone._on_body_entered()` calls
`freeze_in_place()` the instant a body enters, passing a `duration` far
larger than any zone could ever live (`IceZone._NEVER_EXPIRES`, `1.0e9`) so
a caught body's own internal countdown never naturally expires while
inside - `IceZone._on_body_exited()` calls `thaw()` explicitly instead, the
moment a body actually leaves, and `IceZone._despawn()` thaws out whatever's
still inside when the zone's own lifetime runs out, so nothing stays frozen
forever just because it happened to still be standing there. The caster's
own zone skips the caster entirely unless `IceAbility.self_affected` is
checked - the checkbox - same "never affects the caster by default"
convention every other class's ability already used (Growth's channel,
Blink's teleport, the old trap's freeze query).

`IceAbility.affects_other_wizards` (bool, default true) is a separate knob
from `self_affected` above - `self_affected` only ever gated whether the
CASTER's own zone can catch the caster; this one gates whether the zone can
catch any OTHER wizard at all. False turns Ice into a purely anti-ball/
utility zone: balls are slowed exactly as before, the caster still gets
their own `self_knockback` recoil, but every other wizard just walks
through untouched, as if they weren't in the `"wizard"` group. Threaded
through as a new `IceZone.configure()` parameter
(`affects_other_wizards`) and checked in `IceZone._eligible()` right next
to the existing caster-exclusion check.

`slow_amount`/`slow_amount_per_tier` (0..1, clamped after adding tiers) work
exactly like the old trap's `slow_amount` did: 1.0 zeroes a target's
velocity/spin outright and stops gravity outright ("remains in place" - "at
1 we have stopped entirely state"), lower values leave some of its existing
motion to carry through at a reduced rate. Both `freeze_in_place()`
implementations (`ball.gd`'s `gravity_scale` trick, `wizard.gd`'s manual
per-frame scaled gravity) and their three fixed bugs (permanently orphaned
overlays from a `thaw()` guard racing the countdown; a per-frame velocity
re-damp that crushed any partial value to a full freeze; a grounded
wizard's scaled-gravity term being gated behind `is_on_floor()` so a
standing-still catch never visibly showed a partial value) are unchanged
carryovers from that version - see git history/the previous state of this
file if the exact blow-by-blow is ever needed again, not repeated here
since none of it is Ice-specific anymore now that a Zone (not a Trap)
calls into it.

**A wizard caught in a zone still moves, just slower** - a fourth
`freeze_in_place()`/`_physics_process()` fix, this one specific to the Zone
version rather than carried over: the old trap-era frozen branch locked out
LEFT/RIGHT movement input unconditionally, full stop, no matter what
`slow_amount` was set to - only gravity's pull scaled with the knob. That
made sense for a hard "trap," but the Zone's whole framing is "slow, not
stop unless maxed," so a caught wizard now still reads
`Input.get_axis()`/moves at `SPEED * (1.0 - _frozen_slow_amount)` right there
in the frozen branch - full speed at `slow_amount` 0.0, genuinely immobile
only at 1.0, a visible reduced shuffle in between. Jump, dive, casting, and
every hold-based ability stay fully locked out regardless of `slow_amount` -
only movement itself scales; flip this if a slowed wizard should also be
able to jump/dive/cast at low `slow_amount` values instead.

**`thaw()` no longer zeroes velocity** on either `ball.gd` or `wizard.gd` - a
fifth fix, also Zone-specific. The old trap-era `thaw()` always hard-reset
`linear_velocity`/`angular_velocity` (ball) or `velocity` (wizard) to zero,
"dropping" whatever was caught rather than letting it resume - a deliberate
"catch," matching a physical trap. The Zone is framed as a temporary,
localized time slow instead ("a temporary slowing magic zone, not a complete
remover of external forces"), so a target should keep whatever momentum it
already had (already reduced by `slow_amount`, still being acted on by
scaled-down gravity the whole time it's caught - see `freeze_in_place()`)
and simply resume it at full strength once thawed, rather than restarting
from a dead stop. A ball hit while frozen still flies off correctly - the
deflect's own new velocity overwrites whatever `thaw()` leaves it at
immediately after, on both `ball.gd` (`deflection_shield.gd`'s
`deflect_ball()`) and `wizard.gd` paths.

Placeholder overlays: `VFX/Frozen_Ball.tscn` and `VFX/Frozen_Wizard.tscn`,
simple untextured `Polygon2D` + `Line2D` "ice shard" shapes, spawned as a
child of a caught target for as long as it stays inside the zone via
`IceAbility.frozen_ball_overlay`/`frozen_wizard_overlay`. On `thaw()`,
`Ball`/`Wizard._clear_frozen_overlay()` now plays the overlay's own one-shot
`"fade"` clip first (its own `AnimationPlayer`, guarded with
`has_animation()` - same safe-before-the-clip-exists shape
`deflection_shield.gd`'s `start_fade()` already uses) before actually
`queue_free()`ing it, rather than popping it off instantly the moment the
target exits the ice ability - a fifth Zone-specific fix (see the momentum
one above). `_frozen_overlay` is cleared to null immediately, before the
fade even starts, so a fresh freeze that re-spawns a new overlay while the
old one is still fading never clobbers or double-frees it - the old one
just finishes fading and frees itself independently in the background, same
fire-and-forget coroutine shape `IceZone._despawn()`'s own `await` already
uses.

The zone despawns on its own timeline, independent of the caster:
`IceAbility.zone_duration`/`zone_duration_per_tier` set how long it actually
exists and keeps catching/holding bodies; once that runs out,
`IceZone._despawn()` stops monitoring, thaws everything still inside, plays
`self_vfx_scene`'s one-shot `"trap release"` clip on the vfx child if it
has one (guarded with `has_animation()`, same safe-before-the-clip-exists
shape used everywhere), then waits `IceAbility.despawn_delay` - "time to
`queue_free()` the object after the duration" - before actually freeing the
node, so that outro has room to finish playing instead of the zone just
vanishing mid-animation.

The cast also gives the wizard a bit of recoil, via `wizard.gd`'s
`_apply_ice_knockback()`: `IceAbility.self_knockback` sets `velocity.x` once,
as a single hard jolt in the direction OPPOSITE the cast - the same
"one impact, one new velocity" shape `ball.gd`'s deflect gets off a shield
(`deflection_shield.gd`'s `deflect_ball()`: `linear_velocity = direction *
deflection_force`), not additive on top of whatever velocity.x the wizard
already had. A `Tween` (`tween_method`, ease-out/cubic) then eases that
jolt back down to 0 over `IceAbility.knockback_lock_time`, instead of
holding at full force for the whole window or being cut off abruptly.
`_physics_process()`'s normal LEFT/RIGHT movement-input handling is skipped
for that same `knockback_lock_time` window (`_ice_input_lock_remaining`) so
the jolt/Tween isn't instantly fought and overwritten the same physics frame
by whatever direction the player's still holding from the double-tap that
triggered it - the "competing commands" a knockback with no lock at all was
losing to. Jumping, diving, and casting are unaffected; only the
direction-based movement code is held off. An earlier version of this also
suspended gravity for the same window (a "hover", mirroring Growth's channel
hover) so the knockback would carry through the air, but that conflicted
with this wizard's own jump/dive/landing logic (which assumes gravity is
never paused) and produced bad jump behavior, so it was dropped entirely -
gravity is always normal now.

Inspector knobs on `ability_3.tres` (all on `IceAbility`): `double_tap_window`
(tap-vs-tap buffer), `zone_size`/`zone_size_per_tier` ("size"/"additional
size per tier", a scale multiplier on `IceZone.BASE_RADIUS`),
`slow_amount`/`slow_amount_per_tier` ("slow"/"additional slow per tier", 0..1
each), `zone_duration`/`zone_duration_per_tier` ("duration of slow
area"/"additional duration per tier"), `despawn_delay` ("time to
queue_free the object after the duration"), `self_knockback` (force of the
one-time recoil jolt - see above), `knockback_lock_time` (seconds normal
LEFT/RIGHT movement input is held off after a cast so the jolt isn't
instantly overwritten - replaces the old `hover_time`, which also paused
gravity and was dropped), `self_affected` (the checkbox - can the ice mage
be slowed by its own zone), `affects_other_wizards` (can the zone slow any
OTHER wizard at all - false leaves it slowing balls only), `zone_scene` (the interactive zone itself,
`ice_zone.tscn` - not opt-out/null-able like the vfx-only fields below it,
since it IS the ability's gameplay object), `self_vfx_scene` (the cosmetic
visual `IceZone` instantiates in code at `_ready()`, positioned at the
casting wizard rather than the zone - see above), and
`frozen_ball_overlay`/`frozen_wizard_overlay` (carried over unchanged from
the old trap).

Assumption still worth flagging (carried over from the old trap version,
still true here since it touched shared infrastructure, not anything
Ice-specific): the "hit by another shield's deflect thaws it early" rule in
`deflection_shield.gd` was widened to ANY class's shield, not just Ice's -
easy to narrow back to Ice-only later by reverting just the
`collision_mask` changes on `spell_1`/`spell_2`/`spell_4.tscn` if that's not
the intent.

## Strike gauge (banked-strikes visual - a rising fill, not a scaling bead)

`StrikeGauge` (`PLAYERS/strike_gauge.gd`, extends `Sprite2D`) is a small
opt-in cosmetic node: drop it as a child named exactly `StrikeGauge` into
any shield scene and `wizard.gd`'s `_update_strike_gauge()` will drive it
automatically - same opt-in shape as the ability composition pattern above:
a shield with no `StrikeGauge` child is simply skipped, no bloat forced
onto it.

Originally this was a `Sprite2D` scaled from a small bead up to a "full"
size. It still reads as that same bead - same soft-edged circular
footprint, same spot on the shield, no glass/vial container drawn around
it - but now fills by a liquid level rising inside that fixed-size disc
instead of by the whole shape scaling up from a point. Drawn entirely by
`PLAYERS/strike_gauge_vial.gdshader`: the disc's shape (`radius`/
`edge_softness`, tuned by default to match the old `Gradient_sgauge`
texture's own solid-to-faded falloff) and the fill line are both computed
per-pixel from the shader's `fill_level` uniform (0..1), so the node's own
sprite `texture` is only there for sizing/UV and is never actually shown;
the gauge's on-screen size is now just the node's ordinary Transform >
Scale in the Inspector - no more `min_scale`/`max_scale` script exports.
`_ready()` builds a fresh `ShaderMaterial` per instance (rather than
authoring one in the `.tscn`) so every wizard's gauge has independent
fill/slosh state instead of risking several instances sharing one material
resource. `liquid_color`, `radius`, `edge_softness`, and `fill_tween_time`
are exported so each class's shield can tune its own gauge without
touching the shader or the script.

Fill ratio is still banked TIERS, not raw strikes: `floor(strikes /
strikes_per_tier) / max_tiers`, deliberately floored so a partial tier's
worth of strikes (not yet spendable) doesn't read as partial visual
progress - only a completed, spendable tier moves the gauge.

Bonus: the liquid sloshes. `StrikeGauge.slosh_from_impact()` is called from
`wizard.gd`'s `_on_shield_deflected()` (every successful deflect) and
`StrikeGauge.slosh_from_summon()` from `create_new_instance()` right after
a fresh shield is cast and its gauge is synced to whatever's already
banked - a little "bloop" on summon, only actually visible when strikes
carried over into the new cast, since an empty gauge has no liquid to
slosh. Both are the same shape (purely additive, self-decaying, no "stop"
call needed anywhere) and just nudge the same spring's velocity by their
own kick amount - `deflect_slosh_kick` for the impact one,
`summon_slosh_kick` for the summon one, deliberately gentler since a cast
is a quieter moment than getting struck. `_process()` integrates a tiny
damped spring (`slosh_stiffness`/`slosh_damping`) each frame off whichever
kick landed, feeding the result into the shader's `wobble_amount` uniform,
which bends the flat fill line into a `sin()` wave. This is a cheap
spring-driven wobble, not an actual fluid sim - deliberately so, that would
be overkill for a UI element this size.

Four separate knobs, four separate jobs - don't reach for the wrong one:
`deflect_slosh_kick` (default `1.6`) and `summon_slosh_kick` (default
`0.5`) are how BIG each event's initial jolt is - tuned so the impact one's
peak displacement is a clearly visible chunk of `radius` rather than a
fraction of a percent of it, and the summon one noticeably softer than
that. `slosh_stiffness` (default `60.0`) is how FAST each individual
wobble cycles - higher is a tighter, quicker wave, lower is slower and
lazier - and applies to both events equally, since it's a property of the
spring, not of what kicked it. `slosh_damping` (default `2.2`, lowered
from an initial `5.0` once the kicks were large enough to actually see) is
how LONG it takes to settle - lower keeps it visibly rocking for longer
before coming to rest, which is the knob for "more/less gradual" - also
shared between both events.

The surface also has a fixed rest-state curve, separate from the slosh
wave: `meniscus_amount` (default `0.05`, exported on `StrikeGauge`) adds a
static parabola to the surface line - full strength at the center, fading
to 0 at the disc's edges - for a little extra depth even when the liquid
is sitting still. Positive is concave (center dips below the edges, like
liquid climbing a glass wall - the default look, and how the gauge reads
below half full); negative is convex (center domes above the edges, like
mercury). Past half full the shader flips the sign on its own - shallow
liquid climbing the walls reads as concave, but once there's enough of it
banked the surface reads as domed/pressured instead - eased across a small
band around `fill_level == 0.5` (`smoothstep(0.45, 0.55, fill_level)`
picking the sign) rather than a hard snap, so the fill tween pouring
through the midpoint doesn't pop the curve inside-out in one frame.
`meniscus_amount` itself is unchanged by this - it's still just the one
Inspector knob per shield scene, passed to the shader once in `_ready()`;
the flip is baked into the shader's own math, not something the script
tracks or drives per-frame like `slosh_*`.

Currently wired into both `spell_1.tscn` (Blink) and `spell_2.tscn`
(Growth), each with its own tuned vial scale.

## Per-ability cast VFX (opt-in, self-cleaning)

Same opt-in shape again: `BlinkAbility.vfx_scene` (a `PackedScene`, unset by
default) is instantiated by `wizard.gd`'s `_spawn_blink_vfx()`, which drops
it at whatever `global_position` is at the moment it's called - so every
blink now spawns one at EACH end, consistently: `_try_blink()` calls it at
the CAST point (before `blink_delay`'s wind-up), and `_execute_blink()`
calls it again once `global_position` is fully settled (the landing point,
wall-wrapped or not). `_try_slam_wrap()` does the same pairing for its own
vertical teleport (ground strike point, then the ceiling). It plays the
instanced scene's `AnimatedSprite2D` once (flipped to face the blink
direction, or unflipped when called with `direction = 0.0`) and
`queue_free()`s the instance itself the moment that animation ends, so
nothing needs a timer or manual cleanup elsewhere - a scene just needs a
child literally named `AnimatedSprite2D` with a non-looping animation and
this handles the rest (falls back to a 1s timer if a future VFX scene
doesn't have one). `ability_1.tres` currently points this at
`VFX/Blink_VFX.tscn`. This is the first instance of the
"class-signature body effects → a small optional per-ability VFX child
scene" bucket from the earlier VFX-architecture discussion; if another
class wants the same treatment, give its own ability subclass its own
`vfx_scene` field and its own spawn function, rather than generalizing this
one prematurely - same reasoning as `StrikeScaledAbility` only getting
pulled out once two abilities actually needed it.

## Blink wall wrap (Arena only so far)

`_execute_blink()`'s `test_move()` collision check now branches on what it
hit, via a new `_wrap_destination()` lookup: if the collider is in the
`map_wall_left` or `map_wall_right` group, the wizard reappears at that
wall's own `WrapDestination` `Marker2D` child (X only - Y is untouched)
instead of stopping short. Anything not tagged into one of those groups
(another wizard, an untagged wall, a mid-arena platform) keeps the old
stop-at-the-clear-portion behavior unchanged. Currently only `arena.tscn`'s
`left`/`right` walls are tagged - `Tower` and `Yonder` use the same
collision layer for ALL their solid geometry (many scattered wall/platform
segments, not one clean boundary box), so neither has a well-defined single
"map wall" to wrap off of yet. Extending this to another arena means only a
scene change (tag the wall(s), add their own `WrapDestination` marker) - no
`wizard.gd` change needed, since the lookup is group-based, not a hardcoded
node path. Deliberately left/right only here - the bottom-to-top
counterpart is its own separate mechanic, see below.

## Blink slam wrap (floor -> ceiling)

`BlinkAbility.wrap_on_slam` (bool, default false) is the vertical
counterpart to the wall wrap above, but triggered completely differently:
not a blocked blink, but the airborne -> grounded landing transition in
`_physics_process()` (the same `if not hit_the_ground and is_on_floor():`
block that already plays the landing sound/squish), via
`wizard.gd`'s `_try_slam_wrap()`. Landing while holding Down, with
`wrap_on_slam` on and a full tier's worth of strikes banked, spends one
tier (same `strikes_per_tier` cost and "pay at commit" timing as a normal
blink) and moves the wizard's Y straight to the ceiling's own
`WrapDestination` marker (X untouched) instead of landing normally -
looked up via the `map_wall_top` group the same way the left/right wrap
looks up its walls, so it's equally scene-only to extend to another arena.
"Only while airborne" isn't a separate check - it falls out for free, since
this only ever runs from the landing-transition block, which by
construction never fires while already on the floor. Also spawns `ability.vfx_scene` TWICE via `_spawn_blink_vfx()` - once
before moving `global_position` (drops at the ground strike point) and
once after (drops at the landing point, the ceiling) - each call passed
`direction = 0.0` for no flip, since the left/right flip has no vertical
equivalent. `_spawn_blink_vfx()` is now shared across three call sites
total (`_try_blink()` at the cast point, `_try_slam_wrap()` twice) - it
always drops the VFX at wherever `global_position` is when it's called, so
where each one ends up is entirely about caller ordering, not anything the
function itself decides. Needs `wrap_on_slam = true` set explicitly on an
ability's `.tres` to do anything at all - it defaults off like every new
BlinkAbility toggle has so far, which was the cause of it silently doing
nothing the first time it was tested.

## Blink max-tier clone

Cashing in EITHER teleport - a normal left/right blink (`_try_blink()`) or a
slam-wrap landing (`_try_slam_wrap()`) - while `strikes` is already sitting
on a full `max_tiers` bank consumes ALL of it in one go (not the usual flat
`strikes_per_tier` cost) and, if `BlinkAbility.clone_on_max_tier` is true
(default), spawns a temporary clone of the wizard via `wizard.gd`'s
`_spawn_blink_clone()`. Both call sites run the identical
`tiers_banked >= ability.max_tiers` check, so a maxed-out player gets the
same payoff no matter which of the two they spend it with.

The clone is a fresh `PackedScene.instantiate()` of `wizard.tscn` itself
(preloaded once as `wizard.gd`'s `_WIZARD_SCENE` constant), NOT a
`duplicate()` of the live wizard - `duplicate()` would copy the live
wizard's current property values, including reference fields
(`current_instance`, mid-action flags), as shared references rather than
independent copies, risking the clone and the original fighting over the
same barrier/state. A fresh instance just gets the same `seat` set on its
`WizardSeat` root and lets its own `_ready()` derive everything else
(`wizard_class`, input actions, sprite, abilities) exactly like a normal
spawn.

"Mimics all inputs" needs no recording/playback code at all: Godot's
`Input` singleton is queried by action name, not scoped to any node, so the
clone (same seat) and the original both read the exact same
`InputRemap.action_for(seat, ...)` actions off the same physical button
presses, in lockstep, for free.

`wizard.gd` and `wizard_seat.gd` each picked up a `class_name` (`Wizard`,
`WizardSeat` respectively - neither had one before, confirmed no existing
conflicts) purely so the clone-spawning code can type the instantiated
scene's nodes (`_WIZARD_SCENE.instantiate() as WizardSeat`, its
`CharacterBody2D` child `as Wizard`) instead of dynamic `set()`/`call()`.

Knobs on `BlinkAbility`: `clone_on_max_tier` (the on/off switch, default
true), `clone_duration` (seconds before `_despawn_clone()` fires, default
5.0), `clone_transparency` (alpha applied to the clone's `modulate` on
spawn, default 0.5 - purely so it reads as a clone at a glance), and
`clone_strikes_count_for_player` (default false - whether a strike the
clone's own shield deflects gets credited back to `_clone_source` via
`_on_shield_deflected()`'s new clone-redirect branch, or just vanishes with
the clone).

`_is_clone`/`_clone_source` (new `wizard.gd` fields) mark a spawned clone
and point back at whoever cast it. Deliberate design choice, not something
explicitly asked for: a clone that itself reaches max tier never spawns a
FURTHER clone - `_try_blink()`/`_try_slam_wrap()` both gate the whole
clone-spawn branch on `not _is_clone`, so a maxed-out clone just falls
through to a normal flat one-tier spend. Prevents an unbounded clone chain;
revisit if a different cap (e.g. one clone-generation deep) is ever wanted
instead.

`_despawn_clone()` (called by a one-shot timer started the instant the
clone spawns) is also the reason this feature needed its own barrier
cleanup: barriers are always children of `get_tree().current_scene`, never
of the wizard that cast them (see `_spawn_shield_instance()`), so just
freeing the clone's chassis would never have taken its barrier down too.
Fades it out first via the exact same `DeflectionShield.start_fade()`
(animation-driven, ends in its own `queue_free()`) every other barrier
teardown in this file already uses, falling back to a bare `queue_free()`
if the barrier has no `DeflectionShield` to ask - then frees the clone's
whole `WizardSeat` chassis (not just the `CharacterBody2D`).

## Growth VFX (attached to the shield, continuous - contrast with Blink's one-shot drops)

`GrowthAbility.vfx_scene` (a `PackedScene`, unset by default - same opt-in
shape as `BlinkAbility.vfx_scene`) is a different pattern from the Blink
family's VFX above: instead of a one-shot world-space drop that plays once
and frees itself, `wizard.gd`'s `_start_growth_vfx()` instances it as an
actual CHILD of `current_instance` - the growing shield itself, not the
wizard node and not the top-level scene - via `current_instance.add_child(vfx)`.
Being a shield child means it both follows the shield's position for free
AND scales up/down right along with it as `_shield_scale_tween` and the
per-tier `growth_tier_scales()` steps run the shield's own `scale` - no
extra bookkeeping needed to keep the VFX's size in sync with the growth.
Called once, right when a growth channel commits (same moment strikes are
first spent - the existing `_update_strike_gauge()` call site in
`_update_growth_channel()`), it plays the scene's `AnimationPlayer`
animation literally named `"grow"` if present, and is skipped entirely if
there's no live `current_instance` to attach to.

Deliberately tied to the BARRIER's lifetime, not the channel's:
`_end_growth_channel()` (release, exhaustion + grace expiry, lockout) does
NOT stop or free the VFX - it just snaps the shield's scale back to 1.0 via
`_shield_scale_tween` same as always, and the VFX keeps riding along,
playing right through that shrink, since the shield itself is still up.
The VFX only actually goes away when the shield itself does, in
`create_new_instance()` (a fresh Up-press casting a brand new shield) -
since the VFX is a child of `current_instance`, it's carried along
automatically by whatever that shield's own retirement already does
(fades out with it if it has a `"fade"` animation, or is freed instantly
with it via `queue_free()` if not), so no separate stop call is needed
there either - `create_new_instance()` just forgets the `_growth_vfx`
reference once the old shield is retired. `_stop_growth_vfx()` still
exists for one narrower case: a fresh channel committing again on a shield
that already has a VFX running (back-to-back holds without a new cast in
between) - `_start_growth_vfx()` calls it first to explicitly stop the
previous `AnimationPlayer` and `queue_free()` the previous instance before
attaching a new one. `ability_2.tres` currently points this at
`VFX/Growth_VFX.tscn` (particles + a looping heartbeat SFX via its own
`AnimationPlayer`/`"grow"` animation).

## Godot .tres corruption risk

Adding a new `@export` field to a script and then having Godot's editor
resave a `.tres` that uses it (e.g. from its automatic UID-migration pass)
can silently reset that field back to the script's default if the resave
happens before the editor's compiled view of the script catches up. This
bit us once already (`grows_on_hold` silently reset to `false`). If a
just-added field looks reset after the user reopens the project, that's the
likely cause - re-stage and read the live file directly to confirm, then
fix the value on the live (now UID-bearing) file rather than reverting the
UID migration itself.

## Known debug scaffolding still in place

`wizard.gd` has several `# TEMP DEBUG` `print()` calls (strike banking,
tier pay/lock events, up-press diagnostics) left in deliberately while the
strike/growth system is still being verified. Deferred cleanup, not
forgotten - ask before removing them, since they've been the main tool for
diagnosing several real bugs this project.

## VFX/overlay cleanup checklist - don't create memory sinks

Every VFX or status overlay this project spawns at runtime
(`instantiate()` + `add_child()`) follows the same three-part shape, and
any NEW one should too:

1. Track the live instance in a variable (a `var _foo_vfx: Node2D = null`
   on whichever script owns it), not just a local that goes out of scope.
2. Something ends it - either a duration knob (a timer/`await
   get_tree().create_timer(...).timeout`), an animation finishing (`await
   anim.animation_finished`, or `has_animation("end"/"fade")` played first
   as an outro), or an explicit state transition (a shield being retired, a
   `thaw()` call, a clone despawning).
3. Whichever path gets there always ends in `is_instance_valid(x)` +
   `x.queue_free()` - and re-checks the tracked variable still points at
   THIS instance first (`if _foo_vfx == vfx:`) before clearing/freeing, so
   an overlapping respawn (a fresh cast/freeze/ignite landing while the old
   one is still fading out) can never double-free or free a newer instance
   out from under itself.

Current sites, all confirmed following this shape:

- `wizard.gd` `_spawn_blink_vfx()` - Blink's cast-point + landing-point
  drops (also used by `_try_slam_wrap()`'s ground/ceiling pair). One-shot,
  drop-and-forget: frees on the vfx's own `AnimatedSprite2D.animation_finished`,
  or a 1s fallback timer if the scene has no such child.
- `wizard.gd` `_start_growth_vfx()`/`_stop_growth_vfx()`/`_end_growth_vfx()`
  - continuous, attached to the shield itself; always ends in a stop-and-free
    or a fade-then-free.
- `wizard.gd` `_spawn_meteor_vfx()`/`_clear_meteor_vfx()`/`_end_meteor_vfx()`
  - the falling-meteor vfx attached to the wizard; same stop-and-free/
    fade-then-free shape, plus a despawn-delay knob.
- `wizard.gd` `_play_dropped_vfx()` - Meteor's landing splash, a generic
  drop-and-forget-with-a-lifetime-timer helper (same shape as
  `_spawn_blink_vfx()`, minus the flip).
- `wizard.gd`/`ARENAS/ball.gd` `_spawn_frozen_overlay()`/
  `_clear_frozen_overlay()` - the ice-zone freeze overlay on both wizards
  and balls; freed on `thaw()`, with a "fade" outro if the overlay has one.
- `ARENAS/ball.gd` `ignite()`/`_clear_burning_overlay()` - Meteor's
  burning-ball overlay; freed after `burn_duration` seconds, or on a fresh
  `ignite()` re-lighting it early.
- `PLAYERS/ice_zone.gd` - `self_vfx_scene` is a CHILD of the zone `Area2D`
  itself, so it's carried away for free whenever the zone despawns
  (`_despawn()`); no separate reference/cleanup needed on that one.
- `wizard.gd` `_spawn_blink_clone()`/`_despawn_clone()` - the newest one
  (see "Blink max-tier clone" above): a clone chassis freed after
  `clone_duration`, which also explicitly fades out any barrier the clone
  itself left standing first (barriers are never children of the wizard
  that cast them, so this needed its own cleanup step beyond just freeing
  the clone).

One known soft spot, not new/introduced by this pass, just worth
remembering: `Ball.ignite()`'s doc comment already flags that
`duration <= 0` skips the auto-clear entirely and leaves that overlay
attached forever, since nothing else in the project ever clears it. Not
live today (`MeteorAbility.burn_duration` is `1.0` on `ability_4.tres`),
but if that knob's ever tuned down to `0` (or negative) in the Inspector
for an "instant"/"permanent" burn effect, this is exactly the kind of
one-node leak this checklist exists to catch.

**When adding a new ability VFX**: give it its own tracked reference
variable and make sure every path that stops needing it - not just the
"happy path" end-of-effect, but also any early-cancel/interrupt/replace
path - reaches a `queue_free()`. If it's short-lived and one-shot, the
`_spawn_blink_vfx()`/`_play_dropped_vfx()` drop-and-forget pattern is the
simplest template; if it's meant to persist and follow something for a
while, the growth/meteor "attach, track, explicitly end" pattern is the
one to copy.
