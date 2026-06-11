extends MinigameBase

# Dodge mechanic - press X to bin a rotten potato (don't press SPACE!)
# Pressing SPACE on a rotten potato is a FAIL
# Pressing X correctly bins it (PERFECT)
# Doing nothing or pressing SPACE = FAIL

const DODGE_TIMEOUT = 3.0

var input_received: bool = false

func start_minigame(potato: Dictionary):
	super.start_minigame(potato)
	input_received = false

func _process(delta):
	if not is_active or input_received:
		return

	# Auto-fail if time runs out
	if cut_result.time_taken > DODGE_TIMEOUT:
		cut_result.quality = "MISS"
		cut_result.score_multiplier = 0.0
		end_minigame()

func _on_primary_input():
	# SPACE pressed on rotten potato = FAIL
	if not input_received:
		input_received = true
		cut_result.quality = "FAIL"
		cut_result.score_multiplier = 0.0
		cut_result.animation_trigger = "dodge_fail"
		end_minigame()

func _on_secondary_input():
	# X pressed = correctly bin the rotten potato
	if not input_received:
		input_received = true
		cut_result.quality = "PERFECT"
		cut_result.score_multiplier = 1.0
		cut_result.animation_trigger = "dodge_success"
		end_minigame()

# Override input handler for this mechanic
func _input(event: InputEvent):
	if not is_active:
		return

	if event is InputEventKey and event.pressed:
		if event.keycode == KEY_SPACE:
			_on_primary_input()
		elif event.keycode == KEY_X:
			_on_secondary_input()
