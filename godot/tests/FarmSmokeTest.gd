extends Node

# Headless Spudling Acres smoke test (design §10.5, FarmSmokeTest). It drives
# the REAL FarmScene with synthetic input (keys and left clicks pushed through
# get_tree().root.push_input in 1280x720 viewport coordinates, the same path a
# player's input takes) and pins the farm clock with FarmClock.frozen_ms, so
# every time jump is exact. Expected numbers are never hard-coded: they come
# from farm.json at runtime (FarmEconomy.cfg() / crop_info() / cost_of()), or
# from replaying the farm's own xorshift32 rng (star rolls) and a pick-by-pick
# brute force of the Spudling rules, so balance tuning can't break the test.
#
#    1  fresh defaults: start wallet, Field 1 owned + empty, plan, tutorial 1,
#       the first _ready starts the farm, overview zoom, the welcome banner
#    2  tend: not ripe at grow - 0.1 s, ripe at grow; a hand harvest pays the
#       replayed star roll, shipped += plots; a growing field is a no-op that
#       shows its ready time; Russet is free, Yukon charges plots x seed
#    3  a short wallet plants Russet with "Needs N c: planted Russet instead"
#    4  Replant now on a growing crop takes two clicks; refund floor(paid / 2);
#       a Spudling-planted crop refunds 0
#    5  Spudlings: your crop waits out its grace, then is picked at full value
#       x star EV; theirs at the share; exact picks and coins; the shift cap
#       (same wallet at w1 + 1 h and w1 + 3 d) and the nap in Pip's note
#    6  bulk == stepped: one 8 h settle vs 480 x 60 s with JSON round trips
#    7  rollback: no coins, g_offset rebased, crops unchanged
#    8  Pip's note + Collect (tends every ripe field, takes the report) +
#       Change plans first (deferred Collect) + the welcome butterfly
#    9  Catalog page 1 unlocks its crop and the sprinkler rows; page 2 its crop
#   10  sprinklers: buy (Book keys, card arrange), water both fence fields,
#       move for free, Move never buys, the purchase cap
#   11  Market Favorite locked at planting; Spudling replants split at midnight
#   12  butterflies: G catches a spawned one; forced Bumper (x2 hand tend),
#       Sunshower (+g_offset), Penny (max(min, s x farm_power)); a welcome
#       butterfly never rolls Bumper
#   13  Farm Book rows carry cost, d_here, d_away (hut: here 0, away > 0;
#       a sprinkler at a schedule where watering crosses no gap boundary:
#       away 0); buy by click and by key (B, arrows, Enter)
#   14  input: a click on a ripe field tends it, on a growing one opens its
#       card; T, Z, M, G, the Esc ladder; keyboard-only play reaches Pip's note
#   16  slots stay independent; save_farm() writes only farm.json
#   17  NumFmt
# (15, the schema-3 migration, is FarmMigrationTest's.) It never changes scene
# (the gate or a second Esc would free this test root).
#
#   godot --headless --path . res://tests/FarmSmokeTest.tscn --quit-after 600
#
# Prints "FARM SMOKE OK" and exits 0, or "FARM SMOKE FAIL" plus the failed
# checks and exits 1. The slot checks back up and restore the other two slots,
# so a local run doesn't eat a real save (CI always has a fresh user://).

const FE = preload("res://scripts/farm/FarmEconomy.gd")
const FV = preload("res://scripts/farm/FarmView.gd")
const Clock = preload("res://scripts/farm/FarmClock.gd")
const Fmt = preload("res://scripts/utils/NumFmt.gd")

const T0 := 1767254400000          # 2026-01-01 08:00 UTC (the zone is pinned to UTC)
const HOUR := 3600000
const DAY := 86400000
const MASK32 := 0xFFFFFFFF

var cfg: Dictionary
var plots := 12
var fs                              # the FarmScene (FarmController)
var T := 0                          # the farm clock (FarmClock.frozen_ms)
var fails: Array = []
var checks := 0
var mouse_events := 0

func _ready() -> void:
	_run.call_deferred()

func _run() -> void:
	var wall0 := Time.get_ticks_msec()
	var frame0 := Engine.get_process_frames()
	cfg = FE.cfg()
	plots = int(cfg["plots"]["per_field"])
	Clock.reset()
	Clock.tz_override = 0
	Fmt.hour24 = 1
	at(T0)
	# pure economy first (no scene, no save)
	_numfmt()
	_pure_fallback()
	_pure_bulk_stepped()
	_pure_favorite()
	_pure_butterflies()
	_pure_book_rows()
	# the real scene
	at(T0)
	await _fresh_scene()
	await _keyboard_to_pip()
	await _book_and_page1()
	await _replant_and_fallback()
	await _spudlings()
	await _page2()
	await _rollback()
	await _sprinklers()
	await _butterflies()
	await _input_misc()
	fs.queue_free()
	fs = null
	await frames(2)
	_slots()
	Clock.reset()
	Fmt.hour24 = -1
	_finish(Engine.get_process_frames() - frame0, Time.get_ticks_msec() - wall0)

# ════════════════════════════════════════════ helpers

func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails.append(what)
		print("  FAIL ", what)

func _finish(frames_used: int, wall_ms: int) -> void:
	if fails.is_empty():
		print("FARM SMOKE OK — %d checks, %d frames, %.1f s" % [checks, frames_used, wall_ms / 1000.0])
		get_tree().quit(0)
	else:
		print("FARM SMOKE FAIL — %d of %d checks failed:" % [fails.size(), checks])
		for f in fails:
			print("  - " + str(f))
		get_tree().quit(1)

func frame() -> void:
	await get_tree().process_frame

func frames(n: int) -> void:
	for k in n:
		await get_tree().process_frame

func farm() -> Dictionary:
	return SaveDataManager.farm

func wallet() -> int:
	return int(farm()["wallet"])

func at(t: int) -> void:
	T = t
	Clock.frozen_ms = t

func key(code: Key) -> void:
	var ev := InputEventKey.new()
	ev.keycode = code
	ev.physical_keycode = code
	ev.pressed = true
	get_tree().root.push_input(ev, true)
	await frame()

func click(pos: Vector2) -> void:
	mouse_events += 1
	var ev := InputEventMouseButton.new()
	ev.button_index = MOUSE_BUTTON_LEFT
	ev.pressed = true
	ev.position = pos
	ev.global_position = pos
	get_tree().root.push_input(ev, true)
	await frame()

# Click the centre of a drawn hit region (HUD, Farm Book or Pip's note).
func click_region(reg, id: String) -> void:
	var r: Rect2 = reg.rect_of(id)
	if r.size == Vector2.ZERO:
		_check(false, "region '%s' is drawn (have %s)" % [id, str(reg.ids())])
		return
	await click(r.get_center())

# A point inside field i's projected rect that no HUD region or drawer covers,
# so the click reaches the world (FarmController._world_click).
func field_point(i: int) -> Vector2:
	var r: Rect2 = fs.field_screen_rect(i)
	for fy in [0.72, 0.55, 0.88, 0.4]:
		for fx in [0.5, 0.3, 0.7, 0.15, 0.85]:
			var p: Vector2 = r.position + r.size * Vector2(fx, fy)
			if Rect2(0, 0, 1280, 720).has_point(p) and fs.hud.regions.hit_id(p) == "" and not fs.book.contains(p):
				return p
	_check(false, "a free click point inside Field %d (%s)" % [i + 1, r])
	return r.get_center()

func popped(prefix: String, color = null) -> bool:
	for p in fs.popups:
		if str(p["text"]).begins_with(prefix) and (color == null or p["color"] == color):
			return true
	return false

func popup_texts() -> Array:
	return fs.popups.map(func(p): return str(p["text"]))

# Keep the random butterfly away (it would take clicks, and a stale one is
# rescheduled from farm.rng, which the star replays read).
func no_bf() -> void:
	var b: Dictionary = farm()["buffs"]
	b["next_butterfly_ms"] = T + 100 * DAY
	b["welcome"] = false

func ensure_wallet(c: int) -> void:
	if wallet() < c:
		farm()["wallet"] = c

func ready_at(i: int) -> int:
	return int(FE.field_view(farm(), i, T)["ready_at_ms"])

func clockin_ms() -> int:
	return int(cfg["clock"]["clockin_s"]) * 1000

# Advance the clock to t while staying present: a harmless key (H) at least
# every half clock-in, so no Spudling clocks in and no note interrupts.
func advance_present(t: int) -> void:
	var step := clockin_ms() / 2
	while T + step < t:
		at(T + step)
		await key(KEY_H)
	at(maxi(T, t))
	await frame()

func owned_where(pred: Callable) -> Array:
	var out: Array = []
	for i in FE.FIELDS:
		var v := FE.field_view(farm(), i, T)
		if v["owned"] and pred.call(v):
			out.append(i)
	return out

func seed_cost(crop: String) -> int:
	return plots * int(FE.crop_info(crop)["seed"])

# ── the economy, recomputed from farm.json (independent of FarmEconomy's code) ──

static func xs32(x: int) -> int:
	x &= MASK32
	x ^= (x << 13) & MASK32
	x ^= x >> 17
	x ^= (x << 5) & MASK32
	x &= MASK32
	return 1 if x == 0 else x

func tile_milli(f: Dictionary, crop: String, fav: bool) -> int:
	var mult := pow(float(cfg["soil"]["mult"]), int(f["up"]["soil"])) \
			* pow(float(cfg["strains"]["mult"]), int(f["up"]["strains"].get(crop, 0)))
	var v := float(FE.crop_info(crop)["sell"]) * 1000.0 * mult
	if fav:
		v *= float(cfg["favorite"]["mult"])
	return int(round(v))

func star_ev(f: Dictionary) -> float:
	var t: Dictionary = cfg["tools"][int(f["up"]["tool"])]
	return 1.0 + float(t["silver"]) * (float(cfg["stars"]["silver_mult"]) - 1.0) \
			+ float(t["gold"]) * (float(cfg["stars"]["gold_mult"]) - 1.0)

func grow_eff(f: Dictionary, crop: String, i: int) -> int:
	var g := int(FE.crop_info(crop)["grow_ms"])
	if i == FE.GREENHOUSE:
		return int(round(g * float(cfg["greenhouse"]["grow_mult"])))
	for s in f["sprinklers"]:
		for x in cfg["fields"]["fences"][s]:
			if int(x) == i:
				return int(round(g * float(cfg["sprinklers"]["grow_mult"])))
	return g

func is_fav(crop: String, t: int) -> bool:
	return crop != FE.FREE_CROP and FE.favorite(FE.day_index(t, 0)) == crop

func day_start(d: int) -> int:
	return d * DAY

# Expected coins for hand-harvesting the ripe fields `idx` in that order (§5.5):
# replays farm.rng's xorshift32 star rolls on `sim` (a copy; its rng and
# carries advance like the real thing). {coins, per: [coins per field]}.
func replay_hand(sim: Dictionary, idx: Array, bumper: bool) -> Dictionary:
	var tool: Dictionary = cfg["tools"][int(sim["up"]["tool"])]
	var gold := float(tool["gold"])
	var silver := float(tool["silver"])
	var gm := float(cfg["stars"]["gold_mult"])
	var sm := float(cfg["stars"]["silver_mult"])
	var s := int(sim["rng"]["s"])
	var total := 0
	var per: Array = []
	for i in idx:
		var f: Dictionary = sim["fields"][i]
		var tile := tile_milli(sim, str(f["crop"]), bool(f["fav"]))
		var milli := 0
		for p in plots:
			s = xs32(s)
			var r := float(s) / 4294967296.0
			if r < gold:
				milli += int(round(tile * gm))
			elif r < gold + silver:
				milli += int(round(tile * sm))
			else:
				milli += tile
		if bumper:
			milli *= 2
		var tot := int(f["carry"]) + milli
		var coins := tot / 1000
		f["carry"] = tot - coins * 1000
		total += coins
		per.append(coins)
	sim["rng"]["s"] = s
	return {"coins": total, "per": per}

# Spudling picks on field i of `snap` for the absence that began at l_in, up
# to `now`, simulated pick by pick (§5.6 rules 1-5, the shipped your-crop
# grace min(grace, grow) and the star-EV wage on a crop that was in the ground
# when you left; Spudling-planted crops pay the share and take the Favorite
# flag of their own planting day).
func sim_hut(snap: Dictionary, i: int, l_in: int, now: int) -> Dictionary:
	var up: Dictionary = snap["up"]
	var ck: Dictionary = cfg["clock"]
	var grace := int(ck.get("your_crop_grace_s", 0)) * 1000
	var walk := int(cfg["quick"]["walk_s"][int(up["quick"])]) * 1000
	var shift := int(round(float(cfg["house"]["shift_h"][int(up["house"])]) * HOUR))
	var share := float(cfg["share"][int(up["share"])][0])
	var f: Dictionary = snap["fields"][i]
	var goff := int(snap["g_offset_ms"])
	var plan := str(f["plan"])
	var ge_plan := grow_eff(snap, plan, i)
	var out := {"picks": 0, "coins": 0, "spud_fav": 0, "spud_plain": 0, "last_pick": 0, "crop": str(f["crop"]),
			"fav": bool(f["fav"]), "planted_g": int(f["planted_g"])}
	var w0 := l_in + clockin_ms()
	var hi := mini(now, w0 + shift)
	if hi <= w0:
		return out
	var crop := str(f["crop"])
	var fav := bool(f["fav"])
	var planted := int(f["planted_g"]) - goff
	var ge := int(f["grow_eff_ms"])
	var by := str(f["by"])
	if crop == "":
		var tp := w0 + walk
		if tp > hi:
			return out
		crop = plan
		fav = is_fav(plan, tp)
		planted = tp
		ge = ge_plan
		by = "spud"
	var full := by == "you" or planted <= l_in
	var t := maxi(planted + ge + (mini(grace, ge) if full else 0), w0) + walk
	var weight := star_ev(snap) if full else share
	var milli := 0
	while t <= hi:
		milli += int(round(float(tile_milli(snap, crop, fav) * plots) * weight))
		out["picks"] += 1
		if out["picks"] >= 2:
			out["spud_fav" if fav else "spud_plain"] += 1
		out["last_pick"] = t
		crop = plan
		fav = is_fav(plan, t)
		planted = t
		weight = share
		t += ge_plan + walk
	out["crop"] = crop
	out["fav"] = fav
	out["planted_g"] = planted + goff
	out["coins"] = (int(f["carry"]) + milli) / 1000
	return out

# ════════════════════════════════════════════ 17. NumFmt

func _numfmt() -> void:
	print("== NumFmt")
	for c in [[999, "999"], [9999, "9,999"], [12345, "12.3K"], [4560000, "4.56M"]]:
		_check(Fmt.coins(c[0]) == c[1], "NumFmt.coins(%d) = '%s' (want '%s')" % [c[0], Fmt.coins(c[0]), c[1]])
	_check(Fmt.dur(200) == "3m 20s", "NumFmt.dur(200) = '%s' (want '3m 20s')" % Fmt.dur(200))

# ════════════════════════════════════════════ 3. short wallet (pure)

func _pure_fallback() -> void:
	print("== short wallet plants Russet")
	var f := FE.new_farm()
	FE.start(f, T0, 0)
	f["page"] = cfg["catalog"].size()
	FE.normalize(f)
	var dear := ""
	for c in FE.crops():
		if dear == "" or int(FE.crop_info(c)["seed"]) > int(FE.crop_info(dear)["seed"]):
			dear = c
	_check(FE.set_plan(f, 0, dear)["ok"], "fallback: plan the dearest seed (%s)" % dear)
	f["wallet"] = 0
	var r := FE.tend(f, 0, T0, 0)
	var want := "Needs %s c: planted Russet instead (free)" % Fmt.coins(seed_cost(dear))
	_check(str(r["msg"]) == want, "fallback: message '%s' (want '%s')" % [r["msg"], want])
	var fl: Dictionary = f["fields"][0]
	_check(fl["crop"] == FE.FREE_CROP and int(fl["seed_paid"]) == 0 and fl["by"] == "you" and int(f["wallet"]) == 0,
			"fallback: Russet planted free, by you, wallet still 0 (%s)" % str(fl))
	_check(r["events"].any(func(e): return e["type"] == "fallback"), "fallback: 'fallback' event")

# ════════════════════════════════════════════ 6. bulk == stepped (pure)

func _pure_bulk_stepped() -> void:
	print("== bulk == stepped")
	var d := FE.day_index(T0, 0)
	var t0 := day_start(d) + 20 * HOUR          # the 8 h absence crosses local midnight
	var f := FE.new_farm()
	FE.start(f, t0 - HOUR, 0)
	f["page"] = cfg["catalog"].size()
	f["wallet"] = 1000000000
	FE.normalize(f)
	for i in FE.FIELDS:
		f["fields"][i]["owned"] = true
	for i in [0, 1, 2, 4, FE.GREENHOUSE]:
		_check(FE.buy(f, "hut", i, t0 - HOUR, 0)["ok"], "bulk: hire a hut on field %d" % (i + 1))
	for k in 2:
		if FE.cost_of(f, "house", null) >= 0:
			FE.buy(f, "house", null, t0 - HOUR, 0)
	FE.buy(f, "sprinkler", "1-2", t0 - HOUR, 0)
	var crops := FE.crops()
	for i in FE.FIELDS:
		FE.set_plan(f, i, crops[i % crops.size()])
	FE.tend_all(f, t0, 0, true)                 # hand-plants every field at t0 (the last input)
	f["fields"][4]["crop"] = ""                 # an empty hut field: the Spudlings plant it at w0 + walk
	f["fields"][4]["grow_eff_ms"] = 0
	f["fields"][4]["seed_paid"] = 0
	var bulk: Dictionary = f.duplicate(true)
	var res := FE.settle(bulk, t0 + 8 * HOUR, 0)
	var step: Dictionary = f.duplicate(true)
	for k in 480:
		step = JSON.parse_string(JSON.stringify(step))
		FE.settle(step, t0 + (k + 1) * 60000, 0)
	FE.normalize(bulk)
	FE.normalize(step)
	_check(int(res["picks"]) > 0 and int(res["coins"]) > 0, "bulk: the 8 h absence picked something (%d picks)" % int(res["picks"]))
	var same := JSON.stringify(bulk) == JSON.stringify(step)
	if not same:
		var diff: Array = []
		for k2 in bulk:
			if JSON.stringify(bulk[k2]) != JSON.stringify(step.get(k2)):
				diff.append(k2)
		_check(false, "bulk == stepped: one 8 h settle and 480 x 60 s (JSON round trips) differ in %s" % str(diff))
	else:
		_check(true, "bulk == stepped")

# ════════════════════════════════════════════ 11. Market Favorite (pure)

func _pure_favorite() -> void:
	print("== Market Favorite")
	var d0 := FE.day_index(T0, 0)
	var c := FE.favorite(d0)
	_check(c != FE.FREE_CROP and FE.favorite(d0 + 1) != c, "Favorite: never Russet, never the same two days running (%s, %s)" % [c, FE.favorite(d0 + 1)])
	var f := FE.new_farm()
	FE.start(f, day_start(d0) + HOUR, 0)
	f["page"] = cfg["catalog"].size()
	f["wallet"] = 100000000
	FE.normalize(f)
	FE.set_plan(f, 0, c)
	# planted late on its Favorite day, harvested the next day: x fav_mult
	var tp := day_start(d0 + 1) - 30 * 60000
	f["buffs"]["next_butterfly_ms"] = tp + 100 * DAY
	FE.tend(f, 0, tp, 0)
	_check(f["fields"][0]["crop"] == c and bool(f["fields"][0]["fav"]), "Favorite: %s planted on its day carries the flag" % c)
	var th := maxi(tp + int(f["fields"][0]["grow_eff_ms"]), day_start(d0 + 1) + 60000)
	_check(FE.favorite(FE.day_index(th, 0)) != c, "Favorite: harvested on a day %s isn't the Favorite" % c)
	FE.set_plan(f, 0, FE.FREE_CROP)
	var plain := f.duplicate(true)
	plain["fields"][0]["fav"] = false
	var exp_plain := replay_hand(plain, [0], false)
	var sim := f.duplicate(true)
	var exp := replay_hand(sim, [0], false)
	var r := FE.tend(f, 0, th, 0)
	_check(tile_milli(f, c, true) == int(round(float(FE.crop_info(c)["sell"]) * 1000.0 * float(cfg["favorite"]["mult"]))),
			"Favorite: the plot value is sell x favorite.mult")
	_check(int(r["coins"]) == int(exp["coins"]) and int(exp["coins"]) > int(exp_plain["coins"]),
			"Favorite: next-day harvest pays the locked Favorite rate (%d c, replayed %d, plain %d)" % [int(r["coins"]), int(exp["coins"]), int(exp_plain["coins"])])
	# planted the day after (not its day): no bonus, even harvested on a later Favorite day
	FE.set_plan(f, 0, c)
	var tq := day_start(d0 + 1) + HOUR
	f["fields"][0]["crop"] = ""
	f["buffs"]["next_butterfly_ms"] = tq + 100 * DAY
	FE.tend(f, 0, tq, 0)
	_check(not bool(f["fields"][0]["fav"]), "Favorite: planted on another day, no flag")
	var dl := d0 + 2
	while FE.favorite(dl) != c and dl < d0 + 60:
		dl += 1
	var tl := maxi(day_start(dl) + HOUR, tq + int(f["fields"][0]["grow_eff_ms"]))
	f["buffs"]["next_butterfly_ms"] = tl + 100 * DAY
	FE.set_plan(f, 0, FE.FREE_CROP)
	var sim2 := f.duplicate(true)
	var exp2 := replay_hand(sim2, [0], false)
	var r2 := FE.tend(f, 0, tl, 0)
	_check(FE.favorite(FE.day_index(tl, 0)) == c and int(r2["coins"]) == int(exp2["coins"]),
			"Favorite: a crop planted off its day pays plain on a Favorite day (%d c, replayed %d)" % [int(r2["coins"]), int(exp2["coins"])])
	# Spudling replants across local midnight take each planting day's flag
	var walk := int(cfg["quick"]["walk_s"][0]) * 1000
	var shift := int(round(float(cfg["house"]["shift_h"][0]) * HOUR))
	var d := d0
	while d < d0 + 60:
		var p := FE.favorite(d)
		if int(FE.crop_info(p)["grow_ms"]) + walk <= shift / 4:
			break
		d += 1
	var plan := FE.favorite(d)
	_check(int(FE.crop_info(plan)["grow_ms"]) + walk <= shift / 4, "Favorite split: a short Favorite crop (%s on day %d)" % [plan, d])
	var g := FE.new_farm()
	var l_in := day_start(d + 1) - shift / 2 - clockin_ms()     # the work window straddles midnight
	FE.start(g, l_in - DAY, 0)
	g["page"] = cfg["catalog"].size()
	g["wallet"] = 100000000
	FE.normalize(g)
	FE.buy(g, "hut", 0, l_in - 1000, 0)
	FE.set_plan(g, 0, plan)
	g["buffs"]["next_butterfly_ms"] = l_in + 100 * DAY
	FE.tend(g, 0, l_in, 0)
	_check(bool(g["fields"][0]["fav"]), "Favorite split: hand-planted %s on its day" % plan)
	var snap := g.duplicate(true)
	var w1 := l_in + clockin_ms() + shift
	var e := sim_hut(snap, 0, l_in, w1 + HOUR)
	var w_before := int(g["wallet"])
	var rs := FE.settle(g, w1 + HOUR, 0)
	_check(int(e["spud_fav"]) > 0 and int(e["spud_plain"]) > 0,
			"Favorite split: replants on both sides of midnight (%d Favorite, %d plain)" % [int(e["spud_fav"]), int(e["spud_plain"])])
	_check(int(rs["picks"]) == int(e["picks"]) and int(g["wallet"]) - w_before == int(e["coins"]),
			"Favorite split: %d picks / %d c (pick-by-pick: %d / %d)" % [int(rs["picks"]), int(g["wallet"]) - w_before, int(e["picks"]), int(e["coins"])])
	_check(bool(g["fields"][0]["fav"]) == bool(e["fav"]) and int(g["fields"][0]["planted_g"]) == int(e["planted_g"]),
			"Favorite split: the last replant's flag and time")

# ════════════════════════════════════════════ 12. butterflies (pure part)

func _pure_butterflies() -> void:
	print("== welcome butterflies never roll Bumper")
	var f := FE.new_farm()
	FE.start(f, T0, 0)
	var seen := {}
	var seen_w := {}
	for k in 300:
		for welcome in [false, true]:
			var c: Dictionary = f.duplicate(true)
			c["rng"]["s"] = xs32((k * 2654435761 + 7919) & MASK32)
			c["buffs"]["next_butterfly_ms"] = T0
			c["buffs"]["welcome"] = welcome
			var r := FE.catch_butterfly(c, T0)
			if welcome:
				seen_w[str(r["outcome"])] = true
			else:
				seen[str(r["outcome"])] = true
	_check(seen.has("bumper") and seen.has("sunshower") and seen.has("penny"), "butterflies: a timed one rolls all three (%s)" % str(seen.keys()))
	_check(not seen_w.has("bumper") and seen_w.has("sunshower") and seen_w.has("penny"),
			"butterflies: a welcome one is Sunshower or Penny, never Bumper (%s)" % str(seen_w.keys()))
	var c2: Dictionary = f.duplicate(true)
	c2["buffs"]["welcome"] = true
	_check(str(FE.catch_butterfly(c2, T0, false, "bumper")["outcome"]) == "sunshower", "butterflies: a forced Bumper on a welcome one becomes a Sunshower")

# ════════════════════════════════════════════ 13. Book rows (pure part)

func _pure_book_rows() -> void:
	print("== Farm Book: a sprinkler that moves no crop across a gap boundary")
	var f := FE.new_farm()
	var now := T0 + 10 * DAY
	FE.start(f, now - 3 * DAY, 0)
	f["page"] = cfg["catalog"].size()
	f["wallet"] = 100000000
	FE.normalize(f)
	f["fields"][1]["owned"] = true
	var dear := ""
	for c in FE.crops():
		if dear == "" or int(FE.crop_info(c)["grow_ms"]) > int(FE.crop_info(dear)["grow_ms"]):
			dear = c
	FE.set_plan(f, 0, dear)
	FE.set_plan(f, 1, dear)
	# the shortest typical absence (from 3 h up) at which watering moves no
	# unlocked crop across a gap boundary (ceil(grow / gap) unchanged)
	var m := float(cfg["sprinklers"]["grow_mult"])
	var gap := -1
	for mins in range(180, 48 * 60):
		var g := mins * 60000
		var ok := true
		for c in f["unlocked"]:
			var g0 := int(FE.crop_info(c)["grow_ms"])
			var g1 := int(round(g0 * m))
			if ceili(float(g0) / g) != ceili(float(g1) / g):
				ok = false
				break
		if ok:
			gap = g
			break
	_check(gap > 0, "book: found a no-breakpoint gap (%s)" % Fmt.dur(gap / 1000.0))
	f["absences"] = [[now - 3 * DAY + HOUR, gap / 1000], [now - 2 * DAY + HOUR, gap / 1000], [now - DAY + HOUR, gap / 1000]]
	var rows := FE.book(f, now, 0)
	_check(rows.all(func(r): return r.has("cost") and r.has("d_here") and r.has("d_away") and r.has("payback_s")),
			"book: every row has cost, d_here, d_away, payback_s")
	var sp := {}
	for r in rows:
		if r["id"] == "sprinkler:1-2":
			sp = r
	_check(not sp.is_empty() and int(sp["cost"]) == int(cfg["sprinklers"]["costs"][0]), "book: sprinkler:1-2 row at the first sprinkler price")
	_check(not sp.is_empty() and absf(float(sp["d_away"])) < 1e-12 and float(sp["d_here"]) > 0.0,
			"book: sprinkler between two %s fields at a %s schedule: d_away 0, d_here > 0 (%s)" % [dear, Fmt.dur(gap / 1000.0),
			str([sp.get("d_here"), sp.get("d_away")])])

# ════════════════════════════════════════════ 1. fresh defaults

func _fresh_scene() -> void:
	print("== fresh farm")
	SaveDataManager.farm = FE.new_farm()
	var f := farm()
	var st: Dictionary = cfg["start"]
	_check(wallet() == int(st["wallet_if_new"]), "fresh: wallet %d == start.wallet_if_new" % wallet())
	_check(int(f["clock"]["epoch_ms"]) == 0, "fresh: clock epoch 0 (not started)")
	var f0: Dictionary = f["fields"][0]
	_check(f0["owned"] and f0["crop"] == "" and f0["plan"] == str(st["plan"]), "fresh: Field 1 owned, empty, plan %s" % st["plan"])
	_check(owned_where(func(v): return true) == [0], "fresh: only Field 1 owned")
	_check(f["unlocked"] == [FE.FREE_CROP] and int(f["page"]) == 0, "fresh: only Russet unlocked, Catalog page 0")
	fs = load("res://scenes/Farm/FarmScene.tscn").instantiate()
	add_child(fs)
	await frames(3)
	f = farm()
	_check(int(f["clock"]["epoch_ms"]) == T and int(f["clock"]["last_input_ms"]) == T, "fresh: the first _ready called start()")
	_check(fs.is_overview() and absf(fs.zoom_now - float(st["zoom"])) < 0.01, "fresh: first visit in overview (zoom %.2f)" % fs.zoom_now)
	_check(not fs.note_open, "fresh: no Pip's note on a new farm")
	_check(fs.banner_text == "SPUDLING ACRES", "fresh: welcome banner ('%s')" % fs.banner_text)
	var g := FE.next_goal(f, T)
	_check(g["kind"] == "tutorial" and int(g["step"]) == 1 and g["label"] == str(cfg["tutorial"][0]["label"]),
			"fresh: tutorial goal 1 '%s'" % g["label"])
	_check(fs.hud.regions.has("goal") and fs.hud.regions.has("btn:tend_all") and fs.hud.regions.has("sign:0"),
			"fresh: goal card, bottom bar and Field 1's sign drawn")
	no_bf()

# ════════════════════════════════════════════ 2 + 8 + 14: keyboard only to Pip

func _keyboard_to_pip() -> void:
	print("== keyboard only: plant, harvest, hire Pip, Pip's note")
	var m0 := mouse_events
	var f := farm()
	var plan := str(f["fields"][0]["plan"])
	fs.player.position = FV.field_rect(0).get_center()
	await frame()
	_check(str(fs.prompt).begins_with("[E] Plant %s" % FV.field_name(0)), "prompt in Field 1: '%s'" % fs.prompt)
	var w := wallet()
	await key(KEY_E)
	var t_plant := T
	_check(f["fields"][0]["crop"] == plan and int(f["fields"][0]["seed_paid"]) == seed_cost(plan) and wallet() == w - seed_cost(plan),
			"E planted %s on the empty field for %d c" % [plan, seed_cost(plan)])
	_check(int(f["goal"]["tutorial"]) >= 1, "tutorial: planting done")
	var ge := int(f["fields"][0]["grow_eff_ms"])
	_check(ge == int(FE.crop_info(plan)["grow_ms"]), "unwatered grow time locked at planting (%d ms)" % ge)
	# not ripe 0.1 s early: E is a no-op that shows the ready time
	at(t_plant + ge - 100)
	await frame()
	_check(not FE.field_view(f, 0, T)["ripe"], "not ripe at grow - 0.1 s")
	var pg := int(f["fields"][0]["planted_g"])
	fs.popups.clear()
	await key(KEY_E)
	var lr: Dictionary = fs.last_result
	_check(not lr.get("ok", true) and int(lr.get("ready_at_ms", 0)) == t_plant + ge and int(f["fields"][0]["planted_g"]) == pg,
			"E on a growing field is a no-op returning ready_at")
	_check(popped(str(lr.get("msg", "?"))) and str(lr.get("msg", "")).contains("ready at"), "it pops the ready time: %s" % str(popup_texts()))
	# ripe at exactly grow: E harvests (stars replayed from farm.rng) and replants
	at(t_plant + ge)
	await frame()
	_check(FE.field_view(f, 0, T)["ripe"], "ripe at grow")
	var exp := replay_hand(f.duplicate(true), [0], false)
	w = wallet()
	var sh := int(f["shipped"].get(plan, 0))
	await key(KEY_E)
	_check(wallet() == w + int(exp["coins"]) - seed_cost(plan), "hand harvest paid %d c (replayed stars: %d)" % [wallet() - w, int(exp["coins"])])
	_check(int(f["shipped"].get(plan, 0)) == sh + plots, "shipped.%s += %d" % [plan, plots])
	_check(f["fields"][0]["crop"] == plan and int(f["fields"][0]["planted_g"]) == T + int(f["g_offset_ms"]), "harvest replanted the plan")
	_check((fs.last_result.get("stars", []) as Array).size() == plots and int(f["stats"]["hand_picks"]) == 1, "one star roll per plot")
	# Farm Book: a hut row adds nothing here and something away
	var hut_row := {}
	for r in FE.book(f, T, 0):
		if r["id"] == "hut:0":
			hut_row = r
	_check(not hut_row.is_empty() and float(hut_row["d_here"]) == 0.0 and float(hut_row["d_away"]) > 0.0,
			"book: hut row d_here == 0, d_away > 0 (%s)" % str([hut_row.get("d_here"), hut_row.get("d_away")]))
	# harvest by keyboard until the hire goal is affordable, then Q
	var guard := 0
	while not bool(FE.next_goal(f, T)["can_buy"]) and guard < 15:
		guard += 1
		at(ready_at(0))
		await frame()
		await key(KEY_E)
	var g := FE.next_goal(f, T)
	_check(g["kind"] == "tutorial" and g["item"] == "hut" and g["can_buy"], "goal: hire a Spudling, affordable (%s)" % g["label"])
	var hut_cost := FE.cost_of(f, "hut", 0)
	w = wallet()
	await key(KEY_Q)
	var pip := str(cfg["huts"]["names"][0])
	_check(int(f["up"]["huts"]) == 1 and f["fields"][0]["hut"] and wallet() == w - hut_cost, "Q hired %s for %d c" % [pip, hut_cost])
	_check(popped("%s moved into" % pip), "hire popup: %s" % str(popup_texts()))
	_check(SaveDataManager.is_achievement_unlocked("first_spudling"), "achievement first_spudling")
	# 30 minutes away: Pip picks; the first key opens Pip's note (consumed)
	var l_in := T
	var snap: Dictionary = f.duplicate(true)
	at(l_in + 30 * 60000)
	fs.settle_now()
	await frame()
	var e := sim_hut(snap, 0, l_in, T)
	_check(int(f["stats"]["spud_picks"]) == int(e["picks"]) and wallet() - int(snap["wallet"]) == int(e["coins"]),
			"Pip: %d picks / %d c in 30 min (pick-by-pick: %d / %d)" % [int(f["stats"]["spud_picks"]), wallet() - int(snap["wallet"]),
			int(e["picks"]), int(e["coins"])])
	_check(not fs.note_open and FV.note_pending(f, T), "a note is pending, not yet shown")
	await key(KEY_H)
	_check(fs.note_open and int(f["clock"]["last_input_ms"]) == l_in, "the first key after 30 min opened Pip's note (and was consumed)")
	var lines: Array = fs.note_lines()
	_check(not lines.is_empty() and str(lines[0]["text"]).begins_with("We picked %s basket" % Fmt.coins(int(e["picks"]))),
			"note: '%s'" % (str(lines[0]["text"]) if not lines.is_empty() else "?"))
	_check(str(fs.note.get("report", {}).get("helpers", [""])[0]) == pip, "note: from %s" % pip)
	# Collect (Enter): tends every ripe field (stars replayed), takes the report, welcome butterfly
	var ripe := owned_where(func(v): return v["ripe"])
	var empty := owned_where(func(v): return v["empty"])
	var exp_c := replay_hand(f.duplicate(true), ripe, false)
	var seeds := 0
	for i in ripe + empty:
		seeds += seed_cost(str(f["fields"][i]["plan"]))
	w = wallet()
	await key(KEY_ENTER)
	lr = fs.last_result
	_check(not fs.note_open and lr.has("report"), "Enter collected")
	_check(int(lr.get("tended", -1)) == ripe.size() + empty.size() and wallet() == w + int(exp_c["coins"]) - seeds,
			"Collect tended %d fields for %d c (replayed %d)" % [int(lr.get("tended", -1)), wallet() - w + seeds, int(exp_c["coins"])])
	_check(owned_where(func(v): return v["ripe"] or v["empty"]).is_empty(), "Collect left nothing ripe or empty")
	_check(f["report"].is_empty() and not FV.note_pending(f, T), "Collect took the report")
	var dl: Array = cfg["butterflies"]["welcome_delay_s"]
	var wat := int(lr.get("welcome_at_ms", 0))
	_check(wat >= T + int(dl[0]) * 1000 and wat <= T + int(dl[1]) * 1000, "welcome butterfly %d ms after Collect" % (wat - T))
	_check(mouse_events == m0, "keyboard only: no mouse event from planting to Pip's note")
	# the welcome butterfly: G catches it (Sunshower or Penny, never Bumper)
	at(wat + 200)
	await frames(2)
	_check(fs.critters.bf_active and fs.critters.bf_welcome, "the welcome butterfly flies")
	var fp := FE.farm_power(f)
	var g0 := int(f["g_offset_ms"])
	w = wallet()
	await key(KEY_G)
	lr = fs.last_result
	var oc := str(lr.get("outcome", ""))
	_check(lr.get("ok", false) and oc in ["sunshower", "penny"], "G caught the welcome butterfly: %s" % oc)
	var b: Dictionary = cfg["butterflies"]
	if oc == "sunshower":
		_check(int(f["g_offset_ms"]) == g0 + int(b["sunshower_s"]) * 1000, "welcome Sunshower moved g_offset")
	elif oc == "penny":
		_check(wallet() == w + maxi(int(b["penny_min"]), int(round(float(b["penny_s"]) * fp))), "welcome Penny paid")
	_check(int(f["stats"]["butterflies"]) == 1, "one butterfly caught")

# ════════════════════════════════════════════ 13 + 9: Book by click and key, T, page 1

func _book_and_page1() -> void:
	print("== Farm Book: deed by click, Copper Hoe by key; T to Catalog page 1")
	no_bf()
	var f := farm()
	await key(KEY_B)
	_check(fs.book.open and fs.book.mode == "book", "B opens the Farm Book")
	await click_region(fs.book.regions, "tab:land")
	_check(fs.book.tab == "land", "Land tab")
	var deed_cost := FE.cost_of(f, "deed", 1)
	ensure_wallet(deed_cost)
	await frame()
	var row: Dictionary = fs.book.row_by_id("deed:1")
	_check(not row.is_empty() and int(row["cost"]) == deed_cost, "Book row deed:1 at %d c" % deed_cost)
	var w := wallet()
	await click_region(fs.book.regions, "buy:deed:1")
	_check(f["fields"][1]["owned"] and wallet() == w - deed_cost, "a click on [Buy] bought Field 2's deed (%d c)" % deed_cost)
	_check(popped("%s is yours" % FV.field_name(1)), "deed popup: %s" % str(popup_texts()))
	fs.popups.clear()
	await key(KEY_T)
	_check(not FE.has_tend_all(f) and popped("Tend All needs", WorldHUD.WARN), "T without the Copper Hoe is refused in orange")
	await key(KEY_3)
	_check(fs.book.tab == "tools" and not fs.book.rows().is_empty() and fs.book.rows()[0]["id"] == "tool", "3 shows the Tools tab")
	var tool_cost := FE.cost_of(f, "tool", null)
	ensure_wallet(tool_cost)
	w = wallet()
	await key(KEY_ENTER)
	_check(int(f["up"]["tool"]) == 1 and FE.has_tend_all(f) and wallet() == w - tool_cost, "Enter bought the Copper Hoe (%d c)" % tool_cost)
	await key(KEY_B)
	_check(not fs.book.open, "B closes the Book")
	# sprinklers are locked before Catalog page 1
	var sp := FE.book(f, T, 0).filter(func(r): return r["id"] == "sprinkler:1-2")
	_check(sp.size() == 1 and (int(f["page"]) >= 1 or (sp[0]["locked"] and str(sp[0]["locked_reason"]).begins_with("Catalog page 1"))),
			"sprinkler row locked before page 1 (%s)" % (str(sp[0]) + " page=" + str(f["page"]) + " shipped=" + str(f["shipped"]) if sp.size() == 1 else "missing"))
	fs.open_field_card(0)
	_check(int(f["page"]) >= 1 or str(fs.book.sprinkler_state()["kind"]) == "locked", "card: sprinkler locked before page 1")
	fs.book.close()
	# T tends every ripe or empty field
	at(maxi(T, ready_at(0)))
	await frame()
	var due := owned_where(func(v): return v["ripe"] or v["empty"])
	await key(KEY_T)
	_check(fs.last_result.get("ok", false) and int(fs.last_result.get("tended", -1)) == due.size() and due.size() == 2,
			"T tended %d fields (want %s)" % [int(fs.last_result.get("tended", -1)), str(due)])
	var unlock := str(cfg["catalog"][0]["unlocks"])
	var guard := 0
	while int(f["page"]) < 1 and guard < 60:
		guard += 1
		at(maxi(ready_at(0), ready_at(1)))
		await key(KEY_T)
	_check(int(f["page"]) >= 1 and unlock in f["unlocked"], "Catalog page 1 unlocked %s after shipping %s" % [unlock, str(cfg["catalog"][0]["needs"])])
	_check(fs.banner_text == "Catalog page 1: %s!" % FV.crop_name(unlock), "page banner '%s'" % fs.banner_text)
	sp = FE.book(f, T, 0).filter(func(r): return r["id"] == "sprinkler:1-2")
	_check(sp.size() == 1 and not sp[0]["locked"], "page 1 unlocked the sprinkler rows")

# ════════════════════════════════════════════ 14 + 2 + 4 + 3: clicks, Yukon seed, Replant, fallback

func _replant_and_fallback() -> void:
	print("== clicks on fields, Yukon seed, two-step Replant, Russet fallback")
	no_bf()
	var f := farm()
	var yk := str(cfg["catalog"][0]["unlocks"])
	var seed_y := seed_cost(yk)
	at(T + 1000)
	fs.hud.mark_dirty()
	await frame()
	var v1 := FE.field_view(f, 1, T)
	_check(not v1["empty"] and not v1["ripe"], "Field 2 is growing")
	await click(field_point(1))
	_check(fs.book.is_card() and fs.book.field == 1, "a click on a growing field opens its card")
	await click_region(fs.book.regions, "plan:" + yk)
	_check(f["fields"][1]["plan"] == yk and popped("%s will plant %s next" % [FV.field_name(1), FV.crop_name(yk)]), "plan %s picked by click" % yk)
	await key(KEY_ESCAPE)
	_check(not fs.book.open, "Esc closes the drawer")
	# a click on a ripe field tends it: stars + plant the plan, charging plots x seed
	await advance_present(ready_at(1))
	ensure_wallet(seed_y)
	no_bf()
	fs.hud.mark_dirty()
	await frame()
	var exp := replay_hand(f.duplicate(true), [1], false)
	var w := wallet()
	await click(field_point(1))
	_check(f["fields"][1]["crop"] == yk and int(f["fields"][1]["seed_paid"]) == seed_y and wallet() == w + int(exp["coins"]) - seed_y,
			"a click on the ripe field harvested (%d c) and planted %s for %d c" % [int(exp["coins"]), yk, seed_y])
	# Replant now on a growing crop: the first click arms, the second uproots and refunds half
	await key(KEY_2)
	_check(fs.book.is_card() and fs.book.field == 1, "2 opens Field 2's card")
	await click_region(fs.book.regions, "plan:" + FE.FREE_CROP)
	var paid := int(f["fields"][1]["seed_paid"])
	var pg := int(f["fields"][1]["planted_g"])
	w = wallet()
	await click_region(fs.book.regions, "card:replant")
	_check(fs.book.replant_armed() and f["fields"][1]["crop"] == yk and int(f["fields"][1]["planted_g"]) == pg and wallet() == w,
			"Replant: the first click only arms it")
	_check(fs.book.regions.rect_of("card:replant").size.x >= 370.0, "Replant: armed button spans the row")
	await click_region(fs.book.regions, "card:replant")
	_check(f["fields"][1]["crop"] == FE.FREE_CROP and wallet() == w + paid / 2 - seed_cost(FE.FREE_CROP), "Replant: the second click refunded %d of %d c (res=%s crop=%s w=%d->%d)" % [paid / 2, paid, str(fs.last_result), str(f["fields"][1]["crop"]), w, wallet()])
	_check(popped("Replanted · refunded %s c" % Fmt.coins(paid / 2)), "replant popup: %s" % str(popup_texts()))
	# a short wallet: the plan falls back to Russet with the orange message
	await click_region(fs.book.regions, "plan:" + yk)
	f["wallet"] = seed_y - 1
	fs.hud.mark_dirty()
	await frame()
	fs.popups.clear()
	await click_region(fs.book.regions, "card:replant")
	await click_region(fs.book.regions, "card:replant")
	var want := "Needs %s c: planted Russet instead (free)" % Fmt.coins(seed_y)
	var fl: Dictionary = f["fields"][1]
	_check(fl["crop"] == FE.FREE_CROP and int(fl["seed_paid"]) == 0 and fl["by"] == "you" and wallet() == seed_y - 1,
			"short wallet: '%s', Russet free, no refund (res=%s fl=%s w=%d)" % [str(fs.last_result.get("msg", "")), str(fs.last_result), str(fl), wallet()])
	_check(popped(want, WorldHUD.WARN), "short wallet: orange popup (%s)" % str(popup_texts()))
	await key(KEY_ESCAPE)

# ════════════════════════════════════════════ 5 + 8: Spudlings, the shift, Change plans first

func _spudlings() -> void:
	print("== Spudlings: grace, wages, shift cap, nap; Change plans first; welcome butterfly")
	no_bf()
	var f := farm()
	var yk := str(cfg["catalog"][0]["unlocks"])
	await key(KEY_1)
	await click_region(fs.book.regions, "plan:" + yk)
	_check(f["fields"][0]["plan"] == yk, "Pip's field plans %s" % yk)
	await key(KEY_ESCAPE)
	await advance_present(ready_at(0))
	ensure_wallet(seed_cost(yk) * 4)
	no_bf()
	fs.hud.mark_dirty()
	await frame()
	await click(field_point(0))
	var l_in := T
	_check(f["fields"][0]["crop"] == yk and f["fields"][0]["by"] == "you" and int(f["clock"]["last_input_ms"]) == l_in,
			"a click hand-planted %s on Pip's field (the absence starts now)" % yk)
	var snap: Dictionary = f.duplicate(true)
	var w_snap := wallet()
	var picks0 := int(f["stats"]["spud_picks"])
	var ge := int(f["fields"][0]["grow_eff_ms"])
	var grace := int(cfg["clock"].get("your_crop_grace_s", 0)) * 1000
	var walk := int(cfg["quick"]["walk_s"][int(f["up"]["quick"])]) * 1000
	var shift := int(round(float(cfg["house"]["shift_h"][int(f["up"]["house"])]) * HOUR))
	var w0 := l_in + clockin_ms()
	var w1 := w0 + shift
	var p1 := maxi(l_in + ge + mini(grace, ge), w0) + walk
	# your crop waits out its grace: no pick 1 ms early, the first pick at p1
	at(p1 - 1)
	fs.settle_now()
	_check(int(f["stats"]["spud_picks"]) == picks0 and wallet() == w_snap, "grace: no pick 1 ms before max(ripe + grace, clock-in) + walk")
	at(p1)
	fs.settle_now()
	var e1 := sim_hut(snap, 0, l_in, p1)
	_check(int(e1["picks"]) == 1 and int(f["stats"]["spud_picks"]) == picks0 + 1 and wallet() - w_snap == int(e1["coins"]),
			"first pick at p1: your crop at full value x star EV (%d c, want %d)" % [wallet() - w_snap, int(e1["coins"])])
	at(maxi(T, l_in + 10 * 60000))
	fs.settle_now()
	var e10 := sim_hut(snap, 0, l_in, T)
	_check(int(f["stats"]["spud_picks"]) - picks0 == int(e10["picks"]) and wallet() - w_snap == int(e10["coins"]),
			"T + 10 min: %d picks / %d c (pick-by-pick %d / %d; theirs at the share)" % [int(f["stats"]["spud_picks"]) - picks0,
			wallet() - w_snap, int(e10["picks"]), int(e10["coins"])])
	# the shift cap: nothing after w1
	at(w1 + HOUR)
	fs.settle_now()
	await frame()
	var ew := sim_hut(snap, 0, l_in, w1)
	_check(int(f["stats"]["spud_picks"]) - picks0 == int(ew["picks"]) and wallet() - w_snap == int(ew["coins"]),
			"shift: %d picks / %d c by w1 + 1 h (pick-by-pick to w1: %d / %d)" % [int(f["stats"]["spud_picks"]) - picks0,
			wallet() - w_snap, int(ew["picks"]), int(ew["coins"])])
	var later: Dictionary = f.duplicate(true)
	FE.settle(later, w1 + 3 * DAY, 0)
	_check(int(later["wallet"]) == wallet() and int(later["stats"]["spud_picks"]) == int(f["stats"]["spud_picks"]),
			"shift cap: the same wallet at w1 + 1 h and w1 + 3 d")
	var rep: Dictionary = f["report"]
	_check(int(rep.get("worked_ms", -1)) == shift and int(rep.get("nap_ms", -1)) == HOUR and int(rep.get("nap_from_ms", -1)) == w1,
			"report: worked the whole shift, napping since w1 (%s)" % str([rep.get("worked_ms"), rep.get("nap_ms")]))
	# a crop the Spudlings planted refunds nothing on Replant now
	var sp: Dictionary = snap.duplicate(true)
	var tsp := int(ew["last_pick"]) + 1000
	FE.settle(sp, tsp, 0)
	var vsp := FE.field_view(sp, 0, tsp)
	var rr := FE.replant_now(sp, 0, tsp, 0)
	_check(vsp["by"] == "spud" and not vsp["ripe"] and int(vsp["refund"]) == 0 and rr["ok"] and int(rr["refund"]) == 0,
			"Replant on a Spudling-planted crop refunds 0")
	# Pip's note names the nap
	await key(KEY_H)
	_check(fs.note_open, "after the shift, a key opens Pip's note")
	var pip := str(cfg["huts"]["names"][0])
	var nap_head := "%s worked %s" % [pip, Fmt.dur(shift / 1000)]
	var nap: Array = fs.note_lines().filter(func(ln): return str(ln["text"]).begins_with(nap_head) and str(ln["text"]).contains("then napped"))
	_check(nap.size() == 1, "note: '%s worked %s of your …, then napped' (%s)" % [pip, Fmt.dur(shift / 1000),
			str(fs.note_lines().map(func(ln): return ln["text"]))])
	# Change plans first: nothing collected, the first ripe field's card, Collect deferred to T
	var ripe := owned_where(func(v): return v["ripe"])
	var w := wallet()
	await click_region(fs.hud.note_regions, "note:change")
	_check(not fs.note_open and f["report"].is_empty() and wallet() == w and owned_where(func(v): return v["ripe"]) == ripe,
			"Change plans first: the note closes, nothing is collected, nothing rots")
	_check(not ripe.is_empty() and fs.pending_collect and fs.welcome_owed and fs.book.is_card() and fs.book.field == ripe[0],
			"Change plans first: Field %d's card, Collect armed, welcome owed" % (ripe[0] + 1 if not ripe.is_empty() else 0))
	ensure_wallet(seed_cost(yk) * 4)
	no_bf()
	var exp := replay_hand(f.duplicate(true), ripe, false)
	var seeds := 0
	for i in ripe:
		seeds += seed_cost(str(f["fields"][i]["plan"]))
	w = wallet()
	await key(KEY_T)
	var lr: Dictionary = fs.last_result
	_check(int(lr.get("tended", -1)) == ripe.size() and wallet() == w + int(exp["coins"]) - seeds and not fs.pending_collect,
			"T ran the deferred Collect (%d fields, %d c, replayed %d)" % [int(lr.get("tended", -1)), wallet() - w + seeds, int(exp["coins"])])
	var dl: Array = cfg["butterflies"]["welcome_delay_s"]
	var wat := int(lr.get("welcome_at_ms", 0))
	_check(wat >= T + int(dl[0]) * 1000 and wat <= T + int(dl[1]) * 1000 and bool(f["buffs"]["welcome"]) and not fs.welcome_owed,
			"the deferred Collect paid the welcome butterfly (+%d ms)" % (wat - T))
	at(wat + 200)
	await frames(2)
	_check(fs.critters.bf_active and fs.critters.bf_welcome, "the welcome butterfly flies")
	await click_region(fs.hud.regions, "bf:chip")
	lr = fs.last_result
	_check(lr.get("ok", false) and str(lr.get("outcome", "")) in ["sunshower", "penny"], "a click on its chip caught it: %s" % str(lr.get("outcome", "")))
	await key(KEY_ESCAPE)

# ════════════════════════════════════════════ 9: Catalog page 2

func _page2() -> void:
	print("== Catalog page 2 (Spudling absences)")
	var f := farm()
	var unlock := str(cfg["catalog"][1]["unlocks"])
	var shift := int(round(float(cfg["house"]["shift_h"][int(f["up"]["house"])]) * HOUR))
	var saw := false
	var guard := 0
	while int(f["page"]) < 2 and guard < 10:
		guard += 1
		at(T + clockin_ms() + shift + 10 * 60000)
		await key(KEY_H)
		if fs.note_open:
			if int(f["page"]) >= 2:
				saw = fs.note_lines().any(func(ln): return str(ln["text"]) == "New Catalog page: %s!" % FV.crop_name(unlock))
			ensure_wallet(seed_cost(str(f["fields"][0]["plan"])) * 4)
			await key(KEY_ENTER)
	_check(int(f["page"]) >= 2 and unlock in f["unlocked"], "Catalog page 2 unlocked %s (%d absences)" % [unlock, guard])
	_check(fs.banner_text == "Catalog page 2: %s!" % FV.crop_name(unlock), "page 2 in Pip's note and the banner ('%s') saw=%s" % [fs.banner_text, str(saw)])
	_check(not fs.note_open, "note collected")

# ════════════════════════════════════════════ 7: rollback

func _rollback() -> void:
	print("== clock rollback")
	var f := farm()
	await key(KEY_H)                      # present again
	if fs.note_open:
		await key(KEY_ENTER)
	fs.settle_now()
	var w := wallet()
	var goff := int(f["g_offset_ms"])
	var ls := int(f["clock"]["last_settle_ms"])
	var before := {}
	for i in owned_where(func(v): return true):
		before[i] = FE.field_view(f, i, T)
	at(T - HOUR)
	var res: Dictionary = fs.settle_now()
	_check(bool(res.get("rebased", false)) and int(f["g_offset_ms"]) == goff + (ls - T) and int(f["clock"]["last_settle_ms"]) == T,
			"rollback 1 h: rebased (g_offset +%d ms)" % (int(f["g_offset_ms"]) - goff))
	_check(wallet() == w and int(res.get("coins", -1)) == 0, "rollback: no coins")
	var same := true
	for i in before:
		var v := FE.field_view(f, i, T)
		if v["crop"] != before[i]["crop"] or v["ripe"] != before[i]["ripe"] or int(v["left_ms"]) != int(before[i]["left_ms"]):
			same = false
	_check(same, "rollback: crops neither un-grow nor jump")
	await frame()

# ════════════════════════════════════════════ 10: sprinklers

func _sprinklers() -> void:
	print("== sprinklers: Book keys, move for free, Move never buys, card buy, the cap")
	no_bf()
	var f := farm()
	var m := float(cfg["sprinklers"]["grow_mult"])
	var costs: Array = cfg["sprinklers"]["costs"]
	await key(KEY_B)
	await key(KEY_1)
	_check(fs.book.open and fs.book.tab == "land", "B, 1: the Land tab")
	var ids: Array = fs.book.rows().map(func(r): return str(r["id"]))
	var idx := ids.find("sprinkler:1-2")
	_check(idx > 0, "Land rows include sprinkler:1-2 below the deeds (%s)" % str(ids))
	ensure_wallet(int(costs[0]))
	for k in maxi(0, idx):
		await key(KEY_DOWN)
	_check(fs.book.sel == idx, "arrows select the sprinkler row")
	var w := wallet()
	var ge_locked := int(f["fields"][0]["grow_eff_ms"])
	await key(KEY_ENTER)
	_check("1-2" in f["sprinklers"] and int(f["up"]["sprinklers"]) == 1 and wallet() == w - int(costs[0]),
			"Enter bought a sprinkler onto fence 1-2 (%d c)" % int(costs[0]))
	var russet_g := int(FE.crop_info(FE.FREE_CROP)["grow_ms"])
	_check(FE.field_view(f, 0, T)["watered"] and FE.field_view(f, 1, T)["watered"] and not FE.field_view(f, 2, T)["watered"],
			"fence 1-2 waters Fields 1 and 2 only")
	_check(FE.grow_eff_ms(f, FE.FREE_CROP, 0) == int(round(russet_g * m)) and FE.grow_eff_ms(f, FE.FREE_CROP, 3) == russet_g,
			"watered grow time = grow x %s" % str(m))
	_check(int(f["fields"][0]["grow_eff_ms"]) == ge_locked, "a crop already growing keeps its locked grow time")
	await key(KEY_B)
	# move it to 1-4 from Field 1's card: free
	await key(KEY_1)
	_check(fs.book.is_card() and fs.book.field == 0 and bool(fs.book.sprinkler_state().get("can_move", false)), "Field 1's card offers Move")
	await click_region(fs.book.regions, "card:sprinkler_move")
	_check(fs.arrange_active() and fs.arrange["mode"] == "move" and fs.arrange["from"] == "1-2" and fs.is_overview(),
			"Move: arrange mode (overview), 1-2 picked up")
	fs.snap_camera()
	await frame()
	w = wallet()
	await click_region(fs.hud.regions, "socket:1-4")
	_check("1-4" in f["sprinklers"] and not "1-2" in f["sprinklers"] and int(f["up"]["sprinklers"]) == 1 and wallet() == w,
			"moved to fence 1-4 for free")
	_check(FE.field_view(f, 0, T)["watered"] and FE.field_view(f, 3, T)["watered"] and not FE.field_view(f, 1, T)["watered"],
			"fence 1-4 waters Fields 1 and 4, not Field 2")
	_check(not fs.arrange_active() and fs.book.is_card() and fs.book.field == 0, "back on Field 1's card")
	# Move never buys, even with nothing picked; Esc leaves arrange mode first
	fs.begin_arrange(0, "move")
	fs.arrange["from"] = ""
	fs.snap_camera()
	await frame()
	fs.popups.clear()
	await click_region(fs.hud.regions, "socket:2-5")
	_check(int(f["up"]["sprinklers"]) == 1 and wallet() == w and fs.arrange_active() and not "2-5" in f["sprinklers"],
			"Move mode never buys a sprinkler")
	_check(popped("Click a placed sprinkler first", WorldHUD.WARN), "…and says to pick one first (%s)" % str(popup_texts()))
	await key(KEY_ESCAPE)
	_check(not fs.arrange_active() and fs.book.is_card(), "Esc: arrange mode closes first (back to the card)")
	# the second one: the card's Buy, then a socket (arrange 'buy' mode)
	await key(KEY_2)
	ensure_wallet(int(costs[1]))
	fs.hud.mark_dirty()
	await frame()
	_check(str(fs.book.sprinkler_state()["kind"]) == "buy", "Field 2's card offers Buy sprinkler")
	await click_region(fs.book.regions, "card:sprinkler")
	_check(fs.arrange_active() and fs.arrange["mode"] == "buy", "Buy: arrange mode")
	fs.snap_camera()
	await frame()
	w = wallet()
	await click_region(fs.hud.regions, "socket:2-5")
	_check("2-5" in f["sprinklers"] and int(f["up"]["sprinklers"]) == 2 and wallet() == w - int(costs[1]),
			"bought the second sprinkler onto fence 2-5 (%d c)" % int(costs[1]))
	# the rest of the ladder, then the cap
	var bought := 2
	while FE.cost_of(f, "sprinkler", null) >= 0 and bought < 10:
		ensure_wallet(FE.cost_of(f, "sprinkler", null))
		_check(FE.buy(f, "sprinkler", null, T, 0)["ok"], "sprinkler %d bought" % (bought + 1))
		bought += 1
	_check(bought == costs.size(), "%d sprinklers in all (farm.json)" % bought)
	ensure_wallet(int(costs[-1]) * 2)
	var r4 := FE.buy(f, "sprinkler", null, T, 0)
	_check(not r4["ok"] and int(f["up"]["sprinklers"]) == costs.size(), "one more sprinkler is refused ('%s')" % r4["msg"])
	fs.book.invalidate()
	_check(FE.book(f, T, 0).filter(func(r): return str(r["id"]).begins_with("sprinkler")).is_empty(), "no sprinkler rows left in the Book")
	fs.open_field_card(0)
	_check(str(fs.book.sprinkler_state()["kind"]) == "move", "the card only offers Move now")
	fs.book.close()
	await frame()

# ════════════════════════════════════════════ 12 + 14: butterflies

func _butterflies() -> void:
	print("== butterflies: G, forced Bumper / Sunshower / Penny")
	var f := farm()
	var b: Dictionary = cfg["butterflies"]
	no_bf()
	f["buffs"]["next_butterfly_ms"] = T
	f["buffs"]["butterfly_field"] = 0
	await frames(2)
	_check(fs.critters.bf_active and not fs.critters.bf_welcome, "a timed butterfly is out")
	var n0 := int(f["stats"]["butterflies"])
	await key(KEY_G)
	_check(int(f["stats"]["butterflies"]) == n0 + 1 and fs.last_result.get("ok", false), "G caught it (%s)" % str(fs.last_result.get("outcome", "")))
	await frame()
	_check(not fs.critters.bf_active, "and it is gone")
	# Bumper: a hand tend pays x2 while it lasts
	no_bf()
	await advance_present(ready_at(1))
	var r: Dictionary = fs.catch_butterfly("bumper")
	_check(str(r.get("outcome", "")) == "bumper" and int(f["buffs"]["bumper_until_ms"]) == T + int(b["bumper_s"]) * 1000,
			"forced Bumper for %d s" % int(b["bumper_s"]))
	_check(popped(FV.butterfly_text("bumper", 0)), "Bumper popup (%s)" % str(popup_texts()))
	no_bf()
	var plan1 := str(f["fields"][1]["plan"])
	ensure_wallet(seed_cost(plan1))
	var exp := replay_hand(f.duplicate(true), [1], true)
	var w := wallet()
	fs.tend_field(1)
	_check(wallet() == w + int(exp["coins"]) - seed_cost(plan1), "Bumper: the hand tend paid x2 (%d c, replayed %d)" % [wallet() - w + seed_cost(plan1), int(exp["coins"])])
	await advance_present(maxi(int(f["buffs"]["bumper_until_ms"]), ready_at(1)))
	no_bf()
	ensure_wallet(seed_cost(plan1))
	exp = replay_hand(f.duplicate(true), [1], false)
	w = wallet()
	fs.tend_field(1)
	_check(wallet() == w + int(exp["coins"]) - seed_cost(plan1), "after the Bumper: x1 again (%d c)" % int(exp["coins"]))
	# Sunshower: every crop grows sunshower_s at once
	var g0 := int(f["g_offset_ms"])
	var left0 := int(FE.field_view(f, 1, T)["left_ms"])
	r = fs.catch_butterfly("sunshower")
	var sun := int(b["sunshower_s"]) * 1000
	_check(str(r.get("outcome", "")) == "sunshower" and int(f["g_offset_ms"]) == g0 + sun
			and int(FE.field_view(f, 1, T)["left_ms"]) == maxi(0, left0 - sun), "forced Sunshower: g_offset +%d ms" % sun)
	# Lucky Penny: max(penny_min, penny_s x farm_power)
	var fp := FE.farm_power(f)
	w = wallet()
	r = fs.catch_butterfly("penny")
	var want := maxi(int(b["penny_min"]), int(round(float(b["penny_s"]) * fp)))
	_check(str(r.get("outcome", "")) == "penny" and int(r.get("coins", -1)) == want and wallet() == w + want,
			"forced Penny paid %d c (want %d)" % [wallet() - w, want])
	_check(popped(FV.butterfly_text("penny", want)), "Penny popup (%s)" % str(popup_texts()))
	no_bf()
	await frame()

# ════════════════════════════════════════════ 14: Z, M, the Esc ladder

func _input_misc() -> void:
	print("== Z, M, Esc")
	var f := farm()
	var oz := float(cfg["start"]["zoom"])
	fs.book.close()
	await frame()
	_check(fs.is_overview(), "in overview")
	await key(KEY_Z)
	fs.snap_camera()
	_check(not fs.is_overview() and absf(fs.zoom_now - 1.0) < 0.01 and absf(float(f["ui"]["zoom"]) - 1.0) < 0.01, "Z: follow zoom 1.0 (saved)")
	await key(KEY_Z)
	fs.snap_camera()
	_check(fs.is_overview() and absf(fs.zoom_now - oz) < 0.01 and absf(float(f["ui"]["zoom"]) - oz) < 0.01, "Z: overview %.2f (saved)" % oz)
	var snd: bool = AudioManager.sound_enabled
	fs.popups.clear()
	await key(KEY_M)
	_check(AudioManager.sound_enabled != snd and popped("Sound muted" if snd else "Sound on"), "M toggles the sound")
	await key(KEY_M)
	_check(AudioManager.sound_enabled == snd, "M toggles it back")
	# Esc: the drawer first, then (nothing open) only a warning
	await key(KEY_B)
	_check(fs.book.open, "B opens the Book")
	await key(KEY_ESCAPE)
	_check(not fs.book.open, "Esc closes the Book")
	fs.popups.clear()
	await key(KEY_ESCAPE)
	_check(fs.is_inside_tree() and popped("Press Esc again for the menu"), "Esc with nothing open only warns")
	fs._esc_t = 0.0                       # never let a later Esc leave the scene

# ════════════════════════════════════════════ 16: slots

func _slots() -> void:
	print("== save slots")
	var sdm = SaveDataManager
	var home: int = sdm.current_slot
	var others: Array = []
	for n in range(1, sdm.MAX_SLOTS + 1):
		if n != home:
			others.append(n)
	var a: int = others[0]
	var b: int = others[1]
	var keep_a := _backup_slot(a)
	var keep_b := _backup_slot(b)
	sdm.save_game()
	var w_home: int = sdm.wallet()
	_check(sdm.switch_slot(a) and sdm.current_slot == a, "slots: switch to slot %d" % a)
	if not keep_a.has(sdm.FARM_FILE):
		_check(not sdm.farm_started() and sdm.wallet() == int(cfg["start"]["wallet_if_new"]), "slots: an empty slot is a new farm")
	var wa: int = sdm.wallet() + 1234
	sdm.farm["wallet"] = wa
	sdm.save_farm()
	_check(sdm.switch_slot(home) and sdm.wallet() == w_home, "slots: slot %d keeps its own wallet" % home)
	_check(sdm.switch_slot(a) and sdm.wallet() == wa, "slots: slot %d kept its balance" % a)
	# save_farm() writes farm.json and nothing else: mark the other data files
	_check(sdm.switch_slot(b), "slots: switch to slot %d" % b)
	var dir: String = sdm.SAVE_PATH + "slot%d/" % b
	var marks := {}
	for fn in sdm.DATA_FILES:
		if fn == sdm.FARM_FILE:
			continue
		marks[fn] = JSON.stringify({"marker": fn, "us": Time.get_ticks_usec()})
		var fa := FileAccess.open(dir + fn, FileAccess.WRITE)
		fa.store_string(marks[fn])
		fa.close()
	sdm.farm["wallet"] = 4242
	sdm.save_farm()
	for fn in marks:
		_check(FileAccess.get_file_as_string(dir + fn) == marks[fn], "save_farm left %s alone" % fn)
	var extra: Array = []
	for fn in DirAccess.get_files_at(dir):
		if not marks.has(fn) and fn != sdm.FARM_FILE and not keep_b.has(fn):
			extra.append(fn)
	_check(extra.is_empty(), "save_farm wrote no other file (%s)" % str(extra))
	var saved = JSON.parse_string(FileAccess.get_file_as_string(dir + sdm.FARM_FILE))
	_check(saved is Dictionary and int(saved.get("wallet", 0)) == 4242, "save_farm wrote farm.json")
	_check(sdm.switch_slot(home) and sdm.wallet() == w_home, "slots: back to slot %d" % home)
	_restore_slot(a, keep_a)
	_restore_slot(b, keep_b)

func _backup_slot(n: int) -> Dictionary:
	var dir: String = SaveDataManager.SAVE_PATH + "slot%d/" % n
	var out := {}
	if DirAccess.dir_exists_absolute(dir):
		for fn in DirAccess.get_files_at(dir):
			out[fn] = FileAccess.get_file_as_bytes(dir + fn)
	return out

func _restore_slot(n: int, keep: Dictionary) -> void:
	var dir: String = SaveDataManager.SAVE_PATH + "slot%d/" % n
	if not DirAccess.dir_exists_absolute(dir):
		return
	for fn in DirAccess.get_files_at(dir):
		if not keep.has(fn):
			DirAccess.remove_absolute(dir + fn)
	for fn in keep:
		var fa := FileAccess.open(dir + fn, FileAccess.WRITE)
		fa.store_buffer(keep[fn])
		fa.close()
