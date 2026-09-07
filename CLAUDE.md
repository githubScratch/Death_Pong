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

### Known limitation: this composition only covers DATA, not behavior - plan to revisit via child-node composition

Flagged in a code review, not urgent, but real and worth acting on before
adding a 5th class: everything above is genuine composition for each
ability's *tuning knobs* (a `BlinkAbility` carries none of `IceAbility`'s
fields, etc.), but the actual *behavior* - the state machine, tap-timing
windows, physics overrides, VFX spawn/despawn - for all four classes still
lives in one place: `wizard.gd` itself, currently ~2100 lines, carrying every
class's private state (`_channel_tier`, `_blink_pending`,
`_ice_left_tap_window_remaining`, `_meteor_hover_remaining`, `_slam_wrap_
armed`, ~30 fields total) and every class's update function
(`_update_growth_channel`, `_update_blink`, `_update_ice_zone`,
`_update_meteor`, ~25 functions total) whether or not a given wizard
instance is even playing that class. `_physics_process` calls all four
`_update_*` functions unconditionally, every frame, for every wizard - each
one opens with `_current_ability() as WhicheverAbility; if ability == null:
return`, so three of the four silently no-op on any given wizard. Harmless
at this scale, but it means a Blink wizard's script carries Growth's, Ice's,
and Meteor's complete logic too, and adding a 5th class means editing this
same shared file yet again rather than adding an isolated new one.

Not a today problem, but the plan going forward is composition via child
nodes: a small `AbilityController` base (a `Node`, not another `Resource`),
with `BlinkController`/`GrowthController`/`IceController`/`MeteorController`
each in their own script, and `_apply_class()` instantiating exactly the ONE
controller matching `wizard_class`'s ability as a child - so a Blink wizard
simply never loads Growth/Ice/Meteor code or state at all, no null-checks
required, and a 5th class is a new controller file plus one line in
`_apply_class()`'s dispatch, not an edit to `wizard.gd` itself. (A resource-
side alternative - giving `WizardAbility` itself virtual-ish methods like
`physics_process(wizard, delta)` - was considered and set aside: a `.tres`
Resource loaded from disk is a *shared instance* by default, so two seats
both picking Blink would reference the same `BlinkAbility` object, meaning
any runtime state would need to live somewhere per-wizard anyway or the
resource would need `.duplicate()`-ing per wizard - the node approach avoids
that gotcha entirely by construction.)

The real complication whenever this actually happens: `_physics_process`
right now owns one single, carefully ordered read-modify-write of `velocity`
per frame - frozen check, then gravity, then jump/dive, then movement, then
growth's hover override, then meteor's fall override, then one
`move_and_slide()` call - and at least one comment already leans on "the two
abilities are never active at once" as an assumed invariant. Splitting into
independent per-controller nodes means that ordering and mutual-exclusion
has to be made explicit again (something like an `override_velocity(current)
-> Variant` hook the chassis calls on the active controller once, applied
only if non-null) rather than falling out for free from everything living in
one function. Worth doing as its own deliberate pass with every ability
re-tested afterward, not folded into an unrelated change.

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

`IceAbility.affects_other_wizards_at_max_tier` (bool, default false) is a
"fully-charged zone breaks the usual restriction" bonus on top of that -
same shape as `BlinkAbility.clone_on_max_tier`'s own max-tier bonus. Only
does anything when `affects_other_wizards` is false; a cast that spends
every currently-banked tier (`tiers_spent >= max_tiers`) still unlocks
wizard-targeting for that one zone even though ordinary lower-tier casts
stay ball-only. Resolved once per cast in `wizard.gd`'s `_cast_ice_zone()`
into a plain `targets_other_wizards` bool passed to `IceZone.configure()` -
`IceZone` itself has no idea tiers or a max-tier bonus even exist, it just
gets told whether THIS zone instance can catch other wizards.

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

A separate bug, found later via an actual playtest report rather than
carried over from the old trap: a ball caught by a zone could visibly
shrink/squish and stay that way for the whole freeze - worst on
`ball_big.tscn`, Yonder's enlarged ball. `ball.gd`'s own
`_physics_process()` runs a purely cosmetic "stretch" effect on every
unfrozen frame - elongated along the direction of travel, squeezed
perpendicular to it (inverse-square-root, for a volume-preserving squash),
tilted to match - reset back to `_original_scale`/`rotation = 0` only once
velocity drops low again. The frozen branch returns immediately, before
ever reaching that reset, so once frozen NOTHING touches `scale`/`rotation`
again for the rest of the freeze: whatever stretched, squeezed, tilted
shape the ball happened to be in at the exact instant an `Ice Zone` caught
it just holds there, frozen, for the whole duration. A ball is almost
always moving fast enough to be mid-stretch at the moment it's caught, so
this fired on nearly every catch - ordinarily invisible since the real
stretch only lasts a fraction of a second during normal motion, but held
perfectly still for a multi-second freeze it reads as the ball having
shrunk. Fixed by having `freeze_in_place()` itself snap `scale`/`rotation`
back to rest once, at the same moment it already gives velocity/spin their
own one-time freeze treatment - exactly what the very next unfrozen frame's
stretch code would have done anyway, just done before the freeze holds the
ball still instead of after.

Update: a playtester kept seeing the big ball on Yonder shrink/vanish while
frozen even after the fix above shipped, describing the frozen overlay as
"attaching at normal-ball size" while the big ball itself "disappears
almost." The one-time reset in `freeze_in_place()` only guards against the
stretch effect specifically, so as a hedge against any other code path that
might still be touching `scale`/`rotation` mid-freeze, the frozen branch in
`_physics_process()` now re-pins `scale = _original_scale` and
`rotation = 0.0` every frame for the whole freeze, not just once at the
moment of catching. This is defensive rather than a confirmed second root
cause - static reading of `ball.gd`, `ball_big.tscn`, and
`VFX/Frozen_Ball.tscn` turned up no other scale-touching code (no
`top_level`, no `reparent()`, correct overlay scene reference, and the
overlay's z-index sits behind the ball sprite, not in front of it), so if
the symptom persists after this it's worth checking whether it's actually a
lighting/blend artifact from the overlay's `PointLight2D` (`energy = 3.0`)
rather than a true scale change.

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
OTHER wizard at all - false leaves it slowing balls only),
`affects_other_wizards_at_max_tier` (unlocks wizard-targeting for a
fully-charged cast specifically, even when `affects_other_wizards` is
false), `zone_scene` (the interactive zone itself,
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
side's `WrapDestination` `Marker2D` (X only - Y is untouched) instead of
stopping short. Anything not tagged into one of those groups (another
wizard, an untagged wall, a mid-arena platform) keeps the old
stop-at-the-clear-portion behavior unchanged. Currently only `arena.tscn`'s
`left`/`right` walls (and the goal-mouth WizardWall gates parented under
them - see below) are tagged - `Tower` and `Yonder` use the same collision
layer for ALL their solid geometry (many scattered wall/platform segments,
not one clean boundary box), so neither has a well-defined single "map
wall" to wrap off of yet. Extending this to another arena means only a
scene change (tag the wall(s), add their own `WrapDestination` marker) - no
`wizard.gd` change needed, since the lookup is group-based end to end (see
below). Deliberately left/right only here - the bottom-to-top counterpart
is its own separate mechanic, see "Blink slam wrap" above.

`_wrap_destination()` fetches the actual `WrapDestination` marker via
`get_tree().get_first_node_in_group(group)`, not as a direct child of
whichever specific body `test_move()` happened to collide with - it used to
read it straight off the collider itself, which quietly broke once a side
gained a SECOND wrap-tagged body (the WizardWall gate below): a blink
stopped by the gate instead of the main wall would look up a
`WrapDestination` child on the gate, find nothing, and just stop short
instead of wrapping. The group-based fetch means any body tagged into
`map_wall_left`/`map_wall_right` resolves to the same marker regardless of
which specific one was actually hit - the gate and the main wall are both
just "entry points" into the same wrap boundary, not two different
destinations. Same lookup shape `_try_slam_wrap()` already used for
`map_wall_top`.

## Goal-mouth WizardWall gates (wizards can't camp inside a goal)

Each goal is a physical notch cut into the arena's `left`/`right`
`CollisionPolygon2D` (its inner face recedes further from the arena center
for the vertical band the goal covers), purely so the ball has a real gap
to fly through into `Goal_Left`/`Goal_Right`'s scoring `Area2D` instead of
bouncing off. That notch used to be a genuine three-sided physical pocket
(solid top/bottom edges, open only toward the arena) that a WIZARD could
walk into and use those same solid edges as a tiny private floor/ceiling to
stand and bounce between - camping inside the goal itself, invisible to
normal play.

The fix is NOT on `Goal_Left`/`Goal_Right` themselves - an `Area2D` never
physically blocks anything regardless of its own layer/mask, it only fires
overlap signals, so those two nodes were never what let a wizard stand in
there and don't need to change. Instead, `"left wizard wall"`/`"right
wizard wall"` (`StaticBody2D`, parented under `Arena/walls/left`/`Arena/
walls/right` respectively) seal each goal's mouth flush with the wall's
normal face, blocking wizards only, using a layer already built and proven
for exactly this "solid to wizards, invisible to the ball" split:
`collision_layer = 16` (physics layer 5, named `"WizardWall"` in
`project.godot`), `collision_mask = 0` - no mask needed, since it's the
COLLIDING body's own mask that does the work. `wizard.tscn`'s
`CharacterBody2D` already has `collision_mask = 18` (Arena + WizardWall),
so it already sees this gate; the ball's own mask (`14` = Arena + Ball +
Spells) does not include WizardWall, so it sails straight through
untouched, same as always. This is the exact same layer `Mid_Barrier/
Mid_Collision` (the "hot" mode center wall) already uses - not a new
mechanism, just a second application of one already proven out.

Both gates are also tagged into `map_wall_left`/`map_wall_right`
respectively, same as the main wall each is parented under, so a blink
stopped by the gate still wraps around the map exactly like one stopped by
the main wall - see `_wrap_destination()`'s group-based fetch above for why
that needed a small `wizard.gd` fix once a side had two wrap-tagged bodies
instead of one.

## Blink slam wrap (floor -> ceiling)

`BlinkAbility.wrap_on_slam` (bool, default false) is the vertical
counterpart to the wall wrap above, but triggered completely differently:
not a blocked blink, but the airborne -> grounded landing transition in
`_physics_process()` (the same `if not hit_the_ground and is_on_floor():`
block that already plays the landing sound/squish), via
`wizard.gd`'s `_try_slam_wrap()`. Arming it in the air is a separate step
handled by `_update_slam_wrap()`, gated by `BlinkAbility.
slam_wrap_requires_double_tap` (bool, default true): true is the original
double-tap-Down-and-hold gesture (mirrors `MeteorAbility`'s own
double-tap-and-hold), false arms it off a single press-and-hold instead -
either way, releasing Down before landing still cancels the arm, and it's
still gated on being airborne when Down is first pressed. Landing while
still armed, with `wrap_on_slam` on and a full tier's worth of strikes banked, spends one
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

## Blink wall/ceiling wrap on Tower and Yonder

Both maps looked harder to extend the wrap to than Arena at first glance -
Tower has destructible bricks stacked in front of each goal, Yonder has
ceiling/floor panels that slide open and shut - and both DO contain an
always-solid backstop sitting just behind that moving layer, so no
brick-state or platform-position tracking was ever needed in script. But
the first pass at Tower tagged the WRONG wall and shipped a real
regression along with it - see the correction below before trusting the
positions here.

Tower, corrected: the first attempt tagged `walls/left/StaticBody2D`/
`walls/right/StaticBody2D` - full-height `StaticBody2D`s with no notch cut
for the goal, sitting entirely OUTSIDE the visible playfield (left spans
global X -64..0, right spans 1152..1216) - on the assumption that they
were the thing stopping a wizard once a brick broke. They aren't reachable
by a wizard at all: `zones/leftgoal`/`rightgoal` (the scoring `Area2D`s)
sit at X 0..32 and 1120..1152 respectively - flush against each brick
column's inner face, IN FRONT of those far walls, not behind them. Since
an `Area2D` never physically blocks anything, destroying the brick in
front of it left NOTHING solid between the open playfield and the goal
sensor - a wizard could walk straight into the goal pocket, exactly the
"camping in the goal mouth" bug `Goal_Left`/`Goal_Right`'s `WizardWall`
gate already exists to prevent on Arena. Tagging the unreachable far wall
also meant the dash's `test_move()` could never reach a wrap-tagged body
in the first place - a live brick stopped it short every time, and a
destroyed one just let it sail into the goal pocket, so the wrap never
fired either. One bug, two symptoms.

The fix is a `Goal_Left`/`Goal_Right`-style `WizardWall` gate on each
side, same as Arena: `"left wizard wall"`/`"right wizard wall"`
(`StaticBody2D`, `collision_layer = 16`, `collision_mask = 0`, parented
under `walls/left`/`walls/right`) sealing the goal mouth flush at its
playfield-facing edge, reusing the goal `Area2D`'s own collision shapes
(`RectangleShape2D_ed6xj`/`RectangleShape2D_x5ail`) so the gate's footprint
lines up with the goal exactly - solid to wizards (mask 18 includes
WizardWall), invisible to the ball (mask 14 doesn't). Live or destroyed,
a brick no longer matters: the gate blocks wizards from ever reaching the
goal pocket at all, brick or no brick. Both gates are tagged into
`map_wall_left`/`map_wall_right` alongside the original far wall (same
"two wrap-tagged bodies share one group" shape `_wrap_destination()`
already handles for Arena's own gates) - the far wall keeps its existing
`WrapDestination` children (`walls/left/StaticBody2D/WrapDestination` at
local `(1024, 1280)`, `walls/right/StaticBody2D/WrapDestination` at local
`(-1056, 1248)`, both placed past the FAR brick column so reappearing on
the opposite side can never land inside a brick), and the group lookup
resolves to those regardless of which of the two tagged bodies the dash
actually hit, since only the group needs to contain a marker somewhere,
not the specific collider.

The gate alone meant only the space BEHIND a destroyed brick wrapped -
hitting a still-standing brick just bumped off it like any other
obstacle, no wrap. Playtesting showed that reads as "wrapping doesn't
work on Tower" rather than as the intentionally simpler design it was, so
every individual brick is now wrap-tagged too: all 39 `Bricks/BricksLeft`
`RigidBody2D` instances carry `groups=["map_wall_left"]`, all 39
`Bricks/BricksRight` instances carry `groups=["map_wall_right"]` -
`Bricks/BottomBricks` (a third, unrelated usage of the same shared
`brick.tscn`) is deliberately left untagged. No `wizard.gd` changes were
needed for this - `_wrap_destination()` already just checks
`is_in_group("map_wall_left"/"map_wall_right")` on whatever collider the
dash actually hit, and a `WrapDestination` only needs to exist SOMEWHERE
in the group (the far wall's, unchanged) - so a live brick now wraps
exactly like the gate behind it does, and a destroyed brick still falls
through to the gate as before.

Yonder ceiling: `Yonder/walls/top_left`/`top_right` are the visible
sliding ceiling panels (their `AnimationPlayer` tracks only ever move
their X, sliding a gap open and closed - their Y is a fixed `-128` in
every keyframe), but `Yonder/walls/false_roof` is a separate, always-
static, full-width `StaticBody2D` sitting behind them. Rather than tag the
moving panels, `false_roof` is tagged `map_wall_top` with a
`WrapDestination` child at local `(1184, 192)` (global Y 0) - comfortably
below the panels' own collision floor (their box bottom edge sits at
global Y -64 whenever a panel is present at that X) regardless of how open
or closed the panels currently are. `_try_slam_wrap()` only ever applies
the target's Y, so the X chosen for the marker doesn't matter; anchoring
to the one node that never moves means the "stay clear of the moving
platform" requirement is satisfied by construction rather than needing a
live check.

Yonder left/right (added after the Tower correction above, not part of
the original pass): `Yonder/walls/left_wall`/`right_wall` are plain,
un-notched `StaticBody2D`s spanning the full playfield height with no
brick/panel equivalent in front of them at all - the goal here is a
floating circular `Area2D` "portal" (`left_goal_pack`/`right_goal_pack`)
sitting out in the open field, not recessed into the wall, so there's no
adjacent camping bug to fix and no gate needed. Tagged directly into
`map_wall_left`/`map_wall_right` with a `WrapDestination` child each -
`left_wall/WrapDestination` at local `(1392, 312)`, `right_wall/
WrapDestination` at local `(-240, 318)` - placed a comfortable distance
inside the opposite wall rather than hugging it, purely so a reappearing
wizard doesn't materialize flush against the wall or right on top of the
goal circle.

Tower ceiling/floor (added after the above): Tower is a scripted,
continuously-descending-camera vertical shaft (see the `DescentCamera`
AnimationPlayer, `autoplay="descent"`) - the 13 `Platforms/PlatformShape*`
bodies never move vertically at all (their own "movingparts" animation
only ever slides them horizontally, scales them away, or rotates them in
place - checked every track), so the earlier assumption that this needed
dynamic platform-position tracking was wrong. The part that actually
needed solving was different: nothing readable as a fixed-world "floor"
or "ceiling" exists at all, because there isn't one - what a wizard
actually lands on and bumps their head on is `CameraPackage/roof`/
`CameraPackage/floor`, a matched pair of solid `StaticBody2D`s parented
directly under the `Camera2D` node itself (not camera-relative decoration,
despite the name - both carry real collision, `collision_layer = 2`,
`mask = 7`, which is why "hitting the floor" already worked before any of
this) that ride along with the camera's descent to keep the current
on-screen slice of the shaft always capped top and bottom. Tagging
`CameraPackage/roof/StaticBody2D` into `map_wall_top` with a
`WrapDestination` child (`CameraPackage/roof/StaticBody2D/
WrapDestination`, local `(0, 96)` - just past the roof collision shape's
own bottom edge at local Y 32, same margin-past-the-collision-edge idea
Yonder's `false_roof` marker uses) was the entire fix: because that
marker is parented under a node that moves with the camera every frame,
it automatically always resolves to "just below whatever's currently
capping the top of the screen," with no per-frame tracking code needed -
the exact same "anchor to the thing that already never needs live
position math" shape every other wrap destination in this file uses, just
with the anchor itself being the one thing that moves. `_try_slam_wrap()`
doesn't care what body was actually landed on to fire (it only cares
about the airborne -> grounded transition itself), so this one tag now
covers landing on the real floor AND landing on any of the 13 platforms
alike, no additional tagging needed anywhere else on the map.

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

The clone no longer just vanishes when `_despawn_clone()` fires - it now
tweens `modulate.a` from `clone_transparency` down to 0 over
`clone_fade_duration` seconds (default 0.5) before the chassis is actually
freed, shaped by `clone_fade_trans`/`clone_fade_ease` (`Tween.
TransitionType`/`EaseType`, defaulting to a plain `TRANS_LINEAR`/
`EASE_IN`) - the "decay curve" knob, reusing the same trans/ease
vocabulary every other decay tween in this project already exposes
(`deflection_shield.gd`'s shield-return tween, the knockback-decay tweens
in `wizard.gd`) rather than adding a one-off `Curve` resource just for
this. `clone_fade_duration = 0` skips the tween entirely and frees the
clone immediately - the original behavior, still there as an opt-out. Any
barrier the clone left standing fades on its own timeline via
`DeflectionShield.start_fade()`, started right alongside this, not
sequenced before or after it.

That fade-out `await` introduced a real bug: for the whole
`clone_fade_duration` window, the clone chassis is still sitting in the
scene tree, fully alive, and `_physics_process()` was still calling into it
every frame - meaning a despawning clone could keep reading input and cast
a brand-new barrier during its own fade-out. `_despawn_clone()`'s
barrier-cleanup only ever runs once, right at the top (before the fade
even starts), so any barrier cast during that window was never tracked and
never cleaned up - it just sat there forever, which is what surfaced as
leftover spell barriers piling up on the field. Fixed with a new
`_despawning: bool` field on `wizard.gd`, set true as the very first thing
`_despawn_clone()` does - before its barrier cleanup, before the fade
tween, before anything else - and never cleared. `_physics_process()`'s
whole ability-dispatch block (`_update_growth_channel()` through
`_update_meteor()`) is now gated behind `not _despawning`, so a clone
already told to despawn can no longer cast anything for the rest of its
life, fade included. Movement/gravity/animation below that block are
deliberately left ungated, so a despawning clone still finishes
falling/sliding naturally instead of visibly freezing mid-air while it
fades. `_despawn_clone()` also re-checks `current_instance` right before
the final `chassis.queue_free()` and frees anything still there as a
last-resort safety net, even though `_despawning` should make that
unreachable in practice.

Fixing that didn't fully stop leftover barriers from showing up, though -
they kept appearing on Growth and Meteor casts too, nothing to do with
Blink at all, which pointed at a second, unrelated bug in the ONE piece of
fade logic every class's ordinary jump/recast shares:
`create_new_instance()`. That function used to fade an outgoing barrier by
grabbing its `AnimationPlayer` directly and calling `play("fade")`, with
no further tracking - it trusted the "fade" clip's own embedded Call
Method Track (every class's `spell_N.tscn` has one, calling `queue_free()`
on the barrier root at the clip's last frame - see the clip itself, not
any script) to actually remove the barrier once the animation played
through. But `DeflectionShield.deflect_ball()` has no concept of "this
barrier is already retiring" - any ball that touches ANY barrier
unconditionally interrupts whatever the `AnimationPlayer` is doing
(`stop()` then `play("deflect")`), fade included. A ball clipping a
barrier that `create_new_instance()` had just started fading out would
knock it off "fade" and onto "deflect" before that Call Method Track ever
fired, permanently discarding the pending `queue_free()` - the barrier
would just sit there, snapped back to its normal "deflect" pose, forever.
This could in principle fire off a single unlucky recast, but casting
faster (more retirements queued up, each with its own ~0.5s window a ball
could clip) made it far more likely to actually happen, which is why it
read as a "spam" bug.

Fixed at the source rather than by patching this one call site:
`DeflectionShield` (`deflection_shield.gd`) now has an `_is_fading: bool`
flag, set true as the very first thing `start_fade()` does and never
cleared, and `_on_body_entered()` early-outs on it exactly like it already
does for `pass_through` - so once a barrier starts fading, NO later ball
hit can touch its `AnimationPlayer` again, through any code path.
`create_new_instance()` itself no longer pokes the `AnimationPlayer`
directly at all - it now just calls the retiring barrier's own
`DeflectionShield.start_fade()`, the exact same call `_despawn_clone()`
and `_end_meteor_barrier()` already used, so there's now exactly one
function in the whole project that ever decides a barrier's fade has
started, and one flag that protects it the rest of the way to
`queue_free()`. The old `fading_instances` array `create_new_instance()`
used to maintain was dead weight even before this - it only ever pruned
already-freed entries from itself, never actually freed anything - and is
gone now that the real cleanup lives in `start_fade()`.

Second bug, found later via another playtest report matching the same
symptom (barrier visible, collision dead, no strikes, never actually gone -
"can happen for any class"): `_is_fading` closed the door on a LATER ball
hit restarting the fade, but nothing stopped `start_fade()` itself from
being called a SECOND time on a barrier already mid-fade, which does the
exact same damage a ball hit used to. The concrete path that does this:
`wizard.gd`'s `_meteor_barrier` (the reference `_attach_meteor_barrier()`/
`_end_meteor_barrier()` use to track a barrier reparented onto a falling
Fire wizard) is a separate field from `current_instance`, and nothing keeps
them in sync once they diverge. If a tier-2 lingering meteor form's own
jump recast lets `create_new_instance()` fade that same barrier out from
under the form (`MeteorAbility.tier2_meteor_form_blocks_barrier == false`,
see "Blink max-tier clone"'s neighboring meteor sections), `_meteor_barrier`
still points at it - `is_instance_valid()` keeps returning true for the
rest of that ~0.5s fade window, since `queue_free()` doesn't actually
remove a node until the fade's own Call Method Track fires at the very end
of the clip. If the meteor form then ends anywhere inside that window,
`_end_meteor_barrier()` sees a "still valid" barrier and calls
`start_fade()` on it again. `start_fade()` responds to a second call the
same way it always has: `animation_player.stop()` then `play("fade")`,
restarting the clip from 0 - which re-runs the `Area2D:monitoring` track
(collision off at t=0) but resets the countdown to the `queue_free()`
keyframe at t=0.5 before it can ever fire. A barrier hit by this twice ends
up exactly as reported: permanently non-colliding, banking no strikes, and
never freed, because it can never survive a full uninterrupted 0.5s to
reach its own completion.

Fixed the same way as the first bug - at the one function that's supposed
to be the sole authority on a barrier's fade, rather than chasing down
every place a stale reference to a fading barrier might come from:
`start_fade()` now checks its own `_is_fading` flag first and returns
immediately if it's already true, exactly the same "already retiring,
leave it alone" rule `_on_body_entered()` uses. Whichever call gets there
first wins; any later call, from any source, is now a no-op instead of a
restart - closing this off for good regardless of what other reference to
a fading barrier turns up mismatched next.

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

## Meteor hover delay (visual wind-up before the plunge)

`MeteorAbility.meteor_hover_delay` (default `0.0`, opt-in like every other
timing knob in this file) adds a beat of hang-time right at the top of a
meteor fall, between the double-tap-and-hold registering and the actual
straight-down plunge starting - a "visual registry" window so the drop
reads as a deliberate, telegraphed commitment (a dodge/parry opportunity
for whoever's about to get fallen on) instead of an instant snap into
`fall_speed`, same spirit as `BlinkAbility.blink_delay`'s own wind-up
before a teleport fires.

`wizard.gd`'s `_start_meteor()` still does everything it always did the
instant the fall triggers - attaches the barrier (`_attach_meteor_barrier()`)
and spawns `meteor_fall_vfx_scene` (`_spawn_meteor_vfx()`) - unconditionally,
before the delay even starts, not after it. That ordering is the whole
point: the vfx needs to already be on screen for the entire hover for the
wind-up to actually telegraph anything, so both are still fired off exactly
where they always were, only `velocity` is treated differently. With
`meteor_hover_delay` above 0, `_start_meteor()` zeroes velocity and arms a
new `_meteor_hover_remaining` countdown instead of setting `fall_speed`
directly; `_physics_process()`'s own `if _is_meteor:` override (right
before `move_and_slide()`, same spot the plunge override always lived)
now checks that countdown first and forces velocity to `Vector2.ZERO` for
as long as it's still counting down - the exact same per-frame-override
shape `_is_channeling`'s hold-to-grow hover already uses just above it -
falling through to the normal `fall_speed` plunge once it hits 0. The
countdown itself ticks down from `_update_meteor()`'s own tail (the
"nothing else happens here, the fall is uninterruptible by input" block) -
a duration counting down, not a reaction to input, so it doesn't conflict
with that function's own doc comment about the fall being uninterruptible
once started.

A `meteor_hover_delay` of 0 (the default) leaves `_meteor_hover_remaining`
at 0, so the override falls through to the plunge on the very same frame
`_start_meteor()` runs - identical, frame-for-frame, to the behavior
before this knob existed. `_meteor_hover_remaining` is also reset to 0 in
both `_cancel_meteor()` (an external interrupt, like a freeze, catching
the wizard mid-hover or mid-plunge) and `_land_meteor()` (reaching the
ground), even though a fresh `_start_meteor()` call always re-arms it from
scratch anyway - just to avoid leaving stale countdown state sitting
around between falls, same hygiene every other mid-action flag in this
file already gets on cleanup.

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

## Per-seat outline tint - attempted, reverted, revisit later

Goal was to let a player pick their own wizard out at a glance: a
color-per-seat outline around the body sprite. Went through two whole
approaches and five total drafts across one session before the whole thing
got reverted at the user's call ("just not doing it for me... ill come back
to this") rather than land on something that actually looked right - not a
bug fix this time, a design call. Keeping the history here anyway, because
several of the individual technical problems hit along the way are real and
will resurface the moment anyone (human or Claude) tries this again:

- Attempt 1, hand-drawn art: a `WizardClass.outline_sheet` field holding a
  separate white-on-transparent sprite sheet, one class's worth of which a
  playtester provided (`SPRITES/outline 2.png`, plus two unused alternates,
  `outline 1.png` and `fulloutline.png` - all three still sitting in
  `SPRITES/` unreferenced by anything now, worth deleting whenever this is
  picked back up or cleaned out for good). Dropped after one round of
  feedback: at this art's small on-screen size (roughly 64x64), a
  pixel-perfect hand-traced 1px line aliases badly and reads as too
  stark/harsh, and fixing that would have meant redrawing art rather than
  turning a knob.
- Attempt 2, a live shader (`PLAYERS/sprite_outline.gdshader`, deriving the
  rim from the sprite's own alpha channel instead of separate art) went
  through four drafts, each catching a real bug the last one had:
  1. Averaging alpha over a filled disk of samples via a nested 13x13
     for-loop (up to 169 dependent `texture()` calls per fragment) failed
     to compile in-game outright ("Shader compilation failed",
     `renderer_canvas_render_rd.cpp` - a driver/codegen-level rejection
     with no line number, not a GDScript-style parse error, which points at
     the loop's sheer size). Godot fell back to drawing the outline sprite
     with no shader logic at all - a flat, fully opaque copy of the body
     art, multiplied by `modulate`, which is why the in-game result looked
     like a solid seat-colored recolor of the whole wizard rather than a
     rim: the shader had simply never run.
  2. Dropping the loop for a hand-unrolled fixed 8-sample ring and a hard
     0-or-1 alpha cutoff compiled and drew an actual edge, but every seat
     rendered pure white regardless of `GameSettings.color_for_seat()`, and
     the hard binary edge read as harsh/aliased at this sprite's small
     on-screen size.
  3. Fixing the harshness (a continuous soft-edged falloff via three
     weighted sample rings - near/mid/far, 8 directions each, 24
     `texture()` calls total, no loop - averaged rather than maxed) worked
     and stuck. Fixing the white-regardless-of-seat bug did not: both
     earlier drafts read/wrote only the `COLOR` built-in, which by the time
     `fragment()` runs already has `TEXTURE` sampled and multiplied into
     it - overwriting `COLOR` outright, as both did, throws the modulate
     tint away entirely. This draft tried reading a `MODULATE` built-in
     instead, believing Godot exposes a CanvasItem's modulate tint that way
     separate from the texture-multiplied `COLOR` - it doesn't, at least
     not in this project's Godot version: `MODULATE` is not a real
     identifier here, and using it is a hard shader compile failure
     ("Unknown identifier in expression: 'MODULATE'"), not a silent no-op.
  4. Final draft sidestepped modulate-inside-a-shader entirely: since the
     fragment shader always has to fully overwrite `COLOR`, and Godot never
     re-applies `modulate` afterward, the seat color was instead passed in
     directly as a shader uniform, set from script
     (`set_shader_parameter("outline_base_color", ...)`), no node-level
     `modulate` involved at all. This version actually worked (compiled,
     colored correctly per seat, soft edge) - it just didn't look good
     enough in practice once seen running to be worth keeping.

What got reverted, for anyone picking this back up: `wizard.tscn`'s
`outline` child node, its `ShaderMaterial` sub-resource, and the shader's
`ext_resource` entry are gone (back to `load_steps=10`, just `sprite` under
`CharacterBody2D`, no outline sibling/child anywhere). `wizard.gd` lost the
`outline` `@onready` var, `_build_outline_frames()`, and the `_set_facing()`
helper - every `flip_h` call site is back to setting `sprite.flip_h`
directly, and `_build_sprite_frames()` is back to its original inline
region literals (the `_SPRITE_SHEET_REGIONS` const existed only to share
with the now-gone outline builder). `WizardClass.sprite_sheet`'s doc comment
no longer mentions an outline use. One thing NOT cleaned up, because
nothing in this session's toolset can delete a file on the user's machine:
`PLAYERS/sprite_outline.gdshader` itself is still sitting on disk,
unreferenced by anything now that `wizard.tscn` no longer points at it -
harmless (Godot won't try to load a `.gdshader` nothing points at), but
worth deleting by hand next time this project's opened, along with the
three unused `SPRITES/outline*.png`/`fulloutline.png` files from attempt 1
above.

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

Burning is no longer purely cosmetic: `Ball.burning_max_speed` (default
`1400.0`) replaces `max_speed` outright as this ball's speed cap for as
long as it's burning, tracked by a new `_is_burning: bool` rather than by
checking whether `_burning_overlay` is set - `burning_ball_vfx_scene` is
still opt-in/nullable like every other `vfx_scene` field in this project,
so a class with no fire art assigned yet should still get the speed-cap
effect; only the VISUAL half of `ignite()` is a no-op on a null scene now,
not the gameplay half. `_is_burning` is set the instant `ignite()` runs
and cleared by `_clear_burning_overlay()` - which runs both from the top
of a fresh `ignite()` (harmless there, since `_is_burning` is set true
again immediately after on the same frame) and from the duration timer
actually ending the burn, which is what turns the raised cap back off.

**When adding a new ability VFX**: give it its own tracked reference
variable and make sure every path that stops needing it - not just the
"happy path" end-of-effect, but also any early-cancel/interrupt/replace
path - reaches a `queue_free()`. If it's short-lived and one-shot, the
`_spawn_blink_vfx()`/`_play_dropped_vfx()` drop-and-forget pattern is the
simplest template; if it's meant to persist and follow something for a
while, the growth/meteor "attach, track, explicitly end" pattern is the
one to copy.
