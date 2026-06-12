extends Node2D
class_name LobbyController

# LAN lobby: choose to host or join a game, then transition to gameplay
# once both players are connected. Fully keyboard-driven, procedural art.

enum Phase { MENU, HOSTING, JOINING, CONNECTED, ERROR }

var phase: Phase = Phase.MENU
var ip_chars: Array[String] = []
var my_ip: String = ""
var status_msg: String = ""
var blink: float = 0.0

func _ready():
	MultiplayerManager.peer_joined.connect(_on_peer_joined)
	MultiplayerManager.peer_left.connect(_on_peer_left)
	MultiplayerManager.connection_failed.connect(_on_conn_failed)
	MultiplayerManager.game_ready.connect(_on_game_ready)

	for ip in IP.get_local_addresses():
		if not ip.contains(":") and (ip.begins_with("192.168") or
				ip.begins_with("10.") or ip.begins_with("172.")):
			my_ip = ip
			break

func _exit_tree():
	if MultiplayerManager.peer_joined.is_connected(_on_peer_joined):
		MultiplayerManager.peer_joined.disconnect(_on_peer_joined)
	if MultiplayerManager.peer_left.is_connected(_on_peer_left):
		MultiplayerManager.peer_left.disconnect(_on_peer_left)
	if MultiplayerManager.connection_failed.is_connected(_on_conn_failed):
		MultiplayerManager.connection_failed.disconnect(_on_conn_failed)
	if MultiplayerManager.game_ready.is_connected(_on_game_ready):
		MultiplayerManager.game_ready.disconnect(_on_game_ready)

func _input(event: InputEvent):
	if not event is InputEventKey or not event.pressed:
		return
	match phase:
		Phase.MENU:
			match event.keycode:
				KEY_1: _do_host()
				KEY_2:
					phase = Phase.JOINING
					ip_chars.clear()
					queue_redraw()
				KEY_ESCAPE:
					get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		Phase.JOINING:
			match event.keycode:
				KEY_ENTER: _do_join("".join(ip_chars))
				KEY_BACKSPACE:
					if ip_chars.size() > 0:
						ip_chars.pop_back()
						queue_redraw()
				KEY_ESCAPE:
					phase = Phase.MENU
					queue_redraw()
				_:
					var ch := char(event.unicode)
					if (ch >= "0" and ch <= "9") or ch == ".":
						ip_chars.append(ch)
						queue_redraw()
		Phase.HOSTING, Phase.CONNECTED:
			if event.keycode == KEY_ESCAPE:
				MultiplayerManager.leave_game()
				phase = Phase.MENU
				queue_redraw()
		Phase.ERROR:
			phase = Phase.MENU
			queue_redraw()

func _do_host():
	var err := MultiplayerManager.host_game()
	if err != OK:
		status_msg = "Failed to open port %d — is it already in use?" % MultiplayerManager.PORT
		phase = Phase.ERROR
	else:
		phase = Phase.HOSTING
	queue_redraw()

func _do_join(ip: String):
	if ip == "":
		return
	var err := MultiplayerManager.join_game(ip)
	if err != OK:
		status_msg = "Could not connect to %s" % ip
		phase = Phase.ERROR
	else:
		status_msg = "Connecting to %s…" % ip
	queue_redraw()

func _on_peer_joined():
	if MultiplayerManager.is_host:
		status_msg = "Opponent connected!"
		phase = Phase.CONNECTED
		queue_redraw()
		await get_tree().create_timer(1.2).timeout
		_start()

func _on_peer_left():
	if phase == Phase.CONNECTED:
		status_msg = "Opponent disconnected."
		phase = Phase.ERROR
		queue_redraw()

func _on_conn_failed():
	status_msg = "Connection failed — check the IP and try again."
	phase = Phase.ERROR
	queue_redraw()

func _on_game_ready():
	# client received the session seed from the host
	phase = Phase.CONNECTED
	status_msg = "Connected! Starting…"
	queue_redraw()
	await get_tree().create_timer(1.0).timeout
	_start()

func _start():
	GameManager.start_game("championship")
	get_tree().change_scene_to_file("res://scenes/Gameplay/GameplayScene.tscn")

func _process(delta):
	blink += delta
	queue_redraw()

func _draw():
	var font := ThemeDB.fallback_font
	var cx := 640.0

	draw_rect(Rect2(0, 0, 1280, 720), Color(0.11, 0.08, 0.05))

	# Title
	var title := "MULTIPLAYER"
	var ts := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 44)
	draw_string(font, Vector2(cx - ts.x / 2 + 3, 103), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color(0.2, 0.12, 0.05, 0.7))
	draw_string(font, Vector2(cx - ts.x / 2, 100), title,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 44, Color.GOLD)
	draw_line(Vector2(cx - 210, 120), Vector2(cx + 210, 120), Color(0.85, 0.68, 0.3, 0.5), 2.0)

	match phase:
		Phase.MENU:     _draw_menu(font, cx)
		Phase.HOSTING:  _draw_hosting(font, cx)
		Phase.JOINING:  _draw_joining(font, cx)
		Phase.CONNECTED: _draw_connected(font, cx)
		Phase.ERROR:    _draw_error(font, cx)

func _draw_menu(font: Font, cx: float):
	draw_string(font, Vector2(cx - 230, 195),
			"Play together on the same local network (Wi-Fi or LAN).",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.75, 0.7, 0.6))

	var items := [
		["[1] Host a game",
			"Open this machine to others — share your IP to let them in."],
		["[2] Join a game",
			"Enter a friend's IP address to join their game."],
		["[ESC] Back", ""],
	]
	var y := 268.0
	for item in items:
		draw_string(font, Vector2(cx - 230, y), item[0],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
		if item[1] != "":
			draw_string(font, Vector2(cx - 230, y + 28), item[1],
					HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.6, 0.55, 0.45))
		y += 80.0

func _draw_hosting(font: Font, cx: float):
	draw_string(font, Vector2(cx - 230, 185), "Your LAN IP address:",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.65, 0.55))

	var ip_col := Color.GOLD if my_ip != "" else Color(0.55, 0.55, 0.55)
	var ip_txt := my_ip if my_ip != "" else "(detecting…)"
	draw_string(font, Vector2(cx - 230, 228), ip_txt,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 36, ip_col)

	draw_string(font, Vector2(cx - 230, 285),
			"Share this address with your opponent and wait here.",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.65, 0.6, 0.5))

	var dots := ".".repeat(int(blink * 2.0) % 4)
	draw_string(font, Vector2(cx - 100, 385), "Waiting for opponent" + dots,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.85, 0.7))
	draw_string(font, Vector2(cx - 80, 565), "[ESC] Cancel",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.55, 0.5))

func _draw_joining(font: Font, cx: float):
	draw_string(font, Vector2(cx - 230, 200), "Enter the host's IP address:",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.65, 0.55))

	var typed := "".join(ip_chars)
	var cursor := "|" if fmod(blink, 1.0) < 0.5 else " "
	draw_rect(Rect2(cx - 232, 220, 464, 56), Color(0.18, 0.12, 0.06))
	draw_rect(Rect2(cx - 232, 220, 464, 56), Color.GOLD, false, 2.0)
	draw_string(font, Vector2(cx - 215, 259), typed + cursor,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)

	draw_string(font, Vector2(cx - 230, 310), "[ENTER] Connect    [ESC] Back",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.55, 0.5))
	draw_string(font, Vector2(cx - 230, 338), status_msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.7, 0.6))

func _draw_connected(font: Font, cx: float):
	var ts := font.get_string_size(status_msg, HORIZONTAL_ALIGNMENT_CENTER, -1, 28)
	draw_string(font, Vector2(cx - ts.x / 2, 340), status_msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.LIGHT_GREEN)

func _draw_error(font: Font, cx: float):
	draw_string(font, Vector2(cx - 150, 290), "Connection problem",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.ORANGE_RED)
	draw_string(font, Vector2(cx - 230, 335), status_msg,
			HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.9, 0.8, 0.7))
	draw_string(font, Vector2(cx - 80, 420), "[Any key] Back",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.55, 0.5))
