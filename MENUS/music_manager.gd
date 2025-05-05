# MusicManager.gd (attached to the root node)
extends Node

@onready var music: AudioStreamPlayer2D = $music

func _ready():
	if not music.playing:
		music.play()
