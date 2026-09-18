extends Node

func click(pos: Vector2) -> void:
	var motion:=InputEventMouseMotion.new()
	motion.position=pos
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var e:=InputEventMouseButton.new()
	e.position=pos
	e.button_index=MOUSE_BUTTON_LEFT
	e.pressed=true
	Input.parse_input_event(e)
	await get_tree().process_frame
	e=e.duplicate()
	e.pressed=false
	Input.parse_input_event(e)
	await get_tree().process_frame

func key(code: Key) -> void:
	var e:=InputEventKey.new()
	e.physical_keycode=code
	e.pressed=true
	Input.parse_input_event(e)
	await get_tree().physics_frame
	e=e.duplicate()
	e.pressed=false
	Input.parse_input_event(e)
	await get_tree().physics_frame

func shot(file: String) -> void:
	await get_tree().create_timer(0.4).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/"+file+".png")

func run(game: Node3D) -> void:
	await get_tree().create_timer(1.0).timeout
	await click(Vector2(180,382))
	assert(game.started and not game.paused,"Menu click failed")
	await key(KEY_T)
	assert(game.challenge_running,"T challenge failed")
	Input.action_press("fire")
	await get_tree().create_timer(0.45).timeout
	Input.action_release("fire")
	assert(game.player.shots_fired>0,"Fire input failed")
	await shot("18_ui_shooting")
	await key(KEY_G)
	assert(game.course.running,"G course failed")
	await shot("19_ui_course")
	await key(KEY_ESCAPE)
	assert(game.paused,"Pause input failed")
	await shot("20_ui_pause")
	await click(Vector2(550,120))
	assert(game.course.running and not game.paused and game.course.cleared==0,"Course button failed")
	await key(KEY_ESCAPE)
	await click(Vector2(200,382))
	assert(not game.paused,"Resume button failed")
	print("UI_FLOW_PASS: menu click, T, shooting, G, Escape, course button, resume button")
	get_tree().quit()
