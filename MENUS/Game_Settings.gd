extends Node

signal settings_changed # Signal to notify when any setting changes
# Variables to store selected game mode and map
var game_mode = "pure" # "pure" or "random"
var game_arena = "arena" # "arena", "tower", or "yonder"
var game_magic = "on" # "stock" or "time"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("p1_up") or Input.is_action_just_pressed("p2_up"):
		Input.action_press("ui_up")
	if Input.is_action_just_pressed("p1_down") or Input.is_action_just_pressed("p2_down"):
		Input.action_press("ui_down")
	if Input.is_action_just_pressed("p1_left") or Input.is_action_just_pressed("p2_left"):
		Input.action_press("ui_left")
	if Input.is_action_just_pressed("p1_right") or Input.is_action_just_pressed("p2_right"):
		Input.action_press("ui_right")
	if Input.is_action_just_pressed("p1_pause_select") or Input.is_action_just_pressed("p2_pause_select"):
		Input.action_press("ui_select")
		
	if Input.is_action_just_released("p1_up") or Input.is_action_just_released("p2_up"):
		Input.action_release("ui_up")
	if Input.is_action_just_released("p1_down") or Input.is_action_just_released("p2_down"):
		Input.action_release("ui_down")
	if Input.is_action_just_released("p1_left") or Input.is_action_just_released("p2_left"):
		Input.action_release("ui_left")
	if Input.is_action_just_released("p1_right") or Input.is_action_just_released("p2_right"):
		Input.action_release("ui_right")
	if Input.is_action_just_released("p1_pause_select") or Input.is_action_just_released("p2_pause_select"):
		Input.action_release("ui_select")

func set_game_mode(mode: String) -> void:
	game_mode = mode
	emit_signal("settings_changed")
	print("mode change signal emitted")

func set_game_arena(arena: String) -> void:
	game_arena = arena
	emit_signal("settings_changed")
	print("arena change signal emitted")

func set_game_magic(on: String) -> void:
	game_magic = on
	emit_signal("settings_changed")
	print("magic change signal emitted")
	
	
