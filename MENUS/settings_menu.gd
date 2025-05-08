extends Control

@onready var select: AudioStreamPlayer2D = $select
@onready var move: AudioStreamPlayer2D = $move
@onready var back_button: Button = $CenterContainer/HBoxContainer/BackCont/BackButton

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	back_button.grab_focus()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
		move.pitch_scale = randf_range(0.9, 1.1)
		move.play()
	if Input.is_action_just_pressed("ui_select"):
		select.pitch_scale = randf_range(0.9, 1.1)
		select.play()



func _on_back_button_pressed() -> void:
	get_tree().change_scene_to_file("res://MENUS/Mode_Menu.tscn")
