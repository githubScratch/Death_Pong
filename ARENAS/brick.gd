extends RigidBody2D
@onready var color_rect: ColorRect = $ColorRect
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var light_occluder_2d: LightOccluder2D = $LightOccluder2D
@onready var animation_player: AnimationPlayer = $AnimationPlayer
var being_destroyed = false

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass

func hit():
	if not being_destroyed:
		being_destroyed = true
		animation_player.play("hit")
		#color_rect.visible = false
		#collision_shape_2d.disabled = true
		#light_occluder_2d.visible = false
		await get_tree().create_timer(.75).timeout
		queue_free()
