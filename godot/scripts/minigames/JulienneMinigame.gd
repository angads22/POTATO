extends MinigameBase

# Julienne mechanic - land two quick taps in sequence
# Both taps must be within the sweet spot, scored as the worse of the two

const PERFECT_WINDOW = 3
const GOOD_WINDOW = 8
const GREAT_WINDOW = 5

var first_cut_quality: String = ""
var first_cut_done: bool = false
var second_cut_timeout: float = 0.0

func start_minigame(potato: Dictionary):
	super.start_minigame(potato)
	first_cut_quality = ""
	first_cut_done = false

func _process(delta):
	if not is_active or not first_cut_done:
		return

	# Timer for second cut (must happen within 1 second)
	second_cut_timeout += delta
	if second_cut_timeout > 1.0:
		cut_result.quality = "MISS"
		cut_result.score_multiplier = 0.0
		end_minigame()

func _on_primary_input():
	if first_cut_done:
		# Second cut
		var second_quality = _evaluate_cut()

		# Take the worse of the two cuts
		var qualities = ["PERFECT", "GREAT", "GOOD", "MISS"]
		var first_rank = qualities.find(first_cut_quality)
		var second_rank = qualities.find(second_quality)
		var worse_rank = max(first_rank, second_rank)

		cut_result.quality = qualities[worse_rank]
		cut_result.score_multiplier = _get_multiplier(cut_result.quality)
		cut_result.animation_trigger = "julienne_" + cut_result.quality.to_lower()
		end_minigame()
	else:
		# First cut
		first_cut_quality = _evaluate_cut()
		first_cut_done = true

func _evaluate_cut() -> String:
	# Simulate cursor position accuracy
	var accuracy = randf()

	if accuracy > 0.9:
		return "PERFECT"
	elif accuracy > 0.7:
		return "GREAT"
	elif accuracy > 0.5:
		return "GOOD"
	else:
		return "MISS"

func _get_multiplier(quality: String) -> float:
	match quality:
		"PERFECT":
			return 1.5
		"GREAT":
			return 1.25
		"GOOD":
			return 1.0
		_:
			return 0.0

func _on_secondary_input():
	pass
