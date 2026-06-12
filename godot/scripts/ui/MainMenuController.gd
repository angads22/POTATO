extends Node2D

# Main menu UI and navigation
# Mode selection, leaderboard, settings, about

var selected_menu_item: int = 0
var menu_items: Array[String] = [
	"[1] Championship",
	"[2] Endless",
	"[3] Time Attack",
	"[4] Daily Challenge",
	"[5] Leaderboard",
	"[6] Settings",
	"[7] About",
	"[ESC] Quit"
]

var in_submenu: bool = false
var current_submenu: String = ""
var mascot: PotatoVisual

func _ready():
	AudioManager.play_music("menu")
	# bobbing mascot beside the menu
	mascot = PotatoVisual.new()
	mascot.setup({"color": "#e3c16f"})
	mascot.position = Vector2(1010, 400)
	add_child(mascot)
	queue_redraw()

func _input(event: InputEvent):
	if not (event is InputEventKey and event.pressed):
		return

	if in_submenu:
		match event.keycode:
			KEY_SPACE, KEY_ESCAPE:
				_close_submenu()
			KEY_S:
				if current_submenu == "settings":
					AudioManager.toggle_sound()
					queue_redraw()
			KEY_P:
				if current_submenu == "settings":
					SaveDataManager.update_setting("particle_effects", not SaveDataManager.settings["particle_effects"])
					queue_redraw()
		return

	match event.keycode:
		KEY_1:
			_start_game("championship")
		KEY_2:
			_start_game("endless")
		KEY_3:
			_start_game("time_attack")
		KEY_4:
			_start_game("daily_challenge")
		KEY_5:
			_show_leaderboard()
		KEY_6:
			_show_settings()
		KEY_7:
			_show_about()
		KEY_ESCAPE:
			get_tree().quit()

func _start_game(mode: String):
	GameManager.start_game(mode)
	AudioManager.stop_music(0.5)
	get_tree().change_scene_to_file("res://scenes/Gameplay/GameplayScene.tscn")

func _show_leaderboard():
	_open_submenu("leaderboard")

func _show_settings():
	_open_submenu("settings")

func _show_about():
	_open_submenu("about")

func _open_submenu(name: String):
	in_submenu = true
	current_submenu = name
	if mascot:
		mascot.visible = false
	queue_redraw()

func _close_submenu():
	in_submenu = false
	current_submenu = ""
	if mascot:
		mascot.visible = true
	queue_redraw()

func _draw():
	if in_submenu:
		_draw_submenu()
	else:
		_draw_main_menu()

func _draw_main_menu():
	var viewport_size = get_viewport_rect().size
	var centre_x = viewport_size.x / 2

	# Title
	var title_font_size = 48
	var title = "SLICE IT!"
	var title_size = ThemeDB.fallback_font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, title_font_size)
	draw_string(ThemeDB.fallback_font, Vector2(centre_x - title_size.x / 2, 100), title, HORIZONTAL_ALIGNMENT_LEFT, -1, title_font_size, Color.GOLD)

	# Subtitle
	draw_string(ThemeDB.fallback_font, Vector2(centre_x - 150, 160), "The Potato Cutting Championship", HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)

	# Version
	draw_string(ThemeDB.fallback_font, Vector2(centre_x - 40, 200), "v2.0.0", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GRAY)

	# Menu items
	var y_pos = 300
	for i in range(menu_items.size()):
		var color = Color.GOLD if i == selected_menu_item else Color.WHITE
		draw_string(ThemeDB.fallback_font, Vector2(centre_x - 100, y_pos), menu_items[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 20, color)
		y_pos += 50

func _draw_submenu():
	var viewport_size = get_viewport_rect().size
	var centre_x = viewport_size.x / 2

	# Draw background
	draw_rect(Rect2(0, 0, viewport_size.x, viewport_size.y), Color(0, 0, 0, 0.7))

	match current_submenu:
		"leaderboard":
			_draw_leaderboard_screen(centre_x)
		"settings":
			_draw_settings_screen(centre_x)
		"about":
			_draw_about_screen(centre_x)

func _draw_leaderboard_screen(centre_x: float):
	draw_string(ThemeDB.fallback_font, Vector2(centre_x - 80, 100), "LEADERBOARD", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.GOLD)

	var leaderboard = SaveDataManager.get_leaderboard("", 5)
	var y_pos = 200

	for i in range(leaderboard.size()):
		var entry = leaderboard[i]
		var text = "#%d  %s - %d pts" % [i + 1, entry["name"], entry["score"]]
		draw_string(ThemeDB.fallback_font, Vector2(centre_x - 150, y_pos), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		y_pos += 40

	draw_string(ThemeDB.fallback_font, Vector2(centre_x - 150, 500), "[SPACE] Back", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GRAY)

func _draw_settings_screen(centre_x: float):
	draw_string(ThemeDB.fallback_font, Vector2(centre_x - 40, 100), "SETTINGS", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.GOLD)

	var sound_status = "ON" if SaveDataManager.settings["sound_enabled"] else "OFF"
	draw_string(ThemeDB.fallback_font, Vector2(centre_x - 150, 200), "[S] Sound: %s" % sound_status, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	var particles_status = "ON" if SaveDataManager.settings["particle_effects"] else "OFF"
	draw_string(ThemeDB.fallback_font, Vector2(centre_x - 150, 250), "[P] Particles: %s" % particles_status, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	draw_string(ThemeDB.fallback_font, Vector2(centre_x - 150, 500), "[SPACE] Back", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GRAY)

func _draw_about_screen(centre_x: float):
	draw_string(ThemeDB.fallback_font, Vector2(centre_x - 40, 100), "ABOUT", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.GOLD)

	var about_text = "SLICE IT! - The Potato Cutting Championship\nA fully visual rhythm-action game.\n\nPress SPACE to cut, dodge rotten potatoes,\nand climb the leaderboard.\n\nCrafted with Godot Engine"
	draw_multiline_string(ThemeDB.fallback_font, Vector2(centre_x - 250, 200), about_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, -1, Color.WHITE)

	draw_string(ThemeDB.fallback_font, Vector2(centre_x - 150, 500), "[SPACE] Back", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GRAY)
