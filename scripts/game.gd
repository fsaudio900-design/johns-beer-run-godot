extends Node3D
## Game controller for the Godot port — stage 2: cabin life.
## Ports the web build's state machine (title / sitting / walking / busy / passout / end),
## the timed actions (stand up, fridge, sit + drink, line, bong), intoxication (drunk, wired,
## trip with flying cats), the TV, fire, doors, HUD, title + end screens and the camera.

const ANCHOR := Vector2(-2.0, 1.85)                 # in front of the recliner
const FRIDGE_SPOT := Vector3(5.25, -1.0, PI / 2)      # x, z, facing
const SNORT_SPOT := Vector3(3.89, 2.75, PI / 2)
const BONG_SPOT := Vector3(-5.37, 1.05, -PI / 2)
const TOILET := Vector2(4.75, 7.55)
const DOOR_X := 3.6
const FD_X := 0.9
const RZ := 5.0
const MAX_BEERS := 5
const LINE_LEN := 0.22
const BONG_H := 0.47
const BOWL_LOCAL := Vector3(0.127, 0.225, 0)
const STOCK_START := 6       # fridge starts stocked until the Fuel Stop run is ported (stage 6)
const WALK_SPEED := 2.1

const LINES := {
	start = ["Third quarter, and I'm dry. Better fix that."],
	up = ["Oof. Knees.", "Here we go again.", "Who put the floor down there?", "Stand up. Stand up, John.", "Last one. Probably."],
	fridge = ["There you are, sweetheart.", "Still cold. Good fridge.", "Ish the fridge moving?", "Hello, old friend.", "One more for the road. Not driving. Still."],
	drink = ["Now that's TV.", "Ahh. That's the stuff.", "Thish is a good game.", "Who's winning? Doesn't matter.", "Mmh. Just resting my eyes."],
	bong = ["Ohhh yeah. That's the good stuff.", "*cough* ...smooth.", "Mmm. Somebody call the cats."],
	trip = ["Whoa. Are the cats... flying?", "Hi, kitty. Hi. Hi, kitty.", "The walls are breathing, man.", "I can taste the colors.", "Fly, my pretties!", "That one has my face."],
	snort = ["Whoo! Okay. OKAY.", "Now we're cookin'.", "I can hear the TV from here. I AM the TV."],
	no_beer = ["Can't sit without a beer. That's just a chair."],
	flush = ["Ahh. Much better.", "Flush and done.", "Ten out of ten, would flush again."],
}

@onready var john: CharacterBody3D = $John
@onready var world: Node3D = $World
@onready var hud: CanvasLayer = $HUD
@onready var menu: CanvasLayer = $Menu
@onready var cam: Camera3D = $Camera3D
@onready var post_rect: ColorRect = $Post/Rect
@onready var env: Environment = $WorldEnvironment.environment

# ---- game state ----
var state := "title"
var tw = null                       # {t, dur, fn: Callable(k, t), done: Callable}
var clock_t := 0.0
var beers := 0
var minutes := 23 * 60 + 12
var has_beer := false
var stock := STOCK_START
var lines_left := 3
var boost_t := 0.0
var flash_t := 0.0
var trip_delay := -1.0
var trip_t := 0.0
var trip_vis := 0.0
var trip_say_t := 0.0
var drunk_vis := 0.0
var high_vis := 0.0
var hb_t := 0.0
var steps := 0
var last_step_sign := 0.0
var lurch := Vector3.ZERO
var fade := 0.0
var fade_target := 0.0
var flush_cd := 0.0
var crack_t := 0.0
var z_t := 0.0

# ---- camera ----
var yaw := 0.0
var pitch := 0.3
var dist := 3.3
var user_look := 0.0
var cam_target := Vector3.ZERO
var fwd_in := false

# ---- cabin props ----
var n := {}                         # named world nodes
var rest_rot := {}
var door_open := 0.0
var door_target := 0.0
var front_open := 0.0
var front_target := 0.0
var bong_home := Vector3(-6.15, 0.655, 1.0)
var bong_pos := Vector3(-6.15, 0.655, 1.0)
var bong_active := false
var bong_held := false
var lighter_on := false
var smoke_fill := 0.0
var bill_mode := "table"
var snort_obj: Node3D = null
var snort_p := 0.0
var line_x0 := {}
var hand_bill: MeshInstance3D
var lighter: MeshInstance3D
var flame: Sprite3D
var lighter_light: OmniLight3D
var bong_smoke_mat: StandardMaterial3D
var tv_viewport: SubViewport
var tv_draw: Node2D
var channel := 0
var chan_t := 0.0
var static_t := 0.0
var tv_t := 0.0
var light_e0 := {}
var floor_cans: Array[Node3D] = []
var smokes: Array = []
var cats: Array = []
var zzz: Array = []
var puff_tex: Texture2D = preload("res://assets/fx/puff.png")
var cat_tex: Texture2D = preload("res://assets/fx/cat.png")
# ---- stage 3: the visitor + front door peephole ----
var visitor: Node3D
var V := {st = "off", path = [], pi = 0, spd = 1.25, knocks = 0, knock_t = 0.0, talk = [], talk_t = 0.0, talk_i = 0, seen_peep = false, said_knock = false, y = 0.0}
var game_t := 0.0
var peeping := false
var peep_vis := 0.0
var peep_yaw := 0.0
var peep_pitch := 0.0
var peep_said := false
# ---- stage 4: the Glock ----
const GUN_HOME := Vector3(-3.08, 0.658, 2.46)
const GUN_SPOT := Vector3(-3.2, 1.9, 0.0)
const TVX := -2.0
const TVZ := -4.45
const GUN_TWIST := -1.35
var gun_rig: Node3D
var gun_muzzle := Vector3.ZERO
var armed := false
var gun_hidden := false
var ammo := 15
var reload_t := 0.0
var fire_cd := 0.0
var aim_t := 0.0
var aim_hold := 0.0
var rmb_down := false
var tv_dead := false
var aim_point := Vector3.ZERO
var aim_hit := {}
var holes: Array[Node3D] = []
var tracers: Array = []
var sparks: Array = []
var flash_spr: Sprite3D
var flash_light: OmniLight3D
var flash_time := 0.0
var flash_mark := 0.0
var mirror_broken := false
var shards: Array = []
var hole_mat: StandardMaterial3D
var amb_base: Color
var amb_energy: float
var loaded := false

func _ready() -> void:
	amb_base = env.ambient_light_color; amb_energy = env.ambient_light_energy
	await get_tree().process_frame          # world.gd has loaded the chunks
	_find_props()
	_build_tv()
	_build_fx()
	_build_gun()
	visitor = Node3D.new(); visitor.set_script(load("res://scripts/visitor.gd")); visitor.name = "Visitor"
	add_child(visitor); visitor.visible = false
	menu.start_pressed.connect(start)
	menu.again_pressed.connect(func(): reset(); _capture(true))
	menu.menu_pressed.connect(to_main_menu)
	menu.retry_pressed.connect(func(): reset(); _capture(true))
	reset()
	state = "title"
	menu.show_title()
	hud.visible = false
	loaded = true
	print("[game] ready: props ", n.keys().size())
	var a := _debug_args()
	if a.has("scenario"): _run_scenario(a.scenario, a.get("shots", "/tmp/shot"))

# ------------------------------------------------------------------ setup
func _find_props() -> void:
	for node in world.find_children("JBR_*", "", true, false):
		var key := String(node.name).trim_prefix("JBR_")
		if not n.has(key): n[key] = node
	for k in ["FridgeDoor", "BathDoor", "FrontDoor", "Bong"]:
		if n.has(k): rest_rot[k] = (n[k] as Node3D).rotation
	for i in 3:
		var l: Node3D = n.get("PowderLine%d" % i)
		if l: line_x0[i] = l.position.x
	for k in ["TvLight", "FireLight", "FridgeLight", "TripLight", "LampLight", "BulbLight", "PorchLight", "FlashLight"]:
		var l: Light3D = _light(k)
		if l: light_e0[k] = l.light_energy
	# bathroom mirror: a real reflective surface (the web build used a planar reflector)
	var mir: MeshInstance3D = _mesh_of(n.get("BathMirror"))
	if mir:
		var mm := StandardMaterial3D.new(); mm.albedo_color = Color(0.85, 0.88, 0.9); mm.metallic = 1.0; mm.roughness = 0.02
		mir.material_override = mm
		var probe := ReflectionProbe.new(); probe.size = Vector3(3.4, 2.9, 3.05); probe.box_projection = true
		probe.update_mode = ReflectionProbe.UPDATE_ONCE; probe.interior = true
		add_child(probe); probe.global_position = Vector3(3.65, 1.45, 6.73)
	# bong: detach from the world so it can be carried
	if n.has("Bong"):
		var b: Node3D = n.Bong
		bong_home = b.global_position; bong_pos = bong_home
		var sm: MeshInstance3D = b.find_child("JBR_BongSmoke", true, false)
		if sm:
			bong_smoke_mat = StandardMaterial3D.new(); bong_smoke_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			bong_smoke_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; bong_smoke_mat.albedo_color = Color(0.91, 0.91, 0.91, 0)
			sm.material_override = bong_smoke_mat
		for body in b.find_children("*", "StaticBody3D", true, false): body.queue_free()
	# the bill John holds while doing a line (a copy of the one on the table)
	if n.has("TableBill"):
		var tb: MeshInstance3D = _mesh_of(n.TableBill)
		if tb:
			hand_bill = MeshInstance3D.new(); hand_bill.mesh = tb.mesh
			for s in tb.mesh.get_surface_count(): hand_bill.set_surface_override_material(s, tb.get_active_material(s))
			hand_bill.visible = false; add_child(hand_bill)
	# lighter + flame for the bong
	lighter = MeshInstance3D.new(); var bm := BoxMesh.new(); bm.size = Vector3(0.022, 0.065, 0.014); lighter.mesh = bm
	var lm := StandardMaterial3D.new(); lm.albedo_color = Color("#c4271d"); lm.roughness = 0.4; lighter.material_override = lm
	lighter.visible = false; add_child(lighter)
	flame = Sprite3D.new(); flame.texture = puff_tex; flame.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	flame.modulate = Color(1, 0.67, 0.24); flame.pixel_size = 0.0007; flame.visible = false
	flame.shaded = false; flame.alpha_cut = SpriteBase3D.ALPHA_CUT_DISABLED
	add_child(flame)
	lighter_light = OmniLight3D.new(); lighter_light.light_color = Color(1, 0.63, 0.25); lighter_light.omni_range = 2.5; lighter_light.light_energy = 0
	add_child(lighter_light)

func _mesh_of(node: Node) -> MeshInstance3D:
	if node == null: return null
	if node is MeshInstance3D: return node
	var c := node.find_children("*", "MeshInstance3D", true, false)
	return c[0] if c.size() else null

func _light(k: String) -> Light3D:
	var x = n.get(k)
	if x == null: return null
	if x is Light3D: return x
	var c = (x as Node).find_children("*", "Light3D", true, false)
	return c[0] if c.size() else null

func _build_tv() -> void:
	tv_viewport = SubViewport.new(); tv_viewport.size = Vector2i(320, 240)
	tv_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	tv_viewport.disable_3d = true; tv_viewport.transparent_bg = false
	tv_draw = Node2D.new(); tv_draw.set_script(load("res://scripts/tv.gd"))
	tv_viewport.add_child(tv_draw); add_child(tv_viewport)
	var scr: MeshInstance3D = _mesh_of(n.get("TVScreen")) if n.has("TVScreen") else null
	if scr:
		var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_texture = tv_viewport.get_texture(); m.emission_enabled = false
		m.albedo_color = Color(1.25, 1.25, 1.25)
		scr.material_override = m

func _build_fx() -> void:
	for i in 30:
		var s := Sprite3D.new(); s.texture = cat_tex; s.billboard = BaseMaterial3D.BILLBOARD_ENABLED; s.shaded = false
		s.pixel_size = 0.004; s.visible = false; s.transparent = true
		s.set_meta("u", {orbit = i % 3 != 2, a = randf() * TAU, r = 0.9 + randf() * 3.2, h = 0.5 + randf() * 2.6,
			spd = (-1.0 if randf() < 0.5 else 1.0) * (0.4 + randf() * 0.9), bob = 1 + randf() * 2, ph = randf() * TAU,
			size = 0.5 + randf() * 0.5, hue = randf(), from = Vector3.ZERO, to = Vector3.ZERO, t = randf(), dur = 2.5 + randf() * 3, prev = Vector3.ZERO})
		add_child(s); cats.append(s)

# ------------------------------------------------------------------ helpers
func say(text: String, secs := 3.2) -> void: hud.say("John", text, secs)
func sm(k: float) -> float:
	k = clamp(k, 0.0, 1.0)
	return k * k * (3.0 - 2.0 * k)
func tween(dur: float, fn: Callable, done: Callable) -> void: tw = {t = 0.0, dur = dur, fn = fn, done = done}
func set_state(s: String) -> void: state = s
func pos2() -> Vector2: return Vector2(john.global_position.x, john.global_position.z)
func set_pos2(x: float, z: float) -> void: john.global_position = Vector3(x, john.global_position.y, z)
func drunk_level() -> float: return 0.0 if beers < 2 else float(beers - 1) / (MAX_BEERS - 1)
func is_outside() -> bool: return john.global_position.z < -RZ - 0.15

func near_door() -> bool: var p := pos2(); return abs(p.x - DOOR_X) < 0.85 and p.y > RZ - 1.3 and p.y < RZ + 1.1
func near_front() -> bool: var p := pos2(); return abs(p.x - FD_X) < 0.85 and p.y < -RZ + 1.35 and p.y > -RZ - 1.5
func near_toilet() -> bool: return pos2().distance_to(TOILET) < 1.0
func near_bong() -> bool: return pos2().distance_to(Vector2(BONG_SPOT.x, BONG_SPOT.y)) < 1.0
func near_table() -> bool: return pos2().distance_to(Vector2(SNORT_SPOT.x, SNORT_SPOT.y)) < 1.0
func near_fridge() -> bool: return pos2().distance_to(Vector2(FRIDGE_SPOT.x, FRIDGE_SPOT.y)) < 1.15
func near_chair() -> bool: return pos2().distance_to(ANCHOR) < 1.3

func side_dirs() -> Dictionary:
	var f: float = john.facing
	return {fx = sin(f), fz = cos(f), rx = -cos(f), rz = sin(f)}

func show_stock() -> void:
	var i := 0
	for k in n.keys():
		if String(k).begins_with("StockCan") or String(k).begins_with("FridgeCan"):
			(n[k] as Node3D).visible = int(String(k).trim_prefix("StockCan").trim_prefix("FridgeCan")) < stock

# ------------------------------------------------------------------ flow
func start() -> void:
	if not loaded: return
	menu.hide_all(); hud.visible = true
	set_state("sitting"); say(LINES.start[0], 3.4)
	_capture(true)

func _capture(on: bool) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE

func reset() -> void:
	door_target = 0; door_open = 0; front_target = 0; front_open = 0
	visitor_reset()
	gun_reset()
	beers = 0; minutes = 23 * 60 + 12; has_beer = false; steps = 0; stock = STOCK_START; show_stock()
	for c in floor_cans: c.queue_free()
	floor_cans.clear()
	for z in zzz: z.queue_free()
	zzz.clear()
	for s in smokes: s.node.queue_free()
	smokes.clear()
	john.pose = {sit = 1.0, phase = 0.0, walk = 0.0, reach = 0.0, droop = 0.0, clip_t = 0.0, bend = 0.0, squat = 0.0}
	john.snort_ik.w = 0.0; john.left_ik.w = 0.0; john.carry = 0.0
	boost_t = 0; flash_t = 0; lines_left = 3
	for i in 3:
		var l: Node3D = n.get("PowderLine%d" % i)
		if l: l.visible = true; l.scale.x = 1.0; l.position.x = line_x0[i]
	bill_mode = "table"; bong_active = false; bong_held = false; lighter_on = false; smoke_fill = 0; bong_pos = bong_home
	trip_delay = -1; trip_t = 0; trip_vis = 0; drunk_vis = 0; high_vis = 0
	john.global_position = Vector3(ANCHOR.x, 0.02, ANCHOR.y); john.facing = PI; john.velocity = Vector3.ZERO
	tw = null; fade_target = 0; fade = 0
	Sfx.stop_all_loops()
	hud.set_cans(0); hud.set_clock(minutes); hud.prompt("")
	menu.hide_all(); hud.visible = true
	yaw = 0; pitch = 0.3
	set_state("sitting"); say(LINES.start[0], 3.2)

func to_main_menu() -> void:
	reset(); set_state("title"); hud.visible = false; menu.show_title(); _capture(false)

func end_screen() -> void:
	set_state("end"); _capture(false)
	var h24 := (minutes / 60) % 24; var h := ((h24 + 11) % 12) + 1
	menu.show_end(beers, "%d:%02d" % [h, minutes % 60], "PM" if h24 >= 12 else "AM", steps)
	hud.prompt("")

# ------------------------------------------------------------------ actions
func interact() -> void:
	if not loaded: return
	if peeping:
		toggle_peep(false)
		if state == "walking": front_target = 1.0; Sfx.play("creak"); Sfx.play("thunk")
		return
	if state == "sitting" and tw == null: stand_up(); return
	if state != "walking": return
	if near_front():
		front_target = 0.0 if front_target > 0 else 1.0
		Sfx.play("creak")
		if front_target > 0: Sfx.play("thunk")
		return
	if near_door():
		door_target = 0.0 if door_target > 0 else 1.0
		Sfx.play("creak")
		if door_target > 0: Sfx.play("thunk")
		return
	if near_toilet():
		flush_toilet(); return
	if can_take_gun(): equip_gun(); return
	if near_bong(): hit_bong()
	elif near_table() and lines_left > 0: snort_line()
	elif not has_beer and near_fridge():
		if stock > 0: grab_beer()
		else: say("Empty. Gotta make a beer run.", 2.6)
	elif has_beer and near_chair(): sit_down()
	elif not has_beer and near_chair(): say(LINES.no_beer[0], 2.4)

func flush_toilet() -> void:
	if flush_cd > 0: return
	flush_cd = 4; Sfx.play("flush"); say(LINES.flush.pick_random(), 2.4)

func stand_up() -> void:
	set_state("busy"); hud.prompt(""); Sfx.play("creak"); john.pose.clip_t = 0.0
	var _fn := func(k, _t):
		john.pose.sit = 1.0 - sm(k)
	var _done := func():
		john.pose.sit = 0.0; set_pos2(ANCHOR.x, ANCHOR.y); set_state("walking")
		say(LINES.up[min(beers, 4)], 2.6)
	tween(1.5, _fn, _done)

func _walk_to(fx: float, fz: float, fr: float, spot: Vector3, a: float) -> void:
	set_pos2(lerp(fx, spot.x, sm(a)), lerp(fz, spot.y, sm(a)))
	john.facing = lerp_angle(fr, spot.z, sm(a))

func grab_beer() -> void:
	set_state("busy"); hud.prompt("")
	var p := pos2(); var fr: float = john.facing
	var st := {gave = false, opened = false, closed = false}
	var _fn := func(_k, t):
		_walk_to(p.x, p.y, fr, FRIDGE_SPOT, clamp(t / 0.4, 0.0, 1.0))
		var door: float = 0.0 if t < 0.35 else (sm((t - 0.35) / 0.45) if t < 0.8 else (1.0 if t < 1.5 else 1.0 - sm(clamp((t - 1.5) / 0.45, 0.0, 1.0))))
		if t > 0.35 and not st.opened: st.opened = true; Sfx.play("fridge")
		_fridge_door(door)
		john.pose.reach = 0.0 if t < 0.7 else (sm((t - 0.7) / 0.35) if t < 1.05 else (1.0 if t < 1.3 else 1.0 - sm(clamp((t - 1.3) / 0.45, 0.0, 1.0))))
		if t > 1.1 and not st.gave: st.gave = true; has_beer = true; john.has_can = true; stock = max(0, stock - 1); show_stock()
		if t > 1.9 and not st.closed: st.closed = true; Sfx.play("thunk")
	var _done := func():
		_fridge_door(0.0); john.pose.reach = 0.0; set_state("walking"); say(LINES.fridge[min(beers, 4)], 2.6)
	tween(2.2, _fn, _done)

func _fridge_door(k: float) -> void:
	if n.has("FridgeDoor"): (n.FridgeDoor as Node3D).rotation.y = rest_rot.FridgeDoor.y + k * 1.85
	var l := _light("FridgeLight")
	if l: l.light_energy = k * 1.6 * 0.9

func sit_down() -> void:
	set_state("busy"); hud.prompt("")
	var p := pos2(); var fr: float = john.facing; john.pose.clip_t = 0.0
	var _fn := func(_k, t):
		var a: float = clamp(t / 0.6, 0.0, 1.0); var b: float = clamp((t - 0.5) / 1.5, 0.0, 1.0)
		_walk_to(p.x, p.y, fr, Vector3(ANCHOR.x, ANCHOR.y, PI), a)
		john.pose.walk = 0.6 if a < 1 else 0.0; john.pose.phase += 0.12 * (1 if a < 1 else 0)
		john.pose.sit = sm(b)
	var _done := func():
		john.pose.sit = 1.0; Sfx.play("creak"); drink()
	tween(2.0, _fn, _done)

func drink() -> void:
	set_state("busy"); Sfx.play("open")
	var g := {n = 0}; john.pose.clip_t = 0.0
	var L: float = john.clip_len
	var _fn := func(_k, t):
		john.pose.clip_t = t
		if t > L * 0.38 and g.n < 4 and t > L * 0.38 + g.n * 0.36: Sfx.play("gulp"); g.n += 1
	var _done := func():
		john.pose.clip_t = 0.0; has_beer = false; john.has_can = false; Sfx.play("ahh")
		beers += 1; minutes += 22; hud.set_cans(beers); hud.set_clock(minutes)
		toss_can()
		if beers >= MAX_BEERS: pass_out()
		else: set_state("sitting"); say(LINES.drink[beers - 1], 3.0)
	tween(L, _fn, _done)

func toss_can() -> void:
	if john.can_mesh == null: return
	var c := MeshInstance3D.new(); c.mesh = john.can_mesh.mesh; c.material_override = john.can_mesh.material_override
	var sc: Vector3 = john.can_mesh.global_transform.basis.get_scale()
	var crush := 0.6 + randf() * 0.3
	# the can model stands along its local Z; lay it on its side on the floor
	var bs := Basis(Vector3.UP, randf() * TAU) * Basis(Vector3.RIGHT, PI / 2)
	c.transform = Transform3D(bs * Basis.from_scale(Vector3(sc.x, sc.y, sc.z * crush)), Vector3.ZERO)
	add_child(c)
	var aabb := c.get_aabb()
	var r: float = max(aabb.size.x, aabb.size.y) * 0.5 * sc.x
	c.global_position = Vector3(ANCHOR.x + 0.85 + randf() * 0.5, r * 0.9 - aabb.position.y * 0, ANCHOR.y + 0.5 + randf() * 0.6)
	floor_cans.append(c)
	Sfx.play("crush", 0.0, 1.0, 0.2)

func pass_out() -> void:
	set_state("passout"); hud.prompt(""); say("Just gonna... rest my...", 2.6)
	get_tree().create_timer(1.5).timeout.connect(func(): if state == "passout" or state == "end": _snore())
	var _droop := func(k, _t): john.pose.droop = sm(k)
	tween(3.5, _droop, func(): pass)
	get_tree().create_timer(3.5).timeout.connect(func(): if state == "passout": fade_target = 0.55)
	get_tree().create_timer(7.2).timeout.connect(func(): if state == "passout": end_screen())

func _snore() -> void:
	if state != "passout" and state != "end": return
	Sfx.play("snore")
	get_tree().create_timer(2.6).timeout.connect(_snore)

func line_point() -> Vector3:
	if snort_obj == null: return Vector3(SNORT_SPOT.x + 0.6, 0.8, SNORT_SPOT.y)
	return Vector3(line_x0[snort_obj.get_meta("i")] - LINE_LEN / 2 + LINE_LEN * min(snort_p, 0.97), 0.797, snort_obj.global_position.z)

func snort_line() -> void:
	var idx := 3 - lines_left
	var line: Node3D = n.get("PowderLine%d" % idx)
	if line == null: return
	line.set_meta("i", idx)
	set_state("busy"); hud.prompt(""); snort_line_obj_set(line); snort_p = 0.0; gun_hidden = true
	var p := pos2(); var fr: float = john.facing
	var st := {sniffed = false, done = false}
	bill_mode = "table"
	var bill_home: Vector3 = (n.TableBill as Node3D).global_position if n.has("TableBill") else Vector3(SNORT_SPOT.x + 0.6, 0.8, SNORT_SPOT.y + 0.2)
	var _fn := func(_k, t):
		_walk_to(p.x, p.y, fr, SNORT_SPOT, clamp(t / 0.4, 0.0, 1.0))
		var d := side_dirs()
		var at_table := Vector3(bill_home.x + d.rx * 0.07, bill_home.y + 0.07, bill_home.z + d.rz * 0.07)
		var nose: Vector3 = john.nose_world()
		var dir := (line_point() - nose).normalized()
		var at_nose := nose + dir * 0.09 + Vector3(d.rx * 0.075 - d.fx * 0.03, -0.02, d.rz * 0.075 - d.fz * 0.03)
		var down: float = 0.0 if t < 0.6 else (sm((t - 0.6) / 0.6) if t < 1.2 else (1.0 if t < 2.15 else 1.0 - sm(clamp((t - 2.15) / 0.5, 0.0, 1.0))))
		john.pose.bend = down; john.pose.squat = down * 0.55
		john.snort_ik.w = sm(t / 0.3) if t < 0.3 else (1.0 if t < 2.55 else 1.0 - sm(clamp((t - 2.55) / 0.5, 0.0, 1.0)))
		if t < 0.75: john.snort_ik.target = at_table
		elif t < 1.2: john.snort_ik.target = at_table.lerp(at_nose, sm((t - 0.75) / 0.45))
		elif t < 2.15: john.snort_ik.target = at_nose
		elif t < 2.55: john.snort_ik.target = at_nose.lerp(at_table, sm((t - 2.15) / 0.4))
		else: john.snort_ik.target = at_table
		bill_mode = "table" if t < 0.72 else ("hand" if t < 1.15 else ("nose" if t < 2.15 else ("hand" if t < 2.52 else "table")))
		snort_p = clamp((t - 1.25) / 0.8, 0.0, 1.0)
		line.scale.x = max(0.001, 1.0 - snort_p); line.position.x = line_x0[idx] + LINE_LEN * snort_p / 2
		if t > 1.25 and not st.sniffed: st.sniffed = true; Sfx.play("sniff")
		if t > 2.05 and not st.done:
			st.done = true; line.visible = false; lines_left -= 1
			boost_t = min(90.0, boost_t + 30.0); flash_t = 0.45; say(LINES.snort[2 - lines_left], 2.8)
	var _done := func():
		john.pose.bend = 0.0; john.pose.squat = 0.0; john.snort_ik.w = 0.0; bill_mode = "table"; snort_line_obj_set(null); gun_hidden = false; set_state("walking")
	tween(3.1, _fn, _done)

func snort_line_obj_set(l: Node3D) -> void: snort_obj = l

func bowl_world() -> Vector3:
	return (n.Bong as Node3D).global_transform * BOWL_LOCAL if n.has("Bong") else bong_pos

func hit_bong() -> void:
	if not n.has("Bong"): return
	set_state("busy"); hud.prompt(""); bong_active = true; john.has_can = false; gun_hidden = true
	var p := pos2(); var fr: float = john.facing
	var st := {flicked = false, last_bub = 0.0, exhaled = false, coughed = false}
	var _fn := func(_k, t):
		_walk_to(p.x, p.y, fr, BONG_SPOT, clamp(t / 0.4, 0.0, 1.0))
		var d := side_dirs(); var lx: float = -d.rx; var lz: float = -d.rz
		var nose: Vector3 = john.nose_world()
		var mouth := nose + Vector3(d.fx * 0.02, -0.075, d.fz * 0.02)
		var at_mouth := mouth + Vector3(d.fx * 0.035, -BONG_H, d.fz * 0.035)
		var lift: float = 0.0 if t < 0.85 else (sm((t - 0.85) / 0.55) if t < 1.4 else (1.0 if t < 2.95 else (1.0 - sm((t - 2.95) / 0.5) if t < 3.45 else 0.0)))
		bong_held = t >= 0.85 and t < 3.45
		bong_pos = bong_home.lerp(at_mouth, lift)
		var reach_bend: float = 0.0 if t < 0.4 else (sm((t - 0.4) / 0.45) if t < 0.85 else 1.0)
		john.pose.bend = (0.42 * (1 - lift) + 0.1 * lift) * reach_bend * ((1.0 - sm(clamp((t - 3.45) / 0.5, 0.0, 1.0))) if t > 3.45 else 1.0)
		john.pose.squat = john.pose.bend * 0.6
		john.snort_ik.w = sm(t / 0.4) if t < 0.4 else (1.0 if t < 3.5 else 1.0 - sm(clamp((t - 3.5) / 0.5, 0.0, 1.0)))
		john.snort_ik.target = bong_pos + Vector3(d.rx * 0.06 - d.fx * 0.04, 0.24, d.rz * 0.06 - d.fz * 0.04)
		john.left_ik.w = 0.0 if t < 1.1 else (sm((t - 1.1) / 0.35) if t < 1.45 else (1.0 if t < 2.85 else 1.0 - sm(clamp((t - 2.85) / 0.4, 0.0, 1.0))))
		john.left_ik.target = bowl_world() + Vector3(lx * 0.06 - d.fx * 0.02, -0.02, lz * 0.06 - d.fz * 0.02)
		lighter_on = t > 1.4 and t < 2.85
		if t > 1.4 and not st.flicked: st.flicked = true; Sfx.play("flick")
		smoke_fill = 0.0 if t < 1.55 else ((t - 1.55) / 1.25 if t < 2.8 else (1.0 - (t - 2.8) / 0.25 if t < 3.05 else 0.0))
		if t > 1.55 and t < 2.8 and t - st.last_bub > 0.045 + randf() * 0.06: st.last_bub = t; Sfx.play_var("bubble", 4)
		if t > 2.9 and not st.exhaled: st.exhaled = true; Sfx.play("exhale")
		if t > 2.95 and t < 3.9:
			for i in 2:
				puff(mouth + Vector3((randf() - 0.5) * 0.05, 0, (randf() - 0.5) * 0.05),
					Vector3(d.fx * (0.5 + randf() * 0.5) + (randf() - 0.5) * 0.3, 0.15 + randf() * 0.25, d.fz * (0.5 + randf() * 0.5) + (randf() - 0.5) * 0.3),
					0.35 + randf() * 0.25, 2.5 + randf() * 1.5)
		if t > 3.9 and not st.coughed: st.coughed = true; Sfx.play("cough")
	var _done := func():
		john.pose.bend = 0.0; john.pose.squat = 0.0; john.snort_ik.w = 0.0; john.left_ik.w = 0.0
		bong_active = false; bong_held = false; lighter_on = false; smoke_fill = 0.0; bong_pos = bong_home; gun_hidden = false
		john.has_can = has_beer
		set_state("walking")
		if trip_t > 0: trip_t = min(120.0, trip_t + 30.0)
		elif trip_delay < 0: trip_delay = 5.0
		say(LINES.bong.pick_random(), 2.8)
	tween(4.4, _fn, _done)

func puff(p: Vector3, v: Vector3, size: float, life: float) -> void:
	var s := Sprite3D.new(); s.texture = puff_tex; s.billboard = BaseMaterial3D.BILLBOARD_ENABLED; s.shaded = false
	s.modulate = Color(0.87, 0.87, 0.87, 0); s.pixel_size = size * 0.3 / 128.0; s.transparent = true
	add_child(s); s.global_position = p
	smokes.append({node = s, v = v, life = 0.0, max = life, size = size})

# ------------------------------------------------------------------ input
func _unhandled_input(e: InputEvent) -> void:
	if state == "title" or state == "end": return
	if e is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED:
		var mx: float = e.relative.x; var my: float = e.relative.y
		if abs(mx) > 300 or abs(my) > 300: return
		if peeping:
			peep_yaw = clamp(peep_yaw - mx * 0.0018, -0.5, 0.5); peep_pitch = clamp(peep_pitch - my * 0.0018, -0.35, 0.3)
			return
		var sens := 0.0014 if aim_t > 0.5 else 0.0026
		yaw -= mx * sens; pitch = clamp(pitch + my * sens * 0.8, -0.45 if aim_t > 0.3 else 0.02, 1.0); user_look = 3.0
	elif e is InputEventMouseButton and e.pressed:
		if e.button_index == MOUSE_BUTTON_LEFT and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED: _capture(true)
		elif e.button_index == MOUSE_BUTTON_LEFT and armed: fire()
		elif e.button_index == MOUSE_BUTTON_RIGHT: rmb_down = true
		elif e.button_index == MOUSE_BUTTON_WHEEL_UP: dist = clamp(dist - 0.2, 1.8, 5.0)
		elif e.button_index == MOUSE_BUTTON_WHEEL_DOWN: dist = clamp(dist + 0.2, 1.8, 5.0)
	elif e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_RIGHT: rmb_down = false
	elif e is InputEventKey and e.pressed and not e.echo and e.keycode == KEY_R and armed and reload_t <= 0 and ammo < 15 and state == "walking":
		reload_t = 1.3; Sfx.play("reload")
	elif e.is_action_pressed("interact") and not e.is_echo(): interact()
	elif e.is_action_pressed("peephole") and not e.is_echo() and state == "walking":
		if peeping: toggle_peep(false)
		elif near_front() and not is_outside() and front_open < 0.05 and front_target == 0: toggle_peep(true)
	elif e.is_action_pressed("ui_cancel"): _capture(Input.mouse_mode != Input.MOUSE_MODE_CAPTURED)

# ------------------------------------------------------------------ frame
func _physics_process(dt: float) -> void:
	if not loaded: return
	if state == "walking":
		var ix := 0.0 if peeping else Input.get_axis("move_left", "move_right"); var iz := 0.0 if peeping else Input.get_axis("move_back", "move_forward")
		var fx := -sin(yaw); var fz := -cos(yaw); var rx := cos(yaw); var rz := -sin(yaw)
		var mx := fx * iz + rx * ix; var mz := fz * iz + rz * ix; var ml := Vector2(mx, mz).length()
		var vel := Vector3.ZERO
		if ml > 0:
			mx /= ml; mz /= ml
			var b := float(beers) / MAX_BEERS
			var sway := sin(clock_t * 1.6) * 0.95 * b + sin(clock_t * 3.7) * 0.35 * b + sin(clock_t * 0.6) * 0.25 * b
			if randf() < dt * b * 0.7:
				var a := randf() * TAU; lurch = Vector3(cos(a), 0, sin(a)) * (1.2 + 1.6 * b)
			var sx := mx + (-mz) * sway; var sz := mz + mx * sway; var sl := Vector2(sx, sz).length()
			var sp := WALK_SPEED * (1.0 - b * 0.12) * (1.9 if boost_t > 0 else 1.0) * (1.35 if Input.is_action_pressed("run") else 1.0)
			vel = Vector3(sx / sl * sp, 0, sz / sl * sp)
			if not (aim_t > 0.3 or aim_hold > 0): john.facing = lerp_angle(john.facing, atan2(mx, mz), 1.0 - exp(-dt * 10.0))
		fwd_in = iz > 0 and ix == 0
		if aim_t > 0.5: vel.x *= 0.55; vel.z *= 0.55
		if armed and not gun_hidden and (aim_t > 0.3 or aim_hold > 0): john.facing = lerp_angle(john.facing, yaw + PI, 1.0 - exp(-dt * 18))
		vel += lurch; lurch *= exp(-dt * 3.5)
		john.velocity.x = vel.x; john.velocity.z = vel.z
		john.velocity.y = -0.5 if john.is_on_floor() else john.velocity.y - 9.8 * dt
		john.move_and_slide()
		john.pose.walk = lerp(john.pose.walk, 1.0 if ml > 0 else 0.0, 1.0 - exp(-dt * 10.0))
		john.pose.phase += dt * 8.5 * john.pose.walk * (1.55 if boost_t > 0 else 1.0)
		var sg := signf(sin(john.pose.phase))
		if john.pose.walk > 0.5 and sg != last_step_sign: last_step_sign = sg; steps += 1; Sfx.play("step")
		_prompts()
	else:
		john.pose.walk = lerp(john.pose.walk, 0.0, 1.0 - exp(-dt * 10.0))
		if state == "sitting" and tw == null: hud.prompt("Get up out of the chair" if beers == 0 else "Get up for another", true)

func _prompts() -> void:
	if peeping: hud.prompt("Open the door")
	elif near_front():
		var inside := not is_outside()
		hud.prompt("Answer the door" if (visitor_waiting() and front_target == 0 and inside) else ("Close the front door" if front_target > 0 else "Open the front door"), true, front_target == 0 and inside)
	elif near_door(): hud.prompt("Close the door" if door_target > 0 else "Open the bathroom door")
	elif near_toilet(): hud.prompt("Flush the toilet")
	elif can_take_gun(): hud.prompt("Pick up the Glock")
	elif near_bong(): hud.prompt("" if bong_active else "Hit the bong")
	elif near_table(): hud.prompt("Do a line" if lines_left > 0 else "Table's clean", lines_left > 0)
	elif not has_beer and near_fridge(): hud.prompt("Grab a cold one" if stock > 0 else "The fridge is empty", stock > 0)
	elif has_beer and near_chair(): hud.prompt("Sit down and drink")
	elif not has_beer and near_chair(): hud.prompt("Get a beer from the fridge first", false)
	elif is_outside(): hud.prompt("Head back in to the chair" if has_beer else "Head back in. The beer is inside", false)
	else: hud.prompt("Back to the chair" if has_beer else ("Head to the fridge" if stock > 0 else "The fridge is empty"), false)

func _process(dt: float) -> void:
	if not loaded: return
	dt = min(dt, 0.25 if debug_run else 0.05)
	clock_t += dt
	user_look -= dt
	if tw != null:
		tw.t += dt
		var k: float = clamp(tw.t / tw.dur, 0.0, 1.0)
		tw.fn.call(k, tw.t)
		if k >= 1.0:
			var d: Callable = tw.done; tw = null; d.call()
	flush_cd = max(0.0, flush_cd - dt)

	# ---- John's pose + held props
	john.grip_w = 1.0 if armed and not gun_hidden else 0.0
	john.apply_pose(clock_t, float(beers) / MAX_BEERS)
	_update_gun(dt)
	_update_props(dt)

	# ---- fire + TV
	var fl := sin(clock_t * 13) * 0.25 + sin(clock_t * 7.3) * 0.2 + randf() * 0.25
	var fire := _light("FireLight")
	if fire: fire.light_energy = light_e0.get("FireLight", 2.0) * (2.4 + fl) / 2.4
	crack_t -= dt
	if crack_t < 0:
		crack_t = 0.05 + randf() * 0.35
		if state != "title": Sfx.play_var("crackle", 6, -4.0)
	chan_t += dt
	if chan_t > 14: chan_t = 0; channel = (channel + 1) % 3; static_t = 0.35
	if static_t > 0: static_t -= dt
	tv_t += dt
	if tv_t > 1.0 / 20.0:
		tv_t = 0; tv_draw.refresh(clock_t, channel, static_t, trip_vis, tv_dead)
	var tvl := _light("TvLight")
	if tvl and tv_dead: tvl.light_energy = 0.0
	elif tvl:
		var tvb: float = 1.6 if static_t > 0 else [1.3, 1.6, 1.1][channel]
		tvl.light_energy = (tvb + sin(clock_t * 5) * 0.15 + randf() * 0.2) * 0.9
		tvl.light_color = Color("#d0d8ff") if static_t > 0 else [Color("#7fcf8a"), Color("#a8cfff"), Color("#6a8cff")][channel]

	# ---- doors
	door_open = lerp(door_open, door_target, 1.0 - exp(-dt * 5))
	if n.has("BathDoor"): (n.BathDoor as Node3D).rotation.y = rest_rot.BathDoor.y - door_open * 1.7
	front_open = lerp(front_open, front_target, 1.0 - exp(-dt * 4))
	if n.has("FrontDoor"): (n.FrontDoor as Node3D).rotation.y = rest_rot.FrontDoor.y - front_open * 1.55
	update_visitor(dt)
	if peeping and state != "walking": toggle_peep(false)
	peep_vis = lerp(peep_vis, 1.0 if peeping else 0.0, 1.0 - exp(-dt * 14))
	if peep_vis < 0.01 and not peeping: peep_vis = 0.0
	var mirror: Node3D = n.get("BathMirror")
	if mirror: mirror.visible = not mirror_broken and (cam.global_position.z > RZ - 1.5 or john.global_position.z > RZ - 0.6)
	_update_shards(dt)

	# ---- trip
	if state != "title" and state != "end":
		if trip_delay >= 0:
			trip_delay -= dt
			if trip_delay < 0: trip_t = 45; trip_say_t = 0; say(LINES.trip[0], 3.2)
		if trip_t > 0:
			trip_t = max(0.0, trip_t - dt); trip_say_t += dt
			if trip_say_t > 9: trip_say_t = 0; say(LINES.trip[1 + randi() % (LINES.trip.size() - 1)], 2.8)
			if randf() < dt * 0.9 * trip_vis: Sfx.play_var("meow", 3)
	trip_vis = lerp(trip_vis, min(1.0, trip_t / 6.0) if trip_t > 0 else 0.0, 1.0 - exp(-dt * (0.55 if trip_t > 0 else 0.35)))
	if trip_vis < 0.002 and trip_t <= 0: trip_vis = 0
	Sfx.set_loop("drone_loop", trip_vis, dt)
	Sfx.set_loop("room_loop", 0.0 if state == "title" else 1.0, dt, 1.0)
	_update_cats(dt)
	_update_smoke(dt)
	var tl := _light("TripLight")
	if trip_vis > 0:
		var hh := fmod(clock_t * 0.12, 1.0)
		env.ambient_light_color = amb_base.lerp(Color.from_hsv(hh, 0.9, 0.95), trip_vis * 0.8)
		env.ambient_light_energy = amb_energy * (1.0 + 1.3 * trip_vis)
		if tl:
			tl.global_position = john.global_position + Vector3(cos(clock_t) * 1.5, 2.4, sin(clock_t) * 1.5)
			tl.light_color = Color.from_hsv(fmod(hh + 0.5, 1.0), 1, 1); tl.light_energy = 3.2 * trip_vis * 0.9
	else:
		env.ambient_light_color = amb_base; env.ambient_light_energy = amb_energy
		if tl: tl.light_energy = 0
	hud.set_pill("trip", trip_t)

	# ---- Zzz
	if state == "passout" or state == "end":
		z_t -= dt
		if z_t < 0 and john.pose.droop > 0.6: z_t = 1.1; _spawn_z()
	for i in range(zzz.size() - 1, -1, -1):
		var z: Label3D = zzz[i]; var life: float = z.get_meta("life") + dt; z.set_meta("life", life)
		z.position.y += dt * 0.25; z.position.x += sin(life * 3) * dt * 0.15
		z.pixel_size = 0.0018 * (1.0 + life * 0.55); z.modulate.a = max(0.0, 1.0 - life / 3.0)
		if life > 3: z.queue_free(); zzz.remove_at(i)

	# ---- intoxication
	if state != "title" and state != "end" and boost_t > 0:
		boost_t = max(0.0, boost_t - dt); hb_t -= dt
		if hb_t < 0: hb_t = 0.5 - 0.15 * high_vis; Sfx.play("beat")
	drunk_vis = lerp(drunk_vis, drunk_level(), 1.0 - exp(-dt * 0.8))
	high_vis = lerp(high_vis, clamp(boost_t / 6.0, 0.0, 1.0) if boost_t > 0 else 0.0, 1.0 - exp(-dt * 2.5))
	flash_t = max(0.0, flash_t - dt)
	hud.set_pill("boost", boost_t)
	fade = move_toward(fade, fade_target, dt / 2.5)

	_update_camera(dt)
	var m: ShaderMaterial = post_rect.material
	m.set_shader_parameter("u_drunk", drunk_vis * (0.85 + 0.15 * sin(clock_t * 1.3)))
	m.set_shader_parameter("u_high", high_vis)
	m.set_shader_parameter("u_trip", trip_vis)
	m.set_shader_parameter("u_flash", flash_t * 1.2 if flash_t > 0 else 0.0)
	m.set_shader_parameter("u_vignette", 0.35 + drunk_level() * 0.5)
	m.set_shader_parameter("u_fade", fade)
	m.set_shader_parameter("u_peep", peep_vis)

func _update_props(_dt: float) -> void:
	if n.has("Bong"):
		var b: Node3D = n.Bong
		b.global_position = bong_pos
		b.rotation = Vector3(0, john.facing, 0.08) if bong_held else rest_rot.Bong
	if bong_smoke_mat: bong_smoke_mat.albedo_color.a = smoke_fill * 0.75
	lighter.visible = false; flame.visible = false; lighter_light.light_energy = 0
	if bong_active and john.left_ik.w > 0.5:
		var hp: Vector3 = john.hand_world(false); var ep: Vector3 = john.elbow_world(false)
		var dir := (hp - ep).normalized()
		lighter.global_position = hp + dir * 0.06; lighter.visible = true
		if lighter.global_position.distance_to(bong_pos) > 0.01: lighter.look_at(bong_pos)
		if lighter_on:
			flame.visible = true; flame.global_position = lighter.global_position + Vector3(0, 0.06, 0)
			flame.scale = Vector3(0.045 + randf() * 0.015, 0.07 + randf() * 0.03, 1) * 14.0
			lighter_light.global_position = flame.global_position; lighter_light.light_energy = (0.8 + randf() * 0.5) * 0.9
	var tb: Node3D = n.get("TableBill")
	if tb: tb.visible = bill_mode == "table"
	if hand_bill:
		hand_bill.visible = bill_mode != "table"
		if bill_mode == "hand":
			var hp: Vector3 = john.hand_world(true); var ep: Vector3 = john.elbow_world(true)
			var dir := (hp - ep).normalized()
			hand_bill.global_position = hp + dir * 0.075
			var side := dir.cross(Vector3.UP)
			if side.length_squared() < 1e-4: side = Vector3.RIGHT
			hand_bill.look_at(hand_bill.global_position + side.normalized())
		elif bill_mode == "nose":
			var np: Vector3 = john.nose_world(); var lp := line_point()
			hand_bill.global_position = np + (lp - np).normalized() * 0.085
			hand_bill.look_at(lp)

func _update_cats(dt: float) -> void:
	var vis := trip_vis
	var cr := cam.global_transform.basis.x
	var jp := john.global_position
	for c: Sprite3D in cats:
		var u: Dictionary = c.get_meta("u")
		c.visible = vis > 0.02
		if not c.visible: continue
		u.prev = c.position
		if u.orbit:
			u.a += u.spd * dt
			c.position = Vector3(jp.x + cos(u.a) * u.r, u.h + sin(clock_t * u.bob + u.ph) * 0.35, jp.z + sin(u.a) * u.r)
		else:
			u.t += dt / u.dur
			if u.t >= 1 or u.from == Vector3.ZERO:
				u.t = 0; u.from = _rnd_room_pt(); u.to = _rnd_room_pt()
			c.position = u.from.lerp(u.to, u.t); c.position.y += sin(u.t * PI * 3 + u.ph) * 0.3
		c.position = Vector3(clamp(c.position.x, -6.6, 6.6), clamp(c.position.y, 0.25, 3.3), clamp(c.position.z, -4.6, 4.6))
		var dir := -1.0 if (c.position - u.prev).dot(cr) < 0 else 1.0
		var flap := 1.0 + 0.12 * sin(clock_t * 14 + u.ph)
		c.flip_h = dir < 0
		c.scale = Vector3(u.size, u.size * flap * 0.9, 1)
		c.rotation.z = sin(clock_t * 2 + u.ph) * 0.25
		var col := Color.from_hsv(fmod(u.hue + clock_t * 0.25, 1.0), 0.75, 1.0); col.a = vis
		c.modulate = col

func _rnd_room_pt() -> Vector3:
	return Vector3(-6.3 + randf() * 12.6, 0.4 + randf() * 2.8, -4.3 + randf() * 8.6)

func _update_smoke(dt: float) -> void:
	for i in range(smokes.size() - 1, -1, -1):
		var s: Dictionary = smokes[i]; s.life += dt
		var node: Sprite3D = s.node
		node.global_position += s.v * dt; s.v *= exp(-dt * 1.3); s.v.y += dt * 0.15
		var k: float = s.life / s.max
		node.pixel_size = s.size * (0.3 + k * 1.8) / 128.0
		node.modulate.a = 0.5 * sin(PI * min(1.0, k))
		node.rotation.z += dt * 0.3
		if k >= 1: node.queue_free(); smokes.remove_at(i)

func _spawn_z() -> void:
	var z := Label3D.new(); z.text = "Z"; z.font = load("res://assets/fx/AlfaSlabOne-Regular.ttf"); z.font_size = 64
	z.modulate = Color("#f4e8d4"); z.billboard = BaseMaterial3D.BILLBOARD_ENABLED; z.pixel_size = 0.0018; z.outline_size = 0
	z.set_meta("life", 0.0); add_child(z)
	z.global_position = john.head_world() + Vector3(0, 0.15, 0)
	zzz.append(z)

# ------------------------------------------------------------------ camera
func _update_camera(dt: float) -> void:
	var sit: float = john.pose.sit
	var head: Vector3 = john.head_world()
	var jp := john.global_position
	var tgt := Vector3(jp.x, lerp(1.55 + jp.y, head.y, sit), jp.z)
	if sit > 0.01:
		tgt.x = lerp(tgt.x, head.x, sit * 0.6); tgt.z = lerp(tgt.z, head.z, sit * 0.6)
	if state == "title":
		yaw = 0.35 + sin(clock_t * 0.15) * 0.25; pitch = 0.32
	elif (state == "sitting" or state == "busy" or state == "passout") and sit > 0.5 and user_look <= 0:
		yaw = lerp_angle(yaw, 0.0, 1.0 - exp(-dt * 1.2))
	elif state == "walking" and user_look <= 0 and john.pose.walk > 0.3 and fwd_in:
		yaw = lerp_angle(yaw, john.facing + PI, 1.0 - exp(-dt * 1.4))
	if snort_obj != null or bong_active:
		var f: float = john.facing
		var want := atan2(cos(f), -sin(f)) - 0.45 if bong_active else atan2(-cos(f), sin(f)) + 0.35
		yaw = lerp_angle(yaw, want, 1.0 - exp(-dt * 3)); pitch = lerp(pitch, 0.22, 1.0 - exp(-dt * 3))
		tgt = tgt.lerp(head - Vector3(0, 0.12, 0), 0.85)
	var aiming := armed and not gun_hidden and state == "walking" and rmb_down and not peeping
	aim_t = lerp(aim_t, 1.0 if aiming else 0.0, 1.0 - exp(-dt * 12))
	if aim_t > 0.01:
		tgt += Vector3(cos(yaw), 0, -sin(yaw)) * 0.4 * aim_t
		tgt.y = lerp(tgt.y, head.y + 0.12, aim_t)
		if drunk_vis > 0: yaw += sin(clock_t * 1.3) * 0.0025 * drunk_vis; pitch += cos(clock_t * 1.1) * 0.0018 * drunk_vis
	var d := dist
	if state == "passout" or state == "end": d = lerp(dist, 2.2, john.pose.droop)
	elif snort_obj != null or bong_active: d = min(dist, 2.1)
	d = lerp(d, 1.15, aim_t)
	var want_pos := tgt + Vector3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * d
	# keep the camera out of walls
	var q := PhysicsRayQueryParameters3D.create(tgt, want_pos); q.exclude = [john.get_rid()]; q.collision_mask = 1
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	if hit:
		var L := tgt.distance_to(want_pos)
		want_pos = tgt + (want_pos - tgt).normalized() * max(0.35, tgt.distance_to(hit.position) - 0.2)
	if tgt.z > RZ - 0.1:   # bathroom
		want_pos.x = clamp(want_pos.x, 2.05, 5.25); want_pos.z = clamp(want_pos.z, 3.2, 8.15); want_pos.y = clamp(want_pos.y, 0.4, 2.78)
		if want_pos.z < RZ and door_open > 0.5: want_pos.x = clamp(want_pos.x, DOOR_X - 0.45, DOOR_X + 0.45)
	elif jp.z < -RZ - 0.2:  # outside
		want_pos.z = min(want_pos.z, -RZ - 0.5)
	else:
		want_pos = Vector3(clamp(want_pos.x, -6.45, 6.45), clamp(want_pos.y, 0.4, 3.15), clamp(want_pos.z, -4.45, 4.45))
	cam.global_position = cam.global_position.lerp(want_pos, 1.0 - exp(-dt * 6))
	cam_target = cam_target.lerp(tgt, 1.0 - exp(-dt * 8))
	if cam.global_position.distance_to(cam_target) > 0.01:
		cam.look_at(cam_target)
	var b := drunk_vis; var hv := high_vis
	cam.rotation.z += sin(clock_t * 0.9) * 0.09 * b + sin(clock_t * 2.3) * 0.02 * b
	cam.fov = 55 - 14 * aim_t + sin(clock_t * 0.7) * 6 * b + 9 * hv + sin(clock_t * 11) * 0.6 * hv
	if hv > 0: cam.global_position += Vector3((randf() - 0.5) * 0.012 * hv, (randf() - 0.5) * 0.012 * hv, 0)
	if peeping:
		cam.global_position = Vector3(FD_X, 1.58, -RZ - 0.06)
		cam.rotation = Vector3(peep_pitch - 0.05 + sin(clock_t * 0.6) * 0.02 * b, peep_yaw + sin(clock_t * 0.8) * 0.03 * b, 0)
		cam.fov = 112

# ------------------------------------------------------------------ stage 3: visitor + peephole
func visitor_waiting() -> bool: return V.st == "knock"
func visitor_near_door() -> bool: return V.st == "knock" or V.st == "talk"

func visitor_reset() -> void:
	V.st = "off"; V.path = []; V.pi = 0; V.knocks = 0; V.knock_t = 0.0; V.talk = []; V.seen_peep = false; V.said_knock = false
	if visitor: visitor.visible = false; visitor.set_anim("idle")
	game_t = 0.0; peeping = false; peep_vis = 0.0; peep_said = false

func v_say(text: String, secs := 3.0) -> void: hud.say("Visitor", text, secs)

func _vpath(arr: Array) -> Array:
	var out := []
	for p in arr: out.append(Vector3(p[0], 0, p[2]))
	return out

func visitor_start() -> void:
	V.st = "approach"; V.path = _vpath(VisitorPaths.PATH_IN); V.pi = 1
	visitor.global_position = V.path[0]; V.y = _ground(V.path[0]); visitor.visible = true; visitor.set_anim("walk")

func start_talk() -> void:
	V.st = "talk"; V.talk_t = 0.0; V.talk_i = 0; visitor.set_anim("idle")
	var slurred := beers >= 3
	V.talk = [[0.6, "V", "Oh! Good evening. Sorry to knock so late."],
		[3.8, "V", "I'm looking for number 14. My cousin Avi's place?"],
		[7.4, "J", "Thish is forty-one. Fourteen'sh... acrosh the circle." if slurred else "This is 41. Fourteen's right across the circle."],
		[11.0, "V", "Across the circle. Of course, I had it backwards. Thank you!"],
		[14.4, "V", "Enjoy the game. Good night!", "wave"],
		[17.2, "leave"]]

func visitor_leave() -> void:
	V.st = "leave"; V.path = _vpath(VisitorPaths.PATH_OUT); V.pi = 0; visitor.set_anim("walk")

func _ground(p: Vector3) -> float:
	var q := PhysicsRayQueryParameters3D.create(Vector3(p.x, p.y + 2.0, p.z), Vector3(p.x, p.y - 3.0, p.z))
	q.exclude = [john.get_rid()]
	var hit := get_world_3d().direct_space_state.intersect_ray(q)
	return hit.position.y if hit else p.y

func update_visitor(dt: float) -> void:
	if visitor == null: return
	if state != "title" and state != "end": game_t += dt
	if V.st == "off":
		if game_t >= 28 and state != "title" and state != "end" and state != "passout": visitor_start()
		return
	if V.st == "gone": visitor.visible = false; return
	var o := visitor
	var jp := john.global_position
	if V.st == "approach" or V.st == "leave" or V.st == "step":
		if V.pi >= V.path.size():
			if V.st == "approach":
				if front_open > 0.5: start_talk()
				else: V.st = "knock"; V.knock_t = 1.2; visitor.set_anim("idle")
			elif V.st == "step": start_talk()
			else: V.st = "gone"; o.visible = false
		else:
			var tgt: Vector3 = V.path[V.pi]
			var dx := tgt.x - o.global_position.x; var dz := tgt.z - o.global_position.z; var d := Vector2(dx, dz).length()
			var st: float = (0.6 if V.st == "step" else V.spd) * dt
			if d <= st:
				o.global_position.x = tgt.x; o.global_position.z = tgt.z; V.pi += 1
			else:
				o.global_position.x += dx / d * st; o.global_position.z += dz / d * st
			var want := 0.0 if V.st == "step" else atan2(dx, dz)
			o.rotation.y = lerp_angle(o.rotation.y, want, 1.0 - exp(-dt * 8))
	else:
		var close := is_outside() and Vector2(jp.x - o.global_position.x, jp.z - o.global_position.z).length() < 4
		o.rotation.y = lerp_angle(o.rotation.y, atan2(jp.x - o.global_position.x, jp.z - o.global_position.z) if close else 0.0, 1.0 - exp(-dt * 6))
	if V.st == "knock":
		V.knock_t -= dt
		if front_open > 0.45 or (is_outside() and Vector2(jp.x - o.global_position.x, jp.z - o.global_position.z).length() < 3.5):
			V.st = "step"; V.path = [Vector3(VisitorPaths.TALK[0], 0, VisitorPaths.TALK[2])]; V.pi = 0; visitor.set_anim("idle")
		elif V.knock_t <= 0:
			if V.knocks >= 5 or state == "passout":
				v_say("Hello? ...I'll come back another time." if state == "passout" else "Hello? ...Huh. Maybe it's the house across the circle.", 3.6)
				visitor_leave()
			else:
				V.knocks += 1; V.knock_t = 7.5; visitor.set_anim("knock"); Sfx.play("knock")
				get_tree().create_timer(2.1).timeout.connect(func(): if visitor.anim == "knock": visitor.set_anim("idle"))
				if not V.said_knock:
					V.said_knock = true
					get_tree().create_timer(1.5).timeout.connect(func(): say("Who the hell's knocking at this hour?" if state == "sitting" else "Someone's at the front door?", 3.0))
				elif V.knocks == 3:
					get_tree().create_timer(1.5).timeout.connect(func(): say("Somebody really wants in.", 2.4))
	if V.st == "talk":
		V.talk_t += dt
		if V.talk_i < V.talk.size():
			var ln: Array = V.talk[V.talk_i]
			if V.talk_t >= ln[0]:
				V.talk_i += 1
				if ln[1] == "leave": visitor.set_anim("idle"); visitor_leave()
				elif ln[1] == "V": v_say(ln[2], 3.3); visitor.set_anim("wave" if ln.size() > 3 and ln[3] == "wave" else "idle")
				else: say(ln[2], 3.3)
	var gy := _ground(o.global_position)
	V.y = lerp(V.y, gy, 1.0 - exp(-dt * 10)); o.global_position.y = V.y
	visitor.pose(dt)

func toggle_peep(on: bool) -> void:
	if on == peeping: return
	peeping = on
	if on:
		peep_yaw = 0.0; peep_pitch = 0.0; Sfx.play("thunk")
		if not peep_said and V.st != "knock" and V.st != "talk":
			peep_said = true
			get_tree().create_timer(0.7).timeout.connect(func(): if peeping and V.st != "knock": say("Nobody. Just the cul-de-sac.", 2.4))
		if V.st == "knock" and not V.seen_peep:
			V.seen_peep = true
			get_tree().create_timer(0.7).timeout.connect(func(): if peeping: say("Some guy in a hat and a suit. At this hour?", 3.0))

# ------------------------------------------------------------------ stage 4: the Glock
func _build_gun() -> void:
	gun_rig = Node3D.new(); gun_rig.name = "Glock"; add_child(gun_rig)
	var src: Node3D = (load("res://assets/glock/glock.fbx") as PackedScene).instantiate()
	var gm: MeshInstance3D = src.find_children("*", "MeshInstance3D", true, false)[0]
	var mesh := MeshInstance3D.new(); mesh.mesh = gm.mesh
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = load("res://assets/glock/glock_BaseColor.jpg")
	mat.normal_enabled = true; mat.normal_texture = load("res://assets/glock/glock_Normal.jpg")
	mat.roughness_texture = load("res://assets/glock/glock_Roughness.jpg"); mat.roughness = 1.0
	mat.metallic_texture = load("res://assets/glock/glock_Metallic.jpg"); mat.metallic = 1.0
	mesh.material_override = mat
	src.free()
	# model space: barrel along -x, up +z (centimetres) -> rig space: muzzle +z, up +y, metres; grip at the origin
	var M := Basis(Vector3(0, 0, -1), Vector3(-1, 0, 0), Vector3(0, 1, 0))
	var k := 0.187 / 4.7
	var grip: Vector3 = (M * Vector3(1.55, 0.14, -0.9)) * k
	mesh.transform = Transform3D(M.scaled(Vector3.ONE * k / 0.01), -grip)
	gun_muzzle = (M * Vector3(-2.45, 0.14, 0.82)) * k - grip
	gun_rig.add_child(mesh)
	flash_spr = Sprite3D.new(); flash_spr.texture = puff_tex; flash_spr.billboard = BaseMaterial3D.BILLBOARD_ENABLED; flash_spr.shaded = false
	flash_spr.modulate = Color(1, 0.82, 0.47); flash_spr.visible = false; add_child(flash_spr)
	var fm := StandardMaterial3D.new(); fm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; fm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	fm.albedo_texture = puff_tex; fm.albedo_color = Color(1, 0.82, 0.47); fm.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; fm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	flash_spr.material_override = fm
	flash_light = OmniLight3D.new(); flash_light.light_color = Color(1, 0.75, 0.44); flash_light.omni_range = 6; flash_light.light_energy = 0; add_child(flash_light)
	hole_mat = StandardMaterial3D.new(); hole_mat.albedo_color = Color(0.04, 0.03, 0.02, 0.92); hole_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hole_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; hole_mat.albedo_texture = puff_tex

func gun_reset() -> void:
	armed = false; gun_hidden = false; ammo = 15; reload_t = 0; aim_t = 0; aim_hold = 0; rmb_down = false
	_place_gun_on_table()
	for h in holes: if is_instance_valid(h): h.queue_free()
	holes.clear()
	_reset_mirror()
	if tv_dead:
		tv_dead = false; tv_draw.refresh(clock_t, channel, 0.0, 0.0, false)

func _place_gun_on_table() -> void:
	if gun_rig == null: return
	gun_rig.global_transform = Transform3D(Basis(Vector3.RIGHT, 0) * Basis(Vector3.UP, 0.9) * Basis(Vector3.BACK, PI / 2), GUN_HOME)
	gun_rig.visible = true

func near_gun() -> bool: return gun_rig != null and not armed and pos2().distance_to(Vector2(GUN_SPOT.x, GUN_SPOT.y)) < 0.95
func can_take_gun() -> bool: return near_gun() and not (has_beer and near_chair())

func equip_gun() -> void:
	set_state("busy"); hud.prompt("")
	var p := pos2(); var fr: float = john.facing
	var st := {got = false}
	var _fn := func(_k, t):
		_walk_to(p.x, p.y, fr, GUN_SPOT, clamp(t / 0.35, 0.0, 1.0))
		var d := side_dirs()
		john.pose.bend = (0.0 if t < 0.3 else (sm((t - 0.3) / 0.45) if t < 0.75 else 1.0 - sm(clamp((t - 0.75) / 0.5, 0.0, 1.0)))) * 0.35
		john.pose.squat = john.pose.bend * 0.6
		john.snort_ik.w = sm(t / 0.3) if t < 0.3 else (1.0 if t < 0.8 else 1.0 - sm(clamp((t - 0.8) / 0.5, 0.0, 1.0)))
		john.snort_ik.target = GUN_HOME + Vector3(d.rx * 0.03, 0.05, d.rz * 0.03)
		if t > 0.72 and not st.got: st.got = true; armed = true; ammo = 15; Sfx.play("rack")
	var _done := func():
		john.pose.bend = 0.0; john.pose.squat = 0.0; john.snort_ik.w = 0.0; set_state("walking")
		say("Well, hello there. Right-click to aim, left-click to shoot.", 3.4)
	tween(1.5, _fn, _done)

func _aim_query(from: Vector3, to: Vector3) -> Dictionary:
	var q := PhysicsRayQueryParameters3D.create(from, to); q.exclude = [john.get_rid()]
	return get_world_3d().direct_space_state.intersect_ray(q)

func update_aim() -> void:
	var dir := -cam.global_transform.basis.z
	var from := cam.global_position + dir * 0.3
	aim_hit = _aim_query(from, cam.global_position + dir * 40.0)
	aim_point = aim_hit.position if aim_hit else cam.global_position + dir * 30.0

func is_tv(p: Vector3) -> bool: return p.x > TVX - 0.62 and p.x < TVX + 0.62 and p.y > 0.6 and p.y < 1.75 and p.z > TVZ - 0.42 and p.z < TVZ + 0.5

func _is_mirror(collider: Object) -> bool:
	var m: Node = n.get("BathMirror")
	if m == null or collider == null: return false
	var x := collider as Node
	while x:
		if x == m: return true
		x = x.get_parent()
	return false

func fire() -> void:
	if not armed or gun_hidden or state != "walking" or fire_cd > 0 or reload_t > 0 or peeping: return
	if ammo <= 0: reload_t = 1.3; Sfx.play("reload"); return
	ammo -= 1; fire_cd = 0.13; aim_hold = 0.6; Sfx.play("shot")
	update_aim()
	var muzzle: Vector3 = gun_rig.global_transform * gun_muzzle
	flash_spr.global_position = muzzle; flash_spr.visible = true; flash_spr.pixel_size = (0.22 + randf() * 0.1) / 128.0
	flash_spr.rotation.z = randf() * TAU
	flash_light.global_position = muzzle; flash_light.light_energy = 5 * 0.9; flash_time = 0.06
	_tracer(muzzle, aim_point)
	if debug_run: print("[fire] muzzle·aim=", gun_rig.global_transform.basis.z.normalized().dot((aim_point - muzzle).normalized()), " up=", gun_rig.global_transform.basis.y, " hit=", aim_hit.get("collider"), " at ", aim_hit.get("position"))
	pitch = clamp(pitch - 0.03, -0.45, 1.0); yaw += (randf() - 0.5) * 0.012
	if aim_hit:
		var nrm: Vector3 = aim_hit.normal
		if _is_mirror(aim_hit.collider) and not mirror_broken:
			shatter_mirror(aim_hit.position)
		else:
			_hole(aim_hit.position, nrm, aim_hit.collider)
			for i in 7: _spark(aim_hit.position, nrm * (1.5 + randf() * 2) + Vector3((randf() - 0.5) * 2.5, randf() * 2, (randf() - 0.5) * 2.5))
			puff(aim_hit.position + nrm * 0.03, nrm * 0.3, 0.12, 0.9)
			flash_mark = 0.15
		if not tv_dead and is_tv(aim_hit.position): shoot_tv(aim_hit.position)
	if ammo <= 0:
		reload_t = 1.3; Sfx.play("reload", 0.0, 1.0, 0.25)

func _hole(p: Vector3, nrm: Vector3, collider: Object) -> void:
	var h := MeshInstance3D.new(); var qm := QuadMesh.new(); qm.size = Vector2(0.034, 0.034); h.mesh = qm; h.material_override = hole_mat
	var parent: Node3D = self
	if collider is Node3D and (collider as Node3D).get_parent() is Node3D: parent = (collider as Node3D).get_parent()
	parent.add_child(h)
	h.global_position = p + nrm * 0.003
	if abs(nrm.dot(Vector3.UP)) > 0.99: h.look_at(h.global_position - nrm, Vector3.FORWARD)
	else: h.look_at(h.global_position - nrm, Vector3.UP)
	holes.append(h)
	if holes.size() > 80:
		var h0: Node3D = holes.pop_front()
		if is_instance_valid(h0): h0.queue_free()

func _tracer(a: Vector3, b: Vector3) -> void:
	var im := ImmediateMesh.new(); var mi := MeshInstance3D.new(); mi.mesh = im
	var m := StandardMaterial3D.new(); m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED; m.albedo_color = Color(1, 0.94, 0.63, 0.9); m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	im.surface_begin(Mesh.PRIMITIVE_LINES, m); im.surface_add_vertex(a); im.surface_add_vertex(b); im.surface_end()
	add_child(mi); tracers.append({node = mi, mat = m, life = 0.0})

func _spark(p: Vector3, v: Vector3) -> void:
	var s := Sprite3D.new(); s.texture = puff_tex; s.billboard = BaseMaterial3D.BILLBOARD_ENABLED; s.shaded = false
	s.modulate = Color(1, 0.75, 0.35); s.pixel_size = 0.035 / 128.0
	var m := StandardMaterial3D.new(); m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD; m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_texture = puff_tex; m.albedo_color = Color(1, 0.75, 0.35); m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED; m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.vertex_color_use_as_albedo = true
	s.material_override = m
	add_child(s); s.global_position = p
	sparks.append({node = s, v = v, life = 0.0})

func _update_gun(dt: float) -> void:
	fire_cd = max(0.0, fire_cd - dt); aim_hold = max(0.0, aim_hold - dt)
	if reload_t > 0:
		reload_t -= dt
		if reload_t <= 0: reload_t = 0; ammo = 15
	hud.set_ammo(armed, "Reloading" if reload_t > 0 else str(ammo))
	if flash_time > 0:
		flash_time -= dt
		if flash_time <= 0: flash_spr.visible = false; flash_light.light_energy = 0
	for i in range(tracers.size() - 1, -1, -1):
		var t: Dictionary = tracers[i]; t.life += dt; t.mat.albedo_color.a = max(0.0, 0.9 - t.life * 14)
		if t.life > 0.07: t.node.queue_free(); tracers.remove_at(i)
	for i in range(sparks.size() - 1, -1, -1):
		var sp: Dictionary = sparks[i]; sp.life += dt
		var node: Sprite3D = sp.node
		node.global_position += sp.v * dt; sp.v.y -= 9 * dt
		node.modulate.a = max(0.0, 1.0 - sp.life / 0.35)
		if sp.life > 0.35: node.queue_free(); sparks.remove_at(i)
	flash_mark = max(0.0, flash_mark - dt)
	hud.set_aim(aim_t > 0.5 and state == "walking", flash_mark > 0 and aim_t > 0.5)
	# the gun in John's hand, aim IK
	if armed and gun_rig:
		gun_rig.visible = not gun_hidden
		if not gun_hidden:
			gun_rig.global_transform = john.gun_world()
			# keep the Glock upright while aiming: roll the forearm until the slide faces the sky
			if aim_t > 0.05 or aim_hold > 0:
				var f := gun_rig.global_transform.basis.z.normalized(); var u := gun_rig.global_transform.basis.y.normalized()
				var want := (Vector3.UP - f * Vector3.UP.dot(f))
				if want.length_squared() > 1e-4:
					want = want.normalized(); var up := (u - f * u.dot(f)).normalized()
					var ang := atan2(up.cross(want).dot(f), up.dot(want))
					john.gun_twist = clamp(john.gun_twist + ang * 0.6, -3.0, 3.0)
				# and point the barrel at the crosshair (the arm IK gets it close; this closes the gap)
				var gx := gun_rig.global_transform
				var to := aim_point - gx.origin
				if to.length() > 0.3:
					var look := Basis.looking_at(-to.normalized(), Vector3.UP)
					var w2: float = clamp(max(aim_t, 1.0 if aim_hold > 0 else 0.0), 0.0, 1.0) * 0.85
					gun_rig.global_transform = Transform3D(gx.basis.get_rotation_quaternion().slerp(look.get_rotation_quaternion(), w2), gx.origin)
		if state == "walking" and not gun_hidden:
			update_aim()
			if aim_t > 0.3 or aim_hold > 0:
				var w: float = max(aim_t, 1.0 if aim_hold > 0 else 0.0)
				var sh: Vector3 = john.shoulder_world(true)
				var dir := (aim_point - sh).normalized()
				var f: float = john.facing
				john.snort_ik.w = w
				john.snort_ik.target = sh + dir * 0.62 + Vector3(cos(f) * 0.09, 0.2, -sin(f) * 0.09)
				john.left_ik.w = 0.0
			else:
				john.snort_ik.w = lerp(john.snort_ik.w, 0.0, 1.0 - exp(-dt * 10)); john.gun_twist = lerp(john.gun_twist, 0.0, 1.0 - exp(-dt * 10))
				john.left_ik.w = lerp(john.left_ik.w, 0.0, 1.0 - exp(-dt * 10))

func shoot_tv(p: Vector3) -> void:
	tv_dead = true; tv_draw.refresh(clock_t, channel, 0.0, 0.0, true)
	Sfx.play("shatter")
	for i in 40: _spark(p, Vector3((randf() - 0.5) * 4, randf() * 3, 1 + randf() * 3))
	for i in 8: puff(p + Vector3((randf() - 0.5) * 0.3, randf() * 0.2, 0.1), Vector3((randf() - 0.5) * 0.3, 0.4 + randf() * 0.4, 0.2), 0.3 + randf() * 0.2, 2.5)
	var scr := Vector3(TVX - 0.08, 0.98, TVZ + 0.38)
	for z in 8:
		get_tree().create_timer(0.18 * (z + 1)).timeout.connect(func():
			for i in 6: _spark(scr, Vector3((randf() - 0.5) * 2, randf() * 2, 1 + randf()))
			Sfx.play("zap"))
	mission_failed("John shot the TV. Now what's he gonna watch?")

func mission_failed(why: String) -> void:
	set_state("end"); hud.prompt(""); rmb_down = false
	get_tree().create_timer(1.6).timeout.connect(func():
		_capture(false); menu.show_failed(why); Sfx.play("fail"))

# ---- the bathroom mirror
const MIRROR_W := 0.52
const MIRROR_H := 0.74
const MIRROR_CY := 1.62
const MIRROR_CZ := 0.05
var shard_mat: StandardMaterial3D

func shatter_mirror(hit_world: Vector3) -> void:
	var grp: Node3D = n.get("MirrorGroup")
	if grp == null: return
	mirror_broken = true
	if n.has("BathMirror"):
		(n.BathMirror as Node3D).visible = false
		for b in (n.BathMirror as Node).find_children("*", "StaticBody3D", true, false): b.queue_free()
	Sfx.play("shatter"); Sfx.play("shatter", 0.0, 1.1, 0.09)
	if shard_mat == null:
		shard_mat = StandardMaterial3D.new(); shard_mat.albedo_color = Color("#d4dee2"); shard_mat.metallic = 0.85; shard_mat.roughness = 0.06
		shard_mat.emission_enabled = true; shard_mat.emission = Color("#2a3236"); shard_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var W := MIRROR_W; var H := MIRROR_H
	var hit := grp.global_transform.affine_inverse() * hit_world
	var hx: float = clamp(hit.x, -W / 2 + 0.03, W / 2 - 0.03); var hy: float = clamp(hit.y - MIRROR_CY, -H / 2 + 0.03, H / 2 - 0.03)
	var pts := []
	var per := 2 * (W + H)
	for i in 16:
		var t := (i + randf() * 0.6) / 16.0 * per; var x: float; var y: float
		if t < W: x = -W / 2 + t; y = -H / 2
		elif t - W < H: t -= W; x = W / 2; y = -H / 2 + t
		elif t - W - H < W: t -= W + H; x = W / 2 - t; y = H / 2
		else: t -= 2 * W + H; x = -W / 2; y = H / 2 - t
		pts.append(Vector2(x, y))
	for c in [Vector2(-W / 2, -H / 2), Vector2(W / 2, -H / 2), Vector2(W / 2, H / 2), Vector2(-W / 2, H / 2)]: pts.append(c)
	var hp := Vector2(hx, hy)
	pts.sort_custom(func(a, b): return (a - hp).angle() < (b - hp).angle())
	var out: Vector3 = (grp.global_transform.basis * Vector3(0, 0, 1)).normalized()
	for i in pts.size():
		var a: Vector2 = pts[i]; var b: Vector2 = pts[(i + 1) % pts.size()]
		var k := 0.25 + randf() * 0.35
		var am := hp + (a - hp) * k; var bm := hp + (b - hp) * k
		for poly in [[hp, am, bm], [am, a, b, bm]]:
			var c := Vector2.ZERO
			for p in poly: c += p / poly.size()
			var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES); st.set_normal(Vector3(0, 0, 1))
			for j in range(1, poly.size() - 1):
				for v in [poly[0], poly[j], poly[j + 1]]: st.add_vertex(Vector3(v.x - c.x, v.y - c.y, 0))
			var m := MeshInstance3D.new(); m.mesh = st.commit(); m.material_override = shard_mat
			add_child(m)
			m.global_transform = grp.global_transform * Transform3D(Basis(), Vector3(c.x, MIRROR_CY + c.y, MIRROR_CZ))
			var dist := (c - hp).length()
			var stay: bool = poly.size() == 4 and randf() < 0.45 and dist > 0.12
			shards.append({node = m, stay = stay, delay = 1e9 if stay else randf() * 0.35 * dist * 4, rest = false,
				v = out * (0.4 + randf() * 1.1) + Vector3((randf() - 0.5) * 0.6, randf() * 0.6, (randf() - 0.5) * 0.6),
				spin = Vector3((randf() - 0.5) * 14, (randf() - 0.5) * 14, (randf() - 0.5) * 14)})
	for i in 26: _spark(hit_world, Vector3((randf() - 0.5) * 2.5, randf() * 2, (randf() - 0.5) * 2.5))
	say(["Seven years bad luck. Worth it.", "Never liked that guy anyway.", "Ugly son of a gun."].pick_random(), 2.6)

func _update_shards(dt: float) -> void:
	for s in shards:
		if s.stay or s.rest: continue
		if s.delay > 0: s.delay -= dt; continue
		var m: Node3D = s.node
		s.v.y -= 9.8 * dt
		m.global_position += s.v * dt; m.rotation += s.spin * dt
		var p := m.global_position
		p.x = clamp(p.x, 1.98, 5.32); p.z = clamp(p.z, RZ + 0.24, 8.22)
		var fl := 0.8 if (abs(p.x - 5.06) < 0.2 and abs(p.z - 6.05) < 0.24) else 0.006
		if p.y <= fl:
			p.y = fl
			if abs(s.v.y) > 1.2:
				s.v.y *= -0.25; s.v.x *= 0.4; s.v.z *= 0.4; s.spin *= 0.3
			else:
				s.rest = true; m.rotation = Vector3(-PI / 2, 0, randf() * 6); p.y = fl + 0.002
		m.global_position = p

func _reset_mirror() -> void:
	for s in shards: s.node.queue_free()
	shards.clear()
	if mirror_broken:
		mirror_broken = false
		if n.has("BathMirror"):
			(n.BathMirror as Node3D).visible = true
			for mi: MeshInstance3D in (n.BathMirror as Node).find_children("*", "MeshInstance3D", true, false): mi.create_trimesh_collision()
			if n.BathMirror is MeshInstance3D: (n.BathMirror as MeshInstance3D).create_trimesh_collision()

# ------------------------------------------------------------------ test driver
## godot -- --scenario=tour --shots=/tmp/x   walks through the cabin actions and saves frames
var debug_run := false
func _debug_args() -> Dictionary:
	var a := {}
	for s in OS.get_cmdline_user_args():
		if s.begins_with("--") and s.contains("="): a[s.substr(2, s.find("=") - 2)] = s.substr(s.find("=") + 1)
	return a

func _wait_sim(sec: float) -> void:
	var target := clock_t + sec
	while clock_t < target: await get_tree().process_frame

func _shot(prefix: String, name: String) -> void:
	if DisplayServer.get_name() == "headless":
		print("[shot] ", name, " (headless) state=", state); return
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png("%s_%s.png" % [prefix, name])
	print("[shot] ", name, " state=", state, " pos=", john.global_position, " sit=", john.pose.sit)

func _run_scenario(sc: String, prefix: String) -> void:
	debug_run = true
	await _wait_sim(0.5)
	if sc == "visitor":
		start(); await _wait_sim(0.5)
		interact(); await _wait_sim(1.8)
		set_pos2(FD_X, -RZ + 0.9); john.facing = PI; yaw = 0.0
		game_t = 28.0; V.spd = 9.0
		while V.st != "knock": await _wait_sim(0.2)
		await _wait_sim(1.5)
		await _shot(prefix, "1_knock")
		toggle_peep(true); await _wait_sim(0.8)
		await _shot(prefix, "2_peephole")
		interact(); await _wait_sim(4.5)
		await _shot(prefix, "3_talk")
		set_pos2(FD_X + 0.3, -RZ - 2.2); john.facing = 0.0; yaw = PI + 0.4; pitch = 0.25
		await _wait_sim(1.0)
		await _shot(prefix, "4_outside")
		get_tree().quit(); return
	if sc == "gun":
		start(); await _wait_sim(0.5)
		interact(); await _wait_sim(1.8)
		set_pos2(-3.0, 1.2); await _wait_sim(0.2)
		interact(); await _wait_sim(1.8)
		yaw = 0.5; pitch = 0.2; await _wait_sim(0.5)
		await _shot(prefix, "1_armed")
		set_pos2(3.4, -0.6); john.facing = PI / 2; yaw = -PI / 2 + 0.25; pitch = 0.08
		rmb_down = true; await _wait_sim(0.8)
		await _shot(prefix, "2_aim")
		for i in 4: fire(); await _wait_sim(0.25)
		await _wait_sim(0.05)
		await _shot(prefix, "3_fired")
		rmb_down = false
		door_target = 1.0; set_pos2(4.2, 6.05); john.facing = PI / 2; yaw = -PI / 2; pitch = 0.05
		await _wait_sim(1.5)
		rmb_down = true; await _wait_sim(0.8)
		fire(); await _wait_sim(0.2)
		if not mirror_broken and n.has("MirrorGroup"): shatter_mirror((n.MirrorGroup as Node3D).global_transform * Vector3(0.05, 1.62, 0.05))
		await _wait_sim(0.35)
		await _shot(prefix, "4_mirror")
		await _wait_sim(1.5)
		rmb_down = false
		set_pos2(-2.0, -2.2); john.facing = PI; yaw = 0.0; pitch = 0.0
		await _wait_sim(1.0); rmb_down = true; await _wait_sim(0.8)
		fire(); await _wait_sim(0.3)
		if not tv_dead: print("[test] TV missed, aim at ", aim_point); shoot_tv(Vector3(TVX, 1.0, TVZ + 0.38))
		await _wait_sim(0.6)
		await _shot(prefix, "5_tv")
		await _wait_sim(2.0)
		await _shot(prefix, "6_failed")
		get_tree().quit(); return
	if sc == "title":
		await _shot(prefix, "title"); get_tree().quit(); return
	start(); await _wait_sim(1.0)
	await _shot(prefix, "1_sitting")
	interact(); await _wait_sim(1.8)
	set_pos2(4.6, -1.0); await _wait_sim(0.2)
	interact(); await _wait_sim(1.2)
	await _shot(prefix, "2_fridge")
	await _wait_sim(1.3)
	set_pos2(-2.2, 1.3); await _wait_sim(0.2)
	interact(); await _wait_sim(3.6)
	await _shot(prefix, "3_drinking")
	await _wait_sim(3.0)
	interact(); await _wait_sim(1.8)
	set_pos2(3.6, 2.6); await _wait_sim(0.2)
	interact(); await _wait_sim(1.7)
	await _shot(prefix, "4_line")
	await _wait_sim(1.8)
	set_pos2(-5.0, 1.2); await _wait_sim(0.2)
	interact(); await _wait_sim(2.0)
	await _shot(prefix, "5_bong")
	await _wait_sim(3.0)
	trip_t = 30; trip_vis = 1.0; boost_t = 0
	await _wait_sim(0.6)
	await _shot(prefix, "6_trip")
	trip_t = 0; trip_vis = 0; beers = 4; drunk_vis = drunk_level(); hud.set_cans(4)
	Input.action_press("move_forward"); await _wait_sim(1.2); Input.action_release("move_forward")
	await _shot(prefix, "7_drunk_walk")
	get_tree().quit()
