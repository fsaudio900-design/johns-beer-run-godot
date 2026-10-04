extends Node
class_name SkinDriver
## Puts a real skinned character (Mixamo skeleton) on top of one of the procedural "visitor" rigs.
##
## The procedural rig keeps doing all the work (walk cycle, hands up, knocking, the kneel and spin
## reactions, hit zones, the ragdoll), but its meshes are hidden. Every frame its joint rotations
## are copied onto the matching bones of the skinned model, so the new character moves exactly
## like the old one. Rest-pose differences (T-pose vs arms-down) are solved once at startup by
## lining each bone up with its procedural joint.
##
## When the rig goes ragdoll, follow_ragdoll() makes the joints track the physics bodies so the
## skinned body falls with them.

# procedural joint -> [Mixamo bone, procedural joint the bone points at, Mixamo bone it points at]
const MAP := {
	hips = ["Hips", "spine", "Spine"], spine = ["Spine", "chest", "Spine2"], chest = ["Spine2", "neck", "Neck"],
	neck = ["Neck", "head", "Head"], head = ["Head", "", ""],
	shL = ["LeftArm", "elL", "LeftForeArm"], elL = ["LeftForeArm", "wrL", "LeftHand"], wrL = ["LeftHand", "fL1", "LeftHandMiddle1"],
	shR = ["RightArm", "elR", "RightForeArm"], elR = ["RightForeArm", "wrR", "RightHand"], wrR = ["RightHand", "fR1", "RightHandMiddle1"],
	thighL = ["LeftUpLeg", "kneeL", "LeftLeg"], kneeL = ["LeftLeg", "ankleL", "LeftFoot"], ankleL = ["LeftFoot", "", ""],
	thighR = ["RightUpLeg", "kneeR", "RightLeg"], kneeR = ["RightLeg", "ankleR", "RightFoot"], ankleR = ["RightFoot", "", ""],
}
# pistol grip: finger -> curl per joint (radians) for the shooting hand (R) and the support hand (L)
const GRIP_CURL := {
	R = {Index = [0.55, 0.5, 0.3], Middle = [1.35, 1.45, 0.9], Ring = [1.4, 1.5, 0.9], Pinky = [1.45, 1.5, 0.9], Thumb = [0.25, 0.45, 0.35]},
	L = {Index = [1.1, 1.2, 0.8], Middle = [1.2, 1.3, 0.8], Ring = [1.25, 1.35, 0.8], Pinky = [1.3, 1.35, 0.8], Thumb = [0.2, 0.3, 0.25]},
}
const RAG_ANCHOR := {torso = "spine", head = "neck", thighL = "thighL", thighR = "thighR", shinL = "kneeL", shinR = "kneeR",
	armL = "shL", armR = "shR", foreL = "elL", foreR = "elR"}

var rig: Node3D            # the visitor node
var J: Dictionary
var model: Node3D
var skel: Skeleton3D
var order: Array[int] = []           # bones, parents first
var bone_joint := {}                 # bone idx -> joint name
var offset := {}                     # bone idx -> Basis (joint rest -> bone, skeleton space)
var rest_local := {}                 # bone idx -> Basis
var hips_bone := -1
var hips_rest := Vector3.ZERO        # skeleton space
var hips_rest_joint := Vector3.ZERO  # skeleton space
var rag := {}                        # part -> [body, Transform3D body->joint]
var rag_hips := Transform3D()
var bone_ix := {}                    # clean Mixamo name -> bone idx
var grip_w := 0.0                    # 0..1: hands closed round a pistol (set by the rig every pose)
var grip_F := Vector3.FORWARD        # world: barrel direction
var grip_U := Vector3.UP             # world: top of the slide
var grip_P := Vector3.ZERO           # world: where the pistol grip is held (the gun is placed here)
var hand_rest := {}                  # "R"/"L" -> {bone, B0 (rest frame: finger dir, palm normal, cross), HB0}
var curl := {}                       # bone idx -> [side, Vector3 axis in bone-local rest frame, angle]
var after_update: Callable           # e.g. put the officer's pistol in the (now posed) hand

static func _clean(n: String) -> String:
	n = n.get_slice(":", n.get_slice_count(":") - 1)
	var re := RegEx.create_from_string("^mixamorig\\d*_")
	n = re.sub(n, "")
	re = RegEx.create_from_string("_\\d+$")
	return re.sub(n, "")

func setup(visitor: Node3D, path: String) -> void:
	rig = visitor; J = visitor.J
	# measure the procedural body, then hide it
	var lo := INF; var hi := -INF
	for mi: MeshInstance3D in rig.find_children("*", "MeshInstance3D", true, false):
		var bb: AABB = (rig.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		lo = min(lo, bb.position.y); hi = max(hi, bb.end.y)
		mi.visible = false
	model = (load(path) as PackedScene).instantiate()
	rig.add_child(model)
	skel = model.find_children("*", "Skeleton3D", true, false)[0]
	var names := {}
	for b in skel.get_bone_count(): names[_clean(skel.get_bone_name(b))] = b
	bone_ix = names
	# height + facing + feet on the floor: rest pose height of the skinned mesh in rig space
	var mlo := INF; var mhi := -INF
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
		var bb: AABB = (rig.global_transform.affine_inverse() * mi.global_transform) * mi.get_aabb()
		mlo = min(mlo, bb.position.y); mhi = max(mhi, bb.end.y)
	var s: float = (hi - lo) / max(mhi - mlo, 0.01)
	model.scale = Vector3.ONE * s
	# which way does the procedural rig face? the knees bend backwards, toes point forwards:
	# use the line between the shoulders (rig left -> right) and up to get forward
	var to_rig := rig.global_transform.affine_inverse()
	var side: Vector3 = (to_rig * (J.shR as Node3D).global_position) - (to_rig * (J.shL as Node3D).global_position)
	var mside: Vector3 = (to_rig * (skel.global_transform * skel.get_bone_global_rest(names.RightArm).origin)) - (to_rig * (skel.global_transform * skel.get_bone_global_rest(names.LeftArm).origin))
	var ang := atan2(mside.x, mside.z) - atan2(side.x, side.z)
	model.rotation.y = -ang
	# re-measure after scale/rotation and drop the feet onto the rig's floor, hips over hips
	var hip_m: Vector3 = to_rig * (skel.global_transform * skel.get_bone_global_rest(names.Hips).origin)
	var hip_r: Vector3 = to_rig * (J.hips as Node3D).global_position
	model.position += Vector3(hip_r.x - hip_m.x, lo - mlo * s, hip_r.z - hip_m.z)
	# bones, parents first
	var depth := {}
	for b in skel.get_bone_count():
		var d := 0; var p := skel.get_bone_parent(b)
		while p >= 0: d += 1; p = skel.get_bone_parent(p)
		depth[b] = d
	for b in skel.get_bone_count(): order.append(b)
	order.sort_custom(func(a, c): return depth[a] < depth[c])
	for b in skel.get_bone_count(): rest_local[b] = skel.get_bone_rest(b).basis.orthonormalized()
	# line every mapped bone up with its joint in the rest pose
	var sk_inv := skel.global_transform.basis.orthonormalized().inverse()
	for jn in MAP:
		var m: Array = MAP[jn]
		if not J.has(jn) or not names.has(m[0]): continue
		var b: int = names[m[0]]
		var Bg: Basis = skel.get_bone_global_rest(b).basis.orthonormalized()
		var Mb := Bg
		if m[1] != "" and J.has(m[1]) and names.has(m[2]):
			var bd: Vector3 = (skel.get_bone_global_rest(names[m[2]]).origin - skel.get_bone_global_rest(b).origin).normalized()
			var jd: Vector3 = (sk_inv * ((J[m[1]] as Node3D).global_position - (J[jn] as Node3D).global_position)).normalized()
			Mb = Basis(_arc(bd, jd)) * Bg
		var R0: Basis = sk_inv * (J[jn] as Node3D).global_transform.basis.orthonormalized()
		offset[b] = R0.inverse() * Mb
		bone_joint[b] = jn
	# hands and fingers, for the pistol grip
	var down_sk: Vector3 = (sk_inv * Vector3.DOWN).normalized()
	for sd in ["R", "L"]:
		var hside := "Right" if sd == "R" else "Left"
		if not names.has(hside + "Hand") or not names.has(hside + "HandMiddle1"): continue
		var hb: int = names[hside + "Hand"]
		var d0: Vector3 = (skel.get_bone_global_rest(names[hside + "HandMiddle1"]).origin - skel.get_bone_global_rest(hb).origin).normalized()
		var n0: Vector3 = (down_sk - d0 * down_sk.dot(d0)).normalized()          # T-pose palms face the floor
		hand_rest[sd] = {bone = hb, B0 = Basis(d0, n0, d0.cross(n0)), HB0 = skel.get_bone_global_rest(hb).basis.orthonormalized()}
		for f in GRIP_CURL[sd]:
			for k in 3:
				var bn: String = hside + "Hand" + f + str(k + 1)
				var bn2: String = hside + "Hand" + f + str(k + 2)
				if not names.has(bn): continue
				var b: int = names[bn]
				var p0: Vector3 = skel.get_bone_global_rest(b).origin
				var p1: Vector3 = skel.get_bone_global_rest(names[bn2]).origin if names.has(bn2) else p0 + d0 * 0.02
				var fd := (p1 - p0).normalized()
				var nn := n0 if f != "Thumb" else d0.cross(n0) * (-1.0 if sd == "R" else 1.0)
				var axis_sk := fd.cross(nn).normalized()                       # turning about this bends the finger toward the palm
				var axis_local: Vector3 = skel.get_bone_global_rest(b).basis.orthonormalized().inverse() * axis_sk
				curl[b] = [sd, axis_local.normalized(), GRIP_CURL[sd][f][k]]
	hips_bone = names.get("Hips", -1)
	if hips_bone >= 0:
		hips_rest = skel.get_bone_global_rest(hips_bone).origin
		hips_rest_joint = skel.global_transform.affine_inverse() * (J.hips as Node3D).global_position
	process_priority = 100
	update()

static func _arc(a: Vector3, b: Vector3) -> Quaternion:
	var d := a.dot(b)
	if d > 0.99999: return Quaternion.IDENTITY
	if d < -0.99999:
		var ax := a.cross(Vector3.RIGHT)
		if ax.length_squared() < 1e-6: ax = a.cross(Vector3.UP)
		return Quaternion(ax.normalized(), PI)
	return Quaternion(a.cross(b).normalized(), acos(clamp(d, -1.0, 1.0)))

## the hand turned to hold the pistol: shooting hand palm-in against the grip, wrist straight
## behind it; support hand wrapped round it from the other side
func _hand_target(sd: String, sk_inv: Basis) -> Basis:
	var hd := _hand_dirs(sd); var d: Vector3 = hd[0]; var n: Vector3 = hd[1]
	d = (sk_inv * d).normalized(); n = sk_inv * n; n = (n - d * n.dot(d)).normalized()
	var hr: Dictionary = hand_rest[sd]
	return Basis(d, n, d.cross(n)) * (hr.B0 as Basis).inverse() * (hr.HB0 as Basis)

## gun frame in world space: F barrel, U slide-up, L the gun's left
func _gun_frame() -> Array:
	var F := grip_F.normalized(); var U := (grip_U - F * grip_U.dot(F)).normalized()
	return [F, U, U.cross(F)]

## hand directions in world space: d = wrist -> knuckles, n = palm normal
func _hand_dirs(sd: String) -> Array:
	var fr := _gun_frame(); var F: Vector3 = fr[0]; var U: Vector3 = fr[1]; var L: Vector3 = fr[2]
	if sd == "R": return [(F * 0.88 - U * 0.42 - L * 0.12).normalized(), (L * 0.92 - U * 0.25).normalized()]
	return [(F * 0.6 - U * 0.5 - L * 0.62).normalized(), (-L * 0.85 + U * 0.35 - F * 0.1).normalized()]

## where each hand bone (the wrist) must be so the palm closes on the grip at grip_P
var grip_off_r := Vector3(0.055, 0.035, 0.0)     # (along d, along n, along U) metres from wrist to grip
var grip_off_l := Vector3(0.065, 0.025, 0.0)
func _wrist_target(sd: String) -> Vector3:
	var hd := _hand_dirs(sd); var d: Vector3 = hd[0]; var n: Vector3 = hd[1]
	var fr := _gun_frame(); var U: Vector3 = fr[1]; var L: Vector3 = fr[2]
	var o: Vector3 = grip_off_r if sd == "R" else grip_off_l
	# the support hand closes over the shooting hand's fingers from the other side
	var base := grip_P if sd == "R" else fist_world() + L * 0.03 - U * 0.03 - grip_F.normalized() * 0.005
	return base - d * o.x - n * o.y - U * o.z

## exact two-bone IK on the skinned arms (the procedural rig's arms are a little longer than the
## model's, so its wrists don't land where the model's hands do), then turn the hands onto the grip
func _grip_ik() -> void:
	_reachable_grip()
	var inv := skel.global_transform.affine_inverse()
	var down_sk: Vector3 = (skel.global_transform.basis.orthonormalized().inverse() * Vector3.DOWN).normalized()
	for sd in ["R", "L"]:
		if not hand_rest.has(sd): continue
		var side := "Right" if sd == "R" else "Left"
		if not (bone_ix.has(side + "Arm") and bone_ix.has(side + "ForeArm")): continue
		var ba: int = bone_ix[side + "Arm"]; var bf: int = bone_ix[side + "ForeArm"]; var bh: int = hand_rest[sd].bone
		var A := skel.get_bone_global_pose(ba); var Fg := skel.get_bone_global_pose(bf); var Hg := skel.get_bone_global_pose(bh)
		var T: Vector3 = Hg.origin.lerp(inv * _wrist_target(sd), grip_w)
		var a := A.origin.distance_to(Fg.origin); var b := Fg.origin.distance_to(Hg.origin)
		var dv := T - A.origin; var dist: float = clamp(dv.length(), 0.01, a + b - 0.001); var dir := dv.normalized()
		var x := (a * a - b * b + dist * dist) / (2.0 * dist); var h := sqrt(max(a * a - x * x, 0.0))
		var side_sk: Vector3 = (Fg.origin - A.origin).cross(down_sk)
		var pole := down_sk * 1.0 + (A.origin - skel.get_bone_global_pose(bone_ix.get("Spine2", 0)).origin).normalized() * 0.5
		var pv := pole - dir * pole.dot(dir)
		if pv.length_squared() < 1e-6: pv = down_sk
		var E := A.origin + dir * x + pv.normalized() * h
		var q1 := Quaternion(SkinDriver._arc((Fg.origin - A.origin).normalized(), (E - A.origin).normalized()))
		var A2 := Basis(q1) * A.basis
		var F1 := Basis(q1) * Fg.basis
		var H1: Vector3 = E + Basis(q1) * (Hg.origin - Fg.origin)
		var q2 := Quaternion(SkinDriver._arc((H1 - E).normalized(), (A.origin + dir * dist - E).normalized()))
		var F2 := Basis(q2) * F1
		var pa := skel.get_bone_parent(ba)
		var PA: Basis = skel.get_bone_global_pose(pa).basis if pa >= 0 else Basis.IDENTITY
		skel.set_bone_pose_rotation(ba, (PA.orthonormalized().inverse() * A2.orthonormalized()).get_rotation_quaternion())
		skel.set_bone_pose_rotation(bf, (A2.orthonormalized().inverse() * F2.orthonormalized()).get_rotation_quaternion())
		var want := _hand_target(sd, skel.global_transform.basis.orthonormalized().inverse())
		var cur := (F2 * (Fg.basis.inverse() * Hg.basis)).orthonormalized()
		var hand_g := Basis(cur.get_rotation_quaternion().slerp(want.get_rotation_quaternion(), grip_w))
		skel.set_bone_pose_rotation(bh, (F2.orthonormalized().inverse() * hand_g).get_rotation_quaternion())

## the rig asks for the grip where ITS (longer) arms would hold it; move it to where this model's
## arms reach with the elbows a little soft: in front of the chest, centred, just below the shoulders
func _reachable_grip() -> void:
	if not (bone_ix.has("RightArm") and bone_ix.has("LeftArm") and bone_ix.has("RightForeArm") and bone_ix.has("RightHand")): return
	var sr := bone_world("RightArm"); var sl := bone_world("LeftArm")
	var reach := sr.distance_to(bone_world("RightForeArm")) + bone_world("RightForeArm").distance_to(bone_world("RightHand"))
	var F := grip_F.normalized()
	var rgt := (sr - sl); rgt = (rgt - F * rgt.dot(F)).normalized()
	grip_P = (sr + sl) * 0.5 + F * reach * 0.93 + Vector3.DOWN * 0.07 - rgt * 0.02

## centre of the closed shooting hand, where the pistol grip goes (world)
var grip_seat := Vector3(-0.012, -0.035, 0.0)     # (along F, along U, along L) fine-tune of the seat in the fist
func fist_world() -> Vector3:
	var h := bone_world("RightHand")
	var k := (bone_world("RightHandIndex1") + bone_world("RightHandMiddle1") + bone_world("RightHandRing1") + bone_world("RightHandPinky1")) * 0.25
	var tips := (bone_world("RightHandIndex3") + bone_world("RightHandMiddle3") + bone_world("RightHandRing3") + bone_world("RightHandPinky3")) * 0.25
	var fr := _gun_frame()
	return (h * 0.15 + k * 0.45 + tips * 0.4) + fr[0] * grip_seat.x + fr[1] * grip_seat.y + fr[2] * grip_seat.z

## world position of a bone of the skinned model ("RightHand", "Head"...)
func bone_world(bone: String) -> Vector3:
	if skel == null or not bone_ix.has(bone): return Vector3.ZERO
	return skel.global_transform * skel.get_bone_global_pose(bone_ix[bone]).origin

## the procedural joints follow the ragdoll bodies from now on
func follow_ragdoll(bodies: Dictionary) -> void:
	for part in bodies:
		var jn: String = RAG_ANCHOR.get(part, "")
		if jn == "" or not J.has(jn): continue
		var body: Node3D = bodies[part]
		rag[part] = [body, body.global_transform.affine_inverse() * (J[jn] as Node3D).global_transform]
	if bodies.has("torso"):
		rag_hips = (bodies.torso as Node3D).global_transform.affine_inverse() * (J.hips as Node3D).global_transform

func _process(_dt: float) -> void:
	update()

func update() -> void:
	if skel == null or not is_instance_valid(rig): return
	if not rag.is_empty():
		if rag.has("torso") and is_instance_valid(rag.torso[0]): (J.hips as Node3D).global_transform = (rag.torso[0] as Node3D).global_transform * rag_hips
		for part in ["torso", "head", "thighL", "thighR", "shinL", "shinR", "armL", "armR", "foreL", "foreR"]:
			if not rag.has(part) or not is_instance_valid(rag[part][0]): continue
			(J[RAG_ANCHOR[part]] as Node3D).global_transform = (rag[part][0] as Node3D).global_transform * (rag[part][1] as Transform3D)
	var sk_xf := skel.global_transform
	var sk_inv := sk_xf.basis.orthonormalized().inverse()
	var G := {}
	for b in order:
		var p := skel.get_bone_parent(b)
		var pg: Basis = G[p] if p >= 0 else Basis.IDENTITY
		var g: Basis
		if bone_joint.has(b):
			g = (sk_inv * (J[bone_joint[b]] as Node3D).global_transform.basis.orthonormalized()) * offset[b]
			skel.set_bone_pose_rotation(b, (pg.inverse() * g).get_rotation_quaternion())
		else:
			g = pg * rest_local[b]
			var loc: Basis = rest_local[b]
			if grip_w > 0.001 and curl.has(b):
				var c: Array = curl[b]
				loc = loc * Basis(c[1], c[2] * grip_w)
				g = pg * loc
			skel.set_bone_pose_rotation(b, loc.get_rotation_quaternion())
		G[b] = g
	if hips_bone >= 0:
		var now: Vector3 = sk_xf.affine_inverse() * (J.hips as Node3D).global_position
		var target: Vector3 = hips_rest + (now - hips_rest_joint)
		var p := skel.get_bone_parent(hips_bone)
		var pgx: Transform3D = skel.get_bone_global_pose(p) if p >= 0 else Transform3D.IDENTITY
		skel.set_bone_pose_position(hips_bone, pgx.affine_inverse() * target)
	if grip_w > 0.001 and not hand_rest.is_empty() and rag.is_empty(): _grip_ik()
	if after_update.is_valid(): after_update.call()
