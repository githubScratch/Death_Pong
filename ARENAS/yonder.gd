extends Node2D

var player1_score = 0
var player2_score = 0
@onready var hud: Node2D = $HUD
@onready var victory_screens: AnimationPlayer = $Victory_Screens
@onready var rematch_1: Button = $Player_1_Victory/CenterContainer/VBoxContainer/HBoxContainer/Rematch1
@onready var rematch_2: Button = $Player_2_Victory/CenterContainer/VBoxContainer/HBoxContainer/Rematch2
@onready var player_1: Node2D = $player1
@onready var player_2: Node2D = $player2
@onready var continue_1: Button = $Pause/CenterContainer/VBoxContainer/HBoxContainer/Continue1
var is_paused = false
var is_victory = false
var current_instance: Node = null
@export var instance_scene: PackedScene
@onready var goal: AudioStreamPlayer2D = $goal
@onready var spawn_ball: AudioStreamPlayer2D = $spawn_ball
@onready var select: AudioStreamPlayer2D = $select
@onready var move: AudioStreamPlayer2D = $move
@onready var goal_particles: AnimationPlayer = $Goal_Particles
var ball_instances = []
@onready var canvas_layer: CanvasLayer = $Yonder/CanvasLayer
@onready var score_player = $HUD/ScorePlayer
@onready var mid_barrier: Node2D = $Mid_Barrier
@onready var mid_collision: StaticBody2D = $Mid_Barrier/Mid_Collision
@onready var portal_vfx: AnimationPlayer = $Portal_VFX
@export var swap_area_top: Area2D
@export var swap_area_bottom: Area2D
@export var teleport_cooldown: float = 0.1
var teleporting_objects = {}

@export var p3_scene: PackedScene
@export var p4_scene: PackedScene
@onready var ball_spawn: AnimationPlayer = $Ball_Spawn


func _ready() -> void:
	apply_game_settings()
	Engine.time_scale = 1.0
	is_victory = false
	ball_instances.clear()

	GameSettings.settings_changed.connect(_on_settings_changed)
	_spawn_selected_extras()

func _process(_delta: float) -> void:
	var keys_to_remove = []
	for body in teleporting_objects:
		teleporting_objects[body] -= _delta
		if teleporting_objects[body] <= 0:
			keys_to_remove.append(body)

	# Remove objects that have completed their cooldown
	for body in keys_to_remove:
		teleporting_objects.erase(body)

	# Pause/unpause itself is owned by pause_overlay.gd on the Pause node -
	# that node is the one thing that stays ALWAYS-processing, so it's the
	# only safe place to detect the toggle without a same-frame race. This
	# _process() only needs to run while the tree ISN'T paused, so it only
	# has to cover victory-state SFX.
	if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
		if is_victory:
			move.pitch_scale = randf_range(0.9, 1.1)
			move.play()
	if Input.is_action_just_pressed("ui_select"):
		if is_victory:
			select.pitch_scale = randf_range(0.9, 1.1)
			select.play()

func apply_game_settings() -> void:
	if GameSettings.game_mode == "random":
		pass
	if GameSettings.game_mode == "hot":
		mid_barrier.visible = true
		mid_collision.set_collision_layer_value(5, true)
		create_new_instance()
	else:
		create_new_instance()
func _on_settings_changed() -> void:
	# Re-apply settings when they change
	apply_game_settings()

#Ball Reset
func create_new_instance():
	# Check if scene is assigned using is_instance_valid
	if is_instance_valid(instance_scene):
		ball_spawn.play("spawn")
		await get_tree().create_timer(0.7).timeout
		var instance = instance_scene.instantiate()
		instance.global_position = Vector2(574, 160)
		get_tree().current_scene.add_child(instance)
		# Add the instance to our array
		ball_instances.append(instance)
		spawn_ball.pitch_scale = randf_range(0.4, 0.6)
		spawn_ball.play()

#Scoring
func _on_goal_left_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		# Remove this specific ball from our array
		if ball_instances.has(body):
			ball_instances.erase(body)
		goal_particles.play("RESET")
		goal_particles.play("left_goal")
		player2_score += 1
		score_player.play("RESET")
		score_player.play("p2")
		hud.update_score(player1_score, player2_score)
		goal.pitch_scale = randf_range(0.9, 1.1)
		goal.play()
		
		# Queue this specific ball for deletion
		body.queue_free()
		
		if player2_score >= 5 and GameSettings.game_mode != "random":
			# Clear all remaining balls
			for ball in ball_instances:
				if is_instance_valid(ball):
					ball.queue_free()
			ball_instances.clear()
			
			victory_screens.play("Player_2_Victory")
			is_victory = true
			rematch_2.grab_focus()
		elif player2_score >= 5 and GameSettings.game_mode == "random":
			for ball in ball_instances:
				if is_instance_valid(ball):
					ball.queue_free()
			ball_instances.clear()
			
			victory_screens.play("Player_2_Victory")
			is_victory = true
			rematch_2.grab_focus()
		else:
			if GameSettings.game_mode == "random":
				create_new_instance()
				create_new_instance()
			else:
				create_new_instance()
func _on_goal_right_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		# Remove this specific ball from our array
		if ball_instances.has(body):
			ball_instances.erase(body)
		goal_particles.play("RESET")
		goal_particles.play("right_goal")
		player1_score += 1
		score_player.play("RESET")
		score_player.play("p1")
		hud.update_score(player1_score, player2_score)
		goal.pitch_scale = randf_range(0.9, 1.1)
		goal.play()
		
		# Queue this specific ball for deletion
		body.queue_free()
		
		if player1_score >= 5 and GameSettings.game_mode != "random":
			# Clear all remaining balls
			for ball in ball_instances:
				if is_instance_valid(ball):
					ball.queue_free()
			ball_instances.clear()
			
			victory_screens.play("Player_1_Victory")
			is_victory = true
			rematch_1.grab_focus()
		elif player1_score >= 5 and GameSettings.game_mode == "random":
			for ball in ball_instances:
				if is_instance_valid(ball):
					ball.queue_free()
			ball_instances.clear()
			
			victory_screens.play("Player_1_Victory")
			is_victory = true
			rematch_1.grab_focus()
		else:
			if GameSettings.game_mode == "random":
				create_new_instance()
				create_new_instance()
			else:
				create_new_instance()

func pause():
	get_tree().paused = true
	victory_screens.play("Pause")
	is_paused = true
	continue_1.grab_focus()
func unpause_game():
	is_paused = false
	continue_1.release_focus()
	victory_screens.play("Clear")
	await get_tree().create_timer(0.5).timeout
	get_tree().paused = false


#Time Slow Zones ---  debug shader parameter tweens
func _on_zone_left_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		Engine.time_scale = 0.5
		#screen_shader.material.set_shader_parameter("Abberation", 1)
func _on_zone_left_body_exited(body: Node2D) -> void:
	if body.is_in_group("ball"):
		Engine.time_scale = 1.0
func _on_zone_right_body_entered(body: Node2D) -> void:
	if body.is_in_group("ball"):
		Engine.time_scale = 0.5
func _on_zone_right_body_exited(body: Node2D) -> void:
	if body.is_in_group("ball"):
		Engine.time_scale = 1.0

#UI
func _on_rematch_1_pressed() -> void:
	get_tree().change_scene_to_file("res://ARENAS/yonder.tscn")
func _on_rematch_2_pressed() -> void:
	get_tree().change_scene_to_file("res://ARENAS/yonder.tscn")
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


func _on_portal_bottom_body_entered(body: Node2D) -> void:
	if can_teleport(body):
		# Get the top area's position
		portal_vfx.stop()
		portal_vfx.play("bot_glow")
		var target_y = swap_area_top.global_position.y
		
		# Calculate the y offset to position the object just above the top area
		var offset_y = 0
		if swap_area_top.has_node("CollisionShape2D"):
			var shape = swap_area_top.get_node("CollisionShape2D").shape
			if shape is RectangleShape2D:
				offset_y = -shape.size.y / 2
		
		# Keep the x-coordinate the same, change only the y
		var new_position = Vector2(body.global_position.x, target_y + offset_y)
		
		# Perform teleportation
		teleport_object(body, new_position)

func _on_portal_top_body_entered(body: Node2D) -> void:
	if can_teleport(body):
		# Get the bottom area's position
		portal_vfx.play("top_glow")
		var target_y = swap_area_bottom.global_position.y
		
		# Calculate the y offset to position the object just below the bottom area
		var offset_y = 0
		if swap_area_bottom.has_node("CollisionShape2D"):
			var shape = swap_area_bottom.get_node("CollisionShape2D").shape
			if shape is RectangleShape2D:
				offset_y = shape.size.y / 2
		
		# Keep the x-coordinate the same, change only the y
		var new_position = Vector2(body.global_position.x, target_y + offset_y)
		
		# Perform teleportation
		teleport_object(body, new_position)

func teleport_object(body, new_position):
	# Set the new position
	body.global_position = new_position
	
	# Add object to teleporting list with cooldown
	teleporting_objects[body] = teleport_cooldown
	
	# Create a timer to remove the cooldown
	get_tree().create_timer(teleport_cooldown).timeout.connect(
		func(): 
			if teleporting_objects.has(body):
				teleporting_objects.erase(body)
	)

func can_teleport(body):
	# Check if the object is currently on cooldown
	return not teleporting_objects.has(body)


## Instantiates P3/P4 immediately if that seat was activated on the
## character select screen (see MENUS/character_select.gd) - replaces the
## old "press your own down button mid-match to summon" mechanic. Position/
## SFX here are exactly what summon_p3()/summon_p4() used to use - note P3
## and P4 use different spawn points, same as before.
func _spawn_selected_extras() -> void:
	if GameSettings.seat_active.size() > 2 and GameSettings.seat_active[2] and is_instance_valid(p3_scene):
		var p3_instance = p3_scene.instantiate()
		p3_instance.global_position = Vector2(566, 143)
		get_tree().current_scene.add_child(p3_instance)
		spawn_ball.pitch_scale = randf_range(1.4, 1.6)
		spawn_ball.play()
	if GameSettings.seat_active.size() > 3 and GameSettings.seat_active[3] and is_instance_valid(p4_scene):
		var p4_instance = p4_scene.instantiate()
		p4_instance.global_position = Vector2(576, 70)
		get_tree().current_scene.add_child(p4_instance)
		spawn_ball.pitch_scale = randf_range(1.4, 1.6)
		spawn_ball.play()
