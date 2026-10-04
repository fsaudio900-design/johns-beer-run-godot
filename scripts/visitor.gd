extends Node3D
## The procedural "visitor" rig exported from the web build (also reused later for Dale the
## clerk and the officer). Joints are the J_* nodes; pose() is a port of the web animation:
## idle breathing, walk cycle, knocking, waving and hands-up.
##
## The visitor himself is invincible: he is never added to any shootable group.

@export var model_path := "res://assets/chars/Visitor.glb"
@export var skin_path := ""          # optional skinned character worn over the procedural rig
var skin: SkinDriver
var J := {}
var anim := "idle"
var t := 0.0
var k_t := 0.0
var blend := {knock = 0.0, walk = 0.0, wave = 0.0, hands = 0.0, cuff = 0.0}
var aiming := false          # arms up on a two-handed pistol grip, independent of the legs (walk or idle)
var aim_pitch := 0.0         # radians, + = aiming up
var aim_w := 0.0
var flinch := 0.0            # a hit: knocked back a step
var hips_y := 0.95

func _ready() -> void:
	var m: Node3D = get_node_or_null("Model")
	if m == null:
		m = (load(model_path) as PackedScene).instantiate(); add_child(m)
	for node in m.find_children("J_*", "", true, false):
		J[String(node.name).trim_prefix("J_")] = node
	if J.has("hips"): hips_y = J.hips.position.y
	print("[visitor] ", model_path.get_file(), " joints ", J.size())
	for mi: MeshInstance3D in m.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON
	if skin_path != "":
		skin = SkinDriver.new(); skin.name = "Skin"; add_child(skin); skin.setup(self, skin_path)

func set_anim(a: String) -> void:
	if a == "knock" and anim != "knock": k_t = -0.5
	anim = a

func _j(n: String) -> Node3D: return J.get(n)

func pose(dt: float) -> void:
	t += dt; k_t += dt
	for k in blend: blend[k] = lerp(blend[k], 1.0 if anim == k else 0.0, 1.0 - exp(-dt * 6))
	var br := sin(t * 1.7) * 0.012
	var hips := _j("hips"); var spine := _j("spine"); var chest := _j("chest"); var head := _j("head")
	if hips == null: return
	hips.position.y = hips_y + br * 0.4
	if spine: spine.rotation.x = 0.03 + br * 0.3
	if chest: chest.rotation.x = br
	var hx := -0.03 + sin(t * 0.6) * 0.03; var hy := sin(t * 0.37) * 0.12
	rotation.z = sin(t * 0.5) * 0.008
	var aLx := 0.05; var aLz := 0.12; var eLx := -0.25; var aRx := 0.05; var aRz := -0.12; var eRx := -0.25
	# walk
	var w: float = blend.walk; var ph := t * 6.2; var sw := sin(ph)
	_rx("thighL", sw * 0.55 * w); _rx("thighR", -sw * 0.55 * w)
	_rx("kneeL", max(0.0, -cos(ph)) * 0.8 * w); _rx("kneeR", max(0.0, cos(ph)) * 0.8 * w)
	hips.position.y -= abs(cos(ph)) * 0.025 * w
	aLx = lerp(aLx, -sw * 0.45, w); aRx = lerp(aRx, sw * 0.45, w); eLx = lerp(eLx, -0.35, w); eRx = lerp(eRx, -0.35, w)
	# knock: right arm up, wrist rapping three times then a pause
	var k: float = blend.knock; var kc := fmod(k_t, 2.2)
	var rap: float = max(0.0, sin(kc / 0.3 * PI * 2)) if (k_t >= 0 and kc < 0.9) else 0.0
	aRx = lerp(aRx, -1.25, k); aRz = lerp(aRz, -0.05, k); eRx = lerp(eRx, -1.2 + rap * 0.35, k)
	_rx("wrR", lerp(0.0, 0.35 - rap * 0.5, k))
	for i in 4: _rx("fR%d" % i, lerp(0.25, 1.5, k))
	hy = lerp(hy, 0.05, k)
	# wave
	var v: float = blend.wave
	aLx = lerp(aLx, -0.3, v); aLz = lerp(aLz, 2.35, v); eLx = lerp(eLx, -0.35, v)
	var elL := _j("elL")
	if elL: elL.rotation.z = lerp(0.0, sin(t * 7) * 0.35, v)
	# hands up
	var hu: float = blend.hands
	aLx = lerp(aLx, -0.3, hu); aLz = lerp(aLz, 2.75, hu); eLx = lerp(eLx, -1.0, hu)
	aRx = lerp(aRx, -0.3, hu); aRz = lerp(aRz, -2.75, hu); eRx = lerp(eRx, -1.0, hu)
	if hu > 0.01: hx += 0.12 * hu; hips.position.y -= 0.03 * hu
	# cuffing: both hands forward and down onto the wrists in front of him
	var cf: float = blend.cuff
	aLx = lerp(aLx, -0.95, cf); aLz = lerp(aLz, -0.3, cf); eLx = lerp(eLx, -0.7, cf)
	aRx = lerp(aRx, -0.95, cf); aRz = lerp(aRz, 0.3, cf); eRx = lerp(eRx, -0.7, cf)
	hx = lerp(hx, 0.35, cf)
	# two-handed pistol aim
	aim_w = lerp(aim_w, 1.0 if aiming else 0.0, 1.0 - exp(-dt * 9))
	var a := aim_w; var up := -(PI / 2 + aim_pitch)
	aRx = lerp(aRx, up, a); aRz = lerp(aRz, 0.1, a); eRx = lerp(eRx, -0.08, a)
	aLx = lerp(aLx, up + 0.12, a); aLz = lerp(aLz, -0.42, a); eLx = lerp(eLx, -0.45, a)
	hx = lerp(hx, -aim_pitch * 0.5 + 0.08, a); hy = lerp(hy, 0.0, a)
	# flinch from a bullet
	flinch = max(0.0, flinch - dt * 2.2)
	if flinch > 0:
		if spine: spine.rotation.x -= 0.35 * flinch
		hx -= 0.25 * flinch
	if head: head.rotation = Vector3(hx, hy, 0)
	_set_rot("shL", Vector3(aLx, 0, aLz)); _rx("elL", eLx)
	_set_rot("shR", Vector3(aRx, 0, aRz)); _rx("elR", eRx)
	if k < 0.001:
		for i in 4: _rx("fR%d" % i, 0.25)
	for i in 4: _rx("fL%d" % i, lerp(0.25, 0.0, v))

func _rx(n: String, a: float) -> void:
	var j := _j(n)
	if j: j.rotation.x = a

func _set_rot(n: String, r: Vector3) -> void:
	var j := _j(n)
	if j: j.rotation = r
