extends Node

signal settings_changed # Signal to notify when any setting changes
# Variables to store selected game mode and map
var game_mode = "pure" # "pure" or "random"
var game_arena = "arena" # "arena", "tower", or "yonder"
var game_magic = "on" # "stock" or "time"

# Which class each seat is currently wearing - index 0..3 for seats 1..4.
# Defaults match what every arena scene already hardcoded before character
# select existed, so a scene opened directly (skipping the menus entirely,
# e.g. for testing) still gets a sensible, distinct class per seat.
# character_select.gd overwrites entries live as players cycle; wizard.gd's
# _ready() prefers whatever's here over a scene's own baked-in default.
var selected_classes: Array = [
	preload("res://PLAYERS/classes/class_1.tres"),
	preload("res://PLAYERS/classes/class_2.tres"),
	preload("res://PLAYERS/classes/class_3.tres"),
	preload("res://PLAYERS/classes/class_4.tres"),
]

# Every real class a seat can land on - used by reroll_random_seats() below
# to pick a fresh one for a rematch. A separate list from character_select.gd's
# own CLASSES const (same four resources) rather than a shared reference,
# same "duplicated per file that needs it" shape selected_classes' own
# defaults above already follow in this file.
const CLASSES: Array[WizardClass] = [
	preload("res://PLAYERS/classes/class_1.tres"),
	preload("res://PLAYERS/classes/class_2.tres"),
	preload("res://PLAYERS/classes/class_3.tres"),
	preload("res://PLAYERS/classes/class_4.tres"),
]

# Whether each seat's CURRENT selected_classes entry came from a "Random"
# pick on the character select screen rather than a deliberately chosen
# class - index 0..3 for seats 1..4. Set by set_selected_class() below
# (character_select.gd's _resolve_random_picks() passes was_random=true the
# moment a Random pick actually gets rolled; every deliberate pick passes
# the default false instead). Read by reroll_random_seats() so a rematch can
# roll every still-Random seat a FRESH surprise instead of silently
# repeating whatever it happened to land on last match, while a seat that
# deliberately chose a class keeps wearing it, rematch after rematch.
var was_random_pick: Array = [false, false, false, false]

# Which menu sent the player to character select, so its Back button can
# return them to wherever they actually came from.
var character_select_origin: String = "res://MENUS/Menu.tscn"

# Whether each seat joined on the character select screen - index 0..3 for
# seats 1..4. P1/P2 are always true (they're always active there); P3/P4
# start false and flip to true only once that seat's own controls are
# touched. Each arena's _spawn_selected_extras() reads seats 2/3 (P3/P4)
# from this at match start instead of waiting for an in-match summon press -
# see character_select.gd's _refresh_box() for where this gets written.
var seat_active: Array = [true, true, false, false]

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	# This autoload forwards p1-p4 input into ui_up/down/left/right/select
	# every frame (see _process below), and that forwarding is now the ONLY
	# way those actions get driven - the arena pause screens set
	# get_tree().paused = true, which by default halts _process on every
	# node, including this one. Without PROCESS_MODE_ALWAYS, pausing the
	# game would silently cut off menu navigation for all four players the
	# moment the pause screen appears - the one time it's needed most.
	process_mode = Node.PROCESS_MODE_ALWAYS


# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(_delta: float) -> void:
	_forward_to_ui("ui_up", ["p1_up", "p2_up", "p3_up", "p4_up"])
	_forward_to_ui("ui_down", ["p1_down", "p2_down", "p3_down", "p4_down"])
	_forward_to_ui("ui_left", ["p1_left", "p2_left", "p3_left", "p4_left"])
	_forward_to_ui("ui_right", ["p1_right", "p2_right", "p3_right", "p4_right"])
	_forward_to_ui("ui_select", ["p1_pause_select", "p2_pause_select", "p3_pause_select", "p4_pause_select"])

## Mirrors any of `source_actions` being pressed/released onto `ui_action`,
## as a real InputEventAction pushed through Input.parse_input_event().
##
## Input.action_press()/action_release() (the old approach here) only update
## Input's own polling state - the engine docs are explicit that they will
## NOT trigger any _input call. Control's directional focus navigation and
## button activation run off that same _input/_gui_input event pipeline, not
## off polling, so action_press() was silently doing nothing for menu
## navigation. parse_input_event() with an InputEventAction is a genuine
## event, so it flows through the same pipeline a real key/button press would.
func _forward_to_ui(ui_action: String, source_actions: Array) -> void:
	for src in source_actions:
		if Input.is_action_just_pressed(src):
			_send_ui_event(ui_action, true)
		if Input.is_action_just_released(src):
			_send_ui_event(ui_action, false)

func _send_ui_event(action: String, pressed: bool) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = pressed
	Input.parse_input_event(ev)

func set_game_mode(mode: String) -> void:
	game_mode = mode
	emit_signal("settings_changed")
	print("mode change signal emitted")

func set_game_arena(arena: String) -> void:
	game_arena = arena
	emit_signal("settings_changed")
	print("arena change signal emitted")

func set_game_magic(on: String) -> void:
	game_magic = on
	emit_signal("settings_changed")
	print("magic change signal emitted")

func set_selected_class(seat: int, wizard_class: WizardClass, was_random: bool = false) -> void:
	if seat < 1 or seat > selected_classes.size():
		return
	selected_classes[seat - 1] = wizard_class
	was_random_pick[seat - 1] = was_random

func set_seat_active(seat: int, active: bool) -> void:
	if seat < 1 or seat > seat_active.size():
		return
	seat_active[seat - 1] = active

## Re-rolls a fresh random class for every active seat whose CURRENT class
## came from a "Random" pick (see was_random_pick above) - called by each
## arena's own _on_rematch_N_pressed() before it reloads the arena scene, so
## a seat that picked Random on character select keeps getting a new
## surprise every rematch instead of silently repeating whatever it happened
## to land on the first time. A seat that deliberately chose a real class is
## untouched either way - this only ever rerolls entries still flagged
## was_random_pick. Routes back through set_selected_class() itself (with
## was_random=true) so was_random_pick stays true afterward too - a
## rerolled seat is still a "Random" seat for whichever rematch comes next.
func reroll_random_seats() -> void:
	for i in range(was_random_pick.size()):
		if was_random_pick[i] and seat_active[i]:
			set_selected_class(i + 1, CLASSES[randi() % CLASSES.size()], true)

## Both "Start" buttons (Main Menu and the Mode/Settings menu) call this
## instead of switching scenes directly, so Character_Select.tscn's Back
## button always knows which one to return to.
func go_to_character_select(origin_scene: String) -> void:
	character_select_origin = origin_scene
	get_tree().change_scene_to_file("res://MENUS/Character_Select.tscn")


