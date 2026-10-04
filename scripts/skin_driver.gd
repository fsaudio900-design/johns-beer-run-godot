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
	fL0 = ["LeftHandIndex1", "", ""], fL1 = ["LeftHandMiddle1", "", ""], fL2 = ["LeftHandRing1", "", ""], fL3 = ["LeftHandPinky1", "", ""],
	fR0 = ["RightHandIndex1", "", ""], fR1 = ["RightHandMiddle1", "", ""], fR2 = ["RightHandRing1", "", ""], fR3 = ["RightHandPinky1", "", ""],
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
			skel.set_bone_pose_rotation(b, rest_local[b].get_rotation_quaternion())
		G[b] = g
	if hips_bone >= 0:
		var now: Vector3 = sk_xf.affine_inverse() * (J.hips as Node3D).global_position
		var target: Vector3 = hips_rest + (now - hips_rest_joint)
		var p := skel.get_bone_parent(hips_bone)
		var pgx: Transform3D = skel.get_bone_global_pose(p) if p >= 0 else Transform3D.IDENTITY
		skel.set_bone_pose_position(hips_bone, pgx.affine_inverse() * target)
