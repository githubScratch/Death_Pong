extends Control
@onready var back: Button = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer4/Back
@onready var pure: Button = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer3/Pure
@onready var random: Button = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer3/Random
@onready var arena: Button = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer/Arena
@onready var tower: Button = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer/Tower
@onready var on: Button = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer2/On
@onready var off: Button = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer2/Off
@onready var yonder: Button = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer/Yonder
@onready var hot_potatoe: Button = $CenterContainer/VBoxContainer/HBoxContainer/VBoxContainer3/Hot_Potatoe


@onready var select: AudioStreamPlayer2D = $select
@onready var move: AudioStreamPlayer2D = $move

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	back.grab_focus()
	GameSettings.settings_changed.connect(_update_button_states)
	
	# Set initial button states
	_update_button_states()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
		move.pitch_scale = randf_range(0.9, 1.1)
		move.play()
	if Input.is_action_just_pressed("ui_select"):
		select.pitch_scale = randf_range(0.9, 1.1)
		select.play()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://MENUS/Menu.tscn")


func _on_begin_pressed() -> void:
	if GameSettings.game_arena == "arena":
		get_tree().change_scene_to_file("res://ARENAS/arena.tscn")
	if GameSettings.game_arena == "tower":
		get_tree().change_scene_to_file("res://ARENAS/tower.tscn")
	if GameSettings.game_arena == "yonder":
		get_tree().change_scene_to_file("res://ARENAS/yonder.tscn")

func _on_pure_pressed() -> void:
	pure.set_pressed_no_signal(true)
	random.set_pressed_no_signal(false)
	hot_potatoe.set_pressed_no_signal(false)
	GameSettings.set_game_mode("pure")
func _on_random_pressed() -> void:
	pure.set_pressed_no_signal(false)
	random.set_pressed_no_signal(true)
	hot_potatoe.set_pressed_no_signal(false)
	GameSettings.set_game_mode("random")
func _on_hot_potatoe_pressed() -> void:
	pure.set_pressed_no_signal(false)
	random.set_pressed_no_signal(false)
	hot_potatoe.set_pressed_no_signal(true)
	GameSettings.set_game_mode("hot")


func _on_arena_pressed() -> void:
	arena.set_pressed_no_signal(true)
	tower.set_pressed_no_signal(false)
	yonder.set_pressed_no_signal(false)
	GameSettings.set_game_arena("arena")
func _on_tower_pressed() -> void:
	arena.set_pressed_no_signal(false)
	tower.set_pressed_no_signal(true)
	yonder.set_pressed_no_signal(false)
	GameSettings.set_game_arena("tower")
func _on_yonder_pressed() -> void:
	arena.set_pressed_no_signal(false)
	tower.set_pressed_no_signal(false)
	yonder.set_pressed_no_signal(true)
	GameSettings.set_game_arena("yonder")


func _on_on_pressed() -> void:
	on.set_pressed_no_signal(true)
	off.set_pressed_no_signal(false)
	GameSettings.set_game_magic("on")
func _on_off_pressed() -> void:
	on.set_pressed_no_signal(false)
	off.set_pressed_no_signal(true)
	GameSettings.set_game_magic("off")

func _update_button_states() -> void:
	pure.set_pressed_no_signal(GameSettings.game_mode == "pure")
	random.set_pressed_no_signal(GameSettings.game_mode == "random")
	hot_potatoe.set_pressed_no_signal(GameSettings.game_mode == "hot")
	
	arena.set_pressed_no_signal(GameSettings.game_arena == "arena")
	tower.set_pressed_no_signal(GameSettings.game_arena == "tower")
	yonder.set_pressed_no_signal(GameSettings.game_arena == "yonder")
	
	on.set_pressed_no_signal(GameSettings.game_magic == "on")
	off.set_pressed_no_signal(GameSettings.game_magic == "off")


func _on_training_pressed() -> void:
	get_tree().change_scene_to_file("res://ARENAS/training.tscn")

func _on_settings_pressed() -> void:
	get_tree().change_scene_to_file("res://MENUS/Settings_Menu.tscn")
