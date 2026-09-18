extends Node

var checks: Array[Dictionary]=[]
func check(name: String,ok: bool) -> void:
	checks.append({"name":name,"pass":ok})
	print(("PASS " if ok else "FAIL ")+name)

func frames(n: int=5) -> void:
	for i: int in range(n): await get_tree().physics_frame

func run(game: Node3D) -> void:
	await frames(15)
	game._start()
	check("settings panel wired",is_instance_valid(game.course.settings))
	check("scene model details created",game.details.get_child_count()>0)
	check("human target articulated",game.world.targets[0]._limbs.size()==4)
	var target: Node3D=game.world.targets[0]
	target.receive_hit(34,target.global_position+Vector3(0,1.85,0))
	check("headshot one-shot mannequin",target.down and target.last_headshot)
	target.reset_target()
	game.course.start_course()
	await frames(10)
	check("course starts at village",game.course.running and game.course.stage==0 and game.course.stage_targets.size()==3)
	check("course has 180 second standard limit",game.course.remaining>178 and game.course.remaining<180)
	var left: float=game.course.remaining
	var clock: float=game.course.stage_targets[1]._clock
	game._pause()
	await frames(12)
	check("course timer pauses",is_equal_approx(left,game.course.remaining))
	check("course mannequin pauses",is_equal_approx(clock,game.course.stage_targets[1]._clock))
	game._resume()
	for stage: int in range(3):
		var items: Array=game.course.stage_targets.duplicate()
		for t: Node3D in items: t.receive_hit(100,t.global_position+Vector3(0,1.2,0))
		await frames(3)
		if stage<2: check("course advances to stage %d" % (stage+2),game.course.stage==stage+1 and game.course.running)
	check("course completion shows result",not game.course.running and game.course.result_visible and game.paused)
	check("course all nine counted",game.course.cleared==9 and game.course.points>=900)
	game.course.start_course()
	await frames(3)
	check("retry starts clean",game.course.stage==0 and game.course.cleared==0 and game.course.route_targets.size()==3 and not game.course.result_visible)
	game.course.remaining=0.01
	await frames(5)
	check("course timeout produces result",game.course.result_visible and game.paused and not game.course.running)
	game._restart()
	await frames(3)
	check("free mode clears course actors",game.course.route_targets.is_empty() and not game.course.result_visible and not game.paused)
	var previous: float=game.player.base_fov
	game.player.base_fov=90
	await frames(35)
	check("configured fov applied",game.player.camera.fov>89)
	game.player.base_fov=previous
	game.player.view_motion=false
	check("view motion preference exposed",not game.player.view_motion)
	game.player.view_motion=true
	game.player.headshots=3
	game.player.reset_loadout()
	check("headshots reset with loadout",game.player.headshots==0)
	game.course.difficulty=2
	game.course.start_course()
	await frames(2)
	check("hard mode changes limit and motion",game.course.remaining<135 and game.course.stage_targets[1].move_speed>1.5)
	game._restart()
	game._teleport(Vector3(13,0,-28.5),0)
	await frames(20)
	var mannequin: Node3D=game.world.targets[1]
	mannequin.reset_target()
	var offset: Vector3=mannequin.global_position+Vector3(0,1.30,0)-game.player.camera.global_position
	game.player._pitch=atan2(offset.y,Vector2(offset.x,offset.z).length())
	game.player._recoil=0
	await frames(3)
	var obstruction:=StaticBody3D.new()
	var collision:=CollisionShape3D.new()
	var shape:=BoxShape3D.new()
	shape.size=Vector3(0.25,0.42,0.10)
	collision.shape=shape
	obstruction.add_child(collision)
	game.add_child(obstruction)
	obstruction.global_position=game.player._muzzle.global_position+Vector3(0,0,-0.25)
	await frames(3)
	game.player.aiming=true
	game.player._fire()
	check("muzzle obstruction blocks damage",mannequin.health==100)
	obstruction.queue_free()
	await frames(3)
	game.player._recoil=0
	game.player.aiming=true
	game.player._fire()
	check("unobstructed shot reaches mannequin",mannequin.health<100)
	var prefs: Control=game.course.settings
	var saved: Dictionary=prefs.get_values()
	prefs._set_values({"sensitivity":1.7,"fov":88.0,"volume":0.0,"motion":false})
	prefs._apply_values()
	check("settings apply sensitivity and fov",is_equal_approx(game.player.mouse_sensitivity,1.7) and is_equal_approx(game.player.base_fov,88))
	check("zero volume mutes master",AudioServer.is_bus_mute(0))
	prefs._set_values(saved)
	prefs._apply_values()
	await frames(5)
	var failures: int=0
	for c: Dictionary in checks:
		if not c.pass: failures+=1
	var f:=FileAccess.open("res://tests/upgrade_results.json",FileAccess.WRITE)
	f.store_string(JSON.stringify({"checks":checks,"passed":checks.size()-failures,"failed":failures},"  "))
	f.close()
	print("UPGRADE_RESULT %d/%d" % [checks.size()-failures,checks.size()])
	get_tree().quit(1 if failures else 0)
