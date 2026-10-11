extends Node
## Talks to the multiplayer server (Supabase): signing up and in with email
## and password, keeping the session (user://online.cfg remembers it between
## runs), and sending orders to the "game" function one at a time. The server
## decides everything; its answers go to Economy.apply_server().
##
## The server's address comes from data/online.json; pass
## --online-url=http://127.0.0.1:54321 after "--" on the command line to use
## the local stand-in (server/dev/local_server.ts) instead.

const CONFIG_PATH := "res://data/online.json"
const SESSION_PATH := "user://online.cfg"
const TIMEOUT := 20.0

## Fires when an order the server answered was refused or failed.
signal order_failed(message: String)

var url := ""
var key := ""
var email := ""
var _access := ""
var _refresh := ""
var _expires := 0.0
var _queue: Array[Dictionary] = []
var _busy := false


func _ready() -> void:
	var config := GameData.load_json(CONFIG_PATH)
	url = String(config.get("url", "")).trim_suffix("/")
	key = String(config.get("key", ""))
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--online-url="):
			url = arg.trim_prefix("--online-url=").trim_suffix("/")
	var cfg := ConfigFile.new()
	if cfg.load(SESSION_PATH) == OK and cfg.get_value("session", "url", "") == url:
		email = cfg.get_value("session", "email", "")
		_refresh = cfg.get_value("session", "refresh_token", "")


func has_saved_session() -> bool:
	return _refresh != ""


func signed_in() -> bool:
	return _access != ""


func busy() -> bool:
	return _busy or not _queue.is_empty()


# --- Accounts -------------------------------------------------------------------

func sign_up(p_email: String, password: String) -> String:
	## Creates an account. Returns "" when signed in, or why not. If the
	## server wants the address confirmed first it says so.
	var res := await _post("/auth/v1/signup", {"email": p_email.strip_edges(), "password": password}, false)
	if res.data.has("access_token"):
		_take_session(res.data, p_email)
		return ""
	if res.status == 200 and res.data.has("id"):
		return "Check your email and click the link to confirm your account, then sign in."
	return _auth_error(res)


func sign_in(p_email: String, password: String) -> String:
	var res := await _post("/auth/v1/token?grant_type=password",
			{"email": p_email.strip_edges(), "password": password}, false)
	if res.data.has("access_token"):
		_take_session(res.data, p_email)
		return ""
	return _auth_error(res)


func resume() -> bool:
	## Signs in again with the remembered session, if there is one.
	if _refresh == "":
		return false
	var res := await _post("/auth/v1/token?grant_type=refresh_token", {"refresh_token": _refresh}, false)
	if res.data.has("access_token"):
		_take_session(res.data, email)
		return true
	sign_out()
	return false


func sign_out() -> void:
	_access = ""
	_refresh = ""
	_expires = 0.0
	_queue.clear()
	var cfg := ConfigFile.new()
	cfg.save(SESSION_PATH)


# --- Orders ---------------------------------------------------------------------

func call_game(body: Dictionary) -> Dictionary:
	## Sends one request to the game function now and returns its answer:
	## {"ok", "error", "player", "reports", "now", ...}. On a connection
	## problem "ok" is false and "error" says what went wrong.
	if _expires > 0.0 and Time.get_unix_time_from_system() > _expires - 60.0:
		await resume()
	var res := await _post("/functions/v1/game", body, true)
	if res.status == 401 and await resume():
		res = await _post("/functions/v1/game", body, true)
	if res.status == 0:
		return {"ok": false, "error": "Can't reach the server. Check your internet connection."}
	if res.status == 401:
		return {"ok": false, "error": "Please sign in again.", "signed_out": true}
	if not res.data.has("ok"):
		return {"ok": false, "error": "The server answered with an error (%d)." % res.status}
	return res.data


func order(body: Dictionary) -> void:
	## Queues an order for the server. Orders go one at a time in the order
	## given; the castle is updated from the server's answer once the queue
	## is empty, or straight away if an order was refused.
	_queue.append(body)
	if not _busy:
		_run_queue()


func refresh() -> void:
	## Asks the server for the latest state, unless orders are on their way.
	if not busy():
		order({"action": "state"})


func _run_queue() -> void:
	_busy = true
	while not _queue.is_empty():
		var body: Dictionary = _queue.pop_front()
		var answer := await call_game(body)
		var refused: bool = not answer.get("ok", false) or String(answer.get("error", "")) != ""
		if refused:
			order_failed.emit(String(answer.get("error", "")))
		if answer.has("player") and (refused or _queue.is_empty()):
			Economy.apply_server(answer)
	_busy = false


# --- Internals ------------------------------------------------------------------

func _take_session(data: Dictionary, p_email: String) -> void:
	_access = String(data.access_token)
	_refresh = String(data.get("refresh_token", ""))
	_expires = Time.get_unix_time_from_system() + float(data.get("expires_in", 3600))
	email = p_email.strip_edges()
	var cfg := ConfigFile.new()
	cfg.set_value("session", "url", url)
	cfg.set_value("session", "email", email)
	cfg.set_value("session", "refresh_token", _refresh)
	cfg.save(SESSION_PATH)


func _auth_error(res: Dictionary) -> String:
	if res.status == 0:
		return "Can't reach the server. Check your internet connection."
	var code := String(res.data.get("error_code", res.data.get("error", "")))
	match code:
		"invalid_credentials", "invalid_grant":
			return "Wrong email or password."
		"user_already_exists":
			return "There's already an account with that email. Sign in instead."
		"weak_password":
			return "Choose a longer password (at least 6 characters)."
		"email_not_confirmed":
			return "Confirm your email first: click the link we sent you."
		"over_email_send_rate_limit", "over_request_rate_limit":
			return "Too many tries. Wait a minute and try again."
	var msg := String(res.data.get("msg", res.data.get("error_description", "")))
	return msg if msg != "" else "The server answered with an error (%d)." % res.status


func _post(path: String, body: Dictionary, signed: bool) -> Dictionary:
	## POSTs JSON and returns {"status": HTTP code (0 if unreachable), "data": Dictionary}.
	if url == "":
		return {"status": 0, "data": {}}
	var http := HTTPRequest.new()
	http.timeout = TIMEOUT
	http.use_threads = true
	add_child(http)
	var headers := PackedStringArray(["Content-Type: application/json", "apikey: " + key])
	if signed:
		headers.append("Authorization: Bearer " + _access)
	if http.request(url + path, headers, HTTPClient.METHOD_POST, JSON.stringify(body)) != OK:
		http.queue_free()
		return {"status": 0, "data": {}}
	var res: Array = await http.request_completed
	http.queue_free()
	if int(res[0]) != HTTPRequest.RESULT_SUCCESS:
		return {"status": 0, "data": {}}
	var data = JSON.parse_string((res[3] as PackedByteArray).get_string_from_utf8())
	return {"status": int(res[1]), "data": data if data is Dictionary else {}}
