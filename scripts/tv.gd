extends Node2D
## The cabin TV picture (320x240), drawn like drawTV() in the web build:
## channel 0 football, 1 fishing show, 2 local news, static between channels, rainbow rings while tripping.

const W := 320.0
const H := 240.0
var t := 0.0
var channel := 0
var static_t := 0.0
var trip := 0.0
var dead := false
var cracks := []
var players := []
var font: Font
var font_serif: Font
var noise_tex: ImageTexture
var scan_tex: ImageTexture
var vig_tex: GradientTexture2D

func _ready() -> void:
	var r := RandomNumberGenerator.new(); r.seed = 3
	for i in 14: players.append({x = r.randf() * 320, y = 60 + r.randf() * 120, s = r.randf() * 6, t = i < 7})
	font = SystemFont.new(); font.font_names = ["Arial", "Liberation Sans", "DejaVu Sans"]; font.font_weight = 700
	font_serif = SystemFont.new(); font_serif.font_names = ["Georgia", "Liberation Serif", "DejaVu Serif"]; font_serif.font_weight = 700
	var img := Image.create(160, 120, false, Image.FORMAT_L8)
	noise_tex = ImageTexture.create_from_image(img)
	var sl := Image.create(1, 3, false, Image.FORMAT_RGBA8)
	sl.set_pixel(0, 0, Color(0, 0, 0, 0.2)); sl.set_pixel(0, 1, Color(0, 0, 0, 0)); sl.set_pixel(0, 2, Color(0, 0, 0, 0))
	scan_tex = ImageTexture.create_from_image(sl)
	vig_tex = GradientTexture2D.new(); vig_tex.fill = GradientTexture2D.FILL_RADIAL
	vig_tex.fill_from = Vector2(0.5, 0.5); vig_tex.fill_to = Vector2(1.05, 0.5)
	var g := Gradient.new(); g.set_color(0, Color(0, 0, 0, 0)); g.set_color(1, Color(0, 0, 0, 0.6)); g.add_point(0.4, Color(0, 0, 0, 0))
	vig_tex.gradient = g; vig_tex.width = 128; vig_tex.height = 128

func refresh(time: float, ch: int, st: float, tr: float, is_dead: bool) -> void:
	t = time; channel = ch; static_t = st; trip = tr; dead = is_dead
	queue_redraw()

func _text(f: Font, pos: Vector2, s: String, size: int, col: Color) -> void:
	draw_string(f, pos, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, col)

func _draw() -> void:
	if dead:
		draw_rect(Rect2(0, 0, W, H), Color(0.02, 0.02, 0.02))
		if cracks.is_empty():
			var c := Vector2(W * 0.45, H * 0.45)
			for i in 14:
				var a := i / 14.0 * TAU + randf() * 0.3; var p := c; var line := PackedVector2Array([p])
				for j in 5: p += Vector2(cos(a + (randf() - 0.5) * 0.6), sin(a + (randf() - 0.5) * 0.6)) * 30; line.append(p)
				cracks.append(line)
		for l in cracks: draw_polyline(l, Color(220 / 255.0, 230 / 255.0, 1, 0.75), 1.5)
		for r in range(12, 80, 22): draw_arc(Vector2(W * 0.45, H * 0.45), r, 0, TAU, 40, Color(220 / 255.0, 230 / 255.0, 1, 0.75), 1.5)
		draw_circle(Vector2(W * 0.45, H * 0.45), 10, Color.BLACK)
		return
	cracks.clear()
	if trip > 0.25:
		for i in range(24, 0, -1):
			var c := Color.from_hsv(fmod(i * 28 + t * 220, 360.0) / 360.0, 1, 1)
			draw_circle(Vector2(W / 2 + sin(t * 1.3) * 30, H / 2 + cos(t) * 20), i * 9 + fmod(t * 40, 9.0), c)
		_scan(); return
	if static_t > 0:
		var img := Image.create(160, 120, false, Image.FORMAT_L8)
		var data := PackedByteArray(); data.resize(160 * 120)
		for i in data.size(): data[i] = randi() % 256
		img.set_data(160, 120, false, Image.FORMAT_L8, data)
		noise_tex.update(img)
		draw_texture_rect(noise_tex, Rect2(0, 0, W, H), false)
	elif channel == 0:
		draw_rect(Rect2(0, 0, W, H), Color("#2e7d34"))
		var x := -fmod(t * 18, 64.0)
		while x < W: draw_rect(Rect2(x, 0, 32, H), Color("#348a3a")); x += 64
		x = -fmod(t * 18, 32.0)
		while x < W: draw_line(Vector2(x, 30), Vector2(x, 200), Color(1, 1, 1, 0.75), 2); x += 32
		for p in players:
			var px := fmod(p.x + sin(t * 1.3 + p.s) * 30 - t * 18, W)
			if px < 0: px += W
			draw_circle(Vector2(px, p.y + cos(t * 1.7 + p.s) * 12), 5, Color("#c8352a") if p.t else Color("#f1f1f1"))
		_ellipse(Vector2(160 + sin(t * 0.9) * 70, 120 + sin(t * 2.1) * 30), 5, 3, Color("#8a4a1e"))
		draw_rect(Rect2(10, H - 38, W - 20, 28), Color(10 / 255.0, 14 / 255.0, 30 / 255.0, 0.9))
		_text(font, Vector2(20, H - 19), "HOME 17   AWAY 13", 15, Color.WHITE)
		_text(font, Vector2(W - 100, H - 19), "3RD  4:12", 15, Color("#f4c430"))
	elif channel == 1:
		for y in int(H):
			var k := y / H
			var c := Color("#9cc6e8").lerp(Color("#d9e6ee"), k / 0.45) if k < 0.45 else (Color("#2f5f73").lerp(Color("#1c3c4a"), (k - 0.46) / 0.54) if k > 0.46 else Color("#d9e6ee"))
			draw_line(Vector2(0, y), Vector2(W, y), c, 1)
		var hill := PackedVector2Array([Vector2(0, 110)])
		for x in range(0, int(W) + 1, 20): hill.append(Vector2(x, 96 + sin(x * 0.05) * 8))
		hill.append(Vector2(W, 110))
		draw_colored_polygon(hill, Color("#2a4a2a"))
		for i in 6:
			draw_line(Vector2(0, 130 + i * 18 + sin(t + i) * 3), Vector2(W, 130 + i * 18 + cos(t + i) * 3), Color(1, 1, 1, 0.3), 1)
		var by := 150 + sin(t * 3) * 4
		var pts := PackedVector2Array()
		for i in 21:
			var u := i / 20.0
			pts.append(Vector2(40, 20) * (1 - u) * (1 - u) + Vector2(160, 60) * 2 * u * (1 - u) + Vector2(200, by) * u * u)
		draw_polyline(pts, Color("#dddddd"), 1)
		draw_arc(Vector2(200, by), 3, PI, TAU, 8, Color("#ee3333"), 6)
		draw_arc(Vector2(200, by), 3, 0, PI, 8, Color.WHITE, 6)
		draw_rect(Rect2(0, H - 34, W, 34), Color(0, 0, 0, 0.6))
		_text(font_serif, Vector2(12, H - 12), "BASS COUNTRY", 16, Color("#f4e8d4"))
	else:
		draw_rect(Rect2(0, 0, W, H), Color("#16306b"))
		for i in 8: draw_rect(Rect2(i * 44, 0, 22, 150), Color("#0d1f4a"))
		draw_circle(Vector2(160, 110), 30, Color("#2a2a2a")); draw_rect(Rect2(118, 138, 84, 70), Color("#2a2a2a"))
		draw_circle(Vector2(160, 104), 22, Color("#d7a07f"))
		draw_rect(Rect2(40, 170, 240, 40), Color("#5a3a2a"))
		draw_rect(Rect2(0, H - 40, W, 16), Color("#cc2222"))
		_text(font, Vector2(8, H - 28), "LOCAL NEWS", 12, Color.WHITE)
		draw_rect(Rect2(0, H - 24, W, 24), Color("#111111"))
		var msg := "SNOW TONIGHT IN THE HIGH COUNTRY  •  ROADS ICY AFTER MIDNIGHT  •  BAIT SHOP OPEN AT 6  •  "
		var mw := font.get_string_size(msg, HORIZONTAL_ALIGNMENT_LEFT, -1, 13).x
		var f2 := SystemFont.new(); f2.font_names = font.font_names
		_text(f2, Vector2(-fmod(t * 50, mw), H - 8), msg + msg, 13, Color("#ffd34a"))
	_scan()
	draw_texture_rect(vig_tex, Rect2(-W * 0.1, -H * 0.25, W * 1.2, H * 1.5), false)

func _scan() -> void:
	draw_texture_rect(scan_tex, Rect2(0, 0, W, H), true)

func _ellipse(c: Vector2, rx: float, ry: float, col: Color) -> void:
	var pts := PackedVector2Array()
	for i in 16: pts.append(c + Vector2(cos(i * TAU / 16) * rx, sin(i * TAU / 16) * ry))
	draw_colored_polygon(pts, col)
