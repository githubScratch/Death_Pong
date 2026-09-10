extends Control

## The Options screen (file kept as Mode_Menu.tscn/mode_menu.gd - the Lobby's
## own "Options" button already points at this path, so repurposing this
## scene in place needs no rename). NOT reachable from the Title screen -
## Title's "SETTINGS" button goes straight to Settings_Menu.tscn instead
## (see GameSettings.go_to_settings()).
##
## Row of 3 map buttons, row of 4 mod buttons beneath (Pure/Hydra/Zones/
## Training), then a vertical stack of Ready/Settings/Reset Options/Back.
## Training isn't compatible with a map choice or the other three mods, so
## picking it dims all of those out (see _update_button_states()) - but
## they're deliberately never actually .disabled while dimmed: pressing one
## is how you leave Training. The three mod buttons already do that just by
## being pressed (each sets game_mode to something other than "training" -
## see their own handlers below); the three map buttons have no Training
## equivalent of their own, so they route through _exit_training_mode()
## first, which lands back on "pure" before applying the map.

## Same faded-alpha treatment Character_Select.tscn already uses for an
## un-joined P3/P4 box - shared here so "dimmed but still pressable" reads
## the same way across menus.
const DISABLED_TINT := Color(1, 1, 1, 0.423529)

@onready var arena: Button = $CenterContainer/VBoxContainer/MapRow/Arena
@onready var tower: Button = $CenterContainer/VBoxContainer/MapRow/Tower
@onready var yonder: Button = $CenterContainer/VBoxContainer/MapRow/Yonder

@onready var pure: Button = $CenterContainer/VBoxContainer/ModRow/Pure
@onready var random: Button = $CenterContainer/VBoxContainer/ModRow/Random
@onready var hot_potatoe: Button = $CenterContainer/VBoxContainer/ModRow/Hot_Potatoe
@onready var training: Button = $CenterContainer/VBoxContainer/ModRow/Training

@onready var back: Button = $CenterContainer/VBoxContainer/HBoxContainer/ButtonStack/Back

@onready var select: AudioStreamPlayer2D = $select
@onready var move: AudioStreamPlayer2D = $move

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	back.grab_focus()
	GameSettings.settings_changed.connect(_update_button_states)

	# Set initial button states
	_update_button_states()

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	if Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("ui_up") or Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
		move.pitch_scale = randf_range(0.9, 1.1)
		move.play()
	if Input.is_action_just_pressed("ui_select"):
		select.pitch_scale = randf_range(0.9, 1.1)
		select.play()
	if Input.is_action_just_pressed("ui_back"):
		_on_back_pressed()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file("res://MENUS/Menu.tscn")


## Always returns to the Lobby (Character_Select.tscn) - whatever mod/map
## was chosen here is already live in GameSettings, so there's nothing else
## to hand off. Deliberately does NOT call GameSettings.go_to_character_select()
## - that would overwrite character_select_origin with this scene's own path,
## which would then send the Lobby's own Back button here instead of Title.
func _on_ready_pressed() -> void:
	get_tree().change_scene_to_file("res://MENUS/Character_Select.tscn")


func _on_pure_pressed() -> void:
	pure.set_pressed_no_signal(true)
	random.set_pressed_no_signal(false)
	hot_potatoe.set_pressed_no_signal(false)
	training.set_pressed_no_signal(false)
	GameSettings.set_game_mode("pure")

func _on_random_pressed() -> void:
	pure.set_pressed_no_signal(false)
	random.set_pressed_no_signal(true)
	hot_potatoe.set_pressed_no_signal(false)
	training.set_pressed_no_signal(false)
	GameSettings.set_game_mode("random")

func _on_hot_potatoe_pressed() -> void:
	pure.set_pressed_no_signal(false)
	random.set_pressed_no_signal(false)
	hot_potatoe.set_pressed_no_signal(true)
	training.set_pressed_no_signal(false)
	GameSettings.set_game_mode("hot")

func _on_training_pressed() -> void:
	pure.set_pressed_no_signal(false)
	random.set_pressed_no_signal(false)
	hot_potatoe.set_pressed_no_signal(false)
	training.set_pressed_no_signal(true)
	GameSettings.set_game_mode("training")


func _on_arena_pressed() -> void:
	_exit_training_mode()
	arena.set_pressed_no_signal(true)
	tower.set_pressed_no_signal(false)
	yonder.set_pressed_no_signal(false)
	GameSettings.set_game_arena("arena")
func _on_tower_pressed() -> void:
	_exit_training_mode()
	arena.set_pressed_no_signal(false)
	tower.set_pressed_no_signal(true)
	yonder.set_pressed_no_signal(false)
	GameSettings.set_game_arena("tower")
func _on_yonder_pressed() -> void:
	_exit_training_mode()
	arena.set_pressed_no_signal(false)
	tower.set_pressed_no_signal(false)
	yonder.set_pressed_no_signal(true)
	GameSettings.set_game_arena("yonder")


## Maps have no Training equivalent, so pressing one while Training is
## selected means "I want a map, take me out of Training" - lands on
## "pure", the same default _on_reset_options_pressed() uses, rather than
## trying to recall whatever mod was active before Training was picked.
## A no-op the rest of the time - only touches game_mode when Training is
## actually the current mode.
func _exit_training_mode() -> void:
	if GameSettings.game_mode == "training":
		GameSettings.set_game_mode("pure")


func _on_reset_options_pressed() -> void:
	GameSettings.reset_game_options()

func _on_settings_pressed() -> void:
	GameSettings.go_to_settings("res://MENUS/Mode_Menu.tscn")


## Keeps every toggle button's pressed state in sync with GameSettings -
## called on load and whenever settings_changed fires (e.g. Reset Options) -
## and dims the map row and the other three mods while Training is active,
## since none of them apply while it's selected. Dims rather than
## .disable()s them - see the doc comment at the top of this file for why
## they need to stay pressable.
func _update_button_states() -> void:
	pure.set_pressed_no_signal(GameSettings.game_mode == "pure")
	random.set_pressed_no_signal(GameSettings.game_mode == "random")
	hot_potatoe.set_pressed_no_signal(GameSettings.game_mode == "hot")
	training.set_pressed_no_signal(GameSettings.game_mode == "training")

	arena.set_pressed_no_signal(GameSettings.game_arena == "arena")
	tower.set_pressed_no_signal(GameSettings.game_arena == "tower")
	yonder.set_pressed_no_signal(GameSettings.game_arena == "yonder")

	var training_active: bool = GameSettings.game_mode == "training"
	var tint := DISABLED_TINT if training_active else Color.WHITE
	arena.modulate = tint
	tower.modulate = tint
	yonder.modulate = tint
	pure.modulate = tint
	random.modulate = tint
	hot_potatoe.modulate = tint
