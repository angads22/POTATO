extends Node

# Audio — autoloaded as AudioManager. Owns every sound in the game, all of it
# synthesized at runtime (scripts/audio/: Synth, SfxLibrary, SongComposer), so
# the project still ships with zero audio assets.
#
#   SFX     play_sfx("cut_great") — a pool of voices on the "SFX" bus. The
#           library renders on a worker thread at boot (~0.5 s); calls made
#           before it's ready are silently dropped.
#   Music   play_music("menu") / play_song({style, bpm, seed}) — songs are
#           composed + rendered on a worker thread, cached, and crossfaded on
#           two decks. Each song is four synced stems (drums / harmony / lead /
#           fever); set_layer("fever", true) fades a stem in or out.
#   Clock   music_time() / music_beat() — the beat clock gameplay locks to.
#           It runs on the wall clock from the moment a song is requested
#           (so gameplay never waits for a render, and works with sound off
#           or on the headless CI server); when the audio joins it starts at
#           the matching offset, and drift against the real playback position
#           is slewed out every frame. A user offset (Settings) calibrates
#           Bluetooth/latency-heavy setups.

signal beat(index: int)          # fires as the clock crosses each beat
signal music_started(track: String)

const SFX_VOICES := 16
const MUSIC_CACHE := 5
const STEMS := ["drums", "harmony", "lead", "fever"]
const SILENT_DB := -60.0

# Named tracks. Gameplay modes that need their own tempo call play_song().
const TRACKS := {
	"menu": {"style": "menu", "bpm": 104.0, "seed": 11},
	"farm": {"style": "farm", "bpm": 92.0, "seed": 23},
	"town": {"style": "town", "bpm": 120.0, "seed": 31},
	"fps": {"style": "arena", "bpm": 140.0, "seed": 47},
	"results": {"style": "results", "bpm": 90.0, "seed": 5},
	"lobby": {"style": "dance", "bpm": 118.0, "seed": 64},
}

var sound_enabled: bool = true
# Headless tests only: runs the (silent) beat clock this many times faster
# than real time so a smoke test can play several stages in a few seconds.
# Ignored whenever audio is live.
var debug_time_scale: float = 1.0
# false on the headless server: nothing is rendered or played, but the beat
# clock and composed song data still work, so tests drive the real game logic
var audio_live: bool = true

# ── SFX ──
var _sfx: Dictionary = {}
var _sfx_job: Dictionary = {}
var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_next: int = 0
var _sfx_last: Dictionary = {}

# ── music ──
var track: String = ""            # key of the current song ("" = none)
var bpm: float = 120.0
var song: Dictionary = {}         # composed note data of the current song
var loop_sec: float = 0.0
var _origin: float = 0.0          # wall-clock second of beat 0
var _paused_at: float = -1.0
var _decks: Array = [{}, {}]      # stem -> AudioStreamPlayer
var _deck: int = 0
var _deck_key: Array = ["", ""]
var _deck_live: bool = false      # is the active deck actually playing?
var _layers: Dictionary = {"drums": 1.0, "harmony": 1.0, "lead": 1.0, "fever": 0.0}
var _cache: Dictionary = {}       # key -> {stems, loop_sec, song}
var _cache_order: Array = []
var _jobs: Dictionary = {}        # key -> {task, song, result}
var _fade_in: float = 0.8
var _tweens: Dictionary = {}      # AudioStreamPlayer -> its volume Tween
var _last_beat: int = -999999

func _ready():
	process_mode = Node.PROCESS_MODE_ALWAYS  # keep fades/clock alive in pause
	audio_live = DisplayServer.get_name() != "headless"
	sound_enabled = SaveDataManager.settings.get("sound_enabled", true)
	_setup_buses()
	apply_volumes()

	for i in SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		add_child(p)
		_sfx_players.append(p)
	for d in 2:
		for stem in STEMS:
			var p := AudioStreamPlayer.new()
			p.bus = "Music"
			p.volume_db = SILENT_DB
			add_child(p)
			_decks[d][stem] = p

	if audio_live:
		var job := {"result": {}}
		job["task"] = WorkerThreadPool.add_task(func(): job["result"] = SfxLibrary.build(), false, "sfx")
		_sfx_job = job

func _exit_tree():
	# never leave a worker writing into a freed engine
	if _sfx_job.has("task"):
		WorkerThreadPool.wait_for_task_completion(_sfx_job["task"])
	for k in _jobs:
		WorkerThreadPool.wait_for_task_completion(_jobs[k]["task"])
	_jobs.clear()

func _setup_buses():
	for name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, name)
			AudioServer.set_bus_send(idx, "Master")
	# a little room on the music, a safety limiter on everything
	var music := AudioServer.get_bus_index("Music")
	if AudioServer.get_bus_effect_count(music) == 0:
		var verb := AudioEffectReverb.new()
		verb.room_size = 0.35
		verb.damping = 0.6
		verb.wet = 0.1
		verb.dry = 1.0
		AudioServer.add_bus_effect(music, verb)
	if AudioServer.get_bus_effect_count(0) == 0:
		# Godot's limiter adds (ceiling - threshold) of make-up gain, so keep
		# the two close: it should only catch the odd chop-on-a-downbeat peak
		var lim := AudioEffectLimiter.new()
		lim.ceiling_db = -0.5
		lim.threshold_db = -1.0
		AudioServer.add_bus_effect(0, lim)

# Push the saved volumes / mute state onto the buses.
func apply_volumes():
	var st: Dictionary = SaveDataManager.settings
	_set_bus("Master", st.get("master_volume", 1.0))
	_set_bus("Music", st.get("music_volume", 0.8))
	_set_bus("SFX", st.get("sfx_volume", 1.0))
	AudioServer.set_bus_mute(0, not sound_enabled)

func _set_bus(bus: String, v: float):
	var idx := AudioServer.get_bus_index(bus)
	if idx == -1:
		return
	AudioServer.set_bus_volume_db(idx, linear_to_db(v) if v > 0.001 else -80.0)

func set_volume(bus: String, volume: float):
	volume = clampf(volume, 0.0, 1.0)
	SaveDataManager.update_setting(bus.to_lower() + "_volume", volume)
	apply_volumes()

func toggle_sound():
	sound_enabled = not sound_enabled
	SaveDataManager.update_setting("sound_enabled", sound_enabled)
	apply_volumes()

# ────────────────────────────────────────────────────────
#  SFX
# ────────────────────────────────────────────────────────

func play_sfx(sfx_name: String, volume_db: float = 0.0, pitch: float = 1.0):
	if not audio_live or not _sfx.has(sfx_name):
		return
	# the same sound twice within 25 ms just doubles the volume — skip it
	var now := Time.get_ticks_msec()
	if now - int(_sfx_last.get(sfx_name, -1000)) < 25:
		return
	_sfx_last[sfx_name] = now
	var p := _free_voice()
	p.stream = _sfx[sfx_name]
	p.volume_db = volume_db
	p.pitch_scale = pitch
	p.play()

# A little random pitch so repeated sounds (steps, chops) don't machine-gun.
func play_sfx_varied(sfx_name: String, spread: float = 0.06, volume_db: float = 0.0):
	play_sfx(sfx_name, volume_db, 1.0 + randf_range(-spread, spread))

func _free_voice() -> AudioStreamPlayer:
	for i in SFX_VOICES:
		var p := _sfx_players[(_sfx_next + i) % SFX_VOICES]
		if not p.playing:
			_sfx_next = (_sfx_next + i + 1) % SFX_VOICES
			return p
	# all busy: steal the next in rotation
	var p := _sfx_players[_sfx_next]
	_sfx_next = (_sfx_next + 1) % SFX_VOICES
	return p

func sfx_ready() -> bool:
	return not _sfx.is_empty()

# ────────────────────────────────────────────────────────
#  Music
# ────────────────────────────────────────────────────────

func play_music(track_name: String, fade_in: float = 0.8):
	if TRACKS.has(track_name):
		play_song(TRACKS[track_name], fade_in)

static func song_key(spec: Dictionary) -> String:
	return "%s:%d:%.2f" % [spec.get("style", "menu"), int(spec.get("seed", 1)), float(spec.get("bpm", 120.0))]

# Start a song. The beat clock restarts now (+ lead_in_beats of count-in,
# during which music_time() is negative); the audio joins as soon as the
# render is ready, at whatever offset the clock has reached.
func play_song(spec: Dictionary, fade_in: float = 0.8, lead_in_beats: float = 0.0, restart: bool = false):
	var key := song_key(spec)
	if key == track and _paused_at < 0.0 and not restart:
		return
	_fade_out_deck(_deck, 0.6)
	_deck = 1 - _deck
	_deck_live = false
	_deck_key[_deck] = ""
	track = key
	bpm = float(spec.get("bpm", 120.0))
	_fade_in = fade_in
	_paused_at = -1.0
	_origin = _now() + lead_in_beats * 60.0 / bpm
	_last_beat = -999999
	_layers = {"drums": 1.0, "harmony": 1.0, "lead": 1.0, "fever": 0.0}
	if _cache.has(key):
		song = _cache[key]["song"]
		loop_sec = _cache[key]["loop_sec"]
	elif _jobs.has(key):
		song = _jobs[key]["song"]
		loop_sec = song["loop_beats"] * 60.0 / bpm
	else:
		song = SongComposer.compose(spec.get("style", "menu"), int(spec.get("seed", 1)), bpm)
		loop_sec = song["loop_beats"] * 60.0 / bpm
		_start_render(key, song)

# Render a song in the background so a later play_song() starts instantly.
func prefetch(spec: Dictionary):
	var key := song_key(spec)
	if _cache.has(key) or _jobs.has(key):
		return
	var s := SongComposer.compose(spec.get("style", "menu"), int(spec.get("seed", 1)), float(spec.get("bpm", 120.0)))
	_start_render(key, s)

# True once a song's audio is rendered (always true when audio isn't live).
func song_ready(spec: Dictionary) -> bool:
	return not audio_live or _cache.has(song_key(spec))

func _start_render(key: String, s: Dictionary):
	if not audio_live:
		return
	var job := {"song": s, "result": {}}
	job["task"] = WorkerThreadPool.add_task(func(): job["result"] = SongComposer.render(s), false, "song")
	_jobs[key] = job

func stop_music(fade_out: float = 1.0):
	_fade_out_deck(_deck, fade_out)
	_deck_live = false
	track = ""

# Fade a stem layer in/out on the current song ("fever", "lead", ...).
func set_layer(stem: String, on: bool, fade: float = 0.4):
	set_layer_gain(stem, 1.0 if on else 0.0, fade)

func set_layer_gain(stem: String, g: float, fade: float = 0.4):
	_layers[stem] = g
	if _deck_live:
		var p: AudioStreamPlayer = _decks[_deck][stem]
		_tween_db(p, _layer_db(stem), fade)

func _layer_db(stem: String) -> float:
	var g: float = _layers.get(stem, 1.0)
	return linear_to_db(g) if g > 0.001 else SILENT_DB

func pause_music():
	if _paused_at >= 0.0:
		return
	_paused_at = _now()
	for p in _decks[_deck].values():
		p.stream_paused = true

func resume_music():
	if _paused_at < 0.0:
		return
	_origin += _now() - _paused_at
	_paused_at = -1.0
	for p in _decks[_deck].values():
		p.stream_paused = false

func is_paused() -> bool:
	return _paused_at >= 0.0

# Is the current song's audio actually playing (vs. still rendering / off)?
func music_live() -> bool:
	return _deck_live

# ────────────────────────────────────────────────────────
#  The beat clock
# ────────────────────────────────────────────────────────

func _now() -> float:
	var t := Time.get_ticks_usec() / 1000000.0
	return t if audio_live else t * debug_time_scale

# Seconds since beat 0 of the current song, as the player hears it.
func music_time() -> float:
	var t := (_paused_at if _paused_at >= 0.0 else _now()) - _origin
	return t - float(SaveDataManager.settings.get("audio_offset_ms", 0)) / 1000.0

func music_beat() -> float:
	return music_time() * bpm / 60.0

func beat_sec() -> float:
	return 60.0 / bpm

# Beat of the next bar line at or after `beat_pos` (bars of 4 beats).
func next_bar(beat_pos: float) -> float:
	return ceilf(beat_pos / 4.0 - 0.0001) * 4.0

# Seconds from now until the clock reaches `beat_pos`.
func time_until_beat(beat_pos: float) -> float:
	return beat_pos * 60.0 / bpm - music_time()

# ────────────────────────────────────────────────────────
#  Per-frame: finished renders, starting decks, drift correction
# ────────────────────────────────────────────────────────

func _process(_delta):
	_collect_jobs()
	if not audio_live:
		_emit_beats()
		return
	if not _deck_live and track != "" and _cache.has(track) and _paused_at < 0.0:
		_start_deck()
	elif _deck_live and _paused_at < 0.0:
		_correct_drift()
	_emit_beats()

func _emit_beats():
	if track == "" or _paused_at >= 0.0:
		return
	var b := floori(music_beat())
	if b != _last_beat and music_time() >= 0.0:
		_last_beat = b
		beat.emit(b)

func _collect_jobs():
	if _sfx_job.has("task") and WorkerThreadPool.is_task_completed(_sfx_job["task"]):
		WorkerThreadPool.wait_for_task_completion(_sfx_job["task"])
		_sfx = _sfx_job["result"]
		_sfx_job = {}
	for key in _jobs.keys():
		var job: Dictionary = _jobs[key]
		if WorkerThreadPool.is_task_completed(job["task"]):
			WorkerThreadPool.wait_for_task_completion(job["task"])
			_jobs.erase(key)
			if not job["result"].is_empty():
				_cache[key] = job["result"]
				_cache_order.append(key)
				_evict()

func _evict():
	while _cache_order.size() > MUSIC_CACHE:
		var victim := ""
		for k in _cache_order:
			if k != track and k != _deck_key[0] and k != _deck_key[1]:
				victim = k
				break
		if victim == "":
			return
		_cache_order.erase(victim)
		_cache.erase(victim)

func _start_deck():
	var res: Dictionary = _cache[track]
	loop_sec = res["loop_sec"]  # the rendered loop's exact length (sample-rounded)
	var latency := AudioServer.get_time_to_next_mix() + AudioServer.get_output_latency()
	var raw := _now() - _origin  # heard-time, before the user offset
	var start_at := raw + latency
	if start_at < 0.0:
		return  # still in the count-in; start on a later frame
	var from := fposmod(start_at, loop_sec)
	var deck: Dictionary = _decks[_deck]
	# start every stem inside one audio-server lock so they share a mix block
	AudioServer.lock()
	for stem in STEMS:
		var p: AudioStreamPlayer = deck[stem]
		p.stream = res["stems"][stem]
		p.volume_db = SILENT_DB
		p.stream_paused = false
		p.play(from)
	AudioServer.unlock()
	for stem in STEMS:
		_tween_db(deck[stem], _layer_db(stem), _fade_in)
	_deck_key[_deck] = track
	_deck_live = true
	music_started.emit(track)

# Keep the wall clock glued to the real playback position: small errors are
# slewed out gently (no visible jumps), large ones (a hitch) snap.
func _correct_drift():
	var p: AudioStreamPlayer = _decks[_deck]["drums"]
	if not p.playing:
		return
	var pos := p.get_playback_position() + AudioServer.get_time_since_last_mix() - AudioServer.get_output_latency()
	var raw := _now() - _origin
	var k := roundf((raw - pos) / loop_sec)
	var err := k * loop_sec + pos - raw
	if absf(err) > 0.25:
		_origin -= err
	elif absf(err) > 0.002:
		_origin -= err * 0.08

func _fade_out_deck(d: int, fade: float):
	for p in _decks[d].values():
		if p.playing:
			_tween_db(p, SILENT_DB, fade, true)
	_deck_key[d] = ""

# One volume tween per player: a new fade replaces (kills) the old one, so a
# stale fade-out can never stop a deck that has since started a new song.
func _tween_db(p: AudioStreamPlayer, db: float, t: float, stop_after: bool = false):
	var old: Tween = _tweens.get(p)
	if old and old.is_valid():
		old.kill()
	var tw := create_tween()
	tw.tween_property(p, "volume_db", db, maxf(0.01, t))
	if stop_after:
		tw.tween_callback(p.stop)
	_tweens[p] = tw
