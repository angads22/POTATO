extends RefCounted
class_name FarmClock

# The farm's wall clock (design §5.1). This is the ONLY place farm code reads
# Time: FarmEconomy is pure and takes `now_ms` / `tz_s` as arguments, so scenes
# and the SaveDataManager heartbeat ask FarmClock and pass the values in.
#
# Test hooks (all static, reset with reset()):
#   offset_ms    added to the real clock: time travel without waiting
#   frozen_ms    >= 0 pins now_ms() to exactly this value (-1 = off), so a test
#                can stop the heartbeat from moving the wallet
#   tz_override  a fixed UTC offset in seconds (null or -1 = use the OS zone)

static var offset_ms: int = 0
static var frozen_ms: int = -1
static var tz_override = null

# Unix time in integer milliseconds.
static func now_ms() -> int:
	if frozen_ms >= 0:
		return frozen_ms
	return int(Time.get_unix_time_from_system() * 1000.0) + offset_ms

# Local offset from UTC in seconds (positive east): local = utc + tz_s.
static func tz_s() -> int:
	if tz_override != null and int(tz_override) != -1:
		return int(tz_override)
	return int(Time.get_time_zone_from_system().get("bias", 0)) * 60

static func reset() -> void:
	offset_ms = 0
	frozen_ms = -1
	tz_override = null
