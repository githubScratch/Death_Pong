extends StrikeScaledAbility
class_name MeteorAbility

## Class 4's Meteor - see wizard.gd's _update_meteor()/_start_meteor()/
## _land_meteor(). This is the design that finally landed on the scaffold
## class4_ability.gd staged earlier (see git history/that file's old doc
## comment) - the file itself is NOT renamed to meteor_ability.gd, only the
## class_name inside it, since this session's tooling can only edit files in
## place, not rename/delete them on disk. Purely cosmetic mismatch - Godot
## doesn't care that the class_name and the filename disagree - but rename
## the file yourself in the Godot editor whenever convenient; it'll fix up
## ability_4.tres's ext_resource path automatically.
##
## Double-tapping Down and continuing to HOLD it on that second press (own
## separate double-tap state on wizard.gd, _meteor_down_tap_window_remaining -
## same shape Blink/Ice already use for their own directions) turns this
## wizard into a fast-falling "meteor" for as long as the fall lasts: normal
## gravity/movement is overridden to a straight-down plunge at fall_speed
## (see wizard.gd's _start_meteor()), and this wizard's own standing barrier
## (if he has one up) gets reparented onto him for the ride - see
## meteor_barrier_deflection_bonus below for how it hits harder while
## attached, and _attach_meteor_barrier()'s own doc comment for the full
## mechanic. An earlier version of this ability scaled the wizard up and
## gave the fall its own separate invisible hitbox instead - dropped in
## favor of the real, visible barrier doing the job, since its own collision
## radius is a much more honest cue for how far this actually reaches.
## Deliberately UNINTERRUPTIBLE by input once it starts - releasing Down
## early no longer cancels it (see wizard.gd's _update_meteor()'s own doc
## comment) - the only way out early is an external interrupt like getting
## frozen mid-plunge.
##
## Needs at least one full tier banked (strikes_per_tier) to activate at
## all - a qualifying double-tap-and-hold with nothing banked just doesn't
## trigger a fall, same as Blink denying an unaffordable blink. That one
## tier is spent the instant the fall actually starts (see wizard.gd's
## _update_meteor()), same "pay at commit" rule every other ability here
## follows.
##
## What's left banked AFTER that activation cost matters again at the
## LANDING: whatever's currently banked at that point (read, and only then
## spent, if the tier-2 payoff below actually fires - see wizard.gd's
## _land_meteor()) decides which landing plays - fewer than 2 tiers left (or
## tier2_meteor_form_enabled being false) is just meteor_lands_vfx_scene, a
## fiery finish, and the barrier fades out right there. 2 or more tiers left
## (with the knob on) consumes EVERY currently-banked strike outright - no
## partial-tier remainder banked for next time, unlike every other spend in
## this file - and, instead of a one-shot explosion (an earlier version of
## this ability had one - dropped to keep this focused, see
## tier2_meteor_form_enabled's own doc comment below for what replaced it),
## simply keeps the attached barrier and meteor_fall_vfx_scene riding along
## for tier2_meteor_form_duration more seconds after landing, same as if the
## fall had never actually ended - then fades the barrier out. Net result:
## the tier-2 payoff needs 3+ tiers banked BEFORE double-tapping - 1 to
## activate, 2 more still sitting there at landing.

## Seconds between the first and second tap of Down to count as a double-tap
## rather than two separate single taps - same shape/purpose as
## BlinkAbility.double_tap_window/IceAbility.double_tap_window, kept as its
## own field since this ability doesn't extend either of those.
@export var double_tap_window: float = 0.3

## How fast this wizard plunges straight down while falling as a meteor -
## velocity.y is force-set to this every physics frame the fall is active
## (see wizard.gd's _physics_process()), overriding gravity entirely rather
## than accelerating into it, so the drop reads as an instant, deliberate
## commitment rather than just a stronger dive. Deliberately faster than the
## chassis's own DIVE_VELOCITY (1400) - this is meant to feel like a bigger,
## more committal move than a plain dive.
@export var fall_speed: float = 2400.0

## Added directly onto the attached barrier's own DeflectionShield.
## deflection_force for as long as it's riding along with this wizard (see
## wizard.gd's _attach_meteor_barrier()) - this is the ability's entire
## "hits harder while in meteor form" payoff now, layered on top of
## whatever that barrier's own class-specific deflection_force already is.
## Never reverted afterward: the barrier gets faded out and freed the
## instant meteor form ends either way (see _end_meteor_barrier()), so
## there's no surviving instance left to accidentally keep the bonus.
@export var meteor_barrier_deflection_bonus: float = 0.0

## Attached to the wizard itself (see wizard.gd's _start_meteor()) for as
## long as the fall lasts - the "Meteor_Fall" packet: a continuous trail/
## glow riding along with the plunge, not a one-shot burst. Plays the
## instanced scene's AnimationPlayer "hold" clip if present, same convention
## IceZone's own self_vfx_scene uses. Null skips spawning anything, same
## opt-in shape every vfx_scene field in this project already follows - the
## fall itself still works with no art assigned yet.
@export var meteor_fall_vfx_scene: PackedScene

## Extra seconds meteor_fall_vfx_scene lingers AFTER the fall itself ends
## (Down released early, a freeze, or the ground reached - see wizard.gd's
## _cancel_meteor()/_land_meteor(), both now routed through _end_meteor_vfx()
## instead of the old instant _clear_meteor_vfx()) before it's actually
## queue_free()'d. Lets a "fade"/"end" outro clip on the vfx's own
## AnimationPlayer (played automatically if present, same has_animation()
## check the "hold" clip above already uses) or a trailing SFX finish
## naturally instead of being cut off mid-note the instant the fall stops.
## 0 (or less) keeps the old behavior - freed the same frame, no delay.
@export var meteor_fall_vfx_despawn_delay: float = 0.0

## One-shot "fiery finish" dropped at the landing point (see wizard.gd's
## _land_meteor()) when fewer than 2 tiers are banked at the moment of
## landing - "Meteor_Lands." Drop-and-forget, same shape _spawn_blink_vfx()
## already uses: plays the instanced scene's AnimatedSprite2D once, then
## frees it.
@export var meteor_lands_vfx_scene: PackedScene

## Seconds meteor_lands_vfx_scene is given to play before _play_dropped_vfx()
## frees it - a manual, explicit override rather than waiting on the scene's
## own AnimatedSprite2D.animation_finished (which only ever matched whatever
## frame count/FPS the art happened to be authored with, and had no way to
## account for SFX that outlasts the sprite animation). 0 (or less) frees the
## vfx immediately - not a supported mode, just what happens if this is left
## unset by mistake.
@export var meteor_lands_vfx_lifetime: float = 1.0

## Attached to a ball for burn_duration seconds (see Ball.ignite()) the
## moment the attached barrier touches it (see wizard.gd's
## _on_meteor_barrier_touched_ball()) - "Burning_Ball," the ball visibly on
## fire after being struck. Purely cosmetic, opt-in like every other
## vfx_scene field here; a ball already mid-burn just restarts the timer and
## swaps to a fresh overlay instance rather than stacking two.
@export var burning_ball_vfx_scene: PackedScene

## How long a struck ball stays visibly on fire before Ball.ignite() clears
## the overlay on its own. 0 (or less) means it never clears itself - the
## ball just stays lit until something else removes it (nothing does, today;
## treat 0 as "permanent for now" rather than a deliberately supported mode).
@export var burn_duration: float = 3.0

## Master switch for the TIER-2 payoff: when tiers_banked >= 2 at the moment
## the fall lands (see wizard.gd's _land_meteor() - the plain fewer-than-2-
## tiers landing never triggers this and ignores every knob below), the
## attached barrier and meteor_fall_vfx_scene both just keep riding along
## for tier2_meteor_form_duration more seconds instead of ending at the
## ground - nothing about either gets touched at landing at all when this
## fires; they just fade out later instead (see wizard.gd's
## _end_meteor_form_lingering()). Consumes every currently-banked strike
## outright when it fires - see this file's own top doc comment. False keeps
## the old behavior exactly: a tier-2 landing looks exactly like any other
## landing (just meteor_lands_vfx_scene, no spend) - same as if this
## ability's max_tiers were capped at 1.
@export var tier2_meteor_form_enabled: bool = false

## How long the tier-2 payoff above keeps the barrier/vfx going after
## landing, before both get faded out/ended on their own exactly like a
## normal landing would have - see wizard.gd's _meteor_form_lock_remaining.
## Meaningless while tier2_meteor_form_enabled is false.
@export var tier2_meteor_form_duration: float = 2.0

## While the tier-2 payoff above is active, this decides whether jumping is
## ALSO affected for that same window - true means a jump (see wizard.gd's
## create_new_instance(), the shared function behind every class's own
## shield-on-jump) still gives its usual jump impulse/sounds but does NOT
## fade out the current shield or summon a fresh one, so whatever barrier
## was already standing before the fall just stays exactly as it was. False
## leaves jumping completely untouched even while the fall is still going.
## Meaningless while tier2_meteor_form_enabled is false.
@export var tier2_meteor_form_blocks_barrier: bool = true

## True disables banking any NEW strikes for as long as this wizard is in
## any part of meteor form - falling (_is_meteor) or tier-2 lingering
## (_meteor_form_lock_remaining > 0.0) alike - see wizard.gd's
## _on_shield_deflected(). The attached barrier still physically deflects
## balls it touches either way (that's plain DeflectionShield behavior,
## unrelated to this knob); this only decides whether those deflections also
## grow this wizard's own banked strike count for a FUTURE meteor. False
## (the old behavior) leaves strikes banking normally the whole time, same
## as standing behind an ordinary shield.
@export var disable_strikes_while_meteor_form: bool = false
