extends Node

func click(pos: Vector2) -> void:
	var motion:=InputEventMouseMotion.new()
	motion.position=pos
	Input.parse_input_event(motion)
	await get_tree().process_frame
	var ev:=InputEventMouseButton.new()
	ev.position=pos
	ev.button_index=MOUSE_BUTTON_LEFT
	ev.pressed=true
	Input.parse_input_event(ev)
	await get_tree().process_frame
	ev=ev.duplicate()
	ev.pressed=false
	Input.parse_input_event(ev)
	await get_tree().process_frame

func key(code: Key) -> void:
	var ev:=InputEventKey.new()
	ev.physical_keycode=code
	ev.pressed=true
	Input.parse_input_event(ev)
	await get_tree().physics_frame
	ev=ev.duplicate()
	ev.pressed=false
	Input.parse_input_event(ev)
	await get_tree().physics_frame

func run(game: Node3D) -> void:
	await get_tree().create_timer(0.5).timeout
	await click(Vector2(180,382))
	assert(game.running and game.bots.size()==8,"start button")
	for bot: Node3D in game.bots: bot.active=false
	game.player.health=50
	await key(KEY_H)
	assert(game.player.healing,"H heal")
	await key(KEY_ESCAPE)
	assert(game.paused and not game.player.active,"pause")
	await click(Vector2(180,382))
	assert(not game.paused and game.player.active,"resume")
	for bot: Node3D in game.bots: bot.active=false
	game.player.take_damage(1000,Vector3.ZERO,null)
	await get_tree().create_timer(0.1).timeout
	assert(game.finished and not game.won,"defeat")
	await click(Vector2(180,382))
	assert(not game.finished and game.alive_count==9,"result replay")
	await key(KEY_G)
	await key(KEY_T)
	await key(KEY_F)
	assert(game.running and game.player.position.z>25,"old mode keys do not change match")
	await key(KEY_ESCAPE)
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/combat_11_ui.png")
	print("COMBAT_UI_PASS: start,heal,pause,resume,death,replay,no legacy modes")
	get_tree().quit()
