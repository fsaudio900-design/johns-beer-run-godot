extends Node
## Ben, John's neighbour across the cul-de-sac (v2.16).
##
## John knocks on Ben's front door with E. Ben opens it and steps out onto the step. With E
## again John talks to him, and Ben gives him a job: rob the Fuel Stop and bring him the money.
## Once John has the till's cash, he can hand it over at Ben's door for a cut.
##
## Model: assets/chars/Ben.glb (rigged and animated in Blender: Idle, Walk, Talk, LookAround,
## Laugh, Nod, ShakeHead, Shrug).

const DOOR_HINGE := Vector3(0.4, -0.35, -44.47)   # Ben's front door (in the neighbourhood model)
const STEP := Vector3(0.9, -0.29, -43.95)         # where Ben stands when he answers
const HALL := Vector3(0.9, -0.29, -45.3)          # just inside
const KNOCK_SPOT := Vector2(0.9, -43.1)           # John at the door
const LOOPS := ["Idle", "Walk", "Talk", "LookAround"]

var g: Node
var ben: Node3D
var anim: AnimationPlayer
var door: Node3D                 # pivot the door panel hangs on
var door_open := 0.0
var door_target := 0.0
var st := "inside"               # inside | coming | door | talking | going
var t := 0.0
var away_t := 0.0
var mission := "none"            # none | rob | done
var owed := 0.0                  # the haul John should bring back
var visits := 0
var lines: Array = []
var line_t := 0.0
var line_i := 0

func setup(game: Node) -> void:
	g = game
	var ps: PackedScene = load("res://assets/chars/Ben.glb")
	ben = ps.instantiate(); ben.name = "Ben"; g.add_child(ben)
	ben.global_position = HALL; ben.visible = false
	anim = ben.find_child("*", true, false) as AnimationPlayer
	for a in ben.find_children("*", "AnimationPlayer", true, false): anim = a
	if anim:
		for n in LOOPS:
			if anim.has_animation(n): anim.get_animation(n).loop_mode = Animation.LOOP_LINEAR
	for mi: MeshInstance3D in ben.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	_hang_door()

## the door panel is part of the neighbourhood model: hang it on a pivot at its hinge and put a
## dim hallway behind it so the open doorway shows a room, not the sky
func _hang_door() -> void:
	var nb: Node = g.world.get_node_or_null("JBR_Neighborhood")
	if nb == null: return
	var panel: MeshInstance3D = null
	for mi: MeshInstance3D in nb.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = mi.global_transform * mi.get_aabb()
		if b.position.distance_to(Vector3(0.4, -0.35, -44.51)) < 0.06 and abs(b.size.x - 1.0) < 0.05 and abs(b.size.y - 2.1) < 0.05:
			panel = mi; break
	if panel == null: push_warning("[ben] front door not found"); return
	door = Node3D.new(); door.name = "BenDoorPivot"; nb.add_child(door); door.global_position = DOOR_HINGE
	panel.reparent(door, true)
	# the house is a solid box: its front wall (and the foundation skirt) run on behind the door,
	# so cut the doorway out of them (render only: the collision stays, John can't walk in)
	for mi: MeshInstance3D in panel.get_parent().get_parent().find_children("*", "MeshInstance3D", true, false):
		if mi == panel: continue
		var b2: AABB = mi.global_transform * mi.get_aabb()
		if b2.size.x > 5.0 and b2.position.x < 0.4 and b2.end.x > 1.4 and b2.position.z + b2.size.z > -44.6 and b2.position.z + b2.size.z < -44.3:
			_cut_hole(mi, Rect2(0.4, -0.36, 1.0, 2.12), b2.position.z + b2.size.z)
	var hall := MeshInstance3D.new(); hall.name = "BenHall"
	var bm := BoxMesh.new(); bm.size = Vector3(1.05, 2.15, 1.6); bm.flip_faces = true; hall.mesh = bm
	var m := StandardMaterial3D.new(); m.albedo_color = Color(0.32, 0.26, 0.2); m.roughness = 0.9; hall.material_override = m
	nb.add_child(hall); hall.global_position = Vector3(0.9, 0.72, -45.33)
	var l := OmniLight3D.new(); l.light_color = Color(1.0, 0.78, 0.5); l.light_energy = 0.9; l.omni_range = 2.6
	nb.add_child(l); l.global_position = Vector3(0.9, 1.6, -45.6)

## replace the front face of a box mesh (a plane at world z = zf) with pieces around a hole
func _cut_hole(mi: MeshInstance3D, hole: Rect2, zf: float) -> void:
	var xf: Transform3D = mi.global_transform
	var mesh: Mesh = mi.mesh
	var out := ArrayMesh.new()
	for s in mesh.get_surface_count():
		var arr := mesh.surface_get_arrays(s)
		var V: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
		var N: PackedVector3Array = arr[Mesh.ARRAY_NORMAL]
		var U = arr[Mesh.ARRAY_TEX_UV]
		var I = arr[Mesh.ARRAY_INDEX]
		var idx: Array = []
		if I: for k in I: idx.append(k)
		else: for k in V.size(): idx.append(k)
		var st := SurfaceTool.new(); st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var face: Array = []          # vertex ids of the front face
		for t in idx.size() / 3:
			var ids: Array = [idx[t * 3], idx[t * 3 + 1], idx[t * 3 + 2]]
			var on := true
			for k in ids: on = on and abs((xf * V[k]).z - zf) < 0.01 and N[k].z > 0.5
			if on: face.append_array(ids); continue
			for k in ids:
				st.set_normal(N[k])
				if U: st.set_uv(U[k])
				st.add_vertex(V[k])
		if face.size() >= 3:
			# the face's extent and its uv as a function of (x, y)
			var lo := Vector2(1e9, 1e9); var hi := Vector2(-1e9, -1e9)
			for k in face: var w: Vector3 = xf * V[k]; lo = lo.min(Vector2(w.x, w.y)); hi = hi.max(Vector2(w.x, w.y))
			var uv_at := func(x: float, y: float) -> Vector2: return Vector2.ZERO
			if U:
				var a: Vector3 = xf * V[face[0]]; var b: Vector3 = xf * V[face[1]]; var c: Vector3 = xf * V[face[2]]
				var M := Basis(Vector3(a.x, b.x, c.x), Vector3(a.y, b.y, c.y), Vector3(1, 1, 1))   # columns: x, y, 1
				var inv := M.inverse()
				var ua := inv * Vector3(U[face[0]].x, U[face[1]].x, U[face[2]].x)
				var va := inv * Vector3(U[face[0]].y, U[face[1]].y, U[face[2]].y)
				uv_at = func(x: float, y: float) -> Vector2: return Vector2(ua.x * x + ua.y * y + ua.z, va.x * x + va.y * y + va.z)
			var h0 := hole.position; var h1 := hole.end
			h0 = h0.max(lo); h1 = h1.min(hi)
			var rects := [Rect2(lo.x, lo.y, h0.x - lo.x, hi.y - lo.y), Rect2(h1.x, lo.y, hi.x - h1.x, hi.y - lo.y),
				Rect2(h0.x, h1.y, h1.x - h0.x, hi.y - h1.y), Rect2(h0.x, lo.y, h1.x - h0.x, h0.y - lo.y)]
			var inv_xf := xf.affine_inverse()
			for r: Rect2 in rects:
				if r.size.x <= 0.001 or r.size.y <= 0.001: continue
				var cs := [Vector2(r.position.x, r.position.y), Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.end.y), Vector2(r.position.x, r.end.y)]
				for tri in [[0, 2, 1], [0, 3, 2]]:     # Godot's front faces wind clockwise
					for k in tri:
						var c2: Vector2 = cs[k]
						st.set_normal(Vector3(0, 0, 1))
						if U: st.set_uv(uv_at.call(c2.x, c2.y))
						st.add_vertex(inv_xf * Vector3(c2.x, c2.y, zf))
		st.generate_tangents()
		st.commit(out)
		out.surface_set_material(out.get_surface_count() - 1, mi.get_active_material(s))
	mi.mesh = out

func reset() -> void:
	st = "inside"; t = 0.0; mission = "none"; owed = 0.0; visits = 0; lines = []
	hp = 3
	if dead and ben:
		dead = false
		if sim: sim.physical_bones_stop_simulation(); sim.queue_free(); sim = null
		var sk := _skel()
		if sk: sk.reset_bone_poses()
	door_target = 0.0; door_open = 0.0
	if ben: ben.visible = false; ben.global_position = HALL
	_apply_door()

# ------------------------------------------------------------------ helpers
func _play(n: String, blend := 0.25) -> void:
	if anim and anim.has_animation(n) and anim.current_animation != n: anim.play(n, blend)
func b_say(text: String, secs := 3.0) -> void: g.hud.say("Ben", text, secs)
func jpos() -> Vector2: return Vector2(g.john.global_position.x, g.john.global_position.z)
func at_door() -> bool: return jpos().distance_to(KNOCK_SPOT) < 1.5 and g.state == "walking"
func can_pay() -> bool: return mission == "rob" and owed > 0.0

## what Ben is waiting for, shown when nothing else is in reach
func hint() -> String:
	if dead: return ""
	if mission == "rob" and owed <= 0.0: return "Ben's job: rob the Fuel Stop on Main Street"
	if mission == "rob": return "Bring the money to Ben, across the street"
	return ""

func prompt() -> Array:
	if not at_door(): return []
	if dead: return []
	match st:
		"inside": return ["Knock on Ben's door", true]
		"door":
			if can_pay(): return ["Give Ben the money (%s)" % g.store.money(min(owed, g.store.cash)), true]
			return ["Talk to Ben", true]
	return []

func interact() -> bool:
	if not at_door(): return false
	if dead: return false
	if st == "inside" and mission == "off":
		Sfx.play("knock"); b_say(["Get away from my house, you maniac!", "I'm calling the cops, John!", "Go away!"].pick_random(), 2.4)
		return true
	if st == "inside":
		Sfx.play("knock"); g.say("Ben! You home?" if visits == 0 else "Ben, it's me.", 1.8)
		if g.police and g.police.hostile:
			st = "going"; t = 0.0
			get_tree().create_timer(1.6).timeout.connect(func(): b_say("Go away, John! The cops are all over you!", 2.6); st = "inside")
			return true
		st = "coming"; t = 0.0
		return true
	if st == "door":
		if can_pay(): _pay()
		else: _talk()
		return true
	if st == "talking": line_t = min(line_t, 0.05); return true      # E skips to the next line
	return st == "coming"

# ------------------------------------------------------------------ the conversations
func _talk() -> void:
	var slur: bool = g.beers >= 3
	match mission:
		"none":
			lines = [["B", "Actually, glad you came by. I've got a job for you.", "Talk"],
				["J", "A job? Whash kind of job?" if slur else "A job? What kind of job?"],
				["B", "The Fuel Stop on Main Street. That register's full this time of night.", "Talk"],
				["J", "You want me to rob the gash station?" if slur else "You want me to rob the gas station?"],
				["B", "Just bring me the money. All of it. I'll make it worth your while.", "Nod"],
				["J", "...Fine. I'll be back."],
				["B", "Don't keep me waiting.", "Idle", "rob"]]
			if g.store.rob.till == false and g.store.haul > 0.0:
				lines[5] = ["J", "Funny you should say that. Already did it."]
				lines[6] = ["B", "Ha! Then hand it over.", "Laugh", "rob_done"]
		"rob":
			lines = [["B", ["The register isn't going to empty itself, John.", "Fuel Stop. Register. Money. Go.", "Why are you still standing here?"].pick_random(), "Shrug"]]
		"done":
			lines = [["B", ["Lay low for a while, John.", "We're square. Go home.", "Nice doing business with you."].pick_random(), "Nod"]]
	_start_lines()

func _pay() -> void:
	var give: float = min(owed, g.store.cash)
	var cut: float = round(give * 0.25)
	g.store.add_cash(-give)
	lines = [["J", "Here. All of it."],
		["B", "Ha! Look at that!", "Laugh"],
		["B", "Here's your cut. Now get lost before the cops come knocking.", "Talk", "paid", cut]]
	if give < owed * 0.6: lines[1] = ["B", "That's it? Where's the rest of it?", "ShakeHead"]
	mission = "done"; owed = 0.0
	_start_lines()

func _start_lines() -> void:
	st = "talking"; line_i = 0; line_t = 0.0
	g.set_state("busy")
	g.hud.prompt("")
	_next_line()

func _next_line() -> void:
	if line_i >= lines.size():
		st = "door"; t = 0.0; away_t = 0.0; _play("Idle")
		g.set_state("walking"); return
	var ln: Array = lines[line_i]
	if ln[0] == "B":
		b_say(ln[1], 3.0); _play(ln[2] if ln.size() > 2 else "Talk")
		if ln.size() > 3:
			match ln[3]:
				"rob": mission = "rob"
				"rob_done": mission = "rob"; owed = g.store.haul
				"paid":
					var cut: float = ln[4]
					if cut > 0: g.store.add_cash(cut)
	else:
		g.say(ln[1], 2.6); _play("Idle")
	line_t = 3.1 if ln[0] == "B" else 2.6
	line_i += 1

# ------------------------------------------------------------------ update
func update(dt: float) -> void:
	if ben == null or dead: return
	t += dt
	# the till's been emptied while Ben's job is on: that's what he's owed
	if mission == "rob" and owed <= 0.0 and g.store.haul > 0.0 and g.store.rob.till == false: owed = g.store.haul
	match st:
		"coming":
			if t > 1.4: door_target = 1.0
			if t > 1.9:
				ben.visible = true
				var k: float = clamp((t - 1.9) / 1.2, 0.0, 1.0)
				ben.global_position = HALL.lerp(STEP, k); ben.rotation.y = 0.0; _play("Walk", 0.15)
				if k >= 1.0:
					st = "door"; t = 0.0; away_t = 0.0; _play("Idle")
					visits += 1
					var greet := "John! Little late for a visit, isn't it?" if visits == 1 else "Back again?"
					if mission == "rob" and owed > 0.0: greet = "Well? You got it?"
					elif mission == "rob": greet = "Did you do it yet?"
					b_say(greet, 2.6)
		"door":
			_face_john(dt)
			if t > 6.0 and anim and anim.current_animation == "Idle" and randf() < dt * 0.15: _play("LookAround")
			if anim and anim.current_animation == "LookAround" and not anim.is_playing(): _play("Idle")
			if jpos().distance_to(KNOCK_SPOT) > 6.0: away_t += dt
			else: away_t = 0.0
			if away_t > 2.5: st = "going"; t = 0.0
		"talking":
			_face_john(dt)
			line_t -= dt
			if line_t <= 0.0: _next_line()
		"going":
			if ben.visible:
				var k: float = clamp(t / 1.2, 0.0, 1.0)
				ben.rotation.y = lerp_angle(ben.rotation.y, PI, 1.0 - exp(-dt * 10)); _play("Walk", 0.15)
				ben.global_position = STEP.lerp(HALL, k)
				if k >= 1.0: ben.visible = false; door_target = 0.0; Sfx.play("thunk"); st = "inside"; t = 0.0
			else:
				st = "inside"
	if anim and not anim.is_playing() and ben.visible and st != "coming" and st != "going": _play("Idle")
	var was := door_open
	door_open = move_toward(door_open, door_target, dt * 1.6)
	if door_open != was:
		if was == 0.0: Sfx.play("creak")
		_apply_door()

func _face_john(dt: float) -> void:
	var d: Vector3 = g.john.global_position - ben.global_position
	var want := atan2(d.x, d.z)
	ben.rotation.y = lerp_angle(ben.rotation.y, want, 1.0 - exp(-dt * 4))

func _apply_door() -> void:
	if door: door.rotation.y = door_open * 1.45

# ------------------------------------------------------------------ getting shot
## Ben can be shot like anyone else: a head shot or three body hits kill him (he goes limp as a
## ragdoll on his own skeleton); a wound sends him back inside and the deal is off.
var hp := 3
var dead := false
var sim: PhysicalBoneSimulator3D
const RAG_BONES := {"hips": 0.13, "spine": 0.12, "chest": 0.15, "head": 0.11, "thigh.L": 0.08, "thigh.R": 0.08,
	"shin.L": 0.06, "shin.R": 0.06, "upper_arm.L": 0.055, "upper_arm.R": 0.055, "forearm.L": 0.045, "forearm.R": 0.045}

func _skel() -> Skeleton3D:
	return ben.find_children("*", "Skeleton3D", true, false)[0] if ben else null

func _bone_pos(sk: Skeleton3D, n: String) -> Vector3:
	var i := sk.find_bone(n)
	return sk.global_transform * sk.get_bone_global_pose(i).origin if i >= 0 else ben.global_position

## closest approach of the shot to a capsule (segment a-b, radius r); returns distance along the ray or -1
func _ray_capsule(from: Vector3, dir: Vector3, a: Vector3, b: Vector3, r: float, max_d: float) -> float:
	var best := -1.0
	for k in 9:
		var p := a.lerp(b, k / 8.0)
		var t := (p - from).dot(dir)
		if t < 0 or t > max_d: continue
		if (from + dir * t).distance_to(p) < r and (best < 0 or t < best): best = t
	return best

func on_shot(from: Vector3, dir: Vector3, hit: Dictionary) -> bool:
	if ben == null or not ben.visible or dead: return false
	var max_d: float = from.distance_to(hit.position) if hit else 40.0
	var sk := _skel()
	if sk == null: return false
	var head := _bone_pos(sk, "head") + Vector3(0, 0.1, 0)
	var th := _ray_capsule(from, dir, head, head, 0.13, max_d)
	var tb := _ray_capsule(from, dir, _bone_pos(sk, "hips") - Vector3(0, 0.75, 0), _bone_pos(sk, "neck"), 0.21, max_d)
	if th < 0 and tb < 0: return false
	var zone := "head" if th >= 0 and (tb < 0 or th <= tb + 0.05) else "body"
	var t: float = th if zone == "head" else tb
	var p := from + dir * (t - 0.04)
	Sfx.play("hurt")
	g.store.spray(p, dir, 26 if zone == "head" else 16, 2.4); g.store.spray(p, -dir, 6, 0.8)
	var q := PhysicsRayQueryParameters3D.create(p, p + dir * 4.0); q.exclude = [g.john.get_rid()]
	var back: Dictionary = g.get_world_3d().direct_space_state.intersect_ray(q)
	if back: g.store.splat(back.position, back.normal, 0.9 if zone == "head" else 0.55)
	g.store.start_wanted()
	hp -= 3 if zone == "head" else 1
	if st == "talking": lines = []; line_i = 0; g.set_state("walking")
	if hp <= 0: _die(dir, zone)
	else:
		mission = "off"; owed = 0.0
		b_say(["Agh! John, what the hell?!", "Are you insane?! Get away from me!"][3 - hp - 1] if hp < 3 else "Agh!", 2.2)
		if anim: _play("ShakeHead", 0.05)
		st = "going"; t = 0.0
	return true

func _die(dir: Vector3, zone: String) -> void:
	dead = true; mission = "dead"; owed = 0.0; st = "dead"
	if anim: anim.stop()
	var sk := _skel()
	sim = PhysicalBoneSimulator3D.new(); sim.name = "Ragdoll"; sk.add_child(sim)
	var hit_bone := "head" if zone == "head" else "chest"
	for n in RAG_BONES:
		var i := sk.find_bone(n)
		if i < 0: continue
		var blen := 0.25
		for c in sk.get_bone_children(i):
			blen = sk.get_bone_rest(c).origin.length(); break
		if n == "head": blen = 0.24
		if n.begins_with("forearm"): blen = 0.28
		var pb := PhysicalBone3D.new(); pb.name = "Rag_" + n
		sim.add_child(pb); pb.bone_name = n
		pb.joint_type = PhysicalBone3D.JOINT_TYPE_CONE if n != "hips" else PhysicalBone3D.JOINT_TYPE_NONE
		pb.body_offset = Transform3D(Basis(), Vector3(0, -blen * 0.5, 0))
		pb.mass = 8.0 if n in ["hips", "chest", "spine"] else 3.0
		pb.collision_layer = 8; pb.collision_mask = 1
		pb.linear_damp = 0.4; pb.angular_damp = 2.0
		var cs := CollisionShape3D.new(); var cap := CapsuleShape3D.new()
		cap.radius = RAG_BONES[n]; cap.height = max(blen, cap.radius * 2.0 + 0.01); cs.shape = cap
		pb.add_child(cs)
	sim.physical_bones_start_simulation()
	await get_tree().physics_frame
	for pb: PhysicalBone3D in sim.get_children():
		if pb.bone_name == hit_bone: pb.apply_central_impulse(dir * pb.mass * 2.2)
		elif pb.bone_name in ["hips", "spine"]: pb.apply_central_impulse(dir * pb.mass * 0.9)

## where the ragdoll's hips are (for tests)
func rag_hips() -> Vector3:
	if sim:
		for pb: PhysicalBone3D in sim.get_children():
			if pb.bone_name == "hips": return pb.global_position
	return Vector3.ZERO
