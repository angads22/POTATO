extends MinigameBase
class_name DodgeMinigame

# Dodge — a rotten potato is on the board. Press X to bin it.
# Pressing SPACE slices it (FAIL); hesitating too long also costs you.

const DODGE_TIMEOUT = 2.5

var resolved: bool = false

func start_minigame(potato: Dictionary):
	super.start_minigame(potato)
	resolved = false

func _process(_delta):
	if not is_active or resolved:
		return
	if elapsed() > DODGE_TIMEOUT:
		resolved = true
		cut_result.quality = "MISS"
		cut_result.animation_trigger = "dodge_timeout"
		end_minigame()
	queue_redraw()

func _on_primary_input():
	# SPACE on a rotten potato — sliced it, FAIL
	if resolved:
		return
	resolved = true
	cut_result.quality = "FAIL"
	cut_result.animation_trigger = "dodge_fail"
	end_minigame()

func _on_secondary_input():
	# X — binned it correctly
	if resolved:
		return
	resolved = true
	cut_result.quality = "PERFECT"
	cut_result.score_multiplier = 1.0
	cut_result.animation_trigger = "dodge_success"
	end_minigame()

func _draw():
	if not is_active:
		return
	var font = ThemeDB.fallback_font
	var pulse = 0.5 + 0.5 * sin(elapsed() * 12.0)

	# red alarm tint + pulsing border
	draw_rect(Rect2(0, 0, 1280, 720), Color(0.8, 0.1, 0.1, 0.06 + pulse * 0.06))
	draw_rect(Rect2(8, 8, 1264, 704), Color(0.9, 0.15, 0.1, 0.4 + pulse * 0.4), false, 6.0)

	var warning = "ROTTEN POTATO!"
	var ws = font.get_string_size(warning, HORIZONTAL_ALIGNMENT_CENTER, -1, 42)
	draw_string(font, Vector2(640 - ws.x / 2, 130), warning, HORIZONTAL_ALIGNMENT_LEFT, -1, 42, Color.ORANGE_RED)

	# countdown bar draining left to right
	var frac = clampf(1.0 - elapsed() / DODGE_TIMEOUT, 0.0, 1.0)
	draw_rect(Rect2(438, 556, 404, 24), Color(1, 1, 1, 0.4), false, 2.0)
	draw_rect(Rect2(440, 558, 400.0 * frac, 20), Color.ORANGE_RED)

	draw_hint("[X] Bin it — do NOT press SPACE!")
