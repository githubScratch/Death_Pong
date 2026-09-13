extends Node2D
class_name BotController

## Phase 0 of the bot AI rollout (see the project's bot-implementation-roadmap
## doc in the claude.ai Project): proves the input-injection integration
## point works before any actual decision logic exists. A BotController is an
## alternate INPUT SOURCE for one seat, nothing else - it drives that seat's
## p{n}_up/down/left/right actions the exact same way a human's keyboard/pad
## would, via Input.action_press()/action_release(), so wizard.gd (which only
## ever polls Input.get_axis()/Input.is_action_just_pressed() on those same
## action names) needs zero changes to work with a bot seat. This also means
## Blink's max-tier clone - which mirrors a seat's input the same way - keeps
## working on a bot-controlled wizard for free.
##
## Phase 1: added a read-only PERCEPTION layer (own Wizard state, every ball,
## every other Wizard) refreshed every physics frame, plus a toggleable debug
## overlay (F1) that draws exactly what got perceived. Confirmed working,
## including correctly surfacing a Blink clone as an "other wizard."
##
## Phase 2: goal-side reactive positioning + ETA-gated, ground-level cast.
## Confirmed working by playtest - the bot walks to the goal side of the
## ball and casts a shield that clears it away from its own net.
##
## Phase 4: BotProfile (bot_profile.gd) now carries every tunable, including
## imperfection knobs (reaction_delay, placement_offset_error,
## decision_interval) that keep a bot from reading as unbeatable.
##
## Phase 5: ability usage. Whichever class this bot's Wizard is
## actually wearing determines which BotAbilityPolicy (see
## PLAYERS/bots/ability_policies/) gets resolved once in _ready() -
## BlinkPolicy, IcePolicy, MeteorPolicy, or GrowthPolicy - matching this
## project's own WizardAbility composition pattern rather than one shared
## script branching on class. Per the roadmap's explicit guidance, these are
## simple single-threshold triggers, not a scored utility comparison across
## all four abilities - see each policy's own should_use() for its trigger
## and BotController's own execution side:
##   - Blink/Ice: a quick double-tap gesture (_ability_gesture_step/
##     _advance_ability_gesture()) - confirmed from wizard.gd's own
##     _update_blink()/_update_ice_zone() that both trigger on the SECOND
##     tap's press edge alone, no sustained hold required despite how
##     "double-tap" sounds.
##   - Meteor: the same double-tap gesture, on Down instead of Left/Right -
##     confirmed from wizard.gd's _update_meteor() that despite the
##     "double-tap-and-HOLD" framing in class4_ability.gd's own doc comment,
##     the code only checks not is_on_floor() at the instant of the second
##     tap's press edge; nothing later requires Down to stay held.
##   - Growth: genuinely different - confirmed from wizard.gd's
##     _update_growth_channel() that it polls Input.is_action_pressed()
##     every frame and requires accumulated hold time past
##     GrowthAbility.hold_confirm_time before a channel even commits. See
##     _execute_growth()/_up_hold_seconds_remaining.
## All four policies already refuse to fire without enough banked strikes for
## at least one tier (see each policy's own should_use()) - "only use
## abilities the wizard can actually afford" was true from Phase 5 on, not
## new here.
##
## Phase 6 (current): tactical ground movement, reusing wizard.gd's own
## dash/dive/jump moves as deliberate repositioning tools instead of only
## ever walking at plain SPEED - see _maybe_dash(), _update_air_control(),
## and _scan_obstacle():
##   - Dash: Down while grounded gives wizard.gd's own SPEED = DASH burst
##     (see its _physics_process()) - triggered whenever the bot is
##     committed to covering more than profile.dash_trigger_distance in one
##     direction, on a cooldown so it doesn't spam every decision tick.
##   - Dive: Down while airborne sets velocity.y = DIVE_VELOCITY outright -
##     triggered once this bot's own jump has crested (velocity.y turns
##     positive) so it gets back to responsive ground movement sooner, then
##     naturally chains into a dash on landing if _update_movement() still
##     finds itself far from its target (no separate "chain" logic needed -
##     the very next decision tick's dash check already covers it).
##   - Pathing: _update_movement() raycasts ahead (matching this wizard's own
##     collision_mask, so it reacts to exactly what would physically stop it
##     - a moving platform's StaticBody2D, or a grown barrier's own collision
##     shape on its VFX) before walking into it. A short-enough obstacle gets
##     jumped (an ordinary Up press - same _cast_and_jump() a human's jump
##     triggers, recast and all); a too-tall one gets a temporary waypoint
##     just short of it instead, re-scanned every decision tick so a barrier
##     fading or a platform moving out of the way gets walked past on its own
##     rather than needing a real pathfinding graph over what's still just
##     two known obstacles in one arena.
##   - All three stand down for a Meteor-classed bot: Meteor's own double-tap
##     gesture already lives on this same Down action (see
##     _ability_direction_action()), and dash/dive would arm or trip that
##     gesture's timing window as an unintended side effect. Revisiting that
##     - and deliberately using a dive as Meteor's own aggressive
##     finisher-from-above, and Blink's wall-wrap slam as a repositioning
##     tool (see wizard.gd's _try_slam_wrap()/BlinkAbility.wrap_on_slam) - is
##     noted for later, not part of this phase.
##
## Phase 6 addendum (after first playtest): two gaps in how proactive the bot
## was, both closed without new files:
##   - Vertical engagement (_update_vertical_engagement()): the bot made no
##     effort at all to reach a ball sitting above it, despite wizard.gd
##     placing no limit on repeated air-jumps (_apply_jump_impulse() applies
##     DBL_JUMP_VELOCITY every time Up is pressed while airborne - no jump
##     counter anywhere). Now chains jumps toward it, straight up through a
##     one-way platform if that's what's in the way (never actually blocked -
##     the bot just wasn't trying).
##   - Close-range engagement (_update_cast_decision()'s close_range check):
##     a bot standing right next to the ball but not exactly on its own
##     goal-side stand point could pass neither the in-position nor the eta
##     gate and just stand there. A straight distance-based override now
##     fires the cast/jump regardless once the ball is close enough,
##     independent of the stand-point math.
##   - Also: the Hard profile's reaction_delay/placement_offset_error
##     "imperfection" knobs were zeroed out per the user's request, for now -
##     Hard is temporarily perfect-reflex/perfect-aim rather than
##     human-limited, while this playtesting round is still about mechanics,
##     not difficulty feel. Revisit before Hard ships as an actual difficulty
##     choice (Phase 8).
##
## Phase 6 addendum 2 (second playtest round): two more gaps closed, same
## two files:
##   - Unlimited dash (_maybe_dash()): profile.dash_cooldown dropped from an
##     artificial 0.5s to 0.1s (wizard.gd's own dash-burst duration) per the
##     user's explicit request that dashing shouldn't be rate-limited beyond
##     what the mechanic itself takes - it now re-triggers back-to-back for
##     as long as the distance still calls for it, the same "no artificial
##     limit" treatment vertical engagement's air-jumps already got (jumping
##     keeps its own, different pacing - see vertical_jump_interval's doc
##     comment - because every jump ALSO recasts the shield, a cost dashing
##     doesn't carry).
##   - Descend override (_update_movement()'s own descend block): a bot
##     standing directly over a ball on a lower platform/the ground got
##     stuck doing nothing forever - the ball being straight down put the
##     goal-side target X right where the wizard already stood, and a
##     one-way platform (see ARENAS/moving_platform.gd) only ever lets a
##     body pass through moving UP into it, never voluntarily drop down
##     through it while resting on top. Now, whenever grounded with the ball
##     more than profile.descend_engage_height below and nothing else
##     wanting to move, it walks toward its own goal side until it clears
##     the platform's edge and falls - not a real "find the nearest edge"
##     query, just enough to stop it idling on today's two-platform arena.
##
## Attach as a plain child anywhere under the seat's WizardSeat root (see
## wizard.tscn: root Node2D [WizardSeat] -> CharacterBody2D [Wizard] - this
## is added as a second child alongside it, not a replacement for either),
## with `seat` set to match that WizardSeat's own `seat` BEFORE this node
## enters the tree (both are read once, in _ready()).

## Which seat this bot drives (1-4) - matches whichever WizardSeat.seat it's
## attached under. Set by whoever instantiates this (see ARENAS/arena.gd's
## _maybe_attach_bots()) immediately after BotController.new(), before
## add_child() - _ready() below reads it once and never again.
@export var seat: int = 1

## Difficulty/personality knobs - see bot_profile.gd. Left unassigned here on
## purpose so a fresh BotController.new() (see arena.gd's _maybe_attach_bots())
## still works with sane (zero-imperfection) defaults; _ready() fills in a
## plain BotProfile.new() if this is still null once the node enters the
## tree. Assign one of PLAYERS/bots/profiles/*.tres explicitly (before
## add_child()) to pick a real difficulty instead of the perfect-play
## default.
@export var profile: BotProfile

## Draws this bot's perception AND its current decisions every frame when
## true - a green sanity square at this node's own origin, a yellow dot +
## line on its own Wizard/tracked ball, a red dot + cyan velocity line on the
## ball's TRUE current state, a white dot on the DELAYED ball state the
## decision layer is actually reacting to (see profile.reaction_delay - sits
## on top of the red dot when delay is 0), an orange vertical tick at the
## bot's current (possibly jittered) target stand X, a purple ring around
## the bot while an ability gesture/growth-hold is in flight, a short green/
## red line showing the last obstacle probe (see _scan_obstacle() - green if
## clear or jumpable, red if blocked and too tall), a blue tick at
## _move_target_x whenever a reroute has pinched it in short of the orange
## tick, and a magenta dot on every other Wizard it sees. Also toggleable at
## runtime with F1 (see _unhandled_input() below). Defaults on while this is
## still being tuned; flip off once it starts feeling like noise.
@export var debug_draw: bool = true

var _action_up: String
var _action_down: String
var _action_left: String
var _action_right: String

## True for exactly one physics frame after a cast decision presses Up, OR
## for as long as _up_hold_seconds_remaining counts down for a Growth hold -
## see _update_cast_decision()/_execute_growth(). Casting is normally a
## press-then-release PULSE (matching how a human tap registers), not a held
## button, since wizard.gd reads Up via Input.is_action_just_pressed(); a
## Growth channel is the one deliberate exception, which is why
## _up_hold_seconds_remaining exists alongside this instead of every Up
## press just being a flat 1-frame pulse.
var _up_press_pending: bool = false

## >0 means keep Up held THIS frame instead of releasing it after the usual
## one-frame pulse - see _execute_growth(). Counts down every physics frame
## regardless of decision cadence; once it reaches 0, the very next frame's
## normal pulse-release logic takes over and lets go of Up.
var _up_hold_seconds_remaining: float = 0.0

var _cast_cooldown_remaining: float = 0.0

## --- Tactical movement (Phase 6) ------------------------------------------

## True for exactly one physics frame after a dash/dive presses Down - same
## one-frame-pulse shape _up_press_pending gives Up, needed for the same
## reason: wizard.gd reads Down via Input.is_action_just_pressed(), and
## _physics_process()'s own end-of-frame Input.action_release(_action_down)
## (there to keep Down released outside a Meteor gesture) would otherwise
## clobber a same-frame press before wizard.gd ever sees the edge.
var _down_press_pending: bool = false

var _dash_cooldown_remaining: float = 0.0

## Seconds until this bot may chain another air-jump while climbing toward a
## ball above it - see _update_vertical_engagement()/profile.
## vertical_jump_interval. Independent of _dash_cooldown_remaining even
## though both gate a Down/Up "tool" press, since climbing and dashing can in
## principle both want to fire around the same time (e.g. right after
## landing from a climb, still far from the goal-side target X).
var _vertical_jump_cooldown_remaining: float = 0.0

## True from the physics frame an obstacle-clearing jump is requested (see
## _scan_obstacle()'s "jumpable" case in _update_movement()) until this
## wizard is back on the floor - _update_air_control() checks this so a dive
## never cuts that jump's arc short before it's actually carried this wizard
## past whatever it jumped over.
var _obstacle_jump_active: bool = false

## What _update_movement() is actually steering toward THIS decision tick -
## normally identical to _target_x, but pinched in short of a too-tall
## obstacle's near edge while one's in the way (see _scan_obstacle()'s
## "blocked, not jumpable" case). Ability policies/_ability_direction_action()
## deliberately keep reading _target_x instead of this - aiming shouldn't
## drift just because the body is mid-reroute. Kept as a field (not a local)
## purely so _draw() can show it.
var _move_target_x: float = 0.0

## This decision tick's obstacle scan result (see _scan_obstacle()) and which
## direction it was cast in - kept as fields purely for _draw() to visualize;
## nothing else reads them back.
var _last_obstacle_scan: Dictionary = {}
var _last_scan_dir_sign: float = 0.0

## Seconds until the next decision re-evaluation - see profile.decision_interval.
## Starts at 0 so the very first physics frame always makes a decision
## rather than waiting out a full interval with no input at all.
var _decision_timer: float = 0.0

## This decision tick's placement jitter (see profile.placement_offset_error)
## - rerolled once per decision tick in _update_movement(), not every
## physics frame, so it reads as "occasionally imprecise" rather than
## constant twitching. See bot_profile.gd's own note on pairing this with
## decision_interval sensibly.
var _current_aim_jitter: float = 0.0

## Which way this bot's own goal sits relative to the ball: +1.0 stands to
## the ball's RIGHT (higher X) as the goal side, -1.0 stands to its LEFT.
## Resolved once in _ready() from `seat` - see that assignment's own comment
## for why this is a placeholder tied to today's seat-2-only rollout rather
## than real team/side data.
var _goal_side_sign: float = -1.0

## This bot's current target stand X (including profile.placement_offset_error
## jitter), recomputed on every decision tick by _update_movement() - kept
## as a field (not a local) purely so _draw() and the ability policies (via
## BlinkPolicy/IcePolicy's own emergency_distance check) can read it without
## recomputing it.
var _target_x: float = 0.0

## This bot's own Wizard (CharacterBody2D, wizard.gd) - found once in
## _ready() by type rather than by node name, so a future rename of that
## child in wizard.tscn can't silently break this. Null only if this
## BotController somehow got attached somewhere with no Wizard sibling,
## which _ready() push_error()s about since that's a setup mistake, not a
## normal runtime state to quietly tolerate. _draw() below is written to
## degrade gracefully (falling back to this node's own origin) rather than
## just bailing out entirely if this is null, so a lookup failure shows up
## as "the yellow dot is at the wrong spot" instead of "no overlay at all."
var _own_wizard: Wizard = null

## --- Ability usage (Phase 5) ----------------------------------------------

## Whichever policy matches _own_wizard's equipped ability class, resolved
## once in _ready() (a wizard's class/ability doesn't change mid-match) - see
## _resolve_ability_policy(). Null if the equipped ability doesn't match any
## known policy (shouldn't happen with today's four classes, but a future
## 5th class with no policy yet should read as "this bot just never uses its
## ability" rather than erroring out).
var _ability_policy: BotAbilityPolicy = null

var _ability_cooldown_remaining: float = 0.0

## 0 = idle. 1-5 mid-sequence - see _advance_ability_gesture(). Shared by
## Blink/Ice/Meteor, whichever's currently using it; only one gesture is
## ever in flight at a time since a bot only ever has one equipped ability.
var _ability_gesture_step: int = 0

## Which action (_action_left/_action_right/_action_down) the current
## gesture is tapping - see _advance_ability_gesture()/_start_ability_gesture().
var _ability_gesture_action: String = ""

## --- Perception (Phase 1) ------------------------------------------------
## Everything below is refreshed once per physics frame by _update_perception()
## and is read-only from here on out - Phase 2/4/5's decision functions read
## these same fields instead of re-querying groups themselves.

## Every ball currently in the arena (usually 1, can be 2+ in Hydra/"random"
## mode - see ARENAS/arena.gd's ball_instances). Empty right after a goal,
## for the brief window before create_new_instance()'s 0.5s delay spawns the
## next ball - perception (and everything built on it later) has to tolerate
## that, not assume a ball always exists.
var perceived_balls: Array[Ball] = []

## Whichever ball in perceived_balls is currently closest to this bot's own
## Wizard - the natural "what am I reacting to" pick for a single-focus bot,
## even in multi-ball mode. Null when perceived_balls is empty. This is the
## TRUE current target - see _ball_history/_delayed_ball_state() for what
## the decision layer actually reacts to once profile.reaction_delay > 0.
var target_ball: Ball = null

## Every other Wizard in the arena (i.e. every CharacterBody2D in the
## "wizard" group except this bot's own _own_wizard) - human or bot-driven,
## and (confirmed in Phase 1 testing) a Blink clone counts too, since it's a
## real wizard.tscn instance with its own Wizard body. Nothing reads this
## yet - positioning/ability decisions only react to the ball - but it's
## already here for Phase 7 (two-bot coordination) and any future
## threat-assessment work.
var other_wizards: Array[Wizard] = []

## --- Reaction-delay history (Phase 4) -------------------------------------

## Rolling history of target_ball's (position, velocity) samples, newest
## last, one appended per physics frame - see _record_ball_history() and
## _delayed_ball_state(). Each entry is {position: Vector2, velocity:
## Vector2, age: float}; age counts up from 0.0 the frame it's recorded.
## Trimmed to entries no older than _MAX_HISTORY_AGE so this never grows
## unbounded even with a very large reaction_delay.
var _ball_history: Array = []

const _MAX_HISTORY_AGE: float = 1.0


func _ready() -> void:
	# Same "resolve once, cache the strings" shape wizard.gd's own _ready()
	# already uses for its four actions - InputRemap.action_for() is cheap,
	# but there's no reason to pay it every physics frame either.
	_action_up = InputRemap.action_for(seat, "up")
	_action_down = InputRemap.action_for(seat, "down")
	_action_left = InputRemap.action_for(seat, "left")
	_action_right = InputRemap.action_for(seat, "right")

	for child in get_parent().get_children():
		if child is Wizard:
			_own_wizard = child
			break
	if _own_wizard == null:
		push_error("BotController (seat %d): no Wizard sibling found under parent %s - attach this under a WizardSeat, not standalone." % [seat, get_parent()])

	# Opt-in-null-safe, same convention as e.g. ball.gd's ignite() with a
	# null overlay_scene: a BotController with no profile assigned still
	# works, just as a perfect/instant (zero-imperfection) bot rather than
	# erroring out.
	if profile == null:
		profile = BotProfile.new()

	# Placeholder scoped to today's seat-2-only rollout (character_select.gd's
	# "Bots" toggle and arena.gd's _maybe_attach_bots() both hardcode seat 2).
	# arena.gd wires Goal_Left to increment player2_score and Goal_Right to
	# increment player1_score - i.e. seat 1 defends the LEFT goal (lower X),
	# seat 2 defends the RIGHT goal (higher X). Once bots can attach to seat
	# 3/4, or team-based goal assignment matters (Phase 7/8 - see
	# Game_Settings.gd's team_color_for_seat() for how teams actually split),
	# this needs to read real team/side data instead of hardcoding seat == 2.
	_goal_side_sign = 1.0 if seat == 2 else -1.0

	_resolve_ability_policy()


## Picks the one BotAbilityPolicy subclass that matches _own_wizard's
## equipped ability class - a wizard's class (and therefore its ability) is
## fixed for the whole match once spawned, so this only ever needs to run
## once here, not re-checked every frame.
func _resolve_ability_policy() -> void:
	if _own_wizard == null:
		return
	var ability := _own_wizard._current_ability()
	if ability is BlinkAbility:
		_ability_policy = BlinkPolicy.new()
	elif ability is IceAbility:
		_ability_policy = IcePolicy.new()
	elif ability is MeteorAbility:
		_ability_policy = MeteorPolicy.new()
	elif ability is GrowthAbility:
		_ability_policy = GrowthPolicy.new()
	else:
		_ability_policy = null


func _physics_process(delta: float) -> void:
	_advance_ability_gesture()

	# Release last frame's one-frame Up press before anything else this
	# frame, UNLESS a Growth hold (_up_hold_seconds_remaining) is still
	# counting down - see _execute_growth()'s own doc comment for why Growth
	# is the one ability that needs Up held across many frames instead of a
	# single-frame pulse.
	if _up_press_pending:
		if _up_hold_seconds_remaining > 0.0:
			_up_hold_seconds_remaining = maxf(_up_hold_seconds_remaining - delta, 0.0)
		else:
			Input.action_release(_action_up)
			_up_press_pending = false

	# Same one-frame-pulse release as Up above, for a dash/dive's Down press
	# from last frame - see _down_press_pending's own doc comment.
	if _down_press_pending:
		Input.action_release(_action_down)
		_down_press_pending = false

	_update_perception()
	_record_ball_history(delta)

	_cast_cooldown_remaining = maxf(_cast_cooldown_remaining - delta, 0.0)
	_ability_cooldown_remaining = maxf(_ability_cooldown_remaining - delta, 0.0)
	_dash_cooldown_remaining = maxf(_dash_cooldown_remaining - delta, 0.0)
	_vertical_jump_cooldown_remaining = maxf(_vertical_jump_cooldown_remaining - delta, 0.0)

	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer += maxf(profile.decision_interval, 0.0)
		# Movement and a fresh cast both stand down entirely while a gesture
		# (Blink/Ice/Meteor's double-tap) or a Growth hold is in flight - see
		# _advance_ability_gesture()'s own doc comment for why sharing
		# left/right with continuous movement needs this, and
		# _execute_growth() for why Up is already spoken for during a hold.
		if _ability_gesture_step == 0:
			_update_movement()
		if _ability_gesture_step == 0 and not _up_press_pending:
			_update_cast_decision()
		if _ability_gesture_step == 0:
			_update_vertical_engagement()
		_update_ability_usage()

	# Dive isn't gated behind the decision timer - a bot mid-air only has a
	# brief window to act on it, and this is a mechanical "am I falling"
	# check, not a fresh read of the ball that needs profile.decision_interval
	# to pace out.
	_update_air_control()

	# Down stays released except while a Meteor gesture is actively using it
	# (see _advance_ability_gesture() - releasing it out from under a
	# same-frame press/release step would cancel that step outright) or a
	# dash/dive just pressed it this same frame (see _down_press_pending).
	if _ability_gesture_step == 0 and not _down_press_pending:
		Input.action_release(_action_down)

	if debug_draw:
		queue_redraw()


## Refreshes perceived_balls/target_ball/other_wizards from the scene tree.
## Pure read - never touches Input or any Wizard/Ball state. Cheap enough to
## run every physics frame at this project's scale (a handful of balls/
## wizards, never searched more than once per frame).
func _update_perception() -> void:
	perceived_balls.clear()
	for node in get_tree().get_nodes_in_group("ball"):
		if node is Ball:
			perceived_balls.append(node)

	target_ball = null
	if _own_wizard != null and not perceived_balls.is_empty():
		var best_dist := INF
		for ball in perceived_balls:
			var dist: float = _own_wizard.global_position.distance_squared_to(ball.global_position)
			if dist < best_dist:
				best_dist = dist
				target_ball = ball
	elif not perceived_balls.is_empty():
		# No resolved _own_wizard to measure distance from - still surface
		# a target so movement/cast (and the overlay) have something, rather
		# than silently going target-less just because the self-lookup
		# failed.
		target_ball = perceived_balls[0]

	other_wizards.clear()
	# "wizard" group has BOTH each WizardSeat root and its CharacterBody2D
	# child (see wizard.tscn) - filtering by `is Wizard` keeps only the
	# actual bodies, and excluding _own_wizard is what turns this into
	# "everyone ELSE."
	for node in get_tree().get_nodes_in_group("wizard"):
		if node is Wizard and node != _own_wizard:
			other_wizards.append(node)


## Appends this frame's target_ball sample (if any) to _ball_history and ages
## out anything older than _MAX_HISTORY_AGE. Deliberately does NOT append
## anything when target_ball is null (e.g. the brief window between a goal
## and the next ball spawning) - a stretch of missing samples there is fine,
## _delayed_ball_state() just falls back to whatever's oldest/available.
func _record_ball_history(delta: float) -> void:
	for entry in _ball_history:
		entry["age"] += delta
	while not _ball_history.is_empty() and _ball_history[0]["age"] > _MAX_HISTORY_AGE:
		_ball_history.pop_front()

	if target_ball != null:
		_ball_history.append({
			"position": target_ball.global_position,
			"velocity": target_ball.linear_velocity,
			"age": 0.0,
		})


## Returns the oldest history entry whose age is at least profile.
## reaction_delay - i.e. the freshest sample that's still "old enough" to
## count as delayed, quantized to the physics frame rate rather than
## interpolated (plenty precise for a reaction-time knob). Falls back to the
## single oldest entry available when history doesn't go back far enough yet
## (e.g. just after a bot attaches, or reaction_delay set unusually high),
## and to an empty Dictionary when there's no history at all. Callers must
## check target_ball != null first - an empty return with a non-null
## target_ball only happens in that brief just-attached window.
func _delayed_ball_state() -> Dictionary:
	if _ball_history.is_empty():
		return {}
	for entry in _ball_history:
		if entry["age"] >= profile.reaction_delay:
			return entry
	return _ball_history[0]


## Phase 2/4 movement: walk toward the goal-side stand X, computed from the
## DELAYED ball state (see _delayed_ball_state()) rather than target_ball's
## true current position - this is where profile.reaction_delay actually
## bites. Rerolls _current_aim_jitter once per call (i.e. once per decision
## tick - see profile.decision_interval) rather than every physics frame, so
## profile.placement_offset_error reads as occasional imprecision instead of
## constant twitching.
##
## Uses a plain deadzone-gated direction choice rather than porting
## paddle.gd's accelerate/clamp/friction curve literally: that curve exists
## to produce smooth ANALOG motion for a StaticBody2D paddle that sets its
## own position directly, but wizard.gd's horizontal movement is already a
## direct, instant axis-to-velocity mapping (Input.get_axis() * SPEED, no
## acceleration curve of its own) - there's no analog speed for a smoothing
## curve to modulate. The deadzone below achieves the same real goal (don't
## flicker direction from sub-pixel jitter) without simulating a velocity
## curve whose only observable output would be a binary press/don't-press.
func _update_movement() -> void:
	Input.action_release(_action_left)
	Input.action_release(_action_right)

	if _own_wizard == null or target_ball == null:
		return
	var ball_state := _delayed_ball_state()
	if ball_state.is_empty():
		return

	_current_aim_jitter = randf_range(-profile.placement_offset_error, profile.placement_offset_error)
	var ball_x: float = ball_state["position"].x
	_target_x = ball_x + _goal_side_sign * profile.goal_side_margin + _current_aim_jitter
	_move_target_x = _target_x

	var own_x: float = _own_wizard.global_position.x
	var diff := _move_target_x - own_x

	# Obstacle scan/reroute - grounded only (see _scan_obstacle()'s own doc
	# comment for why an airborne wizard doesn't need this: its arc is
	# already committed, and _update_air_control() is what manages getting
	# back down). Meteor stands down entirely - see this function's own
	# "Phase 6" doc comment on the class doc block up top for why.
	if _own_wizard.is_on_floor() and not (_own_wizard._current_ability() is MeteorAbility) \
			and absf(diff) > profile.position_tolerance:
		var dir_sign := signf(diff)
		var scan := _scan_obstacle(dir_sign)
		_last_obstacle_scan = scan
		_last_scan_dir_sign = dir_sign
		if scan.get("blocked", false):
			if scan.get("jumpable", false):
				_request_jump()
				_obstacle_jump_active = true
			else:
				# Too tall to clear - hold just short of it instead of
				# walking into it. Re-scanned fresh every decision tick, so
				# once the obstacle moves/fades out of the way this just
				# stops triggering on its own - no separate "waiting" state
				# to clear.
				var hit_x: float = scan.get("hit_x", own_x)
				_move_target_x = hit_x - dir_sign * profile.reroute_margin
				diff = _move_target_x - own_x
	else:
		_last_obstacle_scan = {}

	# Descend override - grounded, still inside the deadzone (i.e. nothing
	# above this point wants to move at all), and the ball sits meaningfully
	# below. Playtesting surfaced a bot stuck standing directly over a ball
	# on a lower platform/the ground forever: a one-way platform only ever
	# lets a body pass through moving UP into it (see
	# ARENAS/moving_platform.gd), never voluntarily drop down through it
	# while standing on top, so with the ball straight down the goal-side
	# target X sits right where the wizard already is - nothing about normal
	# steering was ever going to walk it off the edge. Biasing toward
	# _goal_side_sign (the same consistent direction _goal_side_sign already
	# gives every other decision here) gets it walking off SOME edge; once
	# airborne, _update_air_control()'s dive and the normal ball-chase logic
	# take it from there. Not a real "find the nearest edge" query - good
	# enough for today's two-platform arena, not a general solution.
	if _own_wizard.is_on_floor() and absf(diff) <= profile.position_tolerance:
		var ball_below: float = (ball_state["position"] as Vector2).y - _own_wizard.global_position.y
		if ball_below > profile.descend_engage_height:
			diff = _goal_side_sign * (profile.position_tolerance + 1.0)

	if diff > profile.position_tolerance:
		Input.action_press(_action_right)
	elif diff < -profile.position_tolerance:
		Input.action_press(_action_left)
	# else: inside the deadzone - hold position (both already released above).

	_maybe_dash(diff)


## Raycasts profile.obstacle_probe_distance pixels ahead of this wizard, in
## the given direction, matching this wizard's OWN collision_mask - so this
## reacts to exactly what would physically stop the wizard's own
## move_and_slide() from getting there, whether that's a moving platform's
## StaticBody2D (see ARENAS/moving_platform.gd) or a grown barrier's own
## collision shape on its VFX (confirmed against the base Arena map: neither
## is special-cased here by node type or group, only by "does this wizard's
## own collision_mask hit it"). A second, identical probe from
## profile.obstacle_clear_height pixels higher up decides whether a detected
## obstacle is short enough to jump - not a real jump-arc simulation, just a
## cheap stand-in for "is there clearance up and over."
## Returns {} shaped as {"blocked": bool, "jumpable": bool, "hit_x": float}
## (hit_x only present when blocked).
func _scan_obstacle(dir_sign: float) -> Dictionary:
	var result := {"blocked": false, "jumpable": false}
	if _own_wizard == null or dir_sign == 0.0:
		return result

	var space_state := _own_wizard.get_world_2d().direct_space_state
	var from := _own_wizard.global_position
	var to := from + Vector2(dir_sign * profile.obstacle_probe_distance, 0.0)
	var query := PhysicsRayQueryParameters2D.create(from, to)
	query.collision_mask = _own_wizard.collision_mask
	query.exclude = [_own_wizard.get_rid()]
	var hit := space_state.intersect_ray(query)
	if hit.is_empty():
		return result

	result["blocked"] = true
	result["hit_x"] = (hit["position"] as Vector2).x

	var high_from := from + Vector2(0.0, -profile.obstacle_clear_height)
	var high_to := high_from + Vector2(dir_sign * profile.obstacle_probe_distance, 0.0)
	var high_query := PhysicsRayQueryParameters2D.create(high_from, high_to)
	high_query.collision_mask = _own_wizard.collision_mask
	high_query.exclude = [_own_wizard.get_rid()]
	result["jumpable"] = space_state.intersect_ray(high_query).is_empty()
	return result


## Presses Up for one physics frame purely to jump - see this function's only
## caller (_update_movement()'s obstacle-clearing case). Deliberately shares
## the exact same _up_press_pending pulse _update_cast_decision() uses rather
## than a separate flag: wizard.gd's _cast_and_jump() fires on every Up press
## unconditionally (jump AND a shield recast together, regardless of why the
## press happened - see wizard.gd line ~563 and its own doc comment), so
## there's no such thing as "just the jump half" to ask for separately, and a
## human player jumping over something in this game recasts their shield the
## same way. No-op if Up is already pressed/pending this frame (e.g. a cast
## decision and an obstacle jump landing on the same decision tick) - one
## press already covers both.
func _request_jump() -> void:
	if _up_press_pending:
		return
	Input.action_press(_action_up)
	_up_press_pending = true


## Triggers wizard.gd's own ground dash (Down while on the floor -> SPEED =
## DASH for 0.1s, see wizard.gd's _physics_process()) whenever this bot is
## committed to covering more than profile.dash_trigger_distance in one
## direction. `diff` is whatever _update_movement() just finished steering
## toward - the real target normally, a reroute waypoint short of a too-tall
## obstacle, or the descend-override direction (dashing off a platform's
## edge closes that gap faster too) - dashing to close it faster is exactly
## as useful in every case. Re-triggers back-to-back, at profile.
## dash_cooldown's pace (matched to the dash's own 0.1s burst, not an
## artificial throttle - see that field's own doc comment), for as long as
## the distance still calls for it, per the user's explicit request for
## unlimited dash repetition rather than a human-style cooldown. Stands down
## for a Meteor-classed bot (Down is spoken for by its own double-tap
## gesture - see _ability_direction_action()), while any gesture is in
## flight, or off the floor entirely (wizard.gd's own dash only triggers
## when is_on_floor() is true - see its own condition).
func _maybe_dash(diff: float) -> void:
	if _dash_cooldown_remaining > 0.0 or _ability_gesture_step != 0:
		return
	if _own_wizard == null or not _own_wizard.is_on_floor():
		return
	if _own_wizard._current_ability() is MeteorAbility:
		return
	if absf(diff) <= profile.dash_trigger_distance:
		return
	_request_down_pulse()
	_dash_cooldown_remaining = profile.dash_cooldown


## One-frame Down press - see _down_press_pending's own doc comment for why
## this needs its own pending flag (mirroring _up_press_pending) rather than
## a bare Input.action_press(). Shared by _maybe_dash() (grounded) and
## _update_air_control()'s dive (airborne) - the two are mutually exclusive
## by construction (one requires is_on_floor(), the other requires not), so
## there's never a conflict over what a given pulse "means."
func _request_down_pulse() -> void:
	if _down_press_pending or _ability_gesture_step != 0:
		return
	Input.action_press(_action_down)
	_down_press_pending = true


## Dive: once this bot's own jump has crested (velocity.y turns positive -
## i.e. it's falling, not still rising into the jump it just took), pressing
## Down sets wizard.gd's velocity.y = DIVE_VELOCITY outright (see its
## _physics_process()), getting this wizard back to responsive ground
## movement - and eligible for _maybe_dash() again - sooner than waiting out
## the rest of a natural fall. Runs every physics frame rather than only on a
## decision tick (see its only caller), since a short hop leaves only a
## brief window to act on this. Stands down while _obstacle_jump_active is
## true so a jump this bot requested specifically to clear an obstacle
## always gets its full horizontal carry - see that field's own doc comment
## - and, same as the dash above, for a Meteor-classed bot or mid-gesture.
func _update_air_control() -> void:
	if _own_wizard == null:
		return
	if _own_wizard.is_on_floor():
		_obstacle_jump_active = false
		return
	if _obstacle_jump_active or _ability_gesture_step != 0:
		return
	if _own_wizard._current_ability() is MeteorAbility:
		return
	if _own_wizard.velocity.y <= 0.0:
		return
	_request_down_pulse()


## Climbs toward a ball sitting above this wizard by chaining wizard.gd's own
## unlimited air-jumps (see _apply_jump_impulse(): DBL_JUMP_VELOCITY applies
## every time Up is pressed while not is_on_floor(), with no jump-count limit
## anywhere) - added after playtesting showed the bot making zero effort to
## reach a ball on a platform above it, even though a human can just mash Up
## to get there, including straight up through a one-way platform (see
## ARENAS/moving_platform.gd's CollisionShape2D.one_way_collision - jumping
## INTO one from below was never blocked in the first place, this is purely
## about the bot choosing to try). Paced by profile.vertical_jump_interval
## rather than firing every physics frame - see that field's own doc comment
## for why (repeated Up presses each also recast the shield, same as any
## other jump). Runs whether grounded or airborne (the very first press to
## leave the ground is exactly the same call as every chained one after it),
## and is independent of _update_movement()'s horizontal walk - the two run
## the same decision tick, so the bot angles toward the ball diagonally
## rather than climbing straight up before moving at all.
func _update_vertical_engagement() -> void:
	if _own_wizard == null or target_ball == null:
		return
	if _vertical_jump_cooldown_remaining > 0.0:
		return
	var ball_state := _delayed_ball_state()
	if ball_state.is_empty():
		return

	var vertical_gap: float = _own_wizard.global_position.y - (ball_state["position"] as Vector2).y
	if vertical_gap < profile.vertical_engage_height:
		return

	_request_jump()
	_vertical_jump_cooldown_remaining = profile.vertical_jump_interval


## Phase 2/4 cast timing: commit to a cast (press Up) once in position and
## the DELAYED ball state's straight-line ETA falls inside
## profile.cast_eta_threshold. Ground-level only - always casts wherever
## this bot's own Wizard currently is, no jump/mid-air height-matching yet.
## That's intentionally deferred rather than built speculatively: the
## roadmap's own Phase 2 milestone is a bot that can rally against a SLOW
## ball, and DeflectionShield's collision radius (see deflection_shield.gd)
## has real tolerance for a ball that hasn't drifted far in height - so this
## proves out positioning and timing in isolation before height-matching
## adds its own moving parts on top. If testing shows shots being missed
## purely on height, that's the next increment, not a sign this was wrong to
## ship alone.
##
## Also fires on a close_range_engage_distance override regardless of the
## eta/in-position gate above - see that field's own doc comment on
## bot_profile.gd for why: `in_position` is measured against the goal-side
## STAND point, not the ball itself, so a bot standing right next to the
## ball but not exactly on that offset point could otherwise pass both
## checks and just stand there doing nothing, which is exactly what
## playtesting surfaced.
func _update_cast_decision() -> void:
	if _own_wizard == null or target_ball == null:
		return
	if _cast_cooldown_remaining > 0.0:
		return
	var ball_state := _delayed_ball_state()
	if ball_state.is_empty():
		return

	var to_ball: Vector2 = ball_state["position"] - _own_wizard.global_position
	var distance: float = to_ball.length()
	var speed: float = maxf((ball_state["velocity"] as Vector2).length(), profile.min_ball_speed_for_eta)
	var eta: float = distance / speed
	var in_position: bool = absf(_target_x - _own_wizard.global_position.x) <= profile.position_tolerance
	var close_range: bool = distance <= profile.close_range_engage_distance

	if (in_position and eta <= profile.cast_eta_threshold) or close_range:
		Input.action_press(_action_up)
		_up_press_pending = true
		_cast_cooldown_remaining = profile.cast_cooldown


## Phase 5 dispatch: asks _ability_policy (whichever one matches the equipped
## class - see _resolve_ability_policy()) whether to use the ability right
## now, and if so, hands off to the right execution path. Stands down
## entirely while a gesture/hold is already in flight or the shared ability
## cooldown hasn't elapsed - see _physics_process()'s own guards, mirrored
## here since _update_ability_usage() can in principle be called from
## contexts that skip those (defensive, not currently reachable any other
## way).
func _update_ability_usage() -> void:
	if _ability_policy == null or _own_wizard == null:
		return
	if _ability_gesture_step != 0 or _ability_cooldown_remaining > 0.0 or _up_hold_seconds_remaining > 0.0:
		return
	if not _ability_policy.should_use(self):
		return

	if _ability_policy is GrowthPolicy:
		_execute_growth(_ability_policy as GrowthPolicy)
		return

	var ability := _own_wizard._current_ability()
	var direction_action := _ability_direction_action(ability)
	if direction_action == "":
		return
	_start_ability_gesture(direction_action)
	_ability_cooldown_remaining = _ability_policy.cooldown


## Which action Blink/Ice/Meteor's double-tap gesture should target, given
## the ability actually equipped - see each policy's own doc comment for WHY
## that direction (toward the goal-side target for Blink, toward the ball
## for Ice, always Down for Meteor). Returns "" if the ability isn't one of
## these three, or if there's no ball to aim relative to yet for Blink/Ice.
func _ability_direction_action(ability: WizardAbility) -> String:
	if ability is MeteorAbility:
		return _action_down

	var ball_state := _delayed_ball_state()
	if ball_state.is_empty():
		return ""

	if ability is BlinkAbility:
		return _action_right if (_target_x - _own_wizard.global_position.x) > 0.0 else _action_left
	if ability is IceAbility:
		var ball_x: float = ball_state["position"].x
		return _action_right if (ball_x - _own_wizard.global_position.x) > 0.0 else _action_left

	return ""


## Growth's own execution path - see GrowthPolicy's doc comment for why this
## can't be the same quick double-tap gesture Blink/Ice/Meteor share.
## Pressing Up here both starts a normal cast+jump immediately (wizard.gd's
## _cast_and_jump() fires on every Up press regardless of class - see
## wizard.gd line ~563) AND, by holding past ability.hold_confirm_time,
## commits to actually growing that fresh barrier - see wizard.gd's
## _update_growth_channel(). Hold length aims for policy.tiers_to_grow tiers
## using the EQUIPPED ability's own real timing (hold_confirm_time,
## growth_duration_per_tier) rather than a guessed constant, so this tracks
## whatever that class's .tres is actually tuned to.
func _execute_growth(policy: GrowthPolicy) -> void:
	var ability := _own_wizard._current_ability() as GrowthAbility
	if ability == null:
		return

	Input.action_press(_action_up)
	_up_press_pending = true
	_up_hold_seconds_remaining = ability.hold_confirm_time + ability.growth_duration_per_tier * maxf(float(policy.tiers_to_grow), 1.0)
	_cast_cooldown_remaining = profile.cast_cooldown
	_ability_cooldown_remaining = policy.cooldown


## Starts a Blink/Ice/Meteor double-tap gesture on the given action - see
## _advance_ability_gesture() for the actual frame-by-frame execution.
func _start_ability_gesture(action_name: String) -> void:
	_ability_gesture_action = action_name
	_ability_gesture_step = 1


## Advances the in-flight gesture (if any) by exactly one step per physics
## frame - confirmed against wizard.gd's own _update_blink()/_update_ice_zone()/
## _update_meteor() that all three trigger purely on the SECOND tap's
## Input.is_action_just_pressed() edge, with no minimum hold afterward, so a
## clean five-frame press/release/press/release sequence (~0.08s at 60Hz,
## comfortably inside every double_tap_window in this project) is enough:
##   1. Release BOTH left and right first - not just the gesture's own
##      action - because continuous movement (_update_movement()) may
##      already be holding the OPPOSITE direction, or even this same
##      direction, from the last decision tick; starting clean guarantees
##      step 2 below actually produces a fresh just_pressed edge instead of
##      silently no-opping because the action already reads as pressed.
##   2. Press the gesture's action (tap 1).
##   3. Release it.
##   4. Press it again (tap 2 - this is the edge wizard.gd's ability code
##      actually reacts to).
##   5. Release it - gesture complete, step resets to 0 (idle) next frame.
## _update_movement()/_update_cast_decision() both stand down entirely for
## as long as _ability_gesture_step != 0 (see _physics_process()) rather
## than trying to interleave with this - five frames of paused
## positioning/casting is imperceptible and far simpler than arbitrating
## shared input actions mid-sequence.
func _advance_ability_gesture() -> void:
	if _ability_gesture_step == 0:
		return
	match _ability_gesture_step:
		1:
			Input.action_release(_action_left)
			Input.action_release(_action_right)
		2:
			Input.action_press(_ability_gesture_action)
		3:
			Input.action_release(_ability_gesture_action)
		4:
			Input.action_press(_ability_gesture_action)
		5:
			Input.action_release(_ability_gesture_action)
	_ability_gesture_step += 1
	if _ability_gesture_step > 5:
		_ability_gesture_step = 0
		_ability_gesture_action = ""


## Debug-only visualization of perception + the current decisions - draws
## nothing when debug_draw is off. Coordinates are converted world -> local
## with to_local() since _draw() always draws in this node's own local
## space, not the world's - this node sits wherever its WizardSeat parent
## placed it, not necessarily at (0,0) in world space.
func _draw() -> void:
	if not debug_draw:
		return

	# Always-drawn sanity marker at this node's own origin, independent of
	# everything below it - if this square isn't visible in-game at all,
	# _draw() itself isn't running, a different problem than anything else
	# in this function.
	draw_rect(Rect2(-4, -4, 8, 8), Color.GREEN)

	var own_local := Vector2.ZERO if _own_wizard == null else to_local(_own_wizard.global_position)
	draw_circle(own_local, 6.0, Color.YELLOW)

	# Ability activity indicator - a gesture in flight (Blink/Ice/Meteor) or
	# a Growth hold counting down, so a policy actually firing is visible in
	# real time instead of only inferable from the game effect a beat later.
	if _ability_gesture_step != 0 or _up_hold_seconds_remaining > 0.0:
		draw_arc(own_local, 14.0, 0.0, TAU, 24, Color.PURPLE, 3.0)

	if target_ball != null:
		var ball_local := to_local(target_ball.global_position)
		draw_line(own_local, ball_local, Color.YELLOW, 2.0)
		draw_circle(ball_local, 10.0, Color.RED)
		# Velocity vector, scaled down so it reads as a short direction
		# indicator rather than shooting off-screen at the ball's actual
		# (often very fast) speed.
		var vel_end := ball_local + target_ball.linear_velocity * 0.25
		draw_line(ball_local, vel_end, Color.CYAN, 3.0)

		# The DELAYED ball state the decision layer is actually reacting to
		# (see profile.reaction_delay) - sits exactly on top of the red dot
		# when reaction_delay is 0, visibly lags behind it otherwise.
		var delayed := _delayed_ball_state()
		if not delayed.is_empty():
			draw_circle(to_local(delayed["position"]), 5.0, Color.WHITE)

		# Current (possibly jittered) target stand X, drawn through the
		# ball's own Y so it reads as "where the bot is trying to stand
		# relative to the ball" rather than floating at an arbitrary height.
		var target_local := to_local(Vector2(_target_x, target_ball.global_position.y))
		draw_line(target_local + Vector2(0, -40), target_local + Vector2(0, 40), Color.ORANGE, 2.0)

	# Phase 6: obstacle probe result, drawn from this wizard's own position -
	# a short line in the direction just scanned, green if clear/jumpable,
	# red if blocked and too tall to jump. A separate blue tick marks
	# _move_target_x whenever a reroute has pinched it in short of _target_x.
	if not _last_obstacle_scan.is_empty() and _own_wizard != null:
		var probe_color: Color = Color.RED if not _last_obstacle_scan.get("jumpable", false) else Color.GREEN
		var probe_end := own_local + Vector2(_last_scan_dir_sign * profile.obstacle_probe_distance, 0.0)
		draw_line(own_local, probe_end, probe_color, 2.0)
		if absf(_move_target_x - _target_x) > 1.0:
			var reroute_local := to_local(Vector2(_move_target_x, _own_wizard.global_position.y))
			draw_line(reroute_local + Vector2(0, -30), reroute_local + Vector2(0, 30), Color.BLUE, 2.0)

	for other in other_wizards:
		draw_circle(to_local(other.global_position), 6.0, Color.MAGENTA)


## Runtime toggle for debug_draw - F1, checked directly on the physical
## keycode rather than through an InputMap action, since this is a dev-only
## overlay with no player-facing binding to route through InputRemap. Only
## one BotController exists at a time under the current seat-2-only rollout
## (see character_select.gd's "Bots" toggle), so there's no ambiguity about
## which bot's overlay this toggles; that assumption will need revisiting
## once Phase 7 (two-bot coordination) puts more than one bot on the field at
## once.
func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_F1:
		debug_draw = not debug_draw
		queue_redraw()
