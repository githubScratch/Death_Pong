extends Node2D

var player1_score = 0
var player2_score = 0
var is_paused = false
var is_victory = false
var current_instance: Node = null
@export var instance_scene: PackedScene
@onready var hud: Node2D = $CameraPackage/HUD
@onready var spawn_ball: AudioStreamPlayer2D = $spawn_ball
@onready var goal: AudioStreamPlayer2D = $goal
@onready var ballspawn: Area2D = $CameraPackage/ballspawn
@onready var screen_player: AnimationPlayer = $CameraPackage/Screens/ScreenPlayer
@onready var continue_1: Button = $CameraPackage/Screens/Pause/CenterContainer/VBoxContainer/HBoxContainer/Continue1
@onready var select: AudioStreamPlayer2D = $select
@onready var move: AudioStreamPlayer2D = $move
@onready var rematch_1: Button = $CameraPackage/Screens/Player_1_Victory/CenterContainer/VBoxContainer/HBoxContainer/Rematch1
@onready var rematch_2: Button = $CameraPackage/Screens/Player_2_Victory/CenterContainer/VBoxContainer/HBoxContainer/Rematch2

var ball_instances = []

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	apply_game_settings() 
	Engine.time_scale = 1.0
	is_victory = false
	ball_instances.clear()
	
	if GameSettings.game_mode == "random":
		create_new_instance()
		create_new_instance()
	else:
		create_new_instance()
	
	GameSettings.settings_changed.connect(_on_settings_changed)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
		if is_paused or is_victory:
			move.pitch_scale = randf_range(0.9, 1.1)
			move.play()
	if Input.is_action_just_pressed("ui_select"):
		if is_paused or is_victory:
			select.pitch_scale = randf_range(0.9, 1.1)
			select.play()
	if Input.is_action_just_pressed("ui_select"):
		if not is_paused and not is_victory:
			pause()
			screen_player.play("pause")
			is_paused = true
			continue_1.grab_focus()
		elif is_paused and not is_victory:
			unpause_game()
			print("UI accept pressed while paused")

func apply_game_settings() -> void:
	# Apply magic setting
	if GameSettings.game_mode == "pure":
		print("Pure mode on")
	else:
		print("Random mode on")
func _on_settings_changed() -> void:
	# Re-apply settings when they change
	apply_game_settings()

#Ball Reset
func create_new_instance():
	# Check if scene is assigned using is_instance_valid
	if is_instance_valid(instance_scene):
		await get_tree().create_timer(0.5).timeout
		var instance = instance_scene.instantiate()
		instance.global_position = ballspawn.global_position
		get_tree().current_scene.add_child(instance)
		# Add the instance to our array
		ball_instances.append(instance)
		spawn_ball.pitch_scale = randf_range(0.4, 0.6)
		spawn_ball.play()

func _on_brickpurge_l_body_entered(body: Node2D) -> void:
	if body.is_in_group("brick"):
		body.queue_free()
		print("gone")

func _on_brickpurge_r_body_entered(body: Node2D) -> void:
	if body.is_in_group("brick"):
		body.queue_free()
		print("gone")


func _on_leftgoal_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		# Remove this specific ball from our array
		if ball_instances.has(body):
			ball_instances.erase(body)
		
		#goal_particles.play("left_goal")
		player2_score += 1
		hud.update_score(player1_score, player2_score)
		goal.pitch_scale = randf_range(0.9, 1.1)
		goal.play()
		
		# Queue this specific ball for deletion
		body.queue_free()
		
		if player2_score >= 5 and GameSettings.game_mode == "pure":
			# Clear all remaining balls
			for ball in ball_instances:
				if is_instance_valid(ball):
					ball.queue_free()
			ball_instances.clear()
			
			screen_player.play("Player_2_Victory")
			is_victory = true
			rematch_2.grab_focus()
		elif player2_score >= 10 and GameSettings.game_mode == "random":
			for ball in ball_instances:
				if is_instance_valid(ball):
					ball.queue_free()
			ball_instances.clear()
			
			screen_player.play("Player_2_Victory")
			is_victory = true
			rematch_2.grab_focus()
		else:
			if GameSettings.game_mode == "random":
				create_new_instance()
				create_new_instance()
			else:
				create_new_instance()


func _on_rightgoal_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		# Remove this specific ball from our array
		if ball_instances.has(body):
			ball_instances.erase(body)
		
		#goal_particles.play("right_goal")
		player1_score += 1
		hud.update_score(player1_score, player2_score)
		goal.pitch_scale = randf_range(0.9, 1.1)
		goal.play()
		
		# Queue this specific ball for deletion
		body.queue_free()
		
		if player1_score >= 5 and GameSettings.game_mode == "pure":
			# Clear all remaining balls
			for ball in ball_instances:
				if is_instance_valid(ball):
					ball.queue_free()
			ball_instances.clear()
			
			screen_player.play("Player_1_Victory")
			is_victory = true
			rematch_1.grab_focus()
		elif player1_score >= 10 and GameSettings.game_mode == "random":
			for ball in ball_instances:
				if is_instance_valid(ball):
					ball.queue_free()
			ball_instances.clear()
			
			screen_player.play("Player_1_Victory")
			is_victory = true
			rematch_1.grab_focus()
		else:
			if GameSettings.game_mode == "random":
				create_new_instance()
				create_new_instance()
			else:
				create_new_instance()


func _on_leftslow_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		Engine.time_scale = 0.35
func _on_leftslow_body_exited(body: Node2D) -> void:
	if body.is_in_group("ball"):
		Engine.time_scale = 1.0

func _on_rightslow_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		Engine.time_scale = 0.35
func _on_rightslow_body_exited(body: Node2D) -> void:
	if body.is_in_group("ball"):
		Engine.time_scale = 1.0


func _on_rematch_1_pressed() -> void:
	get_tree().change_scene_to_file("res://ARENAS/tower.tscn")
func _on_rematch_2_pressed() -> void:
	get_tree().change_scene_to_file("res://ARENAS/tower.tscn")


func _on_menu_1_pressed() -> void:
	get_tree().change_scene_to_file("res://MENUS/Menu.tscn")
func _on_menu_2_pressed() -> void:
	get_tree().change_scene_to_file("res://MENUS/Menu.tscn")


func _on_continue_1_pressed() -> void:
	unpause_game()
func _on_menu_3_pressed() -> void:
	is_paused = false
	get_tree().paused = false
	get_tree().change_scene_to_file("res://MENUS/Menu.tscn")

func pause():
	get_tree().paused = true
func unpause_game():
	is_paused = false
	continue_1.release_focus()
	screen_player.play("clear")
	await get_tree().create_timer(0.5).timeout
	get_tree().paused = false
