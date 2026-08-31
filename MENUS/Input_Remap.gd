extends Node

# Autoload: owns keyboard/controller-button rebinding for p1-p4's
# up/down/left/right actions - defaults, persistence, and conflict rules.
#
# Rules enforced here (per the design agreed with the project owner):
#  - Space / Enter / Escape / Backspace can never be bound to a direction.
#  - A player can't bind the same physical input to two of their own directions.
#  - Two players can't share the same physical input - for keyboard that means
#    the same key; for a controller it means the same button on the SAME
#    physical device (two different pads pressing "A" is not a conflict).
#  - InputEventKey and InputEventJoypadButton are always accepted. A stick's
#    horizontal axis may also be bound to left/right (only) - see STICK_AXIS
#    and rebind_menu.gd. Vertical axis and triggers are still ignored.

const PLAYERS := [1, 2, 3, 4]
const DIRECTIONS := ["up", "down", "left", "right"]

const RESERVED_KEYCODES := [KEY_SPACE, KEY_ENTER, KEY_ESCAPE, KEY_BACKSPACE]
const RESERVED_JOY_BUTTONS := [JOY_BUTTON_START]

## Left/right only: which stick axis rebind_menu.gd listens for when capturing
## those two directions, and how far it has to be pushed to count as intent
## (separate from the action's own runtime deadzone, which stays at 0.2).
const STICK_AXIS := JOY_AXIS_LEFT_X
const STICK_CAPTURE_THRESHOLD := 0.5

const SAVE_PATH := "user://input_bindings.cfg"

# Physical keycode defaults, matching the project's original project.godot.
const DEFAULTS := {
	"p1_up": KEY_W, "p1_down": KEY_S, "p1_left": KEY_A, "p1_right": KEY_D,
	"p2_up": KEY_UP, "p2_down": KEY_DOWN, "p2_left": KEY_LEFT, "p2_right": KEY_RIGHT,
	"p3_up": KEY_J, "p3_down": KEY_M, "p3_left": KEY_N, "p3_right": KEY_COMMA,
	"p4_up": KEY_KP_8, "p4_down": KEY_KP_5, "p4_left": KEY_KP_4, "p4_right": KEY_KP_6,
}

func _ready() -> void:
	_load_bindings()

func action_for(player: int, dir: String) -> String:
	return "p%d_%s" % [player, dir]

## The first key/pad-button/stick event currently bound to this action, or null.
func get_display_event(action: String) -> InputEvent:
	for ev in InputMap.action_get_events(action):
		if ev is InputEventKey or ev is InputEventJoypadButton or ev is InputEventJoypadMotion:
			return ev
	return null

func describe_event(ev: InputEvent) -> String:
	if ev == null:
		return "—"
	if ev is InputEventKey:
		return OS.get_keycode_string(ev.physical_keycode)
	if ev is InputEventJoypadButton:
		return "Pad %d: %s" % [ev.device, _button_name(ev.button_index)]
	if ev is InputEventJoypadMotion:
		return "Pad %d: %s" % [ev.device, _stick_name(ev.axis_value)]
	return "?"

func _stick_name(axis_value: float) -> String:
	return "Stick Left" if axis_value < 0 else "Stick Right"

func _button_name(idx: int) -> String:
	match idx:
		JOY_BUTTON_A: return "A"
		JOY_BUTTON_B: return "B"
		JOY_BUTTON_X: return "X"
		JOY_BUTTON_Y: return "Y"
		JOY_BUTTON_LEFT_SHOULDER: return "LB"
		JOY_BUTTON_RIGHT_SHOULDER: return "RB"
		JOY_BUTTON_LEFT_STICK: return "L3"
		JOY_BUTTON_RIGHT_STICK: return "R3"
		JOY_BUTTON_START: return "Start"
		JOY_BUTTON_BACK: return "Back"
		JOY_BUTTON_DPAD_UP: return "D-Up"
		JOY_BUTTON_DPAD_DOWN: return "D-Down"
		JOY_BUTTON_DPAD_LEFT: return "D-Left"
		JOY_BUTTON_DPAD_RIGHT: return "D-Right"
		_: return "Btn %d" % idx

## Returns "" if candidate is allowed for player/dir, otherwise a short
## machine-readable reason ("reserved" / "used_by_self" / "used_by_other").
func validate_new_binding(player: int, dir: String, candidate: InputEvent) -> String:
	if candidate is InputEventKey and candidate.physical_keycode in RESERVED_KEYCODES:
		return "reserved"
	if candidate is InputEventJoypadButton and candidate.button_index in RESERVED_JOY_BUTTONS:
		return "reserved"
	if candidate is InputEventJoypadMotion and dir != "left" and dir != "right":
		return "reserved"

	for other_dir in DIRECTIONS:
		if other_dir == dir:
			continue
		if _same_input(candidate, get_display_event(action_for(player, other_dir))):
			return "used_by_self"

	for p in PLAYERS:
		if p == player:
			continue
		for other_dir in DIRECTIONS:
			if _same_input(candidate, get_display_event(action_for(p, other_dir))):
				return "used_by_other"

	return ""

func _same_input(a: InputEvent, b: InputEvent) -> bool:
	if a == null or b == null:
		return false
	if a is InputEventKey and b is InputEventKey:
		return a.physical_keycode == b.physical_keycode
	if a is InputEventJoypadButton and b is InputEventJoypadButton:
		return a.device == b.device and a.button_index == b.button_index
	if a is InputEventJoypadMotion and b is InputEventJoypadMotion:
		return a.device == b.device and a.axis == b.axis and sign(a.axis_value) == sign(b.axis_value)
	return false

func set_binding(action: String, ev: InputEvent) -> void:
	InputMap.action_erase_events(action)
	InputMap.action_add_event(action, ev)

func save_bindings() -> void:
	var cfg := ConfigFile.new()
	for p in PLAYERS:
		for dir in DIRECTIONS:
			var ev := get_display_event(action_for(p, dir))
			cfg.set_value("p%d" % p, dir, _serialize(ev))
	cfg.save(SAVE_PATH)

func _serialize(ev: InputEvent) -> Dictionary:
	if ev is InputEventKey:
		return {"type": "key", "code": ev.physical_keycode}
	if ev is InputEventJoypadButton:
		return {"type": "pad", "device": ev.device, "button": ev.button_index}
	if ev is InputEventJoypadMotion:
		return {"type": "motion", "device": ev.device, "axis": ev.axis, "sign": sign(ev.axis_value)}
	return {}

func _deserialize(data: Dictionary) -> InputEvent:
	if data.get("type") == "key":
		var ev := InputEventKey.new()
		ev.physical_keycode = data["code"]
		return ev
	if data.get("type") == "pad":
		var ev := InputEventJoypadButton.new()
		ev.device = data["device"]
		ev.button_index = data["button"]
		return ev
	if data.get("type") == "motion":
		var ev := InputEventJoypadMotion.new()
		ev.device = data["device"]
		ev.axis = data["axis"]
		ev.axis_value = float(data["sign"])
		return ev
	return null

func _load_bindings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return
	for p in PLAYERS:
		var section := "p%d" % p
		if not cfg.has_section(section):
			continue
		for dir in DIRECTIONS:
			if not cfg.has_section_key(section, dir):
				continue
			var ev := _deserialize(cfg.get_value(section, dir))
			if ev:
				set_binding(action_for(p, dir), ev)

## Every file this game itself writes under user:// - extend this list if
## more save data (e.g. persisted volume settings) gets added later.
const OWN_SAVE_FILES := [SAVE_PATH]

## "Clean slate" reset: deletes this game's own save data (currently just
## the keybind config) and reapplies the project's original keyboard
## defaults. Deliberately does NOT touch the rest of user:// - that folder
## is also where Godot keeps its own shader/pipeline cache for an exported
## build, and recursively wiping it out from under the running engine causes
## "_save_to_cache: Condition f.is_null() is true" errors when it tries to
## write a shader variant to a cache directory that no longer exists.
func reset_all_to_defaults() -> void:
	_delete_own_save_files()
	for p in PLAYERS:
		for dir in DIRECTIONS:
			var action := action_for(p, dir)
			var ev := InputEventKey.new()
			ev.physical_keycode = DEFAULTS[action]
			set_binding(action, ev)

func _delete_own_save_files() -> void:
	for path in OWN_SAVE_FILES:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(path)
