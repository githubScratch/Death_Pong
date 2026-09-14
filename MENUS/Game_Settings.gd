extends Node

signal settings_changed # Signal to notify when any setting changes
# Variables to store selected game mode and map
var game_mode = "pure" # "pure", "random", "hot", or "training"
var game_arena = "arena" # "arena", "tower", "yonder", or "random"
var game_magic = "on" # "stock" or "time"

## Player-facing names for each game_mode/game_arena value above - keyed by
## the internal string values, used only to build the Lobby's non-interactive
## summary line (see summary_text() below). Button labels on the Options
## screen are separate, hand-set text on those Button nodes.
const MOD_DISPLAY_NAMES := {
	"pure": "Pure",
	"random": "Hydra",
	"hot": "Zones",
	"training": "Training",
}
const ARENA_DISPLAY_NAMES := {
	"arena": "Arena",
	"tower": "Tower",
	"yonder": "Yonder",
	"random": "Random",
}

## Every deliberately-pickable arena, keyed the same as game_arena/
## ARENA_DISPLAY_NAMES above - the pool next_arena_scene_path() below draws
## from whenever game_arena is "random" (Mode_Menu's Random map button).
const ARENA_SCENE_PATHS := {
	"arena": "res://ARENAS/arena.tscn",
	"tower": "res://ARENAS/tower.tscn",
	"yonder": "res://ARENAS/yonder.tscn",
}

## Resolves game_arena into the actual arena scene to load next. A
## deliberate map choice ("arena"/"tower"/"yonder") is just a lookup - but
## "random" rerolls a fresh pick among all three maps every single time this
## is called, not just once per session, so a Random pick means a genuinely
## new surprise on every trip through here. Both character_select.gd's
## _on_ready_pressed() (the very first match) AND every arena's own
## _on_rematch_N_pressed() (each rematch after that) call this rather than
## hardcoding their own scene, which is what makes Random apply to rematches
## too instead of just freezing on whatever map the first roll happened to
## land on.
func next_arena_scene_path() -> String:
	if game_arena == "random":
		var picks := ARENA_SCENE_PATHS.values()
		return picks[randi() % picks.size()]
	return ARENA_SCENE_PATHS.get(game_arena, ARENA_SCENE_PATHS["arena"])

## The Lobby's non-interactive summary line: "<mod> <map>" (e.g. "pure
## arena", "hydra tower"), or just "<mod>" alone while Training is the
## active mod, since a map choice is meaningless there. Always lowercase,
## regardless of the Title-Case names above - this is flavor text, not a
## button label.
func summary_text() -> String:
	var mod_word: String = MOD_DISPLAY_NAMES.get(game_mode, game_mode).to_lower()
	if game_mode == "training":
		return mod_word
	var map_word: String = ARENA_DISPLAY_NAMES.get(game_arena, game_arena).to_lower()
	return "%s" % [map_word]
	#return "%s %s" % [mod_word, map_word]

## The Options screen's "Reset Options" button - restores the map/mod
## choice to its default. Deliberately separate from Settings' own "Reset"
## (see settings_menu.gd's _on_reset_button_pressed(), which only ever
## touches display/volume/keybinds) so the two stay distinct, as requested.
func reset_game_options() -> void:
	game_mode = "pure"
	game_arena = "arena"
	emit_signal("settings_changed")

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
# the default false instead) and by set_was_random_pick() the instant a box
# lands on Random, before Ready is even pressed. Read by
# reroll_random_seats() so a rematch can roll every still-Random seat a
# FRESH surprise instead of silently repeating whatever it happened to land
# on last match, while a seat that deliberately chose a class keeps wearing
# it, rematch after rematch. Also read directly by character_select.gd's
# _ready() to decide what each box shows on a fresh visit - defaulted to
# true per the user's own explicit request that every seat start on Random
# rather than class_1/2/3/4 (selected_classes' own defaults just below are
# untouched, since they're still what a scene opened directly - skipping
# character select entirely - falls back to; this only changes what the
# character select SCREEN shows before anyone has touched a box).
var was_random_pick: Array = [true, true, true, true]

# Which menu sent the player to character select, so its Back button can
# return them to wherever they actually came from.
var character_select_origin: String = "res://MENUS/Menu.tscn"

# Which menu sent the player to Settings, so ITS Back button can return them
# to wherever they actually came from - Settings is reachable both directly
# from the Title screen's own "SETTINGS" button and from the Options screen's
# "Settings" button, same two-origins situation character_select_origin above
# already solves for the Lobby.
var settings_origin: String = "res://MENUS/Menu.tscn"

# Whether each seat joined on the character select screen - index 0..3 for
# seats 1..4. P1/P2 are always true (they're always active there); P3/P4
# start false and flip to true only once that seat's own controls are
# touched. Each arena's _spawn_selected_extras() reads seats 2/3 (P3/P4)
# from this at match start instead of waiting for an in-match summon press -
# see character_select.gd's _refresh_box() for where this gets written.
var seat_active: Array = [true, true, false, false]

# How many wizard seats the Lobby's bank shows/accepts joins for - 2 or 4,
# toggled there via the WIZARDS: button (see character_select.gd's
# _on_wizards_pressed()). Not consulted at all while game_mode is
# "training" (that mode always plays a single scene-baked seat regardless -
# see character_select.gd's _active_seat_count()), and persists across
# visits the same way selected_classes/seat_active above do, so reopening
# the Lobby doesn't reset the bank back to 2 for no reason.
var wizard_count: int = 2

# Which difficulty (if any) controls each seat - index 0..3 for seats 1..4,
# one of "none"/"easy"/"medium"/"hard". Replaced the old plain bot_active
# boolean array once Character Select's "Bots" button grew from a toggle
# into a 4-state difficulty cycle (None -> Apprentice -> Mage -> Archmage ->
# None - see character_select.gd's _on_bots_pressed()). Toggled today only
# for seat 2, but kept as a full 4-seat array anyway, matching every other
# per-seat array in this file, so extending bot support to more seats later
# is a UI change only, never a data-model change.
# Read by each arena's own _maybe_attach_bots() at match start (see arena.gd
# and bot_profile_path() below) to decide whether to attach a
# PLAYERS/bots/bot_controller.gd to that seat, and with which profile,
# instead of leaving it waiting on hardware input that will never come.
var bot_difficulty: Array = ["none", "none", "none", "none"]

# Per-seat identity color - index 0..3 for seats 1..4, same convention as
# every other per-seat array in this file. Currently only consumed by
# wizard.gd's _apply_class() to tint a wizard's outline sprite (see
# WizardClass.outline_sheet), so a player can tell their own wizard apart at
# a glance. Deliberately a plain array here rather than something keyed by
# team - there's no team concept yet - but color_for_seat() below is the
# only place that reads it, so swapping this out for a per-team lookup later
# (or having it fall back to a team's color when a seat has one) never
# touches wizard.gd at all, only this one function.
const SEAT_COLORS: Array[Color] = [
	Color(0.98, 0.25, 0.25), # P1 - red
	Color(0.25, 0.55, 0.98), # P2 - blue
	Color(0.35, 0.9, 0.35),  # P3 - green
	Color(0.95, 0.85, 0.2),  # P4 - yellow
]

# Returns seat's identity color (1-indexed, matching every other seat
# parameter in this file). Falls back to plain white - a no-op tint, same as
# not modulating at all - for anything out of range rather than erroring, so
# a stray/mistaken seat number just draws the outline at its natural color
# instead of crashing.
func color_for_seat(seat: int) -> Color:
	if seat < 1 or seat > SEAT_COLORS.size():
		return Color.WHITE
	return SEAT_COLORS[seat - 1]

# The two named teams (see arena.gd's victory text and character_select.gd's
# _update_team_labels()): "The Long Beards" over the first half of the seat
# bank, "The Floppy Hats" over the second half. Used to tint wizard.gd's
# outline shader (res://Shaders/Outlines.gdshader) per-team rather than
# per-seat.
const TEAM_COLOR_LONG_BEARDS: Color = Color(0.55, 0.25, 0.85) # purple
const TEAM_COLOR_FLOPPY_HATS: Color = Color(0.25, 0.85, 0.35) # green

# Returns which team's color a seat's outline should use, splitting the
# active wizard_count bank the same way _update_team_labels() does: first
# half is Long Beards, second half is Floppy Hats. wizard_count is always
# 2 or 4, so half is always >= 1 - a seat past that half falls on the
# Floppy Hats side. Training's single scene-baked seat (always seat 1)
# lands on Long Beards, same as P1 always does in a real match.
func team_color_for_seat(seat: int) -> Color:
	var half := maxi(wizard_count / 2, 1)
	return TEAM_COLOR_LONG_BEARDS if seat <= half else TEAM_COLOR_FLOPPY_HATS

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

## Persists "this seat is sitting on Random" the instant it's picked on
## Character_Select's box, rather than waiting for _resolve_random_picks()
## to actually roll one at Ready-press. Random has no WizardClass of its own
## to hand set_selected_class() (see character_select.gd's _refresh_box(),
## which deliberately skips that call for Random), so without this,
## was_random_pick[seat-1] kept whatever value it last had - true after an
## actual roll, false otherwise - and leaving Character_Select for another
## menu before ever pressing Ready silently reverted the box back to
## whatever concrete class was stored from before, instead of remembering
## Random as a standing preference like every other pick on that screen.
func set_was_random_pick(seat: int, was_random: bool) -> void:
	if seat < 1 or seat > was_random_pick.size():
		return
	was_random_pick[seat - 1] = was_random

func set_seat_active(seat: int, active: bool) -> void:
	if seat < 1 or seat > seat_active.size():
		return
	seat_active[seat - 1] = active

func set_wizard_count(count: int) -> void:
	wizard_count = count

func set_bot_difficulty(seat: int, difficulty: String) -> void:
	if seat < 1 or seat > bot_difficulty.size():
		return
	bot_difficulty[seat - 1] = difficulty

## True whenever seat's bot_difficulty entry is anything other than "none" -
## the replacement for the old plain bot_active[seat-1] boolean read, kept as
## a function (rather than a second array to stay in sync) so there is only
## ever one source of truth for whether a seat is bot-controlled.
func is_bot_active(seat: int) -> bool:
	if seat < 1 or seat > bot_difficulty.size():
		return false
	return bot_difficulty[seat - 1] != "none"

## Resource path for the BotController profile matching seat's current
## bot_difficulty, or "" for "none"/anything unrecognized. Centralizes the
## difficulty->profile mapping so arena.gd/tower.gd/yonder.gd's
## _maybe_attach_bots() don't each hardcode their own copy of it.
func bot_profile_path(seat: int) -> String:
	if seat < 1 or seat > bot_difficulty.size():
		return ""
	match bot_difficulty[seat - 1]:
		"easy":
			return "res://PLAYERS/bots/profiles/bot_profile_easy.tres"
		"medium":
			return "res://PLAYERS/bots/profiles/bot_profile_medium.tres"
		"hard":
			return "res://PLAYERS/bots/profiles/bot_profile_hard.tres"
		_:
			return ""

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

## Both "Settings" buttons (Title screen and the Options screen) call this
## instead of switching scenes directly, so Settings_Menu.tscn's Back button
## always knows which one to return to.
func go_to_settings(origin_scene: String) -> void:
	settings_origin = origin_scene
	get_tree().change_scene_to_file("res://MENUS/Settings_Menu.tscn")
