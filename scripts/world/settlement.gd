class_name Settlement
extends Node3D
## One town, castle or village on the campaign map: its placeholder model on a
## small earth plinth, the owner's banner and a name label.

## Label font size per type; labels keep this size on screen at any zoom.
const LABEL_SIZE := {"town": 44, "castle": 38, "village": 34}
## Labels hide above this camera zoom (0 closest, 1 furthest).
const LABEL_MAX_ZOOM := {"town": 1.01, "castle": 0.95, "village": 0.8}
## Banner pole foot (model space) and pole height per type.
const BANNER_SPOT := {
	"town": [Vector3(0, 22.0, -4.0), 10.0],
	"castle": [Vector3(-2.0, 20.0, -2.0), 8.0],
	"village": [Vector3(3.0, 0.0, 3.0), 9.0],
}

var id := ""
var settlement_name := ""
var type := "village"
var faction_id := ""

var _label: Label3D


func setup(data: Dictionary) -> void:
	var terrain: TerrainData = GameData.terrain
	var faction := GameData.get_faction(data.faction)
	id = data.id
	settlement_name = data.name
	type = data.type
	faction_id = data.faction
	name = id

	var x: float = data.position[0]
	var z: float = data.position[1]
	var radius: float = SettlementModels.RADIUS[type]
	# Sit on the average ground height; the plinth covers ground that falls away.
	var centre_h := terrain.get_height(x, z)
	var total := centre_h
	var lowest := centre_h
	for k in 12:
		var off := Vector2.from_angle(k * TAU / 12.0)
		total += terrain.get_height(x + off.x * radius * 0.6, z + off.y * radius * 0.6)
		lowest = minf(lowest, terrain.get_height(x + off.x * radius, z + off.y * radius))
	var base := total / 13.0
	position = Vector3(x, base, z)
	rotation.y = deg_to_rad(float(data.get("rotation_deg", 0.0)))

	var style: Dictionary = faction.get("style", {})
	var model := MeshInstance3D.new()
	model.name = "Model"
	model.mesh = SettlementModels.build(type, style, hash(id))
	add_child(model)

	var plinth := MeshInstance3D.new()
	plinth.name = "Foundation"
	plinth.mesh = SettlementModels.foundation(type, base - lowest + 2.0)
	plinth.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plinth)

	if not faction.is_empty():
		var spot: Array = BANNER_SPOT[type]
		var banner := Banners.make(faction, spot[1], spot[1] * 0.55)
		banner.position = spot[0]
		add_child(banner)

	_label = Label3D.new()
	_label.name = "Label"
	_label.text = settlement_name
	_label.font_size = LABEL_SIZE[type]
	_label.outline_size = 10
	_label.modulate = Color(1.0, 0.84, 0.4) if data.get("player", false) else Color(1.0, 0.96, 0.86)
	_label.outline_modulate = Color(0.16, 0.11, 0.07, 0.9)
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.fixed_size = true
	_label.pixel_size = 0.0005
	_label.no_depth_test = true
	_label.render_priority = 12
	_label.outline_render_priority = 11
	_label.shaded = false
	_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_label.position = Vector3(0, SettlementModels.TOP[type] + 6.0, 0)
	add_child(_label)


func set_zoom(zoom_t: float) -> void:
	_label.visible = zoom_t <= LABEL_MAX_ZOOM[type]
