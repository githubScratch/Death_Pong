extends Area2D
class_name DeflectionShield

## Shared deflection-shield behavior for every wizard class - previously
## four separate, nearly-identical scripts (DeflectionShield1-4, one per
## class, differing only in class_name). Every class's shield scene now
## points at this single script instead; whatever makes one class's shield
## feel different (deflection force, sfx stream, animations) still lives on
## that class's own scene, not here.
##
## Emits `deflected` on every successful ball hit - wizard.gd listens for
## this on whatever instance it just spawned (see create_new_instance()) to
## grow that wizard's banked strike count. Strikes are core, shared
## infrastructure now: every class's shield reports them the same way, even
## though only some classes' abilities currently do anything with the count
## (see GrowthAbility).

signal deflected

@export var deflection_force: float = 1200.0
@onready var deflect_sfx: AudioStreamPlayer2D = $"../deflect_SFX"
@onready var animation_player: AnimationPlayer = $"../AnimationPlayer"

var _freeze_queue = []
var _is_processing_freeze = false

func _ready():
	pass

func _on_body_entered(body):
	if body.is_in_group("ball"):
		var direction = (body.global_position - global_position).normalized()
		deflect_ball(body, direction)

func deflect_ball(ball, direction):
	if ball is RigidBody2D:
		var new_velocity = direction * deflection_force
		ball.linear_velocity = new_velocity
		deflect_sfx.pitch_scale = randf_range(0.9, 1.1)
		deflect_sfx.play()
		animation_player.stop()
		animation_player.play("deflect")
		deflected.emit()

func start_fade() -> void:
	if animation_player.is_playing() and animation_player.current_animation != "fade":
		await animation_player.animation_finished
	if animation_player.has_animation("fade"):
		animation_player.play("fade")
		await animation_player.animation_finished
	queue_free()

func freeze_frame(duration := 0.1):
	_freeze_queue.append(duration)
	if not _is_processing_freeze:
		_process_next_freeze()

func _process_next_freeze():
	if _freeze_queue.size() == 0:
		_is_processing_freeze = false
		return
	_is_processing_freeze = true
	var duration = _freeze_queue.pop_front()
	var original_time_scale = Engine.time_scale
	Engine.time_scale = 0.1
	var start_time = Time.get_ticks_msec()
	var end_time = start_time + int(duration * 1000)
	while Time.get_ticks_msec() < end_time:
		await get_tree().process_frame
	Engine.time_scale = 1.0
	_process_next_freeze()
