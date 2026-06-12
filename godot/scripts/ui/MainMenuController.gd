extends Node2D

# Main menu UI and navigation
# Mode selection, leaderboard, settings, about

var selected_menu_item: int = 0
var menu_items: Array[String] = [
	"[1] Championship",
	"[2] Endless",
	"[3] Potato Farm",
	"[4] Multiplayer",
	"[5] Leaderboard",
	"[6] Settings",
	"[7] Check for Updates",
	"[8] About",
	"[ESC] Quit"
]

var in_submenu: bool = false
var current_submenu: String = ""
var mascot: PotatoVisual
var mascot_knife: KnifeVisual

# Online leaderboard state (populated async when the submenu opens)
var online_scores: Array = []
var online_loading: bool = false
var show_online_tab: bool = false

func _ready():
	AudioManager.play_music("menu")

	# kitchen backdrop, board under the mascot (no window — the title
	# column needs the clear wall)
	var bg = KitchenBackground.new()
	bg.board_rect = Rect2(810, 330, 400, 200)
	bg.show_window = false
	add_child(bg)

	# bobbing mascot with a hovering cleaver beside the menu
	mascot = PotatoVisual.new()
	mascot.setup({"color": "#e3c16f"})
	mascot.position = Vector2(1010, 410)
	add_child(mascot)
	mascot_knife = KnifeVisual.new()
	mascot_knife.position = mascot.position
	add_child(mascot_knife)

	# repaint when the background update check resolves
	UpdateManager.status_changed.connect(queue_redraw)
	queue_redraw()

func _input(event: InputEvent):
	if not (event is InputEventKey and event.pressed):
		return

	if in_submenu:
		match event.keycode:
			KEY_SPACE, KEY_ESCAPE:
				# while an update is mid-flight, stay on the screen
				if current_submenu == "updates" and UpdateManager.state in ["downloading", "installing"]:
					return
				_close_submenu()
			KEY_ENTER, KEY_KP_ENTER:
				if current_submenu == "updates":
					UpdateManager.install()
			KEY_R:
				if current_submenu == "updates":
					UpdateManager.check()
			KEY_S:
				if current_submenu == "settings":
					AudioManager.toggle_sound()
					queue_redraw()
			KEY_P:
				if current_submenu == "settings":
					SaveDataManager.update_setting("particle_effects", not SaveDataManager.settings["particle_effects"])
					queue_redraw()
			KEY_G:
				if current_submenu == "settings":
					StyleManager.cycle()
					queue_redraw()
			KEY_TAB:
				if current_submenu == "leaderboard":
					show_online_tab = not show_online_tab
					queue_redraw()
		return

	match event.keycode:
		KEY_1: _start_game("championship")
		KEY_2: _start_game("endless")
		KEY_3: _enter_farm()
		KEY_4: _enter_lobby()
		KEY_5: _show_leaderboard()
		KEY_6: _show_settings()
		KEY_7: _show_updates()
		KEY_8: _show_about()
		KEY_ESCAPE: get_tree().quit()

func _start_game(mode: String):
	GameManager.start_game(mode)
	AudioManager.stop_music(0.5)
	get_tree().change_scene_to_file("res://scenes/Gameplay/GameplayScene.tscn")

func _enter_farm():
	get_tree().change_scene_to_file("res://scenes/Farm/FarmScene.tscn")

func _enter_lobby():
	get_tree().change_scene_to_file("res://scenes/Multiplayer/LobbyScene.tscn")

func _show_leaderboard():
	online_scores.clear()
	show_online_tab = false
	online_loading = OnlineLeaderboard.is_available()
	if OnlineLeaderboard.is_available():
		OnlineLeaderboard.fetch_scores("", func(scores: Array):
			online_scores = scores
			online_loading = false
			queue_redraw()
		)
	_open_submenu("leaderboard")

func _show_settings():
	_open_submenu("settings")

func _show_updates():
	if UpdateManager.state in ["idle", "error", "uptodate"]:
		UpdateManager.check()
	_open_submenu("updates")

func _show_about():
	_open_submenu("about")

func _open_submenu(name: String):
	in_submenu = true
	current_submenu = name
	if mascot:
		mascot.visible = false
	if mascot_knife:
		mascot_knife.visible = false
	queue_redraw()

func _close_submenu():
	in_submenu = false
	current_submenu = ""
	if mascot:
		mascot.visible = true
	if mascot_knife:
		mascot_knife.visible = true
	queue_redraw()

func _draw():
	if in_submenu:
		_draw_submenu()
	else:
		_draw_main_menu()

func _draw_main_menu():
	var font = ThemeDB.fallback_font
	var title_x = 360.0  # title column centre; the mascot owns the right side

	# Title with drop shadow
	var title = "SLICE IT!"
	var title_size = font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 64)
	draw_string(font, Vector2(title_x - title_size.x / 2 + 4, 124), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color(0.25, 0.15, 0.05, 0.7))
	draw_string(font, Vector2(title_x - title_size.x / 2, 120), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 64, Color.GOLD)

	# Subtitle + version
	var sub = "The Potato Cutting Championship"
	var sub_size = font.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, 22)
	draw_string(font, Vector2(title_x - sub_size.x / 2, 162), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color(0.35, 0.22, 0.1))
	var ver = "v" + UpdateManager.current_version
	var ver_size = font.get_string_size(ver, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
	draw_string(font, Vector2(title_x - ver_size.x / 2, 192), ver, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.45, 0.32, 0.2))

	# farm wallet, so progress is visible from the front door
	var wallet = "Wallet: %d coins" % SaveDataManager.wallet()
	var wallet_size = font.get_string_size(wallet, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
	draw_string(font, Vector2(title_x - wallet_size.x / 2, 218), wallet, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.72, 0.52, 0.12))

	# launch check found a newer release — nudge towards the updater
	if UpdateManager.state == "available":
		var nudge = "Update available: v%s — press [7]" % UpdateManager.latest_version
		var ns = font.get_string_size(nudge, HORIZONTAL_ALIGNMENT_CENTER, -1, 15)
		var pulse = 0.7 + 0.3 * sin(Time.get_ticks_msec() / 400.0)
		draw_string(font, Vector2(title_x - ns.x / 2, 700), nudge, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(1.0, 0.75, 0.2, pulse))

	# Menu in a walnut panel
	var panel_rect = Rect2(title_x - 190, 236, 380, 52 + menu_items.size() * 40)
	GameHUD.panel_style().draw(get_canvas_item(), panel_rect)
	var y_pos = panel_rect.position.y + 46
	for i in range(menu_items.size()):
		var color = Color.GOLD if i == selected_menu_item else Color(0.95, 0.9, 0.8)
		draw_string(font, Vector2(panel_rect.position.x + 48, y_pos), menu_items[i], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, color)
		y_pos += 40

func _draw_submenu():
	var viewport_size = get_viewport_rect().size
	var centre_x = viewport_size.x / 2

	draw_rect(Rect2(0, 0, viewport_size.x, viewport_size.y), Color(0, 0, 0, 0.75))

	match current_submenu:
		"leaderboard": _draw_leaderboard_screen(centre_x)
		"settings":    _draw_settings_screen(centre_x)
		"updates":     _draw_updates_screen(centre_x)
		"about":       _draw_about_screen(centre_x)

func _draw_leaderboard_screen(centre_x: float):
	var font := ThemeDB.fallback_font

	draw_string(font, Vector2(centre_x - 90, 100), "LEADERBOARD", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.GOLD)

	# Tab switcher (only shown when the online backend is configured)
	var tab_y := 145.0
	if OnlineLeaderboard.is_available():
		var local_col := Color.WHITE if not show_online_tab else Color(0.5, 0.45, 0.4)
		var online_col := Color.WHITE if show_online_tab else Color(0.5, 0.45, 0.4)
		draw_string(font, Vector2(centre_x - 180, tab_y), "LOCAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, local_col)
		draw_string(font, Vector2(centre_x - 40, tab_y), "|", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.5, 0.45, 0.4))
		draw_string(font, Vector2(centre_x, tab_y), "GLOBAL", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, online_col)
		draw_string(font, Vector2(centre_x - 180, tab_y + 22), "[TAB] Switch", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.5, 0.45))
		tab_y += 30.0
	else:
		draw_string(font, Vector2(centre_x - 180, tab_y), "Local scores (Supabase not configured — see OnlineLeaderboard.gd)",
				HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.5, 0.45))
		tab_y += 24.0

	var y_pos := tab_y + 24.0

	if show_online_tab:
		if online_loading:
			draw_string(font, Vector2(centre_x - 60, y_pos), "Loading…",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.65, 0.55))
		elif online_scores.is_empty():
			draw_string(font, Vector2(centre_x - 100, y_pos), "No online scores yet.",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.65, 0.55))
		else:
			for i in range(mini(online_scores.size(), 10)):
				var entry = online_scores[i]
				var text := "#%d  %-18s  %d pts  [%s]" % [
					i + 1, entry.get("name", "?"),
					int(entry.get("score", 0)),
					entry.get("mode", "?").capitalize()
				]
				draw_string(font, Vector2(centre_x - 220, y_pos), text,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
				y_pos += 36.0
	else:
		var leaderboard := SaveDataManager.get_leaderboard("", 10)
		if leaderboard.is_empty():
			draw_string(font, Vector2(centre_x - 100, y_pos), "No scores yet — play a run!",
					HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.65, 0.55))
		else:
			for i in range(leaderboard.size()):
				var entry := leaderboard[i]
				var text := "#%d  %-18s  %d pts  [%s]" % [
					i + 1, entry.get("name", "?"),
					int(entry.get("score", 0)),
					entry.get("mode", "?").capitalize().replace("_", " ")
				]
				draw_string(font, Vector2(centre_x - 220, y_pos), text,
						HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color.WHITE)
				y_pos += 36.0

	draw_string(font, Vector2(centre_x - 150, 666), "[SPACE] Back",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GRAY)

func _draw_settings_screen(centre_x: float):
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(centre_x - 55, 100), "SETTINGS", HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.GOLD)

	var sound_status := "ON" if SaveDataManager.settings["sound_enabled"] else "OFF"
	draw_string(font, Vector2(centre_x - 150, 200), "[S] Sound: %s" % sound_status,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	var particles_status := "ON" if SaveDataManager.settings["particle_effects"] else "OFF"
	draw_string(font, Vector2(centre_x - 150, 248), "[P] Particles: %s" % particles_status,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	draw_string(font, Vector2(centre_x - 150, 296), "[G] Graphics: %s" % StyleManager.current_name(),
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)
	draw_string(font, Vector2(centre_x - 150, 322), "Classic → Pixel Art → Hyperreal",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.55, 0.5, 0.45))

	draw_string(font, Vector2(centre_x - 150, 500), "[SPACE] Back",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GRAY)

func _draw_updates_screen(centre_x: float):
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(centre_x - 60, 100), "UPDATES",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.GOLD)

	draw_string(font, Vector2(centre_x - 230, 190),
			"Installed version:  v" + UpdateManager.current_version,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

	var status := ""
	var col := Color.WHITE
	var action := ""
	match UpdateManager.state:
		"checking":
			status = "Checking the latest release…"
			col = Color(0.7, 0.65, 0.55)
		"uptodate":
			status = "You're on the newest version!  (latest: v%s)" % UpdateManager.latest_version
			col = Color.LIGHT_GREEN
			action = "[R] Check again   ·   [SPACE] Back"
		"available":
			status = "Update available:  v%s" % UpdateManager.latest_version
			col = Color.GOLD
			action = "[ENTER] Download & install — the game restarts itself   ·   [SPACE] Back"
		"downloading":
			status = "Downloading v%s…" % UpdateManager.latest_version
			col = Color(0.5, 0.8, 1.0)
		"installing":
			status = "Installing — the game will restart in a moment…"
			col = Color(0.5, 0.8, 1.0)
		"error":
			status = UpdateManager.error_msg
			col = Color.ORANGE_RED
			action = "[R] Try again   ·   [SPACE] Back"
		_:
			status = "Press [R] to check for updates"
			col = Color(0.7, 0.65, 0.55)
			action = "[R] Check   ·   [SPACE] Back"

	draw_string(font, Vector2(centre_x - 230, 240), status, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, col)
	if action != "":
		draw_string(font, Vector2(centre_x - 230, 300), action, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.7, 0.62))

	draw_string(font, Vector2(centre_x - 230, 360),
			"Updates come from github.com/%s/releases" % UpdateManager.REPO,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.55, 0.5, 0.45))

func _draw_about_screen(centre_x: float):
	var font := ThemeDB.fallback_font
	draw_string(font, Vector2(centre_x - 40, 100), "ABOUT",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 32, Color.GOLD)

	var about_text := ("SLICE IT! — The Potato Cutting Championship\n" +
		"A fully visual rhythm-action game.\n\n" +
		"Press SPACE to cut, dodge rotten potatoes,\n" +
		"and climb both the local and global leaderboard.\n\n" +
		"Play solo across 6 championship stages, brave the\n" +
		"endless waves, or face a friend over LAN multiplayer.\n\n" +
		"Pick your look in Settings: Classic, Pixel Art,\n" +
		"or Hyperreal.\n\n" +
		"Crafted with Godot Engine 4.2")
	draw_multiline_string(font, Vector2(centre_x - 260, 200), about_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, -1, Color.WHITE)

	draw_string(font, Vector2(centre_x - 150, 500), "[SPACE] Back",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GRAY)
