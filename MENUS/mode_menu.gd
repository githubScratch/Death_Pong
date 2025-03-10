extends Control
@onready var back: Button = $CenterContainer/HBoxContainer/VBoxContainer4/Back
@onready var pure: Button = $CenterContainer/HBoxContainer/VBoxContainer3/Pure
@onready var random: Button = $CenterContainer/HBoxContainer/VBoxContainer3/Random
@onready var arena: Button = $CenterContainer/HBoxContainer/VBoxContainer/Arena
@onready var yonder: Button = $CenterContainer/HBoxContainer/VBoxContainer/Yonder
@onready var stock: Button = $CenterContainer/HBoxContainer/VBoxContainer2/STOCK
@onready var time: Button = $CenterContainer/HBoxContainer/VBoxContainer2/TIME


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	back.grab_focus()


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://MENUS/Menu.tscn")


func _on_begin_pressed() -> void:
	get_tree().change_scene_to_file("res://ARENAS/arena.tscn")

func _on_pure_pressed() -> void:
	pure.set_pressed_no_signal(true)
	random.set_pressed_no_signal(false)
func _on_random_pressed() -> void:
	pure.set_pressed_no_signal(false)
	random.set_pressed_no_signal(true)

func _on_arena_pressed() -> void:
	arena.set_pressed_no_signal(true)
	yonder.set_pressed_no_signal(false)
func _on_yonder_pressed() -> void:
	arena.set_pressed_no_signal(false)
	yonder.set_pressed_no_signal(true)

func _on_stock_pressed() -> void:
	stock.set_pressed_no_signal(true)
	time.set_pressed_no_signal(false)
func _on_time_pressed() -> void:
	stock.set_pressed_no_signal(false)
	time.set_pressed_no_signal(true)
