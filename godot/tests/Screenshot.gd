extends Node

# Captures /tmp/shot_menu.png, /tmp/shot_gameplay.png, /tmp/shot_farm.png,
# /tmp/shot_farm_night.png, the style variants and /tmp/shot_town.png for
# visual review. Scenes are instantiated as children so this node survives
# the swap.
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
		SaveDataManager.farm["tiles"] = {}
		SaveDataManager.farm["plow_uses"] = 7
		SaveDataManager.farm["sprinkler_stock"] = 1
		current = load("res://scenes/Farm/FarmScene.tscn").instantiate()
		add_child.call_deferred(current)
	elif phase == "farm" and frames == 150:
		# stage a lived-in farm: crops at several growth stages + a sprinkler,
		# plowed straight onto the open grid near the player
		current.day_t = 0.22
		current.player.position = Vector2(900, 830)
		for k in ["6:6", "7:6", "6:7", "7:7"]:
			current.plow_cell(current.key_to_cell(k))
		current.tile_map["6:6"].plant("russet")
		current.tile_map["6:6"].planted_at -= 12.0
		current.tile_map["7:6"].plant("golden")
		current.tile_map["7:6"].planted_at -= 9999.0
		current.tile_map["6:7"].plant("purple")
		current.tile_map["6:7"].planted_at -= 40.0
		current.tile_map["7:7"].plant("yukon_gold")
		current.tile_map["7:7"].watered = true
		current.tile_map["7:7"].planted_at -= 10.0
		current.place_sprinkler_cell(Vector2i(8, 7))
	elif phase == "farm" and frames == 250:
		_snap("/tmp/shot_farm.png")
		phase = "night"
		current.day_t = 0.72
		# frame the farmhouse + well so the lit windows show
		current.player.position = Vector2(900, 480)
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
		phase = "town"
		StyleManager.apply("classic")
		current.queue_free()
		current = load("res://scenes/Town/TownScene.tscn").instantiate()
		add_child.call_deferred(current)
	elif phase == "town" and frames == 360:
		current.day_t = 0.3
		current.player.position = Vector2(820, 660)
	elif phase == "town" and frames == 420:
		_snap("/tmp/shot_town.png")
		get_tree().quit(0)

func _snap(path: String):
	var img = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved " + path)
