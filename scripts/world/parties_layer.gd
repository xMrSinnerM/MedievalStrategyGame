extends Node3D
## Spawns the parties from data/parties.json, moves the lords around their
## realms and lets the player send their own party anywhere with a click.
## Each party is the warband of its home castle: its troop count comes from
## that castle's economy, and lords pick up reinforcements when they visit it.
##
## Warbands of factions at war fight when they meet in the open (Battle
## auto-resolves it). Lords sometimes raid enemy land, and a lord at war with
## you who spots your warband gives chase if they fancy their chances (but
## not while it stands at your castle). You can march on any lord outside
## your own faction from their party's panel.
##
## Sieges: from an enemy castle's panel your warband marches to its walls,
## camps there for Battle.siege_time() and then storms it (Battle.assault).
## Walking away lifts the siege, and so does losing a battle while camped.
## Lords besiege castles of factions they are at war with, yours included,
## when they are confident of taking them; any battle the besieger fights
## lifts the siege, so you can ride to the rescue.
##
## Controls: left click on the ground, a town or a village to travel there
## (clicking a castle or a party opens its panel instead), F to centre the
## camera on your party.

const ROUTE_SHADER := preload("res://shaders/route.gdshader")
const CLICK_SLOP := 6.0          ## pixels the mouse may move and still count as a click
const ROUTE_STEP := 3.0          ## route ribbon resolution in map units
const ROUTE_REFRESH := 0.2       ## seconds between ribbon rebuilds while walking
const LORD_WAIT := Vector2(4.0, 10.0)      ## seconds a lord rests in a settlement
const LORD_RANGE := 750.0                   ## lords prefer settlements within this distance
const RAID_CHANCE := 0.2                    ## chance a lord at war heads into enemy land
const CONTACT := 7.0             ## map units between two warbands that start a battle
const SIGHT := 70.0              ## how far a lord spots your warband
const GIVE_UP := 120.0           ## a chasing lord gives up beyond this distance
const CHASE_ODDS := 0.65         ## a lord chases you only when this likely to win
const CHASE_REPATH := 0.5        ## seconds between route updates while chasing
const TRUCE := 20.0              ## seconds after a battle before either side fights again
const PICK_RADIUS := 26.0        ## pixels around a party that count as clicking it
const SIEGE_CHANCE := 0.05       ## chance a lord's next move is a siege, when one is worth it
const SIEGE_ODDS := 0.7          ## a lord besieges only when this likely to win the assault
const SIEGE_RANGE := 650.0       ## lords besiege castles within this distance
const SIEGE_MIN_WARBAND := 40    ## lords with fewer soldiers don't besiege
const CASTLE_TRUCE := 600.0      ## seconds after an assault before lords besiege that castle again

var parties: Array[Party] = []
var player: Party
var camera_rig: CampaignCamera

var _rng := RandomNumberGenerator.new()
var _lord_timers := {}           ## Party -> seconds left resting
var _press_pos := Vector2.ZERO
var _pressed := false
var _route: MeshInstance3D
var _route_material: ShaderMaterial
var _marker: MeshInstance3D
var _ring: MeshInstance3D
var _route_timer := 0.0
var _zoom_t := 0.0
var _status := ""
var _encounter_timer := 0.0
var _chase_timers := {}          ## Party -> seconds until its route is updated
var _sized_up := {}              ## lord Party -> seconds before it may size you up again
var _siege_target := ""          ## castle your warband is marching on to besiege
var _siege_castle := ""          ## castle your warband is besieging now
var _siege_until := 0.0          ## when the assault comes (seconds since start)
var _siege_label: Label3D
var _lord_sieges := {}           ## lord Party -> {"castle", "until" (0 while marching), "label"}
var _castle_truce := {}          ## castle id -> no lord sieges before this time


func build() -> void:
	_rng.seed = 7
	for data in GameData.parties:
		var start := GameData.get_settlement(data.get("start", ""))
		if start.is_empty():
			push_warning("Party %s has no valid start settlement" % data.id)
			continue
		if not data.get("player", false) and Economy.home_of(data.id, data.get("home", "")) == "":
			continue   # exiled: their faction has no castle left
		var party := Party.new()
		add_child(party)
		party.setup(data)
		if not party.is_player:
			party.home = Economy.home_of(party.id, party.home)
		var home := Vector2(start.position[0], start.position[1])
		if party.is_player:
			player = party
			party.place_at(_outside(start))
		else:
			party.place_at(home)
			party.enter_settlement(start.id)
			_lord_timers[party] = _rng.randf_range(0.5, LORD_WAIT.y)
		party.arrived.connect(_on_arrived)
		parties.append(party)

	_build_markers()
	_sync_troops()
	_update_warband_home()
	Economy.changed.connect(_sync_troops)
	EventBus.camera_zoom_changed.connect(_on_zoom_changed)
	EventBus.travel_requested.connect(_travel_to_settlement)
	EventBus.attack_requested.connect(_attack)
	EventBus.siege_requested.connect(_besiege)
	_set_status("Camped outside %s" % _nearest_settlement_name(player.map_position()) if player else "")


func _build_markers() -> void:
	_route_material = ShaderMaterial.new()
	_route_material.shader = ROUTE_SHADER
	MapStyle.apply_common(_route_material)
	_route = MeshInstance3D.new()
	_route.name = "Route"
	_route.material_override = _route_material
	_route.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_route)

	var gold := StandardMaterial3D.new()
	gold.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	gold.albedo_color = Color(1.0, 0.84, 0.4)
	var torus := TorusMesh.new()
	torus.inner_radius = 2.2
	torus.outer_radius = 2.8
	torus.rings = 24
	torus.ring_segments = 6
	_marker = MeshInstance3D.new()
	_marker.name = "DestinationMarker"
	_marker.mesh = torus
	_marker.material_override = gold
	_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_marker.visible = false
	add_child(_marker)

	_siege_label = _make_siege_label()

	# A ring under the player's party so it is easy to spot.
	var ring_mesh := TorusMesh.new()
	ring_mesh.inner_radius = 3.4
	ring_mesh.outer_radius = 3.9
	ring_mesh.rings = 32
	ring_mesh.ring_segments = 6
	_ring = MeshInstance3D.new()
	_ring.name = "PlayerRing"
	_ring.mesh = ring_mesh
	_ring.material_override = gold
	_ring.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(_ring)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressed = true
			_press_pos = event.position
		elif _pressed:
			_pressed = false
			if event.position.distance_to(_press_pos) <= CLICK_SLOP:
				_on_click(event.position)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F:
		if player and camera_rig:
			camera_rig.focus_on(player.position)


func _on_click(screen_pos: Vector2) -> void:
	if player == null:
		return
	var cam := get_viewport().get_camera_3d()
	var clicked := _party_at(cam, screen_pos)
	if clicked != null and clicked != player:
		EventBus.settlement_selected.emit("")
		EventBus.party_selected.emit(clicked.id)
		return
	EventBus.party_selected.emit("")
	var hit = GameData.terrain.raycast(cam.project_ray_origin(screen_pos), cam.project_ray_normal(screen_pos))
	if hit == null:
		return
	var target := Vector2(hit.x, hit.z)
	var settlement := _settlement_at(target)
	if settlement.get("type", "") == "castle":
		EventBus.settlement_selected.emit(settlement.id)
		return
	EventBus.settlement_selected.emit("")
	if not settlement.is_empty():
		target = Vector2(settlement.position[0], settlement.position[1])
	_travel(target, settlement)


func _travel_to_settlement(settlement_id: String) -> void:
	var settlement := GameData.get_settlement(settlement_id)
	if player != null and not settlement.is_empty():
		_travel(Vector2(settlement.position[0], settlement.position[1]), settlement)


func _party_at(cam: Camera3D, screen_pos: Vector2) -> Party:
	var best: Party = null
	var best_d := PICK_RADIUS
	for p in parties:
		if not p.is_shown():
			continue
		var at := p.position + Vector3(0, 1.5 * p.display_scale(), 0)
		if cam.is_position_behind(at):
			continue
		var d := cam.unproject_position(at).distance_to(screen_pos)
		if d < best_d:
			best_d = d
			best = p
	return best


func get_party(party_id: String) -> Party:
	for p in parties:
		if p.id == party_id:
			return p
	return null


func _attack(party_id: String) -> void:
	var target := get_party(party_id)
	if player == null or target == null or target == player or not GameData.at_war(player.faction_id, target.faction_id):
		return   # war is declared first (the diplomacy screen asks)
	_lift_siege()
	_start_chase(player, target)
	if player.chasing == target:
		_set_status("Marching on %s" % target.party_name)
	else:
		_set_status("No way to reach %s" % target.party_name)


func _start_chase(hunter: Party, prey: Party) -> void:
	var close := hunter.map_position().distance_to(prey.map_position()) <= CONTACT
	if hunter.travel_to(prey.map_position()) or close:
		hunter.chasing = prey
		_chase_timers[hunter] = CHASE_REPATH
		if hunter == player:
			Economy.warband_home = false
			_route_timer = 0.0


func _besiege(castle_id: String) -> void:
	var settlement := GameData.get_settlement(castle_id)
	if player == null or settlement.is_empty() or Economy.get_castle(castle_id) == null \
			or not GameData.at_war(player.faction_id, settlement.faction):
		return
	_lift_siege()
	player.chasing = null
	if player.map_position().distance_to(Vector2(settlement.position[0], settlement.position[1])) <= _siege_reach(settlement):
		_start_siege(castle_id)
	elif player.travel_to(_outside(settlement, player.map_position())):
		_siege_target = castle_id
		Economy.warband_home = false
		_route_timer = 0.0
		_set_status("Marching on %s to lay siege" % settlement.name)
	else:
		_set_status("No way to reach %s" % settlement.name)


func _siege_reach(settlement: Dictionary) -> float:
	return SettlementModels.RADIUS.get(settlement.type, 20.0) + 30.0


func _make_siege_label() -> Label3D:
	var label := Label3D.new()
	label.name = "SiegeLabel"
	label.font_size = 34
	label.outline_size = 10
	label.modulate = Color(1.0, 0.55, 0.4)
	label.outline_modulate = Color(0.16, 0.08, 0.05, 0.9)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.fixed_size = true
	label.pixel_size = 0.0005
	label.no_depth_test = true
	label.render_priority = 13
	label.outline_render_priority = 12
	label.shaded = false
	label.visible = false
	add_child(label)
	return label


func _place_siege_label(label: Label3D, castle_id: String) -> void:
	var settlement := GameData.get_settlement(castle_id)
	var x: float = settlement.position[0]
	var z: float = settlement.position[1]
	label.position = Vector3(x, Party.ground_height(x, z) + SettlementModels.TOP.castle + 14.0, z)
	label.visible = true


func _start_siege(castle_id: String) -> void:
	var castle := Economy.get_castle(castle_id)
	_siege_target = ""
	_siege_castle = castle_id
	_siege_until = Time.get_ticks_msec() * 0.001 + Battle.siege_time(castle)
	_place_siege_label(_siege_label, castle_id)
	_update_siege()


func _lift_siege() -> void:
	if _siege_castle != "":
		_set_status("Lifted the siege of %s" % GameData.get_settlement(_siege_castle).name)
	_siege_target = ""
	_siege_castle = ""
	_siege_label.visible = false


func _update_siege() -> void:
	var left := _siege_until - Time.get_ticks_msec() * 0.001
	var castle_name: String = GameData.get_settlement(_siege_castle).name
	if left > 0.0:
		_siege_label.text = "Siege: %d s" % ceili(left)
		_set_status("Besieging %s, assault in %d s" % [castle_name, ceili(left)])
	else:
		_storm(_siege_castle)


func _storm(castle_id: String) -> void:
	## The siege camp is ready: storm the walls.
	_siege_castle = ""
	_siege_label.visible = false
	var castle := Economy.get_castle(castle_id)
	var mine := Economy.get_castle(player.home)
	if castle == null or mine == null:
		return
	var result := Battle.assault(mine, castle, hash(castle_id) + Time.get_ticks_msec(), Economy.MAIN_CASTLE)
	var report := {
		"attacker": player.party_name, "defender": castle.castle_name,
		"attacker_faction": player.faction_id, "defender_faction": castle.owner,
		"place": castle.castle_name, "winner": result.winner, "a": result.a, "b": result.b,
		"loot": result.loot, "player": "a", "siege": true, "outcome": result.outcome,
		"spoils": result.get("spoils", {}),
	}
	player.truce_until = Time.get_ticks_msec() * 0.001 + TRUCE
	if result.outcome == "captured":
		Economy.capture(castle, "player", GameData.parties, GameData.settlements)
		_set_status("Captured %s" % castle.castle_name)
	elif result.outcome == "sacked":
		_set_status("Sacked %s" % castle.castle_name)
	else:
		_set_status("Driven back from the walls of %s" % castle.castle_name)
	Economy.save_game()
	Economy.changed.emit()
	EventBus.battle_fought.emit(report)


func on_castle_captured(castle_id: String) -> void:
	## Lords whose castle fell move to their new home, or leave the map.
	## Sieges of a castle that is no longer an enemy's are called off.
	if _siege_castle == castle_id and Economy.get_castle(castle_id).owner == "player":
		_lift_siege()
	for lord: Party in _lord_sieges.keys():
		if _lord_sieges[lord].castle == castle_id and not _hostile_castle(lord, GameData.get_settlement(castle_id)):
			_lift_lord_siege(lord)
	for p: Party in parties.duplicate():
		if p.is_player:
			continue
		var home := Economy.home_of(p.id, p.home)
		if home == "":
			_lift_lord_siege(p)
			parties.erase(p)
			_lord_timers.erase(p)
			for hunter in parties:
				if hunter.chasing == p:
					hunter.stop()
			p.queue_free()
			continue
		if home != p.home:
			p.home = home
			if p.inside_settlement == castle_id:
				_send_home(p)
	_sync_troops()


func on_diplomacy_changed() -> void:
	## Peace calls off sieges and chases between factions no longer at war.
	if _siege_castle != "" and not GameData.at_war(player.faction_id, GameData.get_settlement(_siege_castle).faction):
		_lift_siege()
	for lord: Party in _lord_sieges.keys():
		if not _hostile_castle(lord, GameData.get_settlement(_lord_sieges[lord].castle)):
			_lift_lord_siege(lord)
	for hunter in parties:
		if hunter != player and hunter.chasing != null and not GameData.at_war(hunter.faction_id, hunter.chasing.faction_id):
			hunter.stop()
			_lord_timers[hunter] = 1.0


func _travel(target: Vector2, settlement: Dictionary) -> void:
	_lift_siege()
	player.chasing = null
	if player.travel_to(target, settlement.get("id", "")):
		Economy.warband_home = false
		_set_status("Travelling to %s" % settlement.name if not settlement.is_empty() else "Travelling")
		_route_timer = 0.0
	else:
		_set_status("No way to get there")


func _sync_troops() -> void:
	for p in parties:
		var castle := Economy.get_castle(p.home)
		if castle != null:
			p.set_troops(castle.field_count())


func _update_warband_home() -> void:
	## Troops can change hands while your warband stands at (or in) your castle.
	var at_home := false
	var castle := GameData.get_settlement(player.home) if player else {}
	if not castle.is_empty() and not player.moving:
		var centre := Vector2(castle.position[0], castle.position[1])
		var reach: float = SettlementModels.RADIUS.get(castle.type, 20.0) + 24.0
		at_home = player.inside_settlement == player.home or player.map_position().distance_to(centre) <= reach
	Economy.warband_home = at_home


func _on_arrived(party: Party) -> void:
	if party.chasing != null:
		return   # reached where the prey was; the next route update follows it
	if _lord_sieges.has(party) and _lord_sieges[party].until == 0.0:
		_start_lord_siege(party)
		return
	if party == player and _siege_target != "":
		var castle := GameData.get_settlement(_siege_target)
		if party.map_position().distance_to(Vector2(castle.position[0], castle.position[1])) <= _siege_reach(castle):
			_route.mesh = null
			_marker.visible = false
			_start_siege(_siege_target)
			return
	if party == player:
		_update_warband_home()
		if not party.inside_settlement.is_empty():
			_set_status("Staying in %s" % GameData.get_settlement(party.inside_settlement).name)
		else:
			_set_status("Camped")
		_route.mesh = null
		_marker.visible = false
	else:
		if party.inside_settlement.is_empty():
			# Stopped short (an unreachable target); pick somewhere else soon.
			_lord_timers[party] = 1.0
		else:
			_lord_timers[party] = _rng.randf_range(LORD_WAIT.x, LORD_WAIT.y)
			if party.inside_settlement == party.home:
				var castle := Economy.get_castle(party.home)
				if castle != null and NpcBrain.resupply(castle) > 0:
					_sync_troops()


func _on_zoom_changed(zoom_t: float) -> void:
	_zoom_t = zoom_t
	for p in parties:
		p.set_zoom(zoom_t)


func _process(delta: float) -> void:
	_update_lords(delta)
	_update_chases(delta)
	_encounter_timer -= delta
	if _encounter_timer <= 0.0:
		_encounter_timer = 0.2
		_check_encounters()
	_update_lord_sieges()
	if player == null:
		return
	if _siege_castle != "":
		_update_siege()
	var s := player.display_scale()
	_ring.visible = player.is_shown()
	_ring.position = player.position + Vector3(0, 0.3, 0)
	_ring.scale = Vector3(s, 0.4 * s, s)
	if player.moving:
		_route_timer -= delta
		if _route_timer <= 0.0:
			_route_timer = ROUTE_REFRESH
			_rebuild_route()
		var end := player.path[player.path.size() - 1]
		var pulse := 1.0 + 0.15 * sin(Time.get_ticks_msec() * 0.006)
		_marker.visible = true
		_marker.position = Vector3(end.x, Party.ground_height(end.x, end.y) + 0.4, end.y)
		_marker.scale = Vector3(s * pulse, 0.4 * s, s * pulse)
		_set_status(_status.get_slice(" (", 0) + " (%s)" % GameData.nav.kind_name(player.position.x, player.position.z).to_lower())


func _update_lords(delta: float) -> void:
	for party: Party in _lord_timers.keys():
		if party.moving or party.chasing != null or _lord_sieges.has(party):
			continue
		_lord_timers[party] -= delta
		if _lord_timers[party] > 0.0:
			continue
		var siege := _pick_siege_target(party) if _rng.randf() < SIEGE_CHANCE else {}
		if not siege.is_empty() and party.travel_to(_outside(siege, party.map_position())):
			_lord_sieges[party] = {"castle": siege.id, "until": 0.0, "label": null}
			continue
		var target := _pick_lord_destination(party)
		if target.is_empty() or not party.travel_to(Vector2(target.position[0], target.position[1]), target.id):
			_lord_timers[party] = _rng.randf_range(LORD_WAIT.x, LORD_WAIT.y)


func _pick_lord_destination(party: Party) -> Dictionary:
	## Another settlement of the lord's own faction, preferring nearby ones.
	## A lord whose warband has shrunk below half strength heads home first.
	var castle := Economy.get_castle(party.home)
	if castle != null and party.inside_settlement != party.home \
			and castle.field_count() < NpcBrain.WARBAND_BASE / 2 and castle.troop_count() > 0:
		var home := GameData.get_settlement(party.home)
		if not home.is_empty():
			return home
	var here := party.map_position()
	if _rng.randf() < RAID_CHANCE:
		var raid := _pick_raid_target(party)
		if not raid.is_empty():
			return raid
	var near: Array[Dictionary] = []
	var all: Array[Dictionary] = []
	for s in GameData.settlements:
		if s.faction != party.faction_id or s.id == party.inside_settlement or s.get("player", false):
			continue
		all.append(s)
		if here.distance_to(Vector2(s.position[0], s.position[1])) < LORD_RANGE:
			near.append(s)
	var pool := near if not near.is_empty() else all
	return pool[_rng.randi() % pool.size()] if not pool.is_empty() else {}


func _hostile_castle(lord: Party, settlement: Dictionary) -> bool:
	return settlement.get("type", "") == "castle" and GameData.at_war(lord.faction_id, settlement.faction)


func _besieged(castle_id: String) -> bool:
	if _siege_castle == castle_id or _siege_target == castle_id:
		return true
	for lord: Party in _lord_sieges:
		if _lord_sieges[lord].castle == castle_id:
			return true
	return false


func _pick_siege_target(lord: Party) -> Dictionary:
	## The nearest enemy castle this lord is confident of storming, or {}.
	var home := Economy.get_castle(lord.home)
	if home == null or home.field_count() < SIEGE_MIN_WARBAND:
		return {}
	var now := Time.get_ticks_msec() * 0.001
	var here := lord.map_position()
	var best := {}
	var best_d := SIEGE_RANGE
	for s in GameData.settlements:
		if not _hostile_castle(lord, s) or _castle_truce.get(s.id, 0.0) > now or _besieged(s.id):
			continue
		if s.id == Economy.MAIN_CASTLE and Economy.newcomer_protected():
			continue
		var d := here.distance_to(Vector2(s.position[0], s.position[1]))
		var castle := Economy.get_castle(s.id)
		if d >= best_d or castle == null:
			continue
		if Battle.odds(Economy.rules, home.field, castle.troops, 1, Battle.wall_bonus(castle)) >= SIEGE_ODDS:
			best = s
			best_d = d
	return best


func _start_lord_siege(lord: Party) -> void:
	var siege: Dictionary = _lord_sieges[lord]
	var settlement := GameData.get_settlement(siege.castle)
	var castle := Economy.get_castle(siege.castle)
	if castle == null or lord.map_position().distance_to(Vector2(settlement.position[0], settlement.position[1])) > _siege_reach(settlement):
		_lift_lord_siege(lord)   # couldn't get to the walls
		return
	siege.until = Time.get_ticks_msec() * 0.001 + Battle.siege_time(castle)
	siege.label = _make_siege_label()
	_place_siege_label(siege.label, siege.castle)
	EventBus.siege_started.emit(siege.castle, lord.party_name, siege.until)


func _lift_lord_siege(lord: Party) -> void:
	if not _lord_sieges.has(lord):
		return
	var siege: Dictionary = _lord_sieges[lord]
	_lord_sieges.erase(lord)
	_lord_timers[lord] = 1.0
	if siege.label != null:
		siege.label.queue_free()
		EventBus.siege_ended.emit(siege.castle)


func _update_lord_sieges() -> void:
	var now := Time.get_ticks_msec() * 0.001
	for lord: Party in _lord_sieges.keys():
		var siege: Dictionary = _lord_sieges[lord]
		if siege.until == 0.0:
			if not lord.moving:
				_lift_lord_siege(lord)   # stopped short of the walls
			continue
		if now < siege.until:
			siege.label.text = "Siege: %d s" % ceili(siege.until - now)
		else:
			var castle_id: String = siege.castle
			_lift_lord_siege(lord)
			_lord_storm(lord, castle_id)


func _lord_storm(lord: Party, castle_id: String) -> void:
	var castle := Economy.get_castle(castle_id)
	var mine := Economy.get_castle(lord.home)
	if castle == null or mine == null:
		return
	var yours := castle.owner == "player"
	var result := Battle.assault(mine, castle, hash(lord.id + castle_id) + Time.get_ticks_msec(), Economy.MAIN_CASTLE)
	var report := {
		"attacker": lord.party_name, "defender": castle.castle_name,
		"attacker_faction": lord.faction_id, "defender_faction": castle.owner,
		"place": castle.castle_name, "winner": result.winner, "a": result.a, "b": result.b,
		"loot": result.loot, "player": "b" if yours else "", "siege": true,
		"outcome": result.outcome, "spoils": result.get("spoils", {}),
	}
	var now := Time.get_ticks_msec() * 0.001
	_castle_truce[castle_id] = now + CASTLE_TRUCE
	lord.truce_until = now + TRUCE
	if result.outcome == "captured":
		Economy.capture(castle, lord.faction_id, GameData.parties, GameData.settlements)
	if result.outcome == "held":
		_send_home(lord)
	else:
		_lord_timers[lord] = 2.0
	Economy.save_game()
	Economy.changed.emit()
	EventBus.battle_fought.emit(report)


func _pick_raid_target(party: Party) -> Dictionary:
	## A nearby town or village of a faction this lord is at war with.
	var here := party.map_position()
	var pool: Array[Dictionary] = []
	for s in GameData.settlements:
		if s.type == "castle" or s.get("player", false) or not GameData.at_war(party.faction_id, s.faction):
			continue
		if here.distance_to(Vector2(s.position[0], s.position[1])) < LORD_RANGE:
			pool.append(s)
	return pool[_rng.randi() % pool.size()] if not pool.is_empty() else {}


func _update_chases(delta: float) -> void:
	for hunter in parties:
		var prey := hunter.chasing
		if prey == null:
			continue
		var gap := hunter.map_position().distance_to(prey.map_position())
		var lost := not prey.inside_settlement.is_empty() or not prey.is_shown()
		if not lost and hunter != player and (gap > GIVE_UP or (prey == player and Economy.warband_home)):
			lost = true
		if lost:
			hunter.stop()
			if hunter == player:
				var refuge := prey.inside_settlement
				_set_status("%s got away%s" % [prey.party_name,
						" into %s" % GameData.get_settlement(refuge).name if refuge != "" else ""])
				_route.mesh = null
				_marker.visible = false
			else:
				_lord_timers[hunter] = 1.0
				if prey == player:
					_set_status("%s gave up the chase" % hunter.party_name)
			continue
		_chase_timers[hunter] = _chase_timers.get(hunter, 0.0) - delta
		if _chase_timers[hunter] <= 0.0:
			_chase_timers[hunter] = CHASE_REPATH
			if not hunter.travel_to(prey.map_position()):
				hunter.stop()
			else:
				hunter.chasing = prey


func _check_encounters() -> void:
	## Warbands at war that touch fight; lords at war with you who spot your
	## warband may come after it.
	for i in parties.size():
		var a := parties[i]
		if not a.can_fight():
			continue
		for j in range(i + 1, parties.size()):
			var b := parties[j]
			if not b.can_fight():
				continue
			var hostile := a.chasing == b or b.chasing == a or GameData.at_war(a.faction_id, b.faction_id)
			if hostile and Economy.warband_home and (a == player or b == player):
				hostile = false   # safe under your castle's walls
			if not hostile or a.map_position().distance_to(b.map_position()) > CONTACT:
				continue
			# Whoever was chasing attacks; otherwise the one on the move does.
			if b.chasing == a or (a.chasing != b and b.moving and not a.moving):
				_fight(b, a)
			else:
				_fight(a, b)
			return
	if player == null or not player.can_fight() or Economy.warband_home:
		return
	for lord in parties:
		if lord == player or lord.chasing != null or _lord_sieges.has(lord) or not lord.can_fight() \
				or not GameData.at_war(lord.faction_id, player.faction_id):
			continue
		_sized_up[lord] = _sized_up.get(lord, 0.0) - 0.2
		if _sized_up[lord] > 0.0 or lord.map_position().distance_to(player.map_position()) > SIGHT:
			continue
		_sized_up[lord] = 3.0
		var mine := Economy.get_castle(lord.home)
		var theirs := Economy.get_castle(player.home)
		if mine != null and theirs != null and Battle.odds(Economy.rules, mine.field, theirs.field) >= CHASE_ODDS:
			_start_chase(lord, player)
			if lord.chasing == player:
				_set_status("%s is coming after you!" % lord.party_name)


func _fight(attacker: Party, defender: Party) -> void:
	## Resolves a battle and tells everyone. The report holds the names,
	## factions and Battle.resolve() results of both sides ("a" attacked),
	## the place, the winner ("a" or "b") and which side you were on ("" if neither).
	var castle_a := Economy.get_castle(attacker.home)
	var castle_d := Economy.get_castle(defender.home)
	if castle_a == null or castle_d == null:
		return
	var result := Battle.resolve(castle_a, castle_d, hash(attacker.id + defender.id) + Time.get_ticks_msec())
	var truce := Time.get_ticks_msec() * 0.001 + TRUCE
	var lifted := ""
	for p in [attacker, defender]:
		if _lord_sieges.has(p) and _lord_sieges[p].until > 0.0:
			lifted = GameData.get_settlement(_lord_sieges[p].castle).name
		p.stop()
		p.truce_until = truce
		_lift_lord_siege(p)
	var loser := defender if result.winner == "a" else attacker
	var report := {
		"attacker": attacker.party_name, "defender": defender.party_name,
		"attacker_faction": attacker.faction_id, "defender_faction": defender.faction_id,
		"place": _nearest_settlement_name(defender.map_position()),
		"winner": result.winner, "a": result.a, "b": result.b, "loot": result.loot,
		"player": "a" if attacker == player else ("b" if defender == player else ""),
		"lifted": lifted,
	}
	for p in [attacker, defender]:
		if p != player:
			_lord_timers[p] = 0.5 if p != loser else 0.0
	if loser != player:
		_send_home(loser)
	if loser == player:
		_lift_siege()
	if report.player != "":
		_set_status(("Won the battle near %s" if loser != player else "Beaten near %s") % report.place)
		_route.mesh = null
		_marker.visible = false
	Economy.save_game()
	Economy.changed.emit()
	EventBus.battle_fought.emit(report)


func _send_home(lord: Party) -> void:
	## A beaten lord falls back to their castle to lick their wounds.
	var home := GameData.get_settlement(lord.home)
	if not home.is_empty() and lord.inside_settlement != lord.home:
		lord.travel_to(Vector2(home.position[0], home.position[1]), home.id)


func _rebuild_route() -> void:
	## Ribbon from the party along the rest of its path, hugging the ground.
	var pts := PackedVector2Array([player.map_position()])
	pts.append_array(player.path)
	if pts.size() < 2:
		_route.mesh = null
		return
	# Resample evenly so the ribbon follows the terrain between path points.
	var dense := PackedVector2Array([pts[0]])
	for k in range(1, pts.size()):
		var steps := maxi(1, int(pts[k].distance_to(pts[k - 1]) / ROUTE_STEP))
		for s in range(1, steps + 1):
			dense.append(pts[k - 1].lerp(pts[k], float(s) / steps))
	var width := 1.4 * player.display_scale()
	var lift := 0.5 + 0.15 * player.display_scale()
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
	var along := 0.0
	for k in dense.size():
		var q := dense[k]
		if k > 0:
			along += q.distance_to(dense[k - 1])
		var dir := (dense[mini(k + 1, dense.size() - 1)] - dense[maxi(k - 1, 0)]).normalized()
		var side := Vector2(-dir.y, dir.x) * width * 0.5
		for edge in [-1.0, 1.0]:
			var e: Vector2 = q + side * edge
			st.set_uv(Vector2(along, (edge + 1.0) * 0.5))
			st.add_vertex(Vector3(e.x, Party.ground_height(e.x, e.y) + lift, e.y))
	_route.mesh = st.commit()


func _settlement_at(p: Vector2) -> Dictionary:
	for s in GameData.settlements:
		var r: float = SettlementModels.RADIUS.get(s.type, 20.0)
		if p.distance_to(Vector2(s.position[0], s.position[1])) <= r:
			return s
	return {}


func _outside(settlement: Dictionary, facing := Vector2.INF) -> Vector2:
	## A passable spot just outside a settlement's walls, on the side towards
	## `facing` if given.
	var centre := Vector2(settlement.position[0], settlement.position[1])
	var r: float = SettlementModels.RADIUS.get(settlement.type, 20.0) + 14.0
	var start := PI * 0.5 if facing == Vector2.INF else (facing - centre).angle()
	for k in 16:
		var step := ceili(k * 0.5) * (1 if k % 2 == 1 else -1)   # 0, +1, -1, +2, -2 ...
		var p := centre + Vector2.from_angle(start + step * TAU / 16.0) * r
		if GameData.nav.is_passable(p.x, p.y):
			return p
	return centre


func _nearest_settlement_name(p: Vector2) -> String:
	var best := ""
	var best_d := INF
	for s in GameData.settlements:
		var d := p.distance_to(Vector2(s.position[0], s.position[1]))
		if d < best_d:
			best_d = d
			best = s.name
	return best


func _set_status(text: String) -> void:
	if text == _status:
		return
	_status = text
	EventBus.party_status_changed.emit(text)
