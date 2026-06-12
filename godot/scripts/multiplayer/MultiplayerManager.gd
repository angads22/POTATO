extends Node

# LAN multiplayer session manager — autoloaded as MultiplayerManager.
# Host opens an ENet server on PORT; client connects by IP.
# A shared session_seed sent by the host makes both sides generate the
# same potato sequence, so the minigames are mirrored without any further
# synchronisation.

signal peer_joined
signal peer_left
signal connection_failed
signal game_ready

const PORT = 7369
const MAX_CLIENTS = 1

var is_host := false
var is_in_multiplayer := false
var session_seed := 0
var opponent_score := 0
var opponent_lives := 3

func host_game() -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_CLIENTS)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = true
	is_in_multiplayer = true
	session_seed = randi()
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK

func join_game(ip: String) -> Error:
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	is_host = false
	is_in_multiplayer = true
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	return OK

func leave_game():
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
		multiplayer.multiplayer_peer = null
	is_in_multiplayer = false
	is_host = false
	opponent_score = 0
	opponent_lives = 3

func broadcast_score(score: int, lives: int):
	_recv_score.rpc(score, lives)

func _on_peer_connected(id: int):
	peer_joined.emit()
	if is_host:
		_push_seed.rpc_id(id, session_seed)

func _on_peer_disconnected(_id: int):
	peer_left.emit()

func _on_connection_failed():
	is_in_multiplayer = false
	connection_failed.emit()

func _on_connected_to_server():
	pass  # host pushes the seed immediately after connection

@rpc("authority", "call_remote", "reliable")
func _push_seed(seed_val: int):
	session_seed = seed_val
	game_ready.emit()

@rpc("any_peer", "call_remote", "unreliable_ordered")
func _recv_score(score: int, lives: int):
	opponent_score = score
	opponent_lives = lives
