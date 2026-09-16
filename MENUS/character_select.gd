extends Control

## Shown after "Start" from either the Main Menu or the Mode/Settings menu -
## both stash which one sent them here via GameSettings.go_to_character_select()
## before switching to this scene, so Back can return to the right place.
##
## Up to four boxes across the top, one per seat - but only as many as the
## Options overlay's Wizards field currently says (2 or 4 - see
## Options_Menu.tscn/options_menu.gd). Every seat in the bank is active the
## instant it's shown - there's no separate "press any button to join" step
## for P3/P4 anymore now that Wizards is what decides whether they're
## playing at all; joining here still doesn't force them to also join the
## match, though - it just means whichever class a seat lands on here is
## what it'll be wearing *if* it gets summoned later.
## GameSettings.wizard_count remembers the overlay's setting across visits,
## same as every other choice there.
##
## Left/right cycles a seat's class using THAT SEAT'S OWN controls only
## (InputRemap.action_for(seat, "left"/"right")), never the shared ui_left/
## ui_right - those stay reserved for moving focus between Start/Options/
## Back like every other menu. Whatever a seat lands on is written live into
## GameSettings.selected_classes, which wizard.gd's _ready() prefers over
## an arena scene's baked-in default class - see that file for the other
## half of this wiring.
##
## While GameSettings.game_mode is "training", only seat 1 gets a class
## choice here - seats 2-4 are hidden entirely and forced inactive (matching
## training.tscn's single scene-baked P1 plus its own separate P2/P3/P4 join
## mechanics - see ARENAS/training.gd). game_mode has no UI control that can
## actually set it to "training" any more (Options_Menu.tscn dropped the old
## Mode_Menu's Pure/Hydra/Zones/Training row entirely - see that file's own
## top-of-file comment), so this branch is dead in practice today, but left
## intact rather than ripped out in case Training returns to the UI later.
## _active_seat_count() below is the one number the training case and the
## Wizards count both collapse into, so the rest of this file only ever has
## to ask "is seat i in the bank".
##
## Options is now an in-place overlay (Options_Menu.tscn/options_menu.gd),
## same "pop up over this screen, lock out the background" treatment
## Rebind_Menu.tscn already gave per-player key rebinding - _on_options_pressed()
## opens it instead of switching scenes. That overlay owns Map/Magic/
## Wizards/Bot/Balls/Reset/Settings; this screen's own bottom row is down to
## just Start/Options/Back as a result (Wizards:/Bots: used to live here as
## their own buttons - see _sync_from_overlay() for how this screen now
## reacts to those fields changing on the overlay instead of owning them
## directly).
##
## A TeamRow sits where the old "WHO ART THOU?" title used to, naming
## whichever seats are on each half of the bank - "The Long Beard(s)" over
## P1 (plus P2 at a 4-seat bank) and "The Floppy Hat(s)" over the other
## half (see _update_team_labels()). The same two names carry over to
## whichever arena the match ends in - see arena.gd's own
## _update_victory_text() for that half of the wiring.

const CLASSES: Array[WizardClass] = [
	preload("res://PLAYERS/classes/class_1.tres"),
	preload("res://PLAYERS/classes/class_2.tres"),
	preload("res://PLAYERS/classes/class_3.tres"),
	preload("res://PLAYERS/classes/class_4.tres"),
]

## "Random" isn't a real WizardClass - it has no sprite_sheet/abilities of
## its own, it just means "roll one of CLASSES for me" - so it can't be a
## fifth entry IN the typed CLASSES array above. Instead _class_index simply
## ranges 0..CLASSES.size() (one past the last real class), and
## CLASSES.size() itself is treated as "Random" everywhere below - _cycle()
## wraps against CLASSES.size() + 1 options, and it naturally lands last in
## the rotation (right after class 4, wrapping back to class 1) without
## needing its own ordering rule.

## Matches the 6.0 fps "default" animation every class's SpriteFrames uses
## in-game (see wizard.gd's _build_sprite_frames) and the same 2x2 grid of
## 192x192 regions every class's sprite sheet is cut into.
const ANIMATION_SPEED := 6.0
const REGIONS := [
	Rect2(0, 0, 192, 192),
	Rect2(192, 0, 192, 192),
	Rect2(0, 192, 192, 192),
	Rect2(192, 192, 192, 192),
]

const OPTIONS_MENU_SCENE := preload("res://MENUS/Options_Menu.tscn")

@onready var _seat_containers: Array = [
	$Layout/TopRow/P1, $Layout/TopRow/P2, $Layout/TopRow/P3, $Layout/TopRow/P4,
]
@onready var _name_labels: Array = [
	$Layout/TopRow/P1/Box/NameLabel, $Layout/TopRow/P2/Box/NameLabel,
	$Layout/TopRow/P3/Box/NameLabel, $Layout/TopRow/P4/Box/NameLabel,
]
@onready var _sprites: Array = [
	$Layout/TopRow/P1/Box/Sprite, $Layout/TopRow/P2/Box/Sprite,
	$Layout/TopRow/P3/Box/Sprite, $Layout/TopRow/P4/Box/Sprite,
]
## Shown instead of _sprites when a seat has landed on "Random" - a plain
## "?" with a faint glow (see Character_Select.tscn) rather than any actual
## class's sprite, since Random isn't a real WizardClass to cut frames from.
@onready var _random_marks: Array = [
	$Layout/TopRow/P1/Box/RandomMark, $Layout/TopRow/P2/Box/RandomMark,
	$Layout/TopRow/P3/Box/RandomMark, $Layout/TopRow/P4/Box/RandomMark,
]
@onready var _class_labels: Array = [
	$Layout/TopRow/P1/Box/ClassLabel, $Layout/TopRow/P2/Box/ClassLabel,
	$Layout/TopRow/P3/Box/ClassLabel, $Layout/TopRow/P4/Box/ClassLabel,
]
@onready var _prompts: Array = [
	$Layout/TopRow/P1/Box/Prompt, $Layout/TopRow/P2/Box/Prompt,
	$Layout/TopRow/P3/Box/Prompt, $Layout/TopRow/P4/Box/Prompt,
]

## Replaces the old single "WHO ART THOU?" title - one team name per half
## of the seat bank (see _update_team_labels()). Each Label is half the
## TeamRow's width (same size_flags_horizontal=3 every seat box already
## uses), and TeamRow itself is exactly as wide as TopRow below it, so a
## 50/50 split always lines up with the right seats without any extra
## layout math: at a 2-seat bank that's P1 alone under Long Beard and P2
## alone under Floppy Hat, and at 4 it's P1+P2 under Long Beard and P3+P4
## under Floppy Hat - both cases are just "two equal halves" either way.
@onready var team_row: HBoxContainer = $Layout/TeamRow
@onready var long_beard_label: Label = $Layout/TeamRow/LongBeardLabel
@onready var floppy_hat_label: Label = $Layout/TeamRow/FloppyHatLabel
## Beneath the seat row - non-interactive readout of the currently chosen
## mod/map (see GameSettings.summary_text()), kept in sync with the Options
## overlay via GameSettings.settings_changed as well as refreshed on every
## visit here.
@onready var summary_label: Label = $Layout/Summary
@onready var ready_button: Button = $Layout/Bottom/Buttons/Ready
@onready var options_button: Button = $Layout/Bottom/Buttons/Options
@onready var back_button: Button = $Layout/Bottom/Buttons/Back
@onready var select_sfx: AudioStreamPlayer2D = $select
@onready var move_sfx: AudioStreamPlayer2D = $move

## Instantiated fresh each visit to this scene, same pattern
## settings_menu.gd already uses for Rebind_Menu.tscn - see
## _on_options_pressed()/open().
var options_menu: Control

# All four of these are indexed 0..3 for seats 1..4.
# _class_index defaults every seat to Random (CLASSES.size(), one past the
# last real class - see the CLASSES doc comment above) rather than
# class_1/2/3/4, matching GameSettings.was_random_pick's own new default
# (see that field's own doc comment) per the user's explicit request that
# every seat start on Random. _ready()'s restore loop below overwrites this
# for any seat already in the active bank on load, but a seat 3/4 revealed
# LATER by the Options overlay's Wizards field (_sync_from_overlay() calls
# _refresh_box() directly, not through that restore loop) still needs a
# sane starting value of its own - this is that value.
var _class_index := [CLASSES.size(), CLASSES.size(), CLASSES.size(), CLASSES.size()]
var _frame := [0, 0, 0, 0]
var _frame_time := [0.0, 0.0, 0.0, 0.0]


func _is_training() -> bool:
	return GameSettings.game_mode == "training"


## Maps a GameSettings.bot_difficulty value ("none"/"easy"/"medium"/"hard")
## to the in-fiction name shown in a bot seat's own box: Apprentice/Wizard/
## Archwizard for the three difficulties, None for no bot at all. Falls back
## to "None" for anything unrecognized rather than erroring, same spirit as
## color_for_seat()'s out-of-range fallback. options_menu.gd keeps its own
## copy of this same mapping for the overlay's Bot button label - simple
## enough not to bother sharing between the two files.
func _difficulty_display_name(difficulty: String) -> String:
	match difficulty:
		"easy":
			return "Apprentice"
		"medium":
			return "Wizard"
		"hard":
			return "Archwizard"
		_:
			return "None"


## Seat i's own display name for its box's name label - just the difficulty
## name (Apprentice/Wizard/Archwizard) for now, since only seat 2 can ever
## be a bot today and a bank-order "Bot 1"/"Bot 2" numbering would only ever
## show one value anyway. Only call this for a seat GameSettings.is_bot_active()
## already confirmed is bot-controlled.
func _bot_display_name(i: int) -> String:
	return _difficulty_display_name(GameSettings.bot_difficulty[i])


## The one number training's "just seat 1" rule and the Options overlay's
## Wizards field both collapse into - every loop below that used to check
## "training and i > 0" checks "i >= _active_seat_count()" instead, so
## neither case needs its own special-cased skip logic. Reads
## GameSettings.wizard_count directly rather than keeping a local mirror -
## the overlay is the only thing that ever changes it now, and
## GameSettings.settings_changed (see _sync_from_overlay()) is what tells
## this screen to redraw when it does.
func _active_seat_count() -> int:
	return 1 if _is_training() else GameSettings.wizard_count


## Pluralizes both team names to match the current bank size ("The Long
## Beard"/"The Floppy Hat" at 2, "...Beards"/"...Hats" at 4) - see the
## doc comment on long_beard_label above for why a plain 50/50 split is
## all that's needed to keep them lined up with the right seats. Team
## names are meaningless during training (a single scene-baked seat has
## no "team" to name), so the whole row hides there instead.
func _update_team_labels() -> void:
	var training := _is_training()
	team_row.visible = not training
	if training:
		return
	var plural := GameSettings.wizard_count == 4
	long_beard_label.text = "Long Beard%s" % ("s" if plural else "")
	floppy_hat_label.text = "Floppy Hat%s" % ("s" if plural else "")


func _ready() -> void:
	options_menu = OPTIONS_MENU_SCENE.instantiate()
	add_child(options_menu)

	var training := _is_training()
	_update_team_labels()

	# Show only as many seat boxes as are actually in the bank right now,
	# and force every seat outside it inactive so one that joined on an
	# earlier, larger-bank or non-training visit doesn't linger active and
	# get spawned into the match anyway.
	var active_seats := _active_seat_count()
	for i in range(4):
		_seat_containers[i].visible = i < active_seats
	for seat in range(active_seats + 1, 5):
		GameSettings.set_seat_active(seat, false)

	# Remember whatever was picked last time (a previous visit to this
	# screen, or just the game's defaults), so reopening this screen - via
	# Back-then-Start-again, quitting a match back to a menu and returning
	# here, or anything else that routes back through Character_Select.tscn -
	# doesn't reset everyone back to class 1/2/3/4 for no reason. A seat
	# whose last pick was "Random" (see GameSettings.was_random_pick, set by
	# _resolve_random_picks() below and cleared the moment a seat locks in a
	# real class instead - see _refresh_box()) is restored to Random itself,
	# not whatever concrete class it happened to roll last time - Random is
	# a standing preference this screen should keep honoring, not a one-time
	# roll that quietly turns into a fixed class the instant you leave.
	for i in range(4):
		if i >= active_seats:
			continue
		if i < GameSettings.was_random_pick.size() and GameSettings.was_random_pick[i]:
			_class_index[i] = CLASSES.size()
			continue
		var stored: WizardClass = GameSettings.selected_classes[i] if i < GameSettings.selected_classes.size() else null
		if stored != null:
			var idx := CLASSES.find(stored)
			if idx != -1:
				_class_index[i] = idx

	ready_button.grab_focus()
	_update_summary()
	GameSettings.settings_changed.connect(_sync_from_overlay)
	for i in range(4):
		if i >= active_seats:
			continue
		_refresh_box(i)


func _update_summary() -> void:
	summary_label.text = GameSettings.summary_text()


## Reacts to GameSettings.settings_changed - fired by every field the
## Options overlay can touch (Map/Magic/Wizards/Bot/Balls/Reset all route
## through GameSettings setters that emit it - see Game_Settings.gd). Folds
## together what used to be this screen's own _on_wizards_pressed()/
## _on_bots_pressed() bodies, since both buttons now live on the overlay
## instead of here: re-syncs the team labels, which seat boxes are visible,
## and each visible seat's own box (which also picks up a bot-difficulty
## rename via _refresh_box()'s call to _bot_display_name()) from whatever
## GameSettings currently holds. Deliberately does NOT touch _class_index/
## was_random_pick restoration - that's a _ready()-only "fresh visit to this
## scene" concern, not something a live settings change should ever redo out
## from under a seat mid-visit.
func _sync_from_overlay() -> void:
	_update_team_labels()
	var active_seats := _active_seat_count()
	for i in range(4):
		var now_visible := i < active_seats
		_seat_containers[i].visible = now_visible
		if now_visible:
			_refresh_box(i)
		else:
			# Dropped out of the bank - not in the match unless/until the
			# bank grows back to include this seat again.
			GameSettings.set_seat_active(i + 1, false)
	_update_summary()


func _process(delta: float) -> void:
	# The Options overlay locks out background FOCUS itself (see
	# options_menu.gd's _set_background_focusable()), but seat class-cycling
	# below reads raw per-seat input directly (Input.is_action_just_pressed()),
	# which doesn't go through Godot's focus system at all - so it has to be
	# gated here explicitly, same as settings_menu.gd's own
	# "not rebind_menu.visible" guard on its Back handling. This also covers
	# ui_down/up/select/back just below for the same reason.
	if options_menu.visible:
		return

	var active_seats := _active_seat_count()
	for i in range(4):
		if i >= active_seats:
			continue
		var seat := i + 1
		_advance_frame(i, delta)

		if Input.is_action_just_pressed(InputRemap.action_for(seat, "left")):
			_cycle(i, -1)
		elif Input.is_action_just_pressed(InputRemap.action_for(seat, "right")):
			_cycle(i, 1)

	# Ready/Back nav SFX - same pattern every other menu uses, except left/
	# right is deliberately left out here: it's owned by per-seat cycling
	# above, and this shared ui_left/ui_right still fires alongside it
	# (Game_Settings.gd forwards every seat's left/right into it
	# unconditionally), so including it here would double the SFX on every
	# single class-cycle press.
	if Input.is_action_just_pressed("ui_down") or Input.is_action_just_pressed("ui_up"):
		move_sfx.pitch_scale = randf_range(0.9, 1.1)
		move_sfx.play()
	if Input.is_action_just_pressed("ui_select"):
		select_sfx.pitch_scale = randf_range(0.9, 1.1)
		select_sfx.play()
	if Input.is_action_just_pressed("ui_back"):
		_on_back_pressed()


## Total selectable options - every real class, plus "Random" last. See the
## CLASSES doc comment above for why Random is a bare index rather than a
## fifth CLASSES entry.
func _option_count() -> int:
	return CLASSES.size() + 1


func _is_random(i: int) -> bool:
	return _class_index[i] >= CLASSES.size()


func _cycle(i: int, delta_index: int) -> void:
	var total := _option_count()
	_class_index[i] = (_class_index[i] + delta_index + total) % total
	_frame[i] = 0
	_frame_time[i] = 0.0
	_refresh_box(i)
	move_sfx.pitch_scale = randf_range(0.9, 1.1)
	move_sfx.play()


func _advance_frame(i: int, delta: float) -> void:
	# Random has no sprite_sheet to cut frames from - its "?" mark is a
	# static Label, not an animated AtlasTexture - so there's nothing here
	# to advance while it's selected.
	if _is_random(i):
		return
	_frame_time[i] += delta
	var frame_duration := 1.0 / ANIMATION_SPEED
	var changed := false
	while _frame_time[i] >= frame_duration:
		_frame_time[i] -= frame_duration
		_frame[i] = (_frame[i] + 1) % REGIONS.size()
		changed = true
	if changed:
		_sprites[i].texture = _make_frame_texture(CLASSES[_class_index[i]].sprite_sheet, _frame[i])


func _make_frame_texture(sheet: Texture2D, frame: int) -> AtlasTexture:
	var atlas := AtlasTexture.new()
	atlas.atlas = sheet
	atlas.region = REGIONS[frame]
	return atlas


## Redraws box i to match whichever class is currently selected, and writes
## that class into GameSettings so it's ready whenever the match needs it -
## every seat _active_seat_count() counts as "in the bank" is always shown
## and always active, so there's no waiting/joined split to draw here
## anymore (see the doc comment at the top of this file). Random is the one
## exception to the "writes into GameSettings" part - see the comment below.
func _refresh_box(i: int) -> void:
	var seat := i + 1
	var random := _is_random(i)

	_prompts[i].visible = false
	_sprites[i].visible = not random
	_random_marks[i].visible = random
	_class_labels[i].visible = true

	_name_labels[i].text = _bot_display_name(i) if GameSettings.is_bot_active(seat) else "Player %d" % seat
	if random:
		# Deliberately does NOT call GameSettings.set_selected_class()
		# here - Random has no real WizardClass of its own to hand it,
		# and rolling one now (then re-rolling every time _refresh_box()
		# happens to run again, e.g. re-cycling past it) would leak the
		# result early and reroll it for no reason. _on_ready_pressed()
		# below does the actual roll, once, right before the match
		# starts, for every seat still sitting on Random at that point.
		#
		# set_was_random_pick() IS still called, though - separately from
		# the "don't roll early" concern above, this box landing on Random
		# needs to be remembered as a standing preference right away, not
		# just once Ready is pressed. Without it, cycling to Random then
		# leaving for another menu (Options, etc.) before ever pressing
		# Ready left GameSettings.was_random_pick[i] at whatever it was
		# last set to, so _ready()'s restore logic above fell through to
		# whatever concrete class was stored from before instead of
		# showing Random again on return.
		GameSettings.set_was_random_pick(seat, true)
		_class_labels[i].text = "Random"
	else:
		var wclass := CLASSES[_class_index[i]]
		_class_labels[i].text = wclass.display_name
		_sprites[i].texture = _make_frame_texture(wclass.sprite_sheet, _frame[i])
		GameSettings.set_selected_class(seat, wclass)

	# Drives each arena's match-start P3/P4 spawn (see arena.gd's
	# _spawn_selected_extras()) - true here is exactly "this seat is in the
	# bank", so a seat the Wizards field drops back out of still gets
	# forced to false, by _sync_from_overlay()/_ready() rather than here.
	GameSettings.set_seat_active(seat, true)


## Rolls an actual class for every joined seat still sitting on "Random" -
## GameSettings.selected_classes has no representation for "Random" itself
## (it's a WizardClass array - see Game_Settings.gd), so this is the one
## place that pick has to actually happen, right before the scene most needs
## it. Kept out of _refresh_box() entirely (see that function's comment) so
## the roll happens exactly once per seat, the moment Ready is pressed, not
## every time that seat's box happens to redraw.
func _resolve_random_picks() -> void:
	for i in range(4):
		if i < _active_seat_count() and _is_random(i):
			# was_random=true so a later rematch (see arena.gd's
			# _on_rematch_N_pressed()/GameSettings.reroll_random_seats())
			# knows this seat's class was rolled, not chosen, and gives it a
			# fresh roll instead of just repeating this one.
			GameSettings.set_selected_class(i + 1, CLASSES[randi() % CLASSES.size()], true)


func _on_ready_pressed() -> void:
	_resolve_random_picks()
	if _is_training():
		get_tree().change_scene_to_file("res://ARENAS/training.tscn")
		return
	# Was a hardcoded match on GameSettings.game_arena with only "tower"/
	# "yonder" cases and an "_" wildcard defaulting to Arena - meaning
	# "random" (the Options overlay's Random map choice) always fell into
	# that wildcard and loaded Arena every time, never actually rolling
	# among all three maps despite next_arena_scene_path()'s own doc comment
	# claiming this function already called it. Every rematch handler
	# (arena.gd/tower.gd/yonder.gd's _on_rematch_N_pressed()) already calls
	# next_arena_scene_path() correctly - this just brings the very first
	# match in line with them, restoring "Random" as a real rotation
	# through Arena/Tower/Yonder instead of only ever landing on Arena.
	get_tree().change_scene_to_file(GameSettings.next_arena_scene_path())


func _on_options_pressed() -> void:
	options_menu.open()


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(GameSettings.character_select_origin)
