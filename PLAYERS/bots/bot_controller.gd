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
## Phase 6 addendum 3 (third playtest round): a genuine behavior change plus
## a bugfix, per the user's own explicit design:
##   - Engagement role (_update_engagement_role(), new "Engagement Role"
##     export group on BotProfile): always chasing the ball everywhere,
##     including deep into the opponent's half during a long volley, left
##     this wizard's own goal empty for no reason if it was never going to
##     win the race there anyway. Now, when the ball is far
##     (profile.defensive_ball_range) AND the nearest other wizard is close
##     enough to it to be a real threat (profile.opponent_threat_distance)
##     AND a straight distance/Wizard.SPEED race says that wizard gets there
##     first, this bot falls back toward _home_x (its own spawn X - see that
##     field's own doc comment for why that beats a hardcoded arena
##     position) instead of sprinting/climbing after a ball it was going to
##     lose anyway. Close-range engagement and ability usage are
##     deliberately untouched by this - if the ball actually comes back
##     within reach, this wizard still reacts to it; "defensive" only means
##     not going out to get it.
##   - Ceiling-jump bug (_update_vertical_engagement()): a Meteor-classed
##     bot was seen jumping into the ceiling nonstop. Vertical engagement had
##     no sense of "there's nowhere left to climb" - a freshly spawned ball
##     (create_new_instance() drops it in high, at (576, 70)) reads as
##     "above" for a good while to most of the arena, so it kept re-firing a
##     chained jump every vertical_jump_interval even while already pressed
##     flat against the ceiling. Now checks CharacterBody2D's own
##     is_on_ceiling() first and simply stops asking until gravity brings it
##     back down - not Meteor-specific, but Meteor's own airborne-biased
##     playstyle (MeteorPolicy wants is_on_floor() == false to even consider
##     casting) made it the one most often caught against the ceiling in the
##     first place.
##
## Phase 6 addendum 4 (fourth playtest round): two more fixes, same two
## files:
##   - Engagement-role flicker (_role_lock_remaining, new profile.
##     engagement_role_min_hold): a bot was seen flickering left/right in
##     place with no net movement - the ETA race inside
##     _update_engagement_role() has no deadband, and with decision_interval
##     at 0 it re-runs every physics frame, so a ball wobbling by a pixel or
##     an opponent taking one step could flip which side reads as "faster"
##     from one frame to the next; since _defensive flipping swaps
##     _move_target_x between the ball-relative stand point and _home_x -
##     which can sit on opposite sides of this wizard - that flip showed up
##     as instant, repeated direction reversal. Now, once _defensive actually
##     changes, it's locked for engagement_role_min_hold seconds before the
##     function evaluates it again at all. Doesn't change the race logic,
##     just rate-limits how often its verdict can change.
##   - Stationary-ball standoff (_update_cast_decision()'s new
##     stationary_standoff check): a bot could land "in position" (within
##     position_tolerance of the goal-side stand point) without ever being
##     close/fast enough to satisfy either the eta gate or
##     close_range_engage_distance, and just park there forever against a
##     ball that wasn't moving to change that geometry on its own -
##     eta against a stationary ball is still computed off
##     min_ball_speed_for_eta's floor, not its real near-zero speed, so it
##     can sit above cast_eta_threshold indefinitely. Now also fires whenever
##     in_position AND the ball's real speed is at or below that same floor -
##     waiting for a "cleaner" angle against a ball that was never going to
##     move isn't meaningful. close_range_engage_distance was also raised
##     50.0 -> 70.0 to comfortably clear the worst-case in-position distance
##     (goal_side_margin + position_tolerance = 56px by default) for a slow
##     but not perfectly stationary ball too - see that field's own doc
##     comment on bot_profile.gd.
##
## Phase 6 addendum 5 (fifth playtest round): one bugfix, same file, no new
## files:
##   - Dive-cancels-itself bug (new _diving field, guards on
##     _update_cast_decision()/_update_vertical_engagement()): a bot diving
##     down onto a ball from above was bunny-hopping in place instead of
##     ever completing the strike. Root cause: wizard.gd's Up press always
##     both jumps AND recasts together (_cast_and_jump()), and
##     _apply_jump_impulse() overwrites velocity.y unconditionally - so once
##     a diving bot got "close enough" to trip _update_cast_decision()'s
##     close_range or stationary_standoff override (addendum 4), pressing Up
##     to cast canceled its own dive's fall speed. Falling back into range
##     just re-triggered the same cast, over and over - a self-inflicted
##     jump/cast loop that looked exactly like refusing to commit to the
##     drop. _diving now goes true the instant _update_air_control() starts
##     the fall-dive and stays true until landing; while true,
##     _update_cast_decision() (and, for the same reason, though not
##     actually seen overlapping in practice,
##     _update_vertical_engagement()) skip pressing Up entirely, letting the
##     dive carry all the way through uninterrupted.
##
## Phase 6 addendum 6 (sixth playtest round, from a recorded clip): the
## previous addendum's _diving guard didn't fix what it looked like it
## would - a screen recording showed a bot stuck bunny-hopping in place near
## its own goal corner, never actually descending toward a ball sitting well
## below and to the side, casting a shield on every hop for no benefit. Two
## separate fixes, per the user's own diagnosis and design:
##   - Obstacle-jump retry backoff (new _obstacle_jump_cooldown_remaining,
##     profile.obstacle_jump_retry_cooldown): the actual cause wasn't
##     vertical engagement (the ball read as BELOW this wizard the whole
##     clip, so that function correctly never fired) - it was the ordinary
##     grounded obstacle-clearing jump in _update_movement()/_scan_obstacle().
##     That scan's "is this jumpable" check is a cheap two-ray stand-in, not
##     a real jump-arc simulation (its own doc comment already admitted as
##     much), and this wizard's spawn corner is evidently a spot where it
##     reads as clearable but the actual jump never carries past it. With
##     nothing else changing between decision ticks, that meant the exact
##     same jump got re-requested every single tick, forever - and since
##     every jump also recasts (_cast_and_jump()), every failed hop burned a
##     shield along with it. Now, once an obstacle-clearing jump is
##     requested, another one in the same direction is refused for
##     obstacle_jump_retry_cooldown seconds, falling through to the ordinary
##     hold-short reroute instead of retrying instantly.
##   - Goal pressure (new _goal_pressure field, _update_goal_pressure(), new
##     "Engagement Role" fields goal_pressure_range/
##     goal_pressure_dash_trigger_distance): a second, separate behavior
##     change per the user's own explicit design - the deliberate mirror of
##     _update_engagement_role()'s defensive fallback. That function decides
##     when NOT to bother chasing a ball that's already lost; this one
##     decides when the ball is close enough to this wizard's own goal
##     (within goal_pressure_range of _home_x) that there's no decision to
##     make at all - playtesting showed the race-based fallback above could
##     send this wizard to _home_x while a ball closed in on net, sometimes
##     leaving it on the WRONG side of that same ball ("playing around on
##     the opposite side of the ball" per the user's own words). Goal
##     pressure forces _defensive false unconditionally (bypassing even
##     _role_lock_remaining - conceding a goal outweighs one extra flip) and
##     makes _maybe_dash() dash at the first real excuse
##     (goal_pressure_dash_trigger_distance, not the normal
##     dash_trigger_distance) rather than waiting for the usual distance
##     threshold, so this wizard races to get between the ball and its own
##     goal as fast as its mobility toolkit allows.
##
## Phase 6 addendum 7 (Meteor-specific bunny-hop, in
## PLAYERS/bots/ability_policies/meteor_policy.gd, plus one new field here):
## addendum 6 fixed non-Meteor bunny-hopping, but the user still saw it with
## a Meteor-classed bot equipped and correctly guessed it was tangled up
## with Meteor's own "use it whenever airborne" ability logic rather than
## repeating addendum 6's obstacle-jump cause (which stands down entirely
## for Meteor - see _update_movement()'s own Meteor exclusion). Root cause:
## MeteorPolicy.should_use() already gated on banked strikes, but its
## airborne check was a bare is_on_floor() == false, satisfied just as
## readily by the ankle-high hop an ordinary shield-cast
## (_update_cast_decision()'s close-range/stationary-standoff triggers) or
## obstacle-clearing jump produces as by a real jump - and with enough
## strikes banked and the ball not urgent, EVERY one of those frequent tiny
## hops was a fresh opportunity to start the 5-frame double-tap gesture,
## which suspends ordinary movement/casting for its duration (see
## _advance_ability_gesture()) for a hop that's often landing again before
## the gesture even finishes - visually identical to bunny-hopping, for no
## payoff. New field _last_grounded_y (this wizard's own Y as of its last
## grounded physics frame) lets MeteorPolicy tell a genuine jump/climb apart
## from that ankle-high case via its own new min_airborne_height export -
## see that policy's own doc comment for the full reasoning.
##
## Phase 6 addendum 8 (the actual "above the ball" fix): addenda 5-7 all
## treated this as a retry/interruption problem (a cooldown, a height
## check on Meteor's own ability trigger) without fixing the underlying
## decision - per the user's own explicit correction, a wizard above the
## ball should never jump AT ALL unless that jump lands a barrier within
## real striking range, and should otherwise actively WANT to get down to
## the ball as fast as possible, not passively wait for gravity. Two
## changes, same file:
##   - _above_ball_out_of_range() (new): true whenever the ball is
##     meaningfully below this wizard (profile.vertical_engage_height) AND
##     still farther away than profile.close_range_engage_distance would
##     actually matter for a cast. The bug this closes: _update_cast_
##     decision()'s in_position+eta gate never looked at vertical
##     separation at all - eta is straight-line distance/speed, which a
##     fast-moving ball satisfies easily regardless of how far above it
##     this wizard sits - so a wizard could keep re-triggering a
##     "legitimate-looking" cast+jump forever while never closing the
##     vertical gap, perpetually relaunching itself upward while staying
##     above a ball it was never actually touching. _update_cast_decision()
##     now refuses to press Up at all while this is true, and
##     _update_air_control() fires an immediate dive while it's true
##     (regardless of velocity.y - even mid-rise, not just once a jump
##     naturally crests), so getting down to striking range takes priority
##     over anything a stray cast/climb trigger would otherwise do.
##   - _meteor_ability_available() (new): _maybe_dash(), the obstacle-scan
##     in _update_movement(), and _update_air_control() all used to stand
##     down for "equipped with Meteor" outright, permanently reserving Down
##     for its gesture even when this wizard has nowhere near enough
##     strikes banked to actually use it - per the user's own explicit
##     request, a Meteor-classed bot without the strikes should dash,
##     obstacle-jump, and dive exactly like every other class instead of
##     just floating there with half its mobility toolkit switched off for
##     an ability it can't currently use. All three now check this instead
##     of a bare `is MeteorAbility`.
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
## runtime with F1 (see _unhandled_input() below). Defaulted on early while
## this was still being tuned; now off by default per the user's own request
## once regular playtesting no longer needed it visible at all times - press
## F1 in-game to bring it back whenever it's actually needed again.
@export var debug_draw: bool = false

var _action_up: String
var _action_down: String
var _action_left: String
var _action_right: String

## Cached like the four above - only ever meaningful when
## InputRemap.magic_mode_for(seat) is "button" or "both" (see
## _ability_direction_action()/_execute_growth()); resolved unconditionally
## in _ready() anyway since InputRemap.action_for() always returns SOME
## action regardless of mode, and a seat's mode can change later via the
## rebind menu without this node being re-created.
var _action_magic: String

## Set alongside _up_press_pending whenever _execute_growth() presses Up (or
## _action_magic, in "button" mode - see _execute_growth()) so the matching
## release in _physics_process() lets go of whichever action was actually
## pressed, not always _action_up. "" means the pending Up-equivalent press
## was a normal cast/jump on _action_up, not a Growth hold.
var _growth_hold_action: String = ""

## Set alongside _ability_gesture_action whenever a magic-button gesture
## (Blink/Ice fired via _action_magic in "button"/"both" mode) needs a brief
## direction-key tap first to set the wizard's facing before the real
## gesture fires - see _ability_facing_action()/_advance_ability_gesture().
## "" means no facing nudge is needed this gesture (movement-mode gestures
## already tap the real direction key, which sets facing as a side effect).
var _ability_gesture_facing_action: String = ""

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

## Seconds left before this bot may issue its NEXT brand-new discrete
## command - a jump request (_request_jump(), covering the shield-cast jump,
## the obstacle-clearing jump, and vertical engagement's chain-jump all
## alike) or a dash/dive pulse (_request_down_pulse()) - regardless of which
## kind fires next. Set to profile.min_command_interval every time either
## function actually presses a button, purely per the user's own explicit
## request to make this bot look less like a frame-perfect machine: with
## decision_interval able to be 0 (Hard's own default), nothing previously
## stopped e.g. a jump and a dash from firing on the exact same physics
## frame, which no human could ever actually do. Deliberately does NOT gate
## continuous left/right movement (holding a direction isn't "a command"),
## an ability gesture already under way, or a Growth hold already counting
## down - those have their own timing wizard.gd's own gesture window
## depends on, and an arbitrary added delay there risks missing the window
## entirely rather than just looking more human. See _request_jump()/
## _request_down_pulse() for where this is actually checked and set.
var _command_cooldown_remaining: float = 0.0

## Seconds left in the current ground dash's SPEED=DASH window (see
## wizard.gd's own Down-while-grounded dash) - set to profile.
## dash_burst_duration the instant _maybe_dash() actually fires a dash
## pulse, counted down every physics frame like every other cooldown here.
## While this is still > 0.0, _update_movement()'s obstacle-clearing jump
## and _update_vertical_engagement()'s chain-jump both stand down (see each
## one's own doc comment) - added per the user's own explicit report that a
## jump immediately after a dash cuts the dash's repositioning benefit
## short, since wizard.gd's dash only really carries this wizard anywhere
## while it stays grounded for the burst's whole duration. Independent of
## _dash_cooldown_remaining (that one paces how soon ANOTHER dash may fire;
## this one just protects an already-fired one from being interrupted) and
## of _obstacle_jump_active (that one protects an obstacle-jump's own arc
## from being cut short by a dive - the mirror-image concern, one direction
## protecting the other).
var _dash_active_remaining: float = 0.0

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

## Seconds until _update_movement() is allowed to request another
## obstacle-clearing jump - see that function's own "blocked, jumpable" case
## and profile.obstacle_jump_retry_cooldown's own doc comment for why this
## exists: _scan_obstacle()'s jump-arc check is a cheap stand-in, not a real
## simulation (its own doc comment already said so), and playtesting turned
## up exactly the failure mode that admits - a wizard perched somewhere the
## "jumpable" probe reads as clear but the real geometry doesn't actually
## let the jump land past it just re-requested the same jump every single
## decision tick forever, bunny-hopping in place (and, since every jump also
## recasts - see _request_jump()'s own doc comment - burning a shield cast
## every hop) instead of ever making progress. This doesn't make the scan
## itself smarter; it just stops a failed attempt from being retried
## instantly, so a genuinely-blocked path falls through to the ordinary
## hold-short reroute (which doesn't spam anything) instead of jump-spamming
## forever.
var _obstacle_jump_cooldown_remaining: float = 0.0

## True from the physics frame _update_air_control() actually triggers the
## fall-dive (the "already falling, get down faster" case, NOT the obstacle-
## clearing jump above) until this wizard is back on the floor - see that
## function's own doc comment for why this exists: wizard.gd's Up press
## always both jumps AND recasts (_cast_and_jump() - see
## _request_jump()'s own doc comment), and _apply_jump_impulse() applies
## DBL_JUMP_VELOCITY unconditionally, overwriting whatever velocity.y a dive
## already set. Without this, a bot diving down onto a ball from above could
## get "close enough" mid-fall to trip _update_cast_decision()'s close-range
## or stationary-standoff override, press Up to cast, and have that same
## press cancel its own dive - repeatedly, since falling back into range
## just re-triggers it - which is exactly the "bunny hop instead of slamming
## down" playtesting caught. See _update_cast_decision()/
## _update_vertical_engagement()'s own guards against this.
var _diving: bool = false

## This wizard's own global_position.y as of the last physics frame it was
## actually grounded (see _update_air_control(), where this is refreshed
## every frame it's true) - i.e. "how high off the ground am I right now"
## is _last_grounded_y - _own_wizard.global_position.y (positive once
## airborne, since Y increases downward). Added for MeteorPolicy.should_use()
## to tell a genuinely elevated jump apart from the ankle-high hop an
## ordinary shield-cast (_update_cast_decision()'s close-range/
## stationary-standoff triggers, or an obstacle-clearing jump) produces -
## see that policy's own min_airborne_height doc comment for why that
## distinction turned out to matter. Not reset on landing; the next grounded
## frame just overwrites it, so it's always "the last time both feet were on
## the floor," never stale by more than one frame while grounded.
var _last_grounded_y: float = 0.0

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

## --- Engagement role ---------------------------------------------------

## This wizard's OWN spawn X, captured once in _ready() before it ever
## moves - see _update_engagement_role(). Used as "home" to fall back to
## while playing defense, deliberately NOT a hardcoded arena position: since
## whoever placed this seat's WizardSeat already put it somewhere sane for
## that seat's side on THIS map, reusing that spot works on any arena
## without per-map tuning.
var _home_x: float = 0.0

## True while this bot has decided the ball isn't worth chasing right now -
## see _update_engagement_role(). Read by _update_movement() (steers toward
## _home_x instead of the ball-relative stand point) and
## _update_vertical_engagement() (skips climbing entirely - no point
## fighting for a ball this bot has already decided to give up on for the
## moment). Deliberately does NOT touch _update_cast_decision()'s
## close_range override or ability usage - if the ball actually comes back
## within reach, this wizard should still react to it, "defensive" just
## means not sprinting off to go get it.
var _defensive: bool = false

## Seconds left before _update_engagement_role() is allowed to change
## _defensive again - see profile.engagement_role_min_hold's own doc comment
## for why this exists (killing frame-by-frame flicker on a near-tied race).
## Set only when _defensive actually changes value, never just for having
## been evaluated - an unchanging verdict needs no cooldown.
var _role_lock_remaining: float = 0.0

## True whenever the ball is within profile.goal_pressure_range of this
## wizard's own goal side (see _update_goal_pressure()) - an urgent,
## unconditional override added per the user's own explicit design: a ball
## that's actually closing in on this wizard's own goal has to be met
## head-on, full stop, regardless of what the opponent-race in
## _update_engagement_role() would otherwise conclude. Read by that function
## (forces _defensive false, bypassing even _role_lock_remaining - conceding
## a goal is worse than one extra flip) and by _maybe_dash() (drops the
## normal dash_trigger_distance gate in favor of profile.
## goal_pressure_dash_trigger_distance, so closing the gap fast takes
## priority over saving dashes for a "real" distance).
var _goal_pressure: bool = false

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
	_action_magic = InputRemap.action_for(seat, "magic")

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

	# Captured here, before this wizard has ever moved, so "home" always
	# means wherever the scene actually placed this seat - see _home_x's
	# own doc comment for why that beats a hardcoded arena position. Same
	# reasoning for seeding _last_grounded_y here - a spawn point is always
	# on solid ground.
	if _own_wizard != null:
		_home_x = _own_wizard.global_position.x
		_last_grounded_y = _own_wizard.global_position.y

	_resolve_ability_policy()


## Releases every action this bot might currently be holding - guards
## against a real bug the user hit: disabling bots for the next match (or
## any other removal of this node - a rematch's scene reload, in practice)
## left the NEXT seat's wizard walking straight into a wall on its own, as
## if a key were stuck down, with no key actually held. Root cause:
## Input.action_press()/action_release() are GLOBAL, PERSISTENT engine
## state with nothing to do with any node's lifetime - _update_movement()
## presses e.g. _action_left every decision tick it wants to keep moving
## left, but if this node is freed (queue_free(), or the whole scene being
## torn down for a fresh match) before its own next _physics_process() ever
## gets a chance to release it, that press just stays latched forever.
## Godot doesn't reset it on a scene change either, since it's not part of
## the scene tree at all - a brand new wizard.gd in a freshly loaded scene
## reads Input.is_action_pressed(_action_left) as still true from a bot
## that no longer even exists, and walks into whatever wall is that
## direction exactly as if a human were holding the key down.
## _exit_tree() is guaranteed to run for every removal path at once
## (queue_free(), a parent being freed, a scene change discarding this
## whole tree) rather than needing every call site that might remove a bot
## to separately remember to clean up after it - covers all five actions
## this bot ever presses (movement, the ability-gesture direction, Growth's
## hold, and the magic button - see _update_movement()/
## _advance_ability_gesture()/_execute_growth()), regardless of which ones
## happen to be held at the moment of removal.
func _exit_tree() -> void:
	Input.action_release(_action_up)
	Input.action_release(_action_down)
	Input.action_release(_action_left)
	Input.action_release(_action_right)
	Input.action_release(_action_magic)


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
			Input.action_release(_growth_hold_action if _growth_hold_action != "" else _action_up)
			_growth_hold_action = ""
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
	_dash_active_remaining = maxf(_dash_active_remaining - delta, 0.0)
	_command_cooldown_remaining = maxf(_command_cooldown_remaining - delta, 0.0)
	_vertical_jump_cooldown_remaining = maxf(_vertical_jump_cooldown_remaining - delta, 0.0)
	_role_lock_remaining = maxf(_role_lock_remaining - delta, 0.0)
	_obstacle_jump_cooldown_remaining = maxf(_obstacle_jump_cooldown_remaining - delta, 0.0)

	_decision_timer -= delta
	if _decision_timer <= 0.0:
		_decision_timer += maxf(profile.decision_interval, 0.0)
		# Ahead of engagement role/movement since both read _goal_pressure -
		# see that field's own doc comment for why an urgent goal threat has
		# to be known before deciding whether to fall back or chase.
		_update_goal_pressure()
		# Ahead of movement since _update_movement() reads _defensive/_home_x
		# to decide what it's even steering toward this tick.
		_update_engagement_role()
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


## Returns the FRESHEST history entry whose age is at least profile.
## reaction_delay - i.e. the newest sample that's still "old enough" to
## count as delayed, quantized to the physics frame rate rather than
## interpolated (plenty precise for a reaction-time knob). Falls back to the
## single oldest entry available when history doesn't go back far enough yet
## (e.g. just after a bot attaches, or reaction_delay set unusually high),
## and to an empty Dictionary when there's no history at all. Callers must
## check target_ball != null first - an empty return with a non-null
## target_ball only happens in that brief just-attached window.
##
## Walks _ball_history NEWEST-to-OLDEST (backward - see that array's own doc
## comment for why index 0 is the oldest entry and the last index the
## newest) and returns the first one old enough. This direction matters:
## walking it forward (oldest-to-newest, as this used to) returns on the
## very FIRST entry checked - the single oldest sample in the whole buffer,
## up to _MAX_HISTORY_AGE (1 second) stale - for ANY reaction_delay small
## enough to be less than that oldest entry's age, which is effectively
## always. That silently broke reaction_delay as a knob entirely (Hard's own
## reaction_delay of 0.0 was reacting to ball positions up to a full second
## stale instead of the true, current one) and produced exactly the
## "flying off to a seemingly random spot after a weird delay" symptom the
## user reported from a recorded clip - most dramatically right after a
## Yonder teleport portal instantly relocated the ball, where "up to a
## second stale" could mean a completely different position on the map
## rather than a slightly-lagged nearby one.
func _delayed_ball_state() -> Dictionary:
	if _ball_history.is_empty():
		return {}
	for i in range(_ball_history.size() - 1, -1, -1):
		var entry = _ball_history[i]
		if entry["age"] >= profile.reaction_delay:
			return entry
	return _ball_history[0]


## Decides _goal_pressure for this decision tick - added per the user's own
## design, as the deliberate OPPOSITE case from _update_engagement_role()
## below: that function decides when NOT to bother chasing a ball that's far
## away and already lost; this one decides when the ball is close enough to
## this wizard's own goal that there's no decision to make at all - it has
## to be met, full stop, race-to-the-ball math or not. Playtesting showed a
## bot ending up on the wrong side of a ball closing in on its own net -
## "playing around on the opposite side of the ball" - which the
## opponent-race logic below can absolutely produce on its own: if that race
## says the opponent wins it, this wizard falls back toward _home_x even
## while the ball is bearing down on goal, and _home_x can easily end up on
## the FAR side of that same ball rather than between it and the net.
##
## Measures distance from the ball to _home_x rather than to this wizard's
## own current position - deliberately, since the whole point is "is the
## ball close to my GOAL," not "is the ball close to wherever I currently
## am" (those two only agree once this wizard is already home). _home_x is
## the same stand-in _update_engagement_role() already uses for "this
## wizard's own side of the field" (see that field's own doc comment for why
## a hardcoded arena position isn't used instead) - reused here rather than
## adding a second, separate notion of "where is my goal."
## profile.goal_pressure_range defaults to roughly a third of this project's
## current Arena (goal-to-goal is ~1064px), per the user's own estimate, but
## is a plain tunable, not derived from any actual arena dimension - revisit
## if a much larger/smaller arena ever makes 350px the wrong ballpark.
func _update_goal_pressure() -> void:
	_goal_pressure = false
	if _own_wizard == null or target_ball == null:
		return
	var ball_state := _delayed_ball_state()
	if ball_state.is_empty():
		return
	var ball_x: float = (ball_state["position"] as Vector2).x
	_goal_pressure = absf(ball_x - _home_x) <= profile.goal_pressure_range


## Decides _defensive for this decision tick - added per the user's own
## design: always chasing the ball, including deep into the opponent's half
## during a long volley, leaves this wizard's own goal empty for no reason
## if it was never going to win the race there anyway. Three gates, all per
## the user's own framing:
##   1. The ball has to be at least profile.defensive_ball_range away - a
##      nearby ball is always worth going for regardless of who else is
##      around.
##   2. The closest OTHER wizard (see other_wizards - today that's just
##      whoever's on the other end in this seat-2-only 1v1 rollout; revisit
##      once Phase 7 adds real teams) has to be within profile.
##      opponent_threat_distance of the ball - otherwise nobody's really
##      contesting it and this wizard just goes and gets it as usual.
##   3. Even then, only defers if the race itself says the opponent wins it:
##      each side's straight-line distance to the ball divided by its own
##      Wizard.SPEED (a Tier-0-style estimate, same "no trajectory
##      simulation" spirit as the rest of this bot - not accounting for
##      dashing, jumping, or the ball continuing to move). If this wizard's
##      own estimate is still faster despite the distance, it goes for it.
## profile.defensive_role_enabled is an escape hatch back to always-chase,
## mainly for testing without a second wizard on the field to race against.
##
## Rate-limited by _role_lock_remaining/profile.engagement_role_min_hold -
## added after playtesting caught a bot visibly flickering left/right in
## place with no net movement. The race in step 3 is a continuous
## comparison with no deadband, re-run every physics frame whenever
## decision_interval is 0 (Hard's own profile), so a ball wobbling by a
## single pixel or an opponent taking one step was enough to flip which
## side reads as "faster" from one frame to the next - and since
## _defensive flipping swaps _move_target_x between the ball-relative stand
## point and _home_x, which can sit on OPPOSITE sides of this wizard, that
## flip showed up as instant direction reversal, over and over. Once
## _defensive actually changes, this locks it in place for
## engagement_role_min_hold seconds before evaluating again at all -
## doesn't change the verdict itself, just how often it's allowed to change.
##
## _goal_pressure (see that field/_update_goal_pressure()'s own doc comment)
## overrides all of the above unconditionally, bypassing even the lock -
## conceding a goal is worse than one extra flip, so an urgent goal threat
## always wins the instant it's detected rather than waiting out whatever
## hold time a previous, less urgent verdict earned itself.
func _update_engagement_role() -> void:
	if _goal_pressure:
		_defensive = false
		return
	if _role_lock_remaining > 0.0:
		return

	var new_defensive := false
	if profile.defensive_role_enabled and _own_wizard != null and target_ball != null:
		var ball_state := _delayed_ball_state()
		if not ball_state.is_empty():
			var ball_pos: Vector2 = ball_state["position"]
			var own_distance: float = _own_wizard.global_position.distance_to(ball_pos)
			if own_distance > profile.defensive_ball_range:
				var nearest_opponent: Wizard = null
				var nearest_opponent_distance := INF
				for opponent in other_wizards:
					var d: float = opponent.global_position.distance_to(ball_pos)
					if d < nearest_opponent_distance:
						nearest_opponent_distance = d
						nearest_opponent = opponent
				if nearest_opponent != null and nearest_opponent_distance <= profile.opponent_threat_distance:
					var own_speed: float = maxf(_own_wizard.SPEED, 1.0)
					var opponent_speed: float = maxf(nearest_opponent.SPEED, 1.0)
					var own_eta: float = own_distance / own_speed
					var opponent_eta: float = nearest_opponent_distance / opponent_speed
					new_defensive = own_eta > opponent_eta

	if new_defensive != _defensive:
		_defensive = new_defensive
		_role_lock_remaining = profile.engagement_role_min_hold


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

	# Defensive override - see _update_engagement_role(). Deliberately only
	# swaps what _move_target_x steers toward; _target_x itself (read by the
	# ability policies and the orange debug tick) stays the true ball-
	# relative point the whole time, so aiming doesn't drift just because
	# the body has decided to hang back. Applied before the obstacle scan
	# below so pathing still works correctly on the way home, not just on
	# the way to the ball.
	#
	# _home_x is a fixed spawn-time X (see that field's own doc comment) -
	# it has no idea where the ball actually is right now, so nothing
	# guaranteed it stayed on this wizard's goal side of the ball. Per the
	# user's own explicit tactical rule - this wizard should never be
	# FORWARD of the ball (i.e. on the ball's far side, toward the
	# opponent's goal) - only accept _home_x as the retreat target when
	# it's actually still goal-side of (or exactly level with) the ball;
	# (_home_x - ball_x) * _goal_side_sign is >= 0 exactly when that's true,
	# the same sign check _target_x's own construction below relies on.
	# Otherwise fall all the way back to _target_x, the same goal-side
	# stand point normal (non-defensive) engagement already uses - it's
	# ALWAYS on the correct side of the ball by construction, so this never
	# leaves the wizard forward of it even when "go home" would have.
	if _defensive:
		if (_home_x - ball_x) * _goal_side_sign >= 0.0:
			_move_target_x = _home_x
		else:
			_move_target_x = _target_x

	var own_x: float = _own_wizard.global_position.x
	var diff := _move_target_x - own_x

	# Obstacle scan/reroute - grounded only (see _scan_obstacle()'s own doc
	# comment for why an airborne wizard doesn't need this: its arc is
	# already committed, and _update_air_control() is what manages getting
	# back down). Stands down while Meteor actually has the strikes to use
	# its own ability (see _meteor_ability_available()'s own doc comment for
	# why this is no longer a blanket "equipped with Meteor" check) - Down
	# is reserved for that gesture in that case only.
	if _own_wizard.is_on_floor() and not _meteor_ability_available() \
			and absf(diff) > profile.position_tolerance:
		var dir_sign := signf(diff)
		var scan := _scan_obstacle(dir_sign)
		_last_obstacle_scan = scan
		_last_scan_dir_sign = dir_sign
		if scan.get("blocked", false) and scan.get("jumpable", false) and _obstacle_jump_cooldown_remaining > 0.0:
			# See _obstacle_jump_cooldown_remaining's own doc comment - a
			# jump was already tried recently and evidently didn't clear
			# whatever this is (still grounded, still scanning the same
			# direction), so treat it as NOT jumpable for now and fall
			# through to the hold-short case below instead of retrying the
			# same failed jump again this tick.
			scan["jumpable"] = false
		if scan.get("blocked", false) and scan.get("jumpable", false) and _dash_active_remaining > 0.0:
			# See _dash_active_remaining's own doc comment - a dash was just
			# fired and still has some of its SPEED=DASH window left to
			# spend as actual grounded repositioning. Same "not jumpable for
			# now" treatment as the retry-cooldown case just above: hold
			# short of the obstacle for the brief remainder of the dash
			# instead of jumping out from under it immediately, then jump
			# normally on the very next tick once the window closes.
			scan["jumpable"] = false
		if scan.get("blocked", false):
			if scan.get("jumpable", false):
				_request_jump()
				_obstacle_jump_active = true
				_obstacle_jump_cooldown_remaining = profile.obstacle_jump_retry_cooldown
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

	_maybe_dash(diff, ball_x)


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


## Presses Up for one physics frame to jump - called from _update_movement()'s
## obstacle-clearing case and _update_vertical_engagement()'s chain-jump.
## Deliberately shares the exact same _up_press_pending pulse
## _update_cast_decision() uses rather than a separate flag: wizard.gd's
## _cast_and_jump() fires on every Up press unconditionally (jump AND a
## shield recast together, regardless of why the press happened - see
## wizard.gd line ~563 and its own doc comment), so there's no such thing as
## "just the jump half" to ask for separately, and a human player jumping
## over something in this game recasts their shield the same way. No-op if
## Up is already pressed/pending this frame (e.g. a cast decision and an
## obstacle jump landing on the same decision tick) - one press already
## covers both. Also no-op while _command_cooldown_remaining is still
## counting down - see that field's own doc comment for why (purely a
## "look less like a frame-perfect machine" knob, not a gameplay throttle).
func _request_jump() -> void:
	if _up_press_pending or _command_cooldown_remaining > 0.0:
		return
	Input.action_press(_action_up)
	_up_press_pending = true
	_command_cooldown_remaining = profile.min_command_interval


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
##
## Swaps in profile.goal_pressure_dash_trigger_distance instead of the
## normal dash_trigger_distance while _goal_pressure is true (see that
## field's own doc comment) - per the user's own explicit request that a
## ball closing in on this wizard's own goal should be raced down with
## dashes "as needed," not just once the gap happens to exceed the same
## threshold ordinary repositioning uses. Defaults to 0.0, i.e. dash the
## instant there's anywhere to go at all under pressure.
##
## Per the user's own explicit tactical rule: when this wizard is already
## goal-side of the ball (behind it, between it and its own goal - the
## normal, correctly-positioned case) and about to dash TOWARD the ball to
## close in and engage it, a dash covering roughly profile.
## dash_travel_distance pixels can easily overshoot clean through the
## ball's own position rather than stopping near it, landing this wizard
## forward of the ball - exactly the state addendum 9's defensive-fallback
## fix (see _update_movement()) already treats as tactically forbidden.
## Worse, the very next decision tick would then want to walk/dash it back
## the other way to correct that, which can overshoot again the same way -
## a back-and-forth dash loop. So: only when currently goal-side of the
## ball AND moving toward it (diff's sign is the mirror of
## _goal_side_sign - the same sign _target_x's own ball_x-relative
## construction always points "inward" with) AND the estimated dash travel
## would reach at least as far as the ball's own current position, this
## just returns without dashing - ordinary walking (already pressed by
## _update_movement() before this was called) closes the gap instead,
## covering it more slowly but never in a single overshootable burst.
## Retreating AWAY from the ball (the opposite diff sign) is never gated by
## this - there's no ball to overshoot past in that direction.
func _maybe_dash(diff: float, ball_x: float) -> void:
	if _dash_cooldown_remaining > 0.0 or _ability_gesture_step != 0:
		return
	if _own_wizard == null or not _own_wizard.is_on_floor():
		return
	if _meteor_ability_available():
		return
	# Per the user's own explicit report: wizard.gd's dash only actually
	# carries this wizard anywhere while grounded (see this function's own
	# doc comment above) - once airborne, whatever's left of the SPEED=DASH
	# window is far less useful for repositioning. _update_movement()'s own
	# obstacle-clearing jump runs BEFORE this is called and can request a
	# jump earlier in the very same decision tick (see _up_press_pending),
	# which would otherwise still pass every check above (is_on_floor()
	# hasn't updated yet this frame) and fire a dash in the same instant
	# this wizard is about to leave the ground - burning the dash on a jump
	# that was about to carry it over the obstacle anyway. Skip dashing this
	# tick when that's just happened.
	if _up_press_pending:
		return
	# See _command_cooldown_remaining's own doc comment - purely a "look
	# less like a frame-perfect machine" knob, not a gameplay throttle.
	# Deliberately checked/set here rather than inside the shared
	# _request_down_pulse() helper, so _update_air_control()'s dive (which
	# also calls that helper) stays completely ungated by it - diving is
	# safety-critical for getting down to a ball above this wizard (see
	# addendum 8) and should never be delayed by an unrelated command that
	# just fired.
	if _command_cooldown_remaining > 0.0:
		return
	# maxf() against position_tolerance so a goal_pressure_dash_trigger_distance
	# of 0.0 (the default - dash at the first real excuse) still can't fire on
	# a diff that's inside the ordinary movement deadzone and going nowhere.
	var trigger_distance: float = profile.goal_pressure_dash_trigger_distance if _goal_pressure else profile.dash_trigger_distance
	if absf(diff) <= maxf(trigger_distance, profile.position_tolerance):
		return
	# "Don't dash past the ball" guard - see this function's own doc comment
	# above. own_x - ball_x's sign matches _goal_side_sign exactly when this
	# wizard is currently goal-side of the ball (the same sign check addendum
	# 9's _home_x guard and _target_x's own construction both already rely
	# on); signf(diff) matches -_goal_side_sign exactly when this wizard is
	# about to move TOWARD the ball rather than away from it. Only when both
	# hold does overshooting through the ball's own position even become
	# possible - retreating away from it, or already forward of it (a state
	# normal engagement should never produce, but worth not compounding if
	# something else ever does), are both left ungated.
	var own_x: float = _own_wizard.global_position.x
	var currently_goal_side_of_ball: bool = (own_x - ball_x) * _goal_side_sign >= 0.0
	var moving_toward_ball: bool = signf(diff) == -_goal_side_sign
	if currently_goal_side_of_ball and moving_toward_ball and profile.dash_travel_distance >= absf(own_x - ball_x):
		return
	_request_down_pulse()
	_dash_cooldown_remaining = profile.dash_cooldown
	_command_cooldown_remaining = profile.min_command_interval
	# Opens a short window (see _dash_active_remaining's own doc comment)
	# during which this wizard's own OPTIONAL/tactical jump requests
	# (obstacle-clearing, vertical-engagement chasing) stand down, so a dash
	# just committed to gets to spend its whole SPEED=DASH burst as actual
	# grounded repositioning instead of being cut short by a jump on the
	# very next decision tick. A genuinely needed cast/shield jump (see
	# _update_cast_decision()) is deliberately NOT gated by this - an
	# immediate scoring opportunity always outranks finishing a dash.
	_dash_active_remaining = profile.dash_burst_duration


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
		_diving = false
		_last_grounded_y = _own_wizard.global_position.y
		return
	if _obstacle_jump_active or _ability_gesture_step != 0:
		return
	if _meteor_ability_available():
		return
	# Proactive dive - see _above_ball_out_of_range()'s own doc comment.
	# Fires the instant this wizard is meaningfully above the ball and not
	# yet close enough to matter, regardless of velocity.y - i.e. even while
	# still RISING out of a jump, not just once it naturally crests and
	# starts to fall. This is the "actively WANT to get down there" half of
	# the fix; the other half (_update_cast_decision() refusing to jump in
	# the first place while this is true) is what stops a fresh jump from
	# undoing this dive a moment later.
	if _above_ball_out_of_range():
		_diving = true
		_request_down_pulse()
		return
	if _own_wizard.velocity.y <= 0.0:
		return
	_diving = true
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
##
## Two guards added after a second playtest round found a Meteor-classed bot
## ("the fire mage") jumping into the ceiling nonstop: this had no sense of
## "there's nowhere left to climb," so as long as the ball read as above by
## more than vertical_engage_height - which it easily can for a while after
## every respawn, since create_new_instance() drops a fresh ball in high up
## at (576, 70) - it kept firing another chained jump every
## vertical_jump_interval even while already pressed flat against the
## ceiling, unable to gain another pixel. `is_on_ceiling()` (CharacterBody2D's
## own last-move_and_slide() contact flag) stops that outright: once actually
## touching the ceiling, no amount of re-pressing Up helps, so this just
## stops asking until gravity pulls it back down on its own. Also stands
## down entirely while _defensive (see _update_engagement_role()) - a bot
## that's decided the ball isn't worth chasing right now shouldn't still be
## leaping after it if it happens to be overhead - and while _diving, for
## the same reason _update_cast_decision() does (see that guard's own doc
## comment): this function's own jump request would cancel a dive exactly
## the same way a cast would. Shouldn't normally overlap in practice (this
## only fires when the ball reads as ABOVE, diving only happens while
## falling), but cheap insurance against the same bug in a case not
## actually seen yet. Also stands down while _dash_active_remaining is still
## counting down (see that field's own doc comment) - a ball that's both
## above AND off to the side can have _update_movement() fire a dash this
## same decision tick, immediately followed by this function requesting a
## jump; without this guard that jump fires anyway (this runs later in
## _physics_process() than _update_movement() does) and cuts the dash's
## grounded repositioning short exactly like the obstacle-clearing jump case
## this same field already protects against.
func _update_vertical_engagement() -> void:
	if _own_wizard == null or target_ball == null or _defensive or _diving:
		return
	if _own_wizard.is_on_ceiling():
		return
	if _vertical_jump_cooldown_remaining > 0.0 or _dash_active_remaining > 0.0:
		return
	var ball_state := _delayed_ball_state()
	if ball_state.is_empty():
		return

	var vertical_gap: float = _own_wizard.global_position.y - (ball_state["position"] as Vector2).y
	if vertical_gap < profile.vertical_engage_height:
		return

	_request_jump()
	_vertical_jump_cooldown_remaining = profile.vertical_jump_interval


## True when the ball sits meaningfully below this wizard - by more than
## profile.vertical_engage_height, reusing _update_vertical_engagement()'s
## own "is this height gap worth reacting to" threshold for the mirror-image
## case - AND this wizard isn't yet close enough (by profile.
## close_range_engage_distance, the same "actually within striking range"
## threshold _update_cast_decision()'s own close-range override uses) for a
## cast there to do any good.
##
## Added per the user's own explicit framing, after addendum 5's _diving
## guard turned out not to be enough: a wizard above the ball has no
## business jumping AT ALL unless the jump would land a barrier within real
## striking range. The old in_position+eta cast gate never actually checked
## vertical separation - eta is straight-line distance/speed, which a fast
## ball can satisfy easily regardless of how far above it this wizard sits -
## so a wizard could keep re-triggering a "legitimate-looking" cast+jump
## while never closing the vertical gap, perpetually re-launching itself
## upward while staying above a ball it was never actually touching. Read by
## _update_cast_decision() (suppresses Up entirely while true) and
## _update_air_control() (fires an immediate dive while true, instead of
## waiting for the jump to crest naturally on its own) - together, "don't
## jump for no reason while above the ball" and "actively want to get down
## to it as fast as possible" are the same guard applied on two different
## inputs.
func _above_ball_out_of_range() -> bool:
	if _own_wizard == null or target_ball == null:
		return false
	var ball_state := _delayed_ball_state()
	if ball_state.is_empty():
		return false
	var ball_pos: Vector2 = ball_state["position"]
	var ball_below: float = ball_pos.y - _own_wizard.global_position.y
	if ball_below <= profile.vertical_engage_height:
		return false
	var distance: float = _own_wizard.global_position.distance_to(ball_pos)
	return distance > profile.close_range_engage_distance


## True only when this wizard is BOTH equipped with Meteor AND actually has
## enough strikes banked to make using it worth considering (mirrors
## MeteorPolicy.should_use()'s own strikes_per_tier/min_tiers_banked check,
## since a policy's @export fields are readable directly - see
## BotAbilityPolicy's own doc comment on why that coupling is fine). Added
## per the user's own explicit request: reserving Down for Meteor's own
## double-tap gesture (see _maybe_dash()/_scan_obstacle()'s exclusion in
## _update_movement()/_update_air_control(), all of which used to stand down
## for "equipped with Meteor" outright) only makes sense while Meteor is
## actually a live option. A Meteor-classed bot sitting on too few strikes
## to use it has no ability to protect Down for - it should dash, obstacle-
## jump, and dive exactly like every other class instead of just floating
## there unable to use any of its normal mobility tools.
func _meteor_ability_available() -> bool:
	if _own_wizard == null or not (_ability_policy is MeteorPolicy):
		return false
	var ability := _own_wizard._current_ability() as MeteorAbility
	if ability == null or ability.strikes_per_tier <= 0:
		return false
	var tiers_banked := _own_wizard.strikes / ability.strikes_per_tier
	return tiers_banked >= (_ability_policy as MeteorPolicy).min_tiers_banked


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
##
## And also fires whenever in_position AND the ball is reading as
## essentially stationary (speed at or below min_ball_speed_for_eta, the
## same floor eta's own division-by-zero guard already uses) - added after
## a further playtest turned up a standing standoff: eta against a
## stationary ball is computed off that same floor speed, not the ball's
## real (near-zero) speed, so it can sit comfortably above
## cast_eta_threshold forever, and close_range_engage_distance alone isn't
## guaranteed to cover every point inside the in-position deadzone (see its
## own doc comment on bot_profile.gd for the exact worst-case math). Waiting
## for a "cleaner" eta against a ball that was never going to move on its
## own just isn't meaningful - if it's in position, it should hit it.
##
## Stands down entirely while _diving (see that field's own doc comment):
## wizard.gd's Up press always both jumps and recasts together
## (_cast_and_jump()), and a fresh jump impulse overwrites whatever
## velocity.y the dive already set - so a bot diving down onto a ball from
## above could get "close enough" mid-fall for the close_range/
## stationary_standoff override just above to fire Up, canceling its own
## dive. Since falling back into range just re-triggers it, that showed up
## as a bot bunny-hopping in place above the ball instead of ever
## completing the dive and actually striking it. Letting the dive finish
## uninterrupted matters more than casting one extra time mid-fall - any
## shield this wizard needs should already be up from before the dive
## started, and normal cast timing resumes the instant it lands.
func _update_cast_decision() -> void:
	if _own_wizard == null or target_ball == null or _diving:
		return
	if _cast_cooldown_remaining > 0.0:
		return
	# See _command_cooldown_remaining's own doc comment - purely a "look
	# less like a frame-perfect machine" knob. cast_cooldown above is
	# already bigger than profile.min_command_interval by default, so this
	# only actually matters in the rare case some OTHER command (a jump or
	# dash) fired within the last min_command_interval seconds.
	if _command_cooldown_remaining > 0.0:
		return
	if _above_ball_out_of_range():
		# See that function's own doc comment - the eta check below is
		# straight-line distance/speed and never actually looks at vertical
		# separation, so a fast-moving ball could satisfy it while this
		# wizard sits well above the ball, uselessly re-jumping instead of
		# ever closing the gap. Out here, none of the three conditions below
		# should fire anyway (close_range/stationary_standoff both require
		# real proximity this state says isn't there) - this just also
		# closes the eta path they don't cover.
		return
	var ball_state := _delayed_ball_state()
	if ball_state.is_empty():
		return

	var to_ball: Vector2 = ball_state["position"] - _own_wizard.global_position
	var distance: float = to_ball.length()
	var ball_speed: float = (ball_state["velocity"] as Vector2).length()
	var speed: float = maxf(ball_speed, profile.min_ball_speed_for_eta)
	var eta: float = distance / speed
	var in_position: bool = absf(_target_x - _own_wizard.global_position.x) <= profile.position_tolerance
	var close_range: bool = distance <= profile.close_range_engage_distance
	var stationary_standoff: bool = in_position and ball_speed <= profile.min_ball_speed_for_eta

	if (in_position and eta <= profile.cast_eta_threshold) or close_range or stationary_standoff:
		Input.action_press(_action_up)
		_up_press_pending = true
		_cast_cooldown_remaining = profile.cast_cooldown
		_command_cooldown_remaining = profile.min_command_interval


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
	# When this seat's magic is bound to the button, wizard.gd's Blink/Ice
	# still fire in whatever direction the wizard is FACING (see wizard.gd's
	# _update_blink()/_update_ice_zone() magic-button branch), so a nudge tap
	# on the real direction key is needed first purely to set that facing -
	# see _ability_facing_action()'s own doc comment for why this has to be
	# a separate action from direction_action itself.
	var facing_action := ""
	if direction_action == _action_magic:
		facing_action = _ability_facing_action(ability)
	_start_ability_gesture(direction_action, facing_action)
	_ability_cooldown_remaining = _ability_policy.cooldown


## Which action Blink/Ice/Meteor's double-tap gesture should target, given
## the ability actually equipped - see each policy's own doc comment for WHY
## that direction (toward the goal-side target for Blink, toward the ball
## for Ice, always Down for Meteor). Returns "" if the ability isn't one of
## these three, or if there's no ball to aim relative to yet for Blink/Ice.
## When this seat's magic is bound to the button ("button" mode - "both"
## still prefers the real direction key, since it's just as available and
## needs no facing nudge), the gesture itself targets _action_magic instead
## - see wizard.gd's mode-aware _update_blink()/_update_ice_zone()/
## _update_meteor(), which all read _action_magic taps identically to
## direction taps once mode != "movement".
func _ability_direction_action(ability: WizardAbility) -> String:
	if InputRemap.magic_mode_for(seat) == "button":
		return _action_magic

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


## Only called when _ability_direction_action() returned _action_magic (i.e.
## this seat's magic is in "button" mode) for a Blink/Ice ability - Meteor
## isn't directional at all, so it's excluded here. Mirrors the OLD
## direction-selection logic above exactly, but its result is used only to
## pick a direction key for a brief facing-nudge tap (see
## _advance_ability_gesture()), never as the gesture's own action, since
## wizard.gd's button-mode Blink/Ice reads facing (sprite.flip_h) rather
## than a direction key press. Returns "" for Meteor or if there's no ball
## to aim relative to yet.
func _ability_facing_action(ability: WizardAbility) -> String:
	if ability is MeteorAbility:
		return ""

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

	# In "button" mode, wizard.gd's Growth hold is read off _action_magic
	# instead of Up (see wizard.gd's magic_also_casts/_magic_hold_active()) -
	# "movement" and "both" both still accept the real Up hold, so only
	# "button" needs to swap which action gets pressed/held/released here.
	_growth_hold_action = _action_magic if InputRemap.magic_mode_for(seat) == "button" else _action_up
	Input.action_press(_growth_hold_action)
	_up_press_pending = true
	_up_hold_seconds_remaining = ability.hold_confirm_time + ability.growth_duration_per_tier * maxf(float(policy.tiers_to_grow), 1.0)
	_cast_cooldown_remaining = profile.cast_cooldown
	_ability_cooldown_remaining = policy.cooldown


## Starts a Blink/Ice/Meteor double-tap gesture on the given action - see
## _advance_ability_gesture() for the actual frame-by-frame execution.
## facing_action, when non-"", is briefly tapped first purely to set the
## wizard's facing before the real gesture action fires - see
## _ability_facing_action()'s doc comment for when/why that's needed.
func _start_ability_gesture(action_name: String, facing_action: String = "") -> void:
	_ability_gesture_action = action_name
	_ability_gesture_facing_action = facing_action
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
	# wizard.gd's magic button fires Blink/Ice/Meteor on a single press now
	# (double-tapping was only ever needed because Left/Right/Down double as
	# movement keys - the dedicated magic button has no such dual purpose,
	# so it always fires immediately - see wizard.gd's _update_blink()/
	# _update_ice_zone()/_update_meteor() magic-button blocks). A gesture
	# targeting _action_magic (this seat's mode is "button" - see
	# _ability_direction_action()) only needs a clean one-tap pulse, not the
	# full double-tap sequence a direction key still requires.
	var single_tap := _ability_gesture_action == _action_magic
	var final_step := 3 if single_tap else 5
	match _ability_gesture_step:
		1:
			Input.action_release(_action_left)
			Input.action_release(_action_right)
			# Facing nudge (button-mode Blink/Ice only - see
			# _ability_facing_action()): press the real direction key one
			# step early so wizard.gd's movement code has a frame to flip
			# sprite.flip_h before the magic-button tap below reads it.
			if _ability_gesture_facing_action != "":
				Input.action_press(_ability_gesture_facing_action)
		2:
			if _ability_gesture_facing_action != "":
				Input.action_release(_ability_gesture_facing_action)
			Input.action_press(_ability_gesture_action)
		3:
			Input.action_release(_ability_gesture_action)
		4:
			Input.action_press(_ability_gesture_action)
		5:
			Input.action_release(_ability_gesture_action)
	_ability_gesture_step += 1
	if _ability_gesture_step > final_step:
		_ability_gesture_step = 0
		_ability_gesture_action = ""
		_ability_gesture_facing_action = ""


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

	# Engagement role - see _update_engagement_role(). A gray ring plus a
	# gray tick at _home_x makes "this bot has decided to hang back" visible
	# at a glance, distinct from the purple ability ring above.
	if _defensive:
		draw_arc(own_local, 20.0, 0.0, TAU, 24, Color.GRAY, 2.0)
		if _own_wizard != null:
			var home_local := to_local(Vector2(_home_x, _own_wizard.global_position.y))
			draw_line(home_local + Vector2(0, -40), home_local + Vector2(0, 40), Color.GRAY, 2.0)

	# Goal pressure - see _update_goal_pressure(). A thick orange-red ring
	# distinct from both the gray defensive ring and the purple ability ring
	# - this is the "under direct threat, racing to intercept" state, the
	# opposite end of the spectrum from _defensive.
	if _goal_pressure:
		draw_arc(own_local, 26.0, 0.0, TAU, 24, Color(1.0, 0.3, 0.0), 3.0)

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
