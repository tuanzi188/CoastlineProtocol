extends Node
var checks: Array[Dictionary]=[]

func check(name: String,value: bool,detail: String="") -> void:
	checks.append({"name":name,"pass":value,"detail":detail})
	print(("PASS " if value else "FAIL ")+name+" "+detail)

func wait(seconds: float) -> void:
	await get_tree().create_timer(seconds).timeout

func freeze_bots(game: Node3D) -> void:
	for bot: Node3D in game.bots: bot.active=false

func run(game: Node3D) -> void:
	check("ground navigation generated",game.nav.ids.size()>1000,str(game.nav.ids.size()))
	check("no training targets in scene",get_tree().get_nodes_in_group("training_targets").is_empty())
	check("legacy mode keys removed",not InputMap.has_action("course") and not InputMap.has_action("travel") and not InputMap.has_action("challenge"))
	game._start()
	await wait(0.3)
	freeze_bots(game)
	check("single match starts with nine survivors",game.bots.size()==8 and game.alive_count==9 and game.running)
	check("survival loadout",game.player.health==100 and game.player.armor==50 and game.player.medkits==2)
	game.player.take_damage(20,Vector3.ZERO,null)
	check("armor absorbs partial damage",is_equal_approx(game.player.health,87) and is_equal_approx(game.player.armor,43))
	game.player.start_heal()
	await wait(0.25)
	check("healing begins",game.player.healing and game.player.heal_left>2)
	game.player.take_damage(10,Vector3.ZERO,null)
	check("damage interrupts without consuming medkit",not game.player.healing and game.player.medkits==2)
	game.player.start_heal()
	await wait(3.2)
	check("healing completes and consumes one",game.player.health==100 and game.player.medkits==1 and not game.player.healing)
	game.player.health=60
	game.player.start_heal()
	Input.action_press("fire")
	await wait(0.06)
	Input.action_release("fire")
	check("fire input interrupts healing",not game.player.healing and game.player.medkits==1)
	game.player.reset_loadout()
	var ammo: int=game.player.reserve
	game.player.reserve=0
	await wait(0.2)
	check("no infinite ammo regeneration",game.player.reserve==0)
	game.player.reserve=ammo
	var item: Node3D=game.loot[0]
	game.player.position=item.position+Vector3(0,0.1,1)
	await wait(0.2)
	game._update_loot()
	check("nearby supply prompt",is_instance_valid(game._closest_loot))
	var loot_count: int=game.loot.size()
	game._collect_loot()
	check("loot grants and removes once",game.loot.size()==loot_count-1 and game.player.reserve==240 and game.player.medkits==3)
	game._collect_loot()
	check("loot cannot double collect",game.player.reserve==240)
	game.player.position=Vector3(1,game.world.get_height(1,32)+0.1,32)
	await wait(0.3)
	var p: Vector3=game.player.position
	Input.action_press("move_forward")
	await wait(1)
	Input.action_release("move_forward")
	check("walking retained",p.distance_to(game.player.position)>4)
	var paths: PackedVector3Array=game.nav.path(Vector3(-35,3,21),Vector3(-23,3,29))
	check("building route has waypoints",paths.size()>4,str(paths.size()))
	check("safe zone contracts",game.zone_radius_at(90)<132 and game.zone_radius_at(240)==8)
	var elapsed: float=game.elapsed
	game._pause()
	var health: float=game.player.health
	game.player.take_damage(50,Vector3.ZERO,null)
	await wait(0.25)
	check("pause freezes timer and damage",is_equal_approx(game.elapsed,elapsed) and game.player.health==health)
	game._resume()
	freeze_bots(game)
	var bot: Node3D=game.bots[0]
	bot.position=game.nav.nearest(Vector3(4,3,-15))+Vector3.UP*0.15
	game.player.position=Vector3(1,game.world.get_height(1,6)+0.15,6)
	game.player.health=100
	game.player.armor=50
	bot.rotation.y=PI
	bot._rng.seed=42
	bot.active=true
	await wait(0.1)
	check("AI sees unobstructed player",bot._can_see(game.player))
	var wall:=StaticBody3D.new()
	var cs:=CollisionShape3D.new()
	var wall_shape:=BoxShape3D.new()
	wall_shape.size=Vector3(12,5,0.4)
	cs.shape=wall_shape
	wall.add_child(cs)
	wall.position=Vector3(2,5,-5)
	game.add_child(wall)
	await wait(0.1)
	check("AI cannot see through wall",not bot._can_see(game.player))
	bot.target=game.player
	var shots: int=bot.shots_fired
	bot._fire()
	check("AI cannot shoot through wall",bot.shots_fired==shots)
	wall.queue_free()
	await wait(0.1)
	bot.hear_shot(game.player.position,game.player)
	var bot_start: Vector3=bot.position
	await wait(5.0)
	check("AI moves independently",bot_start.distance_to(bot.position)>1,str(bot.position))
	check("AI acquires target and fires",bot.shots_fired>0,"shots=%d state=%s" % [bot.shots_fired,bot.state])
	await wait(3.0)
	check("AI shots can damage player",game.player.health<100,"hp=%.1f" % game.player.health)
	bot.active=false
	var foe: Node3D=game.bots[1]
	game.player.active=false
	bot.position=Vector3(1,game.world.get_height(1,8)+0.1,8)
	foe.position=Vector3(1,game.world.get_height(1,16)+0.1,16)
	bot.rotation.y=PI
	bot.target=foe
	bot.active=true
	foe.active=true
	await wait(0.1)
	bot._scan()
	check("bots acquire other bots",bot.target==foe)
	var foe_health: int=foe.health
	for i: int in range(4): bot._fire()
	check("bots can damage each other",foe.health<foe_health)
	bot.active=false
	foe.active=false
	game.player.active=true
	game.player.active=false
	bot.position=game.nav.nearest(Vector3(-23,3,30))+Vector3.UP*0.12
	bot.velocity=Vector3.ZERO
	bot.target=null
	bot._visible_target=false
	bot._memory_left=10
	bot._last_seen=Vector3(-23,3.1,21)
	bot._path_left=0
	bot.active=true
	await wait(3.0)
	check("AI navigates through house doorway",bot.position.z<25,str(bot.position))
	bot.active=false
	bot.ammo=0
	bot._reload_left=0
	bot.active=true
	await wait(0.1)
	check("AI starts real reload",bot._reload_left>1.7)
	await wait(2.2)
	check("AI reload replenishes magazine",bot.ammo==24 and bot._reload_left==0)
	bot.active=false
	game.player.active=true
	bot.position=Vector3(1,game.world.get_height(1,8)+0.1,8)
	foe.position=Vector3(80,game.world.get_height(80,-70)+0.1,-70)
	game.player.position=Vector3(1,game.world.get_height(1,21)+0.1,21)
	game.player.rotation.y=0
	await wait(0.15)
	var delta_aim: Vector3=bot.position+Vector3.UP*1.2-game.player.camera.global_position
	game.player._pitch=atan2(delta_aim.y,Vector2(delta_aim.x,delta_aim.z).length())
	game.player._recoil=0
	game.player._recoil_yaw=0
	game.player._burst=0
	game.player._recovery_left=0
	game.player.lean=0
	game.player.aiming=true
	game.player._fire()
	check("player hits AI with weapon ray",bot.health<100 and game.player.hits>0)
	var before: int=bot.health
	bot.set_meta("last_attacker",game.player)
	var killed: bool=bot.receive_hit(34,bot.position+Vector3.UP*1.20)
	check("enemy receives real damage",not killed and bot.health<before)
	bot.receive_hit(100,bot.position+Vector3.UP*1.80)
	await wait(0.15)
	check("elimination removes survivor and drops loot",bot.dead and game.alive_count==8 and game.loot.size()==loot_count)
	var remain: int=game.alive_count
	bot.receive_hit(100,bot.position+Vector3.UP)
	check("dead enemy cannot eliminate twice",game.alive_count==remain)
	await wait(0.4)
	check("enemy does not respawn",bot.dead)
	game.player.health=1
	game.player.take_damage(100,Vector3.ZERO,null)
	await wait(0.1)
	check("player death shows defeat",game.finished and not game.won and game.player.dead and not game.running)
	game._restart()
	freeze_bots(game)
	await wait(0.1)
	check("restart restores survivors and clears death",game.alive_count==9 and not game.finished and not game.player.dead and game.player.health==100)
	for enemy: Node3D in game.bots: enemy.take_damage(1000,Vector3.ZERO,game.player)
	await wait(0.15)
	check("last survivor wins",game.finished and game.won and game.alive_count==1)
	game._restart()
	freeze_bots(game)
	game.zone_radius=8
	game.elapsed=240
	game.player.position=Vector3(100,game.world.get_height(100,30)+0.3,30)
	game._zone_clock=1
	game._update_zone(0.1)
	check("outside zone loses health",game.player.health<100)
	var failures: int=0
	for c: Dictionary in checks:
		if not c.pass: failures+=1
	var output:=FileAccess.open("res://tests/combat_results.json",FileAccess.WRITE)
	output.store_string(JSON.stringify({"passed":checks.size()-failures,"failed":failures,"checks":checks},"  "))
	output.close()
	print("COMBAT_RESULT %d/%d" % [checks.size()-failures,checks.size()])
	get_tree().quit(1 if failures else 0)
