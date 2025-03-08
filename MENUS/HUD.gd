extends Node2D
@onready var player_1_score: Label = $CanvasLayer/Player1Score
@onready var player_2_score: Label = $CanvasLayer/Player2Score


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	pass


func update_score(player1_score, player2_score):
	player_1_score.text = str(player1_score)
	player_2_score.text = str(player2_score)
