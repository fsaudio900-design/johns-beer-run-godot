extends CanvasLayer
## Title screen (logo, Start the Night / How to Play / Credits), info panels and the
## "John's out cold" end card. Ported from the web build's #menu.

signal start_pressed
signal again_pressed
signal menu_pressed
signal retry_pressed
signal pause_action(act: String)

const VERSION := "v2.15"
const INK := Color("#f4e8d4")
const MUTED := Color("#bba78c")
const EMBER := Color("#ff8a3d")
const EMBER_DEEP := Color("#c4521c")
const LINE := Color(244 / 255.0, 232 / 255.0, 212 / 255.0, 0.16)

var f_display: Font = preload("res://assets/fx/AlfaSlabOne-Regular.ttf")
var f_sign: Font = preload("res://assets/fx/Rye-Regular.ttf")
var f_body: FontVariation
var f_bold: FontVariation

var title_root: Control
var nav: VBoxContainer
var buttons: Array[Button] = []
var sel := 0
var panels := {}
var panel_open := ""
var card_root: Control
var card_stats: HBoxContainer
var start_btn: Button
var start_sub: Label
var logo_run: Label
var t := 0.0

func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	var archivo: FontFile = load("res://assets/fx/Archivo.ttf")
	f_body = FontVariation.new(); f_body.base_font = archivo; f_body.variation_opentype = {"wght": 400}
	f_bold = FontVariation.new(); f_bold.base_font = archivo; f_bold.variation_opentype = {"wght": 800}
	_build_title()
	_build_card()
	_build_failed()
	_build_pause()
	show_title()

func _l(text: String, font: Font, size: int, col: Color) -> Label:
	var l := Label.new(); l.text = text
	l.add_theme_font_override("font", font); l.add_theme_font_size_override("font_size", size); l.add_theme_color_override("font_color", col)
	return l

func _shadowed(l: Label, col: Color, off: int) -> Label:
	l.add_theme_color_override("font_shadow_color", col); l.add_theme_constant_override("shadow_offset_y", off); l.add_theme_constant_override("shadow_offset_x", 0)
	return l

func _build_title() -> void:
	title_root = Control.new(); title_root.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(title_root)
	# left-to-right darkening like the web title screen
	var grad := TextureRect.new(); grad.set_anchors_preset(Control.PRESET_FULL_RECT); grad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gt := GradientTexture2D.new(); var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.36, 0.7, 1.0])
	g.colors = PackedColorArray([Color(9 / 255.0, 6 / 255.0, 5 / 255.0, 0.94), Color(9 / 255.0, 6 / 255.0, 5 / 255.0, 0.78), Color(9 / 255.0, 6 / 255.0, 5 / 255.0, 0.15), Color(9 / 255.0, 6 / 255.0, 5 / 255.0, 0.35)])
	gt.gradient = g; gt.width = 256; gt.height = 4; grad.texture = gt; grad.stretch_mode = TextureRect.STRETCH_SCALE
	title_root.add_child(grad)

	var cols := HBoxContainer.new(); cols.set_anchors_preset(Control.PRESET_FULL_RECT)
	cols.add_theme_constant_override("separation", 72)
	var margin := MarginContainer.new(); margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right"]: margin.add_theme_constant_override("margin_" + side, 96)
	margin.add_theme_constant_override("margin_top", 40); margin.add_theme_constant_override("margin_bottom", 72)
	title_root.add_child(margin); margin.add_child(cols)
	var col := VBoxContainer.new(); col.alignment = BoxContainer.ALIGNMENT_CENTER; col.custom_minimum_size = Vector2(520, 0)
	col.add_theme_constant_override("separation", 4)
	cols.add_child(col)
	var pres := HBoxContainer.new(); pres.add_theme_constant_override("separation", 10)
	var bar := ColorRect.new(); bar.color = EMBER; bar.custom_minimum_size = Vector2(28, 2); bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	pres.add_child(bar); pres.add_child(_l("C E S S N A   P R E S E N T S", f_bold, 12, MUTED)); col.add_child(pres)
	col.add_child(_shadowed(_l("John's", f_sign, 92, INK), Color("#2a1408"), 3))
	logo_run = _shadowed(_l("Beer Run", f_display, 84, EMBER), EMBER_DEEP, 4); col.add_child(logo_run)
	var stripe := HBoxContainer.new(); stripe.add_theme_constant_override("separation", 0); stripe.custom_minimum_size = Vector2(340, 8)
	stripe.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	for c in [EMBER, INK, EMBER_DEEP]:
		var r := ColorRect.new(); r.color = c; r.custom_minimum_size = Vector2(113, 8); stripe.add_child(r)
	col.add_child(_spacer(14)); col.add_child(stripe)
	var tag := _l("A log cabin. A recliner. A fridge full of cold ones. Get John through five beers before he passes out in front of the game.", f_body, 17, MUTED)
	tag.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; tag.custom_minimum_size = Vector2(440, 0)
	col.add_child(_spacer(14)); col.add_child(tag); col.add_child(_spacer(36))
	nav = VBoxContainer.new(); nav.add_theme_constant_override("separation", 4); col.add_child(nav)
	start_btn = _nav_button("Start the Night", "start")
	start_sub = _l("Loading John…", f_bold, 12, MUTED); start_sub.visible = false
	_nav_button("How to Play", "howto")
	_nav_button("Credits", "credits")
	col.add_child(_spacer(24))
	var hint := HBoxContainer.new(); hint.add_theme_constant_override("separation", 18)
	for pair in [["W  S", "choose"], ["Enter", "select"], ["Esc", "back"]]:
		hint.add_child(_l("%s  %s" % pair, f_bold, 12, MUTED))
	col.add_child(hint)

	var right := CenterContainer.new(); right.size_flags_horizontal = Control.SIZE_EXPAND_FILL; cols.add_child(right)
	panels.howto = _panel(right, "How to Play", [
		["W A S D", "Walk (Shift to stumble faster)"],
		["Mouse", "Look around. Click the game to capture the cursor, Esc for the pause"],
		["E", "Get up, grab a beer, sit and drink, do a line, hit the bong, open doors"],
		["Right / Left click", "Aim and fire the Glock (R to reload)"],
		["Z", "Holster or draw the Glock"],
		["E (when cuffed)", "Resist arrest: pull the gun and shoot it out with the police"],
		["", "Five beers and John is out for the night."]])
	panels.credits = _panel(right, "Credits", [
		["A game by", "Cessna"], ["Created and directed by", "Cessna"], ["Game design", "Cessna"],
		["Starring", "John, as himself"], ["Engine", "Godot 4"],
		["Cashier model", "\"Cashier Lady\" by nur in (sketchfab.com/mochi16), CC BY 4.0"], ["Police model", "Police with sunglasses (Adobe Fuse character)"], ["Bar facade", "\"Dirty street\" model (supplied by Cessna)"], ["Bar interior", "Modelled in Blender for this game"], ["", "No televisions were harmed in the making of this game."]])

	var foot := HBoxContainer.new(); foot.set_anchors_preset(Control.PRESET_BOTTOM_WIDE); foot.position.y = -36
	foot.offset_left = 96; foot.offset_right = -96; foot.offset_top = -40; foot.offset_bottom = -16
	var a := _l("Created by Cessna", f_body, 13, MUTED); a.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	foot.add_child(a); foot.add_child(_l("John's Beer Run · " + VERSION, f_body, 13, MUTED))
	title_root.add_child(foot)

func _spacer(h: int) -> Control:
	var c := Control.new(); c.custom_minimum_size = Vector2(0, h); return c

func _nav_button(text: String, act: String) -> Button:
	var b := Button.new(); b.text = "    " + text; b.flat = true; b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_override("font", f_display); b.add_theme_font_size_override("font_size", 32)
	b.add_theme_color_override("font_color", MUTED); b.add_theme_color_override("font_hover_color", INK)
	b.add_theme_color_override("font_focus_color", INK); b.add_theme_color_override("font_pressed_color", EMBER)
	var empty := StyleBoxEmpty.new()
	for st in ["normal", "hover", "pressed", "focus", "disabled"]: b.add_theme_stylebox_override(st, empty)
	b.set_meta("act", act)
	var ico := ColorRect.new(); ico.color = EMBER; ico.size = Vector2(14, 24); ico.position = Vector2(0, 12); ico.visible = false; ico.name = "Ico"
	b.add_child(ico)
	b.pressed.connect(func(): _act(act))
	b.mouse_entered.connect(func(): _select(buttons.find(b)))
	nav.add_child(b); buttons.append(b)
	return b

func _panel(parent: Control, title: String, rows: Array) -> Control:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new(); s.bg_color = Color(22 / 255.0, 15 / 255.0, 11 / 255.0, 0.84); s.border_color = LINE; s.set_border_width_all(1); s.set_corner_radius_all(14)
	s.content_margin_left = 28; s.content_margin_right = 28; s.content_margin_top = 24; s.content_margin_bottom = 24
	p.add_theme_stylebox_override("panel", s); p.custom_minimum_size = Vector2(440, 0); p.visible = false
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12); p.add_child(v)
	v.add_child(_l(title, f_display, 30, EMBER))
	for r in rows:
		var h := HBoxContainer.new(); h.add_theme_constant_override("separation", 14)
		if r[0] != "":
			var k := _l(r[0], f_bold, 13, Color("#1b120c")); var kb := PanelContainer.new()
			var ks := StyleBoxFlat.new(); ks.bg_color = INK; ks.set_corner_radius_all(6); ks.content_margin_left = 6; ks.content_margin_right = 6
			kb.add_theme_stylebox_override("panel", ks); kb.add_child(k); kb.custom_minimum_size = Vector2(90, 26); k.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			h.add_child(kb)
		var d := _l(r[1], f_body, 15, INK if r[0] != "" else MUTED); d.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; d.custom_minimum_size = Vector2(300, 0)
		d.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(d); v.add_child(h)
	var back := Button.new(); back.text = "Back"; back.add_theme_font_override("font", f_bold); back.pressed.connect(func(): _close_panel())
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	v.add_child(back)
	parent.add_child(p)
	return p

func _build_card() -> void:
	card_root = CenterContainer.new(); card_root.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(card_root)
	var bg := ColorRect.new(); bg.color = Color(12 / 255.0, 9 / 255.0, 8 / 255.0, 0.6); bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card_root.add_child(bg); bg.show_behind_parent = true
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new(); s.bg_color = Color(22 / 255.0, 15 / 255.0, 11 / 255.0, 0.92); s.border_color = LINE; s.set_border_width_all(1); s.set_corner_radius_all(18)
	for m in ["left", "right", "top", "bottom"]: s.set("content_margin_" + m, 32)
	p.add_theme_stylebox_override("panel", s); p.custom_minimum_size = Vector2(520, 0)
	var v := VBoxContainer.new(); v.add_theme_constant_override("separation", 12); p.add_child(v)
	v.add_child(_l("L I G H T S   O U T", f_bold, 12, EMBER))
	v.add_child(_l("John's out cold.", f_display, 44, INK))
	var txt := _l("Five beers deep and snoring through the fourth quarter. The fire's burning low and the TV is still talking to nobody.", f_body, 16, MUTED)
	txt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART; v.add_child(txt)
	card_stats = HBoxContainer.new(); card_stats.add_theme_constant_override("separation", 12); card_stats.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_child(card_stats)
	var again := Button.new(); again.text = "Wake him up and go again"; again.add_theme_font_override("font", f_display); again.add_theme_font_size_override("font_size", 20)
	var bs := StyleBoxFlat.new(); bs.bg_color = EMBER; bs.set_corner_radius_all(999); bs.content_margin_top = 10; bs.content_margin_bottom = 10
	again.add_theme_stylebox_override("normal", bs); again.add_theme_stylebox_override("hover", bs); again.add_theme_stylebox_override("focus", bs)
	again.add_theme_color_override("font_color", Color("#1b120c")); again.add_theme_color_override("font_hover_color", Color("#1b120c"))
	again.pressed.connect(func(): again_pressed.emit())
	v.add_child(again)
	var mm := Button.new(); mm.text = "Main menu"; mm.flat = true; mm.add_theme_font_override("font", f_bold); mm.pressed.connect(func(): menu_pressed.emit())
	mm.size_flags_horizontal = Control.SIZE_SHRINK_CENTER; v.add_child(mm)
	var fine := _l("A game by Cessna", f_body, 12, MUTED); fine.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(fine)
	card_root.add_child(p)
	card_root.visible = false

var failed_root: Control
var failed_why: Label
var failed_title: Label
func _build_failed() -> void:
	failed_root = Control.new(); failed_root.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(failed_root)
	var bg := ColorRect.new(); bg.color = Color(0, 0, 0, 0.78); bg.set_anchors_preset(Control.PRESET_FULL_RECT); failed_root.add_child(bg)
	var cc := CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_FULL_RECT); failed_root.add_child(cc)
	var band := PanelContainer.new(); var s := StyleBoxFlat.new(); s.bg_color = Color(0, 0, 0, 0.72); s.border_color = Color(200 / 255.0, 30 / 255.0, 30 / 255.0, 0.8)
	s.border_width_top = 2; s.border_width_bottom = 2; s.content_margin_top = 28; s.content_margin_bottom = 28; s.content_margin_left = 60; s.content_margin_right = 60
	band.add_theme_stylebox_override("panel", s); band.custom_minimum_size = Vector2(1400, 0); cc.add_child(band)
	var v := VBoxContainer.new(); v.alignment = BoxContainer.ALIGNMENT_CENTER; v.add_theme_constant_override("separation", 14); band.add_child(v)
	var mf := _l("MISSION FAILED", f_display, 92, Color("#d91f1f")); mf.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; failed_title = mf
	mf.add_theme_color_override("font_shadow_color", Color("#3a0000")); mf.add_theme_constant_override("shadow_offset_y", 4); v.add_child(mf)
	failed_why = _l("John shot the TV. Now what's he gonna watch?", f_body, 16, INK); failed_why.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(failed_why)
	var row := HBoxContainer.new(); row.alignment = BoxContainer.ALIGNMENT_CENTER; row.add_theme_constant_override("separation", 14); v.add_child(row)
	var go := Button.new(); go.text = "Try again"; go.custom_minimum_size = Vector2(200, 0); go.add_theme_font_override("font", f_display); go.add_theme_font_size_override("font_size", 20)
	go.pressed.connect(func(): retry_pressed.emit()); row.add_child(go)
	var mm := Button.new(); mm.text = "Main menu"; mm.add_theme_font_override("font", f_bold); mm.pressed.connect(func(): menu_pressed.emit()); row.add_child(mm)
	failed_root.visible = false

func show_failed(why: String, title := "MISSION FAILED") -> void:
	visible = true; title_root.visible = false; card_root.visible = false; failed_root.visible = true
	failed_why.text = why; failed_title.text = title

# ---------------------------------------------------------------- pause menu
const P_LABEL := {"continue": "Continue", "restart": "Restart", "menu": "Exit to Main Menu", "desktop": "Exit to Desktop"}
const P_CONFIRM := {"restart": "Restart the night? Select again", "menu": "Leave to the menu? Select again", "desktop": "Quit the game? Select again"}
var pause_root: Control
var p_buttons: Array[Button] = []
var p_sel := 0
var p_confirm := ""

func _build_pause() -> void:
	pause_root = Control.new(); pause_root.set_anchors_preset(Control.PRESET_FULL_RECT); add_child(pause_root)
	var bg := TextureRect.new(); bg.set_anchors_preset(Control.PRESET_FULL_RECT); bg.stretch_mode = TextureRect.STRETCH_SCALE
	var gt := GradientTexture2D.new(); gt.fill = GradientTexture2D.FILL_RADIAL; gt.fill_from = Vector2(0.3, 0.5); gt.fill_to = Vector2(1.1, 0.5)
	var gr := Gradient.new(); gr.set_color(0, Color(12 / 255.0, 9 / 255.0, 8 / 255.0, 0.72)); gr.set_color(1, Color(6 / 255.0, 4 / 255.0, 3 / 255.0, 0.9))
	gt.gradient = gr; bg.texture = gt; pause_root.add_child(bg)
	var cc := CenterContainer.new(); cc.set_anchors_preset(Control.PRESET_FULL_RECT); pause_root.add_child(cc)
	var col := VBoxContainer.new(); col.add_theme_constant_override("separation", 6); col.custom_minimum_size = Vector2(420, 0); cc.add_child(col)
	col.add_child(_shadowed(_l("Paused", f_display, 72, EMBER), EMBER_DEEP, 4))
	var sub := HBoxContainer.new(); sub.add_theme_constant_override("separation", 10)
	var bar := ColorRect.new(); bar.color = EMBER; bar.custom_minimum_size = Vector2(28, 2); bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sub.add_child(bar); sub.add_child(_l("J O H N ' S   B E E R   R U N", f_bold, 12, MUTED)); col.add_child(sub)
	col.add_child(_spacer(14))
	for act in ["continue", "restart", "menu", "desktop"]:
		var b := Button.new(); b.text = "    " + P_LABEL[act]; b.flat = true; b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.add_theme_font_override("font", f_display); b.add_theme_font_size_override("font_size", 32)
		b.add_theme_color_override("font_color", MUTED); b.add_theme_color_override("font_hover_color", INK); b.add_theme_color_override("font_focus_color", INK)
		var empty := StyleBoxEmpty.new()
		for st in ["normal", "hover", "pressed", "focus", "disabled"]: b.add_theme_stylebox_override(st, empty)
		b.set_meta("act", act)
		var ico := ColorRect.new(); ico.color = EMBER; ico.size = Vector2(14, 24); ico.position = Vector2(0, 12); ico.visible = false; ico.name = "Ico"; b.add_child(ico)
		b.pressed.connect(func(): _p_select(p_buttons.find(b)); _p_act(act))
		b.mouse_entered.connect(func(): _p_select(p_buttons.find(b)))
		col.add_child(b); p_buttons.append(b)
	col.add_child(_spacer(18))
	col.add_child(_l("W  S  choose     Enter  select     Esc  resume", f_bold, 12, MUTED))
	pause_root.visible = false

func show_pause() -> void:
	visible = true; title_root.visible = false; card_root.visible = false; failed_root.visible = false; pause_root.visible = true
	_p_clear(); _p_select(0)

func hide_pause() -> void:
	pause_root.visible = false; visible = false; _p_clear()

func is_paused_open() -> bool: return pause_root != null and pause_root.visible

func _p_select(i: int) -> void:
	if i < 0: return
	p_sel = (i + p_buttons.size()) % p_buttons.size()
	for j in p_buttons.size():
		var b := p_buttons[j]
		(b.get_node("Ico") as ColorRect).visible = j == p_sel
		b.add_theme_color_override("font_color", (EMBER if b.get_meta("act") == p_confirm else INK) if j == p_sel else MUTED)
		b.position.x = 6 if j == p_sel else 0

func _p_clear() -> void:
	p_confirm = ""
	for b in p_buttons: b.text = "    " + P_LABEL[b.get_meta("act")]

func _p_act(act: String) -> void:
	if act == "continue": pause_action.emit("continue"); return
	if p_confirm != act:
		_p_clear(); p_confirm = act
		p_buttons[p_sel].text = "    " + P_CONFIRM[act]; _p_select(p_sel)
		Sfx.play("flick"); return
	_p_clear(); pause_action.emit(act)

func _stat(big: String, small: String) -> Control:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new(); s.bg_color = Color(0, 0, 0, 0.35); s.border_color = LINE; s.set_border_width_all(1); s.set_corner_radius_all(10)
	s.content_margin_left = 18; s.content_margin_right = 18; s.content_margin_top = 8; s.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", s)
	var v := VBoxContainer.new(); p.add_child(v)
	var b := _l(big, f_display, 28, INK); b.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(b)
	var sm := _l(small.to_upper(), f_bold, 11, MUTED); sm.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER; v.add_child(sm)
	return p

# ---------------------------------------------------------------- API
func set_loading(loading: bool) -> void:
	start_btn.disabled = loading

func show_title() -> void:
	visible = true; title_root.visible = true; card_root.visible = false
	if failed_root: failed_root.visible = false
	_close_panel(); _select(0)

func show_end(beers: int, clock: String, ampm: String, steps: int) -> void:
	visible = true; title_root.visible = false; card_root.visible = true; failed_root.visible = false
	for c in card_stats.get_children(): c.queue_free()
	card_stats.add_child(_stat(str(beers), "Beers")); card_stats.add_child(_stat(clock, ampm)); card_stats.add_child(_stat(str(steps), "Steps"))

func hide_all() -> void:
	visible = false
	if failed_root: failed_root.visible = false

func _select(i: int) -> void:
	if i < 0: return
	sel = i
	for j in buttons.size():
		var b := buttons[j]
		(b.get_node("Ico") as ColorRect).visible = j == sel
		b.add_theme_color_override("font_color", INK if j == sel else MUTED)
		b.position.x = 6 if j == sel else 0

func _act(act: String) -> void:
	match act:
		"start": start_pressed.emit()
		"howto", "credits":
			_close_panel(); panel_open = act; panels[act].visible = true

func _close_panel() -> void:
	panel_open = ""
	for p in panels.values(): p.visible = false

func _unhandled_input(e: InputEvent) -> void:
	if is_paused_open():
		if e is InputEventKey and e.pressed and not e.echo:
			match e.keycode:
				KEY_W, KEY_UP: _p_clear(); _p_select(p_sel - 1); get_viewport().set_input_as_handled()
				KEY_S, KEY_DOWN: _p_clear(); _p_select(p_sel + 1); get_viewport().set_input_as_handled()
				KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _p_act(p_buttons[p_sel].get_meta("act")); get_viewport().set_input_as_handled()
				KEY_ESCAPE, KEY_P: pause_action.emit("continue"); get_viewport().set_input_as_handled()
		return
	if not visible or not title_root.visible: return
	if e is InputEventKey and e.pressed and not e.echo:
		match e.keycode:
			KEY_W, KEY_UP: _select((sel + buttons.size() - 1) % buttons.size()); get_viewport().set_input_as_handled()
			KEY_S, KEY_DOWN: _select((sel + 1) % buttons.size()); get_viewport().set_input_as_handled()
			KEY_ENTER, KEY_KP_ENTER, KEY_SPACE: _act(buttons[sel].get_meta("act")); get_viewport().set_input_as_handled()
			KEY_ESCAPE: _close_panel(); get_viewport().set_input_as_handled()

func _process(dt: float) -> void:
	t += dt
	# neon flicker on "Beer Run"
	var k := fmod(t, 7.0) / 7.0
	logo_run.modulate.a = 0.55 if (k > 0.93 and k < 0.95) else (0.7 if (k > 0.96 and k < 0.97) else 1.0)
