extends RefCounted
class_name FarmView

# Pure, read-only query helpers for the farm and town scenes, built only on
# FarmEconomy's public API (and farm.json through FarmEconomy.cfg()). Nothing
# here mutates a farm dict or reads Time: callers pass FarmClock values in.
# Geometry (field rects, fence sockets, hut spots) comes from farm.json so the
# economy and the drawing agree on one layout.

const FE = preload("res://scripts/farm/FarmEconomy.gd")
const Fmt = preload("res://scripts/utils/NumFmt.gd")

const CLOCKIN_FALLBACK_MS := 120000

# ── geometry (world px) ──

static func field_count() -> int:
	return FE.FIELDS

static func field_rect(i: int) -> Rect2:
	var f: Dictionary = FE.cfg()["fields"]
	var a: Array = f["greenhouse_rect"] if i == FE.GREENHOUSE else f["rects"][i]
	return Rect2(float(a[0]), float(a[1]), float(a[2]), float(a[3]))

static func field_name(i: int) -> String:
	var names: Array = FE.cfg()["fields"].get("names", [])
	return str(names[i]) if i < names.size() else "Field %d" % (i + 1)

static func plot_grid() -> Vector2i:
	var p: Dictionary = FE.cfg().get("plots", {})
	return Vector2i(int(p.get("cols", 4)), int(p.get("rows", 3)))

# Fence socket ids in a stable order ("1-2", "2-3", "4-5", "5-6", "1-4", ...).
static func sockets() -> Array:
	return FE.cfg()["fields"]["sockets"].keys()

static func socket_pos(s: String) -> Vector2:
	var p: Array = FE.cfg()["fields"]["sockets"].get(s, [0, 0])
	return Vector2(float(p[0]), float(p[1]))

# The two field indices a fence socket waters.
static func socket_fields(s: String) -> Array:
	var out: Array = []
	for v in FE.cfg()["fields"]["fences"].get(s, []):
		out.append(int(v))           # JSON numbers are floats; 0 in [0.0] is false
	return out

# Sockets on the fences of field i (the Greenhouse has none: it is watered).
static func sockets_of(i: int) -> Array:
	var out: Array = []
	for s in FE.cfg()["fields"]["fences"]:
		if i in socket_fields(s):
			out.append(s)
	return out

# Where field i's Spudling hut stands: in the grass just left of the field's
# top-left corner (the Greenhouse hut sits left of the glass).
static func hut_pos(i: int) -> Vector2:
	var r := field_rect(i)
	return Vector2(r.position.x - 104.0, r.position.y + 58.0)

static func hut_rect(i: int) -> Rect2:
	var p := hut_pos(i)
	return Rect2(p.x - 46, p.y - 52, 92, 92)

# ── clock / presence ──

static func clockin_ms() -> int:
	return int(FE.cfg()["clock"].get("clockin_s", 120)) * 1000

static func report_min_ms() -> int:
	return int(FE.cfg()["clock"].get("report_min_s", 120)) * 1000

static func started(farm: Dictionary) -> bool:
	return int(farm.get("clock", {}).get("epoch_ms", 0)) != 0

# Milliseconds since the last real input (0 before the farm starts).
static func idle_ms(farm: Dictionary, now_ms: int) -> int:
	if not started(farm):
		return 0
	return maxi(0, now_ms - int(farm["clock"]["last_input_ms"]))

# Would Pip's note have something to say right now? True for the one-time
# migration ledger, or a pending report whose away time (closed absences plus
# the open one) reaches report_min_s. Mirrors take_report's away arithmetic.
static func note_pending(farm: Dictionary, now_ms: int) -> bool:
	if not started(farm):
		return false
	if farm.get("migration", {}) is Dictionary and not farm.get("migration", {}).is_empty():
		return true
	var r = farm.get("report", {})
	if not (r is Dictionary) or r.is_empty():
		return false
	var away := int(r.get("away_ms", 0))
	var open := int(farm["clock"]["last_settle_ms"]) - int(farm["clock"]["last_input_ms"])
	if int(r.get("from_ms", 0)) > 0 and open >= clockin_ms():
		away += open
	return away >= report_min_ms()

# What take_report() would return, computed on a deep copy (the save is never
# touched), for drawing the note before [Collect] takes it for real.
static func peek_report(farm: Dictionary) -> Dictionary:
	var cp: Dictionary = farm.duplicate(true)
	return FE.take_report(cp)

# True once the session log holds enough recent absences for f_here and
# typical_absence_s to be measured (before that FarmEconomy uses defaults).
static func history_ready(farm: Dictionary, now_ms: int) -> bool:
	var lg: Dictionary = FE.cfg().get("log", {})
	var need := int(lg.get("min_absences", 3))
	var since := now_ms - int(lg.get("presence_days", 7)) * 86400000
	var n := 0
	for a in farm.get("absences", []):
		if int(a[0]) >= since:
			n += 1
	return n >= need

# Percent of the last 7 days you were here (f_here), for the Book header.
static func here_pct(farm: Dictionary, now_ms: int) -> int:
	return int(round(FE.f_here(farm, now_ms) * 100.0))

# ── crops, Favorite ──

static func crop_name(id: String) -> String:
	if id == "":
		return ""
	return str(FE.crop_info(id).get("name", id))

static func crop_color(id: String) -> Color:
	if id == "":
		return Color(0.72, 0.5, 0.28)
	return Color(str(FE.crop_info(id).get("color", "#b87333")))

static func favorite_today(now_ms: int, tz_s: int) -> String:
	return FE.favorite(FE.day_index(now_ms, tz_s))

static func favorite_tomorrow(now_ms: int, tz_s: int) -> String:
	return FE.favorite(FE.day_index(now_ms, tz_s) + 1)

static func fav_mult() -> float:
	return float(FE.cfg()["favorite"].get("mult", 1.4))

# ── helpers and upgrades ──

static func huts_hired(farm: Dictionary) -> int:
	return int(farm["up"]["huts"])

static func hut_hat(k: int) -> Color:
	var hats: Array = FE.cfg()["huts"].get("hats", [])
	if k < 0 or hats.is_empty():
		return Color(0.8, 0.4, 0.3)
	return Color(str(hats[k % hats.size()]))

static func house_tier(farm: Dictionary) -> int:
	return int(farm["up"].get("house", 0))

static func house_name(tier: int) -> String:
	var names: Array = FE.cfg()["house"].get("names", [])
	return str(names[clampi(tier, 0, names.size() - 1)]) if not names.is_empty() else "House"

static func shift_s(farm: Dictionary) -> int:
	var h: Array = FE.cfg()["house"]["shift_h"]
	return int(float(h[clampi(house_tier(farm), 0, h.size() - 1)]) * 3600.0)

static func share_pct(farm: Dictionary) -> int:
	var sh: Array = FE.cfg()["share"]
	return int(round(float(sh[clampi(int(farm["up"]["share"]), 0, sh.size() - 1)][0]) * 100.0))

# Sprinklers bought but not yet on a fence.
static func sprinklers_in_stock(farm: Dictionary) -> int:
	return maxi(0, int(farm["up"]["sprinklers"]) - farm["sprinklers"].size())

# Price of the next sprinkler, or -1 when all are bought.
static func sprinkler_cost(farm: Dictionary) -> int:
	var sp: Array = FE.cfg()["sprinklers"]["costs"]
	var owned := int(farm["up"]["sprinklers"])
	return int(sp[owned]) if owned < sp.size() else -1

static func sprinkler_page(farm: Dictionary) -> int:
	return int(FE.cfg()["sprinklers"].get("page", 1))

# The Spudling line of a field card: who works here and on what terms.
static func hut_line(farm: Dictionary, i: int, now_ms: int, tz_s: int) -> String:
	var v := FE.field_view(farm, i, now_ms)
	if not v["hut"]:
		return ""
	var nm: String = v["hut_name"]
	var clockin := clockin_ms() / 60000
	var line := "%s works here · starts %d min after you leave · you keep %d%% of what they plant" % [
			nm, clockin, share_pct(farm)]
	if v["working"]:
		var w1 := int(farm["clock"]["last_input_ms"]) + clockin_ms() + shift_s(farm) * 1000
		line = "%s is working until %s · you keep %d%% of what they plant" % [nm, Fmt.clock(w1, tz_s),
				share_pct(farm)]
	elif v["napping"]:
		line = "%s is napping (shift over) · back to work 2 min after you leave" % nm
	return line

# Prize Strain ribbons: [{crop, tier}] for every crop with a tier, table order.
static func ribbons(farm: Dictionary) -> Array:
	var out: Array = []
	for c in FE.crops():
		var t := int(farm["up"]["strains"].get(c, 0))
		if t > 0:
			out.append({"crop": c, "tier": t})
	return out

static func ribbon_color(tier: int) -> Color:
	match tier:
		1: return Color(0.8, 0.5, 0.25)      # bronze
		2: return Color(0.78, 0.8, 0.85)     # silver
		3: return Color(1.0, 0.82, 0.25)     # gold
		_: return Color(0.3, 0.55, 0.95)     # blue

static func catalog_size() -> int:
	return FE.cfg()["catalog"].size()

# Achievement ids whose state condition holds (the caller unlocks them;
# unlock_achievement is idempotent).
static func achievements_due(farm: Dictionary) -> Array:
	var out: Array = []
	if int(farm["up"]["huts"]) >= 1:
		out.append("first_spudling")
	if int(farm["page"]) >= catalog_size():
		out.append("catalog_complete")
	for c in farm["up"]["strains"]:
		if int(farm["up"]["strains"][c]) >= 4:
			out.append("blue_ribbon")
			break
	if house_tier(farm) >= 3:
		out.append("manor")
	return out

# A short human outcome line for a caught butterfly.
static func butterfly_text(outcome: String, coins: int) -> String:
	match outcome:
		"bumper":
			return "Bumper Crop! Hand harvests pay x2 for %ds" % int(FE.cfg()["butterflies"].get("bumper_s", 30))
		"sunshower":
			return "Sunshower! Every crop grew %s" % Fmt.dur(int(FE.cfg()["butterflies"].get("sunshower_s", 120)))
	return "Lucky Penny! +%s c" % Fmt.coins(coins)
