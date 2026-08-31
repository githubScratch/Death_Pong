extends Control

# Per-player keyboard/controller rebind screen. Opened by settings_menu.gd
# via open_for_player(n). Reads/writes InputMap live through the InputRemap
# autoload; only commits to disk on Confirm, and reverts to the state it
# had when opened if cancelled with Backspace.

const DIRECTIONS := ["up", "down", "left", "right"]

var player_index: int = 1
var _original_events: Dictionary = {}
var _capturing_direction: String = ""
var _flash_tween: Tween
var _return_focus_to: Control = null

@onready var title: Label = $CenterContainer/Panel/Margin/VBox/Title
@onready var dir_buttons: Dictionary = {
	"up": $CenterContainer/Panel/Margin/VBox/UpButton,
	"down": $CenterContainer/Panel/Margin/VBox/DownButton,
	"left": $CenterContainer/Panel/Margin/VBox/LeftButton,
	"right": $CenterContainer/Panel/Margin/VBox/RightButton,
}
@onready var confirm_button: Button = $CenterContainer/Panel/Margin/VBox/ConfirmButton

func _ready() -> void:
	for dir in DIRECTIONS:
		dir_buttons[dir].pressed.connect(_on_direction_pressed.bind(dir))
	confirm_button.pressed.connect(_on_confirm_pressed)
	visible = false

## Call this to open the screen for a given player (1-4).
func open_for_player(p: int) -> void:
	player_index = p
	title.text = "P%d CONTROLS" % p
	_return_focus_to = get_viewport().gui_get_focus_owner()
	_original_events.clear()
	for dir in DIRECTIONS:
		_original_events[dir] = InputMap.action_get_events(InputRemap.action_for(p, dir)).duplicate()
	_capturing_direction = ""
	_stop_flash()
	_refresh_labels()
	_set_background_focusable(get_parent(), false)
	visible = true
	dir_buttons["up"].grab_focus()

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
		dir_buttons[dir].text = "%s — %s" % [dir.to_upper(), InputRemap.describe_event(ev)]

func _on_direction_pressed(dir: String) -> void:
	if _capturing_direction != "":
		return
	_capturing_direction = dir
	dir_buttons[dir].text = "%s — ...?" % dir.to_upper()
	_start_flash(dir)

func _start_flash(dir: String) -> void:
	var btn: Button = dir_buttons[dir]
	if _flash_tween:
		_flash_tween.kill()
	_flash_tween = create_tween().set_loops()
	_flash_tween.tween_property(btn, "modulate:a", 0.25, 0.25)
	_flash_tween.tween_property(btn, "modulate:a", 1.0, 0.25)

func _stop_flash() -> void:
	if _flash_tween:
		_flash_tween.kill()
		_flash_tween = null
	for dir in DIRECTIONS:
		dir_buttons[dir].modulate.a = 1.0

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
	_capturing_direction = ""
	_refresh_labels()

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
	var btn: Button = dir_buttons[_capturing_direction]
	var t := create_tween()
	t.tween_property(btn, "modulate", Color(1, 0.35, 0.35), 0.08)
	t.tween_property(btn, "modulate", Color(1, 1, 1), 0.08)

func _on_confirm_pressed() -> void:
	if _capturing_direction != "":
		return
	InputRemap.save_bindings()
	_close()

func _cancel_and_close() -> void:
	if _capturing_direction != "":
		_stop_flash()
		_capturing_direction = ""
	for dir in DIRECTIONS:
		var action := InputRemap.action_for(player_index, dir)
		InputMap.action_erase_events(action)
		for ev in _original_events[dir]:
			InputMap.action_add_event(action, ev)
	_close()

func _close() -> void:
	visible = false
	_set_background_focusable(get_parent(), true)
	if is_instance_valid(_return_focus_to):
		_return_focus_to.grab_focus()
	_return_focus_to = null
