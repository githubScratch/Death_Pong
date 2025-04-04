extends RigidBody2D
@onready var color_rect: ColorRect = $ColorRect
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func _on_body_entered(body: Node) -> void:
	if body.is_in_group("ball"):
		print("brick hit!")
		color_rect.visible = false
		collision_shape_2d.disabled = true
		await get_tree().create_timer(.25).timeout
		queue_free()
	else:
		print("oops")
