extends Control
@onready var begin: Button = $CenterContainer/VBoxContainer/Begin
@onready var select: AudioStreamPlayer2D = $select
@onready var move: AudioStreamPlayer2D = $move

func _ready():
	begin.grab_focus()

func _physics_process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("ui_up"):
		move.pitch_scale = randf_range(0.9, 1.1)
		move.play()
	if Input.is_action_just_pressed("ui_select"):
		select.pitch_scale = randf_range(0.9, 1.1)
		select.play()
	

func _on_begin_pressed() -> void:
	if GameSettings.game_arena == "arena":
		get_tree().change_scene_to_file("res://ARENAS/arena.tscn")
	else:
		get_tree().change_scene_to_file("res://ARENAS/tower.tscn")

func _on_options_pressed() -> void:
	get_tree().change_scene_to_file("res://MENUS/Mode_Menu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
