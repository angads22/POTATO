extends SceneTree

# Spudling Acres balance simulator: the tuning instrument. It plays the REAL
# FarmEconomy (farm.json as shipped, or with --override) with the FarmBot
# profiles of design §6.1. Not part of CI (FarmBalanceTest is the gate).
#
#   godot --headless --path . -s tests/farm/farm_sim.gd -- --profile class --days 14 [--strategy roi] [--log]
#   godot --headless --path . -s tests/farm/farm_sim.gd -- --all
#
# Options
#   --profile active|class|casual|class+eve    (default class)
#   --days N                                   (default 14)
#   --strategy roi|tutorial|s1|s2|s3|s4        (default roi; s3 plants naive)
#   --planting greedy|naive|fixed:<crop>       (default greedy)
#   --wallet N                                 starting wallet (default 50; bankroll = 10000)
#   --log                                      purchase log + per-day table
#   --override '<json>'                        deep-merged into farm.json for this run
#                                              e.g. '{"soil": {"growth": 1.36}}' (arrays replace whole)
#   --all                                      §6.3 milestone table (full windows), §6.2 feel targets,
#                                              SD1-SD9 (SD3: 5 x 4 profiles x 14 days), invariants,
#                                              bankroll, veteran, 60-day magnitudes
#   --ci                                       the FarmBalanceTest set, printed here (no exit code)
#   --only a,b,...                             with --all/--ci: only these sections, from
#                                              main, feel, sdfix, sd4, sd3, sd5, sd8, sd9, inv, bank, vet, mag

const FE = preload("res://scripts/farm/FarmEconomy.gd")
const FarmBot = preload("res://tests/farm/FarmBot.gd")
const FarmSuite = preload("res://tests/farm/FarmSuite.gd")

func _initialize() -> void:
	var args := _parse(OS.get_cmdline_user_args())
	var t0 := Time.get_ticks_msec()
	if args.has("override"):
		var o = JSON.parse_string(str(args["override"]))
		if not o is Dictionary:
			print("bad --override JSON")
			quit(2)
			return
		FE.reload_cfg(o)
		print("override: ", JSON.stringify(o))
	if args.has("all") or args.has("ci"):
		var s = FarmSuite.new()
		if args.has("all"):
			run_all(s, args)
		else:
			run_ci(s)
		s.print_failures()
	else:
		run_one(args)
	print("\n(farm_sim %.1f s)" % ((Time.get_ticks_msec() - t0) / 1000.0))
	quit()

func _parse(argv: PackedStringArray) -> Dictionary:
	var out := {}
	var k := 0
	while k < argv.size():
		var a := argv[k]
		if a.begins_with("--"):
			var key := a.substr(2)
			if k + 1 < argv.size() and not argv[k + 1].begins_with("--"):
				out[key] = argv[k + 1]
				k += 1
			else:
				out[key] = true
		k += 1
	return out

func run_one(args: Dictionary) -> void:
	var b = FarmBot.new(str(args.get("profile", "class")), str(args.get("strategy", "roi")))
	var pl := str(args.get("planting", "greedy"))
	if pl.begins_with("fixed:"):
		b.planting = "fixed"
		b.fixed_crop = pl.substr(6)
	else:
		b.planting = pl
	b.start_wallet = int(args.get("wallet", 50))
	b.metric_afford = b.profile == "class"
	var days := int(args.get("days", 14))
	var t0 := Time.get_ticks_msec()
	b.run(days)
	var s: Dictionary = b.summary()
	print("%s · %s · %s planting · %d days · start %s c   (%d ms)" % [b.profile, b.strategy, b.planting, days,
			FarmSuite.coins(b.start_wallet), Time.get_ticks_msec() - t0])
	print("earned %s · wallet %s · lifetime %s · purchases %d · last-day income %s · hand %d%% · soil L%d · page %d" % [
			FarmSuite.coins(s["earned"]), FarmSuite.coins(s["wallet"]), FarmSuite.coins(s["lifetime"]), s["purchases"],
			FarmSuite.coins(s["income_last_day"]), int(round(s["hand_share"] * 100)), s["soil"], s["page"]])
	print("butterflies ", b.butterflies)
	print("hand plantings by crop ", b.hand_plants)
	print("Spudling picks by crop ", b.spud_picks)
	print("")
	print("milestones")
	for row in FarmSuite.MS:
		var k: int = ["active", "class", "casual"].find(b.profile)
		var spec = row[2 + k] if k >= 0 else null
		var su = FarmSuite.new()
		var verdict: String = su.judge(b, row[0], spec) if k >= 0 else ""
		print("   %-18s %-22s %-12s %s" % [row[1], b.milestone_text(row[0]), su.target_text(spec) if k >= 0 else "", verdict])
	if b.profile == "class" and not b.afford.is_empty():
		var yes := 0
		for a in b.afford:
			if a[1]:
				yes += 1
		print("   class d1 check-ins with a useful affordable buy: %d/%d" % [yes, b.afford.size()])
	if args.has("log"):
		print("")
		print("per day (at the day's first arrival; income = lifetime farm coins to the next day's)")
		FarmSuite.new().print_daily(b)
		print("")
		print("purchases (%d)" % b.purchases.size())
		for l in b.purchase_lines():
			print(l)
	if not b.violations.is_empty():
		print("")
		print("VIOLATIONS")
		for v in b.violations:
			print("  ", v)

var _only := []

func _on(name: String) -> bool:
	return _only.is_empty() or name in _only

func run_all(s, args: Dictionary) -> void:
	if args.has("only"):
		_only = str(args["only"]).split(",")
	var dm := {"active": 22, "class": 24, "casual": 22}
	if _on("main") or _on("sd8") or _on("sd9") or _on("sd5"):
		s.run_main(dm)
	if _on("main"):
		s.print_milestones()
		for p in ["active", "class", "casual"]:
			print("")
			print("-- %s per day   (hand plantings %s · Spudling picks %s)" % [p, str(s.main[p].hand_plants), str(s.main[p].spud_picks)])
			s.print_daily(s.main[p])
	if _on("feel"):
		s.feel()
	if _on("sdfix"):
		s.sd_fixtures(FarmSuite.ALL4)
	if _on("sd4"):
		s.sd4(FarmSuite.ALL4)
	if _on("sd3"):
		s.sd3(FarmSuite.ALL4, 14)
	if _on("sd5"):
		s.sd5(FarmSuite.ALL4, 14)
	if _on("sd8"):
		s.sd8()
	if _on("sd9"):
		s.sd9()
	if _on("inv"):
		s.invariants()
	if _on("bank"):
		s.bankroll({"active": 10, "class": 10, "casual": 10})
	if _on("vet"):
		s.veteran(14)
	if _on("mag"):
		s.magnitudes(60)

func run_ci(s) -> void:
	FarmSuite.run_ci_set(s)
