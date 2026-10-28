extends SceneTree

func _initialize() -> void:
	var scene: Node = load("res://main.tscn").instantiate()
	root.add_child(scene)
	call_deferred("_run")

func _run() -> void:
	var main: Node = root.get_node("CoastlineProtocol")
	var guard: int = 0
	while main.get("initializing") == true and guard < 20000:
		await process_frame
		guard += 1
	var nav: Node = main.get("nav")
	if nav == null:
		push_error("bake: nav missing")
		quit(1)
		return
	print("BAKE nodes=", nav.get("ids").size(), " guard=", guard)
	nav.call("save_prebaked", "res://assets/nav_graph.json")
	print("BAKE saved")
	quit()
