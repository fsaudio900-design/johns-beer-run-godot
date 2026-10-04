extends Node
## Stage 7: the Pine Hollow police force.
## - Navigation meshes are baked from the world at startup: a wide one for cruisers (they keep
##   clear of houses and poles) and a narrow one for officers on foot.
## - When John is Wanted, all three cruisers light up and path to him. If they lose sight of him
##   they drive to where he was last seen and search the area, sweeping their spotlights.
## - Near John, an officer gets out and chases him on foot (into the Fuel Stop, round houses);
##   lose him and the officer searches too. Caught = Busted.
## - Every cruiser carries its own 3D siren, so you hear where they are and they doppler past.

const CAR_LAYER := 1          # navigation layer bits
const FOOT_LAYER := 2
const OFFICER_CHASE := 3.0    # m/s (John walks 2.1, runs 2.8, wired 4.0)
const OFFICER_SEARCH := 1.7
const SEE_DIST_FOOT := 38.0
const SEE_DIST_CAR := 60.0
const LOST_AFTER := 3.0       # seconds out of sight before they switch to searching
const BAKE_AABB := AABB(Vector3(-140, -3, -62), Vector3(165, 14, 80))
const STATION := [Vector3(-121.0, 0, -16.0), Vector3(-112.5, 0, -16.0)]
const OUT_C := Vector2(0.9, -26.0)
const ARRESTS := ["Hands where I can see 'em, John!", "Pine Hollow PD! On the ground!", "Don't move! You're under arrest!"]

var g: Node3D
var nav_car: NavigationRegion3D
var nav_foot: NavigationRegion3D
var nav_ready := 0
var cars: Array = []
var officers: Array = []
var patrol: Array[Vector3] = []
var last_known := Vector3.ZERO
var seen_t := 99.0
var search_pt := Vector3.ZERO
var search_t := 0.0
var arrest := {}
var hide_t := 0.0
var warned := false
var box_t := 0.0
var flash_t := 0.0
var spotted := false

func setup(game: Node3D) -> void:
	g = game
	_build_patrol()
	_bake_navigation()
	for i in 3: cars.append(_make_cruiser(i))
	reset()

# ------------------------------------------------------------------ navigation
func _bake_navigation() -> void:
	g.world.add_to_group("nav_source")
	nav_car = _region("NavCars", 1.25, 1.5, 0.3, 30.0, CAR_LAYER)
	nav_foot = _region("NavFoot", 0.3, 1.8, 0.36, 40.0, FOOT_LAYER)

func _region(name: String, radius: float, height: float, climb: float, slope: float, layer: int) -> NavigationRegion3D:
	var nm := NavigationMesh.new()
	nm.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nm.geometry_collision_mask = 1
	nm.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_GROUPS_WITH_CHILDREN
	nm.geometry_source_group_name = "nav_source"
	nm.agent_radius = radius; nm.agent_height = height; nm.agent_max_climb = climb; nm.agent_max_slope = slope
	nm.cell_size = 0.25; nm.cell_height = 0.25
	nm.filter_baking_aabb = BAKE_AABB
	nm.region_min_size = 4.0
	var r := NavigationRegion3D.new(); r.name = name; r.navigation_mesh = nm; r.navigation_layers = 1 << (layer - 1)
	g.add_child(r)
	r.bake_finished.connect(func():
		nav_ready += 1
		print("[police] %s baked: %d polygons" % [name, nm.get_polygon_count()]))
	r.bake_navigation_mesh(true)
	return r

func _closest(p: Vector3, layer: int) -> Vector3:
	var map = g.get_world_3d().navigation_map
	return NavigationServer3D.map_get_closest_point(map, p) if nav_ready >= 2 else p

func _path(from: Vector3, to: Vector3, layer: int) -> PackedVector3Array:
	if nav_ready < 2: return PackedVector3Array([from, to])
	return NavigationServer3D.map_get_path(g.get_world_3d().navigation_map, from, to, true, 1 << (layer - 1))

# ------------------------------------------------------------------ cruisers
func _build_patrol() -> void:
	for x in range(-134, -11, 8): patrol.append(Vector3(x, 0, OUT_C.y))
	for i in 20:
		var a := PI - i / 20.0 * TAU
		patrol.append(Vector3(OUT_C.x + cos(a) * 7, 0, OUT_C.y + sin(a) * 7))
	for x in range(-12, -135, -8): patrol.append(Vector3(x, 0, OUT_C.y))

func _make_cruiser(i: int) -> Dictionary:
	var body := CharacterBody3D.new(); body.name = "Cruiser%d" % i
	body.motion_mode = CharacterBody3D.MOTION_MODE_FLOATING
	var cs := CollisionShape3D.new(); var box := BoxShape3D.new(); box.size = Vector3(1.95, 0.95, 4.8)
	cs.shape = box; cs.position = Vector3(0, 0.8, 0); body.add_child(cs)
	g.add_child(body)
	var model: Node3D
	if ResourceLoader.exists("res://assets/chars/Cruiser.glb"):
		model = (load("res://assets/chars/Cruiser.glb") as PackedScene).instantiate()
	else:
		model = Node3D.new()
	body.add_child(model)
	var wheels := []
	var bar_mats: Array[StandardMaterial3D] = []
	for n in model.find_children("*", "", true, false):
		var nm := String(n.name)
		if nm.begins_with("Wheel"): wheels.append({piv = n, front = nm.ends_with("F")})
		if nm.begins_with("LightBar"):
			for mi: MeshInstance3D in ([n] if n is MeshInstance3D else n.find_children("*", "MeshInstance3D", true, false)):
				var m := StandardMaterial3D.new(); var src: Material = mi.get_active_material(0)
				if src is StandardMaterial3D: m.albedo_texture = (src as StandardMaterial3D).albedo_texture; m.emission_texture = m.albedo_texture
				m.emission_enabled = true; m.roughness = 0.3; mi.material_override = m; bar_mats.append(m)
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false): mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	var red := OmniLight3D.new(); red.light_color = Color(1, 0.12, 0.12); red.omni_range = 16; red.light_energy = 0; red.position = Vector3(0.42, 1.7, -0.12)
	var blue := OmniLight3D.new(); blue.light_color = Color(0.2, 0.4, 1); blue.omni_range = 16; blue.light_energy = 0; blue.position = Vector3(-0.42, 1.7, -0.12)
	body.add_child(red); body.add_child(blue)
	var heads: Array[SpotLight3D] = []
	for s in [-1.0, 1.0]:
		var h := SpotLight3D.new(); h.light_color = Color(1, 0.95, 0.85); h.light_energy = 0; h.spot_range = 30; h.spot_angle = 24
		h.position = Vector3(s * 0.65, 0.7, 2.3); body.add_child(h); h.look_at_from_position(h.position, Vector3(s * 0.9, 0, 12), Vector3.UP); heads.append(h)
	var search := SpotLight3D.new(); search.light_color = Color(1, 0.97, 0.9); search.light_energy = 0; search.spot_range = 40; search.spot_angle = 9
	search.shadow_enabled = true; search.position = Vector3(0.75, 1.65, 0.9); body.add_child(search)
	var siren := AudioStreamPlayer3D.new(); siren.stream = _siren_stream(); siren.unit_size = 9.0; siren.max_distance = 160.0
	siren.doppler_tracking = AudioStreamPlayer3D.DOPPLER_TRACKING_PHYSICS_STEP; siren.volume_db = 2.0; siren.position = Vector3(0, 1.6, 0)
	body.add_child(siren)
	var home := {pos = STATION[i] if i < 2 else Vector3(-60, 0, OUT_C.y - 1.8), h = 0.0 if i < 2 else PI / 2, mode = "parked" if i < 2 else "patrol"}
	return {body = body, model = model, wheels = wheels, bar = bar_mats, red = red, blue = blue, heads = heads, search = search, siren = siren,
		home = home, mode = "parked", h = 0.0, v = 0.0, steer = 0.0, path = PackedVector3Array(), pi = 0, replan = 0.0, stuck = 0.0, rev = 0.0, rev_dir = 1.0,
		goal = Vector3.ZERO, pi_patrol = 0, officer = null, sweep = 0.0, y = -0.45}

func _siren_stream() -> AudioStream:
	var s: AudioStream = load("res://assets/sfx/siren_loop.wav")
	if s is AudioStreamWAV:
		s = s.duplicate(); s.loop_mode = AudioStreamWAV.LOOP_FORWARD; s.loop_end = int(s.get_length() * s.mix_rate)
	return s

func reset() -> void:
	for o in officers: if is_instance_valid(o.node): o.node.queue_free()
	officers.clear(); arrest = {}; hide_t = 0; warned = false; box_t = 0; seen_t = 99.0; spotted = false; last_known = Vector3.ZERO
	for c in cars:
		var hm: Dictionary = c.home
		c.body.global_position = hm.pos + Vector3(0, -0.45, 0); c.h = hm.h; c.v = 0.0; c.steer = 0.0; c.mode = hm.mode; c.officer = null
		c.path = PackedVector3Array(); c.pi = 0; c.y = -0.45
		if c.mode == "patrol":
			var best := 0; var bd := INF
			for k in patrol.size():
				var d := Vector2(patrol[k].x - hm.pos.x, patrol[k].z - hm.pos.z).length()
				if d < bd: bd = d; best = k
			c.pi_patrol = best
		c.body.rotation = Vector3(0, c.h, 0)
		c.siren.stop()

func wanted() -> bool: return g.store and g.store.rob.wanted > 0 and g.state != "end" and g.state != "title"

## where they should go for John: if he is inside the cabin, they come to the porch
func john_target() -> Vector3:
	var p: Vector3 = g.john.global_position
	if p.z > -g.RZ - 0.2 and p.z < 8.5 and abs(p.x) < 7: return Vector3(g.FD_X, -0.45, -9.8)
	return p

func _sees(from: Vector3, max_d: float) -> bool:
	var jp: Vector3 = g.john.global_position + Vector3(0, 1.2, 0)
	if from.distance_to(jp) > max_d: return false
	var ex = [g.john.get_rid()]
	if g.car: ex.append(g.car.get_rid())
	for c in cars: ex.append(c.body.get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, jp); q.exclude = ex; q.collision_mask = 1
	return g.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

# ------------------------------------------------------------------ driving
func _drive(c: Dictionary, dt: float) -> void:
	var body: CharacterBody3D = c.body
	var p := body.global_position
	var goal = null; var vmax := 0.0
	match c.mode:
		"patrol":
			goal = patrol[c.pi_patrol]; vmax = 8.5
			if Vector2(goal.x - p.x, goal.z - p.z).length() < 4.5: c.pi_patrol = (c.pi_patrol + 1) % patrol.size()
		"pursue", "search", "return":
			var target: Vector3
			if c.mode == "pursue": target = john_target() if seen_t < LOST_AFTER else last_known
			elif c.mode == "search": target = search_pt
			else: target = c.home.pos
			c.replan -= dt
			if c.replan <= 0 or c.path.is_empty():
				c.replan = 1.0; c.path = _path(p, target, CAR_LAYER); c.pi = 1 if c.path.size() > 1 else 0
			while c.pi < c.path.size() - 1 and Vector2(c.path[c.pi].x - p.x, c.path[c.pi].z - p.z).length() < 3.5: c.pi += 1
			goal = c.path[c.pi] if c.pi < c.path.size() else target
			var d_end := Vector2(target.x - p.x, target.z - p.z).length()
			vmax = 17.0 if c.mode == "pursue" else (9.0 if c.mode == "search" else 9.0)
			if d_end < 14: vmax = max(2.0, d_end * 1.1)
			if c.mode == "return" and d_end < 2.0: c.mode = "parked"; c.v = 0.0
			if c.mode == "search" and d_end < 4.0: vmax = 0.0
			if c.mode == "pursue" and c.officer != null: vmax = 0.0       # parked while the officer is out
	if c.mode == "parked":
		c.v = lerp(c.v, 0.0, 1.0 - exp(-dt * 4)); c.h = lerp_angle(c.h, c.home.h, 1.0 - exp(-dt * 1.5))
	elif goal != null:
		var want := atan2(goal.x - p.x, goal.z - p.z)
		if c.rev > 0:
			c.rev -= dt; c.steer = lerp(c.steer, -c.rev_dir * 0.55, 1.0 - exp(-dt * 6)); c.v = max(c.v - 12 * dt, -5.0)
		else:
			var diff = wrapf(want - c.h, -PI, PI)
			c.steer = lerp(c.steer, clamp(diff * 1.9, -0.62, 0.62), 1.0 - exp(-dt * 6))
			var vt = vmax * (1.0 - min(0.75, abs(diff) / 1.3))
			c.v += clamp(vt - c.v, -14 * dt, 7.5 * dt)
			if vmax > 3 and abs(c.v) < 1.2:
				c.stuck += dt
				if c.stuck > 1.3: c.rev = 1.1; c.rev_dir = sign(diff) if diff != 0 else 1.0; c.stuck = 0.0
			else: c.stuck = 0.0
	var yaw_rate: float = c.v * tan(c.steer) / 2.8
	c.h += yaw_rate * dt
	body.rotation = Vector3(0, c.h, 0)
	body.velocity = Vector3(sin(c.h), 0, cos(c.h)) * c.v
	if abs(c.v) > 0.01:
		body.move_and_slide()
		if body.get_slide_collision_count() > 0: c.v *= 0.6
	# ride height
	var q := PhysicsRayQueryParameters3D.create(body.global_position + Vector3(0, 1.5, 0), body.global_position + Vector3(0, -4, 0)); q.exclude = [body.get_rid()]
	var hit = g.get_world_3d().direct_space_state.intersect_ray(q)
	if hit: c.y = lerp(c.y, hit.position.y - 0.01, 1.0 - exp(-dt * 12))
	body.global_position.y = c.y
	c.model.rotation = Vector3(0, 0, -yaw_rate * 0.015 * min(1.0, abs(c.v) / 10.0))
	for w in c.wheels:
		w.piv.rotation.y = c.steer if w.front else 0.0
		w.piv.rotate_object_local(Vector3.RIGHT, c.v * dt / 0.35)

# ------------------------------------------------------------------ officers on foot
func _deploy(c: Dictionary) -> void:
	var o := Node3D.new(); o.set_script(load("res://scripts/visitor.gd")); o.name = "Officer"
	o.set("model_path", "res://assets/chars/Officer.glb")
	o.set("skin_path", "res://assets/chars/Police.glb")
	g.add_child(o)
	var side = c.body.global_transform * Vector3(1.4, 0, 0.3)
	o.global_position = _closest(side, FOOT_LAYER); o.rotation.y = c.h
	o.set_anim("walk")
	var rec := {node = o, car = c, path = PackedVector3Array(), pi = 0, replan = 0.0, mode = "chase", y = side.y, said = false}
	c.officer = rec; officers.append(rec)
	g.hud.say("Officer", ["Pine Hollow PD! Stop right there!", "Freeze, John!", "Hold it!"].pick_random(), 2.4)
	Sfx.play("thunk")

func _walk_officer(o: Dictionary, dt: float) -> void:
	var node: Node3D = o.node
	var p = node.global_position
	var target: Vector3; var speed := OFFICER_CHASE
	match o.mode:
		"chase": target = g.john.global_position if seen_t < LOST_AFTER else last_known
		"search": target = search_pt; speed = OFFICER_SEARCH
		_: target = o.car.body.global_transform * Vector3(1.4, 0, 0.3); speed = 2.2
	if seen_t >= LOST_AFTER and o.mode == "chase" and p.distance_to(last_known) < 1.5: o.mode = "search"
	if seen_t < LOST_AFTER and o.mode == "search": o.mode = "chase"
	o.replan -= dt
	if o.replan <= 0 or o.path.is_empty():
		o.replan = 0.5; o.path = _path(p, target, FOOT_LAYER); o.pi = 1 if o.path.size() > 1 else 0
	while o.pi < o.path.size() - 1 and Vector2(o.path[o.pi].x - p.x, o.path[o.pi].z - p.z).length() < 0.4: o.pi += 1
	var nxt: Vector3 = o.path[o.pi] if o.pi < o.path.size() else target
	var to := Vector2(nxt.x - p.x, nxt.z - p.z)
	var moving = to.length() > 0.15 and not (o.mode == "search" and Vector2(target.x - p.x, target.z - p.z).length() < 0.8)
	if moving:
		var step: float = min(to.length(), speed * dt)
		var d = to.normalized() * step
		node.global_position += Vector3(d.x, 0, d.y)
		node.rotation.y = lerp_angle(node.rotation.y, atan2(to.x, to.y), 1.0 - exp(-dt * 10))
	node.set_anim("walk" if moving else "idle")
	node.t += dt * (speed / 1.25 - 1.0) if moving else 0.0     # faster gait when running
	# ground
	var q := PhysicsRayQueryParameters3D.create(node.global_position + Vector3(0, 1.2, 0), node.global_position + Vector3(0, -2, 0)); q.exclude = [g.john.get_rid()]
	var hit = g.get_world_3d().direct_space_state.intersect_ray(q)
	if hit: o.y = lerp(o.y, hit.position.y, 1.0 - exp(-dt * 12))
	node.global_position.y = o.y
	node.pose(dt)
	# John holed up somewhere they can't reach (the cabin with the door shut)
	if o.mode == "chase" and not o.path.is_empty():
		var end: Vector3 = o.path[o.path.size() - 1]
		var gap := Vector2(end.x - g.john.global_position.x, end.z - g.john.global_position.z).length()
		if p.distance_to(end) < 1.2 and gap > 2.0:
			hide_t += dt
			if not warned: warned = true; g.hud.say("Officer", "Pine Hollow PD! Come out with your hands up!", 3.0)
			if hide_t > 6.0: _arrest(o.car, o)
	if o.mode == "chase" and Vector2(p.x - g.john.global_position.x, p.z - g.john.global_position.z).length() < 1.1 and g.state != "driving":
		_arrest(o.car, o)

# ------------------------------------------------------------------ arrest
func _arrest(c: Dictionary, o) -> void:
	if not arrest.is_empty() or g.state == "end": return
	if g.state == "driving": g.car.v = 0.0; g.exit_car()
	g.set_state("busy"); g.hud.prompt(""); g.rmb_down = false
	var off: Node3D
	if o != null: off = o.node
	else:
		_deploy(c); off = c.officer.node
	var jp: Vector3 = g.john.global_position; var f: float = g.john.facing
	off.global_position = Vector3(jp.x - sin(f) * 1.3, jp.y, jp.z - cos(f) * 1.3)
	off.rotation.y = atan2(jp.x - off.global_position.x, jp.z - off.global_position.z)
	off.set_anim("idle")
	arrest = {t = 0.0, said = false}
	g.hud.say("Officer", ARRESTS.pick_random(), 2.6)

func _busted() -> void:
	for c in cars: c.siren.stop()
	g.mission_failed("The cops caught John in Pine Hollow. Should've gone home.", "BUSTED")

# ------------------------------------------------------------------ frame
func update(dt: float) -> void:
	if g.state == "title": return
	flash_t += dt
	var W := wanted()
	var jp: Vector3 = g.john.global_position
	# who can see John?
	var see := false
	if W:
		for c in cars:
			if c.mode == "pursue" or c.mode == "search":
				if _sees(c.body.global_position + Vector3(0, 1.4, 0), SEE_DIST_CAR if g.state == "driving" else SEE_DIST_FOOT): see = true
		for o in officers:
			if _sees((o.node as Node3D).global_position + Vector3(0, 1.6, 0), SEE_DIST_FOOT): see = true
	if see:
		seen_t = 0.0; last_known = john_target()
		g.store.rob.wanted = min(g.store.WANTED_TIME, g.store.rob.wanted + dt)     # the clock only runs while they've lost him
	else: seen_t += dt
	spotted = W and seen_t < LOST_AFTER
	g.hud.set_pill_title("wanted", "SPOTTED" if spotted else ("SEARCHING" if W and seen_t < 90 and last_known != Vector3.ZERO else "WANTED"))
	# searching: pick points around where he was last seen
	if W and seen_t >= LOST_AFTER:
		search_t -= dt
		if search_t <= 0:
			search_t = 7.0
			var a := randf() * TAU; var r := 4.0 + randf() * 10.0
			search_pt = _closest(last_known + Vector3(cos(a) * r, 0, sin(a) * r), FOOT_LAYER)
	# dispatch / recall
	for c in cars:
		if W and (c.mode == "parked" or c.mode == "patrol" or c.mode == "return"):
			c.mode = "pursue"; c.path = PackedVector3Array(); c.siren.play()
			if last_known == Vector3.ZERO: last_known = Vector3(g.store.STX, -0.45, g.store.STZ + 4.0); seen_t = LOST_AFTER   # the crime scene
		if W and c.mode == "pursue" and seen_t > LOST_AFTER + 6 and c.officer == null: c.mode = "search"; c.path = PackedVector3Array()
		if W and c.mode == "search" and seen_t < LOST_AFTER: c.mode = "pursue"; c.path = PackedVector3Array()
		if not W and (c.mode == "pursue" or c.mode == "search") and c.officer == null:
			c.mode = "return" if c.home.mode == "parked" else "patrol"; c.path = PackedVector3Array(); c.siren.stop()
	if not W:
		for o in officers: o.mode = "return"
	# officers out of cars
	if W and arrest.is_empty() and g.state != "driving":
		for c in cars:
			if c.mode == "pursue" and c.officer == null and abs(c.v) < 3.0 and c.body.global_position.distance_to(last_known) < 16.0: _deploy(c)
	# move everyone
	if arrest.is_empty():
		for c in cars: _drive(c, g.get_physics_process_delta_time() if false else dt)
		for i in range(officers.size() - 1, -1, -1):
			var o: Dictionary = officers[i]
			_walk_officer(o, dt)
			if o.mode == "return" and (o.node as Node3D).global_position.distance_to(o.car.body.global_transform * Vector3(1.4, 0, 0.3)) < 1.0:
				o.car.officer = null; o.node.queue_free(); officers.remove_at(i)
	# boxed in while driving
	var near_d := INF; var near_c = null
	for c in cars:
		var d := Vector2(c.body.global_position.x - jp.x, c.body.global_position.z - jp.z).length()
		if d < near_d: near_d = d; near_c = c
	if W and arrest.is_empty() and g.state == "driving" and near_c != null:
		box_t = box_t + dt if (abs(g.car.v) < 2.2 and near_d < 4.8) else 0.0
		if box_t > 1.6: _arrest(near_c, null)
	# lights, spotlights and sirens
	var flash := int(flash_t * 6) % 2 == 0
	for c in cars:
		var on: bool = c.mode == "pursue" or c.mode == "search" or (not arrest.is_empty())
		c.red.light_energy = (3.2 if flash else 0.3) if on else 0.0
		c.blue.light_energy = (0.3 if flash else 3.2) if on else 0.0
		for m in c.bar:
			m.emission = Color(1, 0.19, 0.19) if flash else Color(0.19, 0.38, 1)
			m.emission_energy_multiplier = 1.6 if on else 0.0
		for h in c.heads: h.light_energy = 0.0 if c.mode == "parked" else 5.0
		# the spotlight sweeps the yards while searching, and fixes on John when they've got him
		var sl: SpotLight3D = c.search
		if c.mode == "search" or (c.mode == "pursue" and c.officer != null):
			sl.light_energy = 12.0
			var aim: Vector3
			if spotted: aim = jp + Vector3(0, 1.0, 0)
			else:
				c.sweep += dt * 0.7
				aim = c.body.global_position + Vector3(cos(c.sweep) * 14, 0, sin(c.sweep) * 14)
			if sl.global_position.distance_to(aim) > 0.5: sl.look_at(aim, Vector3.UP)
		else: sl.light_energy = 0.0
		if not on and c.siren.playing: c.siren.stop()
	# the arrest plays out
	if not arrest.is_empty():
		arrest.t += dt
		for o in officers: (o.node as Node3D).call("pose", dt)
		if arrest.t > 1.2 and not arrest.said:
			arrest.said = true; g.say("Aw, c'mon... I wash only had a few..." if g.beers >= 3 else "Aw, come on...", 2.2)
		if arrest.t > 3.4: arrest = {}; _busted()
