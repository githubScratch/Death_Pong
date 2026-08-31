extends Control

const REBIND_MENU_SCENE := preload("res://MENUS/Rebind_Menu.tscn")

@onready var select: AudioStreamPlayer2D = $select
@onready var move: AudioStreamPlayer2D = $move
@onready var back_button: Button = $CenterContainer/HBoxContainer/BackCont/BackButton
@onready var windowed_button: Button = $CenterContainer/HBoxContainer/VBoxContainer/ScreenCont/HBoxContainer/WindowedButton
@onready var full_button: Button = $CenterContainer/HBoxContainer/VBoxContainer/ScreenCont/HBoxContainer/FullButton
@onready var bgm_slide: HSlider = $CenterContainer/HBoxContainer/VBoxContainer/SoundCont/HBoxContainer2/BGMSlide
@onready var sfx_slide: HSlider = $CenterContainer/HBoxContainer/VBoxContainer/SoundCont/HBoxContainer3/SFXSlide

@onready var p1_button: Button = $CenterContainer/HBoxContainer/VBoxContainer/ControlCont/HBoxContainer/VBoxContainer/P1C
@onready var p2_button: Button = $CenterContainer/HBoxContainer/VBoxContainer/ControlCont/HBoxContainer/VBoxContainer2/P2C
@onready var p3_button: Button = $CenterContainer/HBoxContainer/VBoxContainer/ControlCont/HBoxContainer/VBoxContainer3/P2C
@onready var p4_button: Button = $CenterContainer/HBoxContainer/VBoxContainer/ControlCont/HBoxContainer/VBoxContainer4/P2C

var rebind_menu: Control

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	back_button.grab_focus()

	# These were placed as toggle buttons in the editor; they should behave
	# like normal "open a screen" buttons instead.
	for b in [p1_button, p2_button, p3_button, p4_button]:
		b.toggle_mode = false
	p1_button.pressed.connect(func(): _open_rebind(1))
	p2_button.pressed.connect(func(): _open_rebind(2))
	p3_button.pressed.connect(func(): _open_rebind(3))
	p4_button.pressed.connect(func(): _open_rebind(4))

	rebind_menu = REBIND_MENU_SCENE.instantiate()
	add_child(rebind_menu)

func _open_rebind(player: int) -> void:
	rebind_menu.open_for_player(player)


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
		move.pitch_scale = randf_range(0.9, 1.1)
		move.play()
	if Input.is_action_just_pressed("ui_select"):
		select.pitch_scale = randf_range(0.9, 1.1)
		select.play()

	# The rebind overlay handles its own Backspace (cancel/close); don't
	# also navigate Settings itself away while it's open.
	if Input.is_action_just_pressed("ui_back") and not rebind_menu.visible:
		_on_back_button_pressed()



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

	# Clean slate: wipes the save folder (including any saved keybinds) and
	# reapplies the project's original keyboard defaults for p1-p4.
	InputRemap.reset_all_to_defaults()
