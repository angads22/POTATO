extends Node

# In-game updater for the visual edition — autoloaded as UpdateManager.
# Checks the newest GitHub release on launch (silently); the menu's
# "Check for Updates" screen can then download the right platform build
# and swap the running executable in place. The old binary is parked as
# *.old and cleaned up on the next launch, mirroring the console
# edition's updater.

signal status_changed

const REPO := "angads22/POTATO"
const API_LATEST := "https://api.github.com/repos/" + REPO + "/releases/latest"

var current_version: String = str(ProjectSettings.get_setting("application/config/version", "0.0.0"))
var latest_version := ""
var download_url := ""
var state := "idle"   # idle | checking | uptodate | available | downloading | installing | error
var error_msg := ""

func _ready():
	_cleanup_old()
	check()

func check():
	if state == "checking" or state == "downloading" or state == "installing":
		return
	state = "checking"
	status_changed.emit()
	var req := HTTPRequest.new()
	add_child(req)
	req.request_completed.connect(func(_r, code, _h, body):
		req.queue_free()
		_on_check_done(code, body)
	)
	if req.request(API_LATEST, _headers()) != OK:
		req.queue_free()
		_fail("Could not reach GitHub")

func _on_check_done(code: int, body: PackedByteArray):
	if code != 200:
		_fail("GitHub answered %d — try again later" % code)
		return
	var parsed = JSON.parse_string(body.get_string_from_utf8())
	if not parsed is Dictionary:
		_fail("Unexpected answer from GitHub")
		return
	latest_version = str(parsed.get("tag_name", "")).lstrip("vV")
	download_url = _asset_for_platform(parsed.get("assets", []))
	state = "available" if _is_newer(latest_version, current_version) else "uptodate"
	status_changed.emit()

func _asset_for_platform(assets) -> String:
	var want := ""
	match OS.get_name():
		"Windows":
			want = "SliceIt-Visual-win-x64.zip"
		"macOS":
			want = "SliceIt-Visual-mac.zip"
		_:
			want = "SliceIt-Visual-linux-x64.zip"
	if assets is Array:
		for a in assets:
			if a is Dictionary and a.get("name", "") == want:
				return str(a.get("browser_download_url", ""))
	return ""

func _is_newer(a: String, b: String) -> bool:
	var pa = a.split(".")
	var pb = b.split(".")
	for i in range(3):
		var na = int(pa[i]) if i < pa.size() else 0
		var nb = int(pb[i]) if i < pb.size() else 0
		if na != nb:
			return na > nb
	return false

func install():
	if state != "available":
		return
	if not OS.has_feature("template"):
		_fail("Self-update only works in a downloaded build")
		return
	if download_url == "":
		_fail("This release has no build for your platform")
		return
	state = "downloading"
	status_changed.emit()
	var req := HTTPRequest.new()
	add_child(req)
	req.download_file = "user://update.zip"
	req.request_completed.connect(func(_r, code, _h, _b):
		req.queue_free()
		_on_download_done(code)
	)
	if req.request(download_url, _headers()) != OK:
		req.queue_free()
		_fail("Download failed to start")

func _on_download_done(code: int):
	if code != 200:
		_fail("Download failed (%d)" % code)
		return
	state = "installing"
	status_changed.emit()
	var zip := ZIPReader.new()
	if zip.open(ProjectSettings.globalize_path("user://update.zip")) != OK:
		_fail("Could not open the downloaded archive")
		return
	# find the game binary in the archive — on macOS it's the Mach-O
	# inside the .app bundle (the pck is embedded, so one file is enough)
	var entry := ""
	for f in zip.get_files():
		if f.ends_with("SliceIt.exe") or f.ends_with("SliceIt.x86_64") \
				or f.ends_with("Contents/MacOS/SliceIt"):
			entry = f
			break
	if entry == "":
		zip.close()
		_fail("No game binary inside the update")
		return
	var bytes := zip.read_file(entry)
	zip.close()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://update.zip"))

	# park the running binary as .old (renaming a running executable is
	# allowed on Windows and POSIX; overwriting is not), write the new one
	# at the original path, relaunch and quit
	var exe := OS.get_executable_path()
	if DirAccess.rename_absolute(exe, exe + ".old") != OK:
		_fail("Could not move the old binary aside")
		return
	var out := FileAccess.open(exe, FileAccess.WRITE)
	if out == null:
		DirAccess.rename_absolute(exe + ".old", exe)  # roll back
		_fail("Could not write the new binary")
		return
	out.store_buffer(bytes)
	out.close()
	if OS.get_name() != "Windows":
		OS.execute("chmod", ["+x", exe])
	OS.create_process(exe, ["--updated"])
	get_tree().quit()

func _cleanup_old():
	# best-effort: on Windows the old exe can stay locked for a moment
	# after the swap-restart, in which case the next launch gets it
	var old := OS.get_executable_path() + ".old"
	if FileAccess.file_exists(old):
		DirAccess.remove_absolute(old)

func _fail(msg: String):
	error_msg = msg
	state = "error"
	status_changed.emit()

func _headers() -> PackedStringArray:
	return PackedStringArray([
		"User-Agent: SliceIt-Updater",
		"Accept: application/vnd.github+json",
	])
