extends Node2D
class_name MinigameBase

# Base class for all minigame mechanics
# Extend this for each cut type (Slice, Peel, Speed, Julienne, Dodge)

signal minigame_started
signal minigame_completed(result: Dictionary)  # {quality, score_multiplier, animation_trigger}

class CutResult:
	var quality: String  # "PERFECT", "GREAT", "GOOD", "MISS", "FAIL"
	var score_multiplier: float = 1.0
	var time_taken: float = 0.0
	var animation_trigger: String = ""

var potato_data: Dictionary  # Potato type and properties
var cut_result: CutResult = CutResult.new()
var timer_started: float = 0.0
var is_active: bool = false

# Virtual function to be implemented by subclasses
func _ready():
	pass

func start_minigame(potato: Dictionary):
	potato_data = potato
	timer_started = Time.get_ticks_msec()
	is_active = true
	minigame_started.emit()

func end_minigame():
	is_active = false
	cut_result.time_taken = (Time.get_ticks_msec() - timer_started) / 1000.0
	minigame_completed.emit({
		"quality": cut_result.quality,
		"multiplier": cut_result.score_multiplier,
		"animation": cut_result.animation_trigger
	})

# Timing calculation - if under 1.5s, apply GOOD+ multiplier
func check_quick_cut() -> bool:
	return cut_result.time_taken < 1.5

# To be overridden by specific minigame types
func _input(event: InputEvent):
	if not is_active:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			_on_primary_input()
		elif event.keycode == KEY_X:
			_on_secondary_input()

func _on_primary_input():
	# Override in subclass
	pass

func _on_secondary_input():
	# Override in subclass (for rotten potato dodge)
	pass
