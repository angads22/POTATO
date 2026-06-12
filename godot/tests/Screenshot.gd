extends Node

# Captures /tmp/shot_menu.png and /tmp/shot_gameplay.png for visual review.
# Scenes are instantiated as children so this node survives the swap.
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
		get_tree().quit(0)

func _snap(path: String):
	var img = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved " + path)
