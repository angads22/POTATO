extends MinigameBase

# Speed Cut mechanic - sweet spot shrinks over time, must commit fast
# The window for a successful cut gets smaller and smaller

const INITIAL_WINDOW = 20
const SHRINK_RATE = 5  # pixels per second
const MIN_WINDOW = 3

var current_window: float = INITIAL_WINDOW
var target_position: float = 25
var has_cut: bool = false

func start_minigame(potato: Dictionary):
	super.start_minigame(potato)
	current_window = INITIAL_WINDOW
	has_cut = false

func _process(delta):
	if not is_active or has_cut:
		return

	# Shrinking window
	current_window = max(MIN_WINDOW, current_window - SHRINK_RATE * delta)

	# Auto-fail if too much time passes
	if cut_result.time_taken > 3.0:
		cut_result.quality = "FAIL"
		cut_result.score_multiplier = 0.0
		end_minigame()

func _on_primary_input():
	if has_cut:
		return

	has_cut = true

	# Simulate cursor position (0-50, where 25 is centre)
	var cursor_pos = randf_range(target_position - current_window / 2, target_position + current_window / 2)
	var distance = abs(cursor_pos - target_position)

	if distance < MIN_WINDOW:
		cut_result.quality = "PERFECT"
		cut_result.score_multiplier = 1.5
	elif distance < current_window * 0.3:
		cut_result.quality = "GREAT"
		cut_result.score_multiplier = 1.25
	elif distance < current_window:
		cut_result.quality = "GOOD"
		cut_result.score_multiplier = 1.0
	else:
		cut_result.quality = "MISS"
		cut_result.score_multiplier = 0.0

	cut_result.animation_trigger = "speed_cut_" + cut_result.quality.to_lower()
	end_minigame()

func _on_secondary_input():
	pass
