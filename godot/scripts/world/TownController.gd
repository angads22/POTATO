extends WorldController
class_name TownController

# The town: home of the seed shop, knife stand, tool shed and the championship
# kitchen — and the future home of any non-farming content. Selling has moved
# to the market truck on the farm, so there's no market stall here any more.
# The player arrives through the west gate from the farm, shops with the same
# overlay menus the farm hosts, and can walk into the kitchen to start a
# championship run directly.

var bg: TownBackground

func _ready():
	super._ready()
	_show_banner("POTATO TOWN")

func _world_size() -> Vector2:
	return TownBackground.WORLD

func _spawn_point() -> Vector2:
	if WorldController.travel_spawn == "from_farm":
		WorldController.travel_spawn = ""
		return Vector2(130, 560)
	return Vector2(960, 760)

func _build_world():
	bg = TownBackground.new()
	add_child(bg)
	world_bg = bg

	blockers = [
		TownBackground.KITCHEN_WALL.grow(6),
		TownBackground.SEED_STAND.grow(4),
		TownBackground.KNIFE_STAND.grow(4),
		TownBackground.TOOL_STAND.grow(4),
		TownBackground.COTTAGE_A.grow(6),
		TownBackground.COTTAGE_B.grow(6),
		TownBackground.FUTURE_LOT.grow(4),
		Rect2(TownBackground.FOUNTAIN_C - Vector2(60, 52), Vector2(120, 104)),
	]

func _scan_interactions():
	prompt = ""
	prompt_action = Callable()
	if open_shop != "":
		return

	var stations = [
		{"pos": TownBackground.SEED_STAND.get_center() + Vector2(0, 70), "r": 120.0,
			"text": "[E] Browse the seed shop", "act": func(): open_shop = "seeds"},
		{"pos": TownBackground.KNIFE_STAND.get_center() + Vector2(0, 70), "r": 120.0,
			"text": "[E] Browse the knife stand", "act": func(): open_shop = "knives"},
		{"pos": TownBackground.TOOL_STAND.get_center() + Vector2(0, 70), "r": 120.0,
			"text": "[E] Browse the tool shed", "act": func(): open_shop = "tools"},
		{"pos": Vector2(TownBackground.KITCHEN_WALL.get_center().x, TownBackground.KITCHEN_WALL.end.y + 30), "r": 120.0,
			"text": "[E] Enter the championship kitchen", "act": _enter_kitchen},
		{"pos": TownBackground.FARM_GATE_POS, "r": 110.0,
			"text": "[E] Take the road back to the farm", "act": _goto_farm},
	]
	for s in stations:
		if player.position.distance_to(s.pos) < s.r:
			prompt = s.text
			prompt_action = s.act
			return

func _enter_kitchen():
	GameManager.start_game("championship")
	AudioManager.stop_music(0.5)
	get_tree().change_scene_to_file("res://scenes/Gameplay/GameplayScene.tscn")

func _goto_farm():
	WorldController.travel_spawn = "from_town"
	WorldController.carry_day_t = day_t
	get_tree().change_scene_to_file("res://scenes/Farm/FarmScene.tscn")
