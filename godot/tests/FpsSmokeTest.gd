extends Node

# Headless smoke test for the SPUD BLASTER first-person arena. Boots a solo
# practice match, plants a stationary target dummy dead ahead, aims the local
# chef at it and fires until it's sliced — proving the 3D arena builds, the
# player/raycast/weapon work and the deathmatch scoring registers a frag.
#
#   godot --headless --path . res://tests/FpsSmokeTest.tscn --quit-after 300
#
# Prints "FPS SMOKE OK" and exits 0 on success, "FPS SMOKE FAIL" / exit 1
# otherwise. (Pure offline — no sockets, threads or UPnP are touched.)

var frames := 0
var arena
var player
var bot
var set_up := false

func _ready() -> void:
	FpsNetwork.start_offline()
	arena = load("res://scenes/Fps/FpsArena.tscn").instantiate()
	add_child(arena)

func _physics_process(_delta: float) -> void:
	frames += 1

	# let the world build and physics settle, then plant a dummy in front
	if frames == 8 and not set_up:
		player = arena.get_local_player()
		if player == null:
			print("FPS SMOKE FAIL — no local player spawned")
			get_tree().quit(1)
			return
		# aim toward the arena centre (the player spawns in a corner facing a
		# wall) so the line of fire to the dummy is clear
		var to_centre: Vector3 = Vector3.ZERO - player.global_position
		to_centre.y = 0.0
		var dir: Vector3 = to_centre.normalized()
		bot = arena.spawn_bot(player.global_position + dir * 5.0)
		bot.wander_enabled = false
		set_up = true

	# aim and fire a volley straight at the dummy's chest
	if set_up and frames >= 12 and frames <= 36 and frames % 4 == 0:
		if is_instance_valid(bot):
			player.face(bot.global_position + Vector3(0, 0.9, 0))
		arena.fire_from(player)

	if frames == 60:
		var frags: int = arena.scores.get(1, 0)
		if frags >= 1:
			print("FPS SMOKE OK — frags=%d players=%d bots=%d" % [
				frags, arena.players.size(), arena.bots.size()])
			get_tree().quit(0)
		else:
			print("FPS SMOKE FAIL — no frag scored (frags=%d)" % frags)
			get_tree().quit(1)
