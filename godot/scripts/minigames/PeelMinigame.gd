extends MinigameBase

# Peel mechanic - tap to start rising fill, tap again to lock it
# Player must lock the fill at the correct height within the target zone

const FILL_SPEED = 50  # pixels per second
const TARGET_HEIGHT = 100
const TARGET_START = 150
const TARGET_END = 250

var current_fill: float = 0.0
var fill_started: bool = false
var fill_locked: bool = false
var target_zone_start: float = TARGET_START
var target_zone_end: float = TARGET_END

func start_minigame(potato: Dictionary):
	super.start_minigame(potato)
	current_fill = 0.0
	fill_started = false
	fill_locked = false

func _process(delta):
	if not is_active or not fill_started or fill_locked:
		return

	# Rising fill
	current_fill += FILL_SPEED * delta

	# Auto-fail if exceeds max height
	if current_fill >= 300:
		cut_result.quality = "FAIL"
		cut_result.score_multiplier = 0.0
		end_minigame()

func _on_primary_input():
	if fill_locked:
		return

	if not fill_started:
		# Start the fill
		fill_started = true
	else:
		# Lock the fill
		fill_locked = true

		# Calculate accuracy
		if current_fill >= target_zone_start and current_fill <= target_zone_end:
			if current_fill >= (target_zone_start + target_zone_end) / 2:
				cut_result.quality = "PERFECT"
				cut_result.score_multiplier = 1.5
			else:
				cut_result.quality = "GREAT"
				cut_result.score_multiplier = 1.25
		elif abs(current_fill - target_zone_start) < 20 or abs(current_fill - target_zone_end) < 20:
			cut_result.quality = "GOOD"
			cut_result.score_multiplier = 1.0
		else:
			cut_result.quality = "MISS"
			cut_result.score_multiplier = 0.0

		cut_result.animation_trigger = "peel_" + cut_result.quality.to_lower()
		end_minigame()

func _on_secondary_input():
	# Not used in peel mechanic
	pass
