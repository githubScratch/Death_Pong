extends Control

## Owns the ENTIRE pause/unpause toggle for this arena, in one place.
##
## Lives on the "Pause" Control node, which already carries
## process_mode = PROCESS_MODE_ALWAYS from the original project (it has to,
## so its Continue/Menu buttons stay clickable while the tree is paused).
## That makes it the one legitimate "survives pause" anchor already in the
## scene - so instead of hand-marking every gameplay node PAUSABLE (which
## turned into an endless whack-a-mole as new node types kept needing the
## same override), the arena root and everything under it now stays on
## Godot's normal default process_mode, and only this one small
## always-running script reaches back into the arena to drive the toggle.
##
## Both directions - noticing the pause key while unpaused, and noticing it
## (or the back key) while paused - live in THIS single _process(), rather
## than being split between this script and the arena's own _process().
## Splitting them risks both scripts reacting to the same physical keypress
## in the same frame and fighting each other; keeping the whole toggle in
## one place removes that race entirely.
##
## Reached via get_tree().current_scene rather than get_parent(), because
## Tower's Pause node is nested under CameraPackage/Screens instead of
## being a direct child of the arena root like the other three arenas -
## current_scene finds the arena either way.

func _process(_delta: float) -> void:
	var arena = get_tree().current_scene
	if arena == null or not arena.has_method("pause"):
		return

	# Menu-navigation SFX only needs to be driven from here while the tree
	# is actually paused - the arena's own _process() is alive (and already
	# plays this SFX) any time the tree isn't paused, including victory.
	if arena.is_paused:
		if Input.is_action_just_pressed("ui_left") or Input.is_action_just_pressed("ui_right"):
			arena.move.pitch_scale = randf_range(0.9, 1.1)
			arena.move.play()
		if Input.is_action_just_pressed("ui_select"):
			arena.select.pitch_scale = randf_range(0.9, 1.1)
			arena.select.play()

	if Input.is_action_just_pressed("ui_select"):
		if not arena.is_paused and not arena.is_victory:
			arena.pause()
		elif arena.is_paused and not arena.is_victory:
			arena.unpause_game()

	if Input.is_action_just_pressed("ui_back") and arena.is_paused and not arena.is_victory:
		arena.unpause_game()
