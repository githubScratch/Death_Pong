extends AudioStreamPlayer2D
class_name RandomPitchAudio

## Drop-in script for an AudioStreamPlayer2D that shouldn't sound identical
## every single time it plays. Attached to the cast/impact sound on each of
## blink's, frost's, and fire's own vfx scenes (Blink_VFX.tscn,
## Blink2_VFX.tscn, Frozen_Ball.tscn, Frozen_Wizard.tscn, Burning_Ball.tscn,
## Meteor.tscn, Meteor_Lands.tscn) - the same handful of sounds repeating
## over and over across a match at the exact same pitch reads as grating in
## a way a small, natural-sounding variance fixes. Same +/-0.1 spread
## wizard.gd (jump/spell/dash/land) and deflection_shield.gd (deflect_sfx)
## already apply by hand at their own call sites via
## `randf_range(base - 0.1, base + 0.1)` right before `.play()` - this is
## that same idea, but self-contained on the node itself instead of
## something every caller has to remember to do, for the vfx scenes that
## don't have a persistent script of their own to hang it on.
##
## Randomizes once, in _ready(), rather than by overriding play(): every
## audio player this is attached to lives on a "drop-and-forget" vfx
## instance spawned fresh per cast (see wizard.gd's _spawn_blink_vfx()/
## _play_dropped_vfx()) and freed once its animation ends, so one instance
## only ever plays once regardless of whether that playback is kicked off
## by this node's own autoplay or by an AnimationPlayer property track
## flipping `playing` to true (see Blink_VFX.tscn/Blink2_VFX.tscn) - the
## latter sets the property directly rather than calling play() as a
## method, so a play() override would silently never run for those.
## _ready() fires before either path can start playback, so randomizing
## there covers both. Reads whatever pitch_scale was already authored on
## this node (1.0 if none was set) as the center of the spread, so each vfx
## keeps its own hand-tuned base pitch instead of this flattening them all
## to the same range.
const PITCH_VARIANCE: float = 0.1

func _ready() -> void:
	pitch_scale = randf_range(pitch_scale - PITCH_VARIANCE, pitch_scale + PITCH_VARIANCE)
