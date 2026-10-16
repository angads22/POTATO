extends RefCounted

# FarmSuite: every balance measurement and invariant check of design §6 and
# §5.12, run on the REAL FarmEconomy through FarmBot. Shared by the tuning CLI
# (tests/farm/farm_sim.gd) and the CI gate (tests/FarmBalanceTest.gd); each
# section prints a compact table and appends failures to `fails`.
#
# Fixture runs (SD1/SD2/SD4/SD6/SD7, hut safety) neutralize the economy's
# randomness without changing expected values, through
# FarmEconomy.reload_cfg(): every star is a silver x1.25 (EV 1.25 exactly),
# the Market Favorite is x1.0 and butterflies are not caught. reload_cfg()
# restores farm.json afterwards.

const FE = preload("res://scripts/farm/FarmEconomy.gd")
const FarmBot = preload("res://tests/farm/FarmBot.gd")
const Fmt = preload("res://scripts/utils/NumFmt.gd")

const SEC := 1000
const MIN := 60000
const HOUR := 3600000
const DAY := 86400000
const MAIN := ["active", "class", "casual"]
const ALL4 := ["active", "class", "casual", "class+eve"]
const SHORT := {"active": "act", "class": "cls", "casual": "cas", "class+eve": "c+e"}

# §6.3 windows: [id, label, active, class, casual]. Kinds:
#   ["played", lo_s, hi_s]  played (present) time      ["checkin", lo, hi]  check-in number
#   ["d1_by", sod_s]        day 1 by local time        ["days", lo, hi]     calendar day
#   null                    no target (shown, not asserted)
const MS := [
	["field2", "Field 2", ["played", 0, 300], ["checkin", 1, 2], ["checkin", 1, 2]],
	["hut1", "First hut (Pip)", ["played", 0, 180], ["checkin", 1, 1], ["checkin", 1, 1]],
	["page1", "Page 1 Yukon", ["played", 180, 600], ["d1_by", 9 * 3600], ["d1_by", 15 * 3600]],
	["page2", "Page 2 Red", ["played", 1200, 3600], ["d1_by", 11 * 3600], ["days", 1, 1]],
	["page3", "Page 3 Purple", ["played", 4 * 3600, 10 * 3600], ["days", 1, 2], ["days", 1, 2]],
	["page4", "Page 4 Fingerling", ["days", 2, 4], ["days", 2, 4], ["days", 2, 3]],
	["page5", "Page 5 King", ["days", 3, 6], ["days", 3, 5], ["days", 2, 5]],
	["page6", "Page 6 Golden", ["played", 15 * 3600, 30 * 3600], ["days", 3, 7], ["days", 3, 7]],
	["field6", "6th field", ["days", 7, 14], ["days", 7, 16], ["days", 7, 14]],
	["full", "Full farm 6+GH", ["days", 10, 20], ["days", 12, 24], ["days", 10, 20]],
	["goldhoe", "Gold Hoe", ["days", 12, 22], null, ["days", 12, 22]],
]
# §6.3 calibration column for the info rows.
const CAL := {"soil": ["L40/L44", "L40/L42", "L40/L44"], "income": ["9.2M", "5.1M", "9.0M"],
		"hand": ["89%", "86%", "61%"]}

var fails: Array = []
var main: Dictionary = {}          # profile -> FarmBot (ROI, fresh start)
var t_section := 0

# ════════════════════════════════════════════════════════ helpers

func say(s := "") -> void:
	print(s)

func fail(name: String, detail: String) -> void:
	fails.append("%s: %s" % [name, detail])

func check(cond: bool, name: String, detail: String) -> bool:
	if not cond:
		fail(name, detail)
	return cond

func pf(ok: bool) -> String:
	return "PASS" if ok else "FAIL"

func section(title: String) -> void:
	t_section = Time.get_ticks_msec()
	say("")
	say("== " + title + " " + "=".repeat(maxi(3, 74 - title.length())))

func done() -> void:
	say("   (%.1f s)" % ((Time.get_ticks_msec() - t_section) / 1000.0))

static func pct(x: float) -> String:
	return "%+.0f%%" % (x * 100.0)

static func coins(n) -> String:
	return Fmt.coins(int(n))

static func pad(s, w: int) -> String:
	var t := str(s)
	return t + " ".repeat(maxi(0, w - t.length()))

static func lpad(s, w: int) -> String:
	var t := str(s)
	return " ".repeat(maxi(0, w - t.length())) + t

static func dur(ms: int) -> String:
	return Fmt.dur(ms / 1000.0)

func bot(profile: String, strat := "roi", planting := "greedy") -> RefCounted:
	var b = FarmBot.new(profile, strat)
	b.planting = planting
	return b

# Neutral config: deterministic stars at the same EV (every plot a x1.25
# silver), Favorite x1.0, and optionally the Catalog frozen at its current page.
static func neutral_override(freeze_catalog := false) -> Dictionary:
	FE.reload_cfg()
	var c: Dictionary = FE.cfg()
	var tools: Array = c["tools"].duplicate(true)
	for t in tools:
		t["silver"] = 1.0
		t["gold"] = 0.0
	var o := {"tools": tools, "stars": {"silver_mult": 1.25, "gold_mult": 2.0}, "favorite": {"mult": 1.0}}
	if freeze_catalog:
		var cat: Array = c["catalog"].duplicate(true)
		for pg in cat:
			for k in pg["needs"]:
				pg["needs"][k] = 1000000000000
		o["catalog"] = cat
	return o

# A fixture bot: no buying, no butterflies, no Catalog policy, a 110 s
# keep-alive (still present: clock-in is 120 s), and a deep wallet.
func fixture_bot(profile: String, fx: Dictionary, planting := "greedy", crop := "") -> RefCounted:
	var b = FarmBot.new(profile, "none")
	b.planting = planting
	b.fixed_crop = crop
	b.catch_butterflies = false
	b.page_policy = false
	b.keepalive_ms = 110 * SEC
	var f := fx.duplicate(true)
	if not f.has("wallet"):
		f["wallet"] = 1000000000000
	b.fixture = f
	return b

# Canonical text of a farm for equality checks: a JSON round trip, then
# normalize() so every integer prints as an int (JSON parses numbers as floats).
func canon(farm: Dictionary) -> String:
	var p = JSON.parse_string(JSON.stringify(farm))
	FE.normalize(p)
	return JSON.stringify(p, "", true)

# A plain JSON round trip, as SaveDataManager loads a save: every number comes
# back a float and the economy's public entries normalize it themselves.
func rt(farm: Dictionary) -> Dictionary:
	return JSON.parse_string(JSON.stringify(farm))

# ════════════════════════════════════════════════════════ §6.3 milestones

func run_main(days_map: Dictionary) -> void:
	section("PROFILE RUNS (ROI buyer, greedy crop-for-the-gap, fresh start)")
	for p in MAIN:
		var t0 := Time.get_ticks_msec()
		var b = bot(p)
		b.metric_afford = p == "class"
		b.run(int(days_map[p]))
		main[p] = b
		var s: Dictionary = b.summary()
		say("   %-7s %2d days  earned %-7s wallet %-7s purchases %3d  last-day income %-7s hand %3d%%  soil L%d  (%d ms, %d book reads)" % [
				p, s["days"], coins(s["earned"]), coins(s["wallet"]), s["purchases"], coins(s["income_last_day"]),
				int(round(s["hand_share"] * 100)), s["soil"], Time.get_ticks_msec() - t0, s["book_calls"]])
		for v in b.violations:
			fail("bot " + p, v)
	done()

func target_text(spec) -> String:
	if spec == null:
		return "—"
	match spec[0]:
		"played":
			var lo: int = spec[1]
			var hi: int = spec[2]
			if hi <= 3600:
				return ("<=%dm" % (hi / 60)) if lo == 0 else ("%d-%dm" % [lo / 60, hi / 60])
			return "%d-%dh pl" % [lo / 3600, hi / 3600]
		"checkin":
			return ("#%d" % spec[1]) if spec[1] == spec[2] else ("#%d-#%d" % [spec[1], spec[2]])
		"d1_by":
			return "d1<=%02d:%02d" % [spec[1] / 3600, (spec[1] % 3600) / 60]
		"days":
			return ("d%d" % spec[1]) if spec[1] == spec[2] else ("d%d-d%d" % [spec[1], spec[2]])
	return "?"

# "PASS" / "FAIL" / "open" (not reached, window extends past the run) / "info".
func judge(b, id: String, spec) -> String:
	if spec == null:
		return "info"
	var has: bool = b.milestones.has(id)
	var t: int = b.milestones[id]["t"] if has else 0
	match spec[0]:
		"played":
			if not has:
				return "FAIL" if b.days * 4 * 3600 >= int(spec[2]) else "open"
			var s: float = b.played_ms(t) / 1000.0
			return pf(s >= spec[1] and s <= spec[2])
		"checkin":
			if not has:
				return "FAIL"
			var n: int = int(b.milestones[id]["wi"]) + 1
			return pf(n >= spec[1] and n <= spec[2])
		"d1_by":
			if not has:
				return "FAIL"
			return pf(b.day_of(t) == 1 and posmod(t, DAY) / 1000 <= int(spec[1]))
		"days":
			if not has:
				return "FAIL" if b.days >= int(spec[2]) else "open"
			var d: int = b.day_of(t)
			return pf(d >= spec[1] and d <= spec[2])
	return "?"

func print_milestones(assert_it := true) -> void:
	section("§6.3 MILESTONES (target · result · verdict)")
	var hdr := pad("Milestone", 18)
	for p in MAIN:
		hdr += "| " + pad(p + " target", 15) + pad("result", 20) + pad("", 5)
	say(hdr)
	say("-".repeat(hdr.length()))
	for row in MS:
		var line := pad(row[1], 18)
		for k in 3:
			var p: String = MAIN[k]
			var b = main[p]
			var spec = row[2 + k]
			var v := judge(b, row[0], spec)
			line += "| " + pad(target_text(spec), 15) + pad(b.milestone_text(row[0]), 20) + pad(v, 5)
			if v == "FAIL" and assert_it:
				fail("milestone %s %s" % [p, row[0]], "%s not in %s" % [b.milestone_text(row[0]), target_text(spec)])
		say(line)
	# info rows
	var r1 := pad("Soil at d14 / d21", 18)
	var r2 := pad("Income, last day", 18)
	var r3 := pad("Hand share, last", 18)
	var r4 := pad("Huts / fields end", 18)
	for k in 3:
		var p: String = MAIN[k]
		var b = main[p]
		var s14: Dictionary = b.snap(15)
		var s21: Dictionary = b.snap(22)
		var soil := "%s / %s" % [("L%d" % s14["soil"]) if not s14.is_empty() else "-", ("L%d" % s21["soil"]) if not s21.is_empty() else "-"]
		r1 += "| " + pad("cal " + CAL["soil"][k], 15) + pad(soil, 20) + pad("info", 5)
		var inc: Dictionary = b.day_income(b.days)
		r2 += "| " + pad("cal " + CAL["income"][k] + " d24", 15) + pad("%s (d%d)" % [coins(inc["coins"]), b.days], 20) + pad("info", 5)
		r3 += "| " + pad("cal " + CAL["hand"][k], 15) + pad("%d%%" % int(round(inc["hand"] * 100)), 20) + pad("info", 5)
		var last: Dictionary = b.snap(b.days + 1)
		r4 += "| " + pad("", 15) + pad("%d huts / %d fields" % [last["huts"], last["fields"]], 20) + pad("info", 5)
	say(r1)
	say(r2)
	say(r3)
	say(r4)
	say("   active times show (played time); class/casual show #check-in. 'open' = window extends past the run.")

func print_daily(b) -> void:
	say("   day  wallet    income/day  hand  spud   soil fields huts page tool")
	for d in range(1, b.days + 1):
		var s: Dictionary = b.snap(d)
		var inc: Dictionary = b.day_income(d)
		if s.is_empty():
			continue
		var sp := 0.0
		var nx: Dictionary = b.snap(d + 1)
		if not nx.is_empty() and inc["coins"] > 0:
			sp = float(int(nx["spud"]) - int(s["spud"])) / float(inc["coins"])
		say("   d%-3d %-9s %-11s %3d%%  %3d%%  L%-3d %d      %d    %d    %d" % [d, coins(s["wallet"]), coins(inc["coins"]),
				int(round(inc["hand"] * 100)), int(round(sp * 100)), s["soil"], s["fields"], s["huts"], s["page"], s["tool"]])

# ════════════════════════════════════════════════════════ §6.2 feel targets

func feel() -> void:
	section("§6.2 FEEL TARGETS")
	# fresh active start following the Next Goal card (tutorial), then ROI
	var tb = bot("active", "tutorial")
	tb.run(1)
	var t0: int = tb.t_start
	var first_coins: float = (tb.first_coins_t - t0) / 1000.0 if tb.first_coins_t >= 0 else INF
	var pip: float = (int(tb.milestones["hut1"]["t"]) - t0) / 1000.0 if tb.milestones.has("hut1") else INF
	var times: Array = []
	for p in tb.purchases:
		if int(p["t"]) - t0 < 15 * MIN:
			times.append(int(p["t"]) - t0)
	var gaps: Array = [0] + times + [15 * MIN]
	var max_gap := 0
	for k in range(1, gaps.size()):
		max_gap = maxi(max_gap, int(gaps[k]) - int(gaps[k - 1]))
	var trace: Array = []
	for p in tb.purchases:
		if int(p["t"]) - t0 < 15 * MIN:
			trace.append("%s %s" % [_mmss(int(p["t"]) - t0), p["id"]])
	say("   first coins                 %-8s target <=45s   %s" % [_mmss(int(first_coins * 1000)), pf(first_coins <= 45.0)])
	check(first_coins <= 45.0, "feel first coins", "%.0f s" % first_coins)
	say("   first Spudling (Pip)        %-8s target <=2m    %s" % [_mmss(int(pip * 1000)), pf(pip <= 120.0)])
	check(pip <= 120.0, "feel Pip", "%.0f s" % pip)
	var ok15: bool = times.size() >= 6 and max_gap <= 5 * MIN
	say("   buys in first 15 active min %-8s target >=6, gap<=5m (max gap %s)   %s" % [str(times.size()), _mmss(max_gap), pf(ok15)])
	check(ok15, "feel 15-min purchases", "%d purchases, max gap %s" % [times.size(), _mmss(max_gap)])
	say("     tutorial trace: " + ", ".join(trace))
	if main.has("active"):
		var rb = main["active"]
		var n := 0
		for p in rb.purchases:
			if int(p["t"]) - int(rb.t_start) < 15 * MIN:
				n += 1
		say("     (plain ROI bot, no tutorial: %d purchases in the first 15 min)" % n)
	# class day 1: something useful affordable at each check-in
	if main.has("class"):
		var cb = main["class"]
		var yes := 0
		var miss: Array = []
		for a in cb.afford:
			if a[1]:
				yes += 1
			else:
				miss.append("#%d" % (int(a[0]) + 1))
		var frac: float = float(yes) / maxf(1.0, cb.afford.size())
		say("   class d1 check-ins w/ useful affordable buy (payback<1d)  %d/%d = %d%%  target >=75%%   %s" % [yes,
				cb.afford.size(), int(round(frac * 100)), pf(frac >= 0.75)])
		if not miss.is_empty():
			say("     none affordable at: " + " ".join(miss.slice(0, 20)))
		check(frac >= 0.75, "feel class d1 affordable", "%d%%" % int(round(frac * 100)))
	# class tutorial: the first check-in after Pip shows Spudling coins
	var ct = bot("class", "tutorial")
	ct.run(1)
	var shown := -1
	var at := ""
	if ct.milestones.has("hut1"):
		var hire: int = ct.milestones["hut1"]["t"]
		for a in ct.arrivals:
			if int(a["t"]) > hire:
				shown = int(a["spud"])
				at = ct.fmt_t(int(a["t"]))
				break
	say("   class: next check-in after Pip shows Spudling coins  %s +%d c (design ≈ +96)   %s" % [at, shown, pf(shown > 0)])
	check(shown > 0, "feel class Spudling coins", "next check-in after Pip shows %d" % shown)
	done()

static func _mmss(ms: int) -> String:
	if ms >= 1 << 60 or ms < 0:
		return "never"
	var s := ms / 1000
	return "%d:%02d" % [s / 60, s % 60]

# ════════════════════════════════════════════════════════ fixtures: SD1 SD2 SD6 SD7

# Hand-field fixture (page 6, one field, base multipliers): greedy vs every
# fixed crop, per profile. Returns {profile: {"greedy": bot, crop: rate}}.
func hand_fixtures(profiles: Array, fdays := 3) -> Dictionary:
	FE.reload_cfg(neutral_override())
	var out := {}
	for p in profiles:
		var g = fixture_bot(p, {"page": 6, "owned": [0]})
		g.track_cycles = true
		g.run(fdays)
		var row := {"greedy": g, "rate": g.fixture_rate()}
		for c in FE.crops():
			var f = fixture_bot(p, {"page": 6, "owned": [0]}, "fixed", c)
			f.run(fdays)
			row[c] = f.fixture_rate()
		var sp = fixture_bot(p, {"page": 6, "owned": [0], "sprinklers": ["1-2"]})
		sp.run(fdays)
		row["sprinkler"] = sp.fixture_rate()
		out[p] = row
	FE.reload_cfg()
	return out

# Day (same local day) vs night cycles of a greedy hand field.
static func cycle_split(b) -> Dictionary:
	var acc := {"day": [0, 0], "night": [0, 0]}
	var crop_ms := {}
	var t_from: int = b.snap(2)["t"] if not b.snap(2).is_empty() else 0
	for c in b.cycles:
		if int(c["t0"]) < t_from:
			continue
		var key := "night" if c["night"] else "day"
		acc[key][0] += int(c["net"])
		acc[key][1] += int(c["t1"]) - int(c["t0"])
		if not c["night"]:
			crop_ms[c["crop"]] = int(crop_ms.get(c["crop"], 0)) + int(c["t1"]) - int(c["t0"])
	var top := ""
	var top_ms := -1
	for k in crop_ms:
		if crop_ms[k] > top_ms:
			top_ms = crop_ms[k]
			top = k
	var day_rate: float = acc["day"][0] / maxf(1.0, acc["day"][1] / 60000.0)
	var night_rate: float = acc["night"][0] / maxf(1.0, acc["night"][1] / 60000.0)
	return {"day_rate": day_rate, "night_rate": night_rate, "ratio": day_rate / night_rate if night_rate > 0 else INF,
			"top": top, "crop_ms": crop_ms}

func sd_fixtures(profiles: Array) -> void:
	section("SD1 / SD2 / SD6 / SD7  hand-field fixture (page 6, 1 field, base value, EV-exact stars)")
	var hf := hand_fixtures(profiles)
	var crops: Array = FE.crops()
	# SD2 table
	var hdr := pad("per field per day", 18)
	for p in profiles:
		hdr += lpad(SHORT[p], 13)
	say(hdr)
	var g_line := pad("greedy (net c)", 18)
	for p in profiles:
		g_line += lpad(coins(hf[p]["rate"]), 13)
	say(g_line)
	var sd2_bad: Array = []
	for c in crops:
		var line := pad("  fixed " + c, 18)
		var n85 := 0
		for p in profiles:
			var r: float = hf[p][c] / hf[p]["rate"] if hf[p]["rate"] > 0 else 0.0
			if r >= 0.85:
				n85 += 1
			line += lpad("%d%%" % int(round(r * 100)), 13)
		if n85 >= 2:
			sd2_bad.append("%s (%d profiles >=85%%)" % [c, n85])
		say(line)
	var best_single := 0.0
	for p in profiles:
		for c in crops:
			best_single = maxf(best_single, hf[p][c] / hf[p]["rate"])
	say("SD2 no single crop >=85%% of greedy on 2+ profiles: best single %d%%  %s %s" % [int(round(best_single * 100)),
			pf(sd2_bad.is_empty()), ", ".join(sd2_bad)])
	check(sd2_bad.is_empty(), "SD2", ", ".join(sd2_bad))
	# SD1: the day (in-session) crop
	var tops := {}
	var l1 := "SD1 day crop (most field-time, same-day cycles): "
	for p in profiles:
		var cs := cycle_split(hf[p]["greedy"])
		tops[p] = cs["top"]
		l1 += "%s %s  " % [SHORT[p], cs["top"]]
	var distinct := {}
	for p in ["active", "class", "casual"]:
		if tops.has(p):
			distinct[tops[p]] = true
	var sd1 := distinct.size() == 3
	say(l1 + pf(sd1))
	check(sd1, "SD1", "day crops %s" % str(tops))
	# SD6: sprinkler on a hand field
	var l6 := "SD6 sprinkler on a hand field: "
	var lo := INF
	var hi := -INF
	for p in profiles:
		var v: float = hf[p]["sprinkler"] / hf[p]["rate"] - 1.0
		lo = minf(lo, v)
		hi = maxf(hi, v)
		l6 += "%s %s  " % [SHORT[p], pct(v)]
	var sd6 := hi - lo >= 0.10
	say(l6 + "spread %d pp (>=10)  %s   [cal +8/+0/+16/+0]" % [int(round((hi - lo) * 100)), pf(sd6)])
	check(sd6, "SD6", "spread %.1f pp" % ((hi - lo) * 100))
	# SD7: day vs night per field-minute
	var l7 := "SD7 day:night c/field-min: "
	var sd7 := true
	for p in profiles:
		var cs := cycle_split(hf[p]["greedy"])
		l7 += "%s %.1f/%.1f=%.2fx  " % [SHORT[p], cs["day_rate"], cs["night_rate"], cs["ratio"]]
		if p in ["active", "class"]:
			sd7 = sd7 and cs["ratio"] >= 1.5 and cs["ratio"] <= 2.5
	say(l7 + "(active,class in 1.5-2.5) " + pf(sd7) + "   [cal act 41/16.8=2.4 cls 33.6/19.8=1.7]")
	check(sd7, "SD7", l7)
	done()

# ════════════════════════════════════════════════════════ SD4 hut value

const TIERS := [[0, 0, 0, "50% 60s 2h"], [0, 0, 1, "50% 60s 4h"], [1, 1, 2, "60% 30s 8h"], [2, 2, 3, "70% 15s 12h"]]
const STAGES := ["yukon", "red", "purple", "fing", "king", "all"]

func sd4(profiles: Array, fdays := 3) -> void:
	section("SD4 hut value per field (greedy plans; vs the same field by hand)")
	FE.reload_cfg(neutral_override(true))
	var hdr := pad("stage", 8) + pad("profile", 9) + lpad("hand c/day", 12)
	for t in TIERS:
		hdr += lpad(t[3], 14)
	say(hdr)
	var worst := INF
	var worst_at := ""
	for st in 6:
		for p in profiles:
			var base = fixture_bot(p, {"page": st + 1, "owned": [0]})
			base.run(fdays)
			var hv: float = base.fixture_rate()
			var line := pad(STAGES[st], 8) + pad(p, 9) + lpad(coins(hv), 12)
			for t in TIERS:
				var hb = fixture_bot(p, {"page": st + 1, "owned": [0], "huts": [0], "share": t[0], "quick": t[1], "house": t[2]})
				hb.run(fdays)
				var v: float = hb.fixture_rate() / hv - 1.0 if hv > 0 else 0.0
				if v < worst:
					worst = v
					worst_at = "%s %s %s" % [STAGES[st], p, t[3]]
				line += lpad(pct(v), 14)
			say(line)
	FE.reload_cfg()
	var ok := worst >= -0.02
	say("SD4 min hut value %s at %s (>= -2%%)  %s" % [pct(worst), worst_at, pf(ok)])
	check(ok, "SD4", "hut value %s at %s" % [pct(worst), worst_at])
	done()

# ════════════════════════════════════════════════════════ SD3 tournament, SD5

const STRATS := [["s1", "S1 Hands-on"], ["s2", "S2 Spudling boss"], ["s3", "S3 Long-crop"], ["s4", "S4 Soil-only"], ["roi", "S5 ROI buyer"]]

func sd3(profiles: Array, ndays: int) -> void:
	section("SD3 tournament: 5 strategies x %d profiles x %d days (net coins earned, %% of best)" % [profiles.size(), ndays])
	var score := {}
	for s in STRATS:
		score[s[0]] = {}
		for p in profiles:
			var b = bot(p, s[0])
			b.run(ndays)
			score[s[0]][p] = float(b.earned())
	var hdr := pad("strategy", 18)
	for p in profiles:
		hdr += lpad(p, 18)
	say(hdr)
	var best := {}
	var winner := {}
	for p in profiles:
		best[p] = -INF
		for s in STRATS:
			if score[s[0]][p] > best[p]:
				best[p] = score[s[0]][p]
				winner[p] = s[0]
	var close_all: Array = []
	for s in STRATS:
		var line := pad(s[1], 18)
		var all_close := true
		for p in profiles:
			var v: float = score[s[0]][p]
			var r: float = v / best[p] if best[p] > 0 else 0.0
			all_close = all_close and r >= 0.95
			line += lpad("%s %3d%%%s" % [coins(v), int(round(r * 100)), "*" if winner[p] == s[0] else " "], 18)
		if all_close:
			close_all.append(s[1])
		say(line)
	var wset := {}
	for p in profiles:
		wset[winner[p]] = true
	var ok_a := close_all.is_empty()
	var ok_b := wset.size() >= 2
	say("SD3 no strategy within 5%% of best everywhere: %s %s · distinct winners %d (>=2): %s" % [pf(ok_a),
			", ".join(close_all), wset.size(), pf(ok_b)])
	check(ok_a, "SD3", "within 5% of the best on every profile: " + ", ".join(close_all))
	check(ok_b, "SD3", "one strategy wins every profile: " + str(winner))
	done()

func sd5(profiles: Array, ndays: int) -> void:
	section("SD5 smart (greedy + Favorite + placement) vs naive 'longest crop ripe by return', ROI buying, %d days" % ndays)
	var n10 := 0
	var line := ""
	for p in profiles:
		var g = main[p] if main.has(p) and main[p].days == ndays else null
		if g == null:
			g = bot(p)
			g.run(ndays)
		var nv = bot(p, "roi", "naive")
		nv.run(ndays)
		var r: float = float(g.earned()) / maxf(1.0, nv.earned()) - 1.0
		if r >= 0.10:
			n10 += 1
		line += "%s %s (%s vs %s)  " % [SHORT[p], pct(r), coins(g.earned()), coins(nv.earned())]
	say("   " + line)
	say("SD5 smart beats naive by >=10%% on >=2 profiles: %d  %s   [cal hand-only 1/2/7/12%%]" % [n10, pf(n10 >= 2)])
	check(n10 >= 2, "SD5", line)
	done()

# ════════════════════════════════════════════════════════ SD8, SD9

func sd8() -> void:
	section("SD8 Farm Picnic: a kitchen minute <= 0.5 farm-power minute; cap 15 farm-min")
	var ok := true
	var farms: Array = []
	var f0 := FE.new_farm()
	farms.append(["unstarted", f0])
	for p in main:
		farms.append([p + " end", main[p].farm])
	var line := ""
	for pr in farms:
		var f: Dictionary = pr[1]
		var fp: float = FE.farm_power(f)
		var one: int = FE.picnic_coins(f, 60.0, 1.0)
		var cap: int = FE.picnic_coins(f, 7200.0, 1.0)
		var started: bool = int(f["clock"]["epoch_ms"]) != 0
		var o1: bool = one <= int(ceil(0.5 * 60.0 * fp)) + 1
		var o2: bool = cap <= int(ceil(15.0 * 60.0 * fp)) + 1
		var o3: bool = started or (one == 0 and cap == 0)
		var o4: bool = FE.picnic_coins(f, 600.0, 0.5) <= FE.picnic_coins(f, 600.0, 1.0)
		ok = ok and o1 and o2 and o3 and o4
		line += "%s: 1 min %s / farm-min %s, cap %s  " % [pr[0], coins(one), coins(int(60 * fp)), coins(cap)]
	say("   " + line)
	say("SD8 %s" % pf(ok))
	check(ok, "SD8", line)
	done()

# Kendall tau-a over the items both sequences share, counting only pairs of
# different kinds ("soil#3" before "soil#4" is true for everyone and would
# say nothing about strategy). Items are "kind#n" labels.
static func kendall(a: Array, b: Array) -> float:
	var shared: Array = []
	for x in a:
		if x in b:
			shared.append(x)
	var n := shared.size()
	var conc := 0
	var disc := 0
	var pairs := 0
	for i in n:
		for j in range(i + 1, n):
			if str(shared[i]).split("#")[0] == str(shared[j]).split("#")[0]:
				continue
			pairs += 1
			var s1 := signi(a.find(shared[i]) - a.find(shared[j]))
			var s2 := signi(b.find(shared[i]) - b.find(shared[j]))
			if s1 * s2 > 0:
				conc += 1
			elif s1 * s2 < 0:
				disc += 1
	return float(conc - disc) / float(maxi(1, pairs))

static func seq_labels(b, until_day: int) -> Array:
	var cnt := {}
	var out: Array = []
	for p in b.purchases:
		if b.day_of(int(p["t"])) > until_day:
			break
		var it: String = p["item"]
		var key := it
		if it == "strain":
			key = p["id"]
		cnt[key] = int(cnt.get(key, 0)) + 1
		out.append("%s#%d" % [key, cnt[key]])
	return out

func sd9() -> void:
	section("SD9 greedy buyer purchase order, first 3 days (Kendall tau, shared items of different kinds, < 0.8)")
	var seqs := {}
	for p in MAIN:
		seqs[p] = seq_labels(main[p], 3)
		say("   %-7s %s" % [p, " ".join(seqs[p].slice(0, 24)) + (" …(%d)" % seqs[p].size() if seqs[p].size() > 24 else "")])
	var ok := true
	var line := ""
	for pr in [["active", "class"], ["active", "casual"], ["class", "casual"]]:
		var tau := kendall(seqs[pr[0]], seqs[pr[1]])
		ok = ok and tau < 0.8
		line += "%s-%s %.2f  " % [SHORT[pr[0]], SHORT[pr[1]], tau]
	say("SD9 tau %s %s" % [line, pf(ok)])
	check(ok, "SD9", line)
	done()

# ════════════════════════════════════════════════════════ §5.12 invariants

const T0 := 1792044000000      # 2026-10-15 06:00 UTC

func invariants() -> void:
	section("§5.12 INVARIANTS 2-8")
	FE.reload_cfg()
	inv_bulk_stepped()
	inv_shift_cap()
	inv_nothing_lost()
	inv_hut_safety()
	inv_no_deadlock()
	inv_perf()
	inv_determinism()
	done()

# A mid-game farm: every field and the Greenhouse, huts, mixed plans planted
# by hand at t_plant, last input at t_input.
func _mid_farm(tz: int, t_plant: int, house: int) -> Dictionary:
	var f := FE.new_farm()
	f["wallet"] = 50000000
	FE.start(f, t_plant - MIN, tz)
	f["page"] = 6
	for i in 7:
		f["fields"][i]["owned"] = true
		f["fields"][i]["hut"] = i != 3
		f["fields"][i]["hut_k"] = i
	f["up"]["huts"] = 7
	f["up"]["house"] = house
	f["up"]["share"] = 1
	f["up"]["quick"] = 1
	f["up"]["soil"] = 7
	f["up"]["tool"] = 2
	f["up"]["strains"] = {"red": 2, "yukon_gold": 1}
	f["sprinklers"] = ["2-5"]
	f["up"]["sprinklers"] = 1
	FE.normalize(f)
	var d := FE.day_index(t_plant, tz)
	var plans := ["russet", "yukon_gold", "red", FE.favorite(d), FE.favorite(d + 1), "purple", "fingerling"]
	for i in 7:
		FE.set_plan(f, i, plans[i])
		FE.tend(f, i, t_plant, tz)
	return f

func inv_bulk_stepped() -> void:
	var tz := -5 * 3600
	var ok := true
	var detail := ""
	for house in [3, 0]:
		var tp := (FarmBot.DAY0 + 2) * DAY + 20 * HOUR - tz * 1000     # local 20:00, 8 h crosses midnight
		var f := _mid_farm(tz, tp - 30 * MIN, house)
		FE.note_input(f, tp, tz)
		var bulk := rt(f)
		var step := rt(f)
		var r: Dictionary = FE.settle(bulk, tp + 8 * HOUR, tz)
		for k in 480:
			step = rt(step)
			FE.settle(step, tp + (k + 1) * MIN, tz)
		var same := canon(bulk) == canon(step)
		ok = ok and same and int(r["picks"]) > 0
		detail += "shift %dh: %d picks %s c %s  " % [[2, 4, 8, 12][house], r["picks"], coins(r["coins"]), "equal" if same else "DIFFER"]
		if not same:
			_diff(rt(bulk), rt(step), "")
	say("   2 bulk == 480 x 60 s stepped (JSON round trip each step): %s %s" % [detail, pf(ok)])
	check(ok, "inv2 bulk==stepped", detail)

func _diff(a, b, path: String) -> void:
	if a is Dictionary and b is Dictionary:
		for k in a:
			if not b.has(k):
				say("     missing %s.%s" % [path, k])
			else:
				_diff(a[k], b[k], path + "." + str(k))
	elif a is Array and b is Array and a.size() == b.size():
		for k in a.size():
			_diff(a[k], b[k], "%s[%d]" % [path, k])
	elif str(a) != str(b):
		say("     %s: %s vs %s" % [path, str(a), str(b)])

func inv_shift_cap() -> void:
	var f := _mid_farm(0, T0, 0)
	FE.note_input(f, T0 + MIN, 0)
	var w1: int = T0 + MIN + 120 * SEC + 2 * HOUR
	var a := rt(f)
	var b := rt(f)
	var c := rt(f)
	FE.settle(a, w1 + HOUR, 0)
	FE.settle(b, w1 + 3 * DAY, 0)
	FE.settle(c, w1, 0)
	var keys := ["wallet", "fields", "shipped"]
	var same := true
	for k in keys:
		same = same and JSON.stringify(a[k]) == JSON.stringify(b[k]) and JSON.stringify(a[k]) == JSON.stringify(c[k])
	say("   3 shift cap: wallet at w1 %s = w1+1h %s = w1+3d %s  %s" % [coins(c["wallet"]), coins(a["wallet"]),
			coins(b["wallet"]), pf(same)])
	check(same, "inv3 shift cap", "w1 %d, +1h %d, +3d %d" % [c["wallet"], a["wallet"], b["wallet"]])

# Pseudo-random inputs and settles on a mixed farm (own xorshift): no settle
# lowers the wallet, a ripe hand field stays ripe, a rollback credits
# nothing and moves no crop.
func inv_nothing_lost() -> void:
	var f := _mid_farm(3600, T0, 1)
	var s := 12345
	var t := T0 + MIN
	var bad: Array = []
	var settles := 0
	for k in 400:
		s = FE.xorshift32(s)
		var step: int = [5 * SEC, 70 * SEC, 10 * MIN, 2 * HOUR, 9 * HOUR][s % 5]
		s = FE.xorshift32(s)
		t += step + s % 60000
		var w := int(f["wallet"])
		var ripe: Array = []
		for i in 7:
			if not f["fields"][i]["hut"] and FE.field_view(f, i, t)["ripe"]:
				ripe.append(i)
		FE.settle(f, t, 3600)
		settles += 1
		if int(f["wallet"]) < w:
			bad.append("settle lowered wallet at step %d" % k)
		for i in ripe:
			if not FE.field_view(f, i, t)["ripe"]:
				bad.append("field %d lost its ripe crop at step %d" % [i, k])
		s = FE.xorshift32(s)
		if s % 3 == 0:
			FE.note_input(f, t, 3600)
		elif s % 3 == 1:
			s = FE.xorshift32(s)
			FE.tend(f, s % 7, t, 3600)
	# rollback by 1 h: nothing credited, ripe stays ripe, growing stays put
	var w := int(f["wallet"])
	var views: Array = []
	for i in 7:
		views.append(FE.field_view(f, i, t))
	var r: Dictionary = FE.settle(f, t - HOUR, 3600)
	if not r["rebased"] or int(f["wallet"]) != w:
		bad.append("rollback credited or did not rebase")
	for i in 7:
		var v: Dictionary = FE.field_view(f, i, t - HOUR)
		if v["ripe"] != views[i]["ripe"] or absi(int(v["left_ms"]) - int(views[i]["left_ms"])) > 0:
			bad.append("rollback moved field %d" % i)
	var bot_bad := 0
	for p in main:
		bot_bad += main[p].violations.size()
	var ok := bad.is_empty() and bot_bad == 0
	say("   4 nothing lost: %d random settles + 1 h rollback, %d issues; profile-bot settle monitors %d issues  %s" % [
			settles, bad.size(), bot_bad, pf(ok)])
	for b in bad.slice(0, 5):
		say("     " + b)
	check(ok, "inv4 nothing lost", "; ".join(bad.slice(0, 5)))

# Hut safety, for every crop, helper tier set and absence: hand-plant at T0,
# be away `gap`, come back and tend. Value = wallet change + the crop in the
# ground at its pro-rated hand value. EV-exact stars, Favorite x1.0.
# Asserted bound (restated §5.12.5, for the lead to confirm): per absence,
#   value(hut) >= value(no hut) - (star_ev - 1) x gross(picked crop)
# A Spudling picks your crop at full value without stars (§5.6 rule 3) and
# replants for free, so when it picks just before you return the hut loses
# exactly the star bonus and saves the replant seed: -0.25 x gross + seed,
# which is -0.04 of a hand harvest for a seeded crop (seed ~0.2 x gross, the
# design's "-5%", still checked against -0.06 below) but -0.20 for Russet
# (seed 0), so §5.12.5's flat -0.06 cannot hold for every crop.
func inv_hut_safety() -> void:
	FE.reload_cfg(neutral_override(true))
	var worst := INF
	var worst_at := ""
	var worst_seeded := INF
	var seeded_at := ""
	var bad_at := ""
	var n_bad := 0
	var cases := 0
	var tiers := [[0, 0, 0], [0, 0, 1], [1, 1, 2], [2, 2, 3], [0, 2, 0], [2, 0, 3]]
	for c in FE.crops():
		var g: int = FE.crop_info(c)["grow_ms"]
		for tr in tiers:
			var walk := int(FE.cfg()["quick"]["walk_s"][tr[1]]) * SEC
			var shift := int(FE.cfg()["house"]["shift_h"][tr[2]]) * HOUR
			var gaps: Array = [30 * SEC, 2 * MIN, 3 * MIN, 5 * MIN, 15 * MIN, 30 * MIN, HOUR, 3 * HOUR, 8 * HOUR, 12 * HOUR,
					17 * HOUR, 30 * HOUR]
			for x in [g, g + 120 * SEC + walk, 2 * (g + walk) + 120 * SEC, 120 * SEC + shift]:
				for d in [-SEC, 0, SEC, 30 * SEC]:
					gaps.append(maxi(SEC, x + d))
			for gap in gaps:
				var v := [0.0, 0.0]
				var hh := 0.0
				for h in 2:
					var f := FE.new_farm()
					f["wallet"] = 1000000000
					f["page"] = 6
					f["fields"][0]["hut"] = h == 1
					f["fields"][0]["hut_k"] = 0 if h == 1 else -1
					f["up"]["huts"] = h
					f["up"]["share"] = tr[0]
					f["up"]["quick"] = tr[1]
					f["up"]["house"] = tr[2]
					FE.normalize(f)
					FE.start(f, T0 - MIN, 0)
					FE.set_plan(f, 0, c)
					FE.tend(f, 0, T0, 0)
					var w0 := int(f["wallet"])
					FE.settle(f, T0 + gap, 0)
					FE.tend(f, 0, T0 + gap, 0)
					var fv: Dictionary = FE.field_view(f, 0, T0 + gap)
					var gross: float = 12.0 * FE.crop_info(fv["crop"])["sell"] if fv["crop"] != "" else 0.0
					hh = 12.0 * FE.crop_info(c)["sell"] * 1.25
					v[h] = float(int(f["wallet"]) - w0) + gross * 1.25 * float(fv["progress"])
				cases += 1
				var m: float = (v[1] - v[0]) / hh
				# (star_ev - 1) x gross in hand harvests, + 2 c of whole-coin rounding
				var bound: float = -(0.25 * 12.0 * float(FE.crop_info(c)["sell"]) + 2.0) / hh
				if m < bound:
					n_bad += 1
					if bad_at == "":
						bad_at = "%s tiers %s gap %s: %+.3f < %+.3f" % [c, str(tr), dur(gap), m, bound]
				if m < worst:
					worst = m
					worst_at = "%s tiers %s gap %s" % [c, str(tr), dur(gap)]
				if FE.crop_info(c)["seed"] > 0 and m < worst_seeded:
					worst_seeded = m
					seeded_at = "%s tiers %s gap %s" % [c, str(tr), dur(gap)]
	FE.reload_cfg()
	var ok := n_bad == 0 and worst_seeded >= -0.06
	say("   5 hut safety: %d cases, %d below hut - hand >= -(star_ev - 1) x gross; worst %+.3f hand harvests at %s; seeded crops worst %+.3f (>= -0.06) at %s  %s" % [
			cases, n_bad, worst, worst_at, worst_seeded, seeded_at, pf(ok)])
	check(ok, "inv5 hut safety", "%d below the star bound (%s); seeded worst %+.3f at %s" % [n_bad, bad_at, worst_seeded, seeded_at])

func inv_no_deadlock() -> void:
	var f := FE.new_farm()
	f["wallet"] = 0
	FE.normalize(f)
	FE.set_plan(f, 0, "russet")
	var t := T0
	var r: Dictionary = FE.tend(f, 0, t, 0)
	var n := 0
	while int(f["page"]) < 1 and n < 40:
		t += 41 * SEC
		FE.tend(f, 0, t, 0)
		n += 1
	# a short wallet on an expensive plan falls back to free Russet
	var g := FE.new_farm()
	g["wallet"] = 0
	FE.normalize(g)
	g["page"] = 6
	FE.normalize(g)
	FE.set_plan(g, 0, "golden")
	var r2: Dictionary = FE.tend(g, 0, T0, 0)
	var fb: bool = g["fields"][0]["crop"] == "russet" and str(r2["msg"]).begins_with("Needs")
	var ok: bool = r["ok"] and int(f["page"]) >= 1 and int(f["wallet"]) > 0 and fb
	say("   6 no deadlock: wallet 0 -> page 1 after %d Russet harvests, wallet %d; Golden plan at 0 c -> %s ('%s')  %s" % [
			n, f["wallet"], g["fields"][0]["crop"], r2["msg"], pf(ok)])
	check(ok, "inv6 no deadlock", "page %d after %d harvests, fallback %s" % [f["page"], n, fb])

func inv_perf() -> void:
	var f := _mid_farm(0, T0, 3)
	for i in 7:
		f["fields"][i]["hut"] = true
	f["up"]["quick"] = 2
	f["up"]["soil"] = 40
	FE.normalize(f)
	FE.note_input(f, T0 + MIN, 0)
	var times: Array = []
	for k in 5:
		var c := rt(f)
		var us := Time.get_ticks_usec()
		FE.settle(c, T0 + MIN + 7 * DAY, 0)
		times.append(Time.get_ticks_usec() - us)
	times.sort()
	var med: int = times[2]
	var bk := rt(f)
	var us2 := Time.get_ticks_usec()
	FE.book(bk, T0 + 2 * MIN, 0)
	var book_us := Time.get_ticks_usec() - us2
	var ok := med < 100000
	say("   7 performance: 7-day settle of a full farm %.2f ms (median of 5; < 100 ms); book() %.2f ms  %s" % [
			med / 1000.0, book_us / 1000.0, pf(ok)])
	check(ok, "inv7 performance", "%.2f ms" % (med / 1000.0))

func inv_determinism() -> void:
	var a = bot("class")
	a.run(2)
	var b = bot("class")
	b.run(2)
	var same: bool = canon(a.farm) == canon(b.farm) and JSON.stringify(a.purchases) == JSON.stringify(b.purchases)
	# The economy must never touch the global RNG.
	var src := FileAccess.get_file_as_string("res://scripts/farm/FarmEconomy.gd")
	var hits: Array = []
	var rx := RegEx.new()
	rx.compile("(?<![A-Za-z_.])(randf|randi|randf_range|randi_range|randfn|randomize|seed)\\s*\\(|RandomNumberGenerator")
	var ln := 0
	for line in src.split("\n"):
		ln += 1
		var code := line.split("#")[0]
		if rx.search(code) != null:
			hits.append("line %d: %s" % [ln, line.strip_edges()])
	var ok := same and hits.is_empty()
	say("   8 determinism: two class 2-day runs %s; global RNG calls in FarmEconomy.gd: %d  %s" % [
			"identical" if same else "DIFFER", hits.size(), pf(ok)])
	for h in hits:
		say("     " + h)
	check(ok, "inv8 determinism", "runs %s, rng hits %s" % [same, str(hits)])

# ════════════════════════════════════════════════════════ bankroll, magnitudes, veteran

func bankroll(days_map: Dictionary) -> void:
	section("BANKROLL: a 10,000 c start moves Catalog pages <= 25% earlier (elapsed calendar time)")
	var ok := true
	for p in MAIN:
		var nd := int(days_map[p])
		var base = main[p] if main.has(p) and main[p].days >= nd else null
		if base == null:
			base = bot(p)
			base.run(nd)
		var bk = bot(p)
		bk.start_wallet = 10000
		bk.run(nd)
		var line: String = "   %-7s" % p
		for k in range(1, 7):
			var id := "page%d" % k
			if not base.milestones.has(id) or not bk.milestones.has(id):
				line += "  p%d -" % k
				continue
			var eb: int = int(base.milestones[id]["t"]) - int(base.t_start)
			var ek: int = int(bk.milestones[id]["t"]) - int(bk.t_start)
			var r: float = float(ek) / float(maxi(1, eb)) - 1.0
			var good := r >= -0.25
			ok = ok and good
			line += "  p%d %s→%s %s%s" % [k, dur(eb), dur(ek), pct(r), "" if good else "!"]
			if not good:
				fail("bankroll %s page %d" % [p, k], "%s -> %s (%s)" % [dur(eb), dur(ek), pct(r)])
		say(line)
	say("BANKROLL %s   [cal: page 6 same day; worst active p2 38m→30m -21%%]" % pf(ok))
	done()

func magnitudes(ndays: int) -> void:
	section("MAGNITUDES: %d-day class run" % ndays)
	var b = bot("class")
	b.run(ndays)
	var f: Dictionary = b.farm
	var bad: Array = []
	for s in b.snaps:
		if s.is_empty():
			continue
		if int(s["wallet"]) >= 1000000000000000 or int(s["wallet"]) < 0:
			bad.append("d%d wallet %d" % [s["day"], s["wallet"]])
	var tnow := int(f["clock"]["last_settle_ms"])
	var nums := {"rate_here": FE.rate_here(f), "rate_away": FE.rate_away(f, FE.typical_absence_s(f, tnow)),
			"farm_power": FE.farm_power(f), "income_rate": FE.income_rate(f, tnow), "picnic": float(FE.picnic_coins(f, 600.0, 1.0))}
	for r in FE.book(f, tnow, 0):
		for k in ["d_here", "d_away", "payback_s"]:
			nums["book %s %s" % [r["id"], k]] = float(r[k])
	for k in nums:
		if is_nan(nums[k]) or is_inf(nums[k]):
			bad.append("%s = %s" % [k, str(nums[k])])
	for i in 7:
		var c: int = f["fields"][i]["carry"]
		if c < 0 or c >= 1000:
			bad.append("field %d carry %d" % [i, c])
	var inc: Dictionary = b.day_income(ndays)
	var ok := bad.is_empty() and int(f["wallet"]) < 1000000000000000
	say("   wallet %s · lifetime %s · last-day income %s · soil L%d · strains %s · farm_power %s/min  %s" % [
			coins(f["wallet"]), coins(f["stats"]["lifetime_coins"]), coins(inc["coins"]), f["up"]["soil"],
			str(f["up"]["strains"]), coins(int(nums["farm_power"] * 60)), pf(ok)])
	for x in bad.slice(0, 5):
		say("     " + x)
	check(ok, "magnitudes", "; ".join(bad.slice(0, 5)))
	done()

# The §9.2 maxed-v3 landing, built by hand (migrate_v3 is a later phase):
# page 6, 4 fields, Copper, 3 huts, ~290K refund. The full farm must stay at
# least 3 days away for class.
func veteran(ndays: int) -> void:
	section("VETERAN (synthetic §9.2 maxed-v3 landing: page 6, 4 fields, 3 huts, Copper, 290K c)")
	var b = bot("class")
	b.fixture = {"page": 6, "owned": [0, 1, 2, 3], "huts": [0, 1, 2], "tool": 1, "wallet": 290050}
	b.run(ndays)
	var reached: bool = b.milestones.has("full")
	var el: int = int(b.milestones["full"]["t"]) - int(b.t_start) if reached else ndays * DAY
	var ok := el >= 3 * DAY
	say("   full farm after %s%s (>= 3 days)  %s" % [dur(el), "" if reached else "+ (not within the run)", pf(ok)])
	check(ok, "veteran", "full farm after %s" % dur(el))
	done()

# ════════════════════════════════════════════════════════ the CI set

# Exactly what FarmBalanceTest runs (design §10.5): 14 days class/casual, 10
# sessions active, the cheap SD checks plus a reduced SD3 tournament.
const CI_DAYS := {"active": 10, "class": 14, "casual": 14}

static func run_ci_set(s) -> void:
	s.run_main(CI_DAYS)
	s.print_milestones()
	s.feel()
	s.sd_fixtures(ALL4)
	s.sd4(ALL4)
	s.sd3(MAIN, 7)
	s.sd8()
	s.invariants()
	s.bankroll(CI_DAYS)
	s.veteran(14)
	s.magnitudes(60)

# ════════════════════════════════════════════════════════ summary

func print_failures() -> void:
	say("")
	if fails.is_empty():
		say("all checks passed")
		return
	say("FAILURES (%d):" % fails.size())
	for f in fails:
		say("  - " + f)
