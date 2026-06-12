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
	# deterministic starting economy
	SaveDataManager.farm = {
		"wallet": 500, "seeds": {}, "spuds": {}, "plots": [],
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
