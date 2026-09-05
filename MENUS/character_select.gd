extends Control

## Shown after "Start" from either the Main Menu or the Mode/Settings menu -
## both stash which one sent them here via GameSettings.go_to_character_select()
## before switching to this scene, so Back can return to the right place.
##
## Four boxes across the top, one per seat. P1/P2 are always active. P3/P4
## sit on a "press any button to join" prompt until that seat's own controls
## are touched, matching the same "any input" feel the in-match P3/P4 summon
## already uses - joining here doesn't force them to also join the match;
## it just means whichever class they land on here is what they'll be
## wearing *if* they get summoned later.
##
## Left/right cycles a seat's class using THAT SEAT'S OWN controls only
## (InputRemap.action_for(seat, "left"/"right")), never the shared ui_left/
## ui_right - those stay reserved for moving focus between Ready/Back like
## every other menu. Whatever a seat lands on is written live into
## GameSettings.selected_classes, which wizard.gd's _ready() prefers over
## an arena scene's baked-in default class - see that file for the other
## half of this wiring.

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

@onready var ready_button: Button = $Layout/Bottom/Buttons/Ready
@onready var back_button: Button = $Layout/Bottom/Buttons/Back
@onready var select_sfx: AudioStreamPlayer2D = $select
@onready var move_sfx: AudioStreamPlayer2D = $move

# All four of these are indexed 0..3 for seats 1..4.
var _active := [true, true, false, false]
var _class_index := [0, 1, 2, 3]
var _frame := [0, 0, 0, 0]
var _frame_time := [0.0, 0.0, 0.0, 0.0]


func _ready() -> void:
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
		if i < GameSettings.was_random_pick.size() and GameSettings.was_random_pick[i]:
			_class_index[i] = CLASSES.size()
			continue
		var stored: WizardClass = GameSettings.selected_classes[i] if i < GameSettings.selected_classes.size() else null
		if stored != null:
			var idx := CLASSES.find(stored)
			if idx != -1:
				_class_index[i] = idx

	ready_button.grab_focus()
	for i in range(4):
		_refresh_box(i)


func _process(delta: float) -> void:
	for i in range(4):
		var seat := i + 1
		if not _active[i]:
			if _seat_pressed_any_direction(seat):
				_active[i] = true
				_refresh_box(i)
				select_sfx.pitch_scale = randf_range(0.9, 1.1)
				select_sfx.play()
			continue

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


## Only the four directions count as "join" input, not pause_select -
## pause_select is also forwarded into the shared ui_select (see
## Game_Settings.gd), which would otherwise risk firing whatever's
## currently focused (Ready, by default) the same moment a P3/P4 player
## was just trying to join.
func _seat_pressed_any_direction(seat: int) -> bool:
	for dir in InputRemap.DIRECTIONS:
		if Input.is_action_just_pressed(InputRemap.action_for(seat, dir)):
			return true
	return false


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


## Redraws box i to match current state (active/waiting, whichever class
## is selected) and, for an active seat, writes that class into
## GameSettings so it's ready whenever the match needs it. Random is the one
## exception to that last part - see the comment below.
func _refresh_box(i: int) -> void:
	var seat := i + 1
	# _active is an untyped Array, so indexing it is a Variant as far as the
	# static type checker is concerned - := can't infer a type from that, so
	# this needs an explicit bool annotation instead.
	var waiting: bool = seat >= 3 and not _active[i]
	var random := _is_random(i)

	_prompts[i].visible = waiting
	_sprites[i].visible = not waiting and not random
	_random_marks[i].visible = not waiting and random
	_class_labels[i].visible = not waiting

	if not waiting:
		_name_labels[i].text = "PLAYER %d" % seat
		if random:
			# Deliberately does NOT call GameSettings.set_selected_class()
			# here - Random has no real WizardClass of its own to hand it,
			# and rolling one now (then re-rolling every time _refresh_box()
			# happens to run again, e.g. re-cycling past it) would leak the
			# result early and reroll it for no reason. _on_ready_pressed()
			# below does the actual roll, once, right before the match
			# starts, for every seat still sitting on Random at that point.
			_class_labels[i].text = "Random"
		else:
			var wclass := CLASSES[_class_index[i]]
			_class_labels[i].text = wclass.display_name
			_sprites[i].texture = _make_frame_texture(wclass.sprite_sheet, _frame[i])
			GameSettings.set_selected_class(seat, wclass)

	# Drives each arena's match-start P3/P4 spawn (see arena.gd's
	# _spawn_selected_extras()) - "not waiting" is exactly "this seat has
	# joined", so this also naturally resets a seat back to inactive if this
	# screen is ever reopened after Back without that seat re-joining.
	GameSettings.set_seat_active(seat, not waiting)


## Rolls an actual class for every joined seat still sitting on "Random" -
## GameSettings.selected_classes has no representation for "Random" itself
## (it's a WizardClass array - see Game_Settings.gd), so this is the one
## place that pick has to actually happen, right before the scene most needs
## it. Kept out of _refresh_box() entirely (see that function's comment) so
## the roll happens exactly once per seat, the moment Ready is pressed, not
## every time that seat's box happens to redraw.
func _resolve_random_picks() -> void:
	for i in range(4):
		if _active[i] and _is_random(i):
			# was_random=true so a later rematch (see arena.gd's
			# _on_rematch_N_pressed()/GameSettings.reroll_random_seats())
			# knows this seat's class was rolled, not chosen, and gives it a
			# fresh roll instead of just repeating this one.
			GameSettings.set_selected_class(i + 1, CLASSES[randi() % CLASSES.size()], true)


func _on_ready_pressed() -> void:
	_resolve_random_picks()
	match GameSettings.game_arena:
		"tower":
			get_tree().change_scene_to_file("res://ARENAS/tower.tscn")
		"yonder":
			get_tree().change_scene_to_file("res://ARENAS/yonder.tscn")
		_:
			get_tree().change_scene_to_file("res://ARENAS/arena.tscn")


func _on_back_pressed() -> void:
	get_tree().change_scene_to_file(GameSettings.character_select_origin)
