class_name NoticeRules
extends RefCounted
## Works out what is worth telling the player about by comparing a castle
## before and after the economy moved on: buildings finished, studies done,
## soldiers trained and siege tools made. The Notices autoload shows them.
##
## A snapshot is plain data, so the same comparison works offline and online,
## where the server's answer replaces the castle the game ran ahead.


static func snapshot(castle: CastleState) -> Dictionary:
	var built := {}
	for b in castle.buildings:
		built[int(b.id)] = {"type": String(b.type), "level": int(b.level), "target": int(b.target)}
	var study := {}
	if not castle.studying.is_empty():
		study = {"study": String(castle.studying.study), "target": int(castle.studying.target)}
	return {
		"name": castle.castle_name,
		"buildings": built,
		"studying": study,
		"research": castle.research.duplicate(),
		"training": _queue(castle.training, "unit"),
		"trained": int(castle.stats.get("trained", 0)),
		"crafting": _queue(castle.crafting, "tool"),
		"tools": _total(castle.tools),
	}


static func changes(rules: BuildingRules, before: Dictionary, after: Dictionary, main: bool) -> Array[Dictionary]:
	## What finished between two snapshots of one castle, as notices
	## {"key", "title", "text", "icon"}. The key is the same for the same
	## event however it was seen, so a notice is shown once.
	var found: Array[Dictionary] = []
	var where := "" if main else "%s: " % after.name
	for id: int in before.buildings:
		var old: Dictionary = before.buildings[id]
		var now: Dictionary = after.buildings.get(id, {})
		if old.target <= 0 or now.is_empty() or now.level < old.target:
			continue
		var text := "%s%s reached level %d" % [where, rules.display_name(old.type), old.target]
		if old.level == 0:
			text = "%sYour new %s is built" % [where, rules.display_name(old.type)]
		found.append({"key": "build:%s:%d:%d" % [after.name, id, old.target], "title": "Building finished",
				"text": text, "icon": "builders"})
	var study: Dictionary = before.studying
	if not study.is_empty() and int(after.research.get(study.study, 0)) >= int(study.target):
		found.append({"key": "study:%s:%s:%d" % [after.name, study.study, study.target], "title": "Research done",
				"text": "%s%s reached level %d" % [where, rules.study_name(study.study), study.target], "icon": "research"})
	if after.trained > before.trained:
		for batch: Dictionary in _gone(before.training, after.training):
			found.append({"key": "train:%s:%s" % [after.name, batch.key], "title": "Soldiers ready",
					"text": "%sYour %s have finished training" % [where, rules.unit_plural(batch.what)], "icon": "soldiers"})
	if after.tools > before.tools:
		for batch: Dictionary in _gone(before.crafting, after.crafting):
			found.append({"key": "craft:%s:%s" % [after.name, batch.key], "title": "Workshop done",
					"text": "%sYour %s are ready" % [where, rules.tool_plural(batch.what)], "icon": "battle"})
	return found


static func _queue(batches: Array, field: String) -> Array:
	## Each batch with a key from what it makes and when it will be done,
	## which the game's guess and the server's answer agree on.
	## Only the first batch has a start time; the others follow it.
	var out := []
	var done := 0.0
	for b: Dictionary in batches:
		if out.is_empty():
			done = float(b.next) + float(b.unit_time) * maxf(float(b.remaining) - 1.0, 0.0)
		else:
			done += float(b.unit_time) * float(b.remaining)
		out.append({"what": String(b[field]), "key": "%s@%d" % [b[field], roundi(done / 10.0)]})
	return out


static func _gone(before: Array, after: Array) -> Array:
	var left := {}
	for b: Dictionary in after:
		left[b.key] = true
	return before.filter(func(b: Dictionary) -> bool: return not left.has(b.key))


static func _total(counts: Dictionary) -> int:
	var n := 0
	for k in counts:
		n += int(counts[k])
	return n


static func desktop_command(os_name: String, title: String, text: String) -> Array:
	## The program and arguments that show a notice on the desktop, or [] where
	## there is no way to. Windows uses PowerShell's toast, Linux notify-send
	## and macOS AppleScript, all of which come with the system.
	match os_name:
		"Windows":
			var xml := "<toast><visual><binding template=\"ToastGeneric\"><text>%s</text><text>%s</text></binding></visual></toast>" \
					% [title.xml_escape(true), text.xml_escape(true)]
			var script := "\n".join([
				"[Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime] > $null",
				"[Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime] > $null",
				"$x = New-Object Windows.Data.Xml.Dom.XmlDocument",
				"$x.LoadXml('%s')" % xml.replace("'", "''"),
				"$t = [Windows.UI.Notifications.ToastNotification]::new($x)",
				"[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier('{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\\WindowsPowerShell\\v1.0\\powershell.exe').Show($t)",
			])
			# PowerShell takes the script as base64 of UTF-16, so nothing needs quoting.
			return ["powershell.exe", ["-NoProfile", "-NonInteractive", "-WindowStyle", "Hidden",
					"-EncodedCommand", Marshalls.raw_to_base64(script.to_utf16_buffer())]]
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			return ["notify-send", ["--app-name=Medieval Strategy", title, text]]
		"macOS":
			var quote := func(s: String) -> String: return "\"%s\"" % s.replace("\\", "\\\\").replace("\"", "\\\"")
			return ["osascript", ["-e", "display notification %s with title %s" % [quote.call(text), quote.call(title)]]]
	return []
