extends Node2D
@onready var player_1_score: Label = $CanvasLayer/Player1Score
@onready var player_2_score: Label = $CanvasLayer/Player2Score


func _ready() -> void:
	pass # Replace with function body.

func _process(_delta: float) -> void:
	pass


func update_score(player1_score, player2_score):
	player_1_score.text = str(player1_score)
	player_2_score.text = str(player2_score)
