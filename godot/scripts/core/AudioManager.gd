extends Node

# Audio management - music, sound effects, volume control
# Framework ready for SFX implementation

var sound_enabled: bool = true
var music_players: Dictionary = {}
var sfx_players: Dictionary = {}

func _ready():
	sound_enabled = SaveDataManager.settings["sound_enabled"]

func play_sfx(sfx_name: String, volume_db: float = 0.0):
	if not sound_enabled:
		return

	# Framework for sound effects
	# Would load from res://assets/audio/sfx/{sfx_name}.ogg
	# For now, this is a placeholder
	pass

func play_music(music_name: String, fade_in: float = 1.0):
	if not sound_enabled:
		return

	# Framework for music playback
	# Would load from res://assets/audio/music/{music_name}.ogg
	pass

func stop_music(fade_out: float = 1.0):
	# Framework for music stopping with fade
	pass

func set_volume(bus: String, volume: float):
	SaveDataManager.update_setting(bus + "_volume", volume)
	if AudioServer.get_bus_index(bus) != -1:
		var db = linear2db(volume) if volume > 0 else -80.0
		AudioServer.set_bus_volume_db(AudioServer.get_bus_index(bus), db)

func toggle_sound():
	sound_enabled = not sound_enabled
	SaveDataManager.update_setting("sound_enabled", sound_enabled)

# Sound effects mapping (to be populated with actual audio assets)
var SFX = {
	"cut_good": "res://assets/audio/sfx/cut_good.ogg",
	"cut_great": "res://assets/audio/sfx/cut_great.ogg",
	"cut_miss": "res://assets/audio/sfx/cut_miss.ogg",
	"coin_collect": "res://assets/audio/sfx/coin_collect.ogg",
	"fever_start": "res://assets/audio/sfx/fever_start.ogg",
	"level_complete": "res://assets/audio/sfx/level_complete.ogg",
	"game_over": "res://assets/audio/sfx/game_over.ogg",
	"menu_select": "res://assets/audio/sfx/menu_select.ogg",
}

var MUSIC = {
	"menu": "res://assets/audio/music/menu.ogg",
	"stage_1": "res://assets/audio/music/stage_1.ogg",
	"boss_battle": "res://assets/audio/music/boss_battle.ogg",
	"fever": "res://assets/audio/music/fever.ogg",
}
