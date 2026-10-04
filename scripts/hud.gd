extends CanvasLayer
## In-game HUD, styled like the web build: title + beer cans (top left), cash, clock and
## status pills (top right), John's subtitle line and the interaction prompt (bottom).

const INK := Color("#f4e8d4")
const MUTED := Color("#bba78c")
const EMBER := Color("#ff8a3d")
const EMBER_DEEP := Color("#c4521c")
const PANEL := Color(22 / 255.0, 15 / 255.0, 11 / 255.0, 0.84)
const LINE := Color(244 / 255.0, 232 / 255.0, 212 / 255.0, 0.16)

var f_display: Font = preload("res://assets/fx/AlfaSlabOne-Regular.ttf")
var f_body: FontVariation
var f_body_bold: FontVariation
var f_body_italic: FontVariation

var root: Control
var right: VBoxContainer
var cans: HBoxContainer
var cash_lbl: Label
var cash_fx: Label
var clock_lbl: Label
var ampm_lbl: Label
var pills := {}
var sub: RichTextLabel
var sub_t := 0.0
var ammo_box: PanelContainer
var ammo_n: Label
var xhair: Panel
var hitmark: Control
var prompt_box: PanelContainer
var prompt_key: PanelContainer
var prompt_lbl: Label
var prompt_u: HBoxContainer

func _ready() -> void:
	layer = 5
	var archivo: FontFile = load("res://assets/fx/Archivo.ttf")
	f_body = FontVariation.new(); f_body.base_font = archivo; f_body.variation_opentype = {"wght": 600}
	f_body_bold = FontVariation.new(); f_body_bold.base_font = archivo; f_body_bold.variation_opentype = {"wght": 800}
	f_body_italic = FontVariation.new(); f_body_italic.base_font = archivo; f_body_italic.variation_opentype = {"wght": 500}
	f_body_italic.variation_transform = Transform2D(Vector2(1, 0), Vector2(-0.2, 1), Vector2.ZERO)
	root = Control.new(); root.set_anchors_preset(Control.PRESET_FULL_RECT); root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_build_top()
	_build_bottom()
	set_cans(0); set_cash(500.0); set_clock(23 * 60 + 12)

static func sb(bg: Color, radius: int, border := Color(0, 0, 0, 0), bw := 0, pad := Vector4(10, 4, 10, 4)) -> StyleBoxFlat:
	var s := StyleBoxFlat.new(); s.bg_color = bg; s.set_corner_radius_all(radius)
	if bw > 0: s.border_color = border; s.set_border_width_all(bw)
	s.content_margin_left = pad.x; s.content_margin_top = pad.y; s.content_margin_right = pad.z; s.content_margin_bottom = pad.w
	return s

func _label(text: String, font: Font, size: int, col: Color, shadow := Color(0, 0, 0, 0.6), sh_off := Vector2(0, 2)) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_override("font", font); l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", shadow); l.add_theme_constant_override("shadow_offset_x", int(sh_off.x)); l.add_theme_constant_override("shadow_offset_y", int(sh_off.y))
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l

func _build_top() -> void:
	var left := VBoxContainer.new(); left.position = Vector2(20, 16); left.add_theme_constant_override("separation", 8)
	root.add_child(left)
	left.add_child(_label("John's Beer Run", f_display, 22, INK))
	cans = HBoxContainer.new(); cans.add_theme_constant_override("separation", 6); left.add_child(cans)
	for i in 5:
		var c := Panel.new(); c.custom_minimum_size = Vector2(13, 24); cans.add_child(c)

	right = VBoxContainer.new(); right.alignment = BoxContainer.ALIGNMENT_BEGIN
	right.add_theme_constant_override("separation", 8)
	root.add_child(right)
	# wallet
	var wallet := PanelContainer.new(); wallet.add_theme_stylebox_override("panel", sb(Color(10 / 255.0, 8 / 255.0, 6 / 255.0, 0.55), 10, Color(159 / 255.0, 226 / 255.0, 138 / 255.0, 0.25), 1))
	wallet.size_flags_horizontal = Control.SIZE_SHRINK_END
	var wr := HBoxContainer.new(); wr.add_theme_constant_override("separation", 6); wallet.add_child(wr)
	var cl := _label("CASH", f_body_bold, 11, MUTED, Color(0, 0, 0, 0)); cl.size_flags_vertical = Control.SIZE_SHRINK_CENTER; wr.add_child(cl)
	cash_lbl = _label("$500.00", f_display, 24, Color("#9fe28a"), Color(120 / 255.0, 220 / 255.0, 100 / 255.0, 0.35), Vector2.ZERO)
	wr.add_child(cash_lbl)
	right.add_child(wallet)
	cash_fx = _label("", f_display, 15, Color("#9fe28a")); cash_fx.modulate.a = 0; cash_fx.size_flags_horizontal = Control.SIZE_SHRINK_END
	# clock
	var clock := PanelContainer.new(); clock.add_theme_stylebox_override("panel", sb(Color(0, 0, 0, 0.45), 6, LINE, 1, Vector4(12, 4, 12, 4)))
	clock.size_flags_horizontal = Control.SIZE_SHRINK_END
	var crow := HBoxContainer.new(); crow.add_theme_constant_override("separation", 6); clock.add_child(crow)
	clock_lbl = _label("11:12", f_display, 30, Color("#ff6a4d"), Color(1, 80 / 255.0, 50 / 255.0, 0.55), Vector2.ZERO); crow.add_child(clock_lbl)
	ampm_lbl = _label("PM", f_body_bold, 12, Color("#ff6a4d"), Color(0, 0, 0, 0)); ampm_lbl.size_flags_vertical = Control.SIZE_SHRINK_END; crow.add_child(ampm_lbl)
	right.add_child(clock)
	right.add_child(cash_fx)
	# status pills
	pills.boost = _pill(right, "WIRED", Color("#e8f3ff"), Color("#0d1a2a"))
	pills.trip = _pill(right, "TRIPPING", Color("#ff9ad8"), Color("#120a1e"))
	ammo_box = PanelContainer.new(); ammo_box.add_theme_stylebox_override("panel", sb(Color(0, 0, 0, 0.6), 999, LINE, 1, Vector4(11, 5, 11, 5)))
	ammo_box.size_flags_horizontal = Control.SIZE_SHRINK_END; ammo_box.visible = false
	var ar := HBoxContainer.new(); ar.add_theme_constant_override("separation", 6); ammo_box.add_child(ar)
	ar.add_child(_label("GLOCK 19", f_body_bold, 12, INK, Color(0, 0, 0, 0)))
	ammo_n = _label("15", f_body_bold, 14, Color("#ffd36b"), Color(0, 0, 0, 0)); ar.add_child(ammo_n)
	right.add_child(ammo_box)
	# crosshair + hit marker
	xhair = Panel.new(); var xs := StyleBoxFlat.new(); xs.bg_color = Color(0, 0, 0, 0); xs.set_corner_radius_all(13); xs.set_border_width_all(2)
	xs.border_color = Color(1, 1, 1, 0.85); xs.shadow_color = Color(0, 0, 0, 0.5); xs.shadow_size = 1
	xhair.add_theme_stylebox_override("panel", xs); xhair.size = Vector2(26, 26); xhair.visible = false; xhair.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var dot := Panel.new(); var ds := StyleBoxFlat.new(); ds.bg_color = Color.WHITE; ds.set_corner_radius_all(2); dot.add_theme_stylebox_override("panel", ds)
	dot.size = Vector2(4, 4); dot.position = Vector2(11, 11); xhair.add_child(dot)
	root.add_child(xhair)
	hitmark = Control.new(); hitmark.size = Vector2(18, 18); hitmark.visible = false; hitmark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for a in [45, -45]:
		var bar := ColorRect.new(); bar.color = Color.WHITE; bar.size = Vector2(22, 2); bar.position = Vector2(-2, 8); bar.pivot_offset = Vector2(11, 1); bar.rotation_degrees = a
		hitmark.add_child(bar)
	root.add_child(hitmark)

func _pill(parent: Control, title: String, bg: Color, fg: Color) -> Dictionary:
	var p := PanelContainer.new(); p.add_theme_stylebox_override("panel", sb(bg, 999, Color(0, 0, 0, 0), 0, Vector4(11, 5, 11, 5)))
	p.size_flags_horizontal = Control.SIZE_SHRINK_END; p.visible = false
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 5); p.add_child(row)
	row.add_child(_label(title, f_body_bold, 12, fg, Color(0, 0, 0, 0)))
	var n := _label("0", f_body_bold, 14, fg, Color(0, 0, 0, 0)); row.add_child(n)
	row.add_child(_label("s", f_body_bold, 12, fg, Color(0, 0, 0, 0)))
	parent.add_child(p)
	return {box = p, n = n}

func _build_bottom() -> void:
	sub = RichTextLabel.new(); sub.bbcode_enabled = true; sub.fit_content = true; sub.scroll_active = false
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub.custom_minimum_size = Vector2(560, 0); sub.size = Vector2(560, 60)
	sub.add_theme_font_override("normal_font", f_body_italic); sub.add_theme_font_override("bold_font", f_body_bold)
	sub.add_theme_font_size_override("normal_font_size", 19); sub.add_theme_font_size_override("bold_font_size", 14)
	sub.add_theme_color_override("default_color", INK)
	sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9)); sub.add_theme_constant_override("shadow_offset_y", 2); sub.add_theme_constant_override("shadow_outline_size", 6)
	sub.mouse_filter = Control.MOUSE_FILTER_IGNORE; sub.modulate.a = 0
	root.add_child(sub)

	prompt_box = PanelContainer.new(); prompt_box.add_theme_stylebox_override("panel", sb(PANEL, 999, LINE, 1, Vector4(10, 9, 16, 9)))
	prompt_box.visible = false
	var row := HBoxContainer.new(); row.add_theme_constant_override("separation", 10); prompt_box.add_child(row)
	prompt_key = _kbd("E"); row.add_child(prompt_key)
	prompt_lbl = _label("", f_body, 15, INK, Color(0, 0, 0, 0)); row.add_child(prompt_lbl)
	prompt_u = HBoxContainer.new(); prompt_u.add_theme_constant_override("separation", 8)
	var sep := VSeparator.new(); prompt_u.add_child(sep)
	prompt_u.add_child(_kbd("U")); prompt_u.add_child(_label("Peek", f_body, 15, INK, Color(0, 0, 0, 0)))
	prompt_u.visible = false; row.add_child(prompt_u)
	root.add_child(prompt_box)

func _kbd(k: String) -> PanelContainer:
	var p := PanelContainer.new()
	var s := sb(INK, 6, Color(0, 0, 0, 0), 0, Vector4(6, 1, 6, 1)); s.shadow_color = Color("#8a7a63"); s.shadow_offset = Vector2(0, 3); s.shadow_size = 0
	s.border_width_bottom = 3; s.border_color = Color("#8a7a63")
	p.add_theme_stylebox_override("panel", s); p.custom_minimum_size = Vector2(26, 26)
	var l := _label(k, f_body_bold, 13, Color("#1b120c"), Color(0, 0, 0, 0)); l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	p.add_child(l)
	return p

# ---------------------------------------------------------------- API
func set_cans(n: int) -> void:
	for i in cans.get_child_count():
		var full := i < n
		var s := StyleBoxFlat.new(); s.set_corner_radius_all(3); s.set_border_width_all(2)
		if full:
			s.bg_color = EMBER; s.border_color = INK
		else:
			s.bg_color = Color(0, 0, 0, 0.3); s.border_color = Color(INK, 0.35)
		(cans.get_child(i) as Panel).add_theme_stylebox_override("panel", s)

func set_cash(v: float) -> void:
	cash_lbl.text = "$" + _money(v)

func cash_delta(d: float) -> void:
	cash_fx.text = ("+" if d > 0 else "−") + "$" + _money(abs(d))
	cash_fx.add_theme_color_override("font_color", Color("#9fe28a") if d > 0 else Color("#ff7a6b"))
	var tw := create_tween(); cash_fx.modulate.a = 1.0
	tw.tween_property(cash_fx, "modulate:a", 0.0, 1.6).set_ease(Tween.EASE_IN)

static func _money(v: float) -> String:
	var whole := int(floor(v)); var cents := int(round((v - whole) * 100))
	var s := str(whole); var out := ""
	while s.length() > 3: out = "," + s.substr(s.length() - 3) + out; s = s.substr(0, s.length() - 3)
	return s + out + ".%02d" % cents

func set_clock(minutes: int) -> void:
	var h24 := (minutes / 60) % 24; var m := minutes % 60
	var h := ((h24 + 11) % 12) + 1
	clock_lbl.text = "%d:%02d" % [h, m]; ampm_lbl.text = "PM" if h24 >= 12 else "AM"

func set_pill(name: String, seconds: float) -> void:
	var p: Dictionary = pills[name]
	p.box.visible = seconds > 0
	if seconds > 0: p.n.text = str(int(ceil(seconds)))

func say(who: String, text: String, secs := 3.2) -> void:
	sub.text = "[center][b][color=#ff8a3d]%s[/color][/b]  %s[/center]" % [who.to_upper(), text]
	sub_t = secs
	sub.modulate.a = 1.0

func prompt(text: String, key := true, peek := false) -> void:
	if text == "":
		prompt_box.visible = false; return
	prompt_box.visible = true
	prompt_key.visible = key
	prompt_lbl.text = text
	prompt_lbl.add_theme_color_override("font_color", INK if key else MUTED)
	prompt_u.visible = peek
	prompt_box.reset_size()

func _process(dt: float) -> void:
	var vs := root.size
	right.reset_size(); right.position = Vector2(vs.x - 20 - right.size.x, 16)
	prompt_box.position = Vector2((vs.x - prompt_box.size.x) / 2, vs.y - 44 - prompt_box.size.y)
	sub.position = Vector2((vs.x - sub.size.x) / 2, vs.y - 104 - sub.size.y)
	xhair.position = vs / 2 - xhair.size / 2; hitmark.position = vs / 2 - hitmark.size / 2
	if sub_t > 0:
		sub_t -= dt
	else:
		sub.modulate.a = move_toward(sub.modulate.a, 0.0, dt / 0.4)
	# trip pill: cycle the rainbow
	var tp: PanelContainer = pills.trip.box
	if tp.visible:
		var s: StyleBoxFlat = tp.get_theme_stylebox("panel")
		s.bg_color = Color.from_hsv(fmod(Time.get_ticks_msec() / 2000.0, 1.0), 0.55, 1.0)

func set_ammo(visible_: bool, text: String) -> void:
	ammo_box.visible = visible_; ammo_n.text = text

func set_aim(xh: bool, hit: bool) -> void:
	xhair.visible = xh; hitmark.visible = hit
