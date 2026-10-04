extends CharacterBody3D
## John: the rigged FBX character, posed procedurally exactly like the web build.
## The pose is a blend of the "beer" clip (sitting / drinking) and the standing bind pose
## with pivot rotations for walking, reaching, bending, squatting, two-bone arm IK and a
## head droop for passing out. The rig's deform bones are flat (parented to c_traj), so each
## body region is posed in bind space and then converted back to bone-local poses.

const JOHN_HEIGHT := 1.75
const GRAVITY := 9.8
const BEND_K := 1.0

# ---- pose state (driven by the game controller) ----
var pose := {sit = 1.0, phase = 0.0, walk = 0.0, reach = 0.0, droop = 0.0, clip_t = 0.0, bend = 0.0, squat = 0.0}
var carry := 0.0                     # arm held in for carrying a can / case
var snort_ik := {w = 0.0, target = Vector3.ZERO}    # right hand world-space target
var left_ik := {w = 0.0, target = Vector3.ZERO}     # left hand world-space target
var facing := PI
var has_can := false : set = _set_can
var drunk_sway := 0.0                # 0..1, body roll while standing
var grip_w := 0.0                    # right hand closed around the Glock
var gun_twist := 0.0                 # forearm roll while aiming
var curl_r := {}                     # right-hand finger bone -> joints it curls about
var gun_bind: Transform3D            # Glock relative to the right hand, bind space

var model: Node3D
var fit: Node3D
var skel: Skeleton3D
var can_mesh: MeshInstance3D
var clip: Animation
var clip_len := 4.125

# ---- rig data ----
var need: PackedInt32Array = []      # bones that need posing, parents first
var parent_of: PackedInt32Array = []
var rest_local: Array[Transform3D] = []
var init_local: Array[Transform3D] = []
var rest_global: Array[Transform3D] = []
var deform := {}
var role := {}
var head_set := {}
var upper := {}
var piv := {}
var Gc: Array[Transform3D] = []      # clip pose, skeleton space
var Gp: Array[Transform3D] = []      # procedural pose
var G: Array[Transform3D] = []       # final
var D := {}
var tracks := {}                     # bone -> [pos_track, rot_track, scl_track]
var last_clip_t := -1.0
var b_head := -1; var b_nose := -1; var b_hand_r := -1; var b_hand_l := -1; var b_neck := -1; var b_elbow_l := -1; var b_elbow_r := -1
const FWD := Vector3(0, -1, 0)       # bind-space forward (the nose points -Y)
const SIDE := Vector3(1, 0, 0)       # bind-space lateral axis (John's left is +X)
const UPB := Vector3(0, 0, 1)        # bind-space up
var pole_l := Vector3(0.55, 0.35, -1).normalized()
var pole_r := Vector3(-0.55, 0.35, -1).normalized()
var sgn := {leg = 1.0, knee = 1.0, bend = 1.0, droop = 1.0, splay = 1.0, roll = 1.0, curl = 1.0}

func _ready() -> void:
	_build_model()
	_build_rig()
	_calibrate()

func _set_can(v: bool) -> void:
	has_can = v
	if can_mesh: can_mesh.visible = v

# ------------------------------------------------------------------ model
func _build_model() -> void:
	var adopted := has_node("Model/Fit")        # placed in main.tscn so John shows in the editor
	var john: Node3D
	if adopted:
		model = get_node("Model"); fit = get_node("Fit") if has_node("Fit") else get_node("Model/Fit")
		john = fit.get_child(0)
	else:
		model = Node3D.new(); model.name = "Model"; add_child(model)
		fit = Node3D.new(); fit.name = "Fit"; model.add_child(fit)
		john = (load("res://assets/john/john.fbx") as PackedScene).instantiate()
		fit.add_child(john)
	skel = john.find_child("Skeleton3D", true, false)
	var ap: AnimationPlayer = john.find_child("AnimationPlayer", true, false)
	if ap:
		clip = ap.get_animation("beer")
		clip_len = clip.length
		ap.stop()
		ap.get_parent().remove_child(ap); ap.queue_free()
	var tex := func(n): return load("res://assets/john/" + n)
	for mi: MeshInstance3D in john.find_children("*", "MeshInstance3D", true, false):
		var m := StandardMaterial3D.new()
		match String(mi.name):
			"chair_low": mi.visible = false; continue
			"bee_can":
				m.albedo_texture = tex.call("beer_BaseColor.jpg")
				m.roughness_texture = tex.call("beer_Roughness.jpg")
				m.metallic_texture = tex.call("beer_Metallic.jpg"); m.metallic = 1.0
				can_mesh = mi; mi.visible = false
			"fat_oldman_low":
				m.albedo_texture = tex.call("oldmanskin_BaseColor.jpg")
				m.normal_enabled = true; m.normal_texture = tex.call("oldmanskin_Normal.jpg")
				m.roughness_texture = tex.call("oldmanskin_Roughness.jpg")
				m.cull_mode = BaseMaterial3D.CULL_DISABLED
			"alkashka_low", "pants_low":
				m.albedo_texture = tex.call("cloth_BaseColor.jpg")
				m.normal_enabled = true; m.normal_texture = tex.call("cloth_Normal.jpg")
				m.roughness_texture = tex.call("cloth_Roughness.jpg")
			"eye_low":
				m.albedo_texture = tex.call("eye_BaseColor.jpg"); m.roughness = 0.15
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		mi.extra_cull_margin = 2.0

	if adopted: return
	# orient + scale: head up, face +Z, 1.75 m tall, rig origin at John's position (as in the web build)
	var S: Transform3D = fit.global_transform.affine_inverse() * skel.global_transform
	var bp := func(n: String) -> Vector3: return S * skel.get_bone_global_rest(skel.find_bone(n)).origin
	var foot: Vector3 = (bp.call("foot.l") + bp.call("foot.r")) * 0.5
	var head: Vector3 = bp.call("head.x")
	var up := (head - foot).normalized()
	var fwd: Vector3 = S.basis * FWD; fwd = (fwd - up * fwd.dot(up)).normalized()
	var right := up.cross(fwd)
	var R := Basis(right, up, fwd).transposed()
	var body: MeshInstance3D = john.find_child("fat_oldman_low", true, false)
	var Ms: Transform3D = fit.global_transform.affine_inverse() * body.global_transform
	var lo := INF; var hi := -INF
	var bb := body.get_aabb()
	for i in 8:
		var y := (R * (Ms * bb.get_endpoint(i))).y
		lo = min(lo, y); hi = max(hi, y)
	var k := JOHN_HEIGHT / (hi - lo)
	fit.transform = Transform3D(Basis.from_scale(Vector3.ONE * k) * R, Vector3.ZERO)

# ------------------------------------------------------------------ rig
func _build_rig() -> void:
	var n := skel.get_bone_count()
	parent_of.resize(n); rest_local.resize(n); init_local.resize(n); rest_global.resize(n)
	Gc.resize(n); Gp.resize(n); G.resize(n)
	for i in n:
		parent_of[i] = skel.get_bone_parent(i)
		rest_local[i] = skel.get_bone_rest(i)
		init_local[i] = skel.get_bone_pose(i)
		rest_global[i] = skel.get_bone_global_rest(i)
	for mi: MeshInstance3D in skel.find_children("*", "MeshInstance3D", true, false):
		if mi.skin:
			for i in mi.skin.get_bind_count():
				var bn := String(mi.skin.get_bind_name(i))
				var bi: int = skel.find_bone(bn) if bn != "" else mi.skin.get_bind_bone(i)
				if bi >= 0: deform[bi] = true
	var keep := {}
	var can_b := skel.find_bone("bee_can")
	for b in deform.keys() + ([can_b] if can_b >= 0 else []):
		var x: int = b
		while x >= 0 and not keep.has(x):
			keep[x] = true; x = parent_of[x]
	# parents-first ordering of the bones we pose
	var children := {}
	for i in n:
		if parent_of[i] >= 0: children.get_or_add(parent_of[i], []).push_back(i)
	var stack: Array = []
	for i in n:
		if parent_of[i] < 0: stack.push_back(i)
	while stack.size():
		var b: int = stack.pop_back()
		if keep.has(b): need.push_back(b)
		for c in children.get(b, []): stack.push_back(c)
	if clip:
		for t in clip.get_track_count():
			var path := String(clip.track_get_path(t))
			var bn := path.substr(path.find(":") + 1)
			var bi := skel.find_bone(bn)
			if bi < 0: continue
			var slot: Array = tracks.get_or_add(bi, [-1, -1, -1])
			match clip.track_get_type(t):
				Animation.TYPE_POSITION_3D: slot[0] = t
				Animation.TYPE_ROTATION_3D: slot[1] = t
				Animation.TYPE_SCALE_3D: slot[2] = t
	var fingers := ["c_index1_base","c_index2","c_index3","index1","c_middle1_base","c_middle2","c_middle3","middle1","c_ring1_base","c_ring2","c_ring3","ring1","c_pinky1_base","c_pinky2","c_pinky3","pinky1","thumb1","c_thumb2","c_thumb3"]
	var tag := func(names: Array, s: String, r: String):
		for nm in names:
			var bi := skel.find_bone(nm + "." + s)
			if bi >= 0 and deform.has(bi): role[bi] = r
	for s in ["l", "r"]:
		var S: String = s.to_upper()
		tag.call(["thigh_twist", "thigh_stretch"], s, "leg" + S)
		tag.call(["leg_stretch", "leg_twist", "foot", "toes_01"], s, "shin" + S)
		tag.call(["c_arm_twist_offset", "arm_stretch"], s, "arm" + S)
		tag.call(["forearm_stretch", "forearm_twist", "hand"] + fingers, s, "fore" + S)
	var P := func(nm: String) -> Vector3:
		var bi := skel.find_bone(nm)
		return rest_global[bi].origin if bi >= 0 else Vector3.ZERO
	piv = {hipL = P.call("thigh_twist.l"), hipR = P.call("thigh_twist.r"),
		kneeL = P.call("leg_stretch.l"), kneeR = P.call("leg_stretch.r"),
		shL = P.call("c_arm_twist_offset.l"), shR = P.call("c_arm_twist_offset.r"),
		elL = P.call("forearm_stretch.l"), elR = P.call("forearm_stretch.r"),
		wrL = P.call("hand.l"), wrR = P.call("hand.r"), waist = P.call("spine_01.x")}
	for k in ["legL","shinL","legR","shinR","armL","foreL","armR","foreR"]: D[k] = Transform3D.IDENTITY
	# right-hand finger curl for gripping the gun
	for f in ["index", "middle", "ring", "pinky"]:
		var names := ["c_" + f + "1_base", f + "1", "c_" + f + "2", "c_" + f + "3"]
		var bs := []
		for nm in names:
			var bi := skel.find_bone(nm + ".r")
			if bi >= 0 and deform.has(bi): bs.append({b = bi, p = rest_global[bi].origin})
		if bs.size() < 2: continue
		var joints := []
		for i in range(1, bs.size()): joints.append(bs[i].p)
		for o in bs:
			var js := []
			for j in joints:
				if j.z >= o.p.z - 0.00001: js.append(j)
			curl_r[o.b] = js
	_build_gun_bind()
	b_head = skel.find_bone("head.x"); b_neck = skel.find_bone("neck.x")
	b_nose = skel.find_bone("c_nose_02.x"); if b_nose < 0: b_nose = skel.find_bone("c_nose_01.x")
	b_hand_l = skel.find_bone("hand.l"); b_hand_r = skel.find_bone("hand.r")
	b_elbow_l = skel.find_bone("forearm_stretch.l"); b_elbow_r = skel.find_bone("forearm_stretch.r")
	var neck_z: float = P.call("neck.x").z - 0.002
	var y0: float = piv.hipL.z; var y1: float = P.call("spine_03.x").z
	for b in deform:
		var r: String = role.get(b, "")
		if r == "" and rest_global[b].origin.z >= neck_z: head_set[b] = true
		if r.begins_with("leg") or r.begins_with("shin"): continue
		var f := 1.0 if r != "" else clamp((rest_global[b].origin.z - y0) / (y1 - y0), 0.0, 1.0)
		if f > 0: upper[b] = f * f * (3.0 - 2.0 * f)

## pick rotation signs so the motions go the right way in this rig's bind space
func _calibrate() -> void:
	var foot: Vector3 = rest_global[skel.find_bone("foot.l")].origin
	var hand: Vector3 = rest_global[b_hand_l].origin
	var head: Vector3 = rest_global[b_head].origin
	sgn.knee = 1.0 if (rot_about(piv.kneeL, SIDE, 0.6) * foot - foot).dot(FWD) < 0 else -1.0   # shin swings back
	sgn.leg = 1.0 if (rot_about(piv.hipL, SIDE, -0.4) * foot - foot).dot(FWD) > 0 else -1.0    # -sw lifts the leg forward
	sgn.bend = 1.0 if (rot_about(piv.waist, SIDE, 0.5) * head - head).dot(FWD) > 0 else -1.0  # +bend leans forward
	sgn.droop = sgn.bend
	sgn.splay = 1.0 if abs((rot_about(piv.shL, FWD, -0.2) * hand).x) > abs(hand.x) else -1.0
	var tip := skel.find_bone("c_index3.r"); var knk := skel.find_bone("index1.r")
	if tip >= 0 and knk >= 0:
		var tp: Vector3 = rest_global[tip].origin
		sgn.curl = 1.0 if (rot_about(rest_global[knk].origin, FWD, 0.5) * tp).x > tp.x else -1.0   # toward the palm (+X for the right hand)
	print("[john] rig: %d bones, %d deform, %d posed, %d roles, clip %.2fs, signs %s" % [skel.get_bone_count(), deform.size(), need.size(), role.size(), clip_len, sgn])

static func rot_about(p: Vector3, axis: Vector3, a: float) -> Transform3D:
	var b := Basis(axis.normalized(), a)
	return Transform3D(b, p - b * p)

static func rot_about_q(p: Vector3, q: Quaternion) -> Transform3D:
	var b := Basis(q)
	return Transform3D(b, p - b * p)

## two-bone IK in bind space (port of armIK from the web build)
func arm_ik(S: Vector3, E: Vector3, W: Vector3, T: Vector3, pole: Vector3, w: float, arm_k: String, fore_k: String, twist := 0.0) -> void:
	var a := E.distance_to(S); var b := W.distance_to(E)
	var d: float = clamp(T.distance_to(S), abs(a - b) + a * 0.02, (a + b) * 0.995)
	var u1 := (S - E).normalized(); var u2 := (W - E).normalized()
	var th0 := acos(clamp(u1.dot(u2), -1.0, 1.0))
	var th1 := acos(clamp((a * a + b * b - d * d) / (2 * a * b), -1.0, 1.0))
	var u3 := u1.cross(u2)
	if u3.length_squared() < 1e-14: u3 = SIDE
	u3 = u3.normalized()
	var qc := Quaternion(u3, th1 - th0)
	var w2 := (qc * (W - E)) + E
	var v1 := (w2 - S).normalized(); var v2 := (T - S).normalized()
	var qa := Quaternion(v1, v2) if v1.dot(v2) > -0.9999 else Quaternion(u3, PI)
	var e2 := qa * (E - S)
	var ep := e2 - v2 * e2.dot(v2); var pp := pole - v2 * pole.dot(v2)
	if ep.length_squared() > 1e-12 and pp.length_squared() > 1e-12:
		ep = ep.normalized(); pp = pp.normalized()
		var ang := acos(clamp(ep.dot(pp), -1.0, 1.0))
		if ep.cross(pp).dot(v2) < 0: ang = -ang
		qa = Quaternion(v2, ang) * qa
	qa = Quaternion.IDENTITY.slerp(qa, w); qc = Quaternion.IDENTITY.slerp(qc, w)
	D[arm_k] = rot_about_q(S, qa)
	D[fore_k] = D[arm_k] * rot_about_q(E, qc)
	if twist != 0.0:
		var e2b: Vector3 = D[arm_k] * E; var w2b: Vector3 = D[fore_k] * W
		D[fore_k] = rot_about(e2b, (w2b - e2b).normalized(), twist) * D[fore_k]

func to_bind(world: Vector3) -> Vector3:
	return skel.global_transform.affine_inverse() * world

func bone_world(b: int) -> Vector3:
	return skel.global_transform * G[b].origin if b >= 0 else global_position

func head_world() -> Vector3: return bone_world(b_head) + Vector3(0, 0.12, 0)
func nose_world() -> Vector3: return bone_world(b_nose)
func hand_world(right: bool) -> Vector3: return bone_world(b_hand_r if right else b_hand_l)
func elbow_world(right: bool) -> Vector3: return bone_world(b_elbow_r if right else b_elbow_l)

# ------------------------------------------------------------------ posing
func apply_pose(t_now: float, drunk: float) -> void:
	model.rotation = Vector3(0, facing, 0)
	var bob: float = abs(sin(pose.phase)) * 0.035 * pose.walk
	model.position.y = bob - 0.13 * pose.squat
	model.rotation.z = sin(pose.phase) * 0.05 * pose.walk + drunk * sin(t_now * 1.3) * 0.04 * (1.0 - pose.sit)
	var st: float = 1.0 - pose.sit
	# 1. clip pose
	var t: float = clamp(pose.clip_t, 0.0, clip_len - 0.001)
	if st < 1.0 and t != last_clip_t:
		last_clip_t = t
		for b in need:
			var loc: Transform3D = init_local[b]
			if tracks.has(b) and clip:
				var tr: Array = tracks[b]
				var p := clip.position_track_interpolate(tr[0], t) if tr[0] >= 0 else loc.origin
				var q := clip.rotation_track_interpolate(tr[1], t) if tr[1] >= 0 else loc.basis.get_rotation_quaternion()
				var s := clip.scale_track_interpolate(tr[2], t) if tr[2] >= 0 else loc.basis.get_scale()
				loc = Transform3D(Basis(q).scaled(s), p)
			var pa := parent_of[b]
			Gc[b] = (Gc[pa] * loc) if pa >= 0 else loc
	# 2. procedural deltas on the standing pose
	if st > 0.0:
		var w: float = pose.walk; var ph: float = pose.phase
		var sw := sin(ph) * w; var cw := cos(ph)
		var sq: float = pose.squat
		D.legL = rot_about(piv.hipL, SIDE, sgn.leg * (-sw * 0.42 - 0.55 * sq))
		D.shinL = D.legL * rot_about(piv.kneeL, SIDE, sgn.knee * (max(0.0, cw) * 0.75 * w + 0.05 + 1.0 * sq))
		D.legR = rot_about(piv.hipR, SIDE, sgn.leg * (sw * 0.42 - 0.55 * sq))
		D.shinR = D.legR * rot_about(piv.kneeR, SIDE, sgn.knee * (max(0.0, -cw) * 0.75 * w + 0.05 + 1.0 * sq))
		var reach: float = pose.reach
		var swing_l: float = lerp(sw * 0.32 * (1.0 - carry * 0.6), -1.15, reach)
		D.armL = rot_about(piv.shL, SIDE, sgn.leg * swing_l) * rot_about(piv.shL, FWD, sgn.splay * -0.1)
		D.foreL = D.armL * rot_about(piv.elL, SIDE, -sgn.knee * ((0.15 + carry) * (1.0 - reach) + 0.25 * reach))
		D.armR = rot_about(piv.shR, SIDE, sgn.leg * -sw * 0.32) * rot_about(piv.shR, FWD, sgn.splay * 0.1)
		D.foreR = D.armR * rot_about(piv.elR, SIDE, -sgn.knee * 0.15)
		var unbend := rot_about(piv.waist, SIDE, -sgn.bend * pose.bend * BEND_K)
		if snort_ik.w > 0.0:
			var T := to_bind(snort_ik.target)
			if pose.bend > 0: T = unbend * T
			arm_ik(piv.shR, piv.elR, piv.wrR, T, pole_r, snort_ik.w, "armR", "foreR", gun_twist)
		if left_ik.w > 0.0:
			var T2 := to_bind(left_ik.target)
			if pose.bend > 0: T2 = unbend * T2
			arm_ik(piv.shL, piv.elL, piv.wrL, T2, pole_l, left_ik.w, "armL", "foreL")
		var bend_x := rot_about(piv.waist, SIDE, sgn.bend * pose.bend * BEND_K)
		for b in need:
			var g: Transform3D
			if deform.has(b):
				if grip_w > 0.0 and curl_r.has(b):
					var js: Array = curl_r[b]; var cm := Transform3D.IDENTITY
					var angs := [1.25, 1.15, 0.8]
					for i in js.size(): cm = rot_about(js[i], FWD, sgn.curl * angs[i] * grip_w) * cm
					g = D[role[b]] * cm * rest_global[b]
				else:
					g = (D[role[b]] * rest_global[b]) if role.has(b) else rest_global[b]
				if pose.bend > 0 and upper.has(b):
					g = rot_about(piv.waist, SIDE, sgn.bend * pose.bend * BEND_K * upper[b]) * g
			else:
				var pa := parent_of[b]
				g = (Gp[pa] * rest_local[b]) if pa >= 0 else rest_local[b]
			Gp[b] = g
	# 3. blend, droop, and write bone-local poses
	var droop: Transform3D = Transform3D.IDENTITY
	if pose.droop > 0 and b_neck >= 0:
		var np: Vector3 = Gc[b_neck].origin.lerp(rest_global[b_neck].origin, st) if st < 1.0 else rest_global[b_neck].origin
		droop = rot_about(np, SIDE, sgn.droop * 0.6 * pose.droop) * rot_about(np, FWD, 0.25 * pose.droop)
	for b in need:
		var g: Transform3D
		if st <= 0.0: g = Gc[b]
		elif st >= 1.0: g = Gp[b]
		else: g = Gc[b].interpolate_with(Gp[b], st)
		if pose.droop > 0 and head_set.has(b): g = droop * g
		G[b] = g
		var pa := parent_of[b]
		var lp: Transform3D = (G[pa].affine_inverse() * g) if pa >= 0 else g
		skel.set_bone_pose_position(b, lp.origin)
		skel.set_bone_pose_rotation(b, lp.basis.get_rotation_quaternion())
		skel.set_bone_pose_scale(b, lp.basis.get_scale())

# ------------------------------------------------------------------ the Glock in the right hand
const GRIP_TUNE := {along = 58.0, palm = 31.0, thumb = 7.0}   # web-build units (John = 975 tall)

func _build_gun_bind() -> void:
	var W: Vector3 = piv.wrR; var E: Vector3 = piv.elR
	var fd := (W - E).normalized()
	var pn := Vector3(1, 0, 0); pn = (pn - fd * pn.dot(fd)).normalized()       # palm faces the body
	var td := fd.cross(pn).normalized()
	if td.dot(FWD) < 0: td = -td                                                # thumb side points forward
	var xg := td.cross(fd).normalized()
	var m_per_bind: float = skel.global_transform.basis.get_scale().x
	var u := (1.75 / 975.0) / m_per_bind                                        # web unit in bind units
	var pos := W + fd * GRIP_TUNE.along * u + pn * GRIP_TUNE.palm * u + td * GRIP_TUNE.thumb * u
	gun_bind = Transform3D(Basis(xg, td, fd), pos)

## world transform for the Glock rig (grip at origin, muzzle +Z, top +Y, metres)
func gun_world() -> Transform3D:
	var hand := b_hand_r
	var m: Transform3D = skel.global_transform * G[hand] * rest_global[hand].affine_inverse() * gun_bind
	return Transform3D(m.basis.orthonormalized(), m.origin)

func shoulder_world(right: bool) -> Vector3:
	return skel.global_transform * (piv.shR if right else piv.shL)
