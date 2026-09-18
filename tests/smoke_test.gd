extends Node

var checks: Array[Dictionary] = []
var game: Node3D

func check(label: String,condition: bool,detail: String = "") -> void:
	checks.append({"name":label,"pass":condition,"detail":detail})
	print(("PASS " if condition else "FAIL ")+label+" "+detail)

func settle(frames: int = 10) -> void:
	for i: int in range(frames): await get_tree().physics_frame

func run(root: Node3D) -> void:
	game=root
	await settle(15)
	check("world generated",game.world.get_child_count()>200,str(game.world.get_child_count()))
	check("six targets",game.world.targets.size()==6)
	check("menu initially open",not game.started and game.hud._menu_visible)
	game._start()
	await settle(20)
	check("start enables controls",game.player.active and not game.hud._menu_visible)
	check("spawn grounded",game.player.is_on_floor(),str(game.player.global_position))
	var start: Vector3=game.player.global_position
	Input.action_press("move_forward")
	await settle(60)
	Input.action_release("move_forward")
	await settle(8)
	var walked: float=start.distance_to(game.player.global_position)
	check("walk forward",walked>4.0 and walked<7.0,str(walked))
	game._teleport(Vector3(1,0,32),0)
	await settle(15)
	start=game.player.global_position
	Input.action_press("move_forward")
	Input.action_press("sprint")
	await settle(60)
	Input.action_release("move_forward")
	Input.action_release("sprint")
	await settle(8)
	check("sprint faster than walk",start.distance_to(game.player.global_position)>walked+1.8)
	game._teleport(Vector3(1,0,32),0)
	await settle(15)
	var base_y: float=game.player.position.y
	Input.action_press("jump")
	await settle(8)
	Input.action_release("jump")
	check("jump leaves floor",game.player.position.y>base_y+0.3)
	await settle(50)
	check("jump lands safely",game.player.is_on_floor())
	Input.action_press("crouch")
	await settle(10)
	check("crouch changes capsule",game.player.crouching and game.player._capsule.height<1.3)
	Input.action_release("crouch")
	await settle(10)
	check("uncrouch restores capsule",not game.player.crouching and game.player._capsule.height>1.7)
	Input.action_press("aim")
	await settle(30)
	check("aim narrows field of view",game.player.aiming and game.player.camera.fov<56)
	Input.action_release("aim")
	await settle(30)
	check("aim release restores view",game.player.camera.fov>76)
	game.player.reset_loadout()
	game._teleport(Vector3(7,0,-28.5),0)
	await settle(15)
	var target: Node3D=game.world.targets[0]
	var aim_point: Vector3=target.global_position+Vector3(0,1.35,0.08)
	var diff: Vector3=aim_point-game.player.camera.global_position
	game.player.rotation.y=atan2(-diff.x,-diff.z)
	game.player._pitch=atan2(diff.y,Vector2(diff.x,diff.z).length())
	game.player.aiming=true
	for i: int in range(3):
		game.player._recoil=0
		game.player.aiming=true
		game.player._fire()
	await settle(2)
	check("hitscan damages and drops target",target.down and game.player.kills==1,"hits=%d kills=%d" %[game.player.hits,game.player.kills])
	check("ammo decremented",game.player.ammo==27)
	game.player._start_reload()
	check("reload begins",game.player.reloading)
	await get_tree().create_timer(2.0).timeout
	check("reload finishes with reserve accounting",game.player.ammo==30 and game.player.reserve==177 and not game.player.reloading)
	await get_tree().create_timer(2.2).timeout
	check("target automatically resets",not target.down and target.health==100)
	game._pause()
	var before: int=game.player.ammo
	game.player._fire()
	check("paused fire disabled",game.player.ammo==before and not game.player.active)
	game._resume()
	game._begin_challenge()
	await settle(5)
	check("challenge starts and teleports",game.challenge_running and game.challenge_left>58 and absf(game.player.position.z+28.5)<1)
	game._on_hit(true)
	game._on_hit(true)
	check("combo scoring",game.score==245 and game.combo==2,str(game.score))
	game._pause()
	var timer_before: float=game.challenge_left
	await get_tree().create_timer(0.2).timeout
	check("pause freezes challenge timer",is_equal_approx(game.challenge_left,timer_before))
	game._resume()
	game.challenge_left=0.01
	await settle(4)
	check("challenge completes",game.challenge_finished and not game.challenge_running)
	game._restart()
	check("restart resets stats",game.player.shots_fired==0 and game.player.ammo==30 and not game.challenge_running)
	# Traverse the actual doorway under player movement, not a teleport into the room.
	game._teleport(Vector3(-23,0,29),0)
	await settle(15)
	Input.action_press("move_forward")
	await settle(95)
	Input.action_release("move_forward")
	await settle(5)
	check("house doorway walkable",game.player.position.z<25 and game.player.position.z>18,str(game.player.position))
	game._teleport(Vector3(-28.3,0,16.88),-PI/2)
	await settle(15)
	Input.action_press("move_forward")
	await settle(102)
	Input.action_release("move_forward")
	await settle(5)
	check("second-floor stairs climbable",game.player.position.y>5.8,str(game.player.position))
	# House wall must stop the player rather than allowing movement through it.
	game._teleport(Vector3(-31,0,21),-PI/2)
	await settle(15)
	Input.action_press("move_forward")
	await settle(60)
	Input.action_release("move_forward")
	check("house wall collision",game.player.position.x < -29.1,str(game.player.position))
	game._teleport(Vector3(34,0,7),0)
	await settle(15)
	Input.action_press("move_forward")
	await settle(90)
	Input.action_release("move_forward")
	await settle(5)
	check("warehouse entry walkable",game.player.position.z<0,str(game.player.position))
	game._teleport(Vector3(-31,0,-81),0)
	await settle(20)
	check("hill collision and elevation",game.player.is_on_floor() and game.player.position.y>18,str(game.player.position))
	game._teleport(Vector3(44,0,70),PI)
	await settle(10)
	game.player.position=Vector3(0,-2,110)
	await settle(6)
	check("water boundary recovers player",game.player.position.z<100 and game.player.position.y>0)
	var failures: int=0
	for item: Dictionary in checks:
		if not item["pass"]: failures+=1
	var report: Dictionary={"engine":Engine.get_version_info(),"checks":checks,"passed":checks.size()-failures,"failed":failures}
	var file:=FileAccess.open("res://tests/test_results.json",FileAccess.WRITE)
	file.store_string(JSON.stringify(report,"  "))
	file.close()
	print("SMOKE_RESULT: %d/%d passed" %[checks.size()-failures,checks.size()])
	get_tree().quit(1 if failures>0 else 0)
