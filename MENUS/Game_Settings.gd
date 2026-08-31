extends Node

signal settings_changed # Signal to notify when any setting changes
# Variables to store selected game mode and map
var game_mode = "pure" # "pure" or "random"
var game_arena = "arena" # "arena", "tower", or "yonder"
var game_magic = "on" # "stock" or "time"

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	pass # Replace with function body.


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
	
	
