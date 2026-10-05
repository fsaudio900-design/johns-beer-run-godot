extends Control
## Round minimap, bottom left (v2.20). It turns with the camera, so "up" is where John is looking.
##
## The map image (assets/ui/minimap.png) is a top-down render of the town styled by
## tools/make_minimap.py: it covers x -155..50 m and z -62..12 m at 8 px per metre, north up.
## On top: John's arrow in the middle, Ben's mission marker (fades out as John gets close, like
## the hologram at Ben's door) and symbols for the bar and the Fuel Stop. Markers out of range
## stick to the rim so you can always see which way they are.

const MAP_X0 := -155.0
const MAP_Z0 := -62.0
const PX_PER_M := 8.0
const R := 98.0                 # radius on screen
const RANGE := 42.0             # metres from John to the rim
const BAR_DOOR := Vector2(-75.8, -33.4)
const FUEL_DOOR := Vector2(-52.0, -42.6)

var g: Node
var tex: Texture2D = preload("res://assets/ui/minimap.png")
var i_mission: Texture2D = preload("res://assets/ui/map_mission.png")
var i_bar: Texture2D = preload("res://assets/ui/map_bar.png")
var i_fuel: Texture2D = preload("res://assets/ui/map_fuel.png")
var i_player: Texture2D = preload("res://assets/ui/map_player.png")
var mask: Control
var layer: Control
var over: Control
var phi := 0.0                  # screen rotation (map turns with the camera)

func setup(game: Node) -> void:
	g = game
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sz := R * 2 + 12
	anchor_left = 0.0; anchor_right = 0.0; anchor_top = 1.0; anchor_bottom = 1.0
	offset_left = 20; offset_right = 20 + sz; offset_top = -20 - sz; offset_bottom = -20
	# circle mask: the map layer is clipped to what the mask draws
	mask = Control.new(); mask.clip_children = CanvasItem.CLIP_CHILDREN_ONLY; mask.size = size
	mask.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(mask)
	mask.draw.connect(func(): mask.draw_circle(size / 2, R, Color.WHITE))
	layer = Control.new(); layer.size = size; layer.mouse_filter = Control.MOUSE_FILTER_IGNORE; mask.add_child(layer)
	layer.draw.connect(_draw_map)
	over = Control.new(); over.size = size; over.mouse_filter = Control.MOUSE_FILTER_IGNORE; add_child(over)
	over.draw.connect(_draw_over)

func _process(_dt: float) -> void:
	if g == null or g.john == null: return
	visible = g.loaded and g.state != "title" and g.state != "end" and not g.peeping
	if not visible: return
	var f: Vector3 = -g.cam.global_transform.basis.z
	phi = -PI / 2 - atan2(f.z, f.x)
	layer.queue_redraw(); over.queue_redraw()

func _john() -> Vector2: return Vector2(g.john.global_position.x, g.john.global_position.z)

## world (x, z) -> minimap screen position (unclamped)
func _to_screen(w: Vector2) -> Vector2:
	var rel := (w - _john()) * (R / RANGE)
	return size / 2 + rel.rotated(phi)

func _draw_map() -> void:
	var c := size / 2
	layer.draw_circle(c, R, Color(0.06, 0.08, 0.08))
	var k := (R / RANGE) / PX_PER_M                  # texture pixels -> screen pixels
	var j := _john()
	var origin := Vector2((MAP_X0 - j.x) * PX_PER_M, (MAP_Z0 - j.y) * PX_PER_M) * k
	layer.draw_set_transform(c, phi, Vector2.ONE)
	layer.draw_texture_rect(tex, Rect2(origin, tex.get_size() * k), false)
	layer.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

func _marker(icon: Texture2D, w: Vector2, s: float, alpha := 1.0) -> void:
	if alpha <= 0.01: return
	var c := size / 2
	var p := _to_screen(w)
	var d := p - c
	if d.length() > R - s * 0.55: p = c + d.normalized() * (R - s * 0.55)    # stick to the rim
	over.draw_texture_rect(icon, Rect2(p - Vector2(s, s) / 2, Vector2(s, s)), false, Color(1, 1, 1, alpha))

func _draw_over() -> void:
	var c := size / 2
	# rim
	over.draw_arc(c, R + 1, 0, TAU, 64, Color(0.08, 0.06, 0.05, 0.9), 6.0, true)
	over.draw_arc(c, R + 3.5, 0, TAU, 64, Color(1.0, 0.54, 0.24, 0.85), 2.0, true)
	# north tick
	var n := c + Vector2(0, -(R - 9)).rotated(phi)
	over.draw_string(get_theme_default_font(), n - Vector2(5, -5), "N", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 0.9, 0.75, 0.9))
	_marker(i_fuel, FUEL_DOOR, 26.0)
	_marker(i_bar, BAR_DOOR, 26.0)
	var ben: Node = g.ben_mod
	if ben and ben.marker_on():
		var dist: float = _john().distance_to(ben.marker_pos2())
		var pulse := 1.0 + 0.12 * sin(Time.get_ticks_msec() * 0.006)
		_marker(i_mission, ben.marker_pos2(), 28.0 * pulse, ben.marker_fade(dist))
	# John
	var fwd := Vector2(sin(g.john.facing), cos(g.john.facing)).rotated(phi)
	over.draw_set_transform(c, atan2(fwd.x, -fwd.y), Vector2.ONE)
	over.draw_texture_rect(i_player, Rect2(Vector2(-11, -11), Vector2(22, 22)), false)
	over.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
