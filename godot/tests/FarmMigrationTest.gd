extends Node

# Headless test for the farm save plumbing (design §9, §7.6, §8, §10.5.15-16):
#   - schema-1, schema-2 and schema-3 saves chain to schema 4 on load;
#   - the §10.5.15 schema-3 fixture lands with wallet == old wallet + the exact
#     refund sum, 3 fields, page 3 (Purple), huts on the migrated fields, the
#     Copper Hoe, every legacy key erased, the raw file backed up once, and an
#     idempotent second load;
#   - a maxed v3 save refunds exactly the refundable research (§9.2 ~290K);
#   - a schema-4 save round-trips unchanged;
#   - three independent slots; save_farm() writes only farm.json;
#   - debounced saves (2 s, forced at 10 s), flush on focus-out / window close,
#     low-power mode on focus-out while a scene allows it;
#   - the 30 s heartbeat settles a started farm without stamping input;
#   - the Farm Picnic at the end of a kitchen run.
#
#   godot --headless --path . res://tests/FarmMigrationTest.tscn --quit-after 3000
#
# Prints "FARM MIGRATION OK" and exits 0, or "FARM MIGRATION FAIL" + the failed
# checks and exits 1. Needs a fresh user:// (CI always has one).

const FE = preload("res://scripts/farm/FarmEconomy.gd")
const FM = preload("res://scripts/farm/FarmMigration.gd")
const Clock = preload("res://scripts/farm/FarmClock.gd")
const Fmt = preload("res://scripts/utils/NumFmt.gd")
const GD = preload("res://scripts/utils/GameData.gd")

const T0 := 1760000000000          # a fixed unix ms for the clock-driven checks
const LEGACY_KEYS := ["tiles", "plow_uses", "plows_bought", "plow_mode", "cover_freebies", "water", "items",
		"research", "research_points", "truck", "seed_order", "fertilizer_order", "seeds", "spuds",
		"sprinkler_stock", "sections_owned", "plots", "plots_owned", "tools"]

var fails: Array = []
var checks := 0

func _ready() -> void:
	# headless runs uncapped; pin a frame rate so the timed checks fit --quit-after
	Engine.max_fps = 60
	_run.call_deferred()

func _run() -> void:
	_test_legacy_data()
	_test_schema1()
	_test_schema2()
	_test_schema3_fixture()
	_test_veteran()
	_test_small_v3()
	_test_schema4_roundtrip()
	_test_slots()
	await _test_debounce()
	_test_focus_and_low_power()
	_test_heartbeat()
	_test_picnic()
	_test_misc()
	Clock.reset()
	_finish()

# ── helpers ──

func _check(ok: bool, what: String) -> void:
	checks += 1
	if not ok:
		fails.append(what)

func _slot_file(name: String) -> String:
	return SaveDataManager.SAVE_PATH + "slot%d/" % SaveDataManager.current_slot + name

func _read(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	return parsed if parsed is Dictionary else {}

# Put a raw (old) farm.json in the current slot, with no backup yet.
func _write_raw(d: Dictionary) -> void:
	DirAccess.remove_absolute(_slot_file(SaveDataManager.FARM_BACKUP_FILE))
	SaveDataManager._save_json(SaveDataManager.FARM_FILE, d)

func _legacy_gone(f: Dictionary, label: String) -> void:
	var left: Array = []
	for k in LEGACY_KEYS:
		if f.has(k):
			left.append(k)
	_check(left.is_empty(), "%s: legacy keys erased (left: %s)" % [label, str(left)])

func _owned(f: Dictionary) -> Array:
	var out: Array = []
	for i in f["fields"].size():
		if f["fields"][i]["owned"]:
			out.append(i)
	return out

func _huts(f: Dictionary) -> Array:
	var out: Array = []
	for i in f["fields"].size():
		if f["fields"][i]["hut"]:
			out.append([i, int(f["fields"][i]["hut_k"])])
	return out

# Strict deep equality (types included: an int that comes back a float is a
# difference). Appends "path: a != b" lines to diffs.
func _same(a, b, path: String, diffs: Array) -> void:
	if diffs.size() > 12:
		return
	if typeof(a) != typeof(b):
		diffs.append("%s: %s (%s) != %s (%s)" % [path, str(a), type_string(typeof(a)), str(b), type_string(typeof(b))])
		return
	if a is Dictionary:
		var ka: Array = a.keys()
		var kb: Array = b.keys()
		for k in ka:
			if not b.has(k):
				diffs.append("%s.%s: missing after reload" % [path, str(k)])
			else:
				_same(a[k], b[k], "%s.%s" % [path, str(k)], diffs)
		for k in kb:
			if not a.has(k):
				diffs.append("%s.%s: new after reload" % [path, str(k)])
	elif a is Array:
		if a.size() != b.size():
			diffs.append("%s: size %d != %d" % [path, a.size(), b.size()])
			return
		for i in a.size():
			_same(a[i], b[i], "%s[%d]" % [path, i], diffs)
	elif a != b:
		diffs.append("%s: %s != %s" % [path, str(a), str(b)])

# ── legacy tables (frozen v3 data) ──

func _test_legacy_data() -> void:
	_check(GD.legacy_research_nodes().size() == 87, "legacy: 87 v3 research nodes")
	_check(GD.legacy_items().get("enhancers", []).size() == 3 and GD.legacy_items().get("tools", []).size() == 2,
			"legacy: v3 items (2 tools, 3 fertilizers)")
	_check(GD.legacy_crops().size() == 7, "legacy: 7 v3 crops")
	var clean := true
	for p in GD.potatoes():
		for k in ["seed_cost", "grow_time", "sell_value", "yield"]:
			if p.has(k):
				clean = false
	_check(clean, "potatoes.json keeps only kitchen fields")
	_check(GD.potato_by_id("golden").get("chance", 0.0) > 0.0, "potatoes.json kitchen fields untouched")

# ── schema 1 -> 4 ──

func _test_schema1() -> void:
	# fixed 6-plot field: a growing Russet, a bare plot remembering Yukon, the
	# old global sprinkler (-> 2 placeable) and the harvest drone (-> Spud-Bot)
	var old := {
		"wallet": 300, "seeds": {"russet": 4}, "owned_knives": ["butter"], "equipped_knife": "butter",
		"plots": [{"potato_id": "russet", "planted_at": 1700000000.0, "watered": false},
				{"last": "yukon_gold"}, {}, {}, {}, {}],
		"plots_owned": 6, "tools": ["sprinkler", "harvest_drone"],
	}
	_write_raw(old)
	SaveDataManager.load_game()
	var f: Dictionary = SaveDataManager.farm
	_check(f["schema"] is int and f["schema"] == 4, "s1: upgrades to schema 4")
	# seeds 4x10 + 2 sprinklers x250 + 10 plow uses x15 + 1 Russet plot x6x3
	_check(SaveDataManager.wallet() == 300 + 40 + 500 + 150 + 18, "s1: wallet + refund (got %d)" % SaveDataManager.wallet())
	_check(_owned(f) == [0], "s1: 2 plowed tiles -> 1 field")
	_check(_huts(f) == [[0, 0]] and f["up"]["huts"] == 1, "s1: drone -> Spud-Bot -> Pip's hut on Field 1")
	_check(f["page"] == 0 and f["unlocked"] == ["russet"], "s1: no crop research -> page 0")
	_check(f["clock"]["epoch_ms"] == 0, "s1: not started (start() runs on the next visit)")
	_legacy_gone(f, "s1")
	_check(_read(_slot_file(SaveDataManager.FARM_BACKUP_FILE)).has("plots"), "s1: raw schema-1 file backed up")
	_check(int(_read(_slot_file(SaveDataManager.FARM_FILE)).get("schema", 0)) == 4, "s1: schema 4 written")

# ── schema 2 -> 4 ──

func _test_schema2() -> void:
	# the v4.0.0 smoke test's schema-2 save: a watered Red mid-growth, a bare
	# plot remembering Yukon, purple spuds, a drone, compost, a spare sprinkler
	var old := {
		"schema": 2, "wallet": 777, "seeds": {"russet": 2}, "spuds": {"purple": 4},
		"water": 2, "owned_knives": ["butter", "paring"], "equipped_knife": "paring",
		"sections_owned": 2,
		"tiles": {
			"0:0:0": {"plowed": true, "potato_id": "red", "planted_at": 1700000000.0,
					"watered": true, "boost": 0.7, "bonus_yield": 0, "last": "red"},
			"0:0:1": {"plowed": true, "last": "yukon_gold"},
		},
		"plow_uses": 5, "plows_bought": 1, "sprinkler_stock": 1,
		"tools": ["harvest_drone"], "items": {"compost": 2},
	}
	_write_raw(old)
	SaveDataManager.load_game()
	var f: Dictionary = SaveDataManager.farm
	_check(f["schema"] == 4, "s2: upgrades to schema 4")
	# seeds 2x10 + 4 purple x21 + 1 Red plot x14x3 + compost 2x15 + 1 sprinkler x250 + 5 plow uses x15
	_check(SaveDataManager.wallet() == 777 + 20 + 84 + 42 + 30 + 250 + 75,
			"s2: wallet + refund (got %d)" % SaveDataManager.wallet())
	# 2 -> 3 unlocked every crop the player owned (red, purple): page 3
	_check(f["page"] == 3 and "purple" in f["unlocked"] and "red" in f["unlocked"], "s2: owned crops -> page 3")
	_check(_owned(f) == [0] and _huts(f) == [[0, 0]], "s2: 1 field with Pip's hut")
	_check(f["owned_knives"] == ["butter", "paring"] and f["equipped_knife"] == "paring", "s2: knives kept")
	_legacy_gone(f, "s2")

# ── schema 3 -> 4: the §10.5.15 fixture ──

func _fixture_v3(wallet: int) -> Dictionary:
	var tiles := {
		"10:6": {"plowed": true, "potato_id": "red", "planted_at": 1759999000.0, "watered": false,
				"boost": 1.0, "bonus_yield": 0, "last": "red"},                                    # growing
		"11:6": {"plowed": true, "potato_id": "purple", "planted_at": 1700000000.0, "watered": true,
				"boost": 1.0, "bonus_yield": 0, "last": "purple"},                                 # ripe
		"12:6": {"plowed": true, "potato_id": "purple", "planted_at": 1700000000.0, "watered": false,
				"boost": 0.7, "bonus_yield": 2, "last": "purple"},                                 # ripe
		"13:6": {"plowed": true, "potato_id": "golden", "planted_at": 1700000000.0, "watered": false,
				"boost": 1.0, "bonus_yield": 0, "last": "golden"},                                 # ripe
		"14:6": {"sprinkler": true, "plowed": true},
		"15:6": {"sprinkler": true, "plowed": true},
	}
	for i in 24:   # 24 more plowed tiles: 30 in all
		tiles["%d:%d" % [5 + i % 12, 8 + i / 12]] = {"plowed": true, "last": "russet"} if i % 3 == 0 else {"plowed": true}
	return {
		"schema": 3, "wallet": wallet,
		"seeds": {"russet": 3, "red": 2}, "spuds": {"yukon_gold": 5, "purple": 4}, "water": 3,
		"owned_knives": ["butter", "paring", "santoku"], "equipped_knife": "santoku",
		"tiles": tiles, "plow_uses": 7, "plows_bought": 2, "plow_mode": "3x3", "cover_freebies": 5,
		"sprinkler_stock": 1, "items": {"compost": 4, "super_grow": 2, "miracle_mulch": 1},
		"research_points": 37,
		# crop_purple + tool_autoharvest + logi_cap1 per §10.5.15, plus tool_radius
		# (§9.2 grants the Copper Hoe for tool_radius*, which the fixture expects)
		"research": {"crop_purple": true, "tool_autoharvest": true, "logi_cap1": true, "tool_radius": true},
		"truck": {"status": "away", "cargo": {"red": 10}, "return_at": 1700000100.0,
				"pending_coins": 168, "pending_rp": 2},
		"seed_order": {"enabled": true, "crops": ["russet", "yukon_gold"], "stock_target": 5},
		"fertilizer_order": {"enabled": true, "grade": "compost", "stock_target": 3},
	}

# logi_cap1 300+10x3 · 37 RP x10 · seeds 3x10+2x26 · spuds 5x9+4x21 · truck
# away 168+2x10 (its cargo is already in pending_coins) · in the ground: Red
# 1x14x3, Purple 2x21x3.5, Golden 1x110x2.5 · fertilizer 4x15+2x40+1x75 ·
# sprinklers (2 placed + 1 stock) x250 · plow 7x15
const FIXTURE_REFUND := 330 + 370 + 82 + 129 + 188 + (42 + 147 + 275) + 215 + 750 + 105

func _test_schema3_fixture() -> void:
	_check(FIXTURE_REFUND == 2633, "fixture: refund arithmetic")
	var old := _fixture_v3(1234)
	_write_raw(old)
	var writes0 := SaveDataManager.farm_writes
	SaveDataManager.load_game()
	var f: Dictionary = SaveDataManager.farm
	_check(f["schema"] == 4, "s3: upgrades to schema 4")
	_check(SaveDataManager.wallet() == 1234 + FIXTURE_REFUND,
			"s3: wallet == old + exact refund (%d, want %d)" % [SaveDataManager.wallet(), 1234 + FIXTURE_REFUND])
	var mig: Dictionary = f.get("migration", {})
	_check(mig.get("refund") is int and mig["refund"] == FIXTURE_REFUND, "s3: ledger refund (int) == %d" % FIXTURE_REFUND)
	_check(FM.ledger_sum(mig) == FIXTURE_REFUND, "s3: ledger lines sum to the refund")
	_check(_owned(f) == [0, 1, 2], "s3: 30 plowed tiles -> 3 fields (got %s)" % str(_owned(f)))
	var empty := true
	for i in _owned(f):
		if f["fields"][i]["crop"] != "" or f["fields"][i]["plan"] != "russet":
			empty = false
	_check(empty, "s3: migrated fields are empty with plan Russet")
	_check(f["page"] == 3 and "purple" in f["unlocked"] and not "fingerling" in f["unlocked"],
			"s3: crop_purple -> page 3, Purple unlocked")
	_check(_huts(f) == [[0, 0], [1, 1], [2, 2]] and f["up"]["huts"] == 3, "s3: Spud-Bot -> huts on the 3 migrated fields")
	_check(f["up"]["tool"] == 1, "s3: tool_radius -> Copper Hoe")
	_check(f["sprinklers"].is_empty() and f["up"]["sprinklers"] == 0, "s3: no fence sprinklers granted")
	_check(f["owned_knives"] == ["butter", "paring", "santoku"] and f["equipped_knife"] == "santoku", "s3: knives kept")
	_check(f["clock"]["epoch_ms"] == 0, "s3: clock epoch 0 (start() on the next visit)")
	_legacy_gone(f, "s3")
	# the raw file was copied once, then schema 4 written over it
	var bak := _read(_slot_file(SaveDataManager.FARM_BACKUP_FILE))
	_check(int(bak.get("schema", 0)) == 3 and int(bak.get("wallet", 0)) == 1234 and bak.has("research"),
			"s3: backup slotN/farm.schema3.json holds the raw schema-3 save")
	var disk := _read(_slot_file(SaveDataManager.FARM_FILE))
	_check(int(disk.get("schema", 0)) == 4 and not disk.has("tiles"), "s3: farm.json rewritten as schema 4")
	_check(SaveDataManager.farm_writes == writes0 + 1, "s3: one write for the migration")
	# idempotent: loading again changes nothing and writes nothing
	var snap: Dictionary = f.duplicate(true)
	SaveDataManager.load_game()
	var diffs: Array = []
	_same(snap, SaveDataManager.farm, "farm", diffs)
	_check(diffs.is_empty(), "s3: second load is identical: %s" % str(diffs))
	_check(SaveDataManager.farm_writes == writes0 + 1, "s3: second load writes nothing")
	# Pip's first note carries the ledger once
	var rep: Dictionary = FE.take_report(SaveDataManager.farm)
	_check(int(rep.get("migration", {}).get("refund", -1)) == FIXTURE_REFUND, "s3: take_report returns the ledger")
	_check(rep.get("helpers", []) == ["Pip", "Dot", "Rusty"], "s3: huts named in hire order")
	_check(SaveDataManager.farm["migration"].is_empty(), "s3: take_report clears the ledger")
	# the backup is written ONCE: a second old save in this slot doesn't replace it
	SaveDataManager._save_json(SaveDataManager.FARM_FILE, _fixture_v3(999))
	SaveDataManager.load_game()
	_check(SaveDataManager.wallet() == 999 + FIXTURE_REFUND, "s3: re-migrates a newly written v3 file")
	_check(int(_read(_slot_file(SaveDataManager.FARM_BACKUP_FILE)).get("wallet", 0)) == 1234,
			"s3: the first backup is kept")
	# a pure migrate_v3 call agrees and leaves the raw dict alone
	var raw2 := _fixture_v3(1234)
	var m2: Dictionary = FM.migrate_v3(raw2, GD.legacy_tables())
	_check(int(m2["wallet"]) == 1234 + FIXTURE_REFUND and raw2.has("tiles") and int(raw2["wallet"]) == 1234,
			"s3: migrate_v3 is pure")

# ── a maxed v3 save (design §9.2: ~290K refund, full Catalog, Copper, 3 huts) ──

func _test_veteran() -> void:
	var research := {}
	for n in GD.legacy_research_nodes():
		research[n["id"]] = true
	var tiles := {}
	for i in 60:
		tiles["%d:%d" % [i % 20, i / 20]] = {"plowed": true}
	_write_raw({"schema": 3, "wallet": 0, "research": research, "research_points": 0, "tiles": tiles,
			"plow_uses": 0, "seeds": {}, "spuds": {}})
	SaveDataManager.load_game()
	var f: Dictionary = SaveDataManager.farm
	# 78 refundable nodes: 264,600 c + 10 x 2,813 RP (crop pages, Spud-Bot and
	# the three plow-radius nodes are kept as unlocks, not refunded)
	_check(SaveDataManager.wallet() == 292730, "veteran: refund 292,730 (got %d)" % SaveDataManager.wallet())
	_check(f["page"] == 6 and "golden" in f["unlocked"], "veteran: full Catalog")
	_check(_owned(f) == [0, 1, 2, 3], "veteran: fields capped at 4")
	_check(f["up"]["huts"] == 3 and f["up"]["tool"] == 1, "veteran: 3 huts + Copper")
	_check(not f["fields"][6]["owned"], "veteran: no Greenhouse")

func _test_small_v3() -> void:
	_write_raw({"schema": 3, "wallet": 10, "research": {"tool_autoharvest": true}})
	SaveDataManager.load_game()
	var f: Dictionary = SaveDataManager.farm
	_check(SaveDataManager.wallet() == 10 and int(f["migration"].get("refund", -1)) == 0, "small v3: nothing to refund")
	_check(_owned(f) == [0] and _huts(f) == [[0, 0]] and f["up"]["tool"] == 0,
			"small v3: Spud-Bot alone -> 1 hut, no Copper")
	_write_raw({"schema": 3, "wallet": 10, "research": {"tool_radius2": true, "crop_golden": true}})
	SaveDataManager.load_game()
	f = SaveDataManager.farm
	_check(f["up"]["tool"] == 1 and f["up"]["huts"] == 0 and f["page"] == 6 and SaveDataManager.wallet() == 10,
			"small v3: tool_radius2 -> Copper, crop_golden -> page 6, neither refunded")

# ── schema 4 round trip ──

func _test_schema4_roundtrip() -> void:
	var farm: Dictionary = FE.new_farm()
	FE.start(farm, T0, 3600)
	FE.tend(farm, 0, T0 + 1000, 3600)              # plant Russet
	FE.tend(farm, 0, T0 + 50000, 3600)             # harvest (stars) + replant
	FE.buy(farm, "hut", null, T0 + 51000, 3600)    # Pip
	FE.settle(farm, T0 + 3600000, 3600)            # an hour of Spudling work
	FE.note_input(farm, T0 + 3600000, 3600)
	SaveDataManager.farm = farm
	SaveDataManager.save_farm()
	var snap: Dictionary = farm.duplicate(true)
	SaveDataManager.load_game()
	var diffs: Array = []
	_same(snap, SaveDataManager.farm, "farm", diffs)
	_check(diffs.is_empty(), "s4: a schema-4 save round-trips unchanged: %s" % str(diffs))
	_check(int(farm["stats"]["spud_picks"]) > 0, "s4: the round-trip farm had Spudling work in it")

# ── three independent slots; save_farm writes only farm.json ──

func _test_slots() -> void:
	var fresh := int(FE.new_farm()["wallet"])
	SaveDataManager.save_game()
	var w1 := SaveDataManager.wallet()
	_check(SaveDataManager.switch_slot(2) and SaveDataManager.current_slot == 2, "slots: switch to slot 2")
	_check(SaveDataManager.wallet() == fresh and not SaveDataManager.farm_started(), "slots: an empty slot is a new farm")
	SaveDataManager.add_coins(123)
	_check(SaveDataManager.switch_slot(1) and SaveDataManager.wallet() == w1, "slots: slot 1 keeps its own wallet")
	_check(SaveDataManager.switch_slot(2) and SaveDataManager.wallet() == fresh + 123, "slots: slot 2 kept its balance")
	_check(SaveDataManager.slot_has_data(2) and not SaveDataManager.slot_has_data(3), "slots: has-data flags")
	_check(SaveDataManager.slot_summary(2) == "%s coins · 0 Chef XP" % Fmt.coins(fresh + 123),
			"slots: summary '%s'" % SaveDataManager.slot_summary(2))
	_check(SaveDataManager.slot_summary(1).begins_with(Fmt.coins(w1) + " coins"), "slots: summary uses NumFmt")
	# slot 3, untouched: save_farm() must write farm.json and nothing else
	_check(SaveDataManager.switch_slot(3), "slots: switch to slot 3")
	var dir := SaveDataManager.SAVE_PATH + "slot3/"
	for fn in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute(dir + fn)
	SaveDataManager.farm["wallet"] = 4242
	SaveDataManager.save_farm()
	var files := Array(DirAccess.get_files_at(dir))
	_check(files == ["farm.json"], "save_farm writes only farm.json (got %s)" % str(files))
	_check(int(_read(dir + "farm.json").get("wallet", 0)) == 4242, "save_farm wrote the wallet")

# ── debounced saving ──

func _test_debounce() -> void:
	var path := _slot_file(SaveDataManager.FARM_FILE)
	var w0 := SaveDataManager.farm_writes
	SaveDataManager.farm["wallet"] = 5000
	SaveDataManager.request_farm_save()
	_check(SaveDataManager.farm_dirty() and SaveDataManager.farm_writes == w0, "debounce: a request doesn't write at once")
	await get_tree().create_timer(0.6).timeout
	SaveDataManager.request_farm_save()        # a second request restarts the 2 s wait
	await get_tree().create_timer(1.6).timeout
	_check(SaveDataManager.farm_writes == w0 and int(_read(path)["wallet"]) == 4242,
			"debounce: nothing written 1.6 s after the last request")
	await get_tree().create_timer(0.8).timeout
	_check(SaveDataManager.farm_writes == w0 + 1 and not SaveDataManager.farm_dirty()
			and int(_read(path)["wallet"]) == 5000, "debounce: written 2 s after the last request")
	# requests every frame never settle the debounce: the 10 s cap forces a write
	SaveDataManager.farm["wallet"] = 5100
	SaveDataManager.request_farm_save()
	SaveDataManager._dirty_since_ms -= SaveDataManager.FARM_SAVE_FORCE_MS + 1   # pretend 10 s of requests
	SaveDataManager.request_farm_save()
	await get_tree().process_frame
	await get_tree().process_frame
	_check(SaveDataManager.farm_writes == w0 + 2 and int(_read(path)["wallet"]) == 5100,
			"debounce: forced write after 10 s dirty")
	SaveDataManager.flush_farm()
	_check(SaveDataManager.farm_writes == w0 + 2, "flush: nothing pending, nothing written")

# ── focus-out flush, window close flush, low-power mode ──

func _test_focus_and_low_power() -> void:
	var path := _slot_file(SaveDataManager.FARM_FILE)
	var fps0 := Engine.max_fps
	var low0 := OS.low_processor_usage_mode
	SaveDataManager.set_low_power_ok(true)
	SaveDataManager.farm["wallet"] = 6000
	SaveDataManager.request_farm_save()
	SaveDataManager.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not SaveDataManager.farm_dirty() and int(_read(path)["wallet"]) == 6000, "focus-out flushes the farm")
	_check(SaveDataManager.low_power_active() and Engine.max_fps == 10 and OS.low_processor_usage_mode,
			"focus-out enters low power (10 fps, low-processor mode)")
	SaveDataManager.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	_check(not SaveDataManager.low_power_active() and Engine.max_fps == fps0 and OS.low_processor_usage_mode == low0,
			"focus-in restores fps and processor mode")
	SaveDataManager.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	SaveDataManager.set_low_power_ok(false)
	_check(not SaveDataManager.low_power_active() and Engine.max_fps == fps0, "clearing the flag restores at once")
	SaveDataManager.notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	_check(not SaveDataManager.low_power_active() and Engine.max_fps == fps0, "no low power unless a scene allows it")
	SaveDataManager.notification(NOTIFICATION_APPLICATION_FOCUS_IN)
	SaveDataManager.farm["wallet"] = 6100
	SaveDataManager.request_farm_save()
	SaveDataManager.notification(NOTIFICATION_WM_CLOSE_REQUEST)
	_check(not SaveDataManager.farm_dirty() and int(_read(path)["wallet"]) == 6100, "window close flushes the farm")

# ── the 30 s heartbeat ──

func _test_heartbeat() -> void:
	Clock.tz_override = 0
	Clock.frozen_ms = T0
	SaveDataManager.farm = FE.new_farm()
	_check(SaveDataManager.heartbeat().is_empty(), "heartbeat: an unstarted farm is left alone")
	_check(SaveDataManager.farm["clock"]["epoch_ms"] == 0, "heartbeat: never starts the farm")
	var farm: Dictionary = SaveDataManager.farm
	FE.start(farm, T0, 0)
	FE.tend(farm, 0, T0, 0)                  # plant Russet (your crop)
	FE.buy(farm, "hut", 0, T0, 0)            # Pip on Field 1
	SaveDataManager.save_farm()
	var w0 := SaveDataManager.wallet()
	Clock.frozen_ms = T0 + 600000            # 10 minutes away (kitchen, menu...)
	var res := SaveDataManager.heartbeat()
	_check(int(res.get("coins", 0)) > 0 and int(res.get("picks", 0)) > 0, "heartbeat: Spudlings worked (%s)" % str(res))
	_check(SaveDataManager.wallet() == w0 + int(res.get("coins", 0)), "heartbeat: their coins are in the wallet")
	_check(farm["clock"]["last_input_ms"] == T0, "heartbeat: never stamps input")
	_check(farm["clock"]["last_settle_ms"] == T0 + 600000, "heartbeat: settled to now")
	_check(SaveDataManager.farm_dirty(), "heartbeat: requests a save when coins moved")
	SaveDataManager.flush_farm()
	var again := SaveDataManager.heartbeat()
	_check(int(again.get("coins", -1)) == 0 and not SaveDataManager.farm_dirty(), "heartbeat: idle settle requests nothing")

# ── Farm Picnic at the end of a kitchen run ──

func _test_picnic() -> void:
	var farm: Dictionary = SaveDataManager.farm    # started by the heartbeat test
	var gm = GameManager
	gm.start_game("endless")
	gm.current_state.coins_earned = 40
	gm.current_state.score = 2000
	gm.current_state.perfect = 10
	gm.run_play_seconds = 600.0                    # 10 played minutes
	var expect: int = FE.picnic_coins(farm, 600.0, 1.0)
	var w0 := SaveDataManager.wallet()
	gm.end_game(false)
	var st = gm.current_state
	_check(expect > 0 and st.last_picnic == expect, "picnic: %d coins (want %d)" % [st.last_picnic, expect])
	_check(is_equal_approx(st.picnic_min, 5.0), "picnic: 0.5 x 10 min x 100%% = 5 farm-min (got %s)" % str(st.picnic_min))
	_check(st.last_payout == 140 and SaveDataManager.wallet() == w0 + 140 + expect,
			"picnic: wallet = run payout + picnic")
	_check(int(_read(_slot_file(SaveDataManager.FARM_FILE))["wallet"]) == SaveDataManager.wallet(),
			"picnic: the payout is written at once")
	# a capped long run, and a farm that hasn't started
	gm.start_game("endless")
	gm.current_state.coins_earned = 10
	gm.current_state.perfect = 1
	gm.run_play_seconds = 7200.0
	gm.end_game(false)
	_check(is_equal_approx(gm.current_state.picnic_min, 15.0), "picnic: capped at 15 farm-min")
	SaveDataManager.farm = FE.new_farm()
	gm.start_game("endless")
	gm.current_state.coins_earned = 10
	gm.current_state.perfect = 1
	gm.run_play_seconds = 600.0
	gm.end_game(false)
	_check(gm.current_state.last_picnic == 0 and gm.current_state.picnic_min == 0.0, "picnic: 0 before the farm starts")
	# a run that banked nothing brings no picnic
	FE.start(SaveDataManager.farm, T0, 0)
	gm.start_game("endless")
	gm.run_play_seconds = 600.0
	gm.end_game(false)
	_check(gm.current_state.last_payout == 0 and gm.current_state.last_picnic == 0, "picnic: needs banked coins")

# ── cross-mode data and odds and ends ──

func _test_misc() -> void:
	var farm: Dictionary = FE.new_farm()
	farm["up"]["strains"] = {"red": 2, "golden": 1}
	SaveDataManager.farm = farm
	_check(is_equal_approx(SaveDataManager.kitchen_golden_bonus(), 0.012), "golden odds: +0.004 per Strain tier")
	_check(GD.knife_by_id("santoku").get("unlock_xp", 0) == 100 and GD.knife_by_id("chef").get("unlock_xp", 0) == 300
			and GD.knife_by_id("cleaver").get("unlock_xp", 0) == 700, "knives: Chef-XP gates 100/300/700")
	var names := {"first_spudling": "Hired Help", "catalog_complete": "Full Catalog", "blue_ribbon": "Blue Ribbon",
			"manor": "Manor Born"}
	for id in names:
		_check(GD.achievement_by_id(id).get("name", "") == names[id], "achievement %s" % id)
	_check(SaveDataManager.settings.has("sound_prompted") and SaveDataManager.settings.has("last_menu_item"),
			"settings: sound_prompted + last_menu_item defaults")
	for k in ["research_points", "add_research_points", "has_research", "unlock_research", "unlocked_crops",
			"research_bonus", "grow_time_mult", "research_flag", "add_item", "item_count"]:
		_check(not SaveDataManager.has_method(k), "SaveDataManager.%s removed" % k)
	_check(Fmt.coins(999) == "999" and Fmt.coins(12345) == "12.3K" and Fmt.coins(4560000) == "4.56M"
			and Fmt.dur(200) == "3m 20s", "NumFmt basics")

func _finish() -> void:
	if fails.is_empty():
		print("FARM MIGRATION OK — %d checks: schema 1/2/3 -> 4, refunds, backup, slots, saving, heartbeat, picnic" % checks)
		get_tree().quit(0)
	else:
		print("FARM MIGRATION FAIL (%d of %d checks):" % [fails.size(), checks])
		for f in fails:
			print("  - " + f)
		get_tree().quit(1)
