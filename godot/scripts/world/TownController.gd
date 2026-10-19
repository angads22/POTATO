extends WorldController
class_name TownController

# The town: storefronts for the farm (the seed stall opens the Farm Book on
# its Catalog tab, the tool shed on its Tools tab; they sell nothing extra,
# design §4.1), the knife stand, the championship kitchen, the Concert Hall
# bandstand and the gate back to the farm. Every station is clickable at any
# distance as well as [E]-able up close. Inputs here stamp presence too
# (WorldController.note_real_input), so Spudlings don't clock in while you
# shop, and the farm settles every 0.5 s like on the farm.
#
# Test hooks: station(id) for id in seeds, tools, knives, kitchen, concert,
# gate ({pos, rect, act}); open_book(tab); book (FarmBook); open_knives();
# hud.regions.rect_of("knife:<id>"). B (or the Book buttons) opens the Farm
# Book here too.

var bg: TownBackground

static var _banner_shown := false   # the welcome banner once per game session

func _ready():
	super._ready()
	if not _banner_shown:
		_banner_shown = true
		_show_banner("POTATO TOWN", "Seeds and tools open the Farm Book · knives · kitchen · concert")

func _world_size() -> Vector2:
	return TownBackground.WORLD

func _music_track() -> String:
	return "town"

func _spawn_point() -> Vector2:
	if WorldController.travel_spawn == "from_farm":
		WorldController.travel_spawn = ""
		return Vector2(130, 560)
	if WorldController.travel_spawn == "from_concert":
		WorldController.travel_spawn = ""
		return Vector2(TownBackground.CONCERT_HALL.get_center().x, TownBackground.CONCERT_HALL.position.y - 70)
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
		TownBackground.CONCERT_HALL.grow(4),
		Rect2(TownBackground.FOUNTAIN_C - Vector2(60, 52), Vector2(120, 104)),
	]
	stations = [
		{"id": "seeds", "pos": TownBackground.SEED_STAND.get_center() + Vector2(0, 70), "r": 120.0,
			"rect": TownBackground.SEED_STAND.grow(24),
			"text": "[E] Seed stall: the Seed Catalog (Farm Book)", "act": func(): open_book("catalog")},
		{"id": "knives", "pos": TownBackground.KNIFE_STAND.get_center() + Vector2(0, 70), "r": 120.0,
			"rect": TownBackground.KNIFE_STAND.grow(24),
			"text": "[E] Browse the knife stand", "act": open_knives},
		{"id": "tools", "pos": TownBackground.TOOL_STAND.get_center() + Vector2(0, 70), "r": 120.0,
			"rect": TownBackground.TOOL_STAND.grow(24),
			"text": "[E] Tool shed: hoes and sprinklers (Farm Book)", "act": func(): open_book("tools")},
		{"id": "kitchen", "pos": Vector2(TownBackground.KITCHEN_WALL.get_center().x, TownBackground.KITCHEN_WALL.end.y + 30),
			"r": 120.0, "rect": TownBackground.KITCHEN_WALL,
			"text": "[E] Enter the championship kitchen", "act": enter_kitchen},
		{"id": "concert", "pos": Vector2(TownBackground.CONCERT_HALL.get_center().x, TownBackground.CONCERT_HALL.position.y - 50),
			"r": 120.0, "rect": TownBackground.CONCERT_HALL,
			"text": "[E] Take the stage: play a CONCERT", "act": enter_concert},
		{"id": "gate", "pos": TownBackground.FARM_GATE_POS, "r": 110.0, "rect": Rect2(0, 470, 200, 160),
			"text": "[E] Take the road back to the farm", "act": goto_farm},
	]

func enter_kitchen():
	AudioManager.play_sfx("menu_select")
	GameManager.start_game("championship")
	get_tree().change_scene_to_file("res://scenes/Gameplay/GameplayScene.tscn")

func enter_concert():
	AudioManager.play_sfx("menu_select")
	ConcertController.return_scene = "res://scenes/Town/TownScene.tscn"
	WorldController.travel_spawn = "from_concert"
	get_tree().change_scene_to_file("res://scenes/Concert/ConcertScene.tscn")

func goto_farm():
	WorldController.travel_spawn = "from_town"
	AudioManager.play_sfx("gate")
	get_tree().change_scene_to_file("res://scenes/Farm/FarmScene.tscn")
