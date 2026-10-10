extends SceneTree
# Dumps SongComposer + ConcertChart output for a batch of seeds as JSON, so
# check_parity.py can diff it against the web edition's port (core.js).
#   godot --headless --path godot -s "$PWD/web/tools/dump_godot.gd" -- out.json
func _init():
	var out := []
	for seed_v in _seeds():
		var spec := ConcertChart.spec_for_seed(seed_v)
		var song := SongComposer.compose(spec["style"], spec["seed"], spec["bpm"])
		var charts := {}
		for d in ConcertChart.DIFFICULTIES:
			charts[d] = ConcertChart.build(song, d)
		out.append({"spec": spec, "song": song, "charts": charts})
	var path: String = OS.get_cmdline_user_args()[0]
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("dumped %d songs" % out.size())
	quit()

func _seeds() -> Array:
	var s := [20261010, 20250101, 20271231]
	s.append_array(ConcertChart.SETLIST)
	for i in 24:
		s.append(1000 + i * 7919)
	return s
