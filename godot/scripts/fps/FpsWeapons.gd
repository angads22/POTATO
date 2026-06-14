class_name FpsWeapons
extends RefCounted

# Weapon registry for SPUD BLASTER — the data behind the Shell-Shockers-meets-
# Fortnite arsenal. Every gun is described purely as a stat dictionary here; the
# arena (FpsArena) reads the def of whoever is shooting to resolve hits, and the
# player (FpsPlayer) reads it to drive ammo, reload, spread and the viewmodel.
# No art assets — viewmodels are built procedurally from the "shape" hint.
#
# Each def carries:
#   id, name, short   identity + HUD label
#   slot              suggested loadout slot category (cosmetic grouping)
#   shape             which procedural viewmodel to build
#   damage            base body damage per pellet/hit
#   headshot_mult     multiplier when the hit lands on the target's head
#   mag, reserve      magazine size + starting reserve ammo
#   reload_time       seconds for a full reload
#   rpm               rounds per minute → fire cooldown = 60/rpm
#   pellets           shots per trigger pull (8 = shotgun, 1 = everything else)
#   spread, ads_spread  cone half-angle in degrees, hip vs aim-down-sights
#   automatic         holds-to-fire vs click-per-shot
#   projectile        true = lobbed explosive (Fry Launcher) instead of hitscan
#   splash_radius, splash_damage   explosion radius + max splash damage
#   scoped, ads_fov   sniper scope: narrow camera FOV on ADS
#   premium           starch-exclusive (the Plasma Fryer)
#   color             viewmodel / tracer tint

static var _cache: Dictionary = {}

static func _build() -> Dictionary:
	var w := {}
	w["spud_rifle"] = {
		"id": "spud_rifle", "name": "Spud Rifle", "short": "RIFLE",
		"slot": "primary", "shape": "rifle",
		"damage": 25, "headshot_mult": 2.0,
		"mag": 30, "reserve": 120, "reload_time": 2.0, "rpm": 600.0,
		"pellets": 1, "spread": 1.4, "ads_spread": 0.4,
		"automatic": true, "ads_fov": 58.0,
		"color": Color(0.62, 0.45, 0.28),
	}
	w["peeler_smg"] = {
		"id": "peeler_smg", "name": "Peeler SMG", "short": "SMG",
		"slot": "primary", "shape": "smg",
		"damage": 16, "headshot_mult": 1.6,
		"mag": 35, "reserve": 175, "reload_time": 1.6, "rpm": 900.0,
		"pellets": 1, "spread": 3.2, "ads_spread": 1.4,
		"automatic": true, "ads_fov": 62.0,
		"color": Color(0.55, 0.58, 0.62),
	}
	w["masher"] = {
		"id": "masher", "name": "Masher", "short": "SHOTGUN",
		"slot": "secondary", "shape": "shotgun",
		"damage": 11, "headshot_mult": 1.5,
		"mag": 6, "reserve": 36, "reload_time": 2.6, "rpm": 90.0,
		"pellets": 9, "spread": 8.5, "ads_spread": 5.0,
		"automatic": false, "ads_fov": 64.0,
		"color": Color(0.45, 0.3, 0.18),
	}
	w["tater_sniper"] = {
		"id": "tater_sniper", "name": "Tater Sniper", "short": "SNIPER",
		"slot": "primary", "shape": "sniper",
		"damage": 85, "headshot_mult": 2.2,
		"mag": 5, "reserve": 25, "reload_time": 2.8, "rpm": 50.0,
		"pellets": 1, "spread": 2.5, "ads_spread": 0.05,
		"automatic": false, "scoped": true, "ads_fov": 22.0,
		"color": Color(0.3, 0.34, 0.4),
	}
	w["fry_launcher"] = {
		"id": "fry_launcher", "name": "Fry Launcher", "short": "LAUNCHER",
		"slot": "special", "shape": "launcher",
		"damage": 40, "headshot_mult": 1.0,
		"mag": 4, "reserve": 16, "reload_time": 3.0, "rpm": 70.0,
		"pellets": 1, "spread": 0.6, "ads_spread": 0.3,
		"automatic": false, "ads_fov": 60.0,
		"projectile": true, "splash_radius": 4.2, "splash_damage": 60,
		"color": Color(0.85, 0.55, 0.2),
	}
	w["plasma_fryer"] = {
		"id": "plasma_fryer", "name": "Plasma Fryer", "short": "PLASMA",
		"slot": "special", "shape": "plasma",
		"damage": 30, "headshot_mult": 1.8,
		"mag": 25, "reserve": 100, "reload_time": 1.9, "rpm": 720.0,
		"pellets": 1, "spread": 0.9, "ads_spread": 0.2,
		"automatic": true, "ads_fov": 60.0,
		"premium": true,
		"color": Color(0.45, 0.95, 0.85),
	}
	return w

static func all() -> Dictionary:
	if _cache.is_empty():
		_cache = _build()
	return _cache

static func ids() -> Array:
	return all().keys()

static func get_def(id: String) -> Dictionary:
	var a := all()
	return a.get(id, a["spud_rifle"])

static func has(id: String) -> bool:
	return all().has(id)

static func display_name(id: String) -> String:
	return str(get_def(id).get("name", "?"))

# Two-gun spawn loadout. The starch-exclusive Plasma Fryer is appended as a
# third slot once the player has bought it at the Starch Exchange.
static func default_loadout() -> Array:
	var l := ["spud_rifle", "masher"]
	if SaveDataManager.fps_owns("plasma_fryer"):
		l.append("plasma_fryer")
	return l

# ── cosmetic weapon skins (bought with starch) ───────────────────────────────
# A skin globally tints every viewmodel / tracer. "classic" is free.

static func skins() -> Array:
	return [
		{"id": "classic", "name": "Classic", "cost": 0, "color": Color(1, 1, 1)},
		{"id": "golden", "name": "Golden Fry", "cost": 8, "color": Color(1.0, 0.82, 0.25)},
		{"id": "neon", "name": "Neon Crunch", "cost": 12, "color": Color(0.3, 1.0, 0.6)},
		{"id": "frost", "name": "Frostbite", "cost": 12, "color": Color(0.55, 0.85, 1.0)},
		{"id": "magma", "name": "Magma Mash", "cost": 16, "color": Color(1.0, 0.4, 0.2)},
	]

static func skin_def(id: String) -> Dictionary:
	for s in skins():
		if s["id"] == id:
			return s
	return skins()[0]

# Tint a weapon's base colour by the currently-equipped skin (multiplicative,
# so each gun keeps a hint of its own identity).
static func tint_for(base: Color) -> Color:
	var s := str(SaveDataManager.fps_skin())
	if s == "" or s == "classic":
		return base
	var sc: Color = skin_def(s)["color"]
	return Color(
		clampf(base.r * 0.4 + sc.r * 0.6, 0.0, 1.0),
		clampf(base.g * 0.4 + sc.g * 0.6, 0.0, 1.0),
		clampf(base.b * 0.4 + sc.b * 0.6, 0.0, 1.0))
