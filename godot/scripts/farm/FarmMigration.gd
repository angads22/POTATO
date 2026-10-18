extends RefCounted
class_name FarmMigration

# Farm save schema 3 (v4.0.0: open plow grid, research shed, truck) ->
# schema 4 (Spudling Acres), design §9.2. Static and PURE: no Time, no files,
# no nodes. SaveDataManager runs it on the RAW dict, at the end of its
# 1 -> 2 -> 3 -> 4 chain and before the defaults merge, and injects the frozen
# v3 tables (GameData.legacy_tables(): research_v3 / items_v3 / crops_v3), so
# later balance edits can never change how an old save lands.
#
# Principle: every coin spent on something that no longer exists comes back,
# everything grown is paid at its old value, every unlock earned stays earned.
#   kept      wallet, owned_knives, equipped_knife
#   unlocks   crop research -> Catalog page (red 2 .. golden 6), not refunded
#             tool_autoharvest (Spud-Bot) -> free huts on the migrated fields
#             (at most 3), not refunded
#             tool_radius* -> Copper Hoe, not refunded
#   refunds   every other owned research node: cost_coins + 10 x cost_rp
#             unspent research points x10
#             seeds: n x old seed price
#             cellar spuds and idle-truck cargo: n x old sell value (a spud is
#               one sold potato)
#             crops in the ground (any growth): plots x old sell value x old
#               average yield (as if harvested and sold)
#             truck away: pending_coins + 10 x pending_rp (its cargo is already
#               priced into pending_coins)
#             fertilizer: per charge = old bag price / charges (15 / 40 / 75)
#             placed sprinklers + sprinkler_stock: old price each (250)
#             plow_uses: old plow price / durability each (15)
#   land      plowed tiles P -> fields owned = clamp(1 + floor(P/12), 1, 4),
#             all empty with plan Russet
# The result is FarmEconomy.new_farm() with those values filled in (so every
# legacy key is gone), clock.epoch_ms = 0 so start() runs on the next visit,
# and the one-time ledger farm.migration = {refund, lines: [{label, coins}],
# kept: {fields, page, huts, copper}} that Pip's first note shows (and
# FarmEconomy.take_report() returns and clears).
#
# Other scripts are referenced only by path: SaveDataManager is an autoload,
# loaded before Godot's global class list exists on a fresh checkout.

const FE = preload("res://scripts/farm/FarmEconomy.gd")

const SCHEMA := 4
# Every schema-1..3 key that has no schema-4 meaning (the merge never removes
# keys, so these must not survive into the merged save).
const LEGACY_KEYS := ["tiles", "plow_uses", "plows_bought", "plow_mode", "cover_freebies", "water", "items",
		"research", "research_points", "truck", "seed_order", "fertilizer_order", "seeds", "spuds",
		"sprinkler_stock", "sections_owned", "plots", "plots_owned", "tools"]
# Frozen fallback for crop -> Catalog page (§9.2); the live catalog in farm.json
# wins when it lists the crop, so the researched crop is always unlocked.
const CROP_PAGE := {"yukon_gold": 1, "red": 2, "purple": 3, "fingerling": 4, "king_edward": 5, "golden": 6}
const HUT_NODE := "tool_autoharvest"
const COPPER_PREFIX := "tool_radius"
const PLOTS_PER_FIELD := 12
const MAX_FIELDS := 4
const MAX_FREE_HUTS := 3
const RP_COINS := 10
const COPPER_TIER := 1

# raw: a schema-3 farm dict straight from JSON (numbers may be floats).
# legacy: {research: [nodes], items: {tools: [...], enhancers: [...]}, crops: [...]}.
static func migrate_v3(raw: Dictionary, legacy: Dictionary) -> Dictionary:
	var research_tbl := _by_id(legacy.get("research", []))
	var crop_tbl := _by_id(legacy.get("crops", []))
	var items: Dictionary = legacy.get("items", {}) if legacy.get("items", {}) is Dictionary else {}
	var tool_tbl := _by_id(items.get("tools", []))
	var enh_tbl := _by_id(items.get("enhancers", []))
	var lines: Array = []
	var refund := 0

	# ── research: unlocks kept, everything else refunded ──
	var page := 0
	var huts_node := false
	var copper := false
	var node_coins := 0
	var node_count := 0
	var research = raw.get("research", {})
	if research is Dictionary:
		var ids: Array = research.keys()
		ids.sort()
		for id in ids:
			if not _truthy(research[id]):
				continue
			var node: Dictionary = research_tbl.get(str(id), {})
			if node.is_empty():
				continue  # unknown node: nothing to refund
			var eff = node.get("effect", {})
			if eff is Dictionary and eff.has("unlock_crop"):
				page = maxi(page, _page_for(str(eff["unlock_crop"])))
			elif str(id) == HUT_NODE:
				huts_node = true
			elif str(id).begins_with(COPPER_PREFIX):
				copper = true
			else:
				node_coins += _int(node.get("cost_coins", 0)) + RP_COINS * _int(node.get("cost_rp", 0))
				node_count += 1
	refund += _line(lines, "Research Shed: %d retired upgrade%s" % [node_count, _s(node_count)], node_coins)
	var rp := maxi(0, _int(raw.get("research_points", 0)))
	refund += _line(lines, "Unspent research points (%d RP x %d)" % [rp, RP_COINS], rp * RP_COINS)

	# ── inventories ──
	var seeds_n := 0
	var seeds_c := 0
	var seeds = raw.get("seeds", {})
	if seeds is Dictionary:
		for id in seeds:
			var n := maxi(0, _int(seeds[id]))
			seeds_n += n
			seeds_c += n * _int(crop_tbl.get(str(id), {}).get("seed_cost", 0))
	refund += _line(lines, "Seed pouch (%d seed%s)" % [seeds_n, _s(seeds_n)], seeds_c)
	var sp := _spud_value(raw.get("spuds", {}), crop_tbl)
	refund += _line(lines, "Cellar spuds (%d)" % sp[0], sp[1])

	var truck = raw.get("truck", {})
	if truck is Dictionary:
		if str(truck.get("status", "idle")) == "away":
			var tc := maxi(0, _int(truck.get("pending_coins", 0))) + RP_COINS * maxi(0, _int(truck.get("pending_rp", 0)))
			refund += _line(lines, "Market truck delivery", tc)
		else:
			var cg := _spud_value(truck.get("cargo", {}), crop_tbl)
			refund += _line(lines, "Truck cargo (%d spud%s)" % [cg[0], _s(cg[0])], cg[1])

	# ── the old grid: plowed land, crops in the ground, placed sprinklers ──
	var plowed := 0
	var placed := 0
	var planted := {}     # crop -> plots
	var tiles = raw.get("tiles", {})
	if tiles is Dictionary:
		for key in tiles:
			var td = tiles[key]
			if not td is Dictionary:
				continue
			if _truthy(td.get("plowed", false)):
				plowed += 1
			if _truthy(td.get("sprinkler", false)):
				placed += 1
			elif td.has("potato_id"):
				var c := str(td["potato_id"])
				planted[c] = int(planted.get(c, 0)) + 1
	var crop_n := 0
	var crop_c := 0
	var crops: Array = planted.keys()
	crops.sort()
	for c in crops:
		var info: Dictionary = crop_tbl.get(c, {})
		var y = info.get("yield", [0, 0])
		var ysum := (_int(y[0]) + _int(y[1])) if y is Array and y.size() >= 2 else 0
		crop_n += int(planted[c])
		# n x sell x average yield, rounded half up per crop
		crop_c += int(round(int(planted[c]) * _int(info.get("sell_value", 0)) * ysum / 2.0))
	refund += _line(lines, "Crops in the ground (%d plot%s, as if harvested)" % [crop_n, _s(crop_n)], crop_c)

	var fert_n := 0
	var fert_c := 0
	var bags = raw.get("items", {})
	if bags is Dictionary:
		for id in bags:
			var e: Dictionary = enh_tbl.get(str(id), {})
			var n := maxi(0, _int(bags[id]))
			if e.is_empty() or n == 0:
				continue
			fert_n += n
			fert_c += n * (_int(e.get("cost", 0)) / maxi(1, _int(e.get("charges", 1))))
	refund += _line(lines, "Fertilizer (%d charge%s)" % [fert_n, _s(fert_n)], fert_c)

	var spr_n := placed + maxi(0, _int(raw.get("sprinkler_stock", 0)))
	refund += _line(lines, "Sprinklers (%d)" % spr_n, spr_n * _int(tool_tbl.get("sprinkler", {}).get("cost", 0)))
	var plow: Dictionary = tool_tbl.get("plow", {})
	var uses := maxi(0, _int(raw.get("plow_uses", 0)))
	var per_use := _int(plow.get("base_cost", 0)) / maxi(1, _int(plow.get("durability", 1)))
	refund += _line(lines, "Plow uses (%d)" % uses, uses * per_use)

	# ── the schema-4 farm ──
	var out: Dictionary = FE.new_farm()
	var wallet := maxi(0, _int(raw.get("wallet", out["wallet"])))
	out["wallet"] = wallet + refund
	var knives = raw.get("owned_knives", null)
	if knives is Array and not knives.is_empty():
		var kl: Array = []
		for k in knives:
			if not str(k) in kl:
				kl.append(str(k))
		out["owned_knives"] = kl
	if raw.has("equipped_knife"):
		out["equipped_knife"] = str(raw["equipped_knife"])
	var nf := clampi(1 + plowed / PLOTS_PER_FIELD, 1, MAX_FIELDS)
	var fields: Array = out["fields"]
	for i in nf:
		fields[i]["owned"] = true
	var huts := mini(nf, MAX_FREE_HUTS) if huts_node else 0
	for i in huts:
		fields[i]["hut"] = true
		fields[i]["hut_k"] = i
	out["up"]["huts"] = huts
	if copper:
		out["up"]["tool"] = maxi(int(out["up"]["tool"]), COPPER_TIER)
	out["page"] = page
	out["clock"]["epoch_ms"] = 0
	out["migration"] = {"refund": refund, "lines": lines,
			"kept": {"fields": nf, "page": page, "huts": huts, "copper": copper}}
	FE.normalize(out)
	for k in LEGACY_KEYS:
		out.erase(k)
	return out

# JSON gives the ledger back as floats: int-cast it (SaveDataManager calls this
# after normalize on every load). Safe on an empty or missing ledger.
static func fix_ledger(farm: Dictionary) -> void:
	var m = farm.get("migration", {})
	if not m is Dictionary or m.is_empty():
		return
	m["refund"] = _int(m.get("refund", 0))
	var lines: Array = []
	var src = m.get("lines", [])
	if src is Array:
		for l in src:
			if l is Dictionary:
				lines.append({"label": str(l.get("label", "")), "coins": _int(l.get("coins", 0))})
	m["lines"] = lines
	var kept = m.get("kept", {})
	if kept is Dictionary:
		for key in ["fields", "page", "huts"]:
			if kept.has(key):
				kept[key] = _int(kept[key])
		if kept.has("copper"):
			kept["copper"] = _truthy(kept["copper"])

# The sum of every refund line (what the wallet gained).
static func ledger_sum(ledger: Dictionary) -> int:
	var t := 0
	for l in ledger.get("lines", []):
		t += _int(l.get("coins", 0))
	return t

# ── helpers ──

static func _page_for(crop: String) -> int:
	var cat = FE.cfg().get("catalog", [])
	if cat is Array:
		for p in cat.size():
			if str(cat[p].get("unlocks", "")) == crop:
				return p + 1
	return int(CROP_PAGE.get(crop, 0))

# [count, coins] for a {crop: n} spud dict at the old sell value per spud.
static func _spud_value(d, crop_tbl: Dictionary) -> Array:
	var n := 0
	var c := 0
	if d is Dictionary:
		for id in d:
			var k := maxi(0, _int(d[id]))
			n += k
			c += k * _int(crop_tbl.get(str(id), {}).get("sell_value", 0))
	return [n, c]

static func _line(lines: Array, label: String, coins: int) -> int:
	if coins > 0:
		lines.append({"label": label, "coins": coins})
		return coins
	return 0

static func _by_id(arr) -> Dictionary:
	var out := {}
	if arr is Array:
		for e in arr:
			if e is Dictionary and e.has("id"):
				out[str(e["id"])] = e
	return out

static func _int(v) -> int:
	match typeof(v):
		TYPE_INT, TYPE_FLOAT, TYPE_BOOL:
			return int(v)
		TYPE_STRING:
			return int(v) if str(v).is_valid_float() else 0
	return 0

static func _truthy(v) -> bool:
	match typeof(v):
		TYPE_BOOL:
			return v
		TYPE_INT, TYPE_FLOAT:
			return v != 0
		TYPE_STRING:
			return v != "" and v != "false"
	return v != null

static func _s(n: int) -> String:
	return "" if n == 1 else "s"
