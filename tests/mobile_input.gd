extends SceneTree
var game: Node3D
var checks: Array[Dictionary]=[]

func _initialize() -> void:
	call_deferred("run")

func check(label: String,ok: bool) -> void:
	checks.append({"name":label,"pass":ok})
	print(("PASS " if ok else "FAIL ")+label)

func point(logical: Vector2) -> Vector2:
	return root.get_final_transform() * (game.mobile_controls.get_global_transform_with_canvas()*logical)

func touch(index: int,logical: Vector2,pressed: bool) -> void:
	game.mobile_controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	var event:=InputEventScreenTouch.new()
	event.index=index
	event.position=point(logical)
	event.pressed=pressed
	Input.parse_input_event(event)
	await process_frame
	await physics_frame

func drag(index: int,from: Vector2,to: Vector2) -> void:
	var event:=InputEventScreenDrag.new()
	event.index=index
	event.position=point(to)
	event.relative=point(to)-point(from)
	Input.parse_input_event(event)
	await process_frame
	await physics_frame

func shot(name: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/"+name+".png")

func run() -> void:
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	while game.initializing: await process_frame
	check("mobile profile enabled",game.mobile_mode)
	game._start()
	for bot: Node3D in game.bots: bot.active=false
	# The control layer only enables while the window holds focus, which a scripted
	# launch does not guarantee. touch() already nudges this; the visibility probe
	# below runs before any touch, so it needs the same nudge or it reports a
	# focus race as a regression.
	game.mobile_controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	await create_timer(0.3).timeout
	check("touch controls visible",game.mobile_controls.visible)
	var start: Vector3=game.player.position
	await touch(1,Vector2(126,556),true)
	await drag(1,Vector2(126,556),Vector2(126,488))
	await create_timer(0.7).timeout
	check("joystick moves forward",game.player.position.distance_to(start)>2)
	check("upper joystick sprints",Input.is_action_pressed("sprint"))
	var yaw: float=game.player.rotation.y
	await touch(2,Vector2(720,310),true)
	await drag(2,Vector2(720,310),Vector2(780,310))
	check("look works while moving",absf(game.player.rotation.y-yaw)>0.1 and Input.is_action_pressed("move_forward"))
	await touch(2,Vector2(780,310),false)
	await touch(1,Vector2(126,488),false)
	check("joystick release stops actions",not Input.is_action_pressed("move_forward") and not Input.is_action_pressed("sprint"))
	await touch(3,Vector2(1080,366),true)
	await touch(3,Vector2(1080,366),false)
	await create_timer(0.3).timeout
	check("tap ADS latches",game.player.aiming and game.player.camera.fov<56)
	await shot("mobile_02_ads")
	await touch(3,Vector2(1080,366),true)
	await touch(3,Vector2(1080,366),false)
	var ammo: int=game.player.ammo
	yaw=game.player.rotation.y
	await touch(4,Vector2(1163,472),true)
	await drag(4,Vector2(1163,472),Vector2(1130,498))
	await create_timer(0.3).timeout
	check("fire and drag aim together",game.player.ammo<ammo and absf(game.player.rotation.y-yaw)>0.05)
	await touch(5,Vector2(68,285),true)
	await touch(4,Vector2(1130,498),false)
	check("secondary fire retains held action",Input.is_action_pressed("fire"))
	await touch(5,Vector2(68,285),false)
	check("all fire released",not Input.is_action_pressed("fire"))
	await touch(6,Vector2(1080,588),true)
	await touch(6,Vector2(1080,588),false)
	check("crouch toggle",game.player.crouching)
	await touch(6,Vector2(1080,588),true)
	await touch(6,Vector2(1080,588),false)
	await touch(10,Vector2(780,588),true)
	await touch(10,Vector2(780,588),false)
	await create_timer(0.25).timeout
	check("prone toggle drops capsule",game.player.prone and game.player._capsule.height<0.8)
	await touch(10,Vector2(780,588),true)
	await touch(10,Vector2(780,588),false)
	await create_timer(0.25).timeout
	check("prone toggle restores stance",not game.player.prone and game.player._capsule.height>1.7)
	await touch(11,Vector2(1150,285),true)
	await create_timer(0.4).timeout
	check("lean left holds",game.player.lean<-0.5)
	await touch(11,Vector2(1150,285),false)
	await create_timer(0.4).timeout
	check("lean releases",absf(game.player.lean)<0.1)
	await touch(12,Vector2(780,588),true)
	await touch(12,Vector2(780,588),false)
	await create_timer(0.25).timeout
	await touch(13,Vector2(1080,588),true)
	await touch(13,Vector2(1080,588),false)
	await create_timer(0.25).timeout
	check("crouch overrides prone",game.player.crouching and not game.player.prone)
	await touch(13,Vector2(1080,588),true)
	await touch(13,Vector2(1080,588),false)
	await create_timer(0.25).timeout
	await touch(7,Vector2(980,588),true)
	await touch(7,Vector2(980,588),false)
	check("reload touch",game.player.reloading)
	await create_timer(2).timeout
	check("reload completes",game.player.ammo==30)
	game.player.health=50
	await touch(8,Vector2(880,588),true)
	await touch(8,Vector2(880,588),false)
	check("heal touch",game.player.healing)
	await touch(1,Vector2(126,556),true)
	await touch(9,Vector2(1010,55),true)
	check("pause releases all held inputs",game.paused and game.mobile_controls.touch_roles.is_empty() and not Input.is_action_pressed("move_forward") and not Input.is_action_pressed("fire"))
	await shot("mobile_03_menu")
	game._resume()
	game.mobile_controls._notification(Node.NOTIFICATION_APPLICATION_FOCUS_IN)
	for bot: Node3D in game.bots: bot.active=false
	await process_frame
	check("resume returns clean controls",game.mobile_controls.visible and not game.mobile_controls.aim_toggled)
	game.player.healing=false
	game.player.heal_left=0
	await create_timer(0.2).timeout
	var ground_y: float=game.player.position.y
	await touch(10,Vector2(1180,586),true)
	await create_timer(0.15).timeout
	check("jump touch",game.player.position.y>ground_y+0.2)
	await touch(10,Vector2(1180,586),false)
	await create_timer(0.5).timeout
	var item: Node3D=game.loot[0]
	game.player.position=item.position+Vector3(0,0.1,1)
	await create_timer(0.2).timeout
	var count: int=game.loot.size()
	await touch(11,Vector2(977,470),true)
	await touch(11,Vector2(977,470),false)
	check("pickup touch grants supplies",game.loot.size()==count-1)
	await touch(12,Vector2(1163,472),true)
	var cancel:=InputEventScreenTouch.new()
	cancel.index=12
	cancel.position=point(Vector2(1163,472))
	cancel.canceled=true
	cancel.pressed=false
	Input.parse_input_event(cancel)
	await physics_frame
	check("canceled touch releases fire",not Input.is_action_pressed("fire"))
	await shot("mobile_01_controls")
	var failures: int=0
	for c: Dictionary in checks:
		if not c.pass: failures+=1
	var file:=FileAccess.open("res://tests/mobile_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"checks":checks,"passed":checks.size()-failures,"failed":failures},"  "))
	file.close()
	print("MOBILE_RESULT %d/%d" %[checks.size()-failures,checks.size()])
	quit(1 if failures else 0)
