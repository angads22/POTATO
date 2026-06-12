extends Node

# Captures /tmp/shot_menu.png, /tmp/shot_gameplay.png, /tmp/shot_farm.png
# and /tmp/shot_farm_night.png for visual review. Scenes are instantiated
# as children so this node survives the swap.
# Run under a virtual display:
#   xvfb-run godot --rendering-driver opengl3 --path . res://tests/Screenshot.tscn

var frames := 0
var phase := "menu"
var current

func _ready():
	current = load("res://scenes/MainMenu.tscn").instantiate()
	add_child(current)

func _process(_delta):
	frames += 1
	if phase == "menu" and frames == 40:
		_snap("/tmp/shot_menu.png")
		phase = "game"
		current.queue_free()
		GameManager.start_game("championship")
		GameManager.current_state.lives = 2
		GameManager.current_state.score = 4280
		GameManager.current_state.combo = 7
		current = load("res://scenes/Gameplay/GameplayScene.tscn").instantiate()
		add_child.call_deferred(current)
	elif phase == "game" and frames == 130:
		_snap("/tmp/shot_gameplay.png")
		phase = "farm"
		current.queue_free()
		GameManager.current_state.is_running = false
		SaveDataManager.farm["wallet"] = 264
		SaveDataManager.farm["water"] = 3
		SaveDataManager.farm["seeds"] = {"russet": 2, "purple": 1}
		SaveDataManager.farm["spuds"] = {"russet": 5, "golden": 1}
		SaveDataManager.farm["plots"] = []
		current = load("res://scenes/Farm/FarmScene.tscn").instantiate()
		add_child.call_deferred(current)
	elif phase == "farm" and frames == 150:
		# stage a lived-in farm: crops at several growth stages
		current.day_t = 0.22
		current.player.position = Vector2(900, 830)
		current.plots[0].plant("russet")
		current.plots[0].planted_at -= 12.0
		current.plots[1].plant("golden")
		current.plots[1].planted_at -= 9999.0
		current.plots[2].plant("purple")
		current.plots[2].planted_at -= 40.0
		current.plots[5].plant("yukon_gold")
		current.plots[5].watered = true
		current.plots[5].planted_at -= 10.0
	elif phase == "farm" and frames == 250:
		_snap("/tmp/shot_farm.png")
		phase = "night"
		current.day_t = 0.72
		# frame the kitchen + well so the lit windows show
		current.player.position = Vector2(2030, 560)
	elif phase == "night" and frames == 280:
		_snap("/tmp/shot_farm_night.png")
		phase = "pixel"
		StyleManager.apply("pixel")
	elif phase == "pixel" and frames == 300:
		_snap("/tmp/shot_farm_pixel.png")
		phase = "hyperreal"
		StyleManager.apply("hyperreal")
	elif phase == "hyperreal" and frames == 320:
		_snap("/tmp/shot_farm_hyperreal.png")
		get_tree().quit(0)

func _snap(path: String):
	var img = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved " + path)
