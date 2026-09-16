extends Control

# Per-player keyboard/controller rebind screen. Opened by settings_menu.gd
# via open_for_player(n). Reads/writes InputMap live through the InputRemap
# autoload; only commits to disk on OK, and reverts to the state it had when
# opened if cancelled with Backspace (this also discards a mid-flight Rebind
# Keys sequence or a Reset Keys press, same as any other unconfirmed change).
#
# Layout: a non-interactive D-pad diagram (one box for Up, a row below for
# Left/Down/Right - matching a physical arrow-key cluster) just displays the
# current bindings. "Rebind Keys" walks through all four directions in a
# fixed Up -> Down -> Left -> Right sequence, prompting for each in turn -
# plus one more for Magic afterward, whenever this player's bind-magic-mode
# actually uses it (see below); "Reset Keys" snaps this player's four
# direction bindings AND the magic key back to their defaults; "OK" saves
# and closes.
#
# "BindMagicButton" cycles this player's own bind_magic_mode (see
# Input_Remap.gd's own doc comment on that var for what each of "movement"/
# "button"/"both" actually changes in wizard.gd/bot_controller.gd) and
# relabels itself to match; MagicLabel (under DPad/ExtraRow, alongside the
# four literal direction boxes) shows the current magic key and is only
# visible outside "movement" mode, since that key isn't read by anything
# while movement alone still covers every ability.

const DIRECTIONS := ["up", "down", "left", "right"]

## Cycle order for BindMagicButton - see _on_bind_magic_pressed(). Matches
## InputRemap.bind_magic_mode's own three values exactly; MAGIC_MODE_LABELS
## below is this same order's button text.
const MAGIC_MODES := ["movement", "button", "both"]
const MAGIC_MODE_LABELS := {
	"movement": "BIND MAGIC TO: MOVEMENT",
	"button": "BIND MAGIC TO: BUTTON",
	"both": "BIND MAGIC TO: BOTH",
}

var player_index: int = 1
var _original_events: Dictionary = {}
var _original_magic_mode: String = "movement"
var _capturing_direction: String = ""
var _sequence_remaining: Array = []
var _flash_tween: Tween
var _return_focus_to: Control = null

@onready var title: Label = $CenterContainer/Panel/Margin/VBox/Title
@onready var dir_boxes: Dictionary = {
	"up": $CenterContainer/Panel/Margin/VBox/DPad/UpRow/HBoxContainer/UpBox,
	"down": $CenterContainer/Panel/Margin/VBox/DPad/BottomRow/DownBox,
	"left": $CenterContainer/Panel/Margin/VBox/DPad/BottomRow/LeftBox,
	"right": $CenterContainer/Panel/Margin/VBox/DPad/BottomRow/RightBox,
	# No arrow-key box of its own on the D-pad diagram - MagicLabel/BottomBox
	# below is used as this slot's flash target instead, so capturing it
	# reuses the exact same _start_flash()/_stop_flash()/_flash_rejection()
	# code every direction already goes through, no special-casing needed.
	"magic": $CenterContainer/Panel/Margin/VBox/DPad/UpRow/HBoxContainer/MagicBox,
}
@onready var dir_labels: Dictionary = {
	"up": $CenterContainer/Panel/Margin/VBox/DPad/UpRow/HBoxContainer/UpBox/UpLabel,
	"down": $CenterContainer/Panel/Margin/VBox/DPad/BottomRow/DownBox/DownLabel,
	"left": $CenterContainer/Panel/Margin/VBox/DPad/BottomRow/LeftBox/LeftLabel,
	"right": $CenterContainer/Panel/Margin/VBox/DPad/BottomRow/RightBox/RightLabel,
}
@onready var prompt_label: Label = $CenterContainer/Panel/Margin/VBox/PromptLabel
@onready var ok_button: Button = $CenterContainer/Panel/Margin/VBox/ButtonRow/VBox/OkButton
@onready var rebind_button: Button = $CenterContainer/Panel/Margin/VBox/ButtonRow/VBox/RebindButton
@onready var reset_button: Button = $CenterContainer/Panel/Margin/VBox/ButtonRow/VBox/ResetButton
@onready var bind_magic_button: Button = $CenterContainer/Panel/Margin/VBox/ButtonRow/VBox/BindMagicButton
@onready var magic_label: Label = $CenterContainer/Panel/Margin/VBox/DPad/UpRow/HBoxContainer/MagicBox/MagicLabel
@onready var magic_box: PanelContainer = $CenterContainer/Panel/Margin/VBox/DPad/UpRow/HBoxContainer/MagicBox


func _ready() -> void:
	ok_button.pressed.connect(_on_ok_pressed)
	rebind_button.pressed.connect(_on_rebind_pressed)
	reset_button.pressed.connect(_on_reset_pressed)
	bind_magic_button.pressed.connect(_on_bind_magic_pressed)
	visible = false

## Call this to open the screen for a given player (1-4).
func open_for_player(p: int) -> void:
	player_index = p
	title.text = "P%d CONTROLS" % p
	_return_focus_to = get_viewport().gui_get_focus_owner()
	_original_events.clear()
	for slot in InputRemap.ALL_SLOTS:
		_original_events[slot] = InputMap.action_get_events(InputRemap.action_for(p, slot)).duplicate()
	_original_magic_mode = InputRemap.magic_mode_for(p)
	_capturing_direction = ""
	_sequence_remaining.clear()
	_stop_flash()
	prompt_label.visible = false
	_refresh_labels()
	_refresh_magic_ui()
	_set_background_focusable(get_parent(), false)
	visible = true
	ok_button.grab_focus()

## Recursively disables (or restores) focus on every Control under `root`
## except this rebind screen and its own children, so keyboard/gamepad
## navigation can't wander onto whatever's behind the overlay - mouse_filter
## alone only blocks clicks/hover, not focus traversal.
func _set_background_focusable(root: Node, enabled: bool) -> void:
	for child in root.get_children():
		if child == self:
			continue
		if child is Control:
			if enabled:
				if child.has_meta(&"_rebind_prev_focus_mode"):
					child.focus_mode = child.get_meta(&"_rebind_prev_focus_mode")
					child.remove_meta(&"_rebind_prev_focus_mode")
			elif child.focus_mode != Control.FOCUS_NONE:
				child.set_meta(&"_rebind_prev_focus_mode", child.focus_mode)
				child.focus_mode = Control.FOCUS_NONE
		_set_background_focusable(child, enabled)

func _refresh_labels() -> void:
	for dir in DIRECTIONS:
		var ev := InputRemap.get_display_event(InputRemap.action_for(player_index, dir))
		dir_labels[dir].text = InputRemap.describe_event(ev)

## Updates BindMagicButton's own text to the current mode, and shows/hides +
## relabels MagicLabel to match - hidden entirely in "movement" mode (no
## dedicated magic key is relevant to show), otherwise showing this player's
## current magic key exactly like a fifth direction label would.
func _refresh_magic_ui() -> void:
	var mode: String = InputRemap.magic_mode_for(player_index)
	bind_magic_button.text = MAGIC_MODE_LABELS.get(mode, MAGIC_MODE_LABELS["movement"])
	magic_label.visible = mode != "movement"
	if magic_label.visible:
		var ev := InputRemap.get_display_event(InputRemap.action_for(player_index, "magic"))
		magic_label.text = "%s" % InputRemap.describe_event(ev)

## Cycles this player's bind-magic-mode movement -> button -> both ->
## movement, same as any other in-progress edit on this screen - live in
## InputRemap until OK (or Backspace) is pressed, see open_for_player()'s own
## snapshot and _cancel_and_close()'s restore.
func _on_bind_magic_pressed() -> void:
	if _capturing_direction != "":
		return
	var current: String = InputRemap.magic_mode_for(player_index)
	var next: String = MAGIC_MODES[(MAGIC_MODES.find(current) + 1) % MAGIC_MODES.size()]
	InputRemap.set_magic_mode(player_index, next)
	_refresh_magic_ui()

## Kicks off the full Up -> Down -> Left -> Right rebind sequence, plus a
## final Magic prompt whenever this player's current bind-magic-mode
## actually uses the dedicated magic button ("button" or "both") - skipped
## outright in "movement" mode, where that key is bound but never read by
## anything, so prompting for it would be pure noise.
func _on_rebind_pressed() -> void:
	if _capturing_direction != "":
		return
	_sequence_remaining = DIRECTIONS.duplicate()
	if InputRemap.magic_mode_for(player_index) != "movement":
		_sequence_remaining.append("magic")
	_begin_capture(_sequence_remaining.pop_front())

func _begin_capture(dir: String) -> void:
	_capturing_direction = dir
	prompt_label.text = "PRESS %s" % dir.to_upper()
	prompt_label.visible = true
	_start_flash(dir)

## Snaps this player's four directions AND magic key back to the project
## defaults - NOT the bind-magic-mode choice itself, which is a separate
## setting from "which key," untouched here. Like a rebind, this only lives
## in InputMap until OK (or Backspace) is pressed.
func _on_reset_pressed() -> void:
	if _capturing_direction != "":
		return
	InputRemap.reset_player_to_defaults(player_index)
	_refresh_labels()
	_refresh_magic_ui()

func _start_flash(dir: String) -> void:
	var box: Control = dir_boxes[dir]
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween().set_loops()
	_flash_tween.tween_property(box, "modulate:a", 0.25, 0.25)
	_flash_tween.tween_property(box, "modulate:a", 1.0, 0.25)

func _stop_flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
		_flash_tween = null
	for dir in dir_boxes:
		dir_boxes[dir].modulate.a = 1.0

func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Backspace always cancels the whole screen, mid-capture or not.
	if event is InputEventKey and event.pressed and not event.echo \
			and event.physical_keycode == KEY_BACKSPACE:
		get_viewport().set_input_as_handled()
		_cancel_and_close()
		return

	if _capturing_direction == "":
		return

	var candidate: InputEvent = null
	if event is InputEventKey and event.pressed and not event.echo:
		candidate = event
	elif event is InputEventJoypadButton and event.pressed:
		candidate = event
	elif event is InputEventJoypadMotion and event.axis == InputRemap.STICK_AXIS \
			and _capturing_direction == "left" \
			and event.axis_value <= -InputRemap.STICK_CAPTURE_THRESHOLD:
		candidate = _normalized_stick_event(event, -1.0)
	elif event is InputEventJoypadMotion and event.axis == InputRemap.STICK_AXIS \
			and _capturing_direction == "right" \
			and event.axis_value >= InputRemap.STICK_CAPTURE_THRESHOLD:
		candidate = _normalized_stick_event(event, 1.0)
	else:
		return  # ignore mouse, vertical/trigger axes, releases, etc.

	get_viewport().set_input_as_handled()

	var rejection := InputRemap.validate_new_binding(player_index, _capturing_direction, candidate)
	if rejection != "":
		_flash_rejection()
		return

	InputRemap.set_binding(InputRemap.action_for(player_index, _capturing_direction), candidate)
	_stop_flash()
	if _capturing_direction == "magic":
		_refresh_magic_ui()
	else:
		_refresh_labels()

	if _sequence_remaining.is_empty():
		_capturing_direction = ""
		prompt_label.visible = false
		ok_button.grab_focus()
	else:
		_begin_capture(_sequence_remaining.pop_front())

## Rebuilds the captured stick event with a clean +-1 axis_value instead of
## whatever exact magnitude triggered the capture, so the saved binding
## always reads the same way regardless of how hard the stick was pushed.
func _normalized_stick_event(source: InputEventJoypadMotion, target_sign: float) -> InputEventJoypadMotion:
	var motion := InputEventJoypadMotion.new()
	motion.device = source.device
	motion.axis = source.axis
	motion.axis_value = target_sign
	return motion

func _flash_rejection() -> void:
	var box: Control = dir_boxes[_capturing_direction]
	var t := create_tween()
	t.tween_property(box, "modulate", Color(1, 0.35, 0.35), 0.08)
	t.tween_property(box, "modulate", Color(1, 1, 1), 0.08)

func _on_ok_pressed() -> void:
	if _capturing_direction != "":
		return
	InputRemap.save_bindings()
	_close()

func _cancel_and_close() -> void:
	if _capturing_direction != "":
		_stop_flash()
		_capturing_direction = ""
	_sequence_remaining.clear()
	prompt_label.visible = false
	for slot in InputRemap.ALL_SLOTS:
		var action := InputRemap.action_for(player_index, slot)
		InputMap.action_erase_events(action)
		for ev in _original_events[slot]:
			InputMap.action_add_event(action, ev)
	InputRemap.set_magic_mode(player_index, _original_magic_mode)
	_close()

func _close() -> void:
	visible = false
	_set_background_focusable(get_parent(), true)
	if is_instance_valid(_return_focus_to):
		_return_focus_to.grab_focus()
	_return_focus_to = null
