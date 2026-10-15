extends RefCounted
class_name NumFmt

# Number formatting for wallets, costs, rates and times (design §5.13).
#   coins(9999)    -> "9,999"      separators below 10,000
#   coins(12345)   -> "12.3K"      then 3 significant digits (truncated, so a
#   coins(4560000) -> "4.56M"      wallet never reads as more than it holds)
#   rate(1234.0)   -> "+1.23K/min" per-minute rate, trailing zeros dropped
#   dur(200)       -> "3m 20s"     45s · 3m 20s · 12m · 3h 05m · 2d 4h
#   clock(ms, tz)  -> "10:52" or "10:52 AM" (hour24 / the OS locale decides)
# All integer math, so no float rounding shows up in a 3-digit display.

const SUFFIX := ["", "K", "M", "B", "T", "Qa", "Qi", "Sx"]
# Countries whose locale writes the time of day on a 12-hour clock.
const H12_COUNTRIES := ["US", "CA", "AU", "NZ", "PH", "IN", "PK", "BD", "EG", "SA", "MY", "CO"]

# -1 = follow the OS locale, 0 = force 12-hour, 1 = force 24-hour (tests pin it).
static var hour24: int = -1
static var _locale_24h: int = -1   # cached locale answer

static func coins(n) -> String:
	var v := int(n)
	if v < 0:
		return "-" + coins(-v)
	if v < 10000:
		return _separated(v)
	return _sig3(v, false)

# A per-minute rate with its sign: "+1.2K/min", "+38/min", "+0.5/min".
static func rate(per_min) -> String:
	var x := float(per_min)
	return ("+" if x >= 0.0 else "-") + compact(absf(x)) + "/min"

# Compact non-negative number, 3 significant digits, trailing zeros dropped.
static func compact(x: float) -> String:
	if x < 9.95:
		var s := "%.1f" % x
		return s.trim_suffix(".0")
	var r := int(round(x))
	if r < 1000:
		return str(r)
	return _sig3(r, true)

static func dur(seconds) -> String:
	var s := int(ceil(float(seconds)))
	if s <= 0:
		return "0s"
	if s < 60:
		return "%ds" % s
	if s < 600:
		var r := s % 60
		return ("%dm" % (s / 60)) if r == 0 else ("%dm %02ds" % [s / 60, r])
	if s < 3600:
		return "%dm" % (s / 60)
	if s < 86400:
		var m := (s % 3600) / 60
		return ("%dh" % (s / 3600)) if m == 0 else ("%dh %02dm" % [s / 3600, m])
	var h := (s % 86400) / 3600
	return ("%dd" % (s / 86400)) if h == 0 else ("%dd %dh" % [s / 86400, h])

# Local time of day for a unix-ms instant.
static func clock(ms: int, tz_s: int) -> String:
	var secs := (ms - posmod(ms, 1000)) / 1000 + tz_s
	var sod := posmod(secs, 86400)
	var h := sod / 3600
	var m := (sod % 3600) / 60
	if _use_24h():
		return "%02d:%02d" % [h, m]
	var h12 := h % 12
	if h12 == 0:
		h12 = 12
	return "%d:%02d %s" % [h12, m, "AM" if h < 12 else "PM"]

static func _use_24h() -> bool:
	if hour24 >= 0:
		return hour24 == 1
	if _locale_24h < 0:
		var loc := OS.get_locale()            # e.g. "en_US", "de_DE", "en"
		var parts := loc.split("_")
		var twelve := false
		if parts.size() >= 2:
			twelve = parts[1].substr(0, 2).to_upper() in H12_COUNTRIES
		else:
			twelve = loc == "en"
		_locale_24h = 0 if twelve else 1
	return _locale_24h == 1

static func _separated(v: int) -> String:
	var s := str(v)
	var out := ""
	var n := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		n += 1
		if n % 3 == 0 and i > 0:
			out = "," + out
	return out

# v >= 1000: three significant digits with a K/M/B/T/Qa suffix, truncated.
static func _sig3(v: int, strip: bool) -> String:
	var k := 0
	var unit := 1
	while k < SUFFIX.size() - 1 and v / 1000 >= unit:
		unit *= 1000
		k += 1
	var whole := v / unit
	var s: String
	if whole >= 100:
		s = str(whole)
	elif whole >= 10:
		var tenths := v / (unit / 10)
		s = "%d.%d" % [tenths / 10, tenths % 10]
	else:
		var hundredths := v / (unit / 100)
		s = "%d.%02d" % [hundredths / 100, hundredths % 100]
	if strip and s.contains("."):
		s = s.rstrip("0").trim_suffix(".")
	return s + SUFFIX[k]
