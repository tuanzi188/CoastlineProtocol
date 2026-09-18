extends SceneTree
var game: Node3D
var checks: Array[Dictionary]=[]

func _initialize() -> void:
	call_deferred("run")

func record(label: String,ok: bool) -> void:
	checks.append({"name":label,"pass":ok})
	print(("PASS " if ok else "FAIL ")+label)

func shot(name: String) -> void:
	await create_timer(0.35).timeout
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("res://tests/"+name+".png")

func run() -> void:
	game=load("res://main.tscn").instantiate()
	root.add_child(game)
	current_scene=game
	while game.initializing: await process_frame
	game._start()
	for bot: Node3D in game.bots: bot.active=false
	await create_timer(0.5).timeout
	record("ten individual fingers",game.player._hands.finger_count==10)
	record("detailed glove meshes built",game.player._hands.mesh_count>50)
	await shot("hands_01_hip")
	Input.action_press("aim")
	await create_timer(0.5).timeout
	record("ADS FOV preserved",game.player.camera.fov<55)
	await shot("hands_02_ads")
	Input.action_release("aim")
	await create_timer(0.3).timeout
	game.player.ammo=19
	game.player._start_reload()
	await create_timer(0.77).timeout
	game.player.set_process(false)
	game.player.set_physics_process(false)
	record("support hand moves to magazine",game.player._hands.left.position.z>0.1)
	record("magazine follows reload drop",game.player._hands._magazine.position.y<game.player._hands._magazine_rest.y-0.1)
	await shot("hands_03_reload")
	game.player.set_process(true)
	game.player.set_physics_process(true)
	await create_timer(1.3).timeout
	record("reload ammo accounting unchanged",game.player.ammo==30 and game.player.reserve==169)
	record("support hand returns to grip",game.player._hands.left.position.length()<0.005)
	game.player.reset_loadout()
	await create_timer(0.2).timeout
	record("reset restores hand pose",game.player._hands.left.position.length()<0.001)
	game.player.set_process(false)
	game.player.set_physics_process(false)
	game.hud.hide()
	var w: Node3D=game.player._weapon
	game.overview.fov=45
	game.overview.global_position=w.to_global(Vector3(-0.32,0.09,-0.11))
	game.overview.look_at(w.to_global(Vector3(-0.06,-0.07,-0.41)),Vector3.UP)
	game.overview.near=0.015
	game.overview.current=true
	await shot("hands_04_support_detail")
	game.overview.global_position=w.to_global(Vector3(0.27,0.02,0.22))
	game.overview.look_at(w.to_global(Vector3(0.035,-0.12,0.025)),Vector3.UP)
	await shot("hands_05_trigger_detail")
	var failures: int=0
	for item: Dictionary in checks:
		if not item.pass: failures+=1
	var file:=FileAccess.open("res://tests/hands_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify({"passed":checks.size()-failures,"failed":failures,"checks":checks},"  "))
	file.close()
	print("HANDS_RESULT %d/%d" % [checks.size()-failures,checks.size()])
	quit(1 if failures else 0)
