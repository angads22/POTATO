extends Node2D

# Game-over / results screen
# Shows the final score, lets the player submit to the leaderboard,
# and returns to the main menu.

var name_entry: String = ""
var submitted: bool = false
var earned_rank: int = -1

func _ready():
	AudioManager.play_sfx("game_over")
	queue_redraw()

func _input(event: InputEvent):
	if event is InputEventKey and event.pressed:
		if submitted:
			# Any key returns to the menu once a score is banked
			if event.keycode == KEY_SPACE or event.keycode == KEY_ENTER or event.keycode == KEY_ESCAPE:
				_return_to_menu()
			return

		match event.keycode:
			KEY_ENTER, KEY_KP_ENTER:
				_submit_score()
			KEY_BACKSPACE:
				name_entry = name_entry.substr(0, max(0, name_entry.length() - 1))
				queue_redraw()
			KEY_ESCAPE:
				_return_to_menu()
			_:
				# Accept printable name characters, cap at 12
				var ch := char(event.unicode)
				if ch.length() == 1 and ch.strip_edges() != "" and name_entry.length() < 12:
					name_entry += ch
					queue_redraw()

func _submit_score():
	var player_name := name_entry if name_entry.strip_edges() != "" else "CHEF"
	earned_rank = SaveDataManager.add_to_leaderboard(
		player_name,
		GameManager.current_state.score,
		GameManager.current_state.mode
	)
	submitted = true
	queue_redraw()

func _return_to_menu():
	get_tree().change_scene_to_file("res://scenes/MainMenu.tscn")

func _draw():
	var font := ThemeDB.fallback_font
	var viewport_size := get_viewport_rect().size
	var centre_x := viewport_size.x / 2

	# Backdrop
	draw_rect(Rect2(Vector2.ZERO, viewport_size), Color(0.05, 0.03, 0.0, 1.0))

	# Headline reflects victory vs. defeat
	var headline := "VICTORY!" if GameManager.current_state.last_victory else "GAME OVER"
	var head_color := Color.GOLD if GameManager.current_state.last_victory else Color.ORANGE_RED
	var head_size := font.get_string_size(headline, HORIZONTAL_ALIGNMENT_CENTER, -1, 48)
	draw_string(font, Vector2(centre_x - head_size.x / 2, 140), headline, HORIZONTAL_ALIGNMENT_LEFT, -1, 48, head_color)

	# Final score
	var score_text := "Final Score: %d" % GameManager.current_state.score
	var score_size := font.get_string_size(score_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 28)
	draw_string(font, Vector2(centre_x - score_size.x / 2, 220), score_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)

	# Mode + stage reached
	var mode_text := "%s · reached Stage %d" % [GameManager.current_state.mode.capitalize(), GameManager.current_state.stage]
	var mode_size := font.get_string_size(mode_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
	draw_string(font, Vector2(centre_x - mode_size.x / 2, 260), mode_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.GRAY)

	if submitted:
		var rank_text := "Banked at #%d on the leaderboard!" % (earned_rank + 1) if earned_rank >= 0 else "Score saved!"
		var rank_size := font.get_string_size(rank_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 22)
		draw_string(font, Vector2(centre_x - rank_size.x / 2, 360), rank_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 22, Color.LIGHT_GREEN)

		var back_text := "[SPACE] Back to Menu"
		var back_size := font.get_string_size(back_text, HORIZONTAL_ALIGNMENT_CENTER, -1, 18)
		draw_string(font, Vector2(centre_x - back_size.x / 2, 440), back_text, HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.GRAY)
	else:
		# Name entry prompt
		var prompt := "Enter your name:"
		var prompt_size := font.get_string_size(prompt, HORIZONTAL_ALIGNMENT_CENTER, -1, 20)
		draw_string(font, Vector2(centre_x - prompt_size.x / 2, 360), prompt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20, Color.WHITE)

		var shown := name_entry + "_"
		var name_size := font.get_string_size(shown, HORIZONTAL_ALIGNMENT_CENTER, -1, 28)
		draw_string(font, Vector2(centre_x - name_size.x / 2, 400), shown, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.GOLD)

		var hint := "[ENTER] Submit    [ESC] Skip"
		var hint_size := font.get_string_size(hint, HORIZONTAL_ALIGNMENT_CENTER, -1, 16)
		draw_string(font, Vector2(centre_x - hint_size.x / 2, 460), hint, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.GRAY)
