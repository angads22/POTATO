extends Node2D
class_name FpsLobbyController

# Lobby for the SPUD BLASTER 3D arena: host (LAN + internet via UPnP), join by
# IP, or practice solo against bots. Keyboard-driven, procedural art — same
# look as the rhythm-duel lobby. The host starts the match for everyone once at
# least one opponent has joined.

enum Phase { MENU, HOSTING, JOINING, CONNECTED, ERROR }

var phase: Phase = Phase.MENU
var ip_chars: Array[String] = []
var status_msg := ""
var blink := 0.0

func _ready() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	FpsNetwork.roster_changed.connect(_on_roster_changed)
	FpsNetwork.server_started.connect(queue_redraw)
	FpsNetwork.public_address_resolved.connect(queue_redraw)
	FpsNetwork.connection_failed.connect(_on_conn_failed)
	FpsNetwork.match_starting.connect(_start_arena)

func _exit_tree() -> void:
	for s in [
		[FpsNetwork.roster_changed, _on_roster_changed],
		[FpsNetwork.server_started, queue_redraw],
		[FpsNetwork.public_address_resolved, queue_redraw],
		[FpsNetwork.connection_failed, _on_conn_failed],
		[FpsNetwork.match_starting, _start_arena],
	]:
		if s[0].is_connected(s[1]):
			s[0].disconnect(s[1])

func _process(delta: float) -> void:
	blink += delta
	queue_redraw()

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match phase:
		Phase.MENU:
			match event.keycode:
				KEY_1: _do_host()
				KEY_2:
					phase = Phase.JOINING
					ip_chars.clear()
				KEY_3: _do_practice()
				KEY_ESCAPE:
					get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")
		Phase.JOINING:
			match event.keycode:
				KEY_ENTER, KEY_KP_ENTER: _do_join("".join(ip_chars))
				KEY_BACKSPACE:
					if ip_chars.size() > 0:
						ip_chars.pop_back()
				KEY_ESCAPE:
					phase = Phase.MENU
				_:
					var ch := char(event.unicode)
					if (ch >= "0" and ch <= "9") or ch == ".":
						ip_chars.append(ch)
		Phase.HOSTING:
			match event.keycode:
				KEY_ENTER, KEY_KP_ENTER:
					if FpsNetwork.players.size() >= 2:
						FpsNetwork.start_match()
				KEY_ESCAPE:
					FpsNetwork.leave()
					phase = Phase.MENU
		Phase.CONNECTED:
			if event.keycode == KEY_ESCAPE:
				FpsNetwork.leave()
				phase = Phase.MENU
		Phase.ERROR:
			phase = Phase.MENU

func _do_host() -> void:
	var err := FpsNetwork.host_game()
	if err != OK:
		status_msg = "Could not open port %d — already in use?" % FpsNetwork.PORT
		phase = Phase.ERROR
	else:
		phase = Phase.HOSTING

func _do_join(ip: String) -> void:
	if ip.strip_edges() == "":
		return
	var err := FpsNetwork.join_game(ip)
	if err != OK:
		status_msg = "Could not start a connection to %s" % ip
		phase = Phase.ERROR
	else:
		status_msg = "Connecting to %s…" % ip

func _do_practice() -> void:
	FpsNetwork.start_offline()
	_start_arena()

func _start_arena() -> void:
	get_tree().change_scene_to_file("res://scenes/Fps/FpsArena.tscn")

func _on_roster_changed() -> void:
	if FpsNetwork.mode == "client" and phase == Phase.JOINING:
		phase = Phase.CONNECTED
	queue_redraw()

func _on_conn_failed() -> void:
	status_msg = "Connection lost — check the IP / that the host is open."
	phase = Phase.ERROR

# ── drawing ──────────────────────────────────────────────────────────────────

func _draw() -> void:
	var font := ThemeDB.fallback_font
	var cx := 640.0
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.09, 0.07, 0.05))

	var title := "SPUD BLASTER"
	var ts := font.get_string_size(title, HORIZONTAL_ALIGNMENT_CENTER, -1, 46)
	draw_string(font, Vector2(cx - ts.x / 2 + 3, 95), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color(0.2, 0.12, 0.05, 0.7))
	draw_string(font, Vector2(cx - ts.x / 2, 92), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 46, Color.GOLD)
	var sub := "First-person potato deathmatch"
	var ss := font.get_string_size(sub, HORIZONTAL_ALIGNMENT_CENTER, -1, 17)
	draw_string(font, Vector2(cx - ss.x / 2, 120), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.75, 0.66, 0.42))
	draw_line(Vector2(cx - 230, 138), Vector2(cx + 230, 138), Color(0.85, 0.68, 0.3, 0.5), 2.0)

	match phase:
		Phase.MENU: _draw_menu(font, cx)
		Phase.HOSTING: _draw_hosting(font, cx)
		Phase.JOINING: _draw_joining(font, cx)
		Phase.CONNECTED: _draw_connected(font, cx)
		Phase.ERROR: _draw_error(font, cx)

func _draw_menu(font: Font, cx: float) -> void:
	var items := [
		["[1] Host a game", "Open this machine. Friends join on your LAN, or over the internet (UPnP)."],
		["[2] Join a game", "Enter a host's IP — a 192.168.x address on LAN, or their public IP."],
		["[3] Practice solo", "Warm up in an empty arena against target-dummy bots."],
		["[ESC] Back", ""],
	]
	var y := 210.0
	for item in items:
		draw_string(font, Vector2(cx - 250, y), item[0], HORIZONTAL_ALIGNMENT_LEFT, -1, 24, Color.WHITE)
		if item[1] != "":
			draw_string(font, Vector2(cx - 250, y + 26), item[1], HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.62, 0.57, 0.47))
		y += 78.0

func _draw_hosting(font: Font, cx: float) -> void:
	draw_string(font, Vector2(cx - 250, 185), "LAN address (same Wi-Fi / network):", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.65, 0.55))
	var lan := FpsNetwork.lan_ip if FpsNetwork.lan_ip != "" else "(no LAN address found)"
	draw_string(font, Vector2(cx - 250, 218), lan, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.GOLD)

	draw_string(font, Vector2(cx - 250, 262), "Internet address (share to play globally):", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.7, 0.65, 0.55))
	var pub_txt := ""
	var pub_col := Color(0.6, 0.6, 0.6)
	match FpsNetwork.upnp_status:
		"working":
			pub_txt = "opening port via UPnP" + ".".repeat(int(blink * 2.0) % 4)
		"done":
			pub_txt = "%s:%d" % [FpsNetwork.public_ip, FpsNetwork.PORT]
			pub_col = Color.LIGHT_GREEN
		"unavailable":
			pub_txt = "UPnP unavailable — forward UDP %d on your router, then share your public IP" % FpsNetwork.PORT
			pub_col = Color(0.95, 0.7, 0.4)
		_:
			pub_txt = "…"
	draw_string(font, Vector2(cx - 250, 292), pub_txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, pub_col)

	# roster
	draw_string(font, Vector2(cx - 250, 350), "Players:", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.8, 0.75, 0.6))
	var y := 380.0
	for pid in FpsNetwork.players.keys():
		var nm := str(FpsNetwork.players[pid].get("name", "Chef"))
		var tag := "  (you)" if pid == FpsNetwork.local_id() else ""
		draw_string(font, Vector2(cx - 230, y), "• " + nm + tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		y += 28.0

	if FpsNetwork.players.size() >= 2:
		draw_string(font, Vector2(cx - 250, 560), "[ENTER] Start match", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.LIGHT_GREEN)
	else:
		var dots := ".".repeat(int(blink * 2.0) % 4)
		draw_string(font, Vector2(cx - 250, 560), "Waiting for players to join" + dots, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color(0.9, 0.85, 0.7))
	draw_string(font, Vector2(cx - 250, 600), "[ESC] Cancel", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.55, 0.5))

func _draw_joining(font: Font, cx: float) -> void:
	draw_string(font, Vector2(cx - 250, 210), "Enter the host's IP address:", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color(0.7, 0.65, 0.55))
	var typed := "".join(ip_chars)
	var cursor := "|" if fmod(blink, 1.0) < 0.5 else " "
	draw_rect(Rect2(cx - 252, 232, 504, 56), Color(0.18, 0.12, 0.06))
	draw_rect(Rect2(cx - 252, 232, 504, 56), Color.GOLD, false, 2.0)
	draw_string(font, Vector2(cx - 235, 271), typed + cursor, HORIZONTAL_ALIGNMENT_LEFT, -1, 30, Color.WHITE)
	draw_string(font, Vector2(cx - 250, 322), "[ENTER] Connect     [ESC] Back", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.55, 0.5))
	draw_string(font, Vector2(cx - 250, 350), status_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(0.75, 0.7, 0.6))

func _draw_connected(font: Font, cx: float) -> void:
	draw_string(font, Vector2(cx - 200, 280), "Connected! Waiting for the host to start…", HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.LIGHT_GREEN)
	var y := 340.0
	for pid in FpsNetwork.players.keys():
		var nm := str(FpsNetwork.players[pid].get("name", "Chef"))
		var tag := "  (you)" if pid == FpsNetwork.local_id() else ""
		draw_string(font, Vector2(cx - 180, y), "• " + nm + tag, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
		y += 28.0
	draw_string(font, Vector2(cx - 80, 600), "[ESC] Leave", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.55, 0.5))

func _draw_error(font: Font, cx: float) -> void:
	draw_string(font, Vector2(cx - 150, 290), "Connection problem", HORIZONTAL_ALIGNMENT_LEFT, -1, 26, Color.ORANGE_RED)
	draw_string(font, Vector2(cx - 250, 335), status_msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 17, Color(0.9, 0.8, 0.7))
	draw_string(font, Vector2(cx - 80, 420), "[Any key] Back", HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0.6, 0.55, 0.5))
