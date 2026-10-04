extends Node
## Stage 7: the Pine Hollow police force.
## - Navigation meshes are baked from the world at startup: a wide one for cruisers (they keep
##   clear of houses and poles) and a narrow one for officers on foot.
## - When John is Wanted, all three cruisers light up and path to him. If they lose sight of him
##   they drive to where he was last seen and search the area, sweeping their spotlights.
## - Near John, an officer gets out and chases him on foot (into the Fuel Stop, round houses);
##   lose him and the officer searches too. Caught = Busted.
## - Every cruiser carries its own 3D siren, so you hear where they are and they doppler past.
## - Arrest: the officer draws, John puts his hands up, the officer walks round and cuffs him.
##   Until the cuffs click John can press E to resist: he pulls his gun and it's a shootout.
## - Shootout: officers keep their distance, take cover behind range and fire; John has health,
##   officers can be wounded or killed (ragdoll), a cruiser without its officer can't make arrests.

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
var hostile := false        # John resisted / shot at them: officers shoot on sight
var dead: Array = []        # fallen officers {node, holder, t, pooled}
const ARREST_CUFF := 4.5    # cuffs click: too late to resist

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
		goal = Vector3.ZERO, pi_patrol = 0, officer = null, sweep = 0.0, y = -0.45, crew = 1}

func _siren_stream() -> AudioStream:
	var s: AudioStream = load("res://assets/sfx/siren_loop.wav")
	if s is AudioStreamWAV:
		s = s.duplicate(); s.loop_mode = AudioStreamWAV.LOOP_FORWARD; s.loop_end = int(s.get_length() * s.mix_rate)
	return s

func reset() -> void:
	for o in officers:
		if is_instance_valid(o.node): o.node.queue_free()
		if is_instance_valid(o.gun): o.gun.queue_free()
	for d in dead:
		if is_instance_valid(d.node): d.node.queue_free()
		if is_instance_valid(d.holder): d.holder.queue_free()
	dead.clear(); hostile = false
	officers.clear(); arrest = {}; hide_t = 0; warned = false; box_t = 0; seen_t = 99.0; spotted = false; last_known = Vector3.ZERO
	for c in cars:
		var hm: Dictionary = c.home
		c.body.global_position = hm.pos + Vector3(0, -0.45, 0); c.h = hm.h; c.v = 0.0; c.steer = 0.0; c.mode = hm.mode; c.officer = null
		c.path = PackedVector3Array(); c.pi = 0; c.y = -0.45; c.crew = 1
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
	# nobody behind the wheel: the officer is out on foot (or down) -> the cruiser stays where it stopped
	if c.officer != null or c.crew <= 0:
		c.rev = 0.0; c.stuck = 0.0; c.steer = lerp(c.steer, 0.0, 1.0 - exp(-dt * 4))
		c.v = move_toward(c.v, 0.0, 22.0 * dt)
		goal = null
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
	var gun: Node3D = g.gun_rig.duplicate() if g.gun_rig else Node3D.new()
	gun.visible = false; g.add_child(gun)
	var rec := {node = o, car = c, path = PackedVector3Array(), pi = 0, replan = 0.0, mode = "fight" if hostile else "chase", y = side.y, said = false,
		hp = 100.0, gun = gun, fire_cd = 1.5, shots = 0}
	c.officer = rec; officers.append(rec)
	if hostile: g.hud.say("Officer", ["Drop the weapon, John!", "Shots fired, I need backup!", "Put it down! Now!"].pick_random(), 2.4)
	else: g.hud.say("Officer", ["Pine Hollow PD! Stop right there!", "Freeze, John!", "Hold it!"].pick_random(), 2.4)
	Sfx.play("thunk")

func _walk_officer(o: Dictionary, dt: float) -> void:
	if o.mode == "fight": _fight_officer(o, dt); return
	var node: Node3D = o.node
	node.aiming = false
	var p = node.global_position
	var target: Vector3; var speed := OFFICER_CHASE
	match o.mode:
		"chase": target = g.john.global_position if seen_t < LOST_AFTER else last_known
		"search": target = search_pt; speed = OFFICER_SEARCH
		_: target = o.car.body.global_transform * Vector3(1.4, 0, 0.3); speed = 2.2
	if seen_t >= LOST_AFTER and o.mode == "chase" and p.distance_to(last_known) < 1.5: o.mode = "search"
	if seen_t < LOST_AFTER and o.mode == "search": o.mode = "chase"
	var moving := _step(o, target, speed, dt)
	node.set_anim("walk" if moving else "idle")
	_ground(o, dt)
	node.pose(dt)
	_update_officer_gun(o)
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

## walk an officer along a nav path toward target; returns true while moving
func _step(o: Dictionary, target: Vector3, speed: float, dt: float, face_move := true) -> bool:
	var node: Node3D = o.node
	var p = node.global_position
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
		if face_move: node.rotation.y = lerp_angle(node.rotation.y, atan2(to.x, to.y), 1.0 - exp(-dt * 10))
	node.t += dt * (speed / 1.25 - 1.0) if moving else 0.0     # faster gait when running
	return moving

func _ground(o: Dictionary, dt: float) -> void:
	var node: Node3D = o.node
	var q := PhysicsRayQueryParameters3D.create(node.global_position + Vector3(0, 1.2, 0), node.global_position + Vector3(0, -2, 0)); q.exclude = [g.john.get_rid()]
	var hit = g.get_world_3d().direct_space_state.intersect_ray(q)
	if hit: o.y = lerp(o.y, hit.position.y, 1.0 - exp(-dt * 12))
	node.global_position.y = o.y

# ------------------------------------------------------------------ arrest
func _arrest(c: Dictionary, o) -> void:
	if not arrest.is_empty() or g.state == "end" or g.hp <= 0: return
	if o == null and c.crew <= 0: return                 # nobody left in that cruiser to make the arrest
	if g.state == "driving": g.car.v = 0.0; g.exit_car()
	g.set_state("busy"); g.hud.prompt(""); g.rmb_down = false
	var rec: Dictionary
	if o == null and c.officer != null: o = c.officer       # that cruiser's officer is already out on foot
	if o != null: rec = o
	else:
		_deploy(c); rec = c.officer
	var off: Node3D = rec.node
	var jp: Vector3 = g.john.global_position
	var away := Vector3(off.global_position.x - jp.x, 0, off.global_position.z - jp.z)
	if away.length() < 0.3 or away.length() > 9.0:
		var f: float = g.john.facing; away = Vector3(sin(f), 0, cos(f))
	away = away.normalized()
	var stand := jp + away * 2.4
	if nav_ready >= 2: stand = _closest(stand, FOOT_LAYER)
	stand.y = jp.y
	var had_gun_out: bool = g.gun_out()
	if g.armed: g.holstered = true                        # hands up: the gun goes away
	g.john.snort_ik.w = 0.0; g.john.left_ik.w = 0.0
	arrest = {t = 0.0, o = rec, from = off.global_position, stand = stand, said = false, cuffed = false, can = g.armed,
		a0 = atan2(away.x, away.z), had_out = had_gun_out}
	g.hud.say("Officer", ("Drop it! Drop the gun, John! Hands up!" if had_gun_out else ARRESTS.pick_random()), 2.8)

func can_resist() -> bool:
	return not arrest.is_empty() and arrest.can and not arrest.cuffed and arrest.t > 0.3 and g.state == "busy"

## E during the arrest: John spins, pulls the Glock, and it's on
func resist() -> void:
	var rec: Dictionary = arrest.o
	arrest = {}
	g.hud.prompt("")
	var off: Node3D = rec.node
	var jp: Vector3 = g.john.global_position
	var f := atan2(off.global_position.x - jp.x, off.global_position.z - jp.z)
	g.john.facing = f; g.yaw = f - PI
	g.john.left_ik.w = 0.0; g.john.pose.bend = 0.0
	g.holstered = false; g.gun_hidden = false; g.aim_hold = 1.2
	g.set_state("walking")
	Sfx.play("rack")
	g.say(["Not tonight, officer!", "I don't think so!", "You'll never take me alive! ...Probably."].pick_random(), 2.2)
	_go_hostile()
	off.flinch = 0.8; rec.fire_cd = 1.3                    # a beat of surprise: John gets the first shot

func _go_hostile() -> void:
	if not hostile:
		g.hud.say("Officer", ["He's got a gun! Shots fired!", "Gun! Gun! Shots fired!", "Drop it, John! Drop it now!"].pick_random(), 2.6)
	hostile = true
	if g.store: g.store.rob.wanted = g.store.WANTED_TIME
	for o in officers: o.mode = "fight"

# ------------------------------------------------------------------ shootout
func _fight_officer(o: Dictionary, dt: float) -> void:
	var node: Node3D = o.node
	var p: Vector3 = node.global_position
	var jp: Vector3 = g.john.global_position
	if g.state == "driving" and g.car: jp = g.car.global_position
	var flat := Vector2(jp.x - p.x, jp.z - p.z)
	var dist := flat.length()
	var los := _sees(p + Vector3(0, 1.6, 0), 45.0) if g.state != "driving" else _sees_car(p + Vector3(0, 1.6, 0))
	var moving := false
	if not los or dist > 15.0:
		moving = _step(o, jp if los else last_known, OFFICER_CHASE, dt, not los)
	elif dist < 3.2:
		moving = _step(o, p - Vector3(flat.x, 0, flat.y).normalized() * 2.5, 1.8, dt, false)     # back off, keep the gun on him
	else:
		o.path = PackedVector3Array()
	node.set_anim("walk" if moving else "idle")
	node.aiming = los and dist < 26.0
	if node.aiming:
		node.rotation.y = lerp_angle(node.rotation.y, atan2(flat.x, flat.y), 1.0 - exp(-dt * 12))
		var dy: float = (jp.y + (1.0 if g.state == "driving" else 1.25)) - (p.y + 1.42)
		node.aim_pitch = atan2(dy, max(dist, 0.5))
	_ground(o, dt)
	node.pose(dt)
	_update_officer_gun(o)
	o.fire_cd -= dt
	if node.aiming and node.aim_w > 0.8 and o.fire_cd <= 0 and g.hp > 0 and g.state != "end": _officer_fire(o)

func _sees_car(from: Vector3) -> bool:
	if g.car == null: return false
	var cp: Vector3 = g.car.global_position + Vector3(0, 1.0, 0)
	if from.distance_to(cp) > 45.0: return false
	var ex = [g.john.get_rid(), g.car.get_rid()]
	for c in cars: ex.append(c.body.get_rid())
	var q := PhysicsRayQueryParameters3D.create(from, cp); q.exclude = ex; q.collision_mask = 1
	return g.get_world_3d().direct_space_state.intersect_ray(q).is_empty()

func _update_officer_gun(o: Dictionary) -> void:
	var node: Node3D = o.node
	# the pistol is placed once the skinned body has been posed this frame (its real hand bone)
	if node.skin and not node.skin.after_update.is_valid():
		node.skin.after_update = func(): _place_officer_gun(o)
	if node.skin == null: _place_officer_gun(o)

func _place_officer_gun(o: Dictionary) -> void:
	if not is_instance_valid(o.gun) or not is_instance_valid(o.node): return
	var gun: Node3D = o.gun
	var node: Node3D = o.node
	gun.visible = node.aim_w > 0.35
	if not gun.visible: return
	var dir: Vector3 = node.aim_dir()
	var palm: Vector3
	if node.skin:
		var hand: Vector3 = node.skin.bone_world("RightHand"); var mid: Vector3 = node.skin.bone_world("RightHandMiddle1")
		var idx: Vector3 = node.skin.bone_world("RightHandIndex1"); var pk: Vector3 = node.skin.bone_world("RightHandPinky1")
		palm = hand.lerp((mid + idx + pk) / 3.0, 0.55)
	else:
		palm = (node.J.wrR as Node3D).global_position + dir * 0.05
	# grip in the palm, barrel along the aim, slide up
	gun.global_transform = Transform3D(Basis.looking_at(-dir, Vector3.UP), palm + Vector3(0, -0.035, 0) - dir * 0.01)

func _officer_fire(o: Dictionary) -> void:
	var gun: Node3D = o.gun
	var muzzle: Vector3 = gun.global_transform * g.gun_muzzle
	var driving: bool = g.state == "driving"
	var target: Vector3 = (g.car.global_position + Vector3(0, 1.0, 0)) if driving else (g.john.global_position + Vector3(0, 1.2, 0))
	var dist := muzzle.distance_to(target)
	o.shots += 1
	o.fire_cd = 0.5 + randf() * 0.75
	if o.shots % 8 == 0: o.fire_cd += 1.8                       # reload
	Sfx.play("shot", clamp(-1.0 - dist * 0.35, -22.0, -1.0), 0.9 + randf() * 0.12)
	g.flash_spr.global_position = muzzle; g.flash_spr.visible = true; g.flash_spr.pixel_size = 0.2 / 128.0
	g.flash_light.global_position = muzzle; g.flash_light.light_energy = 4.0; g.flash_time = 0.06
	var chance: float = clamp(0.62 - dist * 0.03, 0.12, 0.55)
	if Vector2(g.john.velocity.x, g.john.velocity.z).length() > 2.2: chance *= 0.65
	if driving: chance *= 0.45
	if g.aim_t > 0.5: chance *= 0.9
	var dir := (target - muzzle).normalized()
	if randf() < chance:
		g._tracer(muzzle, target)
		g.john_hit(8.0 + randf() * 6.0 if not driving else 6.0 + randf() * 4.0, dir)
		return
	# a miss: past him into whatever is behind
	var side := dir.cross(Vector3.UP).normalized()
	var miss := target + side * (0.45 + randf() * 0.8) * (1 if randf() < 0.5 else -1) + Vector3(0, (randf() - 0.4) * 0.9, 0)
	var mdir := (miss - muzzle).normalized()
	var q := PhysicsRayQueryParameters3D.create(muzzle, muzzle + mdir * 60.0); q.exclude = [g.john.get_rid()]
	var hit := g.get_world_3d().direct_space_state.intersect_ray(q)
	var end: Vector3 = hit.position if hit else muzzle + mdir * 60.0
	g._tracer(muzzle, end)
	if hit:
		var nrm: Vector3 = hit.normal
		g._hole(hit.position, nrm, hit.collider)
		for i in 4: g._spark(hit.position, nrm * (1.5 + randf() * 2) + Vector3((randf() - 0.5) * 2.5, randf() * 2, (randf() - 0.5) * 2.5))
		if g.car and hit.collider == g.car: Sfx.play("clink1", -4.0, 0.6)

## John's bullet: did it hit an officer? (called before the store gets the shot)
func on_shot(from: Vector3, dir: Vector3, hit: Dictionary) -> bool:
	var max_d: float = from.distance_to(hit.position) if hit else 40.0
	var best := {}; var bo = null
	for o in officers:
		var h := _ray_officer(o, from, dir, max_d)
		if not h.is_empty() and (best.is_empty() or h.t < best.t): best = h; bo = o
	if bo == null:
		# gunfire near the police starts it too
		if wanted() and not hostile:
			for o in officers:
				if (o.node as Node3D).global_position.distance_to(g.john.global_position) < 30.0: _go_hostile(); break
		return false
	if g.debug_run: print("[police] John hit an officer: ", best.zone, " hp ", bo.hp)
	_hurt_officer(bo, best, from + dir * (best.t - 0.04), dir)
	return true

func _ray_officer(o: Dictionary, from: Vector3, dir: Vector3, max_d: float) -> Dictionary:
	var J: Dictionary = (o.node as Node3D).J
	var S = g.store
	var head: Vector3 = (J.head as Node3D).global_transform * Vector3(0, 0.1, 0.01)
	var hip: Vector3 = (J.hips as Node3D).global_transform * Vector3(0, 0.05, 0)
	var neck: Vector3 = (J.neck as Node3D).global_position
	var r: Dictionary = S._seg(from, dir, head, head)
	if r.d < 0.13 and r.t < max_d: return {zone = "head", t = r.t, part = "head"}
	r = S._seg(from, dir, hip, neck)
	if r.d < 0.24 and r.t < max_d: return {zone = "body", t = r.t, part = "torso"}
	for sd in ["L", "R"]:
		r = S._seg(from, dir, (J["sh" + sd] as Node3D).global_position, (J["wr" + sd] as Node3D).global_position)
		if r.d < 0.08 and r.t < max_d: return {zone = "arm", t = r.t, part = "arm" + sd}
		r = S._seg(from, dir, (J["thigh" + sd] as Node3D).global_position, (J["ankle" + sd] as Node3D).global_position)
		if r.d < 0.1 and r.t < max_d: return {zone = "leg", t = r.t, part = "thigh" + sd}
	return {}

func _hurt_officer(o: Dictionary, h: Dictionary, p: Vector3, dir: Vector3) -> void:
	Sfx.play("hurt", -1.0, 0.75 + randf() * 0.1)
	var S = g.store
	S.spray(p, dir, 22 if h.zone == "head" else 14, 2.4); S.spray(p, -dir, 5, 0.8)
	var q := PhysicsRayQueryParameters3D.create(p, p + dir * 4.0); q.exclude = [g.john.get_rid()]
	var back := g.get_world_3d().direct_space_state.intersect_ray(q)
	if back: S.splat(back.position, back.normal, 0.8 if h.zone == "head" else 0.5)
	o.hp -= {head = 100.0, body = 55.0, arm = 30.0, leg = 35.0}.get(h.zone, 40.0)
	_go_hostile()
	if o.hp <= 0:
		_kill_officer(o, h.part, dir * (7.0 if h.zone == "head" else 6.0))
	else:
		(o.node as Node3D).flinch = 1.0; o.fire_cd = max(o.fire_cd, 0.6)
		g.hud.say("Officer", ["Agh! I'm hit!", "Officer hit! Need backup!", "Son of a-- drop it, John!"].pick_random(), 2.2)

func _kill_officer(o: Dictionary, part: String, impulse: Vector3) -> void:
	var node: Node3D = o.node
	var holder := Node3D.new(); holder.name = "FallenOfficer"; g.add_child(holder)
	var bodies := Ragdoll.build(holder, node.J, part, impulse)
	if node.skin: node.skin.follow_ragdoll(bodies); node.skin.after_update = Callable()
	if is_instance_valid(o.gun): o.gun.queue_free()
	officers.erase(o)
	o.car.officer = null; o.car.crew -= 1
	dead.append({node = node, holder = holder, t = 0.0, pooled = false, bodies = bodies})
	g.get_tree().create_timer(0.6).timeout.connect(func(): Sfx.play("thud"))
	g.hud.say("Officer" if officers.size() > 0 else "John", "Officer down! Officer down!" if officers.size() > 0 else "Oh, that's... that's really bad.", 2.4)

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
		if c.crew <= 0:
			if c.siren.playing: c.siren.stop()
			continue
		if W and (c.mode == "parked" or c.mode == "patrol" or c.mode == "return"):
			c.mode = "pursue"; c.path = PackedVector3Array(); c.siren.play()
			if last_known == Vector3.ZERO: last_known = Vector3(g.store.STX, -0.45, g.store.STZ + 4.0); seen_t = LOST_AFTER   # the crime scene
		if W and c.mode == "pursue" and seen_t > LOST_AFTER + 6 and c.officer == null: c.mode = "search"; c.path = PackedVector3Array()
		if W and c.mode == "search" and seen_t < LOST_AFTER: c.mode = "pursue"; c.path = PackedVector3Array()
		if not W and (c.mode == "pursue" or c.mode == "search") and c.officer == null:
			c.mode = "return" if c.home.mode == "parked" else "patrol"; c.path = PackedVector3Array(); c.siren.stop()
	if not W:
		for o in officers: o.mode = "return"
		hostile = false
	# officers out of cars
	if W and arrest.is_empty() and g.state != "driving":
		for c in cars:
			if c.mode == "pursue" and c.officer == null and c.crew > 0 and abs(c.v) < 3.0 and c.body.global_position.distance_to(last_known) < 16.0: _deploy(c)
	# move everyone
	if arrest.is_empty():
		for c in cars: _drive(c, g.get_physics_process_delta_time() if false else dt)
		for i in range(officers.size() - 1, -1, -1):
			var o: Dictionary = officers[i]
			_walk_officer(o, dt)
			if o.mode == "return" and (o.node as Node3D).global_position.distance_to(o.car.body.global_transform * Vector3(1.4, 0, 0.3)) < 1.0:
				o.car.officer = null; o.node.queue_free(); officers.remove_at(i)
				if is_instance_valid(o.gun): o.gun.queue_free()
	# boxed in while driving
	var near_d := INF; var near_c = null
	for c in cars:
		var d := Vector2(c.body.global_position.x - jp.x, c.body.global_position.z - jp.z).length()
		if d < near_d: near_d = d; near_c = c
	if W and arrest.is_empty() and g.state == "driving" and near_c != null and near_c.crew > 0:
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
	# fallen officers: a pool spreads under them
	for d in dead:
		d.t += dt
		if not d.pooled and d.t > 2.0 and d.bodies.has("torso") and is_instance_valid(d.bodies.torso):
			d.pooled = true
			var tp: Vector3 = (d.bodies.torso as Node3D).global_position
			var q := PhysicsRayQueryParameters3D.create(tp + Vector3(0, 0.5, 0), tp + Vector3(0, -2, 0)); q.collision_mask = 1
			var fl := g.get_world_3d().direct_space_state.intersect_ray(q)
			if fl: g.store.splat(fl.position, Vector3.UP, 1.3)
	# the arrest plays out
	if not arrest.is_empty(): _play_arrest(dt)

func _play_arrest(dt: float) -> void:
	arrest.t += dt
	var t: float = arrest.t
	var rec: Dictionary = arrest.o
	var off: Node3D = rec.node
	if not is_instance_valid(off): arrest = {}; return
	for o in officers:
		if o != rec: (o.node as Node3D).call("pose", dt); _update_officer_gun(o)
	var john: Node3D = g.john
	var jp: Vector3 = john.global_position
	var J: Dictionary = off.J
	var to_off := Vector2(off.global_position.x - jp.x, off.global_position.z - jp.z)
	# --- the officer: draw and cover him, then holster and walk round behind him, then cuff
	if t < 2.7:
		var k: float = g.sm(clamp(t / 0.7, 0.0, 1.0))
		var pos: Vector3 = (arrest.from as Vector3).lerp(arrest.stand, k)
		off.global_position = Vector3(pos.x, jp.y, pos.z)
		off.set_anim("walk" if k < 0.95 else "idle")
		off.aiming = true
		off.rotation.y = lerp_angle(off.rotation.y, atan2(jp.x - off.global_position.x, jp.z - off.global_position.z), 1.0 - exp(-dt * 10))
		off.aim_pitch = atan2(-0.2, max(to_off.length(), 0.5))
	else:
		off.aiming = false
		var u: float = g.sm(clamp((t - 2.7) / 1.5, 0.0, 1.0))
		var behind: float = john.facing + PI                       # angle (from John) of his back
		var a0: float = arrest.a0
		var a := a0 + wrapf(behind - a0, -PI, PI) * u
		var r: float = lerp(2.4, 0.6, u)
		off.global_position = Vector3(jp.x + sin(a) * r, jp.y, jp.z + cos(a) * r)
		off.rotation.y = lerp_angle(off.rotation.y, atan2(jp.x - off.global_position.x, jp.z - off.global_position.z), 1.0 - exp(-dt * 10))
		off.set_anim("walk" if u < 0.98 else "cuff")
	off.pose(dt)
	_update_officer_gun(rec)
	# --- John: turn to face him, hands up; then hands behind his back
	if t < 2.7:
		john.facing = lerp_angle(john.facing, atan2(to_off.x, to_off.y), 1.0 - exp(-dt * 6))
	var up_w: float = g.sm(clamp(t / 0.6, 0.0, 1.0)) * (1.0 - g.sm(clamp((t - 3.6) / 0.5, 0.0, 1.0)))
	var back_w: float = g.sm(clamp((t - 3.6) / 0.6, 0.0, 1.0))
	var d: Dictionary = g.side_dirs()
	var fwd := Vector3(d.fx, 0, d.fz); var right := Vector3(d.rx, 0, d.rz)
	var up_r: Vector3 = john.shoulder_world(true) + Vector3(0, 0.52, 0) + fwd * 0.1 + right * 0.06
	var up_l: Vector3 = john.shoulder_world(false) + Vector3(0, 0.52, 0) + fwd * 0.1 - right * 0.06
	var bk_r: Vector3 = jp + Vector3(0, 0.98, 0) - fwd * 0.2 + right * 0.05
	var bk_l: Vector3 = jp + Vector3(0, 0.98, 0) - fwd * 0.2 - right * 0.05
	john.snort_ik.w = max(up_w, back_w); john.left_ik.w = max(up_w, back_w)
	john.snort_ik.target = up_r.lerp(bk_r, back_w); john.left_ik.target = up_l.lerp(bk_l, back_w)
	john.pose.bend = 0.18 * back_w
	# resist window
	if can_resist(): g.hud.prompt("Resist (pull your gun)")
	else: g.hud.prompt("")
	if t > ARREST_CUFF and not arrest.cuffed:
		arrest.cuffed = true; g.hud.prompt("")
		Sfx.play("clink0", -3.0, 0.55); Sfx.play("clink2", -3.0, 0.5, 0.18)
		g.hud.say("Officer", ["You have the right to remain silent.", "Watch your head. You're done for tonight, John.", "That's it. You're under arrest."].pick_random(), 2.4)
	if t > ARREST_CUFF + 0.9 and not arrest.said:
		arrest.said = true; g.say("Aw, c'mon... I wash only had a few..." if g.beers >= 3 else "Aw, come on...", 2.2)
	if t > ARREST_CUFF + 2.4:
		arrest = {}; john.snort_ik.w = 0.0; john.left_ik.w = 0.0; john.pose.bend = 0.0
		_busted()
