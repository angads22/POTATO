class_name FpsMaps
extends RefCounted

# Map registry for SPUD BLASTER. Three themed arenas, each just a stat
# dictionary the arena builds procedurally — palette, sky/fog, sun, cover
# layout, spawns and pickup spots. All maps share FpsArena.FLOOR_SIZE so the
# perimeter walls, bot wander bounds and HALF_FLOOR maths stay constant; only
# the look and the cover/spawn/pickup layouts change per map.
#
# A map is lobby-picked (host or solo) or "random"; the host resolves a random
# pick to a concrete id at match start and ships it to every peer via
# FpsNetwork._begin_match so everyone loads the same arena.

static var _cache: Array = []

# Floor half-extent for spawn placement. Kept as a local literal (rather than
# reading FpsArena.HALF_FLOOR) so this script has no class_name dependency and
# stays safe to preload from the FpsNetwork autoload. MUST match
# FpsArena.FLOOR_SIZE / 2.0.
const HALF_FLOOR := 22.0

# Cover boxes are { "size": Vector3, "pos": Vector3 }. Spawns are corner-ish
# Vector3s; pickups are { "type": "health"|"ammo"|"weapon", "pos": Vector3,
# "weapon": id (weapon pickups only) }. Cover is kept toward mid-field so the
# corner spawn approaches stay open (the headless smoke test fires along one).
static func _build() -> Array:
	var s := HALF_FLOOR - 4.0
	var spawns := [
		Vector3(-s, 0.3, -s), Vector3(s, 0.3, s),
		Vector3(s, 0.3, -s), Vector3(-s, 0.3, s),
	]

	var maps: Array = []

	# ── Farmyard — sunny green pasture, hay-bale & crate cover ────────────────
	maps.append({
		"id": "farmyard", "name": "Farmyard",
		"floor": Color(0.42, 0.5, 0.30), "wall": Color(0.55, 0.45, 0.34),
		"crate": Color(0.62, 0.46, 0.22),
		"sky": Color(0.47, 0.62, 0.80), "fog": Color(0.55, 0.65, 0.78),
		"fog_density": 0.006, "ambient": Color(0.62, 0.62, 0.68),
		"sun_rot": Vector3(-52.0, 38.0, 0.0), "sun_energy": 1.15,
		"spawns": spawns,
		"cover": [
			{"size": Vector3(2.4, 2.0, 2.4), "pos": Vector3(-8, 1.0, -6)},
			{"size": Vector3(2.4, 2.0, 2.4), "pos": Vector3(9, 1.0, 7)},
			{"size": Vector3(3.0, 1.4, 3.0), "pos": Vector3(0, 0.7, 0)},
			{"size": Vector3(2.0, 3.0, 2.0), "pos": Vector3(7, 1.5, -9)},
			{"size": Vector3(2.0, 3.0, 2.0), "pos": Vector3(-7, 1.5, 9)},
			{"size": Vector3(5.0, 1.2, 2.0), "pos": Vector3(-11, 0.6, 2)},
			{"size": Vector3(2.0, 1.2, 5.0), "pos": Vector3(11, 0.6, -2)},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(0, 1.4, 0)},
			{"type": "ammo", "pos": Vector3(-11, 1.0, 2)},
			{"type": "ammo", "pos": Vector3(11, 1.0, -2)},
			{"type": "weapon", "weapon": "tater_sniper", "pos": Vector3(0, 1.0, -14)},
			{"type": "weapon", "weapon": "peeler_smg", "pos": Vector3(0, 1.0, 14)},
		],
	})

	# ── Kitchen Canyon — warm tiled kitchen, counter & pot cover ──────────────
	maps.append({
		"id": "kitchen", "name": "Kitchen Canyon",
		"floor": Color(0.55, 0.5, 0.46), "wall": Color(0.7, 0.42, 0.34),
		"crate": Color(0.78, 0.78, 0.82),
		"sky": Color(0.85, 0.68, 0.5), "fog": Color(0.8, 0.6, 0.45),
		"fog_density": 0.004, "ambient": Color(0.78, 0.66, 0.58),
		"sun_rot": Vector3(-60.0, 12.0, 0.0), "sun_energy": 1.25,
		"spawns": spawns,
		"cover": [
			{"size": Vector3(6.0, 1.6, 2.0), "pos": Vector3(0, 0.8, -8)},
			{"size": Vector3(6.0, 1.6, 2.0), "pos": Vector3(0, 0.8, 8)},
			{"size": Vector3(2.0, 1.6, 6.0), "pos": Vector3(-9, 0.8, 0)},
			{"size": Vector3(2.0, 1.6, 6.0), "pos": Vector3(9, 0.8, 0)},
			{"size": Vector3(2.6, 2.6, 2.6), "pos": Vector3(0, 1.3, 0)},
			{"size": Vector3(2.0, 2.4, 2.0), "pos": Vector3(-12, 1.2, -12)},
			{"size": Vector3(2.0, 2.4, 2.0), "pos": Vector3(12, 1.2, 12)},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(0, 1.4, 0)},
			{"type": "ammo", "pos": Vector3(-9, 1.0, 8)},
			{"type": "ammo", "pos": Vector3(9, 1.0, -8)},
			{"type": "weapon", "weapon": "fry_launcher", "pos": Vector3(0, 1.0, 0)},
			{"type": "weapon", "weapon": "masher", "pos": Vector3(13, 1.0, -13)},
		],
	})

	# ── Frostbite Fields — cold blue snowfield, ice-block cover ───────────────
	maps.append({
		"id": "frostbite", "name": "Frostbite Fields",
		"floor": Color(0.82, 0.86, 0.92), "wall": Color(0.6, 0.68, 0.78),
		"crate": Color(0.72, 0.82, 0.92),
		"sky": Color(0.66, 0.74, 0.86), "fog": Color(0.8, 0.86, 0.94),
		"fog_density": 0.012, "ambient": Color(0.7, 0.76, 0.86),
		"sun_rot": Vector3(-40.0, 65.0, 0.0), "sun_energy": 0.9,
		"spawns": spawns,
		"cover": [
			{"size": Vector3(2.0, 3.4, 2.0), "pos": Vector3(-6, 1.7, -6)},
			{"size": Vector3(2.0, 3.4, 2.0), "pos": Vector3(6, 1.7, 6)},
			{"size": Vector3(2.0, 3.4, 2.0), "pos": Vector3(6, 1.7, -6)},
			{"size": Vector3(2.0, 3.4, 2.0), "pos": Vector3(-6, 1.7, 6)},
			{"size": Vector3(4.0, 1.0, 4.0), "pos": Vector3(0, 0.5, 0)},
			{"size": Vector3(3.0, 2.0, 3.0), "pos": Vector3(-13, 1.0, 0)},
			{"size": Vector3(3.0, 2.0, 3.0), "pos": Vector3(13, 1.0, 0)},
		],
		"pickups": [
			{"type": "health", "pos": Vector3(0, 1.4, 0)},
			{"type": "health", "pos": Vector3(-13, 1.4, 0)},
			{"type": "ammo", "pos": Vector3(13, 1.0, 0)},
			{"type": "weapon", "weapon": "tater_sniper", "pos": Vector3(0, 1.0, 13)},
			{"type": "weapon", "weapon": "peeler_smg", "pos": Vector3(0, 1.0, -13)},
		],
	})

	return maps

static func all() -> Array:
	if _cache.is_empty():
		_cache = _build()
	return _cache

static func ids() -> Array:
	var out: Array = []
	for m in all():
		out.append(m["id"])
	return out

static func get_map(id: String) -> Dictionary:
	for m in all():
		if m["id"] == id:
			return m
	return all()[0]

static func map_name(id: String) -> String:
	return str(get_map(id).get("name", "?"))

# Resolve "random" (or an unknown id) to a concrete map id. Called by the host
# / solo peer once, so every peer then loads the same concrete map.
static func resolve(id: String) -> String:
	if id == "random" or not _exists(id):
		var list := ids()
		return list[randi() % list.size()]
	return id

static func _exists(id: String) -> bool:
	for m in all():
		if m["id"] == id:
			return true
	return false
