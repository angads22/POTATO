extends Node

# Headless farm-economy smoke test: drives the full loop — buy a seed,
# plant, water, time-travel to maturity, harvest, sell, buy a knife, bank a
# run payout — then checks persistence and the [E] interaction path.
# NOTE: writes to the user:// save like a real session would.
#
#   godot --headless --path . res://tests/FarmSmokeTest.tscn --quit-after 600

var frames := 0
var farm
var fails: Array[String] = []
var expected_wallet := 0

func _ready():
	# deterministic starting economy (rich enough to afford every tool)
	SaveDataManager.farm = {
		"wallet": 5000, "seeds": {}, "spuds": {}, "plots": [],
		"water": 0, "owned_knives": ["butter"], "equipped_knife": "butter"
	}
	farm = load("res://scenes/Farm/FarmScene.tscn").instantiate()
	add_child(farm)

func _check(cond: bool, what: String):
	if not cond:
		fails.append(what)

func _process(_delta):
	frames += 1
	match frames:
		10:
			_run_economy()
		20:
			_run_expansion_and_tools()
		30:
			# stand by the well with an empty can for the input probe
			SaveDataManager.farm["water"] = 0
			farm.player.position = FarmBackground.WELL_POS + Vector2(0, 60)
		40:
			_check(farm.prompt.begins_with("[E] Draw water"), "well prompt appears in range")
			_tap(KEY_E)
		50:
			_check(int(SaveDataManager.farm.get("water", 0)) == 4, "[E] at the well refills the can")
		60:
			_finish()

func _run_economy():
	expected_wallet = SaveDataManager.wallet()

	# buy a seed
	_check(farm.buy_seed("russet"), "seed purchase succeeds")
	expected_wallet -= 10
	_check(SaveDataManager.wallet() == expected_wallet, "seed purchase charges 10 coins")
	_check(SaveDataManager.item_count("seeds", "russet") == 1, "seed lands in inventory")

	# plant it
	var plot: FarmPlot = farm.plots[0]
	_check(farm.plant_on(plot, "russet"), "planting succeeds")
	_check(plot.state == FarmPlot.PState.PLANTED, "plot is planted")
	_check(SaveDataManager.item_count("seeds", "russet") == 0, "planting consumes the seed")

	# water it
	farm.fill_water()
	farm._water_plot(plot)
	_check(plot.watered, "plot is watered")
	_check(int(SaveDataManager.farm.get("water", 0)) == 3, "watering uses a charge")

	# time-travel to maturity and harvest
	plot.planted_at -= 10000.0
	_check(plot.progress() >= 1.0, "crop matures once grow_time passes")
	farm._harvest_plot(plot)
	var n = SaveDataManager.item_count("spuds", "russet")
	_check(n >= 2 and n <= 4, "harvest yields 2-4 potatoes (got %d)" % n)
	_check(plot.state == FarmPlot.PState.EMPTY, "harvest clears the plot")

	# sell the harvest
	var earned = farm.sell_spuds("russet")
	expected_wallet += n * 6
	_check(earned == n * 6, "spuds sell at 6 coins each")
	_check(SaveDataManager.wallet() == expected_wallet, "sale lands in the wallet")

	# buy + equip a knife, and confirm it multiplies the slicing score
	_check(farm.buy_or_equip_knife("paring"), "knife purchase succeeds")
	expected_wallet -= 150
	_check(SaveDataManager.farm.get("equipped_knife", "") == "paring", "knife auto-equips")
	GameManager.start_game("endless")
	var pts = GameManager.add_score(100, "NORMAL")
	_check(pts == 110, "paring knife multiplies score x1.1 (got %d)" % pts)

	# a finished run banks coins_earned + score/20 into the wallet
	GameManager.current_state.score = 400
	GameManager.current_state.coins_earned = 10
	GameManager.end_game(true)
	expected_wallet += 30
	_check(GameManager.current_state.last_payout == 30, "run payout is coins + score/20")
	_check(SaveDataManager.wallet() == expected_wallet, "payout lands in the wallet")

	# persistence round-trip
	SaveDataManager.save_game()
	SaveDataManager.farm["wallet"] = -123
	SaveDataManager.load_game()
	_check(SaveDataManager.wallet() == expected_wallet, "wallet survives save/load")
	var saved_plots: Array = SaveDataManager.farm.get("plots", [])
	_check(saved_plots.size() == farm.plots.size(), "plot states persist")

func _run_expansion_and_tools():
	# ── farm expansion ──
	_check(farm.plots[6].locked, "plot 7 starts locked")
	_check(farm.expand_cost() == 50, "first expansion costs 50")
	_check(farm.buy_plot(farm.plots[6]), "expansion purchase succeeds")
	expected_wallet -= 50
	_check(not farm.plots[6].locked, "bought plot unlocks")
	_check(farm.plots_owned() == 7, "plots_owned advances")
	_check(farm.expand_cost() == 90, "expansion price escalates")

	# ── tools ──
	_check(farm.buy_tool("sprinkler"), "sprinkler purchase succeeds")
	expected_wallet -= 350
	_check(farm.buy_tool("harvest_drone"), "drone purchase succeeds")
	expected_wallet -= 600
	_check(farm.buy_tool("auto_seeder"), "seeder purchase succeeds")
	expected_wallet -= 900
	_check(not farm.buy_tool("sprinkler"), "tools can't be bought twice")

	# ── growth enhancer on a fresh crop ──
	_check(farm.buy_enhancer("miracle_mulch"), "enhancer purchase succeeds")
	expected_wallet -= 90
	farm.buy_seed("russet")
	expected_wallet -= 10
	var plot: FarmPlot = farm.plots[1]
	farm.plant_on(plot, "russet")
	_check(farm.apply_enhancer(plot, "miracle_mulch"), "enhancer applies to a planted plot")
	_check(plot.boost == 0.45, "mulch boosts growth")
	_check(plot.bonus_yield == 2, "mulch adds bonus yield")
	_check(SaveDataManager.item_count("items", "miracle_mulch") == 0, "enhancer is consumed")
	_check(not plot.enhance(0.5, 0), "only one enhancer per crop")

	# ── auto-farming tick ──
	_check(not plot.watered, "fresh crop starts dry")
	farm._auto_farm()
	_check(plot.watered, "sprinkler auto-waters")
	plot.planted_at -= 10000.0
	plot.state = FarmPlot.PState.READY
	var before = SaveDataManager.item_count("spuds", "russet")
	farm._auto_farm()
	var pulled = SaveDataManager.item_count("spuds", "russet") - before
	_check(pulled >= 4 and pulled <= 6, "drone harvest includes the +2 mulch bonus (got %d)" % pulled)
	_check(plot.state == FarmPlot.PState.EMPTY, "drone clears the plot")
	# the seeder replants the first empty plot that grew something (plot 0)
	farm.buy_seed("russet")
	expected_wallet -= 10
	farm._auto_farm()
	_check(farm.plots[0].state == FarmPlot.PState.PLANTED and farm.plots[0].potato_id == "russet",
			"auto-seeder replants the last crop")

	_check(SaveDataManager.wallet() == expected_wallet, "wallet math holds through expansion & tools")

func _finish():
	if fails.is_empty():
		print("FARM SMOKE OK — wallet=%d spuds sold, knife equipped, save round-trips" % SaveDataManager.wallet())
		get_tree().quit(0)
	else:
		print("FARM SMOKE FAIL:")
		for f in fails:
			print("  - " + f)
		get_tree().quit(1)

func _tap(key: Key):
	var down = InputEventKey.new()
	down.keycode = key
	down.pressed = true
	get_tree().root.push_input(down)
	var up = InputEventKey.new()
	up.keycode = key
	up.pressed = false
	get_tree().root.push_input(up)
