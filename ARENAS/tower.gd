extends Node2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	if Input.is_action_just_pressed("ui_select"):
		get_tree().change_scene_to_file("res://MENUS/Menu.tscn")


func _on_brickpurge_l_body_entered(body: Node2D) -> void:
	if body.is_in_group("brick"):
		body.queue_free()
		print("gone")

func _on_brickpurge_r_body_entered(body: Node2D) -> void:
	if body.is_in_group("brick"):
		body.queue_free()
		print("gone")
