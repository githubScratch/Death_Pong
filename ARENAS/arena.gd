extends Node2D

var player1_score = 0
var player2_score = 0
@onready var hud: Node2D = $HUD
@onready var ball: Node2D = $Ball

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_goal_left_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		player2_score += 1
		hud.update_score(player1_score, player2_score)
		#emit_signal("goal_left_scored")
		#reset_ball()


func _on_goal_right_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		player1_score += 1
		hud.update_score(player1_score, player2_score)

		#emit_signal("goal_right_scored")
		#reset_ball()


func reset_ball():
	pass
	# Stop the ball
	#ball.linear_velocity = Vector2.ZERO
	#ball.position = Vector2(get_viewport_rect().size.x / 2, get_viewport_rect().size.y / 2)
	#await get_tree().create_timer(1.0).timeout
	#ball.apply_central_impulse(Vector2(randf_range(-200, 200), randf_range(-200, 200)))
