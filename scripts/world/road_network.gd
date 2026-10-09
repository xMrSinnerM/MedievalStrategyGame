class_name RoadNetwork
extends RefCounted
## Roads and settlement grounds rasterized into masks, built from
## data/roads.json and data/settlements.json at load time.
##
## road_image (1 map unit per pixel): alpha is how much packed dirt shows at a
##   spot (roads and settlement yards), painted by the terrain shader and used by
##   is_on_road() for movement. Colour is white on roads and black on yards, so
##   the parchment map can ink roads only.
## clearance_image (2 map units per pixel): where trees must not grow.

const MAIN_WIDTH := 5.0
const TRACK_WIDTH := 3.2
const TREE_GAP := 5.0          ## extra space kept free of trees beside a road
const YARD_SCALE := 0.85       ## dirt yard radius as a share of the settlement footprint
const CLEARANCE_SCALE := 2     ## clearance pixels are this many map units wide

var roads: Array = []
var road_image: Image
var clearance_image: Image
var world_size := 2048.0

var _brushes := {}


func build(road_list: Array, settlements: Array, size: float) -> void:
	roads = road_list
	world_size = size
	var n := int(world_size)
	road_image = Image.create(n, n, false, Image.FORMAT_RGBA8)
	road_image.fill(Color(1, 1, 1, 0))
	var m := n / CLEARANCE_SCALE
	clearance_image = Image.create(m, m, false, Image.FORMAT_RGBA8)
	clearance_image.fill(Color(1, 1, 1, 0))

	for s in settlements:
		var p := Vector2(s.position[0], s.position[1])
		var r: float = SettlementModels.RADIUS.get(s.type, 20.0)
		_stamp(road_image, p, r * YARD_SCALE, 0.75, 1.0, Color.BLACK)
		_stamp(clearance_image, p, r + 8.0, 1.0, float(CLEARANCE_SCALE))

	for road in roads:
		var width := MAIN_WIDTH if road.kind == "main" else TRACK_WIDTH
		var strength := 1.0 if road.kind == "main" else 0.8
		var pts: Array = road.points
		for k in pts.size() - 1:
			var a := Vector2(pts[k][0], pts[k][1])
			var b := Vector2(pts[k + 1][0], pts[k + 1][1])
			var steps := int(ceil(a.distance_to(b))) + 1
			for s in steps + 1:
				var p := a.lerp(b, float(s) / steps)
				_stamp(road_image, p, width * 0.5, strength, 1.0)
				if s % 2 == 0:
					_stamp(clearance_image, p, width * 0.5 + TREE_GAP, 1.0, float(CLEARANCE_SCALE))


func is_on_road(x: float, z: float) -> bool:
	## True on a road or inside a settlement's grounds.
	return road_amount(x, z) > 0.4


func road_amount(x: float, z: float) -> float:
	var i := int(x)
	var j := int(z)
	if i < 0 or j < 0 or i >= road_image.get_width() or j >= road_image.get_height():
		return 0.0
	return road_image.get_pixel(i, j).a


func is_cleared(x: float, z: float) -> bool:
	## True where trees should not grow (roads, settlements and their surroundings).
	var i := int(x / CLEARANCE_SCALE)
	var j := int(z / CLEARANCE_SCALE)
	if i < 0 or j < 0 or i >= clearance_image.get_width() or j >= clearance_image.get_height():
		return false
	return clearance_image.get_pixel(i, j).a > 0.3


func make_road_texture() -> ImageTexture:
	## Luminance: road (1) or yard (0); alpha: dirt amount.
	var mask: Image = road_image.duplicate()
	mask.convert(Image.FORMAT_LA8)
	mask.generate_mipmaps()
	return ImageTexture.create_from_image(mask)


func _stamp(img: Image, centre: Vector2, radius: float, strength: float, units_per_pixel: float, color := Color.WHITE) -> void:
	## Paints a soft disc by blending a cached brush image over the mask.
	var r_px := radius / units_per_pixel
	var brush := _brush(r_px, strength, color)
	var half := brush.get_width() / 2
	var dst := Vector2i(int(round(centre.x / units_per_pixel)) - half, int(round(centre.y / units_per_pixel)) - half)
	img.blend_rect(brush, Rect2i(Vector2i.ZERO, brush.get_size()), dst)


func _brush(r_px: float, strength: float, color: Color) -> Image:
	var key := Vector3i(int(round(r_px * 4.0)), int(round(strength * 100.0)), int(color.r * 255.0))
	if _brushes.has(key):
		return _brushes[key]
	var half := int(ceil(r_px)) + 1
	var size := half * 2 + 1
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in size:
		for x in size:
			var d := Vector2(x - half, y - half).length()
			# Solid core with a one-pixel soft edge.
			var a := clampf(r_px + 0.5 - d, 0.0, 1.0) * strength
			img.set_pixel(x, y, Color(color, a))
	_brushes[key] = img
	return img
