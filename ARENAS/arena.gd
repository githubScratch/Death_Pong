extends Node2D

var player1_score = 0
var player2_score = 0
@onready var hud: Node2D = $HUD
#@onready var ball: Node2D = $Ball

var current_instance: Node = null
@export var instance_scene: PackedScene

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	create_new_instance()
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func create_new_instance():
	# First, remove any existing instance
	if is_instance_valid(current_instance):
		current_instance.queue_free()
		current_instance = null
	
	# Check if scene is assigned using is_instance_valid
	if is_instance_valid(instance_scene):
		await get_tree().create_timer(0.5).timeout
		var instance = instance_scene.instantiate()
		instance.global_position = Vector2(576,320)
		get_tree().current_scene.add_child(instance)
		current_instance = instance

func _on_goal_left_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		player2_score += 1
		hud.update_score(player1_score, player2_score)
		await get_tree().create_timer(0.2).timeout
		create_new_instance()
		#emit_signal("goal_left_scored")
		#reset_ball()


func _on_goal_right_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		player1_score += 1
		hud.update_score(player1_score, player2_score)
		await get_tree().create_timer(0.2).timeout
		create_new_instance()
		#emit_signal("goal_right_scored")
		#reset_ball()


func reset_ball():
	pass
	# Stop the ball
	#ball.linear_velocity = Vector2.ZERO
	#ball.position = Vector2(get_viewport_rect().size.x / 2, get_viewport_rect().size.y / 2)
	#await get_tree().create_timer(1.0).timeout
	#ball.apply_central_impulse(Vector2(randf_range(-200, 200), randf_range(-200, 200)))

#Time Slow Zones
func _on_zone_left_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		Engine.time_scale = 0.35
func _on_zone_left_body_exited(body: Node2D) -> void:
	if body.is_in_group("ball"):
		Engine.time_scale = 1.0
func _on_zone_right_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		Engine.time_scale = 0.35
func _on_zone_right_body_exited(body: Node2D) -> void:
	if body.is_in_group("ball"):
		Engine.time_scale = 1.0
