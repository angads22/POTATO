extends Node

# Headless smoke test for Concert mode: checks that charts are deterministic
# (same seed + difficulty -> identical notes), then auto-plays a whole song
# on Normal — chopping on each note, holding through ribbons and binning
# rotten spuds — on a 3x headless beat clock. Prints CONCERT SMOKE OK if the
# song clears with every note judged and nothing missed.
#
#   godot --headless --path . res://tests/ConcertSmokeTest.tscn --quit-after 6000

const BUDGET_MS = 60000

var ctrl
var t0 := 0
var held = null
var kinds := {}

func _ready():
	AudioManager.debug_time_scale = 3.0
	ctrl = load("res://scenes/Concert/ConcertScene.tscn").instantiate()
	add_child(ctrl)
	t0 = Time.get_ticks_msec()

	# determinism: composing + charting a seed twice gives the same notes
	var spec := ConcertChart.spec_for_seed(ConcertChart.SETLIST[0])
	var a := ConcertChart.build(SongComposer.compose(spec["style"], spec["seed"], spec["bpm"]), "normal")
	var b := ConcertChart.build(SongComposer.compose(spec["style"], spec["seed"], spec["bpm"]), "normal")
	if JSON.stringify(a) != JSON.stringify(b) or a.size() < 40:
		print("CONCERT SMOKE FAIL — chart not deterministic or too short (%d notes)" % a.size())
		get_tree().quit(1)
		return
	ctrl.start_song.call_deferred(spec, "normal")

func _process(_delta):
	if Time.get_ticks_msec() - t0 > BUDGET_MS:
		print("CONCERT SMOKE FAIL (timeout) — beat=%.1f" % AudioManager.music_beat())
		get_tree().quit(1)
		return
	if ctrl.phase == ConcertController.Phase.SELECT:
		return
	if ctrl.phase == ConcertController.Phase.DONE:
		var s = GameManager.current_state
		var stats := "notes=%d judged=%d perfect=%d miss=%d max_combo=%d score=%d kinds=%s" % [
			ctrl.notes.size(), GameManager.cuts_judged(), s.perfect, s.miss, s.max_combo, s.score, kinds]
		if ctrl.cleared and s.miss == 0 and GameManager.cuts_judged() == ctrl.notes.size() and s.score > 0:
			print("CONCERT SMOKE OK — " + stats)
			get_tree().quit(0)
		else:
			print("CONCERT SMOKE FAIL — cleared=%s " % ctrl.cleared + stats)
			get_tree().quit(1)
		return

	var now := AudioManager.music_beat()
	if held != null and now >= float(held["beat"]) + float(held["len"]) - 0.02:
		_key(KEY_SPACE, false)
		held = null
	for i in range(ctrl.next_note, mini(ctrl.next_note + 4, ctrl.notes.size())):
		var n: Dictionary = ctrl.notes[i]
		if n["done"] or n.get("auto", false):
			continue
		if now >= float(n["beat"]) - 0.03:
			n["auto"] = true
			kinds[n["kind"]] = int(kinds.get(n["kind"], 0)) + 1
			match n["kind"]:
				"rotten":
					_key(KEY_X, true)
					_key(KEY_X, false)
				"hold":
					_key(KEY_SPACE, true)
					held = n
				_:
					_key(KEY_SPACE, true)
					_key(KEY_SPACE, false)

func _key(k: Key, down: bool):
	var e := InputEventKey.new()
	e.keycode = k
	e.pressed = down
	get_tree().root.push_input(e)
