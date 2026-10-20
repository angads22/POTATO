extends RefCounted

# FarmBot: a schedule-profile + strategy player for the REAL FarmEconomy
# (design §6.1 / §10.5). The bot never re-implements economy rules: every
# coin moves through FarmEconomy's public API with an injected clock
# (now_ms, tz_s = 0, so local time = UTC in the sim). The only model it keeps
# of its own is the forward look-ahead it uses to choose a crop, which is a
# player's plan, not a rule.
#
# Event-driven: an absence is ONE settle. While present the bot acts at each
# ripe time (+ reaction), at each butterfly and at least every keepalive_ms,
# and every one of those moments is an input (an action, or note_input).
# A visit opens with settle -> set the plans of the fields Collect will
# replant -> collect() -> catch the welcome butterfly -> shop. The last
# input of a visit is at window end - 1 s.
#
# Usage:
#   const FarmBot = preload("res://tests/farm/FarmBot.gd")
#   var b = FarmBot.new("class")          # profile
#   b.strategy = "roi"                    # roi|tutorial|s1|s2|s3|s4|h1|none (h1 = roi, at most 1 hut)
#   b.planting = "greedy"                 # greedy|naive|biggest|fixed (fixed_crop)
#   b.run(14)
#   b.milestones / b.purchases / b.snaps / b.summary()
#
# No class_name: tests preload this file by path, so it needs no class cache.

const FE = preload("res://scripts/farm/FarmEconomy.gd")

const SEC := 1000
const MIN := 60000
const HOUR := 3600000
const DAY := 86400000
const TZ := 0
const DAY0 := 20740                 # local day index of sim day 1 (2026-10-14)

const PROFILES := ["active", "class", "casual", "class+eve"]
const STRATEGIES := ["roi", "tutorial", "s1", "s2", "s3", "s4", "h1", "none"]

# ── configuration (set before run) ─────────────────────────────────────────
var profile := "class"
var strategy := "roi"
var planting := "greedy"
var fixed_crop := "russet"
var start_wallet := 50
var catch_butterflies := true
var page_policy := true            # ceil(fields/3) fields grow the page's crop
var keepalive_ms := 15 * SEC       # the bot looks at least this often while present
var react_ms := 5 * SEC
var day0 := DAY0
var fixture := {}                  # applied to the new farm before the first visit
var metric_afford := false         # day-1 "something useful affordable" per arrival
var track_cycles := false          # per-planting accounting (SD1 / SD7)
var ignore_huts := false           # plan every field as if it had no hut (SD4: a player who ignores Pip)
var debug := false                 # print plantings and departure plans
static var s2_items := ["hut", "share", "quick", "house"]   # S2's favoured Farm Book rows
static var bias := 0.25             # S1-S3: payback weight of the favoured rows
var max_book_age_ms := 10 * MIN    # re-read the Farm Book at least this often
var save_frac := 0.1               # while saving, small buys up to this share of the target's price

# ── state / results ────────────────────────────────────────────────────────
var farm: Dictionary = {}
var wins: Array = []               # [A_ms, B_ms, day (1-based), played_before_ms]
var wi := -1                       # current window index
var days := 0
var purchases: Array = []          # {t, id, item, cost, wi}
var milestones: Dictionary = {}    # id -> {t, wi}
var snaps: Array = []              # per day (index day-1): first-arrival snapshot
var cycles: Array = []             # {crop, t0, t1, net, here, night}
var afford: Array = []             # [wi, bool] day-1 arrivals (metric_afford)
var arrivals: Array = []           # {wi, t, spud (report coins), absence_s}
var violations: Array = []         # invariant breaches seen while playing (strings)
var events_seen: Dictionary = {}   # event type -> count
var seed_spent := 0
var buy_spent := 0
var refunds := 0
var first_coins_t := -1
var butterflies := {"bumper": 0, "sunshower": 0, "penny": 0, "missed": 0}
var hand_plants: Dictionary = {}   # crop -> hand plantings
var spud_picks: Dictionary = {}    # crop -> Spudling picks (from Pip's notes)
var depart_plans := true           # set hut fields' plans for the coming absence
var short_visit_ms := 5 * MIN      # visits this short shop once, on leaving (plans set for the gap)
var _short := false
var t_start := 0
var book_calls := 0

var _clockin := 120000
var _grace := 0                    # clock.your_crop_grace_s: Spudlings leave your ripe crop alone this long
var _report_min := 120000
var _life := 12000
var _fav_mult := 1.4

var _plant_rec: Dictionary = {}    # field -> {t, crop, seed, wi}
var _book_t := -1
var _next_wallet := 0
var _dirty := true
var _last_bf := 0

func _init(p := "class", strat := "roi") -> void:
	profile = p
	strategy = strat

# ════════════════════════════════════════════════════════ schedule

# Present windows of one local day, [start_s, end_s] (design §6.1).
static func profile_windows(p: String) -> Array:
	var w: Array = []
	match p:
		"active":
			w.append([17 * 3600, 21 * 3600])
		"class", "class+eve":
			for k in 28:
				var a := 8 * 3600 + k * 900
				w.append([a, a + 60])
			if p == "class+eve":
				w.append([19 * 3600, 20 * 3600])
		"casual":
			for h in [9, 12, 15, 18, 21]:
				w.append([h * 3600, h * 3600 + 120])
		_:
			push_error("FarmBot: unknown profile " + p)
	w.sort_custom(func(a, b): return a[0] < b[0])
	return w

func _build_windows(n_days: int) -> void:
	wins = []
	var played := 0
	var day_w := profile_windows(profile)
	for d in n_days:
		var base := (day0 + d) * DAY
		for w in day_w:
			var a: int = base + int(w[0]) * SEC
			var b: int = base + int(w[1]) * SEC
			wins.append([a, b, d + 1, played])
			played += b - a

# Index of the last window starting at or before t (binary search).
func _win_before(t: int) -> int:
	var lo := 0
	var hi := wins.size() - 1
	if t < int(wins[0][0]):
		return -1
	while lo < hi:
		var mid := (lo + hi + 1) / 2
		if int(wins[mid][0]) <= t:
			lo = mid
		else:
			hi = mid - 1
	return lo

func day_of(t: int) -> int:
	return int(floor(float(t) / DAY)) - day0 + 1

func played_ms(t: int) -> int:
	var k := _win_before(t)
	if k < 0:
		return 0
	return int(wins[k][3]) + clampi(t - int(wins[k][0]), 0, int(wins[k][1]) - int(wins[k][0]))

func fmt_t(t: int) -> String:
	var sod := posmod(t, DAY) / SEC
	return "d%d %02d:%02d" % [day_of(t), sod / 3600, (sod % 3600) / 60]

# ════════════════════════════════════════════════════════ run

func run(n_days: int) -> void:
	days = n_days
	if strategy == "s3" and planting == "greedy":
		planting = "naive"          # the long-crop timer plants by the clock
	var c: Dictionary = FE.cfg()
	_clockin = int(c["clock"]["clockin_s"]) * SEC
	_grace = int(c["clock"].get("your_crop_grace_s", 0)) * SEC
	_report_min = int(c["clock"]["report_min_s"]) * SEC
	_life = int(c["butterflies"]["life_s"]) * SEC
	_fav_mult = float(c["favorite"]["mult"])

	farm = FE.new_farm()
	farm["wallet"] = start_wallet
	_apply_fixture()
	_build_windows(n_days + 3)
	t_start = int(wins[0][0])
	for k in wins.size():
		if int(wins[k][2]) > n_days:
			_finish(k)
			break
		_visit(k)

func _apply_fixture() -> void:
	if fixture.is_empty():
		return
	var fx := fixture
	if fx.has("page"):
		farm["page"] = int(fx["page"])
	if fx.has("owned"):
		for i in 7:
			farm["fields"][i]["owned"] = i in fx["owned"]
	if fx.has("huts"):
		var n := 0
		for i in fx["huts"]:
			farm["fields"][i]["hut"] = true
			farm["fields"][i]["hut_k"] = n
			n += 1
		farm["up"]["huts"] = n
	for key in ["share", "quick", "house", "tool"]:
		if fx.has(key):
			farm["up"][key] = int(fx[key])
	if fx.has("soil"):
		for i in 7:
			farm["fields"][i]["soil"] = int(fx["soil"])
	if fx.has("sprinklers"):
		farm["sprinklers"] = fx["sprinklers"].duplicate()
		farm["up"]["sprinklers"] = fx["sprinklers"].size()
	if fx.has("strains"):
		farm["up"]["strains"] = fx["strains"].duplicate()
	if fx.has("wallet"):
		farm["wallet"] = int(fx["wallet"])
	if fx.has("plans"):
		for i in fx["plans"]:
			farm["fields"][int(i)]["plan"] = str(fx["plans"][i])
	FE.normalize(farm)

# One present window: arrive, play, leave.
func _visit(k: int) -> void:
	wi = k
	var a: int = wins[k][0]
	var b: int = wins[k][1]
	var t := a
	var started: bool = int(farm["clock"]["epoch_ms"]) != 0
	var first_of_day: bool = k == 0 or int(wins[k - 1][2]) != int(wins[k][2])
	var pre_wallet := int(farm["wallet"])
	if started:
		var ripe_before := _ripe_hand_fields(t)
		var s: Dictionary = FE.settle(farm, t, TZ)
		_events(s["events"])
		if int(farm["wallet"]) < pre_wallet:
			violations.append("%s settle lowered the wallet %d -> %d" % [fmt_t(t), pre_wallet, farm["wallet"]])
		if int(s["coins"]) < 0:
			violations.append("%s settle credited %d" % [fmt_t(t), s["coins"]])
		for i in ripe_before:
			if not _is_ripe(i, t):
				violations.append("%s settle un-ripened field %d" % [fmt_t(t), i])
	if first_of_day:
		_snapshot(int(wins[k][2]), t, pre_wallet)
	# Plans first (the replant Collect is about to do), then Collect.
	for i in 7:
		var f: Dictionary = farm["fields"][i]
		if f["owned"] and (f["crop"] == "" or _is_ripe(i, t)):
			_set_plan(i, t)
	var gap: int = t - int(farm["clock"]["last_input_ms"]) if started else 0
	var before := _hand_snapshot()
	var r: Dictionary
	if not started or gap >= _report_min:
		r = FE.collect(farm, t, TZ)
		var rep: Dictionary = r.get("report", {})
		arrivals.append({"wi": k, "t": t, "spud": int(rep.get("coins", 0)), "absence_s": gap / SEC,
				"hand": int(r.get("coins", 0))})
		var pk: Dictionary = rep.get("picks", {})
		for c in pk:
			spud_picks[c] = int(spud_picks.get(c, 0)) + int(pk[c])
	else:
		_tend_fields(t)
		r = {}
	if not r.is_empty():
		_after_tend(r, t, before)
	_mark(t)
	# A check-in (1-2 min) reads the Farm Book once, on its way out, when every
	# field's plan is the one for the coming gap (the Book projects from plans).
	# A long session shops on arrival and whenever something new is in reach.
	_short = b - a <= short_visit_ms
	if not _short:
		_shop(t, true)
	var end := b - SEC
	while true:
		var nt := _next_event(t, end)
		if nt >= end:
			break
		t = nt
		_act(t)
	_act(end)
	if depart_plans:
		_depart_plans(end)
	if _short:
		_shop(end, true)
		if depart_plans:
			_depart_plans(end)

# After the last day: one settle at the next day's first arrival time (the
# night's Spudling coins) and the closing snapshot.
func _finish(k: int) -> void:
	var t: int = wins[k][0]
	var pre := int(farm["wallet"])
	FE.settle(farm, t, TZ)
	var pk: Dictionary = farm["report"].get("picks", {})
	for c in pk:
		spud_picks[c] = int(spud_picks.get(c, 0)) + int(pk[c])
	if int(farm["wallet"]) < pre:
		violations.append("%s final settle lowered the wallet" % fmt_t(t))
	_snapshot(int(wins[k][2]), t, pre)
	_mark(t)

# One present moment: tend what's ripe (or keep alive), catch a butterfly,
# maybe shop.
func _act(t: int) -> void:
	if not _tend_fields(t):
		FE.note_input(farm, t, TZ)
	if catch_butterflies:
		var nb := int(farm["buffs"]["next_butterfly_ms"])
		if FE.butterfly_due(farm, t):
			var was_welcome := bool(farm["buffs"]["welcome"])
			var r: Dictionary = FE.catch_butterfly(farm, t)
			if r["ok"]:
				butterflies[r["outcome"]] = int(butterflies[r["outcome"]]) + 1
				if was_welcome:
					butterflies["welcome"] = int(butterflies.get("welcome", 0)) + 1
				_coins_seen(t, int(r["coins"]))
				_events(r["events"])
		elif nb > 0 and nb != _last_bf and t >= nb + _life:
			butterflies["missed"] = int(butterflies["missed"]) + 1
			_last_bf = nb
	_mark(t)
	if not _short:
		_shop(t, false)

func _next_event(t: int, end: int) -> int:
	var nt := t + keepalive_ms
	var goff := int(farm["g_offset_ms"])
	for i in 7:
		var f: Dictionary = farm["fields"][i]
		if not f["owned"]:
			continue
		if f["crop"] == "":
			nt = mini(nt, t + SEC)
			continue
		var ra: int = int(f["planted_g"]) + _crop_grow(i) - goff
		nt = mini(nt, maxi(t + SEC, ra + react_ms))
	if catch_butterflies:
		var nb := int(farm["buffs"]["next_butterfly_ms"])
		if nb > 0 and t < nb + _life:
			nt = mini(nt, maxi(t + SEC, nb + mini(react_ms, _life - 2 * SEC)))
	return mini(nt, end)

# ════════════════════════════════════════════════════════ tending + planting

# The standing crop's grow time: locked at planting by the economy (a
# sprinkler placed or moved later changes only the next planting).
func _crop_grow(i: int) -> int:
	var f: Dictionary = farm["fields"][i]
	var ge := int(f.get("grow_eff_ms", 0))
	return ge if ge > 0 else FE.grow_eff_ms(farm, f["crop"], i)

func _is_ripe(i: int, t: int) -> bool:
	var f: Dictionary = farm["fields"][i]
	if f["crop"] == "":
		return false
	return t + int(farm["g_offset_ms"]) - int(f["planted_g"]) >= _crop_grow(i)

func _ripe_hand_fields(t: int) -> Array:
	var out: Array = []
	for i in 7:
		var f: Dictionary = farm["fields"][i]
		if f["owned"] and not f["hut"] and _is_ripe(i, t):
			out.append(i)
	return out

# Tend every owned field that is ripe or empty, one action each (each is an
# input). Returns true if anything was tended.
func _tend_fields(t: int) -> bool:
	var any := false
	for i in 7:
		var f: Dictionary = farm["fields"][i]
		if not f["owned"] or not (f["crop"] == "" or _is_ripe(i, t)):
			continue
		_set_plan(i, t)
		var before := _hand_snapshot()
		var r: Dictionary = FE.tend(farm, i, t, TZ)
		_after_tend(r, t, before)
		any = true
	return any

func _hand_snapshot() -> Dictionary:
	var by: Array = []
	for f in farm["fields"]:
		by.append(f["by"])
	return {"by": by}

# Book-keeping after tend / collect / replant: coins, seed, cycles, events.
func _after_tend(r: Dictionary, t: int, before: Dictionary) -> void:
	_events(r.get("events", []))
	seed_spent += int(r.get("spent", 0))
	refunds += int(r.get("refund", 0))
	_coins_seen(t, int(r.get("coins", 0)))
	for rec in r.get("fields", []):
		var i: int = rec["field"]
		if track_cycles and rec["crop"] != "" and _plant_rec.has(i) and before["by"][i] == "you":
			var p: Dictionary = _plant_rec[i]
			if p["crop"] == rec["crop"]:
				cycles.append({"crop": rec["crop"], "t0": p["t"], "t1": t, "net": int(rec["coins"]) - int(p["seed"]),
						"here": int(p["wi"]) == wi, "night": day_of(int(p["t"])) != day_of(t)})
		if rec["planted"] != "":
			if debug:
				print("  %s F%d %s -> plant %s%s" % [fmt_t(t), i + 1, rec["crop"] if rec["crop"] != "" else "-",
						rec["planted"], " (hut)" if farm["fields"][i]["hut"] else ""])
			_plant_rec[i] = {"t": t, "crop": rec["planted"], "seed": int(farm["fields"][i]["seed_paid"]), "wi": wi}
			hand_plants[rec["planted"]] = int(hand_plants.get(rec["planted"], 0)) + 1
		else:
			_plant_rec.erase(i)

func _coins_seen(t: int, coins: int) -> void:
	if coins > 0 and first_coins_t < 0:
		first_coins_t = t

func _events(evs: Array) -> void:
	for e in evs:
		var ty := str(e.get("type", ""))
		events_seen[ty] = int(events_seen.get(ty, 0)) + 1
		if ty in ["page", "deed", "greenhouse", "hut_hired"]:
			_dirty = true

func _set_plan(i: int, t: int) -> void:
	var c := choose_plan(i, t)
	if c != "" and c != farm["fields"][i]["plan"]:
		var r: Dictionary = FE.set_plan(farm, i, c)
		if not r["ok"]:
			violations.append("%s set_plan(%d, %s) refused: %s" % [fmt_t(t), i, c, r["msg"]])

# The crop to plant on field i now.
func choose_plan(i: int, t: int) -> String:
	if page_policy and _is_page_field(i):
		var need := _page_need()
		if need != "":
			return need
	var opts: Array = FE.plan_options(farm, i, t, TZ)
	match planting:
		"fixed":
			return fixed_crop if fixed_crop in farm["unlocked"] else FE.FREE_CROP
		"naive":
			return _naive(opts, t)
		"biggest":
			return _biggest(opts)
	return _greedy(opts, i, t)

# The plan picker habit: the affordable crop with the biggest "+N c net".
func _biggest(opts: Array) -> String:
	var best := FE.FREE_CROP
	var best_n := -INF
	for o in opts:
		if o["unlocked"] and float(o["seed_cost"]) <= float(farm["wallet"]) and float(o["net"]) > best_n:
			best_n = float(o["net"])
			best = o["crop"]
	return best

# Catalog policy: while a page is active, ceil(fields/3) fields (lowest
# indices) grow the first unmet crop the page needs.
func _page_need() -> String:
	var cat: Array = FE.cfg()["catalog"]
	var p := int(farm["page"])
	if p >= cat.size():
		return ""
	var needs: Dictionary = cat[p]["needs"]
	for c in needs:
		if int(farm["shipped"].get(c, 0)) < int(needs[c]) and c in farm["unlocked"]:
			return c
	return ""

func _is_page_field(i: int) -> bool:
	var owned: Array = []
	for j in 7:
		if farm["fields"][j]["owned"]:
			owned.append(j)
	var n := int(ceil(owned.size() / 3.0))
	return i in owned.slice(0, n)

func _avail(i: int) -> float:
	# wallet once this field's ripe crop is sold (base value, no stars)
	var f: Dictionary = farm["fields"][i]
	var v := float(farm["wallet"])
	if f["crop"] != "":
		var soil := pow(float(FE.cfg()["soil"]["mult"]), int(f["soil"]))
		v += 12.0 * float(FE.crop_info(f["crop"])["sell"]) * soil
	return v

# Greedy crop-for-the-gap: for each unlocked crop, value per second up to the
# bot's next hand harvest of this field, using its own schedule (and the
# Spudling shift if the field has a hut).
func _greedy(opts: Array, i: int, t: int) -> String:
	var c: Dictionary = FE.cfg()
	var up: Dictionary = farm["up"]
	var ev: float = FE.star_odds(farm)["ev"]
	var hut: bool = farm["fields"][i]["hut"] and not ignore_huts
	var share := float(c["share"][int(up["share"])][0])
	var walk := int(c["quick"]["walk_s"][int(up["quick"])]) * SEC
	var shift := int(round(float(c["house"]["shift_h"][int(up["house"])]) * HOUR))
	var avail := _avail(i)
	var best := FE.FREE_CROP
	var best_r := -INF
	for o in opts:
		if not o["unlocked"] or float(o["seed_cost"]) > avail:
			continue
		var gf := float(int(o["net"]) + int(o["seed_cost"])) / ev
		var gp := gf / _fav_mult if o["fav"] else gf
		var r := forward_rate(t, int(o["grow_ms"]), gf, gp, int(o["seed_cost"]), ev, hut, share, walk, shift)
		if r > best_r:
			best_r = r
			best = o["crop"]
	return best

# Coins per ms from planting at t until this field's next hand harvest.
# Pure planning model of the bot's own schedule; it follows the economy's
# wage rule: a Spudling pick of a crop that was already in the ground when the
# absence began (planted at or before the departure) is at full value × star
# EV after a grace of min(your_crop_grace_s, grow) past ripe, a crop planted
# during the same absence pays the share (no grace). gf is the gross of the
# crop planted at t, gp of a Spudling replant (no Favorite).
func forward_rate(t: int, g: int, gf: float, gp: float, seed: int, ev: float, hut: bool,
		share: float, walk: int, shift: int) -> float:
	var val := -float(seed)
	var cur := t
	var gross := gf
	for _guard in 16:
		var ripe := cur + g
		var pw := _win_before(ripe)
		var a: int = wins[pw][0]
		var end_in: int = int(wins[pw][1]) - SEC
		if ripe <= end_in:
			# ripe while the bot is here: picked by hand (at arrival, or after its reaction)
			var hp: int = a if ripe <= a else mini(ripe + react_ms, end_in)
			return (val + gross * ev) / float(maxi(1, hp - t))
		if pw + 1 >= wins.size():
			break
		var an: int = wins[pw + 1][0]
		if hut:
			var w0 := end_in + _clockin
			var w1 := w0 + shift
			var full := cur <= end_in
			var pick := maxi(ripe + (mini(_grace, g) if full else 0), w0) + walk
			var hi := mini(w1, an)
			if pick <= hi:
				var n := 1 + (hi - pick) / (g + walk)
				val += gross * (ev if full else share) + gp * share * (n - 1)
				cur = pick + (n - 1) * (g + walk)
				gross = gp
				continue
		return (val + gross * ev) / float(maxi(1, an - t))
	return val / float(maxi(1, cur - t))

# Leaving: a hut field whose crop the Spudlings will pick during the coming
# absence replants its plan, so set that plan for the gap (design §2: "set
# plans for the coming gap"). The plan picked is the best Spudling-planted
# crop from the pick time to the bot's next hand harvest (same look-ahead as
# a hand planting, free seed, Spudling share). Page fields keep the page crop.
func _depart_plans(t_dep: int) -> void:
	if planting != "greedy" or ignore_huts or wi + 1 >= wins.size():
		return
	var c: Dictionary = FE.cfg()
	var up: Dictionary = farm["up"]
	var ev: float = FE.star_odds(farm)["ev"]
	var share := float(c["share"][int(up["share"])][0])
	var walk := int(c["quick"]["walk_s"][int(up["quick"])]) * SEC
	var shift := int(round(float(c["house"]["shift_h"][int(up["house"])]) * HOUR))
	var w0 := t_dep + _clockin
	var hi := mini(w0 + shift, int(wins[wi + 1][0]))
	var goff := int(farm["g_offset_ms"])
	for i in 7:
		var f: Dictionary = farm["fields"][i]
		if not f["owned"] or not f["hut"] or f["crop"] == "":
			continue
		if page_policy and _is_page_field(i) and _page_need() != "":
			# The Catalog policy holds on hut fields too: the Spudlings replant
			# the plan, so a page field's plan is the page crop.
			if f["plan"] != _page_need():
				FE.set_plan(farm, i, _page_need())
			continue
		var ra: int = int(f["planted_g"]) + _crop_grow(i) - goff
		ra += mini(_grace, _crop_grow(i))      # standing crops wait out the grace
		var pick := maxi(ra, w0) + walk
		if pick > hi:
			continue
		var best: String = f["plan"]
		var best_r := -INF
		for o in FE.plan_options(farm, i, pick, TZ):
			if not o["unlocked"]:
				continue
			var gf := float(int(o["net"]) + int(o["seed_cost"])) / ev
			var gp := gf / _fav_mult if o["fav"] else gf
			var r := forward_rate(pick, int(o["grow_ms"]), gf, gp, 0, ev, true, share, walk, shift)
			if debug:
				print("    depart %s F%d %s pick %s: %s %.1f/h" % [fmt_t(t_dep), i + 1, f["crop"], fmt_t(pick), o["crop"], r * HOUR])
			if r > best_r:
				best_r = r
				best = o["crop"]
		if best != f["plan"]:
			FE.set_plan(farm, i, best)

# Naive rule (§3 mastery headroom): the longest crop that is ripe by the next
# time the bot will look at the field (>= 61 s from now).
func _naive(opts: Array, t: int) -> String:
	var look := t + 61 * SEC
	var k := _win_before(look)
	var nxt := look
	if look > int(wins[k][1]) - SEC:
		nxt = int(wins[mini(k + 1, wins.size() - 1)][0])
	var gap := nxt - t
	var avail := float(farm["wallet"])
	var best := ""
	var best_g := -1
	var shortest := FE.FREE_CROP
	for o in opts:
		if not o["unlocked"] or (float(o["seed_cost"]) > avail and strategy != "none"):
			continue
		if int(o["grow_ms"]) <= gap and int(o["grow_ms"]) > best_g:
			best_g = int(o["grow_ms"])
			best = o["crop"]
	return best if best != "" else shortest

# ════════════════════════════════════════════════════════ buying

func _tutorial_done() -> bool:
	return int(farm["goal"]["tutorial"]) >= FE.cfg()["tutorial"].size()

func _shop(t: int, force: bool) -> void:
	if strategy == "none":
		return
	if strategy == "tutorial" and not _tutorial_done():
		for _n in 6:
			var g: Dictionary = FE.next_goal(farm, t)
			if g["kind"] != "tutorial" or not g["can_buy"]:
				break
			var r: Dictionary = FE.buy_goal(farm, t, TZ)
			if not r["ok"]:
				break
			_bought(r, t)
		return
	if not force and not _dirty and int(farm["wallet"]) < _next_wallet and t < _book_t + max_book_age_ms:
		return
	for n in 60:
		var rows: Array = FE.book(farm, t, TZ)
		book_calls += 1
		_book_t = t
		_dirty = false
		if n == 0 and force and metric_afford and int(wins[wi][2]) == 1:
			afford.append([wi, _useful(rows)])
			if debug:
				var cheap := ""
				for rr in rows:
					if not rr["locked"] and float(rr["payback_s"]) > 0.0 and float(rr["payback_s"]) < 86400.0:
						cheap += " %s:%d/%s" % [rr["id"], int(rr["cost"]), Fmt.dur(float(rr["payback_s"]))]
				print("  afford #%d %s wallet %d useful%s" % [wi + 1, fmt_t(t), int(farm["wallet"]), cheap])
		var pick := choose_row(rows)
		if pick.is_empty():
			return
		var r: Dictionary = FE.buy(farm, pick["item"], pick["arg"], t, TZ)
		if not r["ok"]:
			violations.append("%s buy %s refused: %s" % [fmt_t(t), pick["id"], r["msg"]])
			return
		_bought(r, t, pick)

func _bought(r: Dictionary, t: int, row := {}) -> void:
	buy_spent += int(r["spent"])
	_events(r["events"])
	_coins_seen(t, int(r.get("spud_coins", 0)))
	purchases.append({"t": t, "id": str(r["id"]), "item": str(r["item"]), "cost": int(r["spent"]), "wi": wi,
			"payback_s": float(row.get("payback_s", 0.0)), "d_here": float(row.get("d_here", 0.0)),
			"d_away": float(row.get("d_away", 0.0)), "typ_s": FE.typical_absence_s(farm, t), "f_here": FE.f_here(farm, t)})
	_dirty = true
	_mark(t)
	if r["item"] in ["deed", "greenhouse"]:
		_tend_fields(t)        # a new field comes empty: plant it now

func _allowed(r: Dictionary) -> bool:
	var huts := int(farm["up"]["huts"])
	match strategy:
		"s1":
			if r["item"] in ["share", "quick", "house"]:
				return false
			if r["item"] == "hut" and huts >= 1:
				return false
		"s3":
			if r["item"] == "hut" and huts >= 2:
				return false
		"s4":
			return r["item"] == "soil"
		"h1":
			if r["item"] == "hut" and huts >= 1:
				return false
	return true

func _weight(r: Dictionary) -> float:
	var it: String = r["item"]
	match strategy:
		"s1":
			if it in ["tool", "soil"]:
				return bias
		"s2":
			if it in s2_items:
				return bias
		"s3":
			if it in ["sprinkler", "greenhouse"]:
				return bias
	return 1.0

# The Farm Book decision (phase B2): the target is the row with the lowest
# wait + payback for the bot's own schedule, where wait = (cost - wallet) /
# its 24 h income rate (0 when affordable) and payback is weighted by the
# strategy (S1-S3). Buy it if affordable. While saving for it, the design's
# §6.1 "within 2x" rule still buys an affordable row whose payback is within
# 2x of the target's, but only a small one (at most save_frac of the
# target's price, so the target slips at most that much per buy), or any
# affordable row whose payback is shorter than the wait (it pays for itself
# before the target is affordable). The §6.1 rule alone never saved for a
# big row once Soil came in small per-field steps: some Soil row was always
# affordable and within 2x, so the 6th field never got bought. When nothing
# has a gain, a
# zero-gain row (the Copper Hoe: Tend All, no rate change) is a convenience
# buy once it costs <= 10 minutes of income. Returns {} when nothing to buy;
# then remembers the wallet at which the decision could change.
func choose_row(rows: Array) -> Dictionary:
	var pick := _choose_roi(rows)
	if not pick.is_empty() or strategy == "s4":
		return pick
	var wallet := int(farm["wallet"])
	var inc := FE.income_rate(farm, int(farm["clock"]["last_settle_ms"]))
	for r in rows:
		if r["locked"] or not _allowed(r) or r["item"] != "tool" or float(r["payback_s"]) > 0.0:
			continue
		if int(r["cost"]) <= wallet and float(r["cost"]) <= 600.0 * inc:
			return r
		if int(r["cost"]) > wallet:
			_next_wallet = mini(_next_wallet, int(r["cost"]))
	return {}

func _choose_roi(rows: Array) -> Dictionary:
	var wallet := int(farm["wallet"])
	var inc := FE.income_rate(farm, int(farm["clock"]["last_settle_ms"]))
	if inc <= 1e-6:
		inc = FE.rate_here(farm)          # no income yet (the first minute): the present rate
	var best: Dictionary = {}
	var best_s := INF
	for r in rows:
		if r["locked"] or not _allowed(r) or float(r["payback_s"]) <= 0.0:
			continue
		var wait := 0.0
		if int(r["cost"]) > wallet:
			wait = float(int(r["cost"]) - wallet) / inc if inc > 1e-9 else INF
		var sc := wait + float(r["payback_s"]) * _weight(r)
		if sc < best_s:
			best_s = sc
			best = r
	if best.is_empty():
		_next_wallet = 1 << 62
		return {}
	if int(best["cost"]) <= wallet:
		return best
	var wait := float(int(best["cost"]) - wallet) / inc if inc > 1e-9 else INF
	var pb := float(best["payback_s"]) * _weight(best)
	var alt: Dictionary = {}
	for r in rows:
		if r["locked"] or not _allowed(r) or float(r["payback_s"]) <= 0.0 or int(r["cost"]) > wallet:
			continue
		var p := float(r["payback_s"]) * _weight(r)
		var small: bool = p <= 2.0 * pb and float(r["cost"]) <= save_frac * float(best["cost"])
		if (p < wait or small) and (alt.is_empty() or p < float(alt["payback_s"]) * _weight(alt)):
			alt = r
	if not alt.is_empty():
		return alt
	_next_wallet = int(best["cost"])
	return {}

# Day-1 class metric (§6.2): at the check-in's Farm Book read, is something
# useful (payback under a day) both unlocked and affordable?
static func _useful(rows: Array) -> bool:
	for r in rows:
		if not r["locked"] and r["can_buy"] and float(r["payback_s"]) > 0.0 and float(r["payback_s"]) < 86400.0:
			return true
	return false

# ════════════════════════════════════════════════════════ milestones + stats

func _ms(id: String, t: int) -> void:
	if not milestones.has(id):
		milestones[id] = {"t": t, "wi": wi}

func _mark(t: int) -> void:
	var owned6 := 0
	for i in 6:
		if farm["fields"][i]["owned"]:
			owned6 += 1
	if owned6 >= 2:
		_ms("field2", t)
	if int(farm["up"]["huts"]) >= 1:
		_ms("hut1", t)
	for p in range(1, int(farm["page"]) + 1):
		_ms("page%d" % p, t)
	if owned6 >= 6:
		_ms("field6", t)
		if farm["fields"][6]["owned"]:
			_ms("full", t)
	if int(farm["up"]["tool"]) >= 3:
		_ms("goldhoe", t)

func _snapshot(day: int, t: int, pre_wallet: int) -> void:
	var st: Dictionary = farm["stats"]
	var owned := 0
	for f in farm["fields"]:
		if f["owned"]:
			owned += 1
	while snaps.size() < day - 1:
		snaps.append({})
	# Per-crop harvest milli-coins of the previous UTC day ({crop: [you, spud]}).
	var mx: Dictionary = farm["mix"]
	var dn := int(floor(float(t) / DAY))
	var yday: Dictionary = {}
	if int(mx["day"]) == dn:
		yday = mx["prev"].duplicate(true)
	elif int(mx["day"]) == dn - 1:
		yday = mx["cur"].duplicate(true)
	snaps.append({"day": day, "t": t, "pre_wallet": pre_wallet, "wallet": int(farm["wallet"]), "mix_prev": yday,
			"lifetime": int(st["lifetime_coins"]), "hand": int(st["hand_coins"]), "spud": int(st["spud_coins"]),
			"penny": int(st["penny_coins"]), "soil": soil_level(), "fields": owned,
			"huts": int(farm["up"]["huts"]), "page": int(farm["page"]), "tool": int(farm["up"]["tool"]),
			"buy_spent": buy_spent, "seed_spent": seed_spent})

# Mean Soil level over the owned fields (Soil is per field), rounded.
func soil_level() -> int:
	var n := 0
	var tot := 0
	for f in farm["fields"]:
		if f["owned"]:
			n += 1
			tot += int(f["soil"])
	return int(round(float(tot) / maxf(1.0, n)))

# Snapshot at the first arrival of `day` (1-based), {} if the run ended earlier.
func snap(day: int) -> Dictionary:
	return snaps[day - 1] if day >= 1 and day <= snaps.size() else {}

# Gross farm coins (hand + Spudling + penny) credited between the first
# arrival of day d and of day d+1, and the hand share of it.
func day_income(d: int) -> Dictionary:
	var a := snap(d)
	var b := snap(d + 1)
	if a.is_empty() or b.is_empty():
		return {"coins": 0, "hand": 0.0}
	var tot := int(b["lifetime"]) - int(a["lifetime"])
	var hand := int(b["hand"]) - int(a["hand"])
	return {"coins": tot, "hand": float(hand) / float(tot) if tot > 0 else 0.0}

# Net farm earnings over the run: everything earned minus seed (= wallet +
# purchases - starting wallet).
func earned() -> int:
	return int(farm["wallet"]) + buy_spent - start_wallet

# Fixture value: net coins per day between the first arrivals of day `from`
# and day `to` (wallet before the arrival settle; buying off).
func fixture_rate(from := 2) -> float:
	var a := snap(from)
	var b := snap(snaps.size())
	if a.is_empty() or b.is_empty() or int(b["day"]) <= int(a["day"]):
		return 0.0
	return float(int(b["pre_wallet"]) - int(a["pre_wallet"])) / float(int(b["day"]) - int(a["day"]))

func milestone_text(id: String) -> String:
	if not milestones.has(id):
		return "-"
	var m: Dictionary = milestones[id]
	var t: int = m["t"]
	if profile == "active":
		var pm := played_ms(t)
		if pm < 2 * HOUR:
			return "%s (%dm)" % [fmt_t(t), int(round(pm / float(MIN)))]
		return "%s (%.1fh)" % [fmt_t(t), pm / float(HOUR)]
	return "%s #%d" % [fmt_t(t), int(m["wi"]) + 1]

func summary() -> Dictionary:
	var last := day_income(days)
	return {"profile": profile, "strategy": strategy, "planting": planting, "days": days,
			"earned": earned(), "wallet": int(farm["wallet"]), "lifetime": int(farm["stats"]["lifetime_coins"]),
			"income_last_day": last["coins"], "hand_share": last["hand"], "soil": soil_level(),
			"page": int(farm["page"]), "purchases": purchases.size(), "violations": violations.size(),
			"book_calls": book_calls}

func purchase_lines(limit := 100000) -> Array:
	var out: Array = []
	var n := 0
	for p in purchases:
		if n >= limit:
			out.append("  ... %d more" % (purchases.size() - limit))
			break
		var why := ""
		if p.has("payback_s") and float(p["payback_s"]) != 0.0:
			why = "payback %-8s here %+.2f/min away %+.2f/min  (typ %s, here %d%%)" % [
					Fmt.dur(float(p["payback_s"])) if float(p["payback_s"]) > 0 else "none", float(p["d_here"]) * 60.0,
					float(p["d_away"]) * 60.0, Fmt.dur(int(p["typ_s"])), int(round(float(p["f_here"]) * 100))]
		elif strategy == "tutorial":
			why = "(Next Goal)"
		out.append("  %s  %-22s %-7s %s" % [fmt_t(int(p["t"])), p["id"], _num(int(p["cost"])), why])
		n += 1
	return out

const Fmt = preload("res://scripts/utils/NumFmt.gd")

static func _num(n: int) -> String:
	return Fmt.coins(n)
