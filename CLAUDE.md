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
    `_try_blink()`. Groundwork note left in `blink_ability.gd`'s doc
    comment: using a blink while maxed out is meant to eventually also
    spawn a temporary input-mirroring clone - not implemented yet.

`wizard.gd` checks ability type with `is`/`as` (e.g. `ability is
GrowthAbility`), never a boolean flag on the shared base - that's the
mechanism that keeps this opt-in per-class instead of bloating every ability
resource. When a new ability needs its own scaling mechanic, follow this
same pattern: a focused subclass (of `StrikeScaledAbility` if it scales with
strikes, of `WizardAbility` directly if not) rather than adding fields to a
shared base.

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

Bonus: the liquid sloshes. `StrikeGauge.slosh()` is called both from
`wizard.gd`'s `_on_shield_deflected()` (every successful deflect) and from
`create_new_instance()` right after a fresh shield is cast and its gauge is
synced to whatever's already banked - a little "bloop" on summon, only
actually visible when strikes carried over into the new cast, since an
empty gauge has no liquid to slosh. Each call just nudges a velocity
(`slosh_kick`), and `_process()` integrates a tiny damped spring
(`slosh_stiffness`/`slosh_damping`) each frame, feeding the result into the
shader's `wobble_amount` uniform, which bends the flat fill line into a
`sin()` wave. No "stop" call needed anywhere - a strike (or a cast) reads
as a jolt that rings back down to still liquid on its own. This is a cheap
spring-driven wobble, not an actual fluid sim - deliberately so, that would
be overkill for a UI element this size.

Three separate knobs, three separate jobs - don't reach for the wrong one:
`slosh_kick` (default `1.6`) is how BIG the initial jolt is, tuned so the
wobble's peak displacement is a clearly visible chunk of `radius` rather
than a fraction of a percent of it. `slosh_stiffness` (default `60.0`) is
how FAST each individual wobble cycles - higher is a tighter, quicker
wave, lower is slower and lazier. `slosh_damping` (default `2.2`, lowered
from an initial `5.0` once the kick itself was large enough to actually
see) is how LONG it takes to settle - lower keeps it visibly rocking for
longer before coming to rest, which is the knob for "more/less gradual."

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
