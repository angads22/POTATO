extends MinigameBase

# Slice/Dice mechanic - classic sweeping bar, press SPACE at centre
# Bar sweeps across screen, player must hit SPACE when bar is at centre

const BAR_WIDTH = 50
const BAR_CENTRE = 25
const BAR_SPEED = 100  # pixels per second
const PERFECT_RANGE = 2  # pixels from centre
const GREAT_RANGE = 5
const GOOD_RANGE = 10

var bar_position: float = 0.0
var bar_direction: int = 1  # 1 for right, -1 for left
var has_cut: bool = false
var bar_rect: Rect2

func _ready():
	bar_position = 0.0
	bar_rect = Rect2(100, 300, BAR_WIDTH, 40)

func start_minigame(potato: Dictionary):
	super.start_minigame(potato)
	has_cut = false
	bar_position = 0.0
	bar_direction = 1

func _process(delta):
	if not is_active or has_cut:
		return

	# Move bar
	bar_position += bar_direction * BAR_SPEED * delta

	# Bounce at edges
	if bar_position <= 0 or bar_position >= BAR_WIDTH - 1:
		bar_direction *= -1

	# Check timeout (5 seconds to make a cut)
	if cut_result.time_taken > 5.0:
		cut_result.quality = "MISS"
		cut_result.score_multiplier = 0.0
		end_minigame()

func _on_primary_input():
	if has_cut:
		return

	has_cut = true

	# Calculate distance from centre
	var distance = abs(bar_position - BAR_CENTRE)

	if distance <= PERFECT_RANGE:
		cut_result.quality = "PERFECT"
		cut_result.score_multiplier = 1.5
	elif distance <= GREAT_RANGE:
		cut_result.quality = "GREAT"
		cut_result.score_multiplier = 1.25
	elif distance <= GOOD_RANGE:
		cut_result.quality = "GOOD"
		cut_result.score_multiplier = 1.0
	else:
		cut_result.quality = "MISS"
		cut_result.score_multiplier = 0.0

	cut_result.animation_trigger = "slice_" + cut_result.quality.to_lower()
	end_minigame()

func _on_secondary_input():
	# Not used in slice mechanic
	pass

func draw_bar():
	# Visual representation of the bar
	# This will be called from the gameplay scene's _draw
	pass
