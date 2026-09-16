extends Control

## Character Select's own "Options" overlay - opened by character_select.gd's
## _on_options_pressed() (open()) in place of the old hop to a separate
## Mode_Menu.tscn scene, same "pop up in place" treatment Rebind_Menu.tscn
## already gave per-player key rebinding. Mode_Menu.tscn itself is untouched
## and still on disk - just unreached from here now - in case its Pure/
## Hydra/Zones/Training mod row and dedicated map-choice layout are ever
## wanted back; nothing else in the project still links to it.
##
## Every field here writes straight into GameSettings the moment it's
## cycled - there's no OK/Backspace commit-or-revert transaction the way
## Rebind_Menu.tscn's per-player key captures need. These are shared
## match-setup choices, not a personal keybind someone might fat-finger and
## want to back out of, and neither the old Mode_Menu nor Character Select's
## own former Wizards:/Bots: buttons ever had a revert path either - so
## "Ready" (and Backspace, purely as a convenience - see _input()) just
## closes the overlay. Nothing is staged to commit or discard.
##
## Vertical stack, top to bottom: Ready, Map, Magic, Wizards, Bot, Balls,
## Reset, Settings. Ready grabs default focus on open, and Up/Down wraps
## Ready<->Settings at both ends of the stack instead of dead-ending, per
## explicit request - see _wire_focus_wrap().
##
## Same "lock out the screen behind it" treatment as Rebind_Menu.tscn - see
## _set_background_focusable() (copied rather than shared, matching how
## rebind_menu.gd's own copy is the only other one - no shared base class
## for these overlays exists yet).
##
## Wizards/Bot here replace Character Select's old Wizards:/Bots: buttons
## outright (see that scene's own reduced Start/Options/Back button stack) -
## GameSettings.wizard_count/bot_difficulty are the same fields those
## buttons used to write, now emitting settings_changed on every change (see
## Game_Settings.gd) so character_select.gd's own _sync_from_overlay() can
## re-sync the seat boxes reactively instead of this file reaching into that
## screen's internals directly.

const ARENA_CYCLE := ["arena", "tower", "yonder", "random"]
const MAGIC_CYCLE := ["classes", "none"]
## Same difficulty cycle/labels character_select.gd's old _on_bots_pressed()
## used - seat 2 only, for now, same "start narrow, widen later" scope that
## function's own doc comment already called out.
const BOT_CYCLE := ["none", "easy", "medium", "hard"]
const BOT_DISPLAY_NAMES := {
	"none": "None",
	"easy": "Apprentice",
	"medium": "Wizard",
	"hard": "Archwizard",
}
## GameSettings.BALL_MODES is the source of truth for the cycle itself (just
## "clean" today) - this is only the display-name lookup, same shape every
## other cycle above already uses.
const BALL_DISPLAY_NAMES := {
	"clean": "Clean",
}

@onready var ready_button: Button = $CenterContainer/Panel/Margin/VBox/ReadyButton
@onready var map_button: Button = $CenterContainer/Panel/Margin/VBox/MapButton
@onready var magic_button: Button = $CenterContainer/Panel/Margin/VBox/MagicButton
@onready var wizards_button: Button = $CenterContainer/Panel/Margin/VBox/WizardsButton
@onready var bot_button: Button = $CenterContainer/Panel/Margin/VBox/BotButton
@onready var balls_button: Button = $CenterContainer/Panel/Margin/VBox/BallsButton
@onready var reset_button: Button = $CenterContainer/Panel/Margin/VBox/ResetButton
@onready var settings_button: Button = $CenterContainer/Panel/Margin/VBox/SettingsButton

var _return_focus_to: Control = null


func _ready() -> void:
	ready_button.pressed.connect(_on_ready_pressed)
	map_button.pressed.connect(_on_map_pressed)
	magic_button.pressed.connect(_on_magic_pressed)
	wizards_button.pressed.connect(_on_wizards_pressed)
	bot_button.pressed.connect(_on_bot_pressed)
	balls_button.pressed.connect(_on_balls_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	settings_button.pressed.connect(_on_settings_pressed)
	_wire_focus_wrap()
	visible = false


## Ready<->Settings wrap at both ends of the stack. Godot's own Control
## focus traversal just stops dead at either end of a container by default,
## so this has to be wired by hand rather than falling out of layout order.
func _wire_focus_wrap() -> void:
	ready_button.focus_neighbor_top = ready_button.get_path_to(settings_button)
	settings_button.focus_neighbor_bottom = settings_button.get_path_to(ready_button)


## Call this (from character_select.gd's _on_options_pressed()) to pop the
## overlay up.
func open() -> void:
	_return_focus_to = get_viewport().gui_get_focus_owner()
	_refresh_labels()
	_set_background_focusable(get_parent(), false)
	visible = true
	ready_button.grab_focus()


## Recursively disables (or restores) focus on every Control under `root`
## except this overlay and its own children, so keyboard/gamepad navigation
## can't wander onto the seat boxes or Start/Options/Back behind it -
## mouse_filter alone only blocks clicks/hover, not focus traversal. Same
## approach as rebind_menu.gd's own copy of this function.
func _set_background_focusable(root: Node, enabled: bool) -> void:
	for child in root.get_children():
		if child == self:
			continue
		if child is Control:
			if enabled:
				if child.has_meta(&"_options_prev_focus_mode"):
					child.focus_mode = child.get_meta(&"_options_prev_focus_mode")
					child.remove_meta(&"_options_prev_focus_mode")
			elif child.focus_mode != Control.FOCUS_NONE:
				child.set_meta(&"_options_prev_focus_mode", child.focus_mode)
				child.focus_mode = Control.FOCUS_NONE
		_set_background_focusable(child, enabled)


## Backspace closes the overlay same as pressing Ready - purely a
## convenience (ui_back already means "leave this screen" everywhere else in
## the project's menus) rather than a cancel, since nothing here is staged
## to revert - see this file's own top-of-file comment.
func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_BACKSPACE:
		get_viewport().set_input_as_handled()
		_close()


func _refresh_labels() -> void:
	map_button.text = "Map: %s" % GameSettings.ARENA_DISPLAY_NAMES.get(GameSettings.game_arena, GameSettings.game_arena)
	magic_button.text = "Magic: %s" % ("Classes" if GameSettings.game_magic == "classes" else "None")
	wizards_button.text = "Wizards: %d" % GameSettings.wizard_count
	bot_button.text = "Bot: %s" % BOT_DISPLAY_NAMES.get(GameSettings.bot_difficulty[1], "None")
	balls_button.text = "Balls: %s" % BALL_DISPLAY_NAMES.get(GameSettings.ball_mode, GameSettings.ball_mode)


func _on_map_pressed() -> void:
	var next: String = ARENA_CYCLE[(ARENA_CYCLE.find(GameSettings.game_arena) + 1) % ARENA_CYCLE.size()]
	GameSettings.set_game_arena(next)
	_refresh_labels()


func _on_magic_pressed() -> void:
	var next: String = MAGIC_CYCLE[(MAGIC_CYCLE.find(GameSettings.game_magic) + 1) % MAGIC_CYCLE.size()]
	GameSettings.set_game_magic(next)
	_refresh_labels()


## Same 2<->4 toggle Character Select's old Wizards: button used - the
## "cycle 1-4" phrasing in the original ask turned out to mean "pick a count
## in that range," not a literal 4-way cycle (an odd wizard count has no
## even split for the Long Beards/Floppy Hats team logic to fall back on -
## see Game_Settings.gd's team_color_for_seat()/character_select.gd's
## _update_team_labels()), so this stays exactly as it worked before, just
## relocated here.
func _on_wizards_pressed() -> void:
	GameSettings.set_wizard_count(4 if GameSettings.wizard_count == 2 else 2)
	_refresh_labels()


func _on_bot_pressed() -> void:
	var seat := 2
	var i := seat - 1
	var current_index := BOT_CYCLE.find(GameSettings.bot_difficulty[i])
	if current_index == -1:
		current_index = 0
	var next: String = BOT_CYCLE[(current_index + 1) % BOT_CYCLE.size()]
	GameSettings.set_bot_difficulty(seat, next)
	_refresh_labels()


func _on_balls_pressed() -> void:
	var cycle: Array = GameSettings.BALL_MODES
	var next: String = cycle[(cycle.find(GameSettings.ball_mode) + 1) % cycle.size()]
	GameSettings.set_ball_mode(next)
	_refresh_labels()


func _on_reset_pressed() -> void:
	GameSettings.reset_game_options()
	_refresh_labels()


func _on_settings_pressed() -> void:
	GameSettings.go_to_settings("res://MENUS/Character_Select.tscn")


func _on_ready_pressed() -> void:
	_close()


func _close() -> void:
	visible = false
	_set_background_focusable(get_parent(), true)
	if is_instance_valid(_return_focus_to):
		_return_focus_to.grab_focus()
	_return_focus_to = null
