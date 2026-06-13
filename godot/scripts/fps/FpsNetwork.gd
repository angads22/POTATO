extends Node

# Network/session manager for the 3D first-person "SPUD BLASTER" arena —
# autoloaded as FpsNetwork. Separate from the rhythm-duel MultiplayerManager
# (different port, different game) so the two never interfere.
#
# Three session modes:
#   "offline" — solo practice against target-dummy bots, no networking at all.
#   "host"    — opens an ENet server on PORT for LAN play and, best-effort,
#               asks the router to forward the port via UPnP so friends can
#               join over the internet by the host's public IP ("global").
#   "client"  — connects to a host by IP (a LAN address or a public IP).
#
# Connection + player identity live here; the per-frame movement, shooting and
# scoring RPCs live on FpsArena (a node with a stable scene path) so they route
# reliably across peers. ENet's server relay (on by default) forwards
# client→client RPCs through the host, so the star topology is fine.

signal roster_changed            # players dict changed
signal server_started            # ENet server is listening (LAN ready)
signal public_address_resolved   # UPnP finished (port_forwarded / public_ip set)
signal connection_failed         # client could not reach / lost the host
signal match_starting            # everyone should load the arena now

const PORT := 7370
const MAX_PLAYERS := 4
const DEFAULT_FRAG_LIMIT := 15
const DEFAULT_TIME_LIMIT := 180.0  # seconds

var mode := "offline"            # "offline" | "host" | "client"
# peer_id -> { "name": String }   (frags are tracked by the arena)
var players := {}
var frag_limit := DEFAULT_FRAG_LIMIT
var time_limit := DEFAULT_TIME_LIMIT
var match_seed := 0

# Diagnostics surfaced by the lobby
var lan_ip := ""
var public_ip := ""
var port_forwarded := false
var upnp_status := "idle"        # idle | working | done | unavailable

var _upnp_thread: Thread = null
var _signals_bound := false

func _ready() -> void:
	lan_ip = _detect_lan_ip()

# ── queries ─────────────────────────────────────────────────────────────────

func is_networked() -> bool:
	return mode == "host" or mode == "client"

# host and offline both own the authoritative game state
func is_authority() -> bool:
	return mode != "client"

func local_id() -> int:
	return multiplayer.get_unique_id() if is_networked() else 1

func my_name() -> String:
	var n := str(SaveDataManager.settings.get("player_name", "")).strip_edges()
	return n if n != "" else "Chef"

# ── session lifecycle ────────────────────────────────────────────────────────

func start_offline() -> void:
	_reset()
	mode = "offline"
	match_seed = randi()
	players = {1: _new_player(my_name())}
	roster_changed.emit()

func host_game() -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_server(PORT, MAX_PLAYERS - 1)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = "host"
	match_seed = randi()
	players = {1: _new_player(my_name())}
	_bind_signals()
	server_started.emit()
	roster_changed.emit()
	_start_upnp()
	return OK

func join_game(ip: String) -> Error:
	_reset()
	var peer := ENetMultiplayerPeer.new()
	var err := peer.create_client(ip, PORT)
	if err != OK:
		return err
	multiplayer.multiplayer_peer = peer
	mode = "client"
	_bind_signals()
	return OK

# host-only: tell every peer to load the arena. Offline starts locally.
func start_match() -> void:
	if mode == "host":
		_begin_match.rpc(match_seed, frag_limit, time_limit)
	else:
		match_starting.emit()

func leave() -> void:
	_stop_upnp()
	_unbind_signals()
	if multiplayer.multiplayer_peer:
		multiplayer.multiplayer_peer.close()
	multiplayer.multiplayer_peer = null
	_reset()

# ── roster ───────────────────────────────────────────────────────────────────

func _new_player(name: String) -> Dictionary:
	return {"name": name}

func _reset() -> void:
	mode = "offline"
	players = {}
	public_ip = ""
	port_forwarded = false
	upnp_status = "idle"

func _bind_signals() -> void:
	if _signals_bound:
		return
	multiplayer.peer_connected.connect(_on_peer_connected)
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	multiplayer.connection_failed.connect(_on_connection_failed)
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	_signals_bound = true

func _unbind_signals() -> void:
	if not _signals_bound:
		return
	multiplayer.peer_connected.disconnect(_on_peer_connected)
	multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	multiplayer.connected_to_server.disconnect(_on_connected_to_server)
	multiplayer.connection_failed.disconnect(_on_connection_failed)
	multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	_signals_bound = false

func _on_peer_connected(_id: int) -> void:
	pass  # the host waits for the client to register its name (below)

func _on_peer_disconnected(id: int) -> void:
	if mode != "host":
		return
	players.erase(id)
	_sync_roster.rpc(players)
	roster_changed.emit()

func _on_connected_to_server() -> void:
	if mode != "client":
		return
	_register.rpc_id(1, my_name())

func _on_connection_failed() -> void:
	if mode != "client":
		return
	mode = "offline"
	connection_failed.emit()

func _on_server_disconnected() -> void:
	if mode != "client":
		return
	leave()
	connection_failed.emit()

@rpc("any_peer", "call_remote", "reliable")
func _register(name: String) -> void:
	if mode != "host":
		return
	var id := multiplayer.get_remote_sender_id()
	players[id] = _new_player(name)
	_sync_roster.rpc(players)
	roster_changed.emit()

@rpc("authority", "call_remote", "reliable")
func _sync_roster(roster: Dictionary) -> void:
	players = roster
	roster_changed.emit()

@rpc("authority", "call_local", "reliable")
func _begin_match(seed_val: int, fl: int, tl: float) -> void:
	match_seed = seed_val
	frag_limit = fl
	time_limit = tl
	match_starting.emit()

# ── networking helpers ───────────────────────────────────────────────────────

func _detect_lan_ip() -> String:
	for ip in IP.get_local_addresses():
		if ip.contains(":"):
			continue  # skip IPv6
		if ip.begins_with("192.168.") or ip.begins_with("10.") or ip.begins_with("172."):
			return ip
	return ""

# ── UPnP (runs on a worker thread so discovery never freezes the lobby) ──────

func _start_upnp() -> void:
	upnp_status = "working"
	public_ip = ""
	port_forwarded = false
	_upnp_thread = Thread.new()
	_upnp_thread.start(_upnp_worker)

func _upnp_worker() -> void:
	var upnp := UPNP.new()
	var ok := false
	var ext := ""
	if upnp.discover() == UPNP.UPNP_RESULT_SUCCESS:
		var gateway := upnp.get_gateway()
		if gateway and gateway.is_valid_gateway():
			# ENet is UDP; map the port to this machine.
			var mapped := upnp.add_port_mapping(PORT, PORT, "SliceItFPS", "UDP", 0)
			ext = upnp.query_external_address()
			ok = mapped == UPNP.UPNP_RESULT_SUCCESS and ext != ""
	call_deferred("_upnp_done", ok, ext)

func _upnp_done(ok: bool, ext: String) -> void:
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
	port_forwarded = ok
	public_ip = ext
	upnp_status = "done" if ok else "unavailable"
	public_address_resolved.emit()

func _stop_upnp() -> void:
	# Join the worker if it's still running; leave any mapping in place (the
	# router expires it, and a blocking re-discover here would stall quitting).
	if _upnp_thread:
		_upnp_thread.wait_to_finish()
		_upnp_thread = null
