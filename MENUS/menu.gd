extends Control
@onready var begin: Button = $CenterContainer/VBoxContainer/Begin

func _ready():
	begin.grab_focus()

func _on_begin_pressed() -> void:
	get_tree().change_scene_to_file("res://ARENAS/arena.tscn")

func _on_options_pressed() -> void:
	get_tree().change_scene_to_file("res://MENUS/Mode_Menu.tscn")

func _on_quit_pressed() -> void:
	get_tree().quit()
