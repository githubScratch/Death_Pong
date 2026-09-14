extends Resource
class_name BotProfile

## Difficulty/personality knobs for a BotController (Phase 4 of the bot AI
## rollout - see the project's bot-implementation-roadmap doc). Everything a
## bot's decision layer needs to know "how good" to be lives here instead of
## as constants in bot_controller.gd, so a new difficulty is a new .tres file
## (see PLAYERS/bots/profiles/) hand-tuned in the Inspector, never a code
## branch - the same convention this project already uses for
## WizardClass/WizardAbility .tres resources.
##
## The imperfection knobs below (reaction_delay, placement_offset_error) are
## not cosmetic here: since a shield's aim is a single placement decision
## rather than continuous tracking (see deflection_shield.gd), a bot with
## zero delay/error looks unbeatable almost immediately - confirmed in
## Phase 2 testing, where a zero-error bot could plant a shield dead-on
## nearly every time. They're load-bearing for the game being fun to play
## against, not optional polish.

## Seconds of simulated reaction lag: the decision layer aims using where
## the tracked ball WAS this many seconds ago, not where it is right now -
## see BotController's _ball_history / _delayed_ball_state(). 0.0 means no
## lag (perfect reflexes).
@export var reaction_delay: float = 0.0

## Random +/- pixels added to the goal-side target X each time the decision
## layer re-aims (see BotController._update_movement()) - simulates
## imprecise placement rather than a laser-guided shield every time. 0.0
## means perfect aim.
@export var placement_offset_error: float = 0.0

## Minimum seconds between decision re-evaluations (movement + cast
## commitment) - 0.0 re-decides every physics frame (60/sec), matching
## Phase 2's original always-on behavior. A larger value makes the bot feel
## like it's "thinking" on a human-scale tick rate instead of a perfect
## 60Hz loop. This also controls how often placement_offset_error gets
## rerolled (see _update_movement()) - pairing a nonzero error with
## decision_interval == 0.0 reads as constant jitter rather than occasional
## imprecision, so keep them paired sensibly (see the starter profiles in
## PLAYERS/bots/profiles/ for reasonable combinations).
@export var decision_interval: float = 0.0

## Minimum real-world seconds this bot enforces between any two brand-new
## discrete input COMMANDS - a jump request or a dash/dive pulse (see
## BotController._request_jump()/_request_down_pulse(), the two chokepoints
## every one-off button press funnels through, and _update_cast_decision()'s
## own direct Up-press) - regardless of which kind fires next. Distinct from
## decision_interval just above: that one paces how often the DECISION
## layer re-evaluates at all, while this paces how soon this bot may act
## again once it HAS decided to do something, even across two completely
## different actions decided on the very same tick. Added per the user's
## own explicit request purely to look less like a frame-perfect machine -
## with decision_interval able to be 0.0 (Hard's own default), nothing
## previously stopped e.g. a jump and a dash from firing on the exact same
## physics frame, something no human could ever actually do. Deliberately
## does NOT gate continuous left/right movement, an ability gesture/Growth
## hold already under way, or _update_air_control()'s dive (safety-critical
## for getting down to a ball above this wizard - see addendum 8 in the
## roadmap doc - and should never be delayed by an unrelated command).
@export var min_command_interval: float = 0.1

## Reserved for Phase 3's optional lookahead tier (not yet built): 0 = pure
## reactive (Tier 0), 1 = straight-line lead-time (Tier 1 - what Phase 2
## actually implements today regardless of this value), 2 = single-bounce
## lookahead (Tier 2, PLAYERS/bots/trajectory_predictor.gd once it exists).
## Unused until Phase 3 lands; present now so starter profiles don't need
## re-authoring later.
@export var lookahead_tier: int = 1

@export_group("Positioning & Cast")
## Moved here in Phase 4 from BotController's own fields of the same names,
## so they're difficulty-tunable per .tres instead of fixed on the node -
## see PLAYERS/bots/bot_controller.gd's git history (or the roadmap doc) for
## the original reasoning behind each.

## How far from the tracked ball's current X to stand, on the goal side of
## it. See deflection_shield.gd's deflect_ball(): a bigger margin plants the
## shield further from dead-center of the ball, sending it off at more of an
## angle rather than straight back.
@export var goal_side_margin: float = 36.0

## Deadzone half-width, in pixels, around the target stand X.
@export var position_tolerance: float = 20.0

## Only commit to a cast when the ball's straight-line ETA is at or below
## this many seconds AND the bot is in position.
@export var cast_eta_threshold: float = 0.35

## Minimum seconds between two casts.
@export var cast_cooldown: float = 0.4

## Floor under the ball's speed when computing ETA (distance / speed).
@export var min_ball_speed_for_eta: float = 40.0

## Bypasses the eta/in-position gating above entirely whenever the ball's
## straight-line distance (not just horizontal - see _update_cast_decision())
## is within this many pixels - added after playtesting showed a bot that
## had walked right up next to the ball could still end up doing nothing but
## stand there: `in_position` is measured against the goal-side STAND point
## (offset from the ball by goal_side_margin), not the ball itself, so a bot
## a few pixels from the ball but not exactly on that offset point could fail
## the in-position check while eta gating separately waited for a "cleaner"
## approach angle that a ball sitting nearly still right next to it was never
## going to produce. This is a deliberate "just engage" override, not a
## replacement for the eta/position logic above - still respects
## cast_cooldown, so it reads as an eager poke, not a stutter.
##
## Raised from an original 50.0 after a further playtest turned up a standing
## standoff against a stationary ball: `in_position` only requires landing
## within position_tolerance of the goal-side stand point, and that stand
## point already sits goal_side_margin away from the ball itself - so a bot
## that parks at the FAR edge of its own tolerance band can be as much as
## goal_side_margin + position_tolerance (56px with the defaults below) from
## the ball while still reading as "in position," which used to clear this
## gate too. Set comfortably above that worst case so being in position is
## never itself the reason a stand nearly on top of the ball fails to close
## the last few pixels. See _update_cast_decision()'s own new stationary-ball
## clause for the other half of that same fix.
@export var close_range_engage_distance: float = 70.0

@export_group("Tactical Movement & Pathing")
## Phase 6: reusing wizard.gd's own ground-dash/dive/jump moves (SPEED = DASH,
## DIVE_VELOCITY, the ordinary jump impulse) as deliberate repositioning
## tools instead of only ever walking at plain SPEED - see
## BotController._maybe_dash()/_update_air_control()/_scan_obstacle().

## Only bother dashing when the remaining distance to travel (to the real
## target, or to a reroute waypoint - see _scan_obstacle()) exceeds this many
## pixels - a short adjustment doesn't need the 1400 SPEED burst wizard.gd's
## own Down-while-grounded dash gives (see wizard.gd's SPEED/DASH constants),
## it'd just overshoot.
@export var dash_trigger_distance: float = 150.0

## Minimum seconds between two dash triggers. Deliberately matched to
## wizard.gd's own dash burst duration (0.1s - see its _physics_process(),
## the SPEED = DASH window) rather than a longer artificial gap: per the
## user's explicit request the bot should be able to dash with unlimited
## repetition, back-to-back, for as long as it's still far from where it
## needs to be - this value's only job is to stop a press landing mid-burst
## (which wouldn't add anything - wizard.gd's own timer is already running)
## and not to rate-limit dashing the way profile.vertical_jump_interval
## deliberately rate-limits chained air-jumps (that one exists because
## every jump ALSO recasts the shield - see _apply_jump_impulse() via
## _cast_and_jump() - a cost the ground dash doesn't carry).
@export var dash_cooldown: float = 0.1

## How long wizard.gd's own ground dash actually boosts SPEED for once
## triggered (see wizard.gd's Down-while-grounded dash: `SPEED = DASH` for a
## hardcoded 0.1s before resetting to INIT_SPEED) - kept as its own tunable
## here rather than read directly off wizard.gd (that 0.1s is a bare literal
## inside an await, not an exposed constant, and this project's own
## convention is never to edit wizard.gd itself). BotController.
## _dash_active_remaining counts down from this the instant a dash pulse
## fires, and this wizard's own optional/tactical jump requests (obstacle-
## clearing, vertical-engagement chasing) stand down for as long as it's
## still counting - see that field's own doc comment for why: per the
## user's own explicit report, a jump immediately after a dash cuts the
## dash's repositioning benefit short, since the SPEED boost above is far
## less useful once this wizard leaves the ground. MUST be kept in sync by
## hand if wizard.gd's own 0.1s literal ever changes.
@export var dash_burst_duration: float = 0.1

## Estimated max horizontal distance (in pixels) wizard.gd's own ground dash
## actually covers over its dash_burst_duration window - wizard.gd's DASH
## constant (1400.0) times that duration (0.1s by default), so 140.0 here.
## Kept as its own tunable rather than computed from DASH/dash_burst_duration
## directly, matching this project's own convention of never reading a bare
## literal out of wizard.gd itself - MUST be kept in sync by hand if either
## one changes. Used only by _maybe_dash()'s "don't dash past the ball" guard
## (see that function's own doc comment) to estimate whether a dash about to
## fire would carry this wizard clean through the ball's own position rather
## than just toward it.
@export var dash_travel_distance: float = 140.0

## How far ahead (in pixels, along the current direction of travel) to check
## for a physical obstacle before walking into it - see _scan_obstacle().
## Matched to a little more than one decision tick's worth of ground covered
## at normal SPEED so the bot reacts before actually touching whatever it
## finds, not after.
@export var obstacle_probe_distance: float = 70.0

## How far above the wizard's own current height (in pixels) to re-run the
## same forward probe when deciding whether an obstacle ahead is short enough
## to clear with an ordinary jump (wizard.gd's JUMP_VELOCITY arc) rather than
## needing to be walked around - see _scan_obstacle(). Not a literal jump-arc
## simulation, just a generous stand-in for "how high does this wizard's jump
## reliably clear."
@export var obstacle_clear_height: float = 220.0

## When an obstacle ahead is too tall to jump (see obstacle_clear_height),
## the bot holds this many pixels short of it instead of walking into it -
## see _scan_obstacle()'s "blocked" case in _update_movement(). Re-scanned
## every decision tick, so a moving platform or a fading barrier that clears
## the path gets noticed and walked past on its own, with no separate
## "waiting" state to track.
@export var reroute_margin: float = 50.0

## Minimum seconds between two obstacle-CLEARING jump attempts (the
## "blocked, jumpable" case above) in the SAME direction - see
## BotController._obstacle_jump_cooldown_remaining's own doc comment for the
## failure this closes: obstacle_clear_height above is a cheap stand-in, not
## a real jump-arc simulation, and playtesting found a spot where it read as
## clearable but the wizard's actual jump never carried past it - which,
## with nothing else changing between decision ticks, meant the exact same
## jump got re-requested every single tick forever: a bot bunny-hopping in
## place (and burning a shield recast every hop - see _request_jump()'s own
## doc comment) instead of ever making progress. This doesn't make the scan
## smarter about what's actually clearable; it just stops a failed attempt
## from being retried instantly, giving the ordinary hold-short reroute a
## chance to take over instead.
@export var obstacle_jump_retry_cooldown: float = 1.0

@export_group("Vertical Engagement")
## Added after playtesting showed the bot making no effort at all to reach a
## ball sitting on a platform above it, despite wizard.gd placing no limit on
## how many times Up can be pressed while airborne (see its
## _apply_jump_impulse(): DBL_JUMP_VELOCITY applies unconditionally whenever
## not is_on_floor(), no jump counter anywhere) - a real, human-usable
## "climb" this bot just wasn't using. See
## BotController._update_vertical_engagement().

## Only bother climbing when the ball sits at least this many pixels above
## this wizard's own current position - a small height difference (e.g. a
## slight bounce) isn't worth interrupting normal ground play for.
@export var vertical_engage_height: float = 50.0

## Minimum seconds between chained air-jumps while climbing toward a ball
## that's above - NOT the same knob as a human's own jump timing, this is
## purely to keep repeated Up presses (each one a fresh
## _apply_jump_impulse() - and, per _cast_and_jump(), a fresh shield recast
## every time) from firing every single physics frame while airborne, which
## would spam-recast dozens of shields a second for no visible benefit -
## this paces it into a readable series of hops instead.
@export var vertical_jump_interval: float = 0.25

## The reverse case, added after playtesting showed the bot stuck standing
## directly over a ball on a lower platform/the ground: since a one-way
## platform (see ARENAS/moving_platform.gd) only ever lets a body pass
## through moving UP into it, not voluntarily drop down through it while
## standing on top, and the ball being straight down means the ordinary
## goal-side target X sits inside position_tolerance (i.e. nothing about
## normal horizontal steering wants to move at all) - the bot needs a
## deliberate reason to walk off the platform's edge instead of idling
## forever. See BotController._update_movement()'s own descend override.
## Only kicks in once the ball is at least this many pixels below this
## wizard's own current position.
@export var descend_engage_height: float = 40.0

@export_group("Engagement Role")
## Added per the user's own explicit design: chasing the ball everywhere,
## including deep into the opponent's half during a long volley, leaves this
## wizard's own goal wide open - not smart, however good the mobility
## toolkit above is. See BotController._update_engagement_role() for the
## race logic this powers, and _home_x for what "falling back" actually
## means (this wizard's own spawn X - see _ready() - rather than a hardcoded
## arena position, so this works on any map without per-arena tuning).

## The ball has to be at least this far away before defensive caution even
## gets considered - a nearby ball is always worth engaging regardless of
## who else is around.
@export var defensive_ball_range: float = 250.0

## An opposing wizard has to be within this distance of the ball to count as
## "about to strike back" - otherwise there's no real threat to react to and
## this wizard just goes and gets the ball as usual.
@export var opponent_threat_distance: float = 200.0

## Whether being far from the ball and outraced by a threatening opponent
## (see the two fields above) means playing it safe. False restores the old
## always-chase behavior - useful for isolated testing (e.g. no second
## wizard on the field, where "opponent" never applies anyway) without
## needing to also blow out the distance thresholds above.
@export var defensive_role_enabled: bool = true

## Minimum seconds _defensive must hold whatever value it just switched to
## before _update_engagement_role() is allowed to re-evaluate it at all -
## added after playtesting caught a bot visibly flickering left/right in
## place ("facing both directions" within the same second). The race in
## step 3 of that function (own distance/speed vs. the nearest threatening
## opponent's) is a continuous comparison with no built-in deadband, and
## with decision_interval at or near 0.0 (see Hard's own profile) it's
## re-run every physics frame - a ball wobbling by a pixel, or an opponent
## taking one step, is enough to flip which side is nominally "faster" from
## frame to frame, and _defensive flipping means _move_target_x flips
## between the ball-relative stand point and _home_x, which can sit on
## OPPOSITE sides of this wizard - hence the flicker. This doesn't change
## the race logic itself, just rate-limits how often its verdict is allowed
## to change, which is enough to turn frame-by-frame flicker into a clean,
## deliberate switch a human would actually perceive as "changing its mind."
@export var engagement_role_min_hold: float = 0.35

## How close (pixels, measured from the ball to _home_x - see
## BotController._update_goal_pressure()'s own doc comment for why _home_x
## and not this wizard's current position) the ball has to get before this
## wizard treats it as urgent goal defense - added per the user's own
## explicit design, as the deliberate opposite case from the
## defensive-fallback fields above: those decide when NOT to bother chasing
## a ball that's already lost; this decides when the ball is close enough to
## this wizard's own goal that it has to be met regardless of any race
## outcome. Defaults to roughly a third of this project's current Arena
## (goal-to-goal is ~1064px) per the user's own estimate - a plain tunable,
## not derived from any actual arena dimension.
@export var goal_pressure_range: float = 350.0

## Replaces dash_trigger_distance while under goal pressure (see the field
## above) - per the user's own explicit request that a ball closing in on
## this wizard's own goal should be raced down with dashes "as needed,"
## not gated behind the same distance threshold ordinary repositioning
## uses. 0.0 means dash the instant there's anywhere to go at all (still
## respects position_tolerance via the diff check in
## BotController._maybe_dash(), so it won't dash while already essentially
## on target).
@export var goal_pressure_dash_trigger_distance: float = 0.0
