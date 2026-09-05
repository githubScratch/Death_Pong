# Ball.gd - Modified to respond better to force changes
extends RigidBody2D

class_name Ball

# Properties
@export var min_speed: float = 200.0
@export var max_speed: float = 1000.0
var last_applied_force: Vector2 = Vector2.ZERO
@onready var sparks_player: AnimationPlayer = $SparksPlayer

@export var stretch_factor: float = 2.5  # How much the ball stretches
@export var min_velocity_for_stretch: float = 200.0  # Minimum velocity to start stretching
@export var max_stretch: float = 4.0  # Maximum stretch multiplier

var _original_scale: Vector2
var _velocity: Vector2 = Vector2.ZERO
var _previous_position: Vector2

## True while this ball is inside an Ice Zone (see PLAYERS/ice_zone.gd's
## _on_body_entered()) - mirrors Wizard's own freeze_in_place()/thaw() with
## the RigidBody2D-appropriate version below. Unlike the wizard's
## CharacterBody2D - fully script-driven via move_and_slide(), so simply not
## calling that each frame is enough to hold it still - the physics engine
## keeps integrating THIS body's gravity/collision response every physics
## step no matter what _physics_process() does or doesn't touch, so holding
## still here also needs gravity_scale itself dialed down, not just velocity
## zeroed once.
##
## Deliberately a SEPARATE flag from _frozen_remaining (see Wizard's own
## _is_frozen for the full reasoning) - the natural-timeout call to thaw()
## below happens the same frame _frozen_remaining is driven to <= 0, so
## thaw()'s own "was this even frozen" guard would otherwise see
## _frozen_remaining already at 0 and skip its own cleanup, silently leaving
## _frozen_overlay attached to the ball forever.
var _is_frozen: bool = false
var _frozen_remaining: float = 0.0
var _frozen_slow_amount: float = 0.0
var _frozen_base_gravity_scale: float = 0.0
var _frozen_overlay: Node2D = null

@onready var wall_impact: AudioStreamPlayer2D = $"../wall_impact"
var audio_pool = []
@export var pool_size = 3
@export var min_velocity_for_sound = 50.0  # Minimum velocity to play sound

func _ready():
	add_to_group("ball")
	for i in range(pool_size):
		var player = AudioStreamPlayer.new()
		player.stream = wall_impact
		add_child(player)
		audio_pool.append(player)
	_original_scale = scale
	_previous_position = global_position
	
	# Physics setup
	contact_monitor = true
	max_contacts_reported = 4
	self.gravity_scale = gravity_scale
	self.linear_damp = linear_damp
	
	# Initial movement
	var initial_direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	apply_central_impulse(initial_direction * min_speed)
	
func _physics_process(_delta):
	if _is_frozen:
		_frozen_remaining -= _delta
		# No per-frame velocity damping here on top of that - freeze_in_place()
		# already cut linear_velocity/angular_velocity ONCE, at the moment of
		# catching this ball, and scaled gravity_scale down for the duration;
		# the physics engine is left to keep integrating normally from there
		# under that already-reduced gravity. Re-damping velocity every frame
		# on top of that (the old behavior) crushed any residual motion back
		# toward zero within a couple physics frames regardless of how
		# partial slow_amount was set to - a slow_amount below 1.0 read as a
		# full freeze anyway. Leaving the engine alone here is what makes a
		# partial slow_amount actually look slowed rather than frozen.
		# Keep this in step with a frozen ball's stationary-or-slowly-moving
		# position so the first frame after thawing doesn't read a huge
		# one-frame jump as velocity and trigger a stretch-effect glitch.
		_previous_position = global_position
		if _frozen_remaining <= 0.0:
			thaw()
		return

	_velocity = (global_position - _previous_position) / _delta
	_previous_position = global_position
	
	# Apply stretch effect based on velocity
	if _velocity.length() > min_velocity_for_stretch:
		# Normalize direction
		var direction = _velocity.normalized()
		
		# Calculate stretch along movement direction
		var stretch_amount = clamp(_velocity.length() * stretch_factor / 1000.0, 1.0, max_stretch)
		
		# Create a basis for the transformation
		var x_axis = direction
		var y_axis = Vector2(-direction.y, direction.x)  # Perpendicular to direction
		
		# Apply stretch - expand in direction of movement, compress in perpendicular direction
		var new_scale_x = _original_scale.x * stretch_amount
		var new_scale_y = _original_scale.y / sqrt(stretch_amount)  # Inverse square root for volume preservation
		
		# Update the scale and rotation
		scale = Vector2(new_scale_x, new_scale_y)
		rotation = direction.angle()
	else:
		# Reset to original scale when velocity is low
		scale = _original_scale
		rotation = 0

	# Cap maximum speed
	if linear_velocity.length() > max_speed:
		linear_velocity = linear_velocity.normalized() * max_speed


func apply_deflection(force_vector):
	# Store for debugging
	last_applied_force = force_vector

	# Stop current movement
	linear_velocity = Vector2.ZERO
	
	# Apply the force directly
	apply_central_force(force_vector * 100)  # Multiply by 100 to amplify the effect
	
	# Alternative: Try impulse with higher value
	apply_central_impulse(force_vector)

	
	# Create visual effect
	create_impact_effect()

##debug this to ensure its working
func create_impact_effect():
	var original_color = modulate
	modulate = Color(0.2, 0.2, 0.2, 1.0)
	
	var tween = create_tween()
	tween.tween_property(self, "modulate", original_color, 0.4)

func _on_sfx_area_body_entered(body):  # Changed function name to match signal
	sparks_player.stop()
	sparks_player.play("sparks")
	if body is StaticBody2D and linear_velocity.length() > min_velocity_for_sound:
		# Play sound with volume based on impact velocity
		var impact_force = min(linear_velocity.length() / 1000.0, 1.0)
		play_collision_sound(impact_force)  # Pass the volume scale, not the audio player
	if body is RigidBody2D and linear_velocity.length() > min_velocity_for_sound:
	
		#var impact_force = min(linear_velocity.length() / 1000.0, 1.0)
		#play_collision_sound(impact_force)  # Pass the volume scale, not the audio player
		if body.is_in_group("brick") and is_instance_valid(body):
			body.hit()
		
func play_collision_sound(volume_scale = 1.0):
	wall_impact.pitch_scale = randf_range(0.9, 1.1)
	wall_impact.play()
	for player in audio_pool:
		if not player.playing:
			player.pitch_scale = randf_range(0.9, 1.1)
			player.volume_db = linear_to_db(volume_scale)
			player.play()
			wall_impact.pitch_scale = randf_range(0.9, 1.1)
			wall_impact.play()
			return
	
	# If all players are busy, use the first one
	audio_pool[0].pitch_scale = randf_range(0.9, 1.1)
	audio_pool[0].volume_db = linear_to_db(volume_scale)
	audio_pool[0].play()


## Called by whichever Ice Zone (PLAYERS/ice_zone.gd) this ball just
## entered. Cuts this ball's CURRENT velocity/spin by slow_amount once,
## right here at the moment of catching it, and scales gravity_scale down
## by the same fraction for the rest of the freeze (gravity_scale rather
## than a per-frame velocity re-damp, since the physics engine integrates a
## RigidBody2D's gravity independent of _physics_process() no matter what
## that function does or doesn't touch - see _physics_process()'s frozen
## branch, which deliberately leaves the engine alone from here on rather
## than fighting it every frame). 1.0 (the default) zeroes velocity/spin
## outright and stops gravity outright, so it holds perfectly still
## ("remains in place"); lower values leave some of its existing motion to
## carry through and keep falling/drifting at a reduced rate for the whole
## freeze, an actual slow-motion catch rather than a hard stop. duration is
## passed in far larger than any zone could actually live (see
## IceZone._NEVER_EXPIRES) - the zone calls thaw() explicitly the moment
## this ball actually leaves it (or the zone itself despawns), rather than
## this ever timing out on its own. overlay_scene (if assigned on the
## IceAbility that owns the zone - see IceAbility.frozen_ball_overlay) is
## spawned as a child for as long as that lasts; null skips spawning
## anything, same opt-in shape used elsewhere in this project.
func freeze_in_place(duration: float, slow_amount: float, overlay_scene: PackedScene = null) -> void:
	if not _is_frozen:
		_frozen_base_gravity_scale = gravity_scale
	_is_frozen = true
	_frozen_remaining = duration
	_frozen_slow_amount = clampf(slow_amount, 0.0, 1.0)
	gravity_scale = _frozen_base_gravity_scale * (1.0 - _frozen_slow_amount)
	linear_velocity *= (1.0 - _frozen_slow_amount)
	angular_velocity *= (1.0 - _frozen_slow_amount)
	_spawn_frozen_overlay(overlay_scene)


## Ends a freeze early - either from freeze_in_place()'s own countdown
## reaching 0 in _physics_process() (a natural thaw) or from another
## shield's deflect touching this ball while it's still frozen (see
## deflection_shield.gd's deflect_ball(), which calls this on any ball it
## hits before applying its own new velocity). Either way this always
## "drops": velocity/spin are zeroed rather than resuming whatever they were
## doing before the freeze - a thaw never launches the ball off with
## pre-freeze momentum - and gravity_scale is restored so it falls normally
## again. A deflect immediately overwrites the zeroed velocity with its own
## anyway; a natural timeout leaves it at rest to fall/roll fresh under
## gravity. No-op if this ball wasn't actually frozen (guards against
## deflect_ball() calling this unconditionally on every ball it ever hits) -
## gated on _is_frozen rather than _frozen_remaining, since the
## natural-timeout call from _physics_process() happens the same frame
## _frozen_remaining already reads <= 0 (see _is_frozen's doc comment).
func thaw() -> void:
	if not _is_frozen:
		return
	_is_frozen = false
	_frozen_remaining = 0.0
	_frozen_slow_amount = 0.0
	gravity_scale = _frozen_base_gravity_scale
	linear_velocity = Vector2.ZERO
	angular_velocity = 0.0
	_clear_frozen_overlay()


func _spawn_frozen_overlay(overlay_scene: PackedScene) -> void:
	_clear_frozen_overlay()
	if not is_instance_valid(overlay_scene):
		return
	var overlay: Node2D = overlay_scene.instantiate()
	add_child(overlay)
	_frozen_overlay = overlay


func _clear_frozen_overlay() -> void:
	if is_instance_valid(_frozen_overlay):
		_frozen_overlay.queue_free()
	_frozen_overlay = null
