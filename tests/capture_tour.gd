extends Node

var performance_samples: Array[Dictionary] = []

func shot(filename: String) -> void:
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/"+filename+".png")
	performance_samples.append({"view":filename,"fps":Engine.get_frames_per_second(),"draw_calls":Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)})

func run(game: Node3D) -> void:
	await shot("01_menu")
	game._start()
	await shot("02_spawn")
	game._teleport(Vector3(-10,0,36),0.63)
	await shot("03_village")
	game._teleport(Vector3(25,0,15),-0.26)
	await shot("04_warehouse")
	game._begin_challenge()
	await shot("05_range")
	Input.action_press("aim")
	await shot("06_aim")
	Input.action_release("aim")
	game.challenge_running=false
	game._teleport(Vector3(-31,0,-81),-2.75)
	game.player._pitch=-0.13
	await shot("07_hill")
	game._teleport(Vector3(44,0,69),-2.82)
	await shot("08_coast")
	game.course.start_course()
	await shot("12_course")
	game._pause()
	await shot("13_settings")
	game.hud.hide()
	game.overview.current=true
	game.overview.position=Vector3(11,5.1,-32.3)
	game.overview.look_at(Vector3(13,4.2,-37))
	await shot("14_character_model")
	game.overview.position=Vector3(-4,5.6,29)
	game.overview.look_at(Vector3(-8,4.0,24))
	await shot("15_vehicle_model")
	game.hud.show()
	game._resume()
	for i: int in range(3):
		var targets: Array=game.course.stage_targets.duplicate()
		for target: Node3D in targets:
			target.receive_hit(100,target.global_position+Vector3(0,1.2,0))
		await get_tree().process_frame
		await get_tree().process_frame
	await shot("16_course_result")
	var file:=FileAccess.open("res://tests/render_metrics.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(performance_samples,"  "))
	file.close()
	print("CAPTURE_TOUR_COMPLETE")
	get_tree().quit()
