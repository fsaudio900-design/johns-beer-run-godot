extends Node
## Stage 6: the Fuel Stop. Money, Dale the clerk, buying a case of Lumberjack, carrying it,
## the M1's trunk, stocking the fridge, and the robbery (hands up, demand the cash, shoot
## Dale: hit reactions by body part, blood, a physics ragdoll, robbing the till yourself).
## Ported from the web build's BEER / ROB / RAG / BLOOD systems.

const START_CASH := 500.0
const CASE_PRICE := 18.99
const STX := -52.0
const STZ := -42.95
const FLOOR := -0.33
const STORE := Rect2(-59.0, -52.95, 14.0, 10.0)            # x, z, width, depth
const CASE_STACK := Vector2(-57.4, -50.65)
const REGISTER := Vector2(-47.4, -45.7)
const CLERK_POS := Vector3(-47.4, -0.33, -43.9)
const TILL_SPOT := Vector2(-47.8, -43.95)
const WANTED_TIME := 90.0

var g: Node3D                       # the game controller (main.gd)
var cash := START_CASH
# the case of beer
var case_state := "store"           # store | carried | trunk
var carried := false
var paid := false
var case_node: Node3D
var trunk_case: Node3D
var lid_t := 0.0
var lid_open := 0.0
var shout_t := 0.0
var greeted := false
var was_in := false
var door_open := 0.0
var chimed := false
var doors: Array[Node3D] = []
var door_x0: Array[float] = []
var drawer: Node3D
var drawer_cash: Node3D
var drawer_z0 := 0.0
var till_open := 0.0
# Dale
var clerk: Node3D
var clerk_block: StaticBody3D
var rob := {clerk = "idle", till = true, wanted = 0.0, groan_t = 0.0, hits = 0, drip_t = 0.0}
var hit_jolt := 0.0
var spin := 0.0
var kneel := 0.0
var rag := {}
var rag_t := 0.0
# blood + debris
var drops: Array = []
var decals: Array[Node3D] = []
var wounds: Array[Node3D] = []
var pool: Decal
var pool_t := 0.0
var debris: Array[Node3D] = []
var tex_splat: Texture2D = preload("res://assets/fx/blood_splat.png")
var tex_pool: Texture2D = preload("res://assets/fx/blood_pool.png")
var tex_wound: Texture2D = preload("res://assets/fx/wound.png")
var drop_mesh: SphereMesh
var drop_mat: StandardMaterial3D
var wound_mat: StandardMaterial3D

func setup(game: Node3D) -> void:
	g = game
	var n: Dictionary = g.n
	for i in 2:
		var d: Node3D = n.get("StoreDoor%d" % i)
		if d:
			doors.append(d); door_x0.append(d.position.x)
			for b in d.find_children("*", "StaticBody3D", true, false): b.queue_free()   # sliding glass: no collision
	drawer = n.get("TillDrawer"); drawer_cash = n.get("TillCash")
	if drawer: drawer_z0 = drawer.position.z
	case_node = n.get("CarryCase")
	if case_node:
		var gt := case_node.global_transform
		case_node.get_parent().remove_child(case_node); g.add_child(case_node); case_node.global_transform = gt
		for b in case_node.find_children("*", "StaticBody3D", true, false): b.queue_free()
		case_node.visible = false
		# a copy rides in the M1's trunk
		trunk_case = case_node.duplicate(); trunk_case.visible = false
		if g.car and g.car.model:
			g.car.model.add_child(trunk_case); trunk_case.position = Vector3(0, 0.84, -1.35); trunk_case.rotation = Vector3.ZERO
	drop_mesh = SphereMesh.new(); drop_mesh.radius = 0.012; drop_mesh.height = 0.024; drop_mesh.radial_segments = 6; drop_mesh.rings = 4
	drop_mat = StandardMaterial3D.new(); drop_mat.albedo_color = Color(0.42, 0, 0.02); drop_mat.roughness = 0.3
	wound_mat = StandardMaterial3D.new(); wound_mat.albedo_texture = tex_wound; wound_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wound_mat.roughness = 0.3; wound_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_spawn_clerk()

# ------------------------------------------------------------------ helpers
func c_say(t: String, secs := 2.8) -> void: g.hud.say("Clerk", t, secs)
func say(t: String, secs := 2.6) -> void: g.say(t, secs)
func money(v: float) -> String: return "$" + g.hud._money(v)
func pos2() -> Vector2: return g.pos2()
func in_store() -> bool: var p := pos2(); return STORE.has_point(p)
func near_stack() -> bool: return in_store() and pos2().distance_to(CASE_STACK + Vector2(0, 0.6)) < 1.3
func near_register() -> bool: return in_store() and pos2().distance_to(REGISTER) < 1.3
func near_till() -> bool: return in_store() and pos2().distance_to(TILL_SPOT) < 0.95
func hostile() -> bool: return rob.clerk != "idle"
func can_afford(v: float) -> bool: return cash + 1e-9 >= v
func later(t: float, f: Callable) -> void: g.get_tree().create_timer(t).timeout.connect(f)

func add_cash(d: float) -> void:
	cash = round((cash + d) * 100.0) / 100.0
	g.hud.set_cash(cash); g.hud.cash_delta(d)

func trunk_point() -> Vector3: return g.car.to_world(Vector3(0, 0, -2.75)) if g.car else Vector3(1e6, 0, 0)
func near_trunk() -> bool:
	if g.car == null or g.state != "walking" or not g.is_outside(): return false
	var tp = trunk_point(); var jp: Vector3 = g.john.global_position
	return Vector2(tp.x - jp.x, tp.z - jp.z).length() < 1.4

func hold(on: bool) -> void:
	carried = on
	if case_node: case_node.visible = on
	g.gun_hidden = on
	if not on: g.john.snort_ik.w = 0.0; g.john.left_ik.w = 0.0

# ------------------------------------------------------------------ reset
func reset() -> void:
	cash = START_CASH; g.hud.set_cash(cash)
	hold(false); case_state = "store"; paid = false; g.stock = 0; g.show_stock()
	lid_t = 0.0; greeted = false; till_open = 0.0
	if drawer: drawer.position.z = drawer_z0
	if drawer_cash: drawer_cash.visible = true
	rob = {clerk = "idle", till = true, wanted = 0.0, groan_t = 0.0, hits = 0, drip_t = 0.0}
	hit_jolt = 0.0; spin = 0.0; kneel = 0.0
	for d in drops: d.node.queue_free()
	drops.clear()
	for d in decals: if is_instance_valid(d): d.queue_free()
	decals.clear(); wounds.clear()
	for d in debris: if is_instance_valid(d): d.queue_free()
	debris.clear()
	if pool: pool.queue_free(); pool = null
	_spawn_clerk()
	g.hud.set_pill("wanted", 0)

func _spawn_clerk() -> void:
	for b in rag.values(): if is_instance_valid(b): b.queue_free()
	rag.clear()
	for c in g.get_children():
		if c is ConeTwistJoint3D: c.queue_free()
	if clerk: clerk.queue_free()
	clerk = Node3D.new(); clerk.set_script(load("res://scripts/visitor.gd")); clerk.name = "Dale"
	clerk.set("model_path", "res://assets/chars/Clerk.glb")
	g.add_child(clerk); clerk.global_position = CLERK_POS; clerk.rotation.y = PI
	if clerk_block == null:
		clerk_block = StaticBody3D.new(); clerk_block.name = "BehindCounterBlock"; g.add_child(clerk_block)
		var cs := CollisionShape3D.new(); var b := BoxShape3D.new(); b.size = Vector3(4.0, 1.6, 1.3); cs.shape = b; clerk_block.add_child(cs)
		clerk_block.global_position = Vector3(STX + 4.9, FLOOR + 0.8, STZ - 0.85)
	clerk_block.process_mode = Node.PROCESS_MODE_INHERIT
	(clerk_block.get_child(0) as CollisionShape3D).disabled = false

# ------------------------------------------------------------------ interaction (returns true when E was used)
func interact() -> bool:
	if rob.till and rob.clerk == "dead" and near_till(): open_till(); return true
	if near_register() and not (carried and not paid and rob.clerk == "idle"):
		if rob.till and (rob.clerk == "hands" or rob.clerk == "hurt"): demand_cash(); return true
		if rob.till and rob.clerk == "dead": say("Gotta get around behind the counter.", 2.0); return true
	if carried:
		if not paid and near_register(): buy_case(); return true
		if not paid and near_stack(): hold(false); case_state = "store"; Sfx.play("thunk"); return true
		if paid and near_trunk(): trunk_case_move(true); return true
		if paid and not g.is_outside() and g.near_fridge(): stock_fridge(); return true
		if g.near_car(): say("Gotta put the beer in the trunk first.", 2.2); return true
		say("My hands are full." if paid else "Gotta pay for this first.", 1.8); return true
	if case_state == "trunk" and near_trunk(): trunk_case_move(false); return true
	if near_stack(): grab_case(); return true
	if not g.has_beer and g.near_fridge() and g.stock <= 0:
		say(["Empty. Who drank all my beer? ...Oh. Me.", "Nothing but ketchup and regret.", "Bone dry. Time for a beer run."].pick_random(), 2.8)
		return true
	return false

func prompt() -> Array:
	if rob.till and rob.clerk == "dead" and near_till(): return ["Open the register", true]
	if near_register():
		if rob.till and (rob.clerk == "hands" or rob.clerk == "hurt"): return ["Demand the cash", true]
		if rob.till and rob.clerk == "dead": return ["Walk around behind the counter to reach the register", false]
		if not rob.till and rob.clerk != "idle": return ["The register is empty", false]
	if carried:
		if not paid and near_register():
			return [("Buy the case (%s)" % money(CASE_PRICE)) if can_afford(CASE_PRICE) else ("Buy the case (%s). You only have %s" % [money(CASE_PRICE), money(cash)]), true]
		if not paid and near_stack(): return ["Put the case back", true]
		if paid and near_trunk(): return ["Put the case in the trunk", true]
		if paid and not g.is_outside() and g.near_fridge(): return ["Stock the fridge", true]
		if not paid: return ["Pay at the register", false]
		return ["Take the case home, or put it in the trunk" if g.is_outside() else "Put the case in the fridge", false]
	if case_state == "trunk" and near_trunk(): return ["Take the case out of the trunk", true]
	if near_stack(): return ["Grab a case of beer", true]
	if near_register(): return ["Grab a case first", false]
	if not g.has_beer and g.near_fridge() and g.stock <= 0: return ["The fridge is empty", true]
	if in_store(): return ["Fuel Stop Mart · open 24 hours", false]
	return []

func grab_case() -> void:
	hold(true); paid = false; case_state = "carried"; Sfx.play("thunk")
	say(["Hello, gorgeous.", "Twelve of my closest friends.", "That one. That one right there."].pick_random(), 2.4)

func buy_case() -> void:
	g.set_state("busy"); g.hud.prompt("")
	var slur: bool = g.beers >= 3
	c_say("Lumberjack twelve-pack. That's %s." % money(CASE_PRICE), 2.6)
	if not can_afford(CASE_PRICE):
		later(2.5, func(): say(("I got... %s. Close enough?" % money(cash)) if cash > 0 else "...Can I owe you?", 2.4))
		later(4.8, func(): c_say("Sorry, pal. No cash, no beer.", 2.6); g.set_state("walking"))
		return
	var pay := 20.0 if can_afford(20.0) else CASE_PRICE
	later(2.5, func(): say(("Here'sh a twenty. Or a ten. Keep it." if slur else "Here's a twenty. Keep the change.") if pay == 20.0 else "Exact change. Count it.", 2.4))
	later(4.8, func():
		Sfx.play("register"); add_cash(-pay); paid = true
		c_say("Thanks. Maybe walk home tonight, buddy." if slur else "Thanks. Have a good night.", 2.8)
		g.set_state("walking"))

func trunk_case_move(put: bool) -> void:
	g.set_state("busy"); g.hud.prompt(""); lid_t = 1.0; Sfx.play("creak")
	later(0.7, func():
		if put: hold(false); case_state = "trunk"
		else: hold(true); case_state = "carried"; paid = true
		Sfx.play("thunk"))
	later(1.4, func():
		lid_t = 0.0; later(0.4, func(): Sfx.play("thunk"))
		g.set_state("walking")
		if put: say("Safe and sound.", 1.8))

func stock_fridge() -> void:
	g.set_state("busy"); g.hud.prompt("")
	var p: Vector2 = pos2(); var fr: float = g.john.facing
	var st := {opened = false, put = false, closed = false}
	var fn := func(_k, t):
		g._walk_to(p.x, p.y, fr, g.FRIDGE_SPOT, clamp(t / 0.4, 0.0, 1.0))
		var door: float = 0.0 if t < 0.35 else (g.sm((t - 0.35) / 0.45) if t < 0.8 else (1.0 if t < 1.7 else 1.0 - g.sm((t - 1.7) / 0.45)))
		if t > 0.35 and not st.opened: st.opened = true; Sfx.play("fridge")
		g._fridge_door(door)
		if t > 1.0 and not st.put:
			st.put = true; hold(false); case_state = "store"; paid = false; g.stock += 12; g.show_stock(); Sfx.play("thunk")
		if t > 2.1 and not st.closed: st.closed = true; Sfx.play("thunk")
	var done := func():
		g._fridge_door(0.0); g.set_state("walking")
		say("Restocked. Now we're talking." if g.stock > 12 else "Twelve cold ones. That's a full fridge.", 2.6)
	g.tween(2.4, fn, done)

# ------------------------------------------------------------------ robbery
func start_wanted() -> void:
	if rob.wanted <= 0:
		rob.wanted = WANTED_TIME
		later(2.6, func(): say("Better not stick around.", 2.2))

func hands_up() -> void:
	if rob.clerk != "idle": return
	rob.clerk = "hands"; clerk.set_anim("hands")
	c_say(["Whoa, whoa! Easy! Easy!", "Don't shoot! Please!", "Okay! Okay! Whatever you want!"].pick_random(), 2.6)
	later(1.4, func(): if rob.clerk == "hands" and rob.till: say("Empty the register. Now.", 2.2))
	start_wanted()

func demand_cash() -> void:
	g.set_state("busy"); g.hud.prompt("")
	c_say("Here... take it... just go..." if rob.clerk == "hurt" else "Okay, okay! Here, take it all!", 2.4)
	later(1.9, func():
		Sfx.play("register"); add_cash(round(380 + randf() * 340)); rob.till = false
		if drawer_cash: drawer_cash.visible = false
		if rob.clerk == "hands": rob.clerk = "robbed"
		say("Pleashure doing business." if g.beers >= 3 else "Pleasure doing business.", 2.2); g.set_state("walking")
		later(2.4, func(): if rob.clerk != "dead": c_say("The cops are already on their way, you know!", 2.6)))

func open_till() -> void:
	g.set_state("busy"); g.hud.prompt("")
	var p: Vector2 = pos2(); var fr: float = g.john.facing
	var st := {opened = false, took = false}
	var fn := func(_k, t):
		g._walk_to(p.x, p.y, fr, Vector3(TILL_SPOT.x, TILL_SPOT.y, PI), clamp(t / 0.45, 0.0, 1.0))
		if t > 0.45 and not st.opened: st.opened = true; Sfx.play("till_ding")
		till_open = 0.0 if t < 0.45 else min(1.0, (t - 0.45) / 0.25)
		if drawer: drawer.position.z = drawer_z0 + 0.24 * till_open
		var dw: Vector3 = drawer.global_position if drawer else Vector3(TILL_SPOT.x, 0.85, TILL_SPOT.y - 0.9)
		g.john.snort_ik.w = 0.0 if t < 0.7 else (g.sm((t - 0.7) / 0.3) if t < 1.0 else (1.0 if t < 1.9 else 1.0 - g.sm((t - 1.9) / 0.5)))
		g.john.snort_ik.target = dw + Vector3(0, 0.06 + (0.08 if (t > 1.3 and t < 1.9) else 0.0), 0.02)
		if t > 1.35 and not st.took:
			st.took = true; Sfx.play("register"); add_cash(round(380 + randf() * 340)); rob.till = false
			if drawer_cash: drawer_cash.visible = false
	var done := func():
		g.john.snort_ik.w = 0.0; g.set_state("walking")
		say(["Don't mind if I do.", "Thanks, Dale.", "Payday."].pick_random(), 2.2)
	g.tween(2.6, fn, done)

## hit test against Dale's current pose (head sphere, torso capsule, arms, legs)
func clerk_ray_hit(from: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	if clerk == null or rob.clerk == "dead": return {}
	var J: Dictionary = clerk.J
	if not J.has("head"): return {}
	var head: Vector3 = (J.head as Node3D).global_transform * Vector3(0, 0.1, 0.01)
	var hip: Vector3 = (J.hips as Node3D).global_transform * Vector3(0, 0.05, 0)
	var neck: Vector3 = (J.neck as Node3D).global_position
	var r := _seg(from, dir, head, head)
	if r.d < 0.12 and r.t < max_d: return {zone = "head", t = r.t, part = "head"}
	r = _seg(from, dir, hip, neck)
	if r.d < 0.2 and r.t < max_d: return {zone = "body", t = r.t, part = "torso"}
	for s in ["L", "R"]:
		r = _seg(from, dir, (J["sh" + s] as Node3D).global_position, (J["wr" + s] as Node3D).global_position)
		if r.d < 0.07 and r.t < max_d: return {zone = "arm", t = r.t, part = "arm" + s, side = s}
		r = _seg(from, dir, (J["thigh" + s] as Node3D).global_position, (J["ankle" + s] as Node3D).global_position)
		if r.d < 0.08 and r.t < max_d: return {zone = "leg", t = r.t, part = "thigh" + s, side = s}
	return {}

func _seg(ro: Vector3, rd: Vector3, a: Vector3, b: Vector3) -> Dictionary:
	var best := INF; var bt := 0.0
	for i in 11:
		var q := a.lerp(b, i / 10.0)
		var t := (q - ro).dot(rd)
		if t < 0.15: continue
		var d := (ro + rd * t).distance_to(q)
		if d < best: best = d; bt = t
	return {d = best, t = bt}

## called by fire(): returns true when the bullet hit Dale (then no bullet hole is made)
func on_shot(from: Vector3, dir: Vector3, hit: Dictionary) -> bool:
	var point_d: float = from.distance_to(hit.position) if hit else 30.0
	# the ragdoll is a physics body now: shooting it bleeds and shoves it
	if hit and hit.collider is RigidBody3D and String(hit.collider.name).begins_with("Rag_"):
		(hit.collider as RigidBody3D).apply_impulse(dir * 18.0, hit.position - hit.collider.global_position)
		spray(hit.position, dir, 10, 1.2); return true
	var ch := clerk_ray_hit(from, dir, point_d)
	if not ch.is_empty():
		shoot_clerk(ch, from + dir * (ch.t - 0.05), dir); return true
	if in_store():
		if hit: _knock_products(hit.position, hit.normal, dir)
		if rob.clerk == "idle": hands_up()
		start_wanted()
	return false

func shoot_clerk(h: Dictionary, p: Vector3, dir: Vector3) -> void:
	Sfx.play("hurt")
	spray(p, dir, 26 if h.zone == "head" else 16, 2.4); spray(p, -dir, 6, 0.8)
	_wound(h.part, p, dir)
	# exit splatter on whatever is behind him
	var q = PhysicsRayQueryParameters3D.create(p, p + dir * 4.0); q.exclude = [g.john.get_rid()]
	var back = g.get_world_3d().direct_space_state.intersect_ray(q)
	if back: splat(back.position, back.normal, 0.9 if h.zone == "head" else 0.55)
	start_wanted()
	if h.zone == "head":
		rob.clerk = "dead"; _go_ragdoll("head", dir * 7.0); return
	rob.hits += 1
	if rob.hits >= 3:
		rob.clerk = "dead"; c_say("...", 0.8); _go_ragdoll(h.part, dir * 6.0); return
	rob.clerk = "hurt"; clerk.set_anim("hands"); hit_jolt = 1.0; rob.groan_t = 4.0
	match h.zone:
		"arm": spin += (0.9 if h.side == "L" else -0.9)          # a shoulder hit spins him
		"leg": kneel = 1.0                                       # a leg hit drops him to a knee
	c_say("AGH! You shot me! Okay, okay, take it!" if rob.hits == 1 else "Please! Please stop! Take the money!", 2.8)

func _go_ragdoll(part: String, impulse: Vector3) -> void:
	(clerk_block.get_child(0) as CollisionShape3D).disabled = true      # John can step behind the counter now
	rag = Ragdoll.build(g, clerk.J, part, impulse)
	clerk.set_process(false); clerk.visible = true
	rag_t = 0.0; pool_t = 0.0
	later(0.6, func(): Sfx.play("thud"))

func _wound(part: String, p: Vector3, dir: Vector3) -> void:
	# stick the wound on a mesh of the part that was hit so it follows him (and the ragdoll)
	var jn := {head = "head", torso = "spine", armL = "shL", armR = "shR", thighL = "thighL", thighR = "thighR"}.get(part, "spine")
	var j: Node3D = clerk.J.get(jn)
	var host: Node3D = j
	if j:
		for c in j.get_children():
			if c is MeshInstance3D: host = c; break
	if host == null: return
	for k in 2:
		var m := MeshInstance3D.new(); var qm := QuadMesh.new()
		qm.size = Vector2(0.04, 0.04) if k == 0 else Vector2(0.14, 0.18)
		m.mesh = qm
		if k == 0: m.material_override = wound_mat
		else:
			var sm := StandardMaterial3D.new(); sm.albedo_texture = tex_splat; sm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA; sm.roughness = 0.25; m.material_override = sm
		host.add_child(m)
		m.global_position = p - dir * (0.006 + k * 0.002)
		m.look_at(m.global_position - dir, Vector3.UP if abs(dir.dot(Vector3.UP)) < 0.95 else Vector3.FORWARD)
		m.rotate_object_local(Vector3(0, 0, 1), randf() * TAU)
		wounds.append(m)

# ------------------------------------------------------------------ blood
func spray(p: Vector3, dir: Vector3, n: int, speed: float) -> void:
	for i in n:
		var m := MeshInstance3D.new(); m.mesh = drop_mesh; m.material_override = drop_mat
		m.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		g.add_child(m); m.global_position = p; m.scale = Vector3.ONE * (0.6 + randf() * 1.4)
		var v := Vector3((randf() - 0.5) * 1.6, randf() * 1.4, (randf() - 0.5) * 1.6) + dir * speed * (0.4 + randf())
		drops.append({node = m, v = v, life = 0.0})

func splat(p: Vector3, nrm: Vector3, size: float) -> void:
	var d := Decal.new(); d.texture_albedo = tex_splat; d.size = Vector3(size, 0.12, size)
	d.cull_mask = 1; d.upper_fade = 0.0; d.lower_fade = 0.0
	g.add_child(d)
	var y := nrm.normalized(); var x := y.cross(Vector3.FORWARD if abs(y.dot(Vector3.FORWARD)) < 0.9 else Vector3.RIGHT).normalized()
	d.global_transform = Transform3D(Basis(x, y, x.cross(y)).rotated(y, randf() * TAU), p + y * 0.02)
	decals.append(d)
	if decals.size() > 60:
		var d0: Node3D = decals.pop_front()
		if is_instance_valid(d0): d0.queue_free()

func _floor_at(p: Vector3) -> float:
	if Rect2(STORE.position - Vector2(1, 1), STORE.size + Vector2(2, 2)).has_point(Vector2(p.x, p.z)): return FLOOR
	return -0.45

func _update_blood(dt: float) -> void:
	for i in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[i]; d.life += dt
		var m: MeshInstance3D = d.node
		d.v.y -= 9.8 * dt; m.global_position += d.v * dt
		var fl := _floor_at(m.global_position)
		if m.global_position.y <= fl + 0.01 or d.life > 2.5:
			if m.global_position.y <= fl + 0.02 and randf() < 0.45:
				splat(Vector3(m.global_position.x, fl, m.global_position.z), Vector3.UP, 0.05 + randf() * 0.1)
			m.queue_free(); drops.remove_at(i)
	if pool:
		pool_t += dt
		var s: float = min(1.0, pool_t / 9.0)
		var sz := 0.05 + 1.3 * sqrt(s)
		pool.size = Vector3(sz, 0.3, sz)

# ------------------------------------------------------------------ products knocked off the shelves
const PRODUCT_COLORS := [Color("#d8261d"), Color("#f6c400"), Color("#1d6fd8"), Color("#2fa84f"), Color("#e8e2d0"), Color("#7a3fb0"), Color("#ff7a1a")]
func _knock_products(p: Vector3, nrm: Vector3, dir: Vector3) -> void:
	if p.y < FLOOR + 0.25 or p.y > FLOOR + 2.3: return
	var n := 2 + randi() % 3
	for i in n:
		var b := RigidBody3D.new(); b.collision_layer = 1 << 2; b.collision_mask = 1 | (1 << 2)
		b.mass = 0.3; b.linear_damp = 0.2; b.angular_damp = 0.4
		var mi := MeshInstance3D.new(); var cs := CollisionShape3D.new()
		var mat := StandardMaterial3D.new(); mat.albedo_color = PRODUCT_COLORS.pick_random(); mat.roughness = 0.45
		if randf() < 0.5:
			var cm := CylinderMesh.new(); cm.top_radius = 0.032; cm.bottom_radius = 0.035; cm.height = 0.2 + randf() * 0.08
			mi.mesh = cm; var sh := CylinderShape3D.new(); sh.radius = 0.034; sh.height = cm.height; cs.shape = sh
			mat.metallic = 0.3
		else:
			var bm := BoxMesh.new(); bm.size = Vector3(0.16 + randf() * 0.06, 0.22 + randf() * 0.06, 0.05 + randf() * 0.04)
			mi.mesh = bm; var sh := BoxShape3D.new(); sh.size = bm.size; cs.shape = sh
		mi.material_override = mat; b.add_child(mi); b.add_child(cs)
		g.add_child(b)
		b.global_position = p + nrm * (0.12 + randf() * 0.1) + Vector3((randf() - 0.5) * 0.3, (randf() - 0.5) * 0.2, (randf() - 0.5) * 0.3)
		b.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		b.linear_velocity = (nrm * (1.0 + randf() * 2.0) + dir * (1.0 + randf() * 1.5) + Vector3(0, 1.2 + randf(), 0))
		b.angular_velocity = Vector3(randf() - 0.5, randf() - 0.5, randf() - 0.5) * 14.0
		debris.append(b)
	Sfx.play_var("clink", 3)
	while debris.size() > 60:
		var d0: Node3D = debris.pop_front()
		if is_instance_valid(d0): d0.queue_free()

# ------------------------------------------------------------------ frame
func update(dt: float) -> void:
	var john: CharacterBody3D = g.john
	var jp := john.global_position
	# the case rides in front of John's belly, both hands on the ends
	if carried and case_node:
		var f: float = john.facing
		var fx := sin(f); var fz := cos(f); var rx := -cos(f); var rz := sin(f)
		case_node.visible = g.state != "driving"
		case_node.global_transform = Transform3D(Basis(Vector3.UP, f), Vector3(jp.x + fx * 0.46, jp.y + 1.02, jp.z + fz * 0.46))
		var c := case_node.global_position
		john.snort_ik.w = 1.0; john.left_ik.w = 1.0
		john.snort_ik.target = Vector3(c.x + rx * 0.21, c.y + 0.02, c.z + rz * 0.21)
		john.left_ik.target = Vector3(c.x - rx * 0.21, c.y + 0.02, c.z - rz * 0.21)
	# an unpaid case can't leave the store
	shout_t = max(0.0, shout_t - dt)
	if carried and not paid and hostile(): paid = true     # nobody's stopping him now
	if carried and not paid and in_store() and jp.z > STZ - 1.15 and abs(jp.x - STX) < 1.3:
		john.global_position.z = STZ - 1.15
		if shout_t <= 0: shout_t = 3.0; c_say("Hey! You gotta pay for that first, pal.", 2.4)
	# Dale greets John and keeps an eye on him
	var inside := in_store()
	if inside and not was_in and hostile() and rob.clerk != "dead": c_say("You again?! Just take what you want and go!", 2.6)
	if inside and not was_in and not hostile() and not greeted:
		greeted = true
		c_say("Evening. ...Rough night, huh?" if g.beers >= 3 else "Evening. Beer's in the back.", 2.6)
		clerk.set_anim("wave"); later(1.8, func(): if rob.clerk == "idle": clerk.set_anim("idle"))
	if not inside and was_in: greeted = false
	was_in = inside
	if clerk and rag.is_empty():
		var want = atan2(jp.x - clerk.global_position.x, jp.z - clerk.global_position.z) if inside else PI
		var dd := wrapf(want - PI, -PI, PI)
		spin = lerp(spin, 0.0, 1.0 - exp(-dt * 1.5))
		clerk.rotation.y = lerp_angle(clerk.rotation.y, PI + clamp(dd, -1.2, 1.2) + spin, 1.0 - exp(-dt * 4))
		clerk.pose(dt)
		# wounded: hunched, bleeding, flinching from each hit; a leg hit puts him on one knee
		hit_jolt = max(0.0, hit_jolt - dt * 2.5)
		if rob.clerk == "hurt":
			var J: Dictionary = clerk.J
			J.spine.rotation.x += 0.32 + 0.25 * hit_jolt; J.head.rotation.x += 0.2
			clerk.global_position.y = CLERK_POS.y - 0.04 * hit_jolt - 0.32 * kneel
			if kneel > 0:
				J.thighL.rotation.x = -1.5 * kneel; J.kneeL.rotation.x = 1.55 * kneel
				J.thighR.rotation.x = -0.2 * kneel; J.kneeR.rotation.x = 1.6 * kneel
			rob.drip_t -= dt
			if rob.drip_t < 0 and wounds.size() > 0:
				rob.drip_t = 0.35 + randf() * 0.5
				var w: Node3D = wounds.pick_random()
				if is_instance_valid(w): spray(w.global_position, Vector3.DOWN, 1, 0.2)
			if inside:
				rob.groan_t -= dt
				if rob.groan_t < 0: rob.groan_t = 6 + randf() * 5; c_say(["Ugh...", "Somebody call 911...", "Ow. Ow. Ow."].pick_random(), 2.0)
	# aiming at Dale (or near him) makes him put his hands up
	if g.armed and not g.gun_hidden and g.aim_t > 0.5 and inside and rob.clerk == "idle":
		var cam: Camera3D = g.cam
		var dir := -cam.global_transform.basis.z
		var J: Dictionary = clerk.J
		var r = _seg(cam.global_position, dir, (J.hips as Node3D).global_position, (J.head as Node3D).global_transform * Vector3(0, 0.1, 0))
		if r.d < 0.6: hands_up()
	# ragdoll settles -> a pool spreads under him
	if not rag.is_empty():
		rag_t += dt
		if pool == null and rag_t > 2.0 and rag.has("torso"):
			var c: Vector3 = (rag.torso as Node3D).global_position
			pool = Decal.new(); pool.texture_albedo = tex_pool; pool.size = Vector3(0.05, 0.3, 0.05); g.add_child(pool)
			pool.global_position = Vector3(c.x, FLOOR + 0.05, c.z); pool_t = 0.0
			spray(c, Vector3.UP, 4, 1.0)
	_update_blood(dt)
	if drawer and rob.clerk != "dead": drawer.position.z = drawer_z0 + 0.24 * till_open
	# sliding doors + chime
	var dp := Vector2(STX, STZ)
	var near = pos2().distance_to(dp) < 3.2 and g.state != "driving"
	door_open = lerp(door_open, 1.0 if near else 0.0, 1.0 - exp(-dt * (6.0 if near else 3.0)))
	if near and door_open < 0.05 and not chimed: chimed = true; Sfx.play("chime")
	if not near and door_open < 0.05: chimed = false
	for i in doors.size():
		var s := -1.0 if i == 0 else 1.0
		doors[i].position.x = s * (0.425 + door_open * 0.78)
	# trunk lid
	if g.car and g.car.lid:
		lid_open = lerp(lid_open, lid_t, 1.0 - exp(-dt * 7))
		g.car.lid.rotation.x = lid_open * 1.05
	if trunk_case: trunk_case.visible = case_state == "trunk" and lid_open > 0.08
	# wanted: the police are on their way (the cruisers arrive in stage 7)
	if rob.wanted > 0 and g.state != "end" and g.state != "title":
		rob.wanted = max(0.0, rob.wanted - dt)
		g.hud.set_pill("wanted", rob.wanted)
		Sfx.set_loop("siren_loop", clamp(1.0 - rob.wanted / 60.0, 0.0, 1.0), dt, 2.0)
		if rob.wanted <= 0:
			say(["Think I lost 'em.", "Nobody saw nothing.", "Home free."].pick_random(), 2.6)
	else:
		g.hud.set_pill("wanted", 0)
		Sfx.set_loop("siren_loop", 0.0, dt, 2.0)
