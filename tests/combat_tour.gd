extends Node
var samples: Array[Dictionary]=[]
func shot(name: String) -> void:
	await get_tree().create_timer(0.8).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("res://tests/"+name+".png")
	samples.append({"view":name,"fps":Engine.get_frames_per_second()})

func run(game: Node3D) -> void:
	await shot("combat_01_menu")
	game._start()
	await shot("combat_02_start")
	for bot: Node3D in game.bots: bot.active=false
	var enemy: Node3D=game.bots[0]
	enemy.position=game.nav.nearest(Vector3(4,3,11))+Vector3.UP*0.1
	enemy.rotation.y=PI
	game.player.position=Vector3(1,game.world.get_height(1,28)+0.2,28)
	enemy.active=true
	enemy.hear_shot(game.player.position,game.player)
	await get_tree().create_timer(2).timeout
	await shot("combat_03_enemy")
	game.hud.hide()
	game.overview.position=enemy.position+Vector3(3.0,2.2,3.5)
	game.overview.look_at(enemy.position+Vector3.UP*1.0)
	game.overview.current=true
	game._pause()
	await shot("combat_04_soldier")
	game.hud.show()
	game._resume()
	for bot: Node3D in game.bots: bot.active=false
	game.player.take_damage(35,enemy.position,enemy)
	await shot("combat_05_health")
	game.player.start_heal()
	await shot("combat_06_healing")
	game._pause()
	await shot("combat_07_pause")
	game._resume()
	for bot: Node3D in game.bots: bot.active=false
	game.elapsed=195
	await shot("combat_08_zone")
	game.player.take_damage(1000,enemy.position,enemy)
	await shot("combat_09_defeat")
	game._restart()
	for bot: Node3D in game.bots: bot.take_damage(1000,Vector3.ZERO,null)
	await shot("combat_10_victory")
	game._restart()
	for bot: Node3D in game.bots: bot.active=false
	game.player._set_stance(game.player.Stance.PRONE)
	await shot("combat_11_prone")
	game.player._set_stance(game.player.Stance.STAND)
	Input.action_press("lean_right")
	await shot("combat_12_lean")
	Input.action_release("lean_right")
	var file:=FileAccess.open("res://tests/combat_render.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(samples,"  "))
	file.close()
	print("COMBAT_TOUR_COMPLETE")
	get_tree().quit()
