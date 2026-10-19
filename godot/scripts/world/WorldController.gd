extends Node2D
class_name WorldController

# Shared base for the walkable overworld scenes (the farm and the town):
# WASD movement against rect blockers, the camera with its two zoom levels
# (overview ↔ follow), the real-clock night tint, the input pipeline (keys,
# mouse buttons, wheel, trackpad pan/magnify), click-able stations with a
# proximity prompt, the Farm Book drawer, the knife stand and popup/banner
# feedback. Every real input calls FarmEconomy.note_input (once per frame at
# most) so Spudlings never clock in while you are shopping, and both maps
# settle the farm every 0.5 s.
#
# Input routing (design §7.1): _modal_input (the farm's Pip's note) → the open
# drawer (nothing on the HUD is meant to sit over it, so a click inside it is
# always the drawer's) → HUD hit regions → the world. Subclasses hook in
# through the virtuals below; test drivers can call handle_input(event)
# directly or push events with get_tree().root.push_input(ev, true) (both
# reach the same code; Input.parse_input_event never reaches a headless
# scene, whose window is 0x0).

const PLAYER_SPEED := 290.0
const POPUP_LIFE := 1.9
const BANNER_LIFE := 2.8
const SETTLE_EVERY := 0.5
const FOLLOW_ZOOM := 1.0
const NIGHT_TINT_MAX := 0.35     # the night tint never hides the farm
const ROLL_S := 0.8              # wallet roll-up time
const GESTURE_COOLDOWN := 0.35
const SCROLL_COOLDOWN := 0.12    # trackpad swipes / hi-res wheels over the drawer
const SCROLL_STEP := 2.0         # accumulated pan delta (or wheel factor) per row
const ESC_ARM_S := 1.5           # Esc with nothing open: press again within this to leave
const VIEW_REFRESH_S := 0.1      # field views / prompt refresh (10 Hz; actions refresh at once)

# Set by travel gates just before change_scene_to_file so the destination
# scene knows where to put the player.
static var travel_spawn := ""

var player: FarmerVisual
var camera: Camera2D
var hud: WorldHUD
var tint: ColorRect
var world_bg               # background node exposing a night01 property
var book: FarmBook
var rng := RandomNumberGenerator.new()

var world_size := Vector2(2560, 1440)
var night01 := 0.0         # 0 = day, 1 = deep night (real local clock)
var prompt := ""
var prompt_action := Callable()
var stations: Array = []   # [{id, pos, r, text, act: Callable, rect: Rect2 (world, clickable)}]
var open_shop := ""        # "" or "knives" (the town's knife stand)
var shop_sel := 0
var popups: Array = []     # {text, color, age}
var banner_text := ""
var banner_sub := ""
var banner_age := 99.0
var blockers: Array = []   # Rect2s the player can't walk through

var overview := false      # zoom state: true = overview, false = follow
var zoom_now := 1.0
var wallet_shown := 0.0    # the HUD's rolling wallet
var input_count := 0       # real inputs noted (test hook; at most one per frame)
var input_serial := 0      # every real input that reached the scene (not frame-deduped)
var _roll_from := 0.0
var _roll_t := 1.0
var _roll_to := 0
var _tick_t := 0.0
var _settle_t := 0.0
var _input_frame := -1
var _step_clock := 0.0
var _gesture_t := 0.0
var _swing_cool := 0.0
var _scroll_t := 0.0
var _scroll_acc := 0.0
var _esc_t := 0.0
var _scan_t := 0.0
var _scan_pos := Vector2(INF, INF)
var _scan_at := 0

# ── subclass hooks ──

func _world_size() -> Vector2:
	return Vector2(2560, 1440)

func _spawn_point() -> Vector2:
	return world_size / 2.0

func _build_world():
	pass

func _make_hud() -> WorldHUD:
	return WorldHUD.new()

func _music_track() -> String:
	return "farm"

func _tick(_delta: float):
	pass

# Zoom that shows the whole map (the farm uses farm.json start.zoom).
func overview_zoom() -> float:
	return minf(1280.0 / world_size.x, 720.0 / world_size.y)

func _initial_overview() -> bool:
	return false

func _on_zoom_changed():
	pass

# The farm's Pip's note: return true to consume the event before anything
# else sees it (and before the input is stamped).
func _modal_input(_event: InputEvent) -> bool:
	return false

# Scene keys after the drawer had its turn; return true when handled.
func _scene_key(_event: InputEventKey) -> bool:
	return false

# A HUD region the base didn't handle.
func _on_hud(_id: String, _data) -> bool:
	return false

# A click that no HUD region or drawer took. world_pos is in world space.
func _world_click(world_pos: Vector2, _screen_pos: Vector2) -> bool:
	for s in stations:
		if s.has("rect") and (s["rect"] as Rect2).has_point(world_pos):
			face_toward(world_pos)
			(s["act"] as Callable).call()
			return true
	return false

func _on_settle(_res: Dictionary):
	pass

# ── lifecycle ──

func _ready():
	rng.randomize()
	SaveDataManager.set_low_power_ok(true)
	AudioManager.play_music(_music_track())
	world_size = _world_size()

	# Dark hedge-green backdrop beyond the map edges (the overview shows a
	# little past the world on wide screens).
	var backdrop := ColorRect.new()
	backdrop.position = Vector2(-3000, -3000)
	backdrop.size = world_size + Vector2(6000, 6000)
	backdrop.color = Color(0.12, 0.22, 0.1)
	backdrop.z_index = -10
	backdrop.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(backdrop)

	_build_world()

	player = FarmerVisual.new()
	player.position = _spawn_point()
	player.z_index = 2
	add_child(player)

	camera = Camera2D.new()
	camera.position_smoothing_enabled = true
	camera.position_smoothing_speed = 6.0
	camera.limit_smoothed = true
	add_child(camera)
	camera.make_current()

	# night tint sits between the world and the HUD
	var tint_layer := CanvasLayer.new()
	tint_layer.layer = 5
	tint = ColorRect.new()
	tint.size = Vector2(1280, 720)
	tint.color = Color(0.04, 0.05, 0.18, 0.0)
	tint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tint_layer.add_child(tint)
	add_child(tint_layer)

	book = FarmBook.new()
	book.ctrl = self

	var hud_layer := CanvasLayer.new()
	hud_layer.layer = 10
	hud = _make_hud()
	hud.ctrl = self
	hud_layer.add_child(hud)
	add_child(hud_layer)

	wallet_shown = SaveDataManager.wallet()
	_roll_to = SaveDataManager.wallet()
	overview = _initial_overview()
	zoom_now = overview_zoom() if overview else FOLLOW_ZOOM
	_update_night()
	_update_camera(0.0)
	snap_camera()

func _exit_tree():
	SaveDataManager.flush_farm()
	SaveDataManager.set_low_power_ok(false)

func _process(delta):
	_update_night()
	_settle_t += delta
	if _settle_t >= SETTLE_EVERY:
		_settle_t = 0.0
		settle_now()
	if can_move():
		_move_player(delta)
	else:
		player.moving = false
	_update_camera(delta)
	_gesture_t = maxf(0.0, _gesture_t - delta)
	_swing_cool = maxf(0.0, _swing_cool - delta)
	_scroll_t = maxf(0.0, _scroll_t - delta)
	_esc_t = maxf(0.0, _esc_t - delta)
	_tick(delta)
	# the prompt only changes when the player moves, a drawer opens/closes or a
	# field's countdown ticks: rescan on movement, else at 10 Hz
	_scan_t -= delta
	var now := now_ms()
	if _scan_t <= 0.0 or player.position != _scan_pos or absi(now - _scan_at) >= int(VIEW_REFRESH_S * 1000.0):
		_scan_t = VIEW_REFRESH_S
		_scan_pos = player.position
		_scan_at = now
		_scan_interactions()
	_roll_wallet(delta)
	banner_age += delta
	for p in popups:
		p.age += delta
	popups = popups.filter(func(p): return p.age < POPUP_LIFE)

# ── farm clock helpers ──

func farm() -> Dictionary:
	return SaveDataManager.farm      # re-read every time: slots/tests replace it

func now_ms() -> int:
	return FarmClock.now_ms()

func tz() -> int:
	return FarmClock.tz_s()

# The 0.5 s settle (idempotent). Requests a save when anything moved.
func settle_now() -> Dictionary:
	var f := farm()
	if not FarmView.started(f):
		return {}
	var res := FarmEconomy.settle(f, now_ms(), tz())
	if int(res.get("coins", 0)) > 0 or int(res.get("picks", 0)) > 0 or not res.get("pages", []).is_empty() \
			or not res.get("events", []).is_empty() or bool(res.get("rebased", false)):
		SaveDataManager.request_farm_save()
		_react(res)
		book.invalidate()
		if hud != null:
			hud.mark_dirty()
	_on_settle(res)
	return res

# Real local time → night amount: clear day 07:00-18:00, dusk to 21:00, full
# night until 05:00, dawn to 07:00.
static func night_amount(now: int, tz_s: int) -> float:
	var sod := posmod(int(floor(now / 1000.0)) + tz_s, 86400)
	var h := sod / 3600.0
	if h >= 7.0 and h < 18.0:
		return 0.0
	if h >= 18.0 and h < 21.0:
		return smoothstep(18.0, 21.0, h)
	if h >= 5.0 and h < 7.0:
		return 1.0 - smoothstep(5.0, 7.0, h)
	return 1.0

func _update_night():
	night01 = night_amount(now_ms(), tz())
	if world_bg != null:
		world_bg.night01 = night01
	tint.color.a = night01 * NIGHT_TINT_MAX

# ── wallet roll-up (0.8 s, coin ticks at most 4/s) ──

func wallet_display() -> int:
	return int(round(wallet_shown))

func _roll_wallet(delta: float):
	var w := SaveDataManager.wallet()
	if w != _roll_to:
		_roll_from = wallet_shown
		_roll_to = w
		_roll_t = 0.0
	if _roll_t < 1.0:
		_roll_t = minf(1.0, _roll_t + delta / ROLL_S)
		wallet_shown = lerpf(_roll_from, float(_roll_to), 1.0 - pow(1.0 - _roll_t, 3.0))
		_tick_t -= delta
		if _tick_t <= 0.0 and _roll_to > _roll_from:
			_tick_t = 0.25
			AudioManager.play_sfx("coin_tick")
	else:
		wallet_shown = w

# ── movement ──

func can_move() -> bool:
	return not ui_blocking()

# True while a drawer, shop or modal owns the keyboard.
func ui_blocking() -> bool:
	return open_shop != "" or (book != null and book.open)

func _move_player(delta):
	var dir = Vector2.ZERO
	if Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_UP):
		dir.y -= 1
	if Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_DOWN):
		dir.y += 1
	if Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_LEFT):
		dir.x -= 1
	if Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_RIGHT):
		dir.x += 1
	player.moving = dir != Vector2.ZERO
	if dir == Vector2.ZERO:
		_step_clock = 0.0
		return
	_step_clock -= delta
	if _step_clock <= 0.0:
		_step_clock = 0.3
		AudioManager.play_sfx_varied("footstep", 0.12, -4.0)
	if dir.x != 0:
		player.face = signf(dir.x)
	var step = dir.normalized() * PLAYER_SPEED * delta
	# slide along blockers: try the full move, then each axis alone
	for attempt in [step, Vector2(step.x, 0), Vector2(0, step.y)]:
		var target = player.position + attempt
		target.x = clampf(target.x, 60, world_size.x - 60)
		target.y = clampf(target.y, 70, world_size.y - 50)
		if _walkable(target):
			player.position = target
			return

func _walkable(p: Vector2) -> bool:
	for r in blockers:
		if r.has_point(p):
			return false
	return true

# The avatar turns toward a clicked target and swings (clicks act at any
# distance, but it still reads as the farmer doing it).
func face_toward(world_pos: Vector2):
	if absf(world_pos.x - player.position.x) > 4.0:
		player.face = signf(world_pos.x - player.position.x)
	if _swing_cool <= 0.0:
		player.swing()
		_swing_cool = 0.12

# ── camera + zoom ──

func is_overview() -> bool:
	return overview

func toggle_zoom():
	set_overview(not overview)

func set_overview(on: bool, quiet := false):
	if on == overview:
		return
	overview = on
	_on_zoom_changed()
	if not quiet:
		AudioManager.play_sfx("menu_move")

func _update_camera(delta: float):
	var target := overview_zoom() if overview else FOLLOW_ZOOM
	if delta <= 0.0:
		zoom_now = target
	else:
		zoom_now = lerpf(zoom_now, target, 1.0 - exp(-delta * 9.0))
		if absf(zoom_now - target) < 0.003:
			zoom_now = target
	camera.zoom = Vector2(zoom_now, zoom_now)
	var view := Vector2(1280, 720) / zoom_now
	# The world fits the view only when zoomed in; otherwise lift the limits
	# and centre the map so it doesn't pin to the left edge.
	if not overview and view.x <= world_size.x + 1.0 and view.y <= world_size.y + 1.0:
		camera.limit_left = 0
		camera.limit_top = 0
		camera.limit_right = int(world_size.x)
		camera.limit_bottom = int(world_size.y)
		camera.position = player.position
	else:
		camera.limit_left = -100000
		camera.limit_top = -100000
		camera.limit_right = 100000
		camera.limit_bottom = 100000
		camera.position = world_size / 2.0 if overview else player.position

# Jump the camera to its target (tests, scene entry).
func snap_camera():
	zoom_now = overview_zoom() if overview else FOLLOW_ZOOM
	_update_camera(0.0)
	camera.reset_smoothing()
	camera.force_update_scroll()

func world_to_screen(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform() * p

func screen_to_world(p: Vector2) -> Vector2:
	return get_viewport().get_canvas_transform().affine_inverse() * p

func world_rect_to_screen(r: Rect2) -> Rect2:
	var a := world_to_screen(r.position)
	var b := world_to_screen(r.end)
	return Rect2(a, b - a)

# ── input ──

func _unhandled_input(event: InputEvent):
	if is_real_input(event):
		handle_input(event)

# Keys (incl. echo), mouse buttons and wheel, trackpad pan/magnify. Mouse
# motion is not an input: it doesn't stamp presence.
static func is_real_input(event: InputEvent) -> bool:
	if event is InputEventKey:
		return event.pressed
	if event is InputEventMouseButton:
		return event.pressed
	return event is InputEventPanGesture or event is InputEventMagnifyGesture

func handle_input(event: InputEvent):
	if _modal_input(event):
		return
	note_real_input()
	input_serial += 1
	_scan_t = 0.0
	if hud != null:
		hud.mark_dirty()
	# The design never needs a double-click: the second press of one is only
	# presence (stamped above), never a second Buy / Collect / tend.
	if event is InputEventMouseButton and event.double_click and event.button_index == MOUSE_BUTTON_LEFT:
		return
	if event is InputEventKey:
		if event.echo:
			if ui_blocking() and event.keycode in [KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT]:
				_key_input(event)
			return
		_key_input(event)
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				click(event.position)
			MOUSE_BUTTON_WHEEL_UP:
				_scroll_or_zoom(event.position, -1, false, event.factor)
			MOUSE_BUTTON_WHEEL_DOWN:
				_scroll_or_zoom(event.position, 1, false, event.factor)
	elif event is InputEventPanGesture:
		if book.open and book.contains(event.position):
			_scroll_drawer(event.delta.y, true)
		elif absf(event.delta.y) > 0.3:
			_scroll_or_zoom(event.position, 1 if event.delta.y > 0 else -1, true)
	elif event is InputEventMagnifyGesture:
		if _gesture_t <= 0.0 and absf(event.factor - 1.0) > 0.02:
			_gesture_t = GESTURE_COOLDOWN
			set_overview(event.factor < 1.0)

# Stamp presence once per frame at most (FarmEconomy.note_input settles first
# and logs the absence the input ended), then ask for a (debounced) save.
func note_real_input() -> Dictionary:
	var f := Engine.get_process_frames()
	if f == _input_frame:
		return {}
	_input_frame = f
	input_count += 1
	var fm := farm()
	if not FarmView.started(fm):
		return {}
	var res := FarmEconomy.note_input(fm, now_ms(), tz())
	SaveDataManager.request_farm_save()
	_react(res)
	return res

func _scroll_or_zoom(pos: Vector2, dir: int, gesture := false, factor := 1.0):
	if book.open and book.contains(pos):
		# a plain wheel notch reports factor 1 (or 0 where unsupported): one row
		# each; precision touchpads send fractions at frame rate: accumulate
		if factor <= 0.0 or factor >= 0.999:
			book.scroll_by(dir)
		else:
			_scroll_drawer(dir * factor * SCROLL_STEP * 0.5, true)
		return
	if open_shop != "":
		return
	if gesture:
		if _gesture_t > 0.0:
			return
		_gesture_t = GESTURE_COOLDOWN
	# wheel / ctrl+wheel / two-finger scroll: up zooms in, down zooms out
	set_overview(dir > 0)

# A two-finger swipe (or hi-res wheel) over the drawer: one row per
# SCROLL_STEP of accumulated delta, at most one row per SCROLL_COOLDOWN, so a
# single swipe moves a row or two instead of jumping to the end.
func _scroll_drawer(dy: float, _gesture := true):
	if signf(dy) != signf(_scroll_acc):
		_scroll_acc = 0.0
	_scroll_acc += dy
	if absf(_scroll_acc) < SCROLL_STEP or _scroll_t > 0.0:
		return
	book.scroll_by(1 if _scroll_acc > 0.0 else -1)
	_scroll_acc = 0.0
	_scroll_t = SCROLL_COOLDOWN

func click(pos: Vector2):
	# The open drawer first: no HUD target is meant to sit over it, and world
	# overlays (field signs, the butterfly) must never steal a Buy / Pin click.
	if book.open and book.contains(pos):
		book.click(pos)
		return
	var h: Dictionary = hud.regions.hit(pos)
	if not h.is_empty():
		_hud_action(str(h["id"]), h.get("data"))
		return
	if open_shop != "":
		if not WorldHUD.SHOP_PANEL.has_point(pos):
			close_shop()
		return
	_world_click(screen_to_world(pos), pos)

func _hud_action(id: String, data):
	if id in ["btn:sound_bar", "btn:zoom_bar", "btn:menu_bar", "btn:book_bar"]:
		id = id.trim_suffix("_bar")
	match id:
		"btn:sound":
			toggle_mute()
		"btn:zoom":
			toggle_zoom()
		"btn:menu":
			go_menu()
		"shop:close":
			close_shop()
		"prompt":
			interact()
		"btn:book":
			toggle_book()
		_:
			if id.begins_with("knife:"):
				buy_or_equip_knife(str(data))
			elif id.begins_with("station:"):
				var st := station(id.substr(8))
				if not st.is_empty():
					face_toward(st["pos"])
					(st["act"] as Callable).call()
			else:
				_on_hud(id, data)

# Movement polls PHYSICAL W/A/S/D while shortcuts read the logical keycode. On
# AZERTY (or Dvorak) a movement key types another letter (physical A = Q,
# physical W = Z, Dvorak physical D = E), so while the player can walk such a
# key is movement only, never a shortcut. QWERTY is unaffected (keycode ==
# physical keycode there).
static func is_movement_alias(event: InputEventKey) -> bool:
	return event.physical_keycode in [KEY_W, KEY_A, KEY_S, KEY_D] and event.keycode != event.physical_keycode

func _key_input(event: InputEventKey):
	var k := event.keycode
	if can_move() and is_movement_alias(event):
		return
	if k == KEY_M:
		toggle_mute()
		return
	if k == KEY_ESCAPE:
		escape()
		return
	if open_shop == "knives":
		_shop_key(k)
		return
	if book.open and book.key(event):
		return
	if _scene_key(event):
		return
	match k:
		KEY_Z:
			toggle_zoom()
		KEY_B:
			toggle_book()
		KEY_E, KEY_SPACE:
			interact()

# B / the Book buttons: open the Farm Book (on its last tab), or close it.
func toggle_book():
	if book.open and book.mode == "book":
		book.close()
		AudioManager.play_sfx("menu_back")
	else:
		open_book("")

# Esc closes the drawer or shop first. With nothing open, the first press only
# warns ("Esc again for the menu") so a student closing things doesn't fall
# out of the farm; a second press within ESC_ARM_S leaves. The HUD Menu
# button leaves at once.
func escape():
	if book.open and book.replant_armed():
		book.disarm()                 # Esc just takes back an armed "Replant now"
		AudioManager.play_sfx("menu_back")
	elif book.open:
		book.close()
		AudioManager.play_sfx("menu_back")
	elif open_shop != "":
		close_shop()
	elif _esc_t > 0.0:
		_esc_t = 0.0
		go_menu()
	else:
		_esc_t = ESC_ARM_S
		_popup("Press Esc again for the menu", INK_HINT)

func interact():
	if prompt_action.is_valid():
		prompt_action.call()

func toggle_mute():
	AudioManager.toggle_sound()
	_popup("Sound on" if AudioManager.sound_enabled else "Sound muted", Color(0.85, 0.9, 1.0))

func go_menu():
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

# ── stations + prompt ──

func _scan_interactions():
	prompt = ""
	prompt_action = Callable()
	if ui_blocking():
		return
	for s in stations:
		if player.position.distance_to(s["pos"]) < float(s["r"]):
			prompt = s["text"]
			prompt_action = s["act"]
			return

func station(id: String) -> Dictionary:
	for s in stations:
		if s["id"] == id:
			return s
	return {}

# ── Farm Book actions (shared: the town's stalls open the Book too) ──

func open_book(tab := ""):
	close_shop()
	book.open_book(tab)
	AudioManager.play_sfx("menu_select")

func farm_buy(item: String, arg) -> Dictionary:
	var res := FarmEconomy.buy(farm(), item, arg, now_ms(), tz())
	_after_action(res)
	if res["ok"]:
		AudioManager.play_sfx("purchase")
		var bought := ""
		for e in res["events"]:
			if e["type"] in ["hut_hired", "deed", "greenhouse", "house", "tool", "soil", "strain", "share", "quick", "sprinkler"]:
				bought = e["type"]
		if bought == "":
			_popup("Bought!", WorldHUD.GOOD)
	else:
		_popup(str(res["msg"]), WorldHUD.WARN)
	return res

func farm_pin(id: String) -> Dictionary:
	var f := farm()
	var unpin: bool = str(f["goal"]["pinned"]) == id
	var res := FarmEconomy.pin(f, "" if unpin else id)
	SaveDataManager.request_farm_save()
	book.invalidate()
	if not res["ok"]:
		_popup(str(res["msg"]), WorldHUD.WARN)
	elif unpin:
		_popup("Unpinned", WorldHUD.INK_DIM)
		AudioManager.play_sfx("menu_back")
	else:
		_popup("Pinned as your Next Goal · Q buys it", WorldHUD.GOOD)
		AudioManager.play_sfx("menu_select")
	return res

func farm_buy_goal() -> Dictionary:
	var res := FarmEconomy.buy_goal(farm(), now_ms(), tz())
	_after_action(res)
	if res["ok"]:
		AudioManager.play_sfx("purchase")
	else:
		_popup(str(res["msg"]), WorldHUD.WARN)
	return res

func farm_set_plan(i: int, crop: String) -> Dictionary:
	var res := FarmEconomy.set_plan(farm(), i, crop, now_ms(), tz())
	_after_action(res)
	if res["ok"]:
		AudioManager.play_sfx("menu_select")
		_popup("%s will plant %s next" % [FarmView.field_name(i), FarmView.crop_name(crop)], WorldHUD.GOOD)
	else:
		_popup(str(res["msg"]), WorldHUD.WARN)
	return res

func farm_replant(i: int) -> Dictionary:
	var res := FarmEconomy.replant_now(farm(), i, now_ms(), tz())
	_after_action(res)
	if res["ok"]:
		AudioManager.play_sfx("tend_pop")
		if int(res.get("refund", 0)) > 0:
			_popup("Replanted · refunded %s c" % NumFmt.coins(int(res["refund"])), WorldHUD.GOOD)
		elif res.get("msg", "") == "":
			_popup("Replanted %s" % FarmView.field_name(i), WorldHUD.GOOD)
	else:
		_popup(str(res["msg"]), WorldHUD.WARN)
	return res

# After any FarmEconomy action: save, react to its events, award achievements.
func _after_action(res: Dictionary):
	SaveDataManager.request_farm_save()
	_react(res)
	book.invalidate()
	_scan_t = 0.0
	if hud != null:
		hud.mark_dirty()

# Popups / banners / SFX for FarmEconomy events (both scenes).
func _react(res: Dictionary):
	var evs: Array = res.get("events", [])
	var goal_done := false
	for e in evs:
		match str(e.get("type", "")):
			"page":
				var pg := int(e["page"])
				_show_banner("Catalog page %d: %s!" % [pg, FarmView.crop_name(str(e["crop"]))], str(e.get("text", "")))
				AudioManager.play_sfx("page_unlock")
			"hut_hired":
				_popup("%s moved into the %s hut!" % [e["name"], FarmView.field_name(int(e["field"]))], WorldHUD.GOOD)
			"deed":
				_popup("%s is yours: %d tilled plots!" % [FarmView.field_name(int(e["field"])), FarmView.plots_per_field()], WorldHUD.GOOD)
			"greenhouse":
				_show_banner("Greenhouse built!", "Crops under glass grow almost twice as fast.")
			"house":
				_show_banner("The %s!" % str(e["name"]), "Spudlings now work %dh shifts while you're away." % int(e["shift_h"]))
			"tool":
				_popup("New hoe: %s" % _tool_name(int(e["tier"])), WorldHUD.GOOD)
			"soil":
				_popup("%s Soil level %d: its crops are worth more" % [FarmView.field_name(int(e.get("field", 0))), int(e["level"])], WorldHUD.GOOD)
			"strain":
				_popup("Prize Strain %s %s: a new ribbon!" % [FarmView.crop_name(str(e["crop"])), FarmEconomy.ROMAN[int(e["tier"])]], WorldHUD.GOOD)
			"share":
				_popup("You now keep %d%% of Spudling crops" % int(round(float(e["share"]) * 100.0)), WorldHUD.GOOD)
			"quick":
				_popup("Quick Hands: %ds per pick" % int(e["walk_s"]), WorldHUD.GOOD)
			"sprinkler":
				if str(e.get("socket", "")) != "":
					_popup("Sprinkler on fence %s" % str(e["socket"]), Color(0.6, 0.85, 1.0))
				else:
					_popup("Sprinkler bought: place it from a field card", Color(0.6, 0.85, 1.0))
			"sprinkler_moved":
				_popup("Sprinkler moved to fence %s" % str(e["to"]), Color(0.6, 0.85, 1.0))
			"fallback":
				_popup(str(res.get("msg", "Short of coins: planted Russet (free)")), WorldHUD.WARN)
			"tutorial":
				if not bool(e.get("skipped", false)):
					goal_done = true
	if goal_done:
		_popup("Goal done!", WorldHUD.GOOD)
	_check_achievements()

func _tool_name(tier: int) -> String:
	var tools: Array = FarmEconomy.cfg()["tools"]
	return str(tools[clampi(tier, 0, tools.size() - 1)].get("name", "Hoe"))

func _check_achievements():
	var f := farm()
	if not f.has("up"):
		return
	for id in FarmView.achievements_due(f):
		if SaveDataManager.unlock_achievement(id):
			_popup("Achievement: %s!" % _achievement_name(id), Color(1.0, 0.85, 0.35))
			AudioManager.play_sfx("achievement")

func _achievement_name(id: String) -> String:
	match id:
		"first_spudling": return "Hired Help"
		"catalog_complete": return "Full Catalog"
		"blue_ribbon": return "Blue Ribbon"
		"manor": return "Manor Born"
	return id

# ── knife stand (town) ──

func open_knives():
	book.close()
	open_shop = "knives"
	shop_sel = 0
	AudioManager.play_sfx("menu_select")

func close_shop():
	if open_shop != "":
		open_shop = ""
		AudioManager.play_sfx("menu_back")

func _shop_key(k: Key):
	var knives := GameData.knives()
	match k:
		KEY_UP, KEY_W:
			shop_sel = posmod(shop_sel - 1, knives.size())
		KEY_DOWN, KEY_S:
			shop_sel = posmod(shop_sel + 1, knives.size())
		KEY_ENTER, KEY_KP_ENTER:
			buy_or_equip_knife(str(knives[shop_sel]["id"]))
		_:
			var idx := int(k) - KEY_1
			if idx >= 0 and idx < knives.size():
				shop_sel = idx
				buy_or_equip_knife(str(knives[idx]["id"]))

func buy_or_equip_knife(id: String) -> bool:
	var owned: Array = SaveDataManager.farm.get("owned_knives", [])
	var k = GameData.knife_by_id(id)
	if id in owned:
		SaveDataManager.farm["equipped_knife"] = id
		SaveDataManager.save_game()
		_popup("%s equipped (×%.2f score)" % [k.get("name", id), float(k.get("damage", 1.0))], WorldHUD.GOOD)
		AudioManager.play_sfx("menu_select")
		return true
	# top-tier knives are rank-gated: you must earn the Chef XP first
	var need_xp := int(k.get("unlock_xp", 0))
	if SaveDataManager.career_xp() < need_xp:
		_popup("%s locked: reach %s Chef XP" % [k.get("name", id), NumFmt.coins(need_xp)], WorldHUD.WARN)
		return false
	var cost := int(k.get("cost", 99999))
	if not SaveDataManager.spend_coins(cost):
		_popup("Needs %s c" % NumFmt.coins(cost), WorldHUD.WARN)
		return false
	owned.append(id)
	SaveDataManager.farm["owned_knives"] = owned
	SaveDataManager.farm["equipped_knife"] = id
	SaveDataManager.save_game()
	_popup("%s bought and equipped! (-%s c)" % [k.get("name", id), NumFmt.coins(cost)], WorldHUD.GOLD)
	AudioManager.play_sfx("level_complete")
	# achievement: own every knife in the block
	if owned.size() >= GameData.knives().size() and SaveDataManager.unlock_achievement("knife_collector"):
		_popup("Achievement: Full Block!", Color(1.0, 0.85, 0.35))
	return true

# ── feedback ──

const INK_HINT := Color(0.85, 0.9, 1.0)

func _popup(text: String, color: Color):
	# the same line again (e.g. two "Goal done!" in a row) restarts its life
	# instead of stacking a duplicate
	for p in popups:
		if p.text == text and p.age < POPUP_LIFE * 0.5:
			p.age = 0.0
			p.color = color
			if color == WorldHUD.WARN:
				AudioManager.play_sfx("error")
			return
	popups.append({"text": text, "color": color, "age": 0.0})
	if popups.size() > 6:
		popups.pop_front()
	# every refusal is an orange popup with a soft buzz (its visual twin)
	if color == WorldHUD.WARN:
		AudioManager.play_sfx("error")

func _show_banner(text: String, sub := ""):
	if hud != null:
		hud.mark_dirty()
	banner_text = text
	banner_sub = sub
	banner_age = 0.0
