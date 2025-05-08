extends Control

@onready var select: AudioStreamPlayer2D = $select
@onready var move: AudioStreamPlayer2D = $move
@onready var back_button: Button = $CenterContainer/HBoxContainer/BackCont/BackButton
@onready var windowed_button: Button = $CenterContainer/HBoxContainer/VBoxContainer/ScreenCont/HBoxContainer/WindowedButton
@onready var full_button: Button = $CenterContainer/HBoxContainer/VBoxContainer/ScreenCont/HBoxContainer/FullButton
@onready var bgm_slide: HSlider = $CenterContainer/HBoxContainer/VBoxContainer/SoundCont/HBoxContainer2/BGMSlide
@onready var sfx_slide: HSlider = $CenterContainer/HBoxContainer/VBoxContainer/SoundCont/HBoxContainer3/SFXSlide

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


func _on_windowed_button_pressed() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
	full_button.set_pressed_no_signal(false)
	windowed_button.set_pressed_no_signal(true)
	
func _on_full_button_pressed() -> void:
	#DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	full_button.set_pressed_no_signal(true)
	windowed_button.set_pressed_no_signal(false)


func _on_reset_button_pressed() -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN)
	full_button.set_pressed_no_signal(true)
	windowed_button.set_pressed_no_signal(false)
	bgm_slide.set_value(1)
	sfx_slide.set_value(1)
