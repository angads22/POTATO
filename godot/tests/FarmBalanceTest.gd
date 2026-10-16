extends Node

# Spudling Acres balance gate (design §10.5 "FarmBalanceTest"). Pure
# FarmEconomy, no farm scene: FarmBot profile players (tests/farm/FarmBot.gd)
# play the REAL economy on farm.json with an injected clock, and FarmSuite
# (tests/farm/FarmSuite.gd) checks:
#   - §6.3 milestone windows (14 days class/casual, 10 sessions active)
#   - §6.2 feel targets (first coins, Pip, 6 buys in 15 min, class day 1)
#   - SD1 SD2 SD4 SD6 SD7 SD8 and a reduced SD3 tournament (5 x 3 x 7 days)
#   - §5.12 invariants 2-8 (bulk == stepped with a JSON round trip, shift
#     cap, nothing lost, hut safety, no deadlock, 7-day settle < 100 ms,
#     determinism), bankroll (10K start: pages <= 25% earlier), the veteran
#     landing, and 60-day magnitudes
# Prints its tables, then "FARM BALANCE OK", or "FARM BALANCE FAIL: <n>
# failures" followed by each failure. Runs synchronously in _ready (~30 s).
# It never touches SaveDataManager or user://.
#
#   godot --headless --path . res://tests/FarmBalanceTest.tscn --quit-after 6000
#
# The same checks (and the full-length §6.3 table, SD5, SD9) are in the tuning
# CLI: godot --headless --path . -s tests/farm/farm_sim.gd -- --all

const FE = preload("res://scripts/farm/FarmEconomy.gd")
const FarmSuite = preload("res://tests/farm/FarmSuite.gd")

const BUDGET_S := 90.0

func _ready() -> void:
	var t0 := Time.get_ticks_msec()
	FE.reload_cfg()
	var s = FarmSuite.new()
	FarmSuite.run_ci_set(s)
	FE.reload_cfg()
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	print("")
	print("farm balance runtime %.1f s (budget %d s)" % [secs, int(BUDGET_S)])
	if secs > BUDGET_S:
		s.fail("runtime", "%.1f s > %d s" % [secs, int(BUDGET_S)])
	if s.fails.is_empty():
		print("FARM BALANCE OK")
		get_tree().quit(0)
	else:
		print("FARM BALANCE FAIL: %d failures" % s.fails.size())
		for f in s.fails:
			print("  - " + f)
		get_tree().quit(1)
