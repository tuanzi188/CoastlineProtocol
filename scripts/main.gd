extends Node3D

const WorldScript = preload("res://scripts/world.gd")
const PlayerScript = preload("res://scripts/player.gd")
const HUDScript = preload("res://scripts/hud.gd")
const SettingsScript = preload("res://scripts/settings_panel.gd")
const DetailsScript = preload("res://scripts/scene_detail.gd")
const EnemyScript = preload("res://scripts/enemy.gd")
const NavigationScript = preload("res://scripts/combat_navigation.gd")
const QualityScript = preload("res://scripts/mobile_quality.gd")
const ZoneWallShader = preload("res://assets/zone_wall.gdshader")
var mobile_mode: bool=false
var mobile_controls: Control
var render_profile: Dictionary={}
var world: Node3D
var player: CharacterBody3D
var hud: CanvasLayer
var settings: Control
var details: Node3D
var nav: Node
var overview: Camera3D
var bots: Array[Node3D]=[]
var loot: Array[Node3D]=[]
var started: bool=false
var running: bool=false
var paused: bool=false
var finished: bool=false
var won: bool=false
var alive_count: int=9
var elapsed: float=0.0
var zone_center:=Vector3(0,0,-8)
var zone_radius: float=132.0
var zone_next_in: float=60.0
var initializing: bool=true
var match_id: int=0
var _zone: MeshInstance3D
var _zone_clock: float=0
var _zone_warned: bool=false
var _loot_hint: Label
var _status: Label
var _closest_loot: Node3D
var _last_zone: String=""
var _test_mode: bool=false
var _shot_lock: float=0

func _ready() -> void:
	_test_mode="--combat-test" in OS.get_cmdline_user_args()
	mobile_mode=OS.has_feature("android") or OS.has_feature("ios") or "--mobile-preview" in OS.get_cmdline_user_args()
	_input_map()
	if mobile_mode:
		InputMap.action_erase_events("fire")
		InputMap.action_erase_events("aim")
		if "--mobile-preview" in OS.get_cmdline_user_args(): Input.emulate_touch_from_mouse=true
	world=WorldScript.new()
	world.name="Island"
	add_child(world)
	details=DetailsScript.new()
	add_child(details)
	details.build(world)
	player=PlayerScript.new()
	player.name="Player"
	add_child(player)
	player.position=Vector3(1,world.get_height(1,32)+0.2,32)
	player.active=false
	overview=Camera3D.new()
	overview.position=Vector3(89,66,118)
	overview.fov=55
	add_child(overview)
	overview.look_at(Vector3(-8,4,4))
	overview.current=true
	hud=HUDScript.new()
	add_child(hud)
	hud.setup(player,world)
	hud.game=self
	hud.start_requested.connect(_start)
	hud.resume_requested.connect(_resume)
	hud.restart_requested.connect(_restart)
	hud.quit_requested.connect(func() -> void: get_tree().quit())
	player.target_hit.connect(hud.notify_hit)
	player.hit_confirmed.connect(_on_hit)
	player.damaged.connect(hud.notify_damage)
	player.died.connect(_player_died)
	player.shot_fired.connect(_player_shot)
	hud.show_menu()
	settings=SettingsScript.new()
	hud.get_node("TacticalHUD").add_child(settings)
	settings.setup(player)
	settings.visible=true
	_build_status()
	if mobile_mode:
		mobile_controls=preload("res://scripts/mobile_controls.gd").new()
		hud.get_node("TacticalHUD").add_child(mobile_controls)
		mobile_controls.setup(self)
		_loot_hint.position=Vector2(365,501)
		_loot_hint.size=Vector2(470,34)
	# Distance culling is not a mobile-only concern: the island renders the same
	# props for every tier, so desktop and web borrow the cheap half of the cut.
	render_profile=QualityScript.apply(self,"mobile" if mobile_mode else "desktop")
	_build_zone()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	nav=NavigationScript.new()
	add_child(nav)
	call_deferred("_prepare")

func _prepare() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var excluded: Array[RID]=[player.get_rid()]
	await nav.build(world,excluded)
	initializing=false
	_status.text="单人生存  /  你 + 8 名 AI\n听枪声、找掩体，留意安全区"
	if _test_mode:
		var test: Node=load("res://tests/combat_test.gd").new()
		add_child(test)
		test.call_deferred("run",self)
	if "--combat-tour" in OS.get_cmdline_user_args():
		var tour: Node=load("res://tests/combat_tour.gd").new()
		add_child(tour)
		tour.call_deferred("run",self)
	if "--combat-ui" in OS.get_cmdline_user_args():
		var test: Node=load("res://tests/combat_ui.gd").new()
		add_child(test)
		test.call_deferred("run",self)

func _input_map() -> void:
	var keys: Dictionary={"move_forward":KEY_W,"move_back":KEY_S,"move_left":KEY_A,"move_right":KEY_D,"jump":KEY_SPACE,"sprint":KEY_SHIFT,"crouch":KEY_C,"prone":KEY_Z,"lean_left":KEY_Q,"lean_right":KEY_E,"reload":KEY_R,"pause":KEY_ESCAPE,"heal":KEY_H,"interact":KEY_F,"fullscreen":KEY_F11}
	for action: String in keys:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var ev:=InputEventKey.new()
		ev.physical_keycode=keys[action]
		InputMap.action_add_event(action,ev)
	for action: String in ["fire","aim"]:
		if not InputMap.has_action(action): InputMap.add_action(action)
		var ev:=InputEventMouseButton.new()
		ev.button_index=MOUSE_BUTTON_LEFT if action=="fire" else MOUSE_BUTTON_RIGHT
		InputMap.action_add_event(action,ev)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("fullscreen"):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED if DisplayServer.window_get_mode()==DisplayServer.WINDOW_MODE_FULLSCREEN else DisplayServer.WINDOW_MODE_FULLSCREEN)
	if event.is_action_pressed("pause") and started and not finished:
		if paused: _resume()
		else: _pause()
	if running and not paused and event.is_action_pressed("interact"): _collect_loot()

func _start() -> void:
	if initializing:
		_status.text="正在准备 AI 通行路径，请稍候…"
		return
	_restart()

func _restart() -> void:
	if initializing: return
	if is_instance_valid(mobile_controls): mobile_controls.release_all()
	running=false
	match_id+=1
	for bot: Node3D in bots:
		bot.active=false
		bot.collision_layer=0
		bot.queue_free()
	bots.clear()
	for item: Node3D in loot: item.queue_free()
	loot.clear()
	_closest_loot=null
	finished=false
	won=false
	elapsed=0
	zone_radius=132
	zone_next_in=60
	_zone_clock=0
	_zone_warned=false
	_last_zone=""
	player.process_mode=Node.PROCESS_MODE_INHERIT
	player.reset_loadout()
	player.position=Vector3(1,world.get_height(1,32)+0.25,32)
	player.rotation=Vector3.ZERO
	player._pitch=0
	player.velocity=Vector3.ZERO
	_spawn_bots()
	for p: Vector3 in [Vector3(-17,0,28),Vector3(18,0,12),Vector3(48,0,-3),Vector3(-48,0,-29),Vector3(-28,0,-70),Vector3(-23,0,23),Vector3(34,0,-6),Vector3(23,0,-22)]: _spawn_loot(p)
	started=true
	running=true
	hud.hide_result()
	_resume()
	hud.notify_message("行动开始 · 左侧移动 · 右侧滑屏瞄准" if mobile_mode else "行动开始 · 8 名对手 · H 治疗 · F 搜取补给")

func _spawn_bots() -> void:
	var spawns: Array[Vector3]=[Vector3(-16,0,6),Vector3(21,0,14),Vector3(-61,0,14),Vector3(51,0,-31),Vector3(-14,0,-50),Vector3(-63,0,-52),Vector3(64,0,34),Vector3(24,0,-82)]
	for i: int in range(spawns.size()):
		var bot: CharacterBody3D=EnemyScript.new()
		bot.game=self
		bot.bot_id=i
		bot.name="Survivor_%02d" % (i+1)
		bot.position=nav.nearest(spawns[i])+Vector3.UP*0.12
		add_child(bot)
		bots.append(bot)
		bot.eliminated.connect(_bot_eliminated)
	alive_count=bots.size()+1

func _resume() -> void:
	if finished: return
	paused=false
	running=started
	player.process_mode=Node.PROCESS_MODE_INHERIT
	player.active=true
	player.camera.current=true
	for bot: Node3D in bots:
		bot.process_mode=Node.PROCESS_MODE_INHERIT
		bot.active=not bot.dead
	hud.hide_menu()
	hud.set_active(true)
	settings.hide()
	_status.hide()
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE if mobile_mode else Input.MOUSE_MODE_CAPTURED

func _pause() -> void:
	if is_instance_valid(mobile_controls): mobile_controls.release_all()
	paused=true
	player.active=false
	player.velocity=Vector3.ZERO
	player._flash.visible=false
	player._muzzle_light.visible=false
	player.process_mode=Node.PROCESS_MODE_DISABLED
	for bot: Node3D in bots:
		bot.active=false
		bot.process_mode=Node.PROCESS_MODE_DISABLED
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	hud.show_menu(true)
	settings.visible=not finished
	_status.visible=not finished

func _process(delta: float) -> void:
	if not is_instance_valid(player): return
	_loot_hint.visible=running and not paused and not finished
	if not running or paused or finished: return
	elapsed+=delta
	_shot_lock=maxf(0,_shot_lock-delta)
	_update_zone(delta)
	_update_loot()
	if player.position.y<0.0 or absf(player.position.x)>155 or player.position.z < -156:
		player.fall_out_of_world()
	var region: String=world.get_zone(player.position)
	if region!=_last_zone:
		_last_zone=region
		if _shot_lock<=0: hud.notify_message(region)

func _player_shot() -> void:
	_shot_lock=2
	for bot: Node3D in bots:
		if not bot.dead: bot.hear_shot(player.global_position,player)

func _on_hit(killed: bool,headshot: bool,_point: Vector3) -> void:
	Audio.hit(killed,headshot)
	if killed: hud.notify_message("爆头淘汰" if headshot else "淘汰对手")

func _bot_eliminated(bot: Node3D,killer: Node) -> void:
	_spawn_loot(bot.position)
	if killer==player: _shot_lock=2
	_update_alive()
	if running and alive_count==1 and not player.dead:
		call_deferred("_finish",true,match_id)

func _player_died(_attacker: Node) -> void:
	_update_alive()
	Audio.eliminated()
	call_deferred("_finish",false,match_id)

func _update_alive() -> void:
	alive_count=0 if player.dead else 1
	for bot: Node3D in bots:
		if not bot.dead: alive_count+=1

func _finish(victory: bool,generation: int) -> void:
	# Settlement is deferred because `died` fires from inside a bullet's damage
	# pass. A restart issued in the same frame would otherwise be stamped out by
	# this call, leaving the fresh match paused with frozen bots.
	if finished or generation!=match_id: return
	finished=true
	won=victory
	running=false
	_pause()
	settings.hide()
	_status.hide()
	_loot_hint.hide()
	Audio.outcome(victory)
	hud.show_result(victory,player.kills,elapsed)

func _build_zone() -> void:
	_zone=MeshInstance3D.new()
	var cylinder:=CylinderMesh.new()
	cylinder.top_radius=1
	cylinder.bottom_radius=1
	cylinder.height=44
	cylinder.cap_top=false
	cylinder.cap_bottom=false
	cylinder.radial_segments=128
	_zone.mesh=cylinder
	var material:=ShaderMaterial.new()
	material.shader=ZoneWallShader
	_zone.material_override=material
	_zone.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_zone.position=zone_center+Vector3.UP*16
	_zone.scale=Vector3(zone_radius,1,zone_radius)
	add_child(_zone)

func _update_zone(delta: float) -> void:
	zone_radius=zone_radius_at(elapsed)
	if elapsed<60: zone_next_in=60-elapsed
	elif elapsed<240: zone_next_in=240-elapsed
	else: zone_next_in=0
	# One warning right as the ring starts moving; the player has to learn the
	# sound means "circle closing", not "you are standing in it".
	if not _zone_warned and elapsed>=60:
		_zone_warned=true
		Audio.zone_warning()
	_zone.scale=Vector3(zone_radius,1,zone_radius)
	_zone_clock+=delta
	if _zone_clock<1: return
	_zone_clock=0
	var damage: int=5 if elapsed<180 else 10
	if outside_zone(player.position):
		player.take_damage(damage,zone_center,null)
		Audio.zone_damage()
		hud.notify_message("你在安全区外！向蓝圈内移动")
	for bot: Node3D in bots:
		if not bot.dead and outside_zone(bot.position): bot.take_damage(damage,zone_center,null)

func zone_radius_at(time: float) -> float:
	if time<60: return 132
	return lerpf(132.0,8.0,clampf((time-60)/180,0,1))

func outside_zone(point: Vector3) -> bool:
	return Vector2(point.x-zone_center.x,point.z-zone_center.z).length()>zone_radius

func _spawn_loot(point: Vector3) -> void:
	var item:=Node3D.new()
	item.position=Vector3(point.x,world.get_height(point.x,point.z)+0.24,point.z)
	var mesh:=MeshInstance3D.new()
	var box:=BoxMesh.new()
	box.size=Vector3(0.64,0.42,0.48)
	mesh.mesh=box
	var material:=StandardMaterial3D.new()
	material.albedo_color=Color("937e54")
	material.roughness=0.85
	mesh.material_override=material
	item.add_child(mesh)
	var stripe:=MeshInstance3D.new()
	var strip:=BoxMesh.new()
	strip.size=Vector3(0.10,0.43,0.50)
	stripe.mesh=strip
	var metal:=StandardMaterial3D.new()
	metal.albedo_color=Color("d9c18d")
	stripe.material_override=metal
	item.add_child(stripe)
	add_child(item)
	loot.append(item)

func _update_loot() -> void:
	_closest_loot=null
	var distance: float=2.4
	for item: Node3D in loot:
		if not is_instance_valid(item): continue
		var d: float=player.position.distance_to(item.position)
		if d<distance:
			var q:=PhysicsRayQueryParameters3D.create(player.camera.global_position,item.position,1,[player.get_rid()])
			if get_world_3d().direct_space_state.intersect_ray(q).is_empty():
				distance=d
				_closest_loot=item
	if mobile_mode:
		_set_hint("点按「拾取」  弹药 +60 · 医疗包 +1 · 护甲 +20" if is_instance_valid(_closest_loot) else "")
	else:
		_set_hint("F  搜取补给  /  弹药 +60 · 医疗包 +1 · 护甲 +20" if is_instance_valid(_closest_loot) else "H 医疗包 ×%d  /  寻找掩体，警惕枪声" % player.medkits)

## Re-shaping a Label costs more than the string compare, and the hint is only
## ever read at a handful of distinct states per match.
func _set_hint(text: String) -> void:
	if _loot_hint.text != text:
		_loot_hint.text = text

func _collect_loot() -> void:
	if not is_instance_valid(_closest_loot): return
	player.collect_supply()
	Audio.pickup()
	loot.erase(_closest_loot)
	_closest_loot.queue_free()
	_closest_loot=null
	hud.notify_message("已搜取弹药、医疗包和护甲补给")

func _build_status() -> void:
	var font: FontFile = load("res://assets/simhei.ttf")
	_status=Label.new()
	_status.position=Vector2(475,94)
	_status.size=Vector2(420,60)
	_status.text="正在准备海岛与 AI 路径…"
	_status.add_theme_font_override("font",font)
	_status.add_theme_font_size_override("font_size",18)
	_status.add_theme_color_override("font_shadow_color",Color.BLACK)
	_status.add_theme_constant_override("shadow_offset_y",2)
	_status.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.get_node("TacticalHUD").add_child(_status)
	_loot_hint=Label.new()
	_loot_hint.position=Vector2(410,601)
	_loot_hint.size=Vector2(510,34)
	_loot_hint.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_loot_hint.add_theme_font_override("font",font)
	_loot_hint.add_theme_font_size_override("font_size",14)
	_loot_hint.add_theme_color_override("font_color",Color("edd7a8"))
	_loot_hint.add_theme_color_override("font_shadow_color",Color.BLACK)
	_loot_hint.add_theme_constant_override("shadow_offset_y",2)
	_loot_hint.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.get_node("TacticalHUD").add_child(_loot_hint)
	_loot_hint.hide()

func _notification(what: int) -> void:
	if what==NOTIFICATION_APPLICATION_FOCUS_OUT and running and not paused and not "--mobile-test" in OS.get_cmdline_user_args():
		_pause()
