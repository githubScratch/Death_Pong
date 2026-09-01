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

func set_selected_class(seat: int, wizard_class: WizardClass) -> void:
	if seat < 1 or seat > selected_classes.size():
		return
	selected_classes[seat - 1] = wizard_class

func set_seat_active(seat: int, active: bool) -> void:
	if seat < 1 or seat > seat_active.size():
		return
	seat_active[seat - 1] = active

## Both "Start" buttons (Main Menu and the Mode/Settings menu) call this
## instead of switching scenes directly, so Character_Select.tscn's Back
## button always knows which one to return to.
func go_to_character_select(origin_scene: String) -> void:
	character_select_origin = origin_scene
	get_tree().change_scene_to_file("res://MENUS/Character_Select.tscn")


