extends RefCounted
class_name FarmEconomy

# Spudling Acres economy core (design §5 and §10.2).
#
# Everything here is static and PURE over (farm: Dictionary, now_ms: int,
# tz_s: int): no Time, no nodes, no audio, no saving, no global RNG. Scenes and
# the SaveDataManager heartbeat read the clock from FarmClock and pass it in;
# the farm dict (save schema 4, §9.1) is mutated in place and every action
# returns a result Dictionary:
#   {ok: bool, coins: int (credited), spent: int (paid), msg: String,
#    events: Array, ...action-specific keys}
# so the wallet moved by coins + refund - spent. Achievements, SFX and banners
# are the caller's job: it reacts to `events` ({"type": "page", "page": 3},
# {"type": "hut_hired", ...}).
#
# Other scripts are referenced only through preload() consts: autoloads load
# this file at runtime before Godot's global class list exists on a fresh
# checkout (see commit 3000e3d), so no class_name identifier may appear here.
#
# Units: every time is integer unix milliseconds (*_ms), coins are integers,
# fractional coins live in each field's integer milli-coin `carry`. Rates
# (rate_here, rate_away, farm_power, book d_here/d_away) are coins per SECOND
# as floats; multiply by 60 for the "/min" the HUD shows.

const Fmt = preload("res://scripts/utils/NumFmt.gd")

const CFG_PATH := "res://resources/game_data/farm.json"
const SCHEMA := 4
const FIELDS := 7                 # six fields + the Greenhouse
const GREENHOUSE := 6
const FREE_CROP := "russet"       # seed 0: the no-deadlock fallback
const MASK32 := 0xFFFFFFFF
const HOUR_MS := 3600000
const DAY_MS := 86400000
const FAV_DEFAULT := [["yukon_gold", "purple", "king_edward"], ["red", "fingerling", "golden"]]
const ROMAN := ["", "I", "II", "III", "IV"]
const TAB := {"deed": "land", "greenhouse": "land", "sprinkler": "land",
		"hut": "helpers", "share": "helpers", "quick": "helpers", "house": "helpers",
		"tool": "tools", "soil": "soil", "strain": "soil"}

static var _cfg: Dictionary = {}
static var _k: Dictionary = {}        # derived constants, ms ints and floats
static var _crop: Dictionary = {}     # id -> {id, name, color, grow_ms, seed, sell, strain_at, page}
static var _order: Array = []         # crop ids in table order
static var _dfarm: Dictionary = {}    # new_farm() template for normalize()

# ════════════════════════════════════════════════════════════ config

static func cfg() -> Dictionary:
	if _cfg.is_empty():
		reload_cfg()
	return _cfg

# Re-read farm.json, deep-merging `override` on top (the balance test tunes
# knobs this way without touching the file).
static func reload_cfg(override: Dictionary = {}) -> void:
	var d = null
	var f := FileAccess.open(CFG_PATH, FileAccess.READ)
	if f:
		d = JSON.parse_string(f.get_as_text())
		f.close()
	if not d is Dictionary:
		push_error("FarmEconomy: cannot read " + CFG_PATH)
		d = {}
	_merge_into(d, override)
	_cfg = d
	_index()

static func _kk() -> Dictionary:
	if _k.is_empty():
		reload_cfg()
	return _k

static func _merge_into(dst: Dictionary, src: Dictionary) -> void:
	for key in src:
		if dst.get(key) is Dictionary and src[key] is Dictionary:
			_merge_into(dst[key], src[key])
		else:
			dst[key] = src[key].duplicate(true) if (src[key] is Dictionary or src[key] is Array) else src[key]

static func _index() -> void:
	_crop = {}
	_order = []
	for c in _cfg.get("crops", []):
		var id := str(c["id"])
		_order.append(id)
		var th: Array = []
		for x in c.get("strain_at", []):
			th.append(int(x))
		_crop[id] = {"id": id, "name": str(c.get("name", id)), "color": str(c.get("color", "#ffffff")),
				"grow_ms": int(round(float(c["grow_s"]) * 1000.0)), "seed": int(c["seed"]),
				"sell": int(c["sell"]), "strain_at": th, "page": 0, "rare": bool(c.get("rare", false))}
	var cat: Array = _cfg.get("catalog", [])
	for p in cat.size():
		var u := str(cat[p].get("unlocks", ""))
		if _crop.has(u):
			_crop[u]["page"] = p + 1
	var ck: Dictionary = _cfg["clock"]
	var fences := {}
	for s in _cfg["fields"]["fences"]:
		var pair: Array = _cfg["fields"]["fences"][s]
		fences[s] = [int(pair[0]), int(pair[1])]
	var walk: Array = []
	for w in _cfg["quick"]["walk_s"]:
		walk.append(int(w) * 1000)
	var shift: Array = []
	for h in _cfg["house"]["shift_h"]:
		shift.append(int(round(float(h) * 3600000.0)))
	var share: Array = []
	for s in _cfg["share"]:
		share.append(float(s[0]))
	var b: Dictionary = _cfg["butterflies"]
	# Market Favorite day lists: [even days, odd days]. They must be disjoint
	# (no repeat on consecutive days) and never hold the free crop; a missing
	# or empty list falls back to the lead-decision defaults.
	var fav_days: Array = []
	for key in ["even", "odd"]:
		var lst: Array = []
		for c in _cfg["favorite"].get(key, []):
			if _crop.has(str(c)) and str(c) != FREE_CROP and not str(c) in lst:
				lst.append(str(c))
		fav_days.append(lst if not lst.is_empty() else FAV_DEFAULT[fav_days.size()].duplicate())
	_k = {
		"clockin_ms": int(ck["clockin_s"]) * 1000,
		"grace_ms": int(ck.get("your_crop_grace_s", 0)) * 1000,
		"report_min_ms": int(ck["report_min_s"]) * 1000,
		"welcome_min_ms": int(ck["welcome_butterfly_min_s"]) * 1000,
		"reaction_ms": int(ck["reaction_s"]) * 1000,
		"rollback_ms": int(ck.get("rollback_tolerance_s", 60)) * 1000,
		"plots": int(_cfg["plots"]["per_field"]),
		"field_count": int(_cfg["fields"]["count"]),
		"fences": fences,
		"walk_ms": walk, "shift_ms": shift, "share": share,
		"wallet_cap": int(_cfg["wallet_cap"]),
		"fav_mult": float(_cfg["favorite"]["mult"]), "fav_salt": int(_cfg["favorite"]["salt"]) & MASK32,
		"fav_days": fav_days,
		"soil_base": float(_cfg["soil"]["base"]), "soil_growth": float(_cfg["soil"]["growth"]),
		"soil_mult": float(_cfg["soil"]["mult"]), "strain_mult": float(_cfg["strains"]["mult"]),
		"spr_mult": float(_cfg["sprinklers"]["grow_mult"]), "gh_mult": float(_cfg["greenhouse"]["grow_mult"]),
		"silver_mult": float(_cfg["stars"]["silver_mult"]), "gold_mult": float(_cfg["stars"]["gold_mult"]),
		"life_ms": int(b["life_s"]) * 1000,
		"start_plan": str(_cfg["start"]["plan"]),
	}
	_dfarm = {}
	_dfarm = new_farm()

# Ordered crop ids and per-crop info (grow_ms, seed, sell, name, color, page).
static func crops() -> Array:
	_kk()
	return _order.duplicate()

static func crop_info(id: String) -> Dictionary:
	_kk()
	return _crop.get(id, {})

# ════════════════════════════════════════════════════════════ save dict

# Schema-4 defaults (§9.1). Field 1 owned and empty with plan Russet; the
# clock epoch 0 means "not started" so start() runs on the first visit.
# Beyond §9.1: field.hut_k (hire index -> Spudling name), up.sprinklers
# (owned count; placed ones are `sprinklers`), extra stats, buffs.welcome /
# butterfly_field, presence entries hold milliseconds, mix (per-crop harvest
# milli-coins of the current and previous UTC day; prices Prize Strain rows).
static func new_farm() -> Dictionary:
	var k := _kk()
	var fields: Array = []
	for i in FIELDS:
		fields.append(_new_field(i == 0))
	var buckets: Array = []
	buckets.resize(24)
	buckets.fill(0)
	return {
		"schema": SCHEMA,
		"wallet": int(_cfg["start"]["wallet_if_new"]),
		"owned_knives": ["butter"], "equipped_knife": "butter",
		"clock": {"epoch_ms": 0, "last_settle_ms": 0, "last_input_ms": 0, "tz_s": 0},
		"g_offset_ms": 0,
		"fields": fields,
		"sprinklers": [],
		"up": {"tool": 0, "share": 0, "quick": 0, "house": 0, "soil": 0, "huts": 0, "sprinklers": 0, "strains": {}},
		"unlocked": [FREE_CROP], "page": 0,
		"shipped": {},
		"stats": {"lifetime_coins": 0, "hand_picks": 0, "spud_picks": 0, "butterflies": 0, "stars": 0,
				"hand_coins": 0, "spud_coins": 0, "penny_coins": 0},
		"income": {"hour0": 0, "buckets": buckets},
		"mix": {"day": 0, "cur": {}, "prev": {}},
		"absences": [], "presence": [],
		"buffs": {"bumper_until_ms": 0, "next_butterfly_ms": 0, "butterfly_field": 0, "welcome": false},
		"report": {},
		"goal": {"tutorial": 0, "pinned": ""},
		"rng": {"s": 0},
		"ui": {"zoom": float(_cfg["start"].get("zoom", 0.45))},
		"migration": {},
	}

# grow_eff_ms: the standing crop's effective grow time, locked at planting
# (like fav), so a sprinkler placed, moved or removed later changes the next
# planting only: a growing crop never jumps to ripe and a ripe one never
# un-ripens. 0 when empty.
static func _new_field(owned: bool) -> Dictionary:
	return {"owned": owned, "plan": str(_k.get("start_plan", FREE_CROP)), "crop": "", "planted_g": 0,
			"grow_eff_ms": 0, "by": "you", "seed_paid": 0, "fav": false, "hut": false, "hut_k": -1, "carry": 0}

# Deep-fill missing keys from the schema-4 defaults and int()-cast every
# integer (Godot's JSON parser returns all numbers as floats). Idempotent.
static func normalize(farm: Dictionary) -> void:
	var k := _kk()
	_fill(farm, _dfarm)
	farm["schema"] = int(farm["schema"])
	farm["wallet"] = mini(int(farm["wallet"]), k.wallet_cap)
	farm["g_offset_ms"] = int(farm["g_offset_ms"])
	_ints(farm["clock"], ["epoch_ms", "last_settle_ms", "last_input_ms", "tz_s"])
	# fields: exactly 7 dicts
	var fields: Array = farm["fields"]
	while fields.size() < FIELDS:
		fields.append(_new_field(fields.is_empty()))
	if fields.size() > FIELDS:
		fields.resize(FIELDS)
	for i in FIELDS:
		if not fields[i] is Dictionary:
			fields[i] = _new_field(i == 0)
		var f: Dictionary = fields[i]
		_fill(f, _dfarm["fields"][i])
		f["owned"] = bool(f["owned"])
		f["hut"] = bool(f["hut"])
		f["fav"] = bool(f["fav"])
		f["plan"] = str(f["plan"]) if _crop.has(str(f["plan"])) else k.start_plan
		f["crop"] = str(f["crop"]) if _crop.has(str(f["crop"])) else ""
		f["by"] = "spud" if str(f["by"]) == "spud" else "you"
		_ints(f, ["planted_g", "grow_eff_ms", "seed_paid", "carry", "hut_k"])
	# upgrades, clamped to their ladders
	var up: Dictionary = farm["up"]
	_ints(up, ["tool", "share", "quick", "house", "soil", "huts", "sprinklers"])
	up["tool"] = clampi(up["tool"], 0, _cfg["tools"].size() - 1)
	up["share"] = clampi(up["share"], 0, k.share.size() - 1)
	up["quick"] = clampi(up["quick"], 0, k.walk_ms.size() - 1)
	up["house"] = clampi(up["house"], 0, k.shift_ms.size() - 1)
	up["huts"] = clampi(up["huts"], 0, _cfg["huts"]["costs"].size())
	up["soil"] = maxi(0, up["soil"])
	for c in up["strains"].keys():
		up["strains"][c] = clampi(int(up["strains"][c]), 0, 4)
	# placed sprinklers: known, distinct sockets; owned count covers them
	var placed: Array = []
	for s in farm["sprinklers"]:
		if k.fences.has(str(s)) and not str(s) in placed:
			placed.append(str(s))
	farm["sprinklers"] = placed
	up["sprinklers"] = clampi(maxi(up["sprinklers"], placed.size()), 0, _cfg["sprinklers"]["costs"].size())
	# A standing crop without a locked grow time (a hand-built dict) takes the
	# field's current watering; an empty field holds 0.
	for i in FIELDS:
		var f: Dictionary = fields[i]
		if f["crop"] == "":
			f["grow_eff_ms"] = 0
		elif int(f["grow_eff_ms"]) <= 0:
			f["grow_eff_ms"] = grow_eff_ms(farm, f["crop"], i)
	# catalog: page clamped, every crop up to it unlocked
	var cat: Array = _cfg["catalog"]
	farm["page"] = clampi(int(farm["page"]), 0, cat.size())
	var unl: Array = []
	for c in farm["unlocked"]:
		if _crop.has(str(c)) and not str(c) in unl:
			unl.append(str(c))
	if not FREE_CROP in unl:
		unl.push_front(FREE_CROP)
	for p in farm["page"]:
		var u := str(cat[p]["unlocks"])
		if not u in unl:
			unl.append(u)
	farm["unlocked"] = unl
	for c in farm["shipped"].keys():
		farm["shipped"][c] = int(farm["shipped"][c])
	_ints(farm["stats"], farm["stats"].keys())
	var inc: Dictionary = farm["income"]
	inc["hour0"] = int(inc["hour0"])
	var bk: Array = inc["buckets"]
	bk.resize(24)
	for h in 24:
		bk[h] = int(bk[h]) if bk[h] != null else 0
	var mix: Dictionary = farm["mix"]
	mix["day"] = int(mix["day"])
	for key in ["cur", "prev"]:
		var m: Dictionary = mix[key]
		for c in m.keys():
			var e = m[c]
			if _crop.has(str(c)) and e is Array and e.size() == 2:
				m[c] = [int(e[0]), int(e[1])]
			else:
				m.erase(c)
	farm["absences"] = _int_pairs(farm["absences"])
	farm["presence"] = _int_pairs(farm["presence"])
	var bf: Dictionary = farm["buffs"]
	_ints(bf, ["bumper_until_ms", "next_butterfly_ms", "butterfly_field"])
	bf["welcome"] = bool(bf["welcome"])
	var rep: Dictionary = farm["report"]
	if not rep.is_empty():
		_fill(rep, _empty_report())
		_ints(rep, ["from_ms", "to_ms", "away_ms", "coins", "baskets", "worked_ms", "nap_ms", "nap_from_ms"])
		for c in rep["picks"].keys():
			rep["picks"][c] = int(rep["picks"][c])
		var pg: Array = []
		for p in rep["pages"]:
			pg.append(int(p))
		rep["pages"] = pg
	farm["goal"]["tutorial"] = int(farm["goal"]["tutorial"])
	farm["goal"]["pinned"] = str(farm["goal"]["pinned"])
	farm["rng"]["s"] = int(farm["rng"]["s"]) & MASK32
	farm["ui"]["zoom"] = float(farm["ui"]["zoom"])

# Cheap guard at the top of every public entry: a dict that already looks
# normalized (int wallet and stamps, 7 fields: never true straight out of
# JSON, whose numbers are all floats) skips the full pass. normalize() itself
# always runs the full pass; call it after editing a farm dict by hand.
static func _ensure(farm: Dictionary) -> void:
	if typeof(farm.get("wallet")) == TYPE_INT and typeof(farm.get("g_offset_ms")) == TYPE_INT \
			and farm.get("schema") is int and farm["schema"] == SCHEMA and farm.has("migration") \
			and farm.has("mix"):
		var fl = farm.get("fields")
		var ck = farm.get("clock")
		if fl is Array and fl.size() == FIELDS and ck is Dictionary \
				and typeof(ck.get("last_settle_ms")) == TYPE_INT and typeof(ck.get("last_input_ms")) == TYPE_INT \
				and fl[0] is Dictionary and typeof(fl[0].get("planted_g")) == TYPE_INT \
				and fl[6] is Dictionary and typeof(fl[6].get("carry")) == TYPE_INT:
			_kk()
			return
	normalize(farm)

static func _fill(dst: Dictionary, src: Dictionary) -> void:
	for key in src:
		var dv = src[key]
		var have = dst.get(key)
		var numeric: bool = (typeof(have) == TYPE_INT or typeof(have) == TYPE_FLOAT) \
				and (typeof(dv) == TYPE_INT or typeof(dv) == TYPE_FLOAT)
		if not dst.has(key) or (typeof(have) != typeof(dv) and not numeric):
			dst[key] = dv.duplicate(true) if (dv is Dictionary or dv is Array) else dv
		elif dv is Dictionary and not dv.is_empty():
			_fill(have, dv)

static func _ints(d: Dictionary, keys: Array) -> void:
	for key in keys:
		var v = d.get(key, 0)
		d[key] = int(v) if (typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT or typeof(v) == TYPE_BOOL) else 0

static func _int_pairs(a) -> Array:
	var out: Array = []
	if a is Array:
		for e in a:
			if e is Array and e.size() >= 2:
				out.append([int(e[0]), int(e[1])])
	return out

# worked_ms and nap_ms are durations summed over the absences since the last
# note; nap_from_ms is the instant the latest shift ended (0 if none did).
static func _empty_report() -> Dictionary:
	return {"from_ms": 0, "to_ms": 0, "away_ms": 0, "coins": 0, "baskets": 0, "picks": {}, "worked_ms": 0,
			"nap_ms": 0, "nap_from_ms": 0, "pages": []}

# First farm visit: stamp the clock, seed the rng, schedule the first
# butterfly. Field 1 stays empty (tutorial goal 1 is to plant it). No-op once
# started.
static func start(farm: Dictionary, now_ms: int, tz_s: int) -> void:
	normalize(farm)
	var clock: Dictionary = farm["clock"]
	if clock["epoch_ms"] != 0:
		return
	var t := maxi(1, now_ms)
	clock["epoch_ms"] = t
	clock["last_settle_ms"] = t
	clock["last_input_ms"] = t
	clock["tz_s"] = tz_s
	var s := (t ^ (t >> 32) ^ 0x9E3779B9) & MASK32
	farm["rng"]["s"] = xorshift32(s)
	farm["income"]["hour0"] = _fdiv(t, HOUR_MS)
	farm["income"]["buckets"].fill(0)
	_schedule_butterfly(farm, t)

# ════════════════════════════════════════════════════════════ clocks

# Local calendar day: floor((t/1000 + tz_s) / 86400).
static func day_index(now_ms: int, tz_s: int) -> int:
	return _fdiv(now_ms + tz_s * 1000, DAY_MS)

static func _day_start(day: int, tz_s: int) -> int:
	return day * DAY_MS - tz_s * 1000

# Growth clock G(t) = t + g_offset_ms (moved only by Sunshower and rollback).
static func g_now(farm: Dictionary, now_ms: int) -> int:
	return now_ms + int(farm["g_offset_ms"])

static func is_present(farm: Dictionary, now_ms: int) -> bool:
	return now_ms - int(farm["clock"]["last_input_ms"]) < _kk().clockin_ms

static func _fdiv(a: int, b: int) -> int:    # floor division, b > 0
	return (a - posmod(a, b)) / b

static func _cdiv(a: int, b: int) -> int:    # ceiling division, b > 0
	return -_fdiv(-a, b)

static func _hour(t: int) -> int:
	return _fdiv(t, HOUR_MS)

# ════════════════════════════════════════════════════════════ rng + favorite

static func xorshift32(x: int) -> int:
	x &= MASK32
	x ^= (x << 13) & MASK32
	x ^= x >> 17
	x ^= (x << 5) & MASK32
	x &= MASK32
	if x == 0:
		x = 1
	return x

# The farm's own rng (farm.rng.s): uniform float in [0, 1).
static func _rand(farm: Dictionary) -> float:
	var r: Dictionary = farm["rng"]
	var s := xorshift32(int(r["s"]))
	r["s"] = s
	return float(s) / 4294967296.0

static func _rand_int(farm: Dictionary, lo: int, hi: int) -> int:   # inclusive
	return lo + mini(hi - lo, int(_rand(farm) * float(hi - lo + 1)))

# Today's Market Favorite (lead decision 2, replacing the §5.8 base/shift
# hash), stateless: even local days pick from farm.json favorite.even
# [yukon_gold, purple, king_edward], odd days from favorite.odd [red,
# fingerling, golden], index xorshift32(((d * 2654435761) & 0xFFFFFFFF) ^
# salt) % 3. The two lists are disjoint, so consecutive days never share a
# Favorite; Russet is in neither.
static func favorite(day: int) -> String:
	var tri: Array = _kk().fav_days[posmod(day, 2)]
	var x := ((day * 2654435761) & MASK32) ^ int(_k.fav_salt)
	return tri[xorshift32(x) % tri.size()]

static func _is_fav(crop: String, t: int, tz: int) -> bool:
	return crop != FREE_CROP and favorite(day_index(t, tz)) == crop

# ════════════════════════════════════════════════════════════ field math

static func _walk_ms(farm: Dictionary) -> int:
	return _kk().walk_ms[clampi(int(farm["up"]["quick"]), 0, _k.walk_ms.size() - 1)]

static func _shift_ms(farm: Dictionary) -> int:
	return _kk().shift_ms[clampi(int(farm["up"]["house"]), 0, _k.shift_ms.size() - 1)]

static func _share(farm: Dictionary) -> float:
	return _kk().share[clampi(int(farm["up"]["share"]), 0, _k.share.size() - 1)]

# Star odds of the current hoe: {silver, gold, ev}. EV 1.25 / 1.325 / 1.40.
static func star_odds(farm: Dictionary) -> Dictionary:
	var k := _kk()
	var t: Dictionary = _cfg["tools"][clampi(int(farm["up"]["tool"]), 0, _cfg["tools"].size() - 1)]
	var sv := float(t["silver"])
	var gd := float(t["gold"])
	return {"silver": sv, "gold": gd, "ev": 1.0 + sv * (k.silver_mult - 1.0) + gd * (k.gold_mult - 1.0)}

static func _star_ev(farm: Dictionary) -> float:
	var k := _kk()
	var t: Dictionary = _cfg["tools"][clampi(int(farm["up"]["tool"]), 0, _cfg["tools"].size() - 1)]
	return 1.0 + float(t["silver"]) * (k.silver_mult - 1.0) + float(t["gold"]) * (k.gold_mult - 1.0)

# Value multiplier of a crop: soil_mult^soil × strain_mult^strain.
static func _mult(farm: Dictionary, crop: String) -> float:
	var k := _kk()
	return pow(k.soil_mult, int(farm["up"]["soil"])) * pow(k.strain_mult, int(farm["up"]["strains"].get(crop, 0)))

# Integer milli-coins one plot of `crop` sells for (before stars/Bumper).
static func _tile_milli(farm: Dictionary, crop: String, fav: bool) -> int:
	var v := float(_crop[crop]["sell"]) * 1000.0 * _mult(farm, crop)
	if fav:
		v *= _kk().fav_mult
	return int(round(v))

static func _watered(farm: Dictionary, i: int) -> bool:
	if i == GREENHOUSE:
		return true
	var fences: Dictionary = _kk().fences
	for s in farm["sprinklers"]:
		if fences.has(s) and i in fences[s]:
			return true
	return false

# Effective grow time: ×0.5333 in the Greenhouse, ×0.8 on a watered field.
static func grow_eff_ms(farm: Dictionary, crop: String, i: int) -> int:
	var g: int = _crop[crop]["grow_ms"]
	if i == GREENHOUSE:
		return int(round(g * _kk().gh_mult))
	if _watered(farm, i):
		return int(round(g * _kk().spr_mult))
	return g

# The standing crop's grow time, locked when it was planted (falls back to the
# current watering for a hand-built dict that never went through normalize()).
static func _ge_of(farm: Dictionary, i: int) -> int:
	var f: Dictionary = farm["fields"][i]
	var ge := int(f.get("grow_eff_ms", 0))
	return ge if ge > 0 else grow_eff_ms(farm, f["crop"], i)

static func _ripe(farm: Dictionary, i: int, now: int) -> bool:
	var f: Dictionary = farm["fields"][i]
	return f["crop"] != "" and g_now(farm, now) - int(f["planted_g"]) >= _ge_of(farm, i)

# Wall-clock instant the current crop ripens (0 when empty).
static func _ready_at(farm: Dictionary, i: int) -> int:
	var f: Dictionary = farm["fields"][i]
	if f["crop"] == "":
		return 0
	return int(f["planted_g"]) + _ge_of(farm, i) - int(farm["g_offset_ms"])

static func _valid_field(i) -> bool:
	return typeof(i) == TYPE_INT and i >= 0 and i < FIELDS

static func _field_name(i: int) -> String:
	return str(_cfg["fields"]["names"][i])

static func _owned_count(farm: Dictionary, include_gh := false) -> int:
	var n := 0
	for i in (FIELDS if include_gh else _kk().field_count):
		if farm["fields"][i]["owned"]:
			n += 1
	return n

# ════════════════════════════════════════════════════════════ wallet + income

static func _add_wallet(farm: Dictionary, coins: int) -> void:
	farm["wallet"] = mini(_kk().wallet_cap, int(farm["wallet"]) + coins)

# Credit milli-coins through a field's carry; returns whole coins paid.
static func _credit_field(farm: Dictionary, f: Dictionary, milli: int) -> int:
	var tot := int(f["carry"]) + milli
	var coins := tot / 1000
	f["carry"] = tot - coins * 1000
	_add_wallet(farm, coins)
	var st: Dictionary = farm["stats"]
	st["lifetime_coins"] = int(st["lifetime_coins"]) + coins
	return coins

# Rolling 24 h of farm income in milli-coins, one bucket per absolute hour.
# Spudling picks land in the hour they happened, so one bulk settle and many
# small ones fill identical buckets.
static func _income_add(farm: Dictionary, hour: int, milli: int) -> void:
	var inc: Dictionary = farm["income"]
	if hour > int(inc["hour0"]):
		_income_advance(farm, hour)
	if hour <= int(inc["hour0"]) - 24:
		return
	var bk: Array = inc["buckets"]
	bk[posmod(hour, 24)] = int(bk[posmod(hour, 24)]) + milli

static func _income_advance(farm: Dictionary, hour: int) -> void:
	var inc: Dictionary = farm["income"]
	var h0 := int(inc["hour0"])
	if hour <= h0:
		return
	var bk: Array = inc["buckets"]
	if hour - h0 >= 24:
		bk.fill(0)
	else:
		for h in range(h0 + 1, hour + 1):
			bk[posmod(h, 24)] = 0
	inc["hour0"] = hour

# Harvest mix (prices the Prize Strain rows, design §3 D10 "worth 0.5 x f_c"):
# milli-coins per crop of the current and the previous UTC day, split into
# crops you planted and crops the Spudlings planted ([you, spud]), because a
# Strain multiplies the two differently. Like the income buckets, every pick
# lands on the day it happened, so bulk and stepped settles agree.
static func _mix_add(farm: Dictionary, t: int, crop: String, milli: int, spud: bool) -> void:
	var mix: Dictionary = farm["mix"]
	var d := _fdiv(t, DAY_MS)
	var d0 := int(mix["day"])
	if d > d0:
		mix["prev"] = mix["cur"] if d == d0 + 1 else {}
		mix["cur"] = {}
		mix["day"] = d
		d0 = d
	var m: Dictionary
	if d == d0:
		m = mix["cur"]
	elif d == d0 - 1:
		m = mix["prev"]
	else:
		return
	var e: Array = m.get(crop, [0, 0])
	e[1 if spud else 0] = int(e[1 if spud else 0]) + milli
	m[crop] = e

# Per-crop harvest income over today and yesterday (UTC), coins per second,
# as {crop: [you, spud]}.
static func _mix_rates(farm: Dictionary, now_ms: int) -> Dictionary:
	var mix: Dictionary = farm["mix"]
	var dn := _fdiv(now_ms, DAY_MS)
	var d0 := int(mix["day"])
	var maps: Array = []
	if d0 == dn:
		maps = [mix["cur"], mix["prev"]]
	elif d0 == dn - 1:
		maps = [mix["cur"]]
	var span := float(maxi(HOUR_MS, now_ms - maxi(int(farm["clock"]["epoch_ms"]), (dn - 1) * DAY_MS)))
	var out := {}
	for m in maps:
		for c in m:
			var e: Array = out.get(c, [0.0, 0.0])
			e[0] += float(m[c][0]) / span
			e[1] += float(m[c][1]) / span
			out[c] = e
	return out

# Farm coins per second over the last 24 h (0 before any income).
static func income_rate(farm: Dictionary, now_ms: int) -> float:
	var inc: Dictionary = farm["income"]
	var h0 := int(inc["hour0"])
	var hn := _hour(now_ms)
	var sum := 0
	for h in range(hn - 23, hn + 1):
		if h <= h0 and h > h0 - 24:
			sum += int(inc["buckets"][posmod(h, 24)])
	var elapsed := clampi(now_ms - int(farm["clock"]["epoch_ms"]), 60000, DAY_MS)
	return float(sum) / float(elapsed)     # milli per ms == coins per second

# ════════════════════════════════════════════════════════════ settle

# Advance the farm to now_ms: Spudling picks in closed form, rollback rebase,
# catalog pages, report accumulation, income buckets. Idempotent for the same
# now; one settle over a long span equals many small ones (§5.12.2).
# Returns {ok, coins (Spudling coins credited), picks, pages, rebased, events}.
static func settle(farm: Dictionary, now_ms: int, tz_s: int) -> Dictionary:
	_ensure(farm)
	return _settle(farm, now_ms, tz_s)

static func _settle(farm: Dictionary, now: int, tz: int) -> Dictionary:
	var res := _result()
	res["picks"] = 0
	res["pages"] = []
	res["rebased"] = false
	var clock: Dictionary = farm["clock"]
	if clock["epoch_ms"] == 0:
		return res
	clock["tz_s"] = tz
	var k := _kk()
	var last: int = clock["last_settle_ms"]
	if now < last - k.rollback_ms:
		_rebase(farm, now, last - now)
		res["rebased"] = true
		res["events"].append({"type": "rebased", "by_ms": last - now})
		return res
	if now <= last:
		return res
	# The current absence's work window: Spudlings clock in 120 s after the
	# last input and work one shift. Nothing happens while you're present.
	var l_in: int = clock["last_input_ms"]
	var w0: int = l_in + k.clockin_ms
	var w1: int = w0 + _shift_ms(farm)
	var huts: Array = []
	for i in FIELDS:
		if farm["fields"][i]["owned"] and farm["fields"][i]["hut"]:
			huts.append(i)
	var hi := mini(now, w1)
	if hi > w0:
		for i in huts:
			_settle_hut(farm, i, l_in, w0, hi, tz, res)
	if now >= w0:
		var rep := _report(farm)
		if rep["from_ms"] == 0:
			rep["from_ms"] = l_in
		rep["to_ms"] = now
		if not huts.is_empty():
			# Durations, additive over settle spans (bulk == stepped).
			rep["worked_ms"] += maxi(0, mini(now, w1) - maxi(last, w0))
			if now > w1:
				rep["nap_ms"] += now - maxi(last, w1)
				rep["nap_from_ms"] = w1
	clock["last_settle_ms"] = now
	_income_advance(farm, _hour(now))
	var pages := _check_pages(farm, res["events"])
	if not pages.is_empty():
		var rp: Array = _report(farm)["pages"]
		rp.append_array(pages)
	res["pages"] = pages
	_advance_tutorial(farm, res["events"])
	return res

# The clock went backwards (more than the tolerance): credit nothing and shift
# the whole farm back with it (§5.1): the growth clock, so crops neither
# un-grow nor jump, and the last input stamp, so the absence keeps the shift it
# had left. (§5.1 says last_input = min(last_input, now); that leaves the work
# window where it was in wall time, and a clock set back and then restored
# would let Spudlings re-work the hours already worked. last_input <=
# last_settle, so the shifted stamp is still <= now.)
static func _rebase(farm: Dictionary, now: int, back: int) -> void:
	var clock: Dictionary = farm["clock"]
	farm["g_offset_ms"] = int(farm["g_offset_ms"]) + back
	clock["last_settle_ms"] = now
	clock["last_input_ms"] = mini(int(clock["last_input_ms"]) - back, now)
	var bf: Dictionary = farm["buffs"]
	for key in ["bumper_until_ms", "next_butterfly_ms"]:
		if int(bf[key]) > 0:
			bf[key] = maxi(1, int(bf[key]) - back)

# One hut field over the work window up to `hi` (§5.6). Closed form:
#   pick 1 at p1 = max(ripe_wall [+ grace], w0) + P harvests the stored crop
#   and replants the plan for free; every later pick k comes one cycle
#   c = grow_eff(plan) + P after the previous one, so n = 1 + floor((hi - p1)
#   / c). A replant carries the Favorite flag of its own local day, so picks
#   are summed per hour bucket and the Favorite plantings counted per local
#   day by floor division.
# Wages (pick 1 is the crop standing when the window opened): a crop that was
# already in the ground when this absence began (wall planting time <= l_in,
# the last input), whoever planted it, is picked as carefully as you would:
# full value × your hoe's star EV, no Bumper (A3 rule, with the star average:
# at 1.0 × gross, Pip picking your Golden two hours before a casual check-in
# cost the star bonus, SD4 -7%; a Spudling crop that grew through your visit
# counts as yours). Only a crop the Spudlings planted during this absence
# pays the share.
# Grace (phase B): such a crop also waits min(clock.your_crop_grace_s, its
# grow time) past ripe before the Spudlings pick it, so a check-in player's
# Red is still there at the next bell (hand-led by day) while a long absence
# loses at most the grace. It depends only on the stored field and l_in, so
# bulk == stepped still holds.
static func _settle_hut(farm: Dictionary, i: int, l_in: int, w0: int, hi: int, tz: int, res: Dictionary) -> void:
	var f: Dictionary = farm["fields"][i]
	var plan: String = f["plan"]
	var goff := int(farm["g_offset_ms"])
	var walk := _walk_ms(farm)
	var ge_plan := grow_eff_ms(farm, plan, i)
	if f["crop"] == "":
		# An empty hut field is planted at w0 + P (no harvest value).
		var tp := w0 + walk
		if tp > hi:
			return
		_spud_plant(f, plan, tp, goff, tz, ge_plan)
	var crop1: String = f["crop"]
	var ge1 := _ge_of(farm, i)
	var ripe_wall := int(f["planted_g"]) + ge1 - goff
	# A crop that was in the ground when you left is yours: it waits for you
	# for a grace of min(clock.your_crop_grace_s, its grow time) after it
	# ripens (a check-in player comes back and picks it with stars), and then
	# the Spudlings pick it at full value × your star EV. Only a crop they
	# planted during this absence pays the share (and has no grace).
	var full1: bool = f["by"] == "you" or int(f["planted_g"]) - goff <= l_in
	if full1:
		ripe_wall += mini(_kk().grace_ms, ge1)
	var p1 := maxi(ripe_wall, w0) + walk
	if p1 > hi:
		return
	var cyc := ge_plan + walk
	var n := 1 + (hi - p1) / cyc                 # hi >= p1, so no negative division
	var share := _share(farm)
	var ev := _star_ev(farm)
	var plots: int = _kk().plots
	var spud1: bool = f["by"] == "spud"
	var w1v := ev if full1 else share
	var v1 := int(round(float(_tile_milli(farm, crop1, f["fav"]) * plots) * w1v))
	_income_add(farm, _hour(p1), v1)
	_mix_add(farm, p1, crop1, v1, spud1)
	var total := v1
	if n >= 2:
		var pm_plain := int(round(float(_tile_milli(farm, plan, false) * plots) * share))
		var pm_fav := int(round(float(_tile_milli(farm, plan, true) * plots) * share))
		# Picks k = 2..n at p1 + (k-1)c, walked one hour bucket at a time; pick k
		# harvests planting j = k-1 (made at p1 + (j-1)c).
		var kk := 2
		while kk <= n:
			var h := _hour(p1 + (kk - 1) * cyc)
			var k_end := mini(n, _cdiv((h + 1) * HOUR_MS - p1, cyc))
			var cnt := k_end - kk + 1
			var nf := _count_fav(plan, p1, cyc, kk - 1, k_end - 1, tz)
			var m := (cnt - nf) * pm_plain + nf * pm_fav
			_income_add(farm, h, m)
			_mix_add(farm, h * HOUR_MS, plan, m, true)
			total += m
			kk = k_end + 1
	var pn := p1 + (n - 1) * cyc
	_spud_plant(f, plan, pn, goff, tz, ge_plan)
	var coins := _credit_field(farm, f, total)
	var shipped: Dictionary = farm["shipped"]
	shipped[crop1] = int(shipped.get(crop1, 0)) + plots
	if n >= 2:
		shipped[plan] = int(shipped.get(plan, 0)) + plots * (n - 1)
	var st: Dictionary = farm["stats"]
	st["spud_picks"] = int(st["spud_picks"]) + n
	st["spud_coins"] = int(st["spud_coins"]) + coins
	var rep := _report(farm)
	var picks: Dictionary = rep["picks"]
	picks[crop1] = int(picks.get(crop1, 0)) + 1
	if n >= 2:
		picks[plan] = int(picks.get(plan, 0)) + n - 1
	rep["baskets"] += n
	rep["coins"] += coins
	res["picks"] += n
	res["coins"] += coins

static func _spud_plant(f: Dictionary, plan: String, t: int, goff: int, tz: int, ge: int) -> void:
	f["crop"] = plan
	f["planted_g"] = t + goff
	f["grow_eff_ms"] = ge
	f["by"] = "spud"
	f["seed_paid"] = 0
	f["fav"] = _is_fav(plan, t, tz)

# Count plantings j in [j_lo, j_hi] (planting j at p1 + (j-1)c) that fall on a
# local day whose Favorite is `plan`: per day d, j-1 runs from
# ceil((start(d) - p1)/c) to ceil((start(d+1) - p1)/c) - 1.
static func _count_fav(plan: String, p1: int, c: int, j_lo: int, j_hi: int, tz: int) -> int:
	if j_hi < j_lo or plan == FREE_CROP:
		return 0
	var d0 := day_index(p1 + (j_lo - 1) * c, tz)
	var d1 := day_index(p1 + (j_hi - 1) * c, tz)
	var n := 0
	for d in range(d0, d1 + 1):
		if favorite(d) != plan:
			continue
		var ds := _day_start(d, tz)
		var a := maxi(j_lo, 1 + _cdiv(ds - p1, c))
		var b := mini(j_hi, _cdiv(ds + DAY_MS - p1, c))
		if b >= a:
			n += b - a + 1
	return n

static func _report(farm: Dictionary) -> Dictionary:
	var r: Dictionary = farm["report"]
	if r.is_empty():
		r.merge(_empty_report())
	return r

# ════════════════════════════════════════════════════════════ input + session log

# A real input in the farm or town: settle with the old stamp first, log the
# absence (>= clock-in) and the present time, then stamp. Returns the settle
# result plus absence_s (0 when this input didn't end an absence).
static func note_input(farm: Dictionary, now_ms: int, tz_s: int) -> Dictionary:
	_ensure(farm)
	return _note_input(farm, now_ms, tz_s)

static func _note_input(farm: Dictionary, now: int, tz: int) -> Dictionary:
	var clock: Dictionary = farm["clock"]
	if clock["epoch_ms"] == 0:
		var r := _result()
		r["absence_s"] = 0
		return r
	var res := _settle(farm, now, tz)
	var k := _kk()
	var last_in: int = clock["last_input_ms"]
	var gap := maxi(0, now - last_in)
	res["absence_s"] = 0
	if gap >= k.clockin_ms:
		# An absence ended before the note was taken: the report keeps summing
		# away time, so its "away" never counts the present time in between.
		if not farm["report"].is_empty():
			farm["report"]["away_ms"] = int(farm["report"]["away_ms"]) + gap
		var ab: Array = farm["absences"]
		ab.append([last_in, gap / 1000])
		while ab.size() > int(_cfg["log"]["absences_max"]):
			ab.pop_front()
		res["absence_s"] = gap / 1000
	# Present time is the gap between two inputs less than the clock-in apart.
	# An absence adds nothing: its first 120 s are the Spudlings' clock-in
	# wait, not play, and counting them tripled a check-in player's 'here'.
	_log_presence(farm, day_index(now, tz), gap if gap < k.clockin_ms else 0)
	if now > last_in:
		clock["last_input_ms"] = now
	# Butterflies are online-only: a stale or missed one is rescheduled from now.
	var nb := int(farm["buffs"]["next_butterfly_ms"])
	if nb == 0 or now >= nb + k.life_ms:
		_schedule_butterfly(farm, now)
	return res

# Present milliseconds per local day, last 7 days ([day, ms] pairs).
static func _log_presence(farm: Dictionary, day: int, add_ms: int) -> void:
	var pres: Array = farm["presence"]
	if add_ms > 0:
		if not pres.is_empty() and pres[-1][0] >= day:
			pres[-1][1] = int(pres[-1][1]) + add_ms
		else:
			pres.append([day, add_ms])
	var keep := int(_cfg["log"]["presence_days"])
	while not pres.is_empty() and (pres[0][0] <= day - keep or pres.size() > keep):
		pres.pop_front()

# Median absence over the last 7 days, in seconds (3 h until 3 are logged).
static func typical_absence_s(farm: Dictionary, now_ms: int) -> int:
	var lens := _recent_absences(farm, now_ms)
	if lens.size() < int(_cfg["log"]["min_absences"]):
		return int(_cfg["log"]["typical_default_s"])
	lens.sort()
	var n := lens.size()
	return lens[n / 2] if n % 2 == 1 else (lens[n / 2 - 1] + lens[n / 2]) / 2

static func _recent_absences(farm: Dictionary, now_ms: int) -> Array:
	_kk()
	var cut := now_ms - 7 * DAY_MS
	var lens: Array = []
	for a in farm["absences"]:
		if int(a[0]) >= cut:
			lens.append(int(a[1]))
	return lens

# The away schedule the Farm Book prices against (lead ruling 2a): the
# absences logged in the last 7 days as [[gap_ms, count], ...], gaps within 3%
# of a cluster's shortest merged into it (the shortest kept, so a crop that
# fits it fits the whole cluster) and at most 8 clusters (closest neighbours
# merged). Fewer than 3 logged: farm.json log.default_schedule. A log younger
# than log.min_history_s (20 h) hasn't seen your night yet, so one night of
# log.assumed_night_s (12 h) is added to it.
static func _schedule(farm: Dictionary, now_ms: int) -> Array:
	var lens := _recent_absences(farm, now_ms)
	var lg: Dictionary = cfg()["log"]
	var out: Array = []
	if lens.size() < int(lg["min_absences"]):
		for e in lg.get("default_schedule", [[lg["typical_default_s"], 1]]):
			out.append([int(e[0]) * 1000, maxi(1, int(e[1]))])
		return out
	if now_ms - int(farm["clock"]["epoch_ms"]) < int(lg.get("min_history_s", 0)) * 1000:
		lens.append(int(lg.get("assumed_night_s", 43200)))
	lens.sort()
	var tol := 1.0 + float(lg.get("cluster_tol", 0.03))
	for g in lens:
		var gm := maxi(1, int(g)) * 1000
		if not out.is_empty() and float(gm) <= float(out[-1][0]) * tol:
			out[-1][1] += 1
		else:
			out.append([gm, 1])
	var kmax := maxi(1, int(lg.get("max_clusters", 8)))
	while out.size() > kmax:
		var at := 0
		var best := INF
		for j in out.size() - 1:
			var r := float(out[j + 1][0]) / float(out[j][0])
			if r < best:
				best = r
				at = j
		out[at][1] += out[at + 1][1]
		out.remove_at(at + 1)
	return out

# Fraction of the last 7 days spent present (0.10 until 3 absences are logged).
static func f_here(farm: Dictionary, now_ms: int) -> float:
	var dflt := float(cfg()["log"]["f_here_default"])
	if _recent_absences(farm, now_ms).size() < int(_cfg["log"]["min_absences"]):
		return dflt
	var today := day_index(now_ms, int(farm["clock"]["tz_s"]))
	var present := 0
	for p in farm["presence"]:
		if int(p[0]) > today - int(_cfg["log"]["presence_days"]):
			present += int(p[1])
	var elapsed := mini(7 * DAY_MS, now_ms - int(farm["clock"]["epoch_ms"]))
	if elapsed <= 0:
		return dflt
	return clampf(float(present) / float(elapsed), 0.0, 1.0)

# ════════════════════════════════════════════════════════════ actions

static func _result() -> Dictionary:
	return {"ok": true, "coins": 0, "spent": 0, "msg": "", "events": []}

static func _fail(res: Dictionary, msg: String) -> Dictionary:
	res["ok"] = false
	res["msg"] = msg
	return res

# A failed action still ran note_input (and may have settled): drop a pin that
# is no longer buyable, as every action does.
static func _failf(farm: Dictionary, res: Dictionary, msg: String) -> Dictionary:
	_check_pin(farm)
	return _fail(res, msg)

# Clear goal.pinned once its row can no longer be bought (bought, maxed, owned).
static func _check_pin(farm: Dictionary) -> void:
	var pin: String = farm["goal"]["pinned"]
	if pin != "":
		var p := _parse_id(pin, null)
		if _cost(farm, p[0], _resolve_arg(farm, p[0], p[1])) < 0:
			farm["goal"]["pinned"] = ""

# Every player action: start the farm if needed, then note the input (which
# settles first). Spudling coins credited on the way in are `spud_coins`.
static func _begin(farm: Dictionary, now: int, tz: int) -> Dictionary:
	if farm["clock"]["epoch_ms"] == 0:
		start(farm, now, tz)
	var s := _note_input(farm, now, tz)
	var res := _result()
	res["events"].append_array(s["events"])
	res["spud_coins"] = s["coins"]
	res["absence_s"] = s.get("absence_s", 0)
	return res

static func _finish(farm: Dictionary, res: Dictionary) -> void:
	_check_pages(farm, res["events"])
	_advance_tutorial(farm, res["events"])
	_check_pin(farm)

# Tend one field (§5.4): ripe -> hand-harvest + plant the plan; empty -> plant
# the plan; growing -> no-op returning ready_at_ms and a prompt.
# Result adds: crop (harvested, "" if none), stars (12 × 0/1/2), planted,
# fields [{field, crop, coins, stars, planted}], ready_at_ms when growing.
static func tend(farm: Dictionary, i: int, now_ms: int, tz_s: int) -> Dictionary:
	_ensure(farm)
	var res := _begin(farm, now_ms, tz_s)
	if not _valid_field(i):
		return _failf(farm, res, "No such field")
	if not farm["fields"][i]["owned"]:
		return _failf(farm, res, "%s is for sale" % _field_name(i))
	res["crop"] = ""
	res["stars"] = []
	res["planted"] = ""
	_tend_field(farm, i, now_ms, tz_s, res)
	if not res["fields"].is_empty():
		var rec: Dictionary = res["fields"][0]
		res["crop"] = rec["crop"]
		res["stars"] = rec["stars"]
		res["planted"] = rec["planted"]
	_finish(farm, res)
	return res

static func _tend_field(farm: Dictionary, i: int, now: int, tz: int, res: Dictionary) -> bool:
	if not res.has("fields"):
		res["fields"] = []
	var f: Dictionary = farm["fields"][i]
	var rec := {"field": i, "crop": "", "coins": 0, "stars": [], "planted": ""}
	if f["crop"] != "":
		if not _ripe(farm, i, now):
			var ready := _ready_at(farm, i)
			res["ok"] = false
			res["ready_at_ms"] = ready
			res["msg"] = "%s · ready at %s (in %s)" % [_crop[f["crop"]]["name"], Fmt.clock(ready, tz),
					Fmt.dur((ready - now) / 1000.0)]
			return false
		_harvest(farm, i, now, rec)
		res["coins"] += rec["coins"]
	rec["planted"] = _plant_plan(farm, i, now, tz, res)
	res["fields"].append(rec)
	return true

# Hand harvest (§5.5): 12 plots, each rolls a star from the farm rng; Bumper
# doubles; coins credited at once; shipped += 12.
static func _harvest(farm: Dictionary, i: int, now: int, rec: Dictionary) -> void:
	var k := _kk()
	var f: Dictionary = farm["fields"][i]
	var crop: String = f["crop"]
	var spud: bool = f["by"] == "spud"
	var tile := _tile_milli(farm, crop, f["fav"])
	var odds := star_odds(farm)
	var stars: Array = []
	var milli := 0
	var starred := 0
	for p in k.plots:
		var r := _rand(farm)
		var s := 2 if r < odds.gold else (1 if r < odds.gold + odds.silver else 0)
		stars.append(s)
		if s > 0:
			starred += 1
		milli += tile if s == 0 else int(round(tile * (k.gold_mult if s == 2 else k.silver_mult)))
	if now < int(farm["buffs"]["bumper_until_ms"]):
		milli *= 2
	_income_add(farm, _hour(now), milli)
	_mix_add(farm, now, crop, milli, spud)
	var coins := _credit_field(farm, f, milli)
	farm["shipped"][crop] = int(farm["shipped"].get(crop, 0)) + k.plots
	var st: Dictionary = farm["stats"]
	st["hand_picks"] = int(st["hand_picks"]) + 1
	st["hand_coins"] = int(st["hand_coins"]) + coins
	st["stars"] = int(st["stars"]) + starred
	f["crop"] = ""
	f["grow_eff_ms"] = 0
	f["seed_paid"] = 0
	rec["crop"] = crop
	rec["coins"] = coins
	rec["stars"] = stars

# Plant the field's plan, paying 12 × seed. A short wallet plants Russet free
# and says so. Returns the crop planted.
static func _plant_plan(farm: Dictionary, i: int, now: int, tz: int, res: Dictionary) -> String:
	var f: Dictionary = farm["fields"][i]
	var plan: String = f["plan"]
	if not plan in farm["unlocked"]:
		plan = FREE_CROP
	var cost: int = _kk().plots * int(_crop[plan]["seed"])
	if int(farm["wallet"]) < cost:
		res["msg"] = "Needs %s c: planted Russet instead (free)" % Fmt.coins(cost)
		res["events"].append({"type": "fallback", "field": i, "crop": plan, "needed": cost})
		plan = FREE_CROP
		cost = 0
	farm["wallet"] = int(farm["wallet"]) - cost
	res["spent"] += cost
	f["crop"] = plan
	f["planted_g"] = g_now(farm, now)
	f["grow_eff_ms"] = grow_eff_ms(farm, plan, i)
	f["by"] = "you"
	f["seed_paid"] = cost
	f["fav"] = _is_fav(plan, now, tz)
	return plan

# Tend every owned ripe or empty field in index order. Needs the Copper Hoe
# unless ignore_tool (Collect).
static func tend_all(farm: Dictionary, now_ms: int, tz_s: int, ignore_tool := false) -> Dictionary:
	_ensure(farm)
	var res := _begin(farm, now_ms, tz_s)
	if not ignore_tool and not has_tend_all(farm):
		return _failf(farm, res, "Tend All needs the Copper Hoe")
	_tend_all_fields(farm, now_ms, tz_s, res)
	_finish(farm, res)
	return res

# True once any owned hoe tier grants Tend All (the Copper Hoe and up).
static func has_tend_all(farm: Dictionary) -> bool:
	for t in mini(int(farm["up"]["tool"]) + 1, cfg()["tools"].size()):
		if bool(_cfg["tools"][t].get("tend_all", false)):
			return true
	return false

static func _tend_all_fields(farm: Dictionary, now: int, tz: int, res: Dictionary) -> void:
	res["fields"] = []
	for i in FIELDS:
		var f: Dictionary = farm["fields"][i]
		if f["owned"] and (f["crop"] == "" or _ripe(farm, i, now)):
			_tend_field(farm, i, now, tz, res)
	res["tended"] = res["fields"].size()

# Pip's note [Collect]: take_report() then a Tend All that ignores the tool.
# After an absence >= 10 min it schedules the welcome butterfly 3-8 s out.
# Result adds report (take_report's dict) and welcome_at_ms (0 if none).
static func collect(farm: Dictionary, now_ms: int, tz_s: int) -> Dictionary:
	_ensure(farm)
	if farm["clock"]["epoch_ms"] == 0:
		start(farm, now_ms, tz_s)
	var s := _settle(farm, now_ms, tz_s)
	var gap := maxi(0, now_ms - int(farm["clock"]["last_input_ms"]))
	var rep := _take_report(farm)
	var res := _begin(farm, now_ms, tz_s)
	var ev: Array = s["events"].duplicate()
	ev.append_array(res["events"])
	res["events"] = ev
	res["spud_coins"] += s["coins"]
	res["absence_s"] = gap / 1000 if gap >= _kk().clockin_ms else 0
	res["report"] = rep
	_tend_all_fields(farm, now_ms, tz_s, res)
	res["welcome_at_ms"] = 0
	if gap >= _k.welcome_min_ms:
		var d: Array = _cfg["butterflies"]["welcome_delay_s"]
		var bf: Dictionary = farm["buffs"]
		bf["next_butterfly_ms"] = now_ms + _rand_int(farm, int(d[0]) * 1000, int(d[1]) * 1000)
		bf["welcome"] = true
		bf["butterfly_field"] = _random_owned_field(farm)
		res["welcome_at_ms"] = bf["next_butterfly_ms"]
		res["events"].append({"type": "welcome_butterfly", "at_ms": bf["next_butterfly_ms"]})
	_finish(farm, res)
	return res

# Set a field's plan (free; only the next planting uses it). Scenes pass
# now_ms: the change is then an input that settles first, so the new plan is
# never applied to Spudling replants in time already passed. Without now_ms
# (projections, tests) nothing is settled or stamped.
static func set_plan(farm: Dictionary, i: int, crop: String, now_ms := -1, tz_s := 0) -> Dictionary:
	_ensure(farm)
	var res := _begin(farm, now_ms, tz_s) if now_ms >= 0 else _result()
	if not _valid_field(i) or not farm["fields"][i]["owned"]:
		return _failf(farm, res, "No such field")
	if not _crop.has(crop):
		return _failf(farm, res, "Unknown crop")
	if not crop in farm["unlocked"]:
		return _failf(farm, res, _page_reason(farm, int(_crop[crop]["page"])))
	farm["fields"][i]["plan"] = crop
	res["events"].append({"type": "plan", "field": i, "crop": crop})
	_check_pin(farm)
	return res

# Uproot the growing crop (refund floor(seed_paid / 2)) and plant the plan. A
# ripe or empty field is simply tended, so nothing grown is ever thrown away.
# Result adds refund.
static func replant_now(farm: Dictionary, i: int, now_ms: int, tz_s: int) -> Dictionary:
	_ensure(farm)
	var res := _begin(farm, now_ms, tz_s)
	res["refund"] = 0
	if not _valid_field(i) or not farm["fields"][i]["owned"]:
		return _failf(farm, res, "No such field")
	var f: Dictionary = farm["fields"][i]
	if f["crop"] == "" or _ripe(farm, i, now_ms):
		_tend_field(farm, i, now_ms, tz_s, res)
	else:
		var refund := int(f["seed_paid"]) / 2
		_add_wallet(farm, refund)
		res["refund"] = refund
		res["events"].append({"type": "uproot", "field": i, "crop": f["crop"], "refund": refund})
		f["crop"] = ""
		f["grow_eff_ms"] = 0
		f["seed_paid"] = 0
		res["fields"] = [{"field": i, "crop": "", "coins": 0, "stars": [], "planted": _plant_plan(farm, i, now_ms, tz_s, res)}]
	_finish(farm, res)
	return res

# ════════════════════════════════════════════════════════════ purchases

# buy(farm, item, arg, now, tz). Items and args:
#   "deed" i (0..5; null = lowest unowned) · "greenhouse" · "hut" i (null =
#   first owned field without one) · "share" · "quick" · "house" · "tool" ·
#   "soil" · "strain" crop · "sprinkler" socket ("1-2"...; null = first free
#   fence touching an owned field). "hut:3" style ids work with arg null.
# Result adds id, item, arg, needed (cost when short).
static func buy(farm: Dictionary, item: String, arg, now_ms: int, tz_s: int) -> Dictionary:
	_ensure(farm)
	return _buy(farm, item, arg, _begin(farm, now_ms, tz_s))

# buy() after the input was noted (res from _begin).
static func _buy(farm: Dictionary, item: String, arg, res: Dictionary) -> Dictionary:
	var p := _parse_id(item, arg)
	var it: String = p[0]
	var a = _resolve_arg(farm, it, p[1])
	res["item"] = it
	res["arg"] = a
	res["id"] = row_id(it, a)
	var cost := _cost(farm, it, a)
	if cost < 0:
		return _failf(farm, res, "Nothing left to buy there")
	var why := _lock_reason(farm, it, a)
	if why != "":
		return _failf(farm, res, why)
	if int(farm["wallet"]) < cost:
		res["needed"] = cost
		return _failf(farm, res, "Needs %s c" % Fmt.coins(cost))
	farm["wallet"] = int(farm["wallet"]) - cost
	res["spent"] = cost
	_apply(farm, it, a, res["events"])
	_finish(farm, res)
	return res

# Price of the next purchase of item/arg, or -1 when maxed, owned or invalid.
static func cost_of(farm: Dictionary, item: String, arg) -> int:
	_ensure(farm)
	var p := _parse_id(item, arg)
	return _cost(farm, p[0], _resolve_arg(farm, p[0], p[1]))

static func row_id(item: String, arg) -> String:
	if arg == null or (arg is String and arg == ""):
		return item
	return "%s:%s" % [item, str(arg)]

static func _parse_id(item: String, arg) -> Array:
	if arg == null and item.contains(":"):
		var parts := item.split(":", true, 1)
		var a = parts[1]
		if parts[0] in ["deed", "hut"] and a.is_valid_int():
			a = int(a)
		return [parts[0], a]
	return [item, arg]

static func _resolve_arg(farm: Dictionary, it: String, arg):
	match it:
		"deed":
			if _is_num(arg):
				return int(arg)
			if arg != null and str(arg) != "":
				return -1                 # "deed:abc" names no field
			for i in _kk().field_count:
				if not farm["fields"][i]["owned"]:
					return i
			return -1
		"hut":
			if _is_num(arg):
				return int(arg)
			if arg != null and str(arg) != "":
				return -1
			for i in FIELDS:
				if farm["fields"][i]["owned"] and not farm["fields"][i]["hut"]:
					return i
			return -1
		"strain":
			return "" if arg == null else str(arg)
		"sprinkler":
			if arg != null and str(arg) != "":
				return str(arg)
			return _first_free_socket(farm)
	return null

static func _is_num(v) -> bool:
	return typeof(v) == TYPE_INT or typeof(v) == TYPE_FLOAT or (v is String and v.is_valid_int())

static func _first_free_socket(farm: Dictionary) -> String:
	var fences: Dictionary = _kk().fences
	for s in fences:
		if s in farm["sprinklers"]:
			continue
		if farm["fields"][fences[s][0]]["owned"] or farm["fields"][fences[s][1]]["owned"]:
			return s
	return ""

static func _cost(farm: Dictionary, it: String, a) -> int:
	var up: Dictionary = farm["up"]
	match it:
		"deed":
			if typeof(a) != TYPE_INT or a < 0 or a >= _kk().field_count or farm["fields"][a]["owned"]:
				return -1
			var n := _owned_count(farm) - 1
			var deeds: Array = _cfg["deeds"]
			return int(deeds[n]) if n >= 0 and n < deeds.size() else -1
		"greenhouse":
			return -1 if farm["fields"][GREENHOUSE]["owned"] else int(_cfg["greenhouse"]["cost"])
		"hut":
			var costs: Array = _cfg["huts"]["costs"]
			if not _valid_field(a) or farm["fields"][a]["hut"] or int(up["huts"]) >= costs.size():
				return -1
			return int(costs[up["huts"]])
		"share":
			var nx := int(up["share"]) + 1
			return int(_cfg["share"][nx][1]) if nx < _cfg["share"].size() else -1
		"quick":
			var nx := int(up["quick"]) + 1
			return int(_cfg["quick"]["costs"][nx]) if nx < _cfg["quick"]["costs"].size() else -1
		"house":
			var nx := int(up["house"]) + 1
			return int(_cfg["house"]["costs"][nx]) if nx < _cfg["house"]["costs"].size() else -1
		"tool":
			var nx := int(up["tool"]) + 1
			return int(_cfg["tools"][nx]["cost"]) if nx < _cfg["tools"].size() else -1
		"soil":
			return int(round(_kk().soil_base * pow(_k.soil_growth, int(up["soil"]))))
		"strain":
			if not _crop.has(str(a)):
				return -1
			var tier := int(up["strains"].get(a, 0))
			var sc: Array = _cfg["strains"]["costs"]
			return int(sc[tier]) if tier < sc.size() else -1
		"sprinkler":
			var sp: Array = _cfg["sprinklers"]["costs"]
			var owned := int(up["sprinklers"])
			if owned >= sp.size():
				return -1
			if a != "" and (not _kk().fences.has(a) or a in farm["sprinklers"]):
				return -1
			return int(sp[owned])
	return -1

# Why a purchase is gated ("" when it isn't): Catalog pages, a field you don't
# own yet, a Strain threshold. Land grants: the n-th deed opens with Catalog
# page deed_pages[n] (farm.json), so kitchen money buys land no faster than
# the Catalog grows.
static func _lock_reason(farm: Dictionary, it: String, a) -> String:
	match it:
		"deed":
			var dp: Array = _cfg.get("deed_pages", [])
			var n := _owned_count(farm) - 1
			if n >= 0 and n < dp.size():
				return _page_reason(farm, int(dp[n]))
		"greenhouse":
			return _page_reason(farm, int(_cfg["greenhouse"]["page"]))
		"hut":
			if not farm["fields"][a]["owned"]:
				return "Buy %s first" % _field_name(a)
		"quick":
			return _page_reason(farm, int(_cfg["quick"]["page"]))
		"sprinkler":
			return _page_reason(farm, int(_cfg["sprinklers"]["page"]))
		"tool":
			var nx := int(farm["up"]["tool"]) + 1
			return _page_reason(farm, int(_cfg["tools"][nx].get("page", 0)))
		"strain":
			var r := _page_reason(farm, int(_cfg["strains"]["page"]))
			if r != "":
				return r
			if not a in farm["unlocked"]:
				return _page_reason(farm, int(_crop[a]["page"]))
			var tier := int(farm["up"]["strains"].get(a, 0))
			var need: int = _crop[a]["strain_at"][tier]
			var have := int(farm["shipped"].get(a, 0))
			if have < need:
				return "Ship %s %s · %s/%s" % [Fmt.coins(need), _crop[a]["name"], Fmt.coins(have), Fmt.coins(need)]
	return ""

# "Catalog page 3: ship 480 Red · 312/480" for the next page, "Catalog page 5"
# for later ones, "" once reached.
static func _page_reason(farm: Dictionary, p: int) -> String:
	if p <= 0 or int(farm["page"]) >= p:
		return ""
	if p != int(farm["page"]) + 1:
		return "Catalog page %d" % p
	var needs: Dictionary = _cfg["catalog"][p - 1]["needs"]
	for c in needs:
		var have := int(farm["shipped"].get(c, 0))
		if have < int(needs[c]):
			return "Catalog page %d: ship %s %s · %s/%s" % [p, Fmt.coins(int(needs[c])), _crop[c]["name"],
					Fmt.coins(have), Fmt.coins(int(needs[c]))]
	return "Catalog page %d" % p

# Apply a (paid) purchase. Also used on projection copies by book().
static func _apply(farm: Dictionary, it: String, a, events: Array) -> void:
	var up: Dictionary = farm["up"]
	match it:
		"deed":
			farm["fields"][a]["owned"] = true
			events.append({"type": "deed", "field": a})
		"greenhouse":
			farm["fields"][GREENHOUSE]["owned"] = true
			events.append({"type": "greenhouse", "field": GREENHOUSE})
		"hut":
			var kk := int(up["huts"])
			farm["fields"][a]["hut"] = true
			farm["fields"][a]["hut_k"] = kk
			up["huts"] = kk + 1
			events.append({"type": "hut_hired", "field": a, "index": kk, "name": _hut_name(kk)})
		"share":
			up["share"] = int(up["share"]) + 1
			events.append({"type": "share", "tier": up["share"], "share": _share(farm)})
		"quick":
			up["quick"] = int(up["quick"]) + 1
			events.append({"type": "quick", "tier": up["quick"], "walk_s": _walk_ms(farm) / 1000})
		"house":
			up["house"] = int(up["house"]) + 1
			events.append({"type": "house", "tier": up["house"], "name": str(_cfg["house"]["names"][up["house"]]),
					"shift_h": _shift_ms(farm) / HOUR_MS})
		"tool":
			up["tool"] = int(up["tool"]) + 1
			events.append({"type": "tool", "tier": up["tool"], "id": str(_cfg["tools"][up["tool"]]["id"])})
		"soil":
			up["soil"] = int(up["soil"]) + 1
			events.append({"type": "soil", "level": up["soil"]})
		"strain":
			var t := int(up["strains"].get(a, 0)) + 1
			up["strains"][a] = t
			events.append({"type": "strain", "crop": a, "tier": t})
		"sprinkler":
			up["sprinklers"] = int(up["sprinklers"]) + 1
			if a != "":
				farm["sprinklers"].append(a)
			events.append({"type": "sprinkler", "socket": a})

static func _hut_name(kk: int) -> String:
	var names: Array = _cfg["huts"]["names"]
	return str(names[kk]) if kk >= 0 and kk < names.size() else "Spudling"

# Place a bought sprinkler on a fence socket, or move one (from_socket) for
# free. Sockets bordering unowned fields are allowed. Watering only affects
# plantings made after the change (crops in the ground keep the grow time
# they were planted with). Scenes pass now_ms: it is then an input that
# settles first, so Spudling replants in time already passed keep the old
# watering. Without now_ms nothing is settled or stamped.
static func place_sprinkler(farm: Dictionary, socket: String, from_socket := "", now_ms := -1, tz_s := 0) -> Dictionary:
	_ensure(farm)
	var res := _begin(farm, now_ms, tz_s) if now_ms >= 0 else _result()
	if not _kk().fences.has(socket):
		return _failf(farm, res, "No such fence")
	var placed: Array = farm["sprinklers"]
	if from_socket != "":
		var idx := placed.find(from_socket)
		if idx < 0:
			return _failf(farm, res, "No sprinkler on fence %s" % from_socket)
		if socket == from_socket:
			_check_pin(farm)
			return res
		if socket in placed:
			return _failf(farm, res, "That fence already has a sprinkler")
		placed[idx] = socket
		res["events"].append({"type": "sprinkler_moved", "from": from_socket, "to": socket})
		_check_pin(farm)
		return res
	if socket in placed:
		return _failf(farm, res, "That fence already has a sprinkler")
	if placed.size() >= int(farm["up"]["sprinklers"]):
		return _failf(farm, res, "Buy a sprinkler first")
	placed.append(socket)
	res["events"].append({"type": "sprinkler", "socket": socket})
	_check_pin(farm)
	return res

# Pin a Farm Book row as the Next Goal ("" unpins). Refused (ok=false, the
# old pin kept) for an id that can't be bought: unknown, maxed, owned. A
# gated row can be pinned. The stored id is the row's canonical id ("hut" ->
# "hut:0", "deed" -> "deed:1"), the one book() rows carry; result adds id.
static func pin(farm: Dictionary, id: String) -> Dictionary:
	_ensure(farm)
	var res := _result()
	res["id"] = ""
	if id == "":
		farm["goal"]["pinned"] = ""
		return res
	var p := _parse_id(id, null)
	var a = _resolve_arg(farm, p[0], p[1])
	if _cost(farm, p[0], a) < 0:
		return _fail(res, "Nothing left to buy there")
	res["id"] = row_id(p[0], a)
	farm["goal"]["pinned"] = res["id"]
	return res

# Q: buy the Next Goal if it is an affordable purchase (never a filler buy).
# Like every action it notes the input (settling first) even when it fails.
static func buy_goal(farm: Dictionary, now_ms: int, tz_s: int) -> Dictionary:
	_ensure(farm)
	var res := _begin(farm, now_ms, tz_s)
	var g := next_goal(farm, now_ms)
	if g["item"] == "" or not g["can_buy"]:
		return _failf(farm, res, g["locked_reason"] if g["locked_reason"] != "" else "Nothing to buy yet")
	return _buy(farm, g["item"], g["arg"], res)

# ════════════════════════════════════════════════════════════ butterflies

# Next timed spawn at now + U(240, 480) s (÷1.5 with the Gold Hoe) on a random
# owned field. Returns the spawn time.
static func schedule_butterfly(farm: Dictionary, now_ms: int) -> int:
	_ensure(farm)
	return _schedule_butterfly(farm, now_ms)

static func _schedule_butterfly(farm: Dictionary, now: int) -> int:
	var b: Dictionary = _cfg["butterflies"]
	var span := _rand_int(farm, int(b["min_s"]) * 1000, int(b["max_s"]) * 1000)
	var rate := float(_cfg["tools"][farm["up"]["tool"]].get("butterfly_rate", 1.0))
	span = int(round(span / rate))
	var bf: Dictionary = farm["buffs"]
	bf["next_butterfly_ms"] = now + span
	bf["welcome"] = false
	bf["butterfly_field"] = _random_owned_field(farm)
	return now + span

static func _random_owned_field(farm: Dictionary) -> int:
	var owned: Array = []
	for i in FIELDS:
		if farm["fields"][i]["owned"]:
			owned.append(i)
	if owned.is_empty():
		return 0
	return owned[_rand_int(farm, 0, owned.size() - 1)]

# A butterfly is on screen: spawned, not yet expired (12 s), player present.
static func butterfly_due(farm: Dictionary, now_ms: int) -> bool:
	var nb := int(farm["buffs"]["next_butterfly_ms"])
	return nb > 0 and now_ms >= nb and now_ms < nb + _kk().life_ms and is_present(farm, now_ms)

# Catch it: 40% Bumper (hand value ×2 for 30 s), 30% Sunshower (every crop
# grows 2 min), 30% Lucky Penny (max(25, 120 s of farm_power)). A welcome
# butterfly is 50/50 Sunshower/Penny and never Bumper. forced_outcome
# ("bumper" | "sunshower" | "penny") is a test hook that skips the due check.
# Result adds outcome; coins is the Penny.
static func catch_butterfly(farm: Dictionary, now_ms: int, welcome := false, forced_outcome := "") -> Dictionary:
	_ensure(farm)
	var tz := int(farm["clock"]["tz_s"])
	var due := butterfly_due(farm, now_ms)
	var is_welcome := welcome or bool(farm["buffs"]["welcome"])
	var res := _begin(farm, now_ms, tz)
	if forced_outcome == "" and not due:
		return _failf(farm, res, "No butterfly here")
	var b: Dictionary = _cfg["butterflies"]
	var outcome := forced_outcome
	if outcome == "":
		var r := _rand(farm)
		if is_welcome:
			outcome = "sunshower" if r < float(b["welcome_odds"]["sunshower"]) else "penny"
		elif r < float(b["odds"]["bumper"]):
			outcome = "bumper"
		elif r < float(b["odds"]["bumper"]) + float(b["odds"]["sunshower"]):
			outcome = "sunshower"
		else:
			outcome = "penny"
	if is_welcome and outcome == "bumper":
		outcome = "sunshower"      # Collect just harvested everything
	match outcome:
		"bumper":
			farm["buffs"]["bumper_until_ms"] = now_ms + int(b["bumper_s"]) * 1000
		"sunshower":
			farm["g_offset_ms"] = int(farm["g_offset_ms"]) + int(b["sunshower_s"]) * 1000
		_:
			outcome = "penny"
			var coins := maxi(int(b["penny_min"]), int(round(float(b["penny_s"]) * _farm_power(farm))))
			_add_wallet(farm, coins)
			_income_add(farm, _hour(now_ms), coins * 1000)
			var st: Dictionary = farm["stats"]
			st["lifetime_coins"] = int(st["lifetime_coins"]) + coins
			st["penny_coins"] = int(st["penny_coins"]) + coins
			res["coins"] = coins
	farm["stats"]["butterflies"] = int(farm["stats"]["butterflies"]) + 1
	_schedule_butterfly(farm, now_ms)
	res["outcome"] = outcome
	res["welcome"] = is_welcome
	res["events"].append({"type": "butterfly", "outcome": outcome, "coins": res["coins"]})
	_finish(farm, res)
	return res

# ════════════════════════════════════════════════════════════ catalog + tutorial

# Unlock every Catalog page whose shipped counts are met (pages are in order).
static func _check_pages(farm: Dictionary, events: Array) -> Array:
	var cat: Array = _cfg["catalog"]
	var got: Array = []
	while int(farm["page"]) < cat.size():
		var pg: Dictionary = cat[farm["page"]]
		if not _needs_met(farm, pg["needs"]):
			break
		farm["page"] = int(farm["page"]) + 1
		var crop := str(pg["unlocks"])
		if not crop in farm["unlocked"]:
			farm["unlocked"].append(crop)
		got.append(farm["page"])
		events.append({"type": "page", "page": farm["page"], "crop": crop, "also": pg.get("also", []),
				"text": str(pg.get("text", ""))})
	return got

static func _needs_met(farm: Dictionary, needs: Dictionary) -> bool:
	for c in needs:
		if int(farm["shipped"].get(c, 0)) < int(needs[c]):
			return false
	return true

# Catalog tab: [{page, crop, done, current, needs: [{crop, name, have, need}], text, also}].
static func catalog_view(farm: Dictionary) -> Array:
	_ensure(farm)
	var out: Array = []
	var cat: Array = _cfg["catalog"]
	for p in cat.size():
		var pg: Dictionary = cat[p]
		var needs: Array = []
		for c in pg["needs"]:
			needs.append({"crop": c, "name": _crop[c]["name"], "have": int(farm["shipped"].get(c, 0)),
					"need": int(pg["needs"][c])})
		out.append({"page": p + 1, "crop": str(pg["unlocks"]), "done": int(farm["page"]) > p,
				"current": int(farm["page"]) == p, "needs": needs, "text": str(pg.get("text", "")),
				"also": pg.get("also", [])})
	return out

static func _advance_tutorial(farm: Dictionary, events: Array) -> void:
	var tut: Array = _cfg["tutorial"]
	var step := int(farm["goal"]["tutorial"])
	while step < tut.size() and _goal_done(farm, tut[step]):
		step += 1
		events.append({"type": "tutorial", "step": step, "id": str(tut[step - 1]["id"])})
	farm["goal"]["tutorial"] = step

static func _goal_done(farm: Dictionary, g: Dictionary) -> bool:
	var d: Dictionary = g["done"]
	for key in d:
		if _goal_stat(farm, key) < int(d[key]):
			return false
	return true

static func _goal_stat(farm: Dictionary, key: String) -> int:
	match key:
		"planted":
			var n := int(farm["stats"]["hand_picks"])
			for f in farm["fields"]:
				if f["owned"] and f["crop"] != "":
					n += 1
			return n
		"hand_picks":
			return int(farm["stats"]["hand_picks"])
		"huts":
			return int(farm["up"]["huts"])
		"fields":
			return _owned_count(farm, true)
		"tool":
			return int(farm["up"]["tool"])
		"page":
			return int(farm["page"])
	if key.begins_with("shipped:"):
		return int(farm["shipped"].get(key.substr(8), 0))
	return 0

# ════════════════════════════════════════════════════════════ projections (§5.11)

# Hand net of one field harvest of crop c on field i, in milli-coins:
# 12 × (tile × star_ev − seed × 1000).
static func _hand_net(farm: Dictionary, i: int, c: String, fav := false, ev := -1.0) -> float:
	if ev < 0.0:
		ev = _star_ev(farm)
	return _kk().plots * (_tile_milli(farm, c, fav) * ev - _crop[c]["seed"] * 1000.0)

# Coins per second while present: every owned field cycling its plan by hand
# (grow + 5 s reaction).
static func rate_here(farm: Dictionary) -> float:
	_ensure(farm)
	return _rate_here(farm)

static func _rate_here(farm: Dictionary) -> float:
	var ev := _star_ev(farm)
	var sum := 0.0
	for i in FIELDS:
		sum += _field_here(farm, i, ev)
	return sum

# One field's share of rate_here (c/s; 0 when unowned).
static func _field_here(farm: Dictionary, i: int, ev: float) -> float:
	var f: Dictionary = farm["fields"][i]
	if not f["owned"]:
		return 0.0
	return _hand_net(farm, i, f["plan"], false, ev) / float(grow_eff_ms(farm, f["plan"], i) + _kk().reaction_ms)

# Coins per second over one absence of gap_s that starts right after you
# hand-plant every field's plan.
static func rate_away(farm: Dictionary, gap_s: int) -> float:
	_ensure(farm)
	return _rate_away(farm, gap_s)

static func _rate_away(farm: Dictionary, gap_s: int) -> float:
	if gap_s <= 0:
		return 0.0
	var gap := gap_s * 1000
	var ev := _star_ev(farm)
	var sum := 0.0
	for i in FIELDS:
		sum += _field_away(farm, i, gap, ev)
	return sum / float(gap)

# One field's away value for its plan (milli-coins; 0 when unowned).
static func _field_away(farm: Dictionary, i: int, gap: int, ev: float) -> float:
	if not farm["fields"][i]["owned"]:
		return 0.0
	return _away_value(farm, i, farm["fields"][i]["plan"], gap, ev)

# Value (milli-coins) of one absence of gap_ms on field i planted with c,
# with breakpoint (sawtooth) math (lead decision 1, replacing §5.11's
# pro-rating): a crop that is ripe `span` ms after the absence starts is worth
# its full value if span <= gap, else value / ceil(span / gap), the share of
# it one gap-long absence of a steady schedule brings in.
#   no hut (or gap <= clock-in): hand_net per the rule above (span = grow_eff);
#   hut: first pick of your crop (after its grace, min(grace, grow_eff) past
#   ripe) at full value × star EV, + share × gross of
#   a Spudling-planted crop per further cycle until the shift ends − seed,
#   plus the last Spudling crop (planted at p_last, hand-picked with stars)
#   per the same rule with span = p_last + grow_eff.
# Speed upgrades therefore pay only when they move a crop across a gap boundary.
static func _away_value(farm: Dictionary, i: int, c: String, gap: int, ev := -1.0) -> float:
	if ev < 0.0:
		ev = _star_ev(farm)
	return _away_eval(_away_params(farm, i, c, ev), gap)

# The gap-independent part of _away_value for field i and crop c, so a
# schedule of many gaps costs one pass of arithmetic per gap:
# [grow_eff, hand_net] without a hut, plus [first pick − seed, share × gross,
# gross × EV, walk, clock-in + shift] with one.
static func _away_params(farm: Dictionary, i: int, c: String, ev: float) -> Array:
	var k := _kk()
	var ge := grow_eff_ms(farm, c, i)
	var hn := _hand_net(farm, i, c, false, ev)
	if not farm["fields"][i]["hut"]:
		return [ge, hn]
	var gross := float(k.plots * _tile_milli(farm, c, false))
	return [ge, hn, gross * ev - k.plots * _crop[c]["seed"] * 1000.0, _share(farm) * gross, gross * ev,
			_walk_ms(farm), k.clockin_ms + _shift_ms(farm)]

static func _away_eval(p: Array, gap: int) -> float:
	var ge: int = p[0]
	var no_hut := _per_absence(p[1], ge, gap)
	var ck: int = _k.clockin_ms
	if p.size() == 2 or gap <= ck:
		return no_hut
	var walk: int = p[5]
	var e := mini(gap, p[6])
	var p1 := maxi(ge + mini(_k.grace_ms, ge), ck) + walk     # your crop waits out its grace
	if p1 > e:
		return no_hut
	var cyc := ge + walk
	var cycles := (e - p1) / cyc
	return p[2] + p[3] * cycles + _per_absence(p[4], p1 + cycles * cyc + ge, gap)

# Away value of field i over a whole schedule ([[gap_ms, count], ...]): each
# absence with the crop that is best for that gap (what a sensible player
# plants before leaving), summed. 0 when unowned.
static func _field_away_sched(farm: Dictionary, i: int, sched: Array, ev: float) -> float:
	if not farm["fields"][i]["owned"]:
		return 0.0
	var best: Array = []
	best.resize(sched.size())
	best.fill(0.0)
	for c in farm["unlocked"]:
		var p := _away_params(farm, i, c, ev)
		for j in sched.size():
			best[j] = maxf(best[j], _away_eval(p, sched[j][0]))
	var sum := 0.0
	for j in sched.size():
		sum += best[j] * sched[j][1]
	return sum

# Breakpoint share of a value that becomes ripe `span` ms into an absence.
static func _per_absence(value: float, span: int, gap: int) -> float:
	if span <= gap:
		return value
	return value / ceilf(float(span) / float(maxi(1, gap)))

# Plan-independent power: each owned field's best unlocked hand rate (c/s).
static func farm_power(farm: Dictionary) -> float:
	_ensure(farm)
	return _farm_power(farm)

static func _farm_power(farm: Dictionary) -> float:
	var ev := _star_ev(farm)
	var sum := 0.0
	for i in FIELDS:
		if not farm["fields"][i]["owned"]:
			continue
		var best := 0.0
		for c in farm["unlocked"]:
			best = maxf(best, _hand_net(farm, i, c, false, ev) / float(grow_eff_ms(farm, c, i) + _kk().reaction_ms))
		sum += best
	return sum

# ════════════════════════════════════════════════════════════ views

# Everything a field sign / card needs. Times are wall-clock ms.
static func field_view(farm: Dictionary, i: int, now_ms: int) -> Dictionary:
	_ensure(farm)
	var f: Dictionary = farm["fields"][i]
	var k := _kk()
	var v := {"index": i, "name": _field_name(i), "owned": f["owned"], "greenhouse": i == GREENHOUSE,
			"crop": f["crop"], "plan": f["plan"], "empty": f["crop"] == "", "ripe": false, "stage": 0,
			"progress": 0.0, "planted_ms": 0, "ready_at_ms": 0, "left_ms": 0, "grow_ms": 0,
			"watered": _watered(farm, i), "sockets": [], "hut": f["hut"], "hut_name": "",
			"working": false, "napping": false, "fav": f["fav"], "by": f["by"],
			"seed_paid": f["seed_paid"], "refund": int(f["seed_paid"]) / 2,
			"cost": _cost(farm, "deed", i) if i < k.field_count else _cost(farm, "greenhouse", null),
			"locked_reason": "" if f["owned"] else (_lock_reason(farm, "deed", i) if i < k.field_count \
						else _lock_reason(farm, "greenhouse", null))}
	for s in farm["sprinklers"]:
		if i in k.fences.get(s, []):
			v["sockets"].append(s)
	if f["hut"]:
		v["hut_name"] = _hut_name(int(f["hut_k"]))
		var w0: int = int(farm["clock"]["last_input_ms"]) + k.clockin_ms
		var w1: int = w0 + _shift_ms(farm)
		v["working"] = now_ms >= w0 and now_ms <= w1
		v["napping"] = now_ms > w1
	if f["crop"] != "":
		var ge := _ge_of(farm, i)
		var ready := _ready_at(farm, i)
		var prog := clampf(float(ge - maxi(0, ready - now_ms)) / float(ge), 0.0, 1.0)
		v["grow_ms"] = ge
		v["planted_ms"] = ready - ge
		v["ready_at_ms"] = ready
		v["left_ms"] = maxi(0, ready - now_ms)
		v["progress"] = prog
		v["ripe"] = now_ms >= ready
		v["stage"] = 4 if v["ripe"] else 1 + mini(2, int(prog * 3.0))
	return v

# Plan picker rows for field i, in crop-table order: {crop, name, color,
# grow_ms, ready_at_ms, seed_cost, net (coins, Favorite included if today's),
# fav, unlocked, page, locked_reason}.
static func plan_options(farm: Dictionary, i: int, now_ms: int, tz_s: int) -> Array:
	_ensure(farm)
	var out: Array = []
	var today := favorite(day_index(now_ms, tz_s))
	for c in _order:
		var ge := grow_eff_ms(farm, c, i)
		var fav: bool = c == today
		out.append({"crop": c, "name": _crop[c]["name"], "color": _crop[c]["color"], "grow_ms": ge,
				"ready_at_ms": now_ms + ge, "seed_cost": _kk().plots * int(_crop[c]["seed"]),
				"net": int(round(_hand_net(farm, i, c, fav) / 1000.0)), "fav": fav,
				"unlocked": c in farm["unlocked"], "page": _crop[c]["page"],
				"locked_reason": _page_reason(farm, int(_crop[c]["page"])) if not c in farm["unlocked"] else ""})
	return out

# Farm Book rows (§5.10/§5.11): every next purchase, maxed ones omitted.
# Row: {id, item, arg, tab, group, name, effect, cost, can_buy, locked,
#   locked_reason, d_here, d_away (c/s), payback_s (-1 = no gain for your
#   schedule), pinned}. Gains come from applying the purchase to a copy;
#   payback = cost / (d_here × f_here + d_away × (1 − f_here)) with your
#   logged schedule. A new field is projected with its best crop for you.
static func book(farm: Dictionary, now_ms: int, tz_s: int) -> Array:
	_ensure(farm)
	var sched := _schedule(farm, now_ms)
	var wsum := 0.0
	for e in sched:
		wsum += float(e[0]) * float(e[1])
	var fh := f_here(farm, now_ms)
	var ev0 := _star_ev(farm)
	var here0: Array = []
	var away0: Array = []
	for i in FIELDS:
		here0.append(_field_here(farm, i, ev0))
		away0.append(_field_away_sched(farm, i, sched, ev0))
	var mixr := {}
	var rows: Array = []
	for cand in _candidates(farm):
		var it: String = cand[0]
		var a = cand[1]
		var cost := _cost(farm, it, a)
		if cost < 0:
			continue
		var why := _lock_reason(farm, it, a)
		var dh := 0.0
		var da := 0.0
		if it == "strain":
			# Priced from what you actually harvest (design D10: a Strain is
			# worth 0.5 × f_c of income), not from today's plans.
			if mixr.is_empty():
				mixr = _mix_rates(farm, now_ms)
				mixr["_"] = true
			dh = _strain_gain(farm, a, mixr)
			da = dh
		else:
			# Rates are sums over fields, so only the fields this purchase
			# touches are recomputed on the copy (a hut row's d_here is exactly 0).
			var aff := _affected(farm, it, a)
			var cp := _proj_copy(farm, aff)
			_apply(cp, it, a, [])
			if it == "deed" or it == "greenhouse":
				var ni: int = a if it == "deed" else GREENHOUSE
				cp["fields"][ni]["plan"] = _best_plan_for(cp, ni, fh, sched, wsum)
			var ev1 := _star_ev(cp)
			for i in aff:
				dh += _field_here(cp, i, ev1) - here0[i]
				da += _field_away_sched(cp, i, sched, ev1) - away0[i]
			da /= maxf(1.0, wsum)
		var denom := dh * fh + da * (1.0 - fh)
		var d := _describe(farm, it, a)
		var id := row_id(it, a)
		rows.append({"id": id, "item": it, "arg": a, "tab": TAB[it], "group": it, "name": d[0], "effect": d[1],
				"cost": cost, "can_buy": why == "" and int(farm["wallet"]) >= cost, "locked": why != "",
				"locked_reason": why, "d_here": dh, "d_away": da,
				"payback_s": float(cost) / denom if denom > 1e-9 else -1.0,
				"pinned": farm["goal"]["pinned"] == id})
	return rows

# Coins per second the next Strain tier of crop c adds at your recent harvest
# mix: (strain_mult − 1) × that crop's harvest income.
static func _strain_gain(farm: Dictionary, c: String, mixr: Dictionary) -> float:
	var e: Array = mixr.get(c, [0.0, 0.0])
	return (float(e[0]) + float(e[1])) * (_kk().strain_mult - 1.0)

# Every purchase that could be a row: [item, arg].
static func _candidates(farm: Dictionary) -> Array:
	var out: Array = []
	var dz = _resolve_arg(farm, "deed", null)
	if dz >= 0:
		out.append(["deed", dz])
	out.append(["greenhouse", null])
	for s in _kk().fences:
		var pr: Array = _k.fences[s]
		if not s in farm["sprinklers"] and (farm["fields"][pr[0]]["owned"] or farm["fields"][pr[1]]["owned"]):
			out.append(["sprinkler", s])
	for i in FIELDS:
		if farm["fields"][i]["owned"] and not farm["fields"][i]["hut"]:
			out.append(["hut", i])
	for it in ["share", "quick", "house", "tool", "soil"]:
		out.append([it, null])
	for c in _order:
		if c in farm["unlocked"]:
			out.append(["strain", c])
	return out

# The parts of the farm the rate functions read; the field dicts in `aff`
# (the only ones a purchase may edit) are copied, the rest shared read-only.
static func _proj_copy(farm: Dictionary, aff: Array) -> Dictionary:
	var fields: Array = farm["fields"].duplicate()
	for i in aff:
		fields[i] = fields[i].duplicate()
	return {"fields": fields, "up": farm["up"].duplicate(true),
			"sprinklers": farm["sprinklers"].duplicate(), "unlocked": farm["unlocked"],
			"page": farm["page"], "shipped": farm["shipped"]}

# Fields whose rates a purchase can change.
static func _affected(farm: Dictionary, it: String, a) -> Array:
	match it:
		"deed", "hut":
			return [a]
		"greenhouse":
			return [GREENHOUSE]
		"sprinkler":
			return _kk().fences[a].duplicate() if a != "" else []
	var out: Array = []
	for i in FIELDS:
		var f: Dictionary = farm["fields"][i]
		if not f["owned"]:
			continue
		if it in ["share", "quick", "house"] and not f["hut"]:
			continue
		if it == "strain" and f["plan"] != a:
			continue
		out.append(i)
	return out

# Crop with the best blended value for this schedule on field i (the plan a
# new field is projected with): here rate × f_here + its away value over the
# schedule × (1 − f_here).
static func _best_plan_for(farm: Dictionary, i: int, fh: float, sched: Array, wsum: float) -> String:
	var ev := _star_ev(farm)
	var best := FREE_CROP
	var best_v := -INF
	for c in farm["unlocked"]:
		var here := _hand_net(farm, i, c, false, ev) / float(grow_eff_ms(farm, c, i) + _kk().reaction_ms)
		var p := _away_params(farm, i, c, ev)
		var away := 0.0
		for e in sched:
			away += _away_eval(p, e[0]) * e[1]
		var v := fh * here + (1.0 - fh) * away / maxf(1.0, wsum)
		if v > best_v:
			best_v = v
			best = c
	return best

# [name, effect] for a row.
static func _describe(farm: Dictionary, it: String, a) -> Array:
	var up: Dictionary = farm["up"]
	match it:
		"deed":
			return ["Deed · %s" % _field_name(a), "+1 field (%d plots)" % _kk().plots]
		"greenhouse":
			return ["Greenhouse", "7th field, grows ×%.2f" % _kk().gh_mult]
		"sprinkler":
			if a == "":
				return ["Sprinkler", "Waters both fields on one fence (grow ×%.1f)" % _kk().spr_mult]
			var pr: Array = _kk().fences[a]
			return ["Sprinkler · fence %s" % a, "Waters %s and %s (grow ×%.1f)" % [_field_name(pr[0]),
					_field_name(pr[1]), _k.spr_mult]]
		"hut":
			var nm := _hut_name(int(up["huts"]))
			return ["Spudling hut · %s" % _field_name(a), "%s works %s while you're away" % [nm, _field_name(a)]]
		"share":
			var nx := int(up["share"]) + 1
			return ["Share %d%%" % int(round(_kk().share[nx] * 100.0)),
					"You keep %d%% of Spudling-planted crops (now %d%%)" % [int(round(_k.share[nx] * 100.0)),
					int(round(_share(farm) * 100.0))]]
		"quick":
			var nx := int(up["quick"]) + 1
			return ["Quick Hands %ds" % (_kk().walk_ms[nx] / 1000),
					"Spudlings walk %ds per pick (now %ds)" % [_k.walk_ms[nx] / 1000, _walk_ms(farm) / 1000]]
		"house":
			var nx := int(up["house"]) + 1
			return ["Farmhouse · %s" % str(_cfg["house"]["names"][nx]),
					"Spudlings work %s per absence (now %s)" % [Fmt.dur(_kk().shift_ms[nx] / 1000),
					Fmt.dur(_shift_ms(farm) / 1000)]]
		"tool":
			var t: Dictionary = _cfg["tools"][int(up["tool"]) + 1]
			if bool(t.get("tend_all", false)):
				return [str(t["name"]), "Tend All (T)"]
			var eff := "Stars: silver %d%% · gold %d%%" % [int(round(float(t["silver"]) * 100.0)),
					int(round(float(t["gold"]) * 100.0))]
			if t.has("butterfly_rate"):
				eff += " · butterflies ×%s" % str(t["butterfly_rate"])
			return [str(t["name"]), eff]
		"soil":
			return ["Soil L%d" % (int(up["soil"]) + 1), "×%s every crop (now ×%.2f)" % [str(_kk().soil_mult),
					pow(_k.soil_mult, int(up["soil"]))]]
		"strain":
			var t := int(up["strains"].get(a, 0)) + 1
			return ["Prize Strain · %s %s" % [_crop[a]["name"], ROMAN[t]],
					"×%s %s value (%s ribbon)" % [str(_kk().strain_mult), _crop[a]["name"],
					str(_cfg["strains"]["ribbons"][t - 1])]]
	return [it, ""]

# ════════════════════════════════════════════════════════════ next goal

# The Next Goal card: tutorial goals 1-6, then the pinned row, then the next
# Catalog page, then the cheapest Farm Book row you can't afford yet.
# {kind: "tutorial"|"pinned"|"page"|"buy"|"done", step, id, item, arg, label,
#  hint, progress, target, cost, can_buy, locked_reason, eta_s (-1 unknown),
#  checkins}
static func next_goal(farm: Dictionary, now_ms: int) -> Dictionary:
	_ensure(farm)
	var g := {"kind": "done", "step": 0, "id": "", "item": "", "arg": null, "label": "", "hint": "",
			"progress": 0, "target": 0, "cost": -1, "can_buy": false, "locked_reason": "", "eta_s": -1,
			"checkins": 0}
	var tut: Array = _cfg["tutorial"]
	var step := int(farm["goal"]["tutorial"])
	while step < tut.size() and _goal_done(farm, tut[step]):
		step += 1
	if step < tut.size():
		var t: Dictionary = tut[step]
		g["kind"] = "tutorial"
		g["step"] = step + 1
		g["label"] = str(t["label"])
		g["hint"] = str(t.get("hint", ""))
		if t.has("buy"):
			_goal_buy(farm, g, str(t["buy"]), _resolve_arg(farm, str(t["buy"]), null), now_ms)
			g["label"] = str(t["label"])
		elif t["done"].has("page"):
			_goal_page(farm, g, int(t["done"]["page"]), now_ms)
			g["label"] = str(t["label"])
		else:
			g["target"] = 1
			if t["done"].has("hand_picks") and farm["fields"][0]["crop"] != "":
				g["eta_s"] = maxi(0, _ready_at(farm, 0) - now_ms) / 1000
		return g
	var pinned: String = farm["goal"]["pinned"]
	if pinned != "":
		var p := _parse_id(pinned, null)
		var a = _resolve_arg(farm, p[0], p[1])
		if _cost(farm, p[0], a) >= 0:
			_goal_buy(farm, g, p[0], a, now_ms)
			g["kind"] = "pinned"
			return g
	if int(farm["page"]) < _cfg["catalog"].size():
		_goal_page(farm, g, int(farm["page"]) + 1, now_ms)
		return g
	var best_cost := -1
	var best: Array = []
	for cand in _candidates(farm):
		var c := _cost(farm, cand[0], cand[1])
		if c >= 0 and c > int(farm["wallet"]) and _lock_reason(farm, cand[0], cand[1]) == "" \
				and (best_cost < 0 or c < best_cost):
			best_cost = c
			best = cand
	if not best.is_empty():
		_goal_buy(farm, g, best[0], best[1], now_ms)
		g["kind"] = "buy"
	return g

static func _goal_buy(farm: Dictionary, g: Dictionary, it: String, a, now: int) -> void:
	var cost := _cost(farm, it, a)
	var why := _lock_reason(farm, it, a) if cost >= 0 else "Nothing left to buy there"
	var wallet := int(farm["wallet"])
	g["item"] = it
	g["arg"] = a
	g["id"] = row_id(it, a)
	g["label"] = _describe(farm, it, a)[0] if cost >= 0 else it
	g["cost"] = cost
	g["progress"] = mini(wallet, maxi(0, cost))
	g["target"] = maxi(0, cost)
	g["locked_reason"] = why
	g["can_buy"] = why == "" and cost >= 0 and wallet >= cost
	if cost >= 0 and wallet < cost:
		var typ := typical_absence_s(farm, now)
		var rate := maxf(income_rate(farm, now), _rate_away(farm, typ))
		if rate > 0.0:
			g["eta_s"] = int(ceil(float(cost - wallet) / rate))
			g["checkins"] = int(ceil(float(g["eta_s"]) / float(typ + 60)))
	elif cost >= 0:
		g["eta_s"] = 0

static func _goal_page(farm: Dictionary, g: Dictionary, p: int, now: int) -> void:
	var pg: Dictionary = _cfg["catalog"][p - 1]
	g["kind"] = "page" if g["kind"] == "done" else g["kind"]
	g["id"] = "page:%d" % p
	g["label"] = "%s page" % _crop[str(pg["unlocks"])]["name"]
	g["eta_s"] = 0
	var typ := typical_absence_s(farm, now)
	var fh := f_here(farm, now)
	var first := true
	for c in pg["needs"]:
		var have := int(farm["shipped"].get(c, 0))
		var need := int(pg["needs"][c])
		if have >= need:
			continue
		if first:
			g["label"] += " · ship %s %s" % [Fmt.coins(need), _crop[c]["name"]]
			g["progress"] = have
			g["target"] = need
			first = false
		var rate := _ship_rate(farm, c, fh, typ)
		if rate <= 0.0:
			g["eta_s"] = -1
		elif g["eta_s"] >= 0:
			g["eta_s"] = maxi(g["eta_s"], int(ceil(float(need - have) / rate)))
	if g["eta_s"] > 0:
		g["checkins"] = int(ceil(float(g["eta_s"]) / float(typ + 60)))

# Plots of crop c shipped per second from the current plans, blending present
# hand cycles with away harvests (Spudling cycles during the shift).
static func _ship_rate(farm: Dictionary, c: String, fh: float, typ: int) -> float:
	var k := _kk()
	var gap := typ * 1000
	var sum := 0.0
	for i in FIELDS:
		var f: Dictionary = farm["fields"][i]
		if not f["owned"] or f["plan"] != c:
			continue
		var ge := grow_eff_ms(farm, c, i)
		var here := float(k.plots) / float(ge + k.reaction_ms)
		# one harvest per ceil(ge / gap) absences (breakpoint math, lead decision 1)
		var away := float(k.plots) / float(_cdiv(ge, maxi(1, gap)) * maxi(1, gap))
		if f["hut"]:
			var work := maxi(0, mini(gap, k.clockin_ms + _shift_ms(farm)) - k.clockin_ms)
			away = float(k.plots) * (1.0 + float(work) / float(ge + _walk_ms(farm))) / float(maxi(gap, 1))
		sum += (fh * here + (1.0 - fh) * away) * 1000.0
	return sum

# ════════════════════════════════════════════════════════════ report, preview

# Pip's note: what happened since the last note, then cleared (along with the
# one-time migration ledger). Ripe fields are counted at the last settle;
# away_ms sums every absence (>= clock-in) since the last note, including the
# one still open. from_ms is the start of the first of them. worked_ms and
# nap_ms are durations (Spudlings working / napping after their shift, summed
# over those absences); nap_from_ms is the instant the latest shift ended.
# {from_ms, to_ms, away_ms, coins, baskets, picks {crop: baskets}, worked_ms,
#  nap_ms, nap_from_ms, napped, pages, ripe, ripe_fields, waiting_coins,
#  helpers, migration}
static func take_report(farm: Dictionary) -> Dictionary:
	_ensure(farm)
	return _take_report(farm)

static func _take_report(farm: Dictionary) -> Dictionary:
	var r: Dictionary = farm["report"].duplicate(true)
	_fill(r, _empty_report())
	var at := int(farm["clock"]["last_settle_ms"])
	# Away time: absences already ended since the last note, plus the open one.
	var away := int(r["away_ms"])
	var open := at - int(farm["clock"]["last_input_ms"])
	if int(r["from_ms"]) > 0 and open >= _kk().clockin_ms:
		away += open
	var ripe: Array = []
	var waiting := 0.0
	for i in FIELDS:
		if farm["fields"][i]["owned"] and _ripe(farm, i, at):
			ripe.append(i)
			waiting += _ripe_value(farm, i)
	var helpers: Array = []
	for kk in int(farm["up"]["huts"]):
		helpers.append(_hut_name(kk))
	var out := {"from_ms": int(r["from_ms"]), "to_ms": int(r["to_ms"]),
			"away_ms": away,
			"coins": int(r["coins"]), "baskets": int(r["baskets"]), "picks": r["picks"],
			"worked_ms": int(r["worked_ms"]), "nap_ms": int(r["nap_ms"]), "nap_from_ms": int(r["nap_from_ms"]),
			"napped": int(r["nap_ms"]) > 0,
			"pages": r["pages"], "ripe": ripe.size(), "ripe_fields": ripe, "waiting_coins": int(waiting),
			"helpers": helpers, "migration": farm["migration"].duplicate(true)}
	farm["report"] = {}
	farm["migration"] = {}
	return out

# Expected hand value of a ripe field (coins, star EV, no Bumper).
static func _ripe_value(farm: Dictionary, i: int) -> float:
	var f: Dictionary = farm["fields"][i]
	return _kk().plots * _tile_milli(farm, f["crop"], f["fav"]) * _star_ev(farm) / 1000.0

# Dry-run settle on a deep copy (main-menu teaser); never mutates `farm`.
# {started, ripe, waiting_coins, settle_coins, report_coins, wallet}
static func preview(farm: Dictionary, now_ms: int, tz_s: int) -> Dictionary:
	var cp: Dictionary = farm.duplicate(true)
	_ensure(cp)
	var s := _settle(cp, now_ms, tz_s)
	var ripe := 0
	var waiting := 0.0
	for i in FIELDS:
		if cp["fields"][i]["owned"] and _ripe(cp, i, now_ms):
			ripe += 1
			waiting += _ripe_value(cp, i)
	return {"started": cp["clock"]["epoch_ms"] != 0, "ripe": ripe, "waiting_coins": int(waiting),
			"settle_coins": s["coins"], "report_coins": int(cp["report"].get("coins", 0)),
			"wallet": cp["wallet"]}

# ════════════════════════════════════════════════════════════ cross-mode

# Farm Picnic for a kitchen / concert / SPUD BLASTER run (not credited here):
# min(15, 0.5 × played minutes × accuracy) minutes of farm_power.
static func picnic_coins(farm: Dictionary, played_s: float, accuracy: float) -> int:
	_ensure(farm)
	if farm["clock"]["epoch_ms"] == 0:
		return 0
	var p: Dictionary = _cfg["picnic"]
	var minutes := minf(float(p["max_min"]), float(p["factor"]) * maxf(0.0, played_s) / 60.0 * clampf(accuracy, 0.0, 1.0))
	return int(round(minutes * 60.0 * _farm_power(farm)))

# Kitchen golden-potato odds bonus: +0.004 per Prize Strain tier, capped 0.10.
static func kitchen_golden_bonus(farm: Dictionary) -> float:
	_ensure(farm)
	var tiers := 0
	for c in farm["up"]["strains"]:
		tiers += int(farm["up"]["strains"][c])
	var kc: Dictionary = _cfg["kitchen"]
	return minf(float(kc["golden_cap"]), float(kc["golden_per_ribbon"]) * tiers)
