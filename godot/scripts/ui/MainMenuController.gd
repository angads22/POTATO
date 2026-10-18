extends Node2D

# Main menu UI and navigation
# Mode selection, leaderboard, settings (incl. audio calibration), achievements,
# updates & about. Everything is keyboard- and mouse-driven; the title and the
# mascot bob in time with the (procedurally composed) menu theme.
#
# Classroom-friendly bits (farm design §7.5/§7.6): the [4] Potato Farm row
# teases "9 ripe · +1.2K waiting" from a dry-run settle (never touching the
# save), the menu remembers the last mode it opened so Enter re-opens it, the
# very first launch asks "Play with sound?" before any music starts, M mutes
# from anywhere in the menu, and the game idles at 10 fps while unfocused.

const Fmt = preload("res://scripts/utils/NumFmt.gd")
# Menu actions remembered in settings.last_menu_item (submenus and Quit are not).
const REMEMBERED := ["championship", "endless", "concert", "farm", "lobby", "fps"]
const TEASER_EVERY := 1.0   # seconds between farm-teaser dry runs

var selected_menu_item: int = 0
var hovered_item: int = -1
var _item_rects: Array[Rect2] = []
# [label, hotkey, action]
var menu_items: Array = [
	["Championship", KEY_1, "championship"],
	["Endless", KEY_2, "endless"],
	["Concert  ♪ NEW", KEY_3, "concert"],
	["Potato Farm", KEY_4, "farm"],
	["Multiplayer (LAN duel)", KEY_5, "lobby"],
	["Spud Blaster (FPS)", KEY_6, "fps"],
	["Leaderboard", KEY_7, "leaderboard"],
	["Achievements", KEY_8, "achievements"],
	["Settings", KEY_9, "settings"],
	["Updates & About", KEY_0, "about"],
	["Quit", KEY_ESCAPE, "quit"],
]

var in_submenu: bool = false
var current_submenu: String = ""
var mascot: PotatoVisual
var mascot_knife: KnifeVisual

# Online leaderboard state (populated async when the submenu opens)
var online_scores: Array = []
var online_loading: bool = false
var show_online_tab: bool = false

# settings screen: a navigable list of rows
const SETTINGS_ROWS := ["sound", "music", "sfx", "offset", "calibrate", "graphics", "particles", "shake",
		"fullscreen", "slot"]
var settings_sel: int = 0
var _settings_rects: Array[Rect2] = []

# audio calibration: tap along with a four-on-the-floor kick
const CALIB_TAPS := 12
var calib_offsets: Array = []
var calib_result_ms: int = 0
var calib_done: bool = false

# "9 ripe · +1.2K waiting" for the farm row ("" until the farm has started)
var farm_teaser: String = ""
var _teaser_t: float = 0.0

# first-launch "Play with sound?" card (settings.sound_prompted)
var sound_prompt: bool = false
var _prompt_sel: int = 0     # 0 = Sound on, 1 = Muted
var _prompt_rects: Array[Rect2] = []

func _ready():
	SaveDataManager.set_low_power_ok(true)
	# The very first launch asks before making any noise (a classroom is quiet).
	sound_prompt = not bool(SaveDataManager.settings.get("sound_prompted", false))
	if not sound_prompt:
		AudioManager.play_music("menu")
	# Enter re-opens whatever mode was opened last (the farm, for most visits).
	var last := str(SaveDataManager.settings.get("last_menu_item", ""))
	for i in menu_items.size():
		if menu_items[i][2] == last:
			selected_menu_item = i
	update_farm_teaser()
	# warm up the first kitchen song and the farm theme while the player browses
	AudioManager.prefetch({"style": "lofi", "bpm": 132.0, "seed": 101})
	AudioManager.prefetch(AudioManager.TRACKS["farm"])

	# kitchen backdrop, board under the mascot (no window — the title
	# column needs the clear wall)
	var bg = KitchenBackground.new()
	bg.board_rect = Rect2(810, 330, 400, 200)
	bg.show_window = false
	bg.beat_sync = true
	add_child(bg)

	# bobbing mascot with a hovering cleaver beside the menu
	mascot = PotatoVisual.new()
	mascot.setup({"color": "#e3c16f"})
	mascot.position = Vector2(1010, 410)
	mascot.beat_sync = true
	add_child(mascot)
	mascot_knife = KnifeVisual.new()
	mascot_knife.position = mascot.position
	mascot_knife.beat_sync = true
	add_child(mascot_knife)

	# repaint when the background update check resolves
	UpdateManager.status_changed.connect(queue_redraw)
	queue_redraw()

func _exit_tree():
	SaveDataManager.set_low_power_ok(false)

func _process(delta):
	# the farm teaser is a dry-run settle: cheap, but once a second is plenty
	_teaser_t += delta
	if _teaser_t >= TEASER_EVERY:
		_teaser_t = 0.0
		update_farm_teaser()
	# keep the hover highlight, selection pulse and beat bounce live
	queue_redraw()

# "9 ripe · +1.2K waiting" from FarmEconomy.preview (a settle on a deep copy;
# the save itself is never touched). Empty until the farm has been started.
func update_farm_teaser():
	farm_teaser = ""
	if not SaveDataManager.farm_started():
		return
	var pv: Dictionary = SaveDataManager.farm_preview()
	var ripe := int(pv.get("ripe", 0))
	if ripe > 0:
		farm_teaser = "%d ripe · +%s waiting" % [ripe, Fmt.coins(int(pv.get("waiting_coins", 0)))]
	elif int(pv.get("report_coins", 0)) > 0:
		farm_teaser = "Spudlings picked +%s" % Fmt.coins(int(pv["report_coins"]))
	else:
		farm_teaser = "all growing"

# ── first-launch sound card ──

func _sound_prompt_input(event: InputEvent):
	if event is InputEventMouseMotion:
		for i in _prompt_rects.size():
			if _prompt_rects[i].has_point(get_global_mouse_position()):
				_prompt_sel = i
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		for i in _prompt_rects.size():
			if _prompt_rects[i].has_point(get_global_mouse_position()):
				answer_sound_prompt(i == 0)
		return
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.keycode:
		KEY_LEFT, KEY_RIGHT, KEY_UP, KEY_DOWN, KEY_A, KEY_D, KEY_W, KEY_S, KEY_TAB:
			_prompt_sel = 1 - _prompt_sel
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			answer_sound_prompt(_prompt_sel == 0)
		KEY_M, KEY_ESCAPE:
			answer_sound_prompt(false)

# Store the answer (settings.sound_enabled + sound_prompted), then start the
# menu music, which the card held back.
func answer_sound_prompt(sound_on: bool):
	if not sound_prompt:
		return
	sound_prompt = false
	if AudioManager.sound_enabled != sound_on:
		AudioManager.toggle_sound()
	SaveDataManager.update_setting("sound_prompted", true)
	AudioManager.play_music("menu")
	AudioManager.play_sfx("menu_select")

func _toggle_mute():
	AudioManager.toggle_sound()
	AudioManager.play_sfx("menu_select")

func _input(event: InputEvent):
	if sound_prompt:
		_sound_prompt_input(event)
		return
	# Mouse on the main menu: hover to highlight, left-click to pick.
	if not in_submenu:
		if event is InputEventMouseMotion:
			_update_hover(get_global_mouse_position())
			return
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			var clicked := _item_at(get_global_mouse_position())
			if clicked >= 0:
				selected_menu_item = clicked
				_activate(clicked)
			return
	elif current_submenu == "settings":
		if event is InputEventMouseMotion:
			for i in _settings_rects.size():
				if _settings_rects[i].has_point(get_global_mouse_position()) and settings_sel != i:
					settings_sel = i
					AudioManager.play_sfx("menu_move")
			return
		if event is InputEventMouseButton and event.pressed:
			for i in _settings_rects.size():
				if _settings_rects[i].has_point(get_global_mouse_position()):
					settings_sel = i
					_settings_change(SETTINGS_ROWS[i], -1 if event.button_index == MOUSE_BUTTON_RIGHT else 1, true)
			return

	if not (event is InputEventKey and event.pressed):
		return

	if in_submenu:
		_submenu_key(event)
		return

	match event.keycode:
		KEY_UP, KEY_W: _move_selection(-1)
		KEY_DOWN, KEY_S: _move_selection(1)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _activate(selected_menu_item)
		KEY_M: _toggle_mute()
		_:
			for i in menu_items.size():
				if menu_items[i][1] == event.keycode:
					selected_menu_item = i
					_activate(i)
					return

func _submenu_key(event: InputEventKey):
	if current_submenu == "calibrate":
		_calibrate_key(event)
		return
	if event.keycode == KEY_M and not event.echo:
		_toggle_mute()
		return
	if current_submenu == "settings":
		_settings_key(event)
		return
	match event.keycode:
		KEY_SPACE, KEY_ESCAPE, KEY_BACKSPACE:
			# while an update is mid-flight, stay on the screen
			if current_submenu == "about" and UpdateManager.state in ["downloading", "installing"]:
				return
			_close_submenu()
		KEY_ENTER, KEY_KP_ENTER:
			if current_submenu == "about" and UpdateManager.state == "available":
				UpdateManager.install()
		KEY_R:
			if current_submenu == "about":
				UpdateManager.check()
		KEY_TAB:
			if current_submenu == "leaderboard":
				show_online_tab = not show_online_tab
				AudioManager.play_sfx("menu_move")

# Maps a menu row to its action (shared by keys, arrows and clicks).
func _activate(i: int):
	var action: String = menu_items[i][2]
	AudioManager.play_sfx("menu_select")
	if action in REMEMBERED and str(SaveDataManager.settings.get("last_menu_item", "")) != action:
		SaveDataManager.update_setting("last_menu_item", action)
	match action:
		"championship", "endless": _start_game(action)
		"concert":
			ConcertController.return_scene = "res://scenes/MainMenu.tscn"
			get_tree().change_scene_to_file("res://scenes/Concert/ConcertScene.tscn")
		"farm": get_tree().change_scene_to_file("res://scenes/Farm/FarmScene.tscn")
		"lobby": get_tree().change_scene_to_file("res://scenes/Multiplayer/LobbyScene.tscn")
		"fps": get_tree().change_scene_to_file("res://scenes/Fps/FpsLobby.tscn")
		"leaderboard": _show_leaderboard()
		"achievements": _open_submenu("achievements")
		"settings": _open_submenu("settings")
		"about":
			if UpdateManager.state in ["idle", "error", "uptodate"]:
				UpdateManager.check()
			_open_submenu("about")
		"quit":
			SaveDataManager.flush_farm()   # a debounced farm save must not be lost
			get_tree().quit()

func _move_selection(delta: int):
	selected_menu_item = posmod(selected_menu_item + delta, menu_items.size())
	hovered_item = -1
	AudioManager.play_sfx("menu_move")

func _update_hover(pos: Vector2):
	var h := _item_at(pos)
	if h != hovered_item:
		hovered_item = h
		if h >= 0:
			if h != selected_menu_item:
				AudioManager.play_sfx("menu_move")
			selected_menu_item = h
		Input.set_default_cursor_shape(Input.CURSOR_POINTING_HAND if h >= 0 else Input.CURSOR_ARROW)

func _item_at(pos: Vector2) -> int:
	for i in range(_item_rects.size()):
		if _item_rects[i].has_point(pos):
			return i
	return -1

func _start_game(mode: String):
	GameManager.start_game(mode)
	get_tree().change_scene_to_file("res://scenes/Gameplay/GameplayScene.tscn")

func _show_leaderboard():
	online_scores.clear()
	show_online_tab = false
	online_loading = OnlineLeaderboard.is_available()
	if OnlineLeaderboard.is_available():
		OnlineLeaderboard.fetch_scores("", func(scores: Array):
			online_scores = scores
			online_loading = false
		)
	_open_submenu("leaderboard")

func _open_submenu(name: String):
	in_submenu = true
	current_submenu = name
	if mascot:
		mascot.visible = false
	if mascot_knife:
		mascot_knife.visible = false

func _close_submenu():
	AudioManager.play_sfx("menu_back")
	in_submenu = false
	current_submenu = ""
	Input.set_default_cursor_shape(Input.CURSOR_ARROW)
	if mascot:
		mascot.visible = true
	if mascot_knife:
		mascot_knife.visible = true

# ────────────────────────────────────────────────────────
#  Settings
# ────────────────────────────────────────────────────────

func _settings_key(event: InputEventKey):
	var row: String = SETTINGS_ROWS[settings_sel]
	match event.keycode:
		KEY_ESCAPE, KEY_BACKSPACE:
			_close_submenu()
		KEY_UP, KEY_W:
			settings_sel = posmod(settings_sel - 1, SETTINGS_ROWS.size())
			AudioManager.play_sfx("menu_move")
		KEY_DOWN, KEY_S:
			settings_sel = posmod(settings_sel + 1, SETTINGS_ROWS.size())
			AudioManager.play_sfx("menu_move")
		KEY_LEFT, KEY_A:
			_settings_change(row, -1, false)
		KEY_RIGHT, KEY_D:
			_settings_change(row, 1, false)
		KEY_ENTER, KEY_KP_ENTER, KEY_SPACE:
			_settings_change(row, 1, true)
		KEY_1, KEY_2, KEY_3:
			_switch_slot(event.keycode - KEY_0)

# dir: -1 / +1; activate: Enter/click (toggles cycle, buttons fire)
func _settings_change(row: String, dir: int, activate: bool):
	var st: Dictionary = SaveDataManager.settings
	match row:
		"sound":
			AudioManager.toggle_sound()
		"music", "sfx":
			var key := row + "_volume"
			var v := clampf(snappedf(float(st.get(key, 1.0)) + 0.1 * dir, 0.1), 0.0, 1.0)
			if activate and dir > 0 and float(st.get(key, 1.0)) >= 1.0:
				v = 0.0  # wrap around on click/Enter
			AudioManager.set_volume("Music" if row == "music" else "SFX", v)
		"offset":
			var ms := clampi(int(st.get("audio_offset_ms", 0)) + 5 * dir, -250, 250)
			SaveDataManager.update_setting("audio_offset_ms", ms)
		"calibrate":
			if activate:
				_start_calibration()
				return
		"graphics":
			StyleManager.cycle()
		"particles":
			SaveDataManager.update_setting("particle_effects", not st.get("particle_effects", true))
		"shake":
			SaveDataManager.update_setting("screen_shake", not st.get("screen_shake", true))
		"fullscreen":
			SaveDataManager.update_setting("fullscreen", not st.get("fullscreen", false))
			GameManager.apply_fullscreen()
		"slot":
			_switch_slot(posmod(SaveDataManager.current_slot - 1 + dir, SaveDataManager.MAX_SLOTS) + 1)
			return
	AudioManager.play_sfx("menu_select" if dir > 0 else "menu_back")

func _switch_slot(n: int):
	if SaveDataManager.switch_slot(n):
		# the new slot carries its own settings — resync the live systems
		# that cache them at boot
		AudioManager.sound_enabled = SaveDataManager.settings.get("sound_enabled", true)
		AudioManager.apply_volumes()
		StyleManager.apply(StyleManager.current())
		GameManager.apply_fullscreen()
		AudioManager.play_sfx("menu_select")

func _settings_value(row: String) -> String:
	var st: Dictionary = SaveDataManager.settings
	match row:
		"sound": return "ON" if st.get("sound_enabled", true) else "OFF"
		"music": return _bar(float(st.get("music_volume", 0.8)))
		"sfx": return _bar(float(st.get("sfx_volume", 1.0)))
		"offset": return "%+d ms" % int(st.get("audio_offset_ms", 0))
		"calibrate": return "tap along to set the offset"
		"graphics": return StyleManager.current_name()
		"particles": return "ON" if st.get("particle_effects", true) else "OFF"
		"shake": return "ON" if st.get("screen_shake", true) else "OFF"
		"fullscreen": return "ON" if st.get("fullscreen", false) else "OFF"
		"slot": return "Slot %d — %s" % [SaveDataManager.current_slot, SaveDataManager.slot_summary(SaveDataManager.current_slot)]
	return ""

static func _bar(v: float) -> String:
	var n := int(round(v * 10.0))
	return "%s%s  %d%%" % ["■".repeat(n), "□".repeat(10 - n), int(round(v * 100.0))]

const SETTINGS_LABELS := {
	"sound": "Sound", "music": "Music volume", "sfx": "Effects volume", "offset": "Audio offset",
	"calibrate": "Calibrate audio offset…", "graphics": "Graphics style", "particles": "Particles",
	"shake": "Screen shake", "fullscreen": "Fullscreen  (F11)", "slot": "Save file",
}

# ────────────────────────────────────────────────────────
#  Audio calibration
# ────────────────────────────────────────────────────────

func _start_calibration():
	calib_offsets.clear()
	calib_done = false
	current_submenu = "calibrate"
	AudioManager.play_song({"style": "dance", "bpm": 100.0, "seed": 77}, 0.3)
	AudioManager.play_sfx("menu_select")

func _calibrate_key(event: InputEventKey):
	match event.keycode:
		KEY_ESCAPE, KEY_BACKSPACE:
			AudioManager.play_music("menu")
			current_submenu = "settings"
			AudioManager.play_sfx("menu_back")
		KEY_R:
			calib_offsets.clear()
			calib_done = false
		KEY_ENTER, KEY_KP_ENTER:
			if calib_done:
				SaveDataManager.update_setting("audio_offset_ms", clampi(calib_result_ms, -250, 250))
				AudioManager.play_music("menu")
				current_submenu = "settings"
				AudioManager.play_sfx("achievement")
		KEY_SPACE:
			if calib_done or AudioManager.music_time() < 0.0:
				return
			# where the tap fell relative to the nearest beat, measured on the
			# raw clock (the current offset is added back so a re-calibration
			# doesn't compound the old value)
			var cur_ms := float(SaveDataManager.settings.get("audio_offset_ms", 0))
			var raw_beat := (AudioManager.music_time() + cur_ms / 1000.0) * AudioManager.bpm / 60.0
			var off_beats := raw_beat - roundf(raw_beat)
			calib_offsets.append(off_beats * AudioManager.beat_sec() * 1000.0)
			AudioManager.play_sfx("menu_move", -8.0)
			if calib_offsets.size() >= CALIB_TAPS:
				var used := calib_offsets.slice(2)  # the first taps are warm-up
				used.sort()
				calib_result_ms = int(round(used[used.size() / 2]))
				calib_done = true

func _draw_calibrate_screen(cx: float):
	var font := ThemeDB.fallback_font
	_text(font, "AUDIO CALIBRATION", cx, 110, 32, Color.GOLD)
	_text(font, "Listen to the kick drum and tap [SPACE] on every beat.", cx, 170, 19, Color.WHITE)
	_text(font, "Headphones with lag (Bluetooth, TVs) are what this fixes.", cx, 198, 15, Color(0.7, 0.65, 0.55))
	if not SaveDataManager.settings.get("sound_enabled", true):
		_text(font, "Sound is OFF — turn it on in Settings first.", cx, 240, 17, Color.ORANGE_RED)
	# tap progress dots
	for i in CALIB_TAPS:
		var x := cx + (i - (CALIB_TAPS - 1) / 2.0) * 30.0
		var col := Color.GOLD if i < calib_offsets.size() else Color(0.5, 0.45, 0.4, 0.5)
		draw_circle(Vector2(x, 300), 9.0, col)
	# the taps so far, plotted early (left) / late (right)
	var px0 := cx - 200.0
	draw_line(Vector2(px0, 360), Vector2(px0 + 400, 360), Color(0.6, 0.55, 0.5, 0.6), 2.0)
	draw_line(Vector2(cx, 345), Vector2(cx, 375), Color.WHITE, 2.0)
	_text(font, "early", px0 + 20, 395, 13, Color(0.6, 0.55, 0.5))
	_text(font, "late", px0 + 380, 395, 13, Color(0.6, 0.55, 0.5))
	for o in calib_offsets:
		var x := cx + clampf(o / 150.0, -1.0, 1.0) * 200.0
		draw_circle(Vector2(x, 360), 5.0, Color(1.0, 0.8, 0.3, 0.8))
	if calib_done:
		var verdict := "right on the beat" if absi(calib_result_ms) <= 10 else \
				("%d ms late" % calib_result_ms if calib_result_ms > 0 else "%d ms early" % -calib_result_ms)
		_text(font, "Your taps land %s." % verdict, cx, 450, 22, Color.LIGHT_GREEN)
		_text(font, "[ENTER] Use %+d ms    [R] Try again    [ESC] Cancel" % calib_result_ms, cx, 490, 17,
				Color(0.85, 0.8, 0.7))
	else:
		_text(font, "%d / %d taps    ·    [ESC] Cancel" % [calib_offsets.size(), CALIB_TAPS], cx, 450, 17,
				Color(0.75, 0.7, 0.62))

# ────────────────────────────────────────────────────────
#  Drawing
# ────────────────────────────────────────────────────────

func _text(font: Font, s: String, cx: float, y: float, size: int, col: Color):
	var w := font.get_string_size(s, HORIZONTAL_ALIGNMENT_CENTER, -1, size).x
	draw_string(font, Vector2(cx - w / 2, y), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw():
	if in_submenu:
		_draw_submenu()
	else:
		_draw_main_menu()
	if sound_prompt:
		_draw_sound_prompt()

# The first-launch card: two big buttons (>= 44 px for trackpads).
func _draw_sound_prompt():
	var font := ThemeDB.fallback_font
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.72))
	var card := Rect2(vp.x / 2 - 260, vp.y / 2 - 130, 520, 260)
	GameHUD.panel_style(Color(0.16, 0.1, 0.06, 0.97)).draw(get_canvas_item(), card)
	var cx := card.get_center().x
	_text(font, "Play with sound?", cx, card.position.y + 64, 30, Color.GOLD)
	_text(font, "You can press M any time to mute or unmute.", cx, card.position.y + 100, 15,
			Color(0.8, 0.74, 0.62))
	_prompt_rects.clear()
	var labels := ["Sound on", "Muted"]
	for i in 2:
		var r := Rect2(cx - 220 + i * 230, card.position.y + 140, 210, 64)
		_prompt_rects.append(r)
		var active := i == _prompt_sel
		draw_rect(r, Color(0.85, 0.68, 0.3, 0.3 if active else 0.1))
		draw_rect(r, Color(1.0, 0.8, 0.3, 0.95) if active else Color(0.6, 0.5, 0.35, 0.8), false, 2.0)
		_text(font, labels[i], r.get_center().x, r.get_center().y + 8, 22,
				Color.GOLD if active else Color(0.92, 0.88, 0.8))
	_text(font, "←/→ choose · Enter confirm · Esc muted", cx, card.end.y - 22, 13, Color(0.6, 0.55, 0.45))

func _draw_main_menu():
	var font = ThemeDB.fallback_font
	var title_x = 360.0  # title column centre; the mascot owns the right side

	# Title with drop shadow — it bounces on every beat of the menu theme
	var title = "SLICE IT!"
	var bounce := MinigameBase.beat_pulse(6.0)
	var tsize := int(64 + bounce * 4)
	var title_size = font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, tsize)
	draw_string(font, Vector2(title_x - title_size.x / 2 + 4, 124), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsize, Color(0.25, 0.15, 0.05, 0.7))
	draw_string(font, Vector2(title_x - title_size.x / 2, 120), title, HORIZONTAL_ALIGNMENT_LEFT, -1, tsize, Color.GOLD)

	# Subtitle + version
	_text(font, "The Potato Cutting Championship", title_x, 160, 22, Color(0.35, 0.22, 0.1))
	_text(font, "v" + UpdateManager.current_version, title_x, 186, 15, Color(0.45, 0.32, 0.2))
	# farm wallet, so progress is visible from the front door
	_text(font, "Wallet: %s coins" % Fmt.coins(SaveDataManager.wallet()), title_x, 210, 16, Color(0.72, 0.52, 0.12))

	# chef career card under the mascot, so the rank shows from the front door
	_draw_career_card(font, 1010.0, 560.0)

	# now playing — the menu theme is composed on the fly; give it a name
	if AudioManager.song.has("title") and SaveDataManager.settings.get("sound_enabled", true):
		_text(font, "♪ now playing: \"%s\"" % AudioManager.song["title"], 1010.0, 640, 14, Color(0.55, 0.42, 0.28, 0.9))

	# launch check found a newer release — nudge towards the updater
	if UpdateManager.state == "available":
		var nudge = "Update available: v%s — press [0]" % UpdateManager.latest_version
		var pulse = 0.7 + 0.3 * sin(Time.get_ticks_msec() / 400.0)
		_text(font, nudge, title_x, 700, 15, Color(1.0, 0.75, 0.2, pulse))

	# Menu in a walnut panel
	var row_h := 32.0
	var panel_rect = Rect2(title_x - 220, 226, 440, 40 + menu_items.size() * row_h)
	GameHUD.panel_style().draw(get_canvas_item(), panel_rect)
	_item_rects.clear()
	var y_pos = panel_rect.position.y + 40
	for i in range(menu_items.size()):
		var row_rect := Rect2(panel_rect.position.x + 14, y_pos - 23, panel_rect.size.x - 28, row_h - 2)
		_item_rects.append(row_rect)
		var active := i == selected_menu_item
		if active:
			# glowing highlight bar, a bright left accent and a pointer
			var pulse := 0.16 + 0.07 * sin(Time.get_ticks_msec() / 280.0)
			draw_rect(row_rect, Color(0.85, 0.68, 0.3, pulse))
			draw_rect(Rect2(row_rect.position, Vector2(4, row_rect.size.y)), Color(1.0, 0.8, 0.3, 0.95))
			var tx: float = panel_rect.position.x + 26
			var ty: float = y_pos - 13
			draw_colored_polygon(PackedVector2Array([
				Vector2(tx, ty), Vector2(tx, ty + 12), Vector2(tx + 9, ty + 6)]), Color.GOLD)
		var key_label := "ESC" if menu_items[i][1] == KEY_ESCAPE else OS.get_keycode_string(menu_items[i][1])
		var color = Color.GOLD if active else Color(0.95, 0.9, 0.8)
		draw_string(font, Vector2(panel_rect.position.x + 44, y_pos), "[%s]" % key_label, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(0.75, 0.62, 0.4) if not active else Color(1.0, 0.85, 0.4))
		draw_string(font, Vector2(panel_rect.position.x + 98, y_pos), menu_items[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, color)
		# the farm teaser: "· 9 ripe · +1.2K waiting", right-aligned in the row
		if menu_items[i][2] == "farm" and farm_teaser != "":
			var tz := "· " + farm_teaser
			var tw := font.get_string_size(tz, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
			var lw := font.get_string_size(menu_items[i][0], HORIZONTAL_ALIGNMENT_LEFT, -1, 19).x
			var tx0 := maxf(panel_rect.position.x + 98 + lw + 8, row_rect.end.x - 8 - tw)
			draw_string(font, Vector2(tx0, y_pos - 1), tz, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
					Color(0.75, 0.95, 0.55) if active else Color(0.62, 0.8, 0.48))
		# a little "new" sparkle on Concert
		if menu_items[i][2] == "concert":
			var sp := 0.6 + 0.4 * sin(Time.get_ticks_msec() / 200.0)
			draw_circle(Vector2(panel_rect.end.x - 30, y_pos - 7), 4.0 + sp * 2.0, Color(1.0, 0.8, 0.3, sp))
		y_pos += row_h

	# clickability hint
	draw_string(font, Vector2(panel_rect.position.x + 16, panel_rect.position.y + panel_rect.size.y + 22),
			"Click an option, or Up/Down + Enter  ·  M sound %s  ·  F11 fullscreen" % (
				"on" if AudioManager.sound_enabled else "off"), HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.6, 0.55, 0.45))

# Chef rank + XP-to-next-rank bar, centred on (cx, cy).
func _draw_career_card(font: Font, cx: float, cy: float):
	var rank = SaveDataManager.career_rank()
	var xp = SaveDataManager.career_xp()
	GameHUD.panel_style().draw(get_canvas_item(), Rect2(cx - 150, cy - 30, 300, 64))
	_text(font, "CHEF RANK", cx, cy - 12, 12, Color(0.7, 0.6, 0.4))
	_text(font, "%s · %d XP" % [rank["name"], xp], cx, cy + 8, 16, Color(1.0, 0.85, 0.35))
	var bar_w = 260.0
	var bx = cx - bar_w / 2
	var by = cy + 18.0
	var span = maxi(1, int(rank["next_floor"]) - int(rank["floor"]))
	var prog = clampf(float(xp - int(rank["floor"])) / float(span), 0.0, 1.0)
	draw_rect(Rect2(bx, by, bar_w, 7), Color(0.2, 0.15, 0.1, 0.8))
	draw_rect(Rect2(bx, by, bar_w * prog, 7), Color(0.9, 0.72, 0.25))

func _draw_submenu():
	var viewport_size = get_viewport_rect().size
	var centre_x = viewport_size.x / 2

	draw_rect(Rect2(0, 0, viewport_size.x, viewport_size.y), Color(0, 0, 0, 0.75))

	match current_submenu:
		"leaderboard": _draw_leaderboard_screen(centre_x)
		"settings":    _draw_settings_screen(centre_x)
		"calibrate":   _draw_calibrate_screen(centre_x)
		"about":       _draw_about_screen(centre_x)
		"achievements": _draw_achievements_screen(centre_x)

func _draw_achievements_screen(centre_x: float):
	var font := ThemeDB.fallback_font
	var all := GameData.achievements()
	var got := 0
	for a in all:
		if SaveDataManager.is_achievement_unlocked(a.get("id", "")):
			got += 1
	_text(font, "ACHIEVEMENTS", centre_x, 90, 32, Color.GOLD)
	_text(font, "%d / %d unlocked" % [got, all.size()], centre_x, 120, 16, Color(0.7, 0.65, 0.55))

	var y := 160.0
	for a in all:
		var unlocked: bool = SaveDataManager.is_achievement_unlocked(a.get("id", ""))
		var icon := "★" if unlocked else "·"
		var name_col := Color(1.0, 0.85, 0.35) if unlocked else Color(0.55, 0.5, 0.45)
		draw_string(font, Vector2(centre_x - 280, y), "%s  %s" % [icon, a.get("name", "?")],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 20, name_col)
		var desc: String = a.get("desc", "") if unlocked else "???"
		draw_string(font, Vector2(centre_x - 40, y), desc, HORIZONTAL_ALIGNMENT_LEFT, -1, 15,
				Color(0.8, 0.75, 0.65) if unlocked else Color(0.45, 0.4, 0.36))
		y += 40.0

	_text(font, "[SPACE] Back", centre_x, 690, 16, Color.GRAY)

func _draw_leaderboard_screen(centre_x: float):
	var font := ThemeDB.fallback_font
	_text(font, "LEADERBOARD", centre_x, 100, 32, Color.GOLD)

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
		_text(font, "Local scores (Supabase not configured — see README)", centre_x, tab_y, 13, Color(0.55, 0.5, 0.45))
		tab_y += 24.0

	var y_pos := tab_y + 24.0
	var entries: Array = []
	if show_online_tab:
		if online_loading:
			_text(font, "Loading…", centre_x, y_pos, 18, Color(0.7, 0.65, 0.55))
		elif online_scores.is_empty():
			_text(font, "No online scores yet.", centre_x, y_pos, 18, Color(0.7, 0.65, 0.55))
		entries = online_scores
	else:
		entries = SaveDataManager.get_leaderboard("", 10)
		if entries.is_empty():
			_text(font, "No scores yet — play a run!", centre_x, y_pos, 18, Color(0.7, 0.65, 0.55))
	for i in range(mini(entries.size(), 10)):
		var entry = entries[i]
		var text := "#%d  %-14s  %7d pts   %s" % [
			i + 1, str(entry.get("name", "?")),
			int(entry.get("score", 0)),
			str(entry.get("mode", "?")).capitalize().replace("_", " ")
		]
		draw_string(font, Vector2(centre_x - 240, y_pos), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
				Color.GOLD if i == 0 else Color.WHITE)
		y_pos += 36.0

	_text(font, "[SPACE] Back", centre_x, 680, 16, Color.GRAY)

func _draw_settings_screen(centre_x: float):
	var font := ThemeDB.fallback_font
	_text(font, "SETTINGS", centre_x, 86, 32, Color.GOLD)
	var panel := Rect2(centre_x - 330, 112, 660, 40 + SETTINGS_ROWS.size() * 46)
	GameHUD.panel_style(Color(0.16, 0.1, 0.06, 0.9)).draw(get_canvas_item(), panel)
	_settings_rects.clear()
	var y := panel.position.y + 50.0
	for i in SETTINGS_ROWS.size():
		var row: String = SETTINGS_ROWS[i]
		var r := Rect2(panel.position.x + 16, y - 30, panel.size.x - 32, 42)
		_settings_rects.append(r)
		var active := i == settings_sel
		if active:
			draw_rect(r, Color(0.85, 0.68, 0.3, 0.18))
			draw_rect(Rect2(r.position, Vector2(4, r.size.y)), Color(1.0, 0.8, 0.3))
		var col := Color.GOLD if active else Color(0.95, 0.9, 0.8)
		draw_string(font, Vector2(r.position.x + 22, y), SETTINGS_LABELS[row], HORIZONTAL_ALIGNMENT_LEFT, -1, 19, col)
		var val := _settings_value(row)
		if active and row != "calibrate":
			val = "◀  " + val + "  ▶"
		var vw := font.get_string_size(val, HORIZONTAL_ALIGNMENT_LEFT, -1, 17).x
		draw_string(font, Vector2(r.end.x - 20 - vw, y), val, HORIZONTAL_ALIGNMENT_LEFT, -1, 17,
				Color(1.0, 0.85, 0.45) if active else Color(0.8, 0.75, 0.65))
		y += 46.0
	_text(font, "↑↓ choose · ←→ change · ENTER toggle · 1/2/3 save file · ESC back", centre_x,
			panel.end.y + 28, 14, Color(0.6, 0.55, 0.45))
	if SETTINGS_ROWS[settings_sel] == "slot":
		_text(font, "Each save file is a whole separate game — an empty slot starts fresh.", centre_x,
				panel.end.y + 52, 13, Color(0.6, 0.55, 0.45))

func _draw_about_screen(centre_x: float):
	var font := ThemeDB.fallback_font
	_text(font, "SLICE IT!", centre_x, 92, 36, Color.GOLD)
	_text(font, "The Potato Cutting Championship  ·  v" + UpdateManager.current_version, centre_x, 122, 17,
			Color(0.8, 0.72, 0.58))

	var about_text := ("A rhythm-action game about knives, starch and questionable life choices.\n" +
		"Every sound and every note of music is synthesized live by the game —\n" +
		"no audio files, no image files, all procedural.\n\n" +
		"Cut on the beat across six championship venues, survive endless waves,\n" +
		"play a generated song in Concert mode, duel a friend over LAN, run a\n" +
		"potato farm, or drop into SPUD BLASTER — a first-person potato deathmatch.\n\n" +
		"Crafted with Godot Engine 4.2")
	draw_multiline_string(font, Vector2(centre_x - 300, 172), about_text,
			HORIZONTAL_ALIGNMENT_CENTER, 600, 16, -1, Color.WHITE)

	# ── updates ──
	var status := ""
	var col := Color.WHITE
	var action := ""
	match UpdateManager.state:
		"checking":
			status = "Checking for updates…"
			col = Color(0.7, 0.65, 0.55)
		"uptodate":
			status = "You're on the newest version!"
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
	GameHUD.panel_style(Color(0.16, 0.1, 0.06, 0.9)).draw(get_canvas_item(), Rect2(centre_x - 330, 430, 660, 140))
	_text(font, "UPDATES", centre_x, 462, 15, Color(0.85, 0.68, 0.3))
	_text(font, status, centre_x, 500, 20, col)
	if action != "":
		_text(font, action, centre_x, 540, 15, Color(0.75, 0.7, 0.62))
	_text(font, "Updates come from github.com/%s/releases" % UpdateManager.REPO, centre_x, 600, 13,
			Color(0.55, 0.5, 0.45))
