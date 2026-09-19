extends Node3D

const TargetScript = preload("res://scripts/target.gd")
var game: Node3D
var running: bool = false
var remaining: float = 180.0
var stage: int = 0
var cleared: int = 0
var points: int = 0
var course_best: int = 0
var difficulty: int = 1
var result_visible: bool = false
var route_targets: Array[Node3D] = []
var stage_targets: Array[Node3D] = []
var settings: Control
var menu_controls: Control
var result_panel: PanelContainer
var result_text: Label
var _marker: Label3D
var _font: FontFile
var _advancing: bool = false
var _elapsed: float = 0
const STAGE_NAMES: Array[String] = ["01 / 房区清剿", "02 / 仓库突入", "03 / 山坡决胜"]
const DESTINATIONS: Array[Vector3] = [Vector3(-23,0,25),Vector3(34,0,-4),Vector3(-31,0,-81)]

func setup(owner_game: Node3D) -> void:
	game = owner_game
	_font = load("res://assets/simhei.ttf")
	var surface: Control = game.hud.get_node("TacticalHUD")
	menu_controls = Control.new()
	menu_controls.mouse_filter = Control.MOUSE_FILTER_IGNORE
	surface.add_child(menu_controls)
	var title := Label.new()
	title.position=Vector2(475,57)
	title.text="行动模式"
	title.add_theme_font_override("font",_font)
	title.add_theme_font_size_override("font_size",21)
	title.add_theme_color_override("font_shadow_color",Color.BLACK)
	title.add_theme_constant_override("shadow_offset_x",1)
	title.add_theme_constant_override("shadow_offset_y",2)
	menu_controls.add_child(title)
	_button(menu_controls,"三段清靶闯关",Vector2(475,100),Vector2(174,46),start_course)
	_button(menu_controls,"60 秒靶场挑战",Vector2(663,100),Vector2(174,46),func() -> void:
		abort()
		game.started=true
		game._resume()
		game._begin_challenge())
	var mode:=OptionButton.new()
	mode.position=Vector2(850,100)
	mode.size=Vector2(155,46)
	mode.add_theme_font_override("font",_font)
	mode.add_item("休闲",0)
	mode.add_item("标准",1)
	mode.add_item("硬核",2)
	mode.selected=1
	mode.item_selected.connect(func(index: int) -> void: difficulty=index)
	menu_controls.add_child(mode)
	result_panel=PanelContainer.new()
	result_panel.position=Vector2(475,185)
	result_panel.size=Vector2(475,350)
	var style:=StyleBoxFlat.new()
	style.bg_color=Color(0.025,0.047,0.056,0.96)
	style.border_color=Color("65dedc")
	style.set_border_width_all(1)
	style.content_margin_left=24
	style.content_margin_right=24
	style.content_margin_top=22
	style.content_margin_bottom=22
	result_panel.add_theme_stylebox_override("panel",style)
	surface.add_child(result_panel)
	var box:=VBoxContainer.new()
	box.add_theme_constant_override("separation",18)
	result_panel.add_child(box)
	result_text=Label.new()
	result_text.add_theme_font_override("font",_font)
	result_text.add_theme_font_size_override("font_size",19)
	box.add_child(result_text)
	var retry:=Button.new()
	retry.text="再战一局"
	retry.custom_minimum_size=Vector2(0,44)
	retry.add_theme_font_override("font",_font)
	retry.pressed.connect(start_course)
	box.add_child(retry)
	var free:=Button.new()
	free.text="返回自由训练"
	free.custom_minimum_size=Vector2(0,40)
	free.add_theme_font_override("font",_font)
	free.pressed.connect(func() -> void: game._restart())
	box.add_child(free)
	result_panel.hide()
	_marker=Label3D.new()
	_marker.font=_font
	_marker.font_size=36
	_marker.pixel_size=0.018
	_marker.modulate=Color("65dedc")
	_marker.billboard=BaseMaterial3D.BILLBOARD_ENABLED
	_marker.no_depth_test=true
	_marker.outline_size=8
	add_child(_marker)
	_marker.hide()
	var cfg:=ConfigFile.new()
	if cfg.load("user://course_records.cfg")==OK: course_best=int(cfg.get_value("course","best",0))

func _button(parent: Control,text: String,pos: Vector2,size: Vector2,callback: Callable) -> void:
	var b:=Button.new()
	b.text=text
	b.position=pos
	b.size=size
	b.add_theme_font_override("font",_font)
	b.add_theme_font_size_override("font_size",16)
	b.pressed.connect(callback)
	parent.add_child(b)

func _process(delta: float) -> void:
	if not is_instance_valid(game): return
	menu_controls.visible=not game.started or game.paused
	if is_instance_valid(settings): settings.visible=menu_controls.visible and not result_visible
	result_panel.visible=result_visible and game.paused
	_marker.visible=running and not game.paused
	if not running or game.paused: return
	remaining=maxf(0,remaining-delta)
	_elapsed+=delta
	var distance: float=Vector2(game.player.position.x-DESTINATIONS[stage].x,game.player.position.z-DESTINATIONS[stage].z).length()
	_marker.visible=distance>15.0
	_marker.pixel_size=clampf(distance*0.0002,0.004,0.018)
	var count: int=0
	for target: Node3D in stage_targets:
		if not target.down: count+=1
	game.challenge_label.text="%s   %d 秒   %04d 分\n剩余 %d 人形靶 · 目标 %.0f m · 共 %d / 9" % [STAGE_NAMES[stage],ceili(remaining),points,count,distance,cleared]
	if remaining<=0: finish(false)

func start_course() -> void:
	game._restart()
	running=true
	remaining=[210.0,180.0,135.0][difficulty]
	_elapsed=0
	stage=0
	cleared=0
	points=0
	_advancing=false
	game.player.reserve=240
	game._teleport(Vector3(-23,0,31),0)
	_spawn_stage()
	game.hud.notify_message("清靶闯关开始 · 清空当前区域后前往下一点")

func _spawn_stage() -> void:
	stage_targets.clear()
	var positions: Array = [
		[Vector3(-23,0,21.5),Vector3(-38,0,25),Vector3(-26,0,-0.5)],
		[Vector3(34,0,-4),Vector3(39,0,-17),Vector3(28,0,-20)],
		[Vector3(-28,0,-73),Vector3(-34,0,-87),Vector3(-39,0,-93)]
	]
	for i: int in range(3):
		var t: Node3D=TargetScript.new()
		var p: Vector3=positions[stage][i]
		p.y=game.world.get_height(p.x,p.z)+0.23
		t.position=p
		t.auto_respawn=false
		t.moving=difficulty>0 and i==1
		t.move_distance=0.7
		t.move_speed=1.0 if difficulty==1 else 1.65
		add_child(t)
		t.defeated.connect(_defeated)
		route_targets.append(t)
		stage_targets.append(t)
	var destination: Vector3=DESTINATIONS[stage]
	_marker.position=Vector3(destination.x,game.world.get_height(destination.x,destination.z)+5,destination.z)
	_marker.text=STAGE_NAMES[stage]
	_advancing=false

func _defeated(target: Node3D) -> void:
	if not running or not stage_targets.has(target): return
	cleared+=1
	points+=150 if target.last_headshot else 100
	var all_down: bool=true
	for t: Node3D in stage_targets:
		if not t.down: all_down=false
	if all_down and not _advancing:
		_advancing=true
		call_deferred("_advance")

func _advance() -> void:
	if not running: return
	if stage==2:
		finish(true)
		return
	stage+=1
	game.player.reserve+=60
	game.hud.notify_message("区域完成！补充 60 发 · 下一站："+STAGE_NAMES[stage])
	_spawn_stage()

func finish(success: bool) -> void:
	if not running: return
	running=false
	_marker.hide()
	if success: points+=int(remaining)*5
	var rating: String="S" if success and points>=1600 else ("A" if success and points>=1200 else ("B" if success else "未完成"))
	if success and points>course_best:
		course_best=points
		if not "--smoke-test" in OS.get_cmdline_user_args() and not "--upgrade-test" in OS.get_cmdline_user_args() and not "--capture-tour" in OS.get_cmdline_user_args():
			var cfg:=ConfigFile.new()
			cfg.set_value("course","best",course_best)
			cfg.save("user://course_records.cfg")
	result_text.text="%s  /  %s\n\n得分  %04d     最佳  %04d\n击倒  %d / 9     爆头  %d\n用时  %.1f 秒     命中率  %.0f%%" % ["行动完成" if success else "时间到",rating,points,course_best,cleared,game.player.headshots,_elapsed,game.player.get_accuracy()]
	result_visible=true
	game._pause()

func abort() -> void:
	running=false
	result_visible=false
	_advancing=false
	for t: Node3D in route_targets:
		if is_instance_valid(t): t.queue_free()
	route_targets.clear()
	stage_targets.clear()
	if is_instance_valid(_marker): _marker.hide()
	if is_instance_valid(result_panel): result_panel.hide()

func get_height(x: float,z: float) -> float:
	return game.world.get_height(x,z)+0.23
