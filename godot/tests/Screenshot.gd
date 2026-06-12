extends Node

# Captures screenshots of the menu and mid-gameplay for visual review.

var frames := 0
var phase := "menu"
var gameplay

func _ready():
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _process(_delta):
	frames += 1
	if phase == "menu" and frames == 40:
		_snap("/tmp/shot_menu.png")
		phase = "to_game"
		GameManager.start_game("championship")
		GameManager.current_state.lives = 2
		GameManager.current_state.combo = 7
		GameManager.current_state.score = 4280
		get_tree().change_scene_to_file("res://scenes/Gameplay/GameplayScene.tscn")
	elif phase == "to_game" and frames == 90:
		_snap("/tmp/shot_gameplay.png")
		phase = "done"
		get_tree().quit(0)

func _snap(path: String):
	var img = get_viewport().get_texture().get_image()
	img.save_png(path)
	print("saved " + path)
