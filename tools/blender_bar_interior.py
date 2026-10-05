"""Build the dive-bar interior in Blender and export it as BarInterior.glb.

Run inside Blender (5.x):  exec(open(r'...\\blender_bar_interior.py').read())
with TEX (texture folder) and OUT (glb path) set beforehand, or edit the defaults below.

Coordinates: everything is written in the bar's own glTF frame (metres, Y up, the street front
at z = 0 facing -z, the back wall at z = 9.625), the frame Bar.glb uses, and converted to
Blender's Z-up frame (X = x, Y = -z, Z = y) here, so the exported GLB sits inside Bar.glb
with no offset.

Objects (each joined from many parts):
  Interior_Solid       walls, floor, ceiling, counter, furniture: gets collision in the game
  Interior_Decor_nocol bottles, signs, lamps, small things: no collision
  Interior_Neon_nocol  the neon signs (alpha-blended, emissive)
"""
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

TEX = globals().get('TEX', r'C:\Users\aliso\Documents\JohnsBeerRun_Blender\textures')
OUT = globals().get('OUT', r'C:\Users\aliso\Documents\JohnsBeerRun_Blender\export\BarInterior.glb')
COLL = 'BarInterior'

# ------------------------------------------------------------------ layout (bar-local metres)
XI = 5.37            # inner faces of the side walls (outer sheets at +-5.569)
XO = 5.55
ZF = 0.25            # inner face of the main front wall
ZF0 = 0.01           # its back, just behind the facade sheet
XSTEP = -2.57        # step wall into the wing
ZW = -1.23           # inner face of the wing's front wall
ZB = 9.42            # inner face of the back wall
ZBO = 9.60
H = 3.6              # ceiling
FL = 0.06            # floor top
WAIN = 1.1           # wainscot height
DOOR_X0, DOOR_X1, DOOR_H = -0.666, 0.40, 2.25   # inner opening (the door is x -0.592..0.258)

# ------------------------------------------------------------------ scene reset
if COLL in bpy.data.collections:
    c = bpy.data.collections[COLL]
    for o in list(c.objects): bpy.data.objects.remove(o, do_unlink=True)
else:
    c = bpy.data.collections.new(COLL); bpy.context.scene.collection.children.link(c)
for m in list(bpy.data.meshes):
    if m.users == 0: bpy.data.meshes.remove(m)
COL = bpy.data.collections[COLL]

def B(x, y, z): return Vector((x, -z, y))          # bar-local -> Blender

# ------------------------------------------------------------------ materials
_img = {}
def img(name, non_color=False):
    key = (name, non_color)
    if key not in _img:
        im = bpy.data.images.load(os.path.join(TEX, name), check_existing=True)
        if non_color: im.colorspace_settings.name = 'Non-Color'
        _img[key] = im
    return _img[key]

UVS = {}     # material -> (metres per tile u, v, rotate)
def mat(name, color=(0.5, 0.5, 0.5), rough=0.6, metal=0.0, tex=None, nrm=None, emit=None, emit_color=None,
        alpha=False, uv=(1.0, 1.0, False), nstr=1.0):
    UVS[name] = uv
    m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree; nt.nodes.clear()
    out = nt.nodes.new('ShaderNodeOutputMaterial'); out.location = (400, 0)
    p = nt.nodes.new('ShaderNodeBsdfPrincipled'); p.location = (100, 0)
    nt.links.new(p.outputs['BSDF'], out.inputs['Surface'])
    p.inputs['Base Color'].default_value = (*color, 1.0)
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    if tex:
        t = nt.nodes.new('ShaderNodeTexImage'); t.image = img(tex); t.location = (-400, 200)
        nt.links.new(t.outputs['Color'], p.inputs['Base Color'])
        if alpha:
            nt.links.new(t.outputs['Alpha'], p.inputs['Alpha'])
            try: m.surface_render_method = 'BLENDED'
            except Exception: m.blend_method = 'BLEND'
    if nrm:
        t = nt.nodes.new('ShaderNodeTexImage'); t.image = img(nrm, True); t.location = (-400, -200)
        nm = nt.nodes.new('ShaderNodeNormalMap'); nm.location = (-150, -200); nm.inputs['Strength'].default_value = nstr
        nt.links.new(t.outputs['Color'], nm.inputs['Color']); nt.links.new(nm.outputs['Normal'], p.inputs['Normal'])
    if emit:
        t = nt.nodes.new('ShaderNodeTexImage'); t.image = img(emit); t.location = (-400, -450)
        nt.links.new(t.outputs['Color'], p.inputs['Emission Color'])
        p.inputs['Emission Strength'].default_value = 1.0
    elif emit_color:
        p.inputs['Emission Color'].default_value = (*emit_color, 1.0)
        p.inputs['Emission Strength'].default_value = 1.0
    return m

M = {}
def defmats():
    M['floor'] = mat('Bar_FloorWood', tex='floor_wood.jpg', nrm='floor_wood_n.jpg', rough=0.72, uv=(1.4, 1.4, False))
    M['panel'] = mat('Bar_PanelWood', tex='panel_wood.jpg', nrm='panel_wood_n.jpg', rough=0.65, uv=(0.7, 1.3, False))
    M['bartop'] = mat('Bar_TopWood', tex='bar_wood.jpg', nrm='bar_wood_n.jpg', rough=0.3, uv=(1.6, 0.8, True), nstr=0.6)
    M['tablewood'] = mat('Bar_TableWood', tex='bar_wood.jpg', nrm='bar_wood_n.jpg', rough=0.35, uv=(1.6, 0.8, False), nstr=0.6)
    M['brick'] = mat('Bar_BrickInside', tex='brick_dark.jpg', nrm='brick_dark_n.jpg', rough=0.92, uv=(2.263, 2.053, False))
    M['tin'] = mat('Bar_CeilingTin', tex='ceiling_tin.jpg', nrm='ceiling_tin_n.jpg', rough=0.55, metal=0.4, uv=(0.61, 0.61, False))
    M['felt'] = mat('Bar_Felt', tex='felt.jpg', rough=1.0, uv=(0.6, 0.6, False))
    M['vinyl'] = mat('Bar_VinylRed', tex='vinyl_red.jpg', nrm='vinyl_red_n.jpg', rough=0.4, uv=(0.5, 0.5, False), nstr=0.45)
    M['trim'] = mat('Bar_DarkTrim', color=(0.06, 0.035, 0.02), rough=0.5)
    M['chrome'] = mat('Bar_Chrome', color=(0.8, 0.8, 0.82), rough=0.18, metal=1.0)
    M['brass'] = mat('Bar_Brass', color=(0.72, 0.52, 0.22), rough=0.3, metal=1.0)
    M['blackmetal'] = mat('Bar_BlackMetal', color=(0.025, 0.025, 0.025), rough=0.45, metal=0.6)
    M['duct'] = mat('Bar_Duct', color=(0.42, 0.42, 0.43), rough=0.45, metal=0.85)
    M['mirror'] = mat('Bar_Mirror', color=(0.55, 0.52, 0.48), rough=0.06, metal=1.0)
    M['rubber'] = mat('Bar_Rubber', color=(0.03, 0.03, 0.03), rough=0.85)
    M['amber'] = mat('Bar_GlassAmber', color=(0.32, 0.12, 0.02), rough=0.08, metal=0.2)
    M['green'] = mat('Bar_GlassGreen', color=(0.04, 0.17, 0.06), rough=0.08, metal=0.2)
    M['clear'] = mat('Bar_GlassClear', color=(0.55, 0.6, 0.58), rough=0.05, metal=0.3)
    M['beer'] = mat('Bar_Beer', color=(0.75, 0.42, 0.06), rough=0.15)
    M['labels'] = mat('Bar_Labels', tex='labels.jpg', rough=0.6)
    M['door'] = mat('Bar_DoorPaint', color=(0.12, 0.17, 0.13), rough=0.55)
    M['steel'] = mat('Bar_SteelDoor', color=(0.32, 0.33, 0.34), rough=0.5, metal=0.6)
    M['tape'] = mat('Bar_Tape', color=(0.8, 0.65, 0.05), rough=0.7)
    M['shade'] = mat('Bar_LampShade', color=(0.05, 0.16, 0.08), rough=0.4, metal=0.5)
    M['bulb'] = mat('Bar_Bulb', color=(1.0, 0.85, 0.6), rough=0.3, emit_color=(1.0, 0.72, 0.4))
    M['diffuser'] = mat('Bar_LampDiffuser', color=(0.85, 0.8, 0.65), rough=0.5, emit_color=(0.5, 0.45, 0.32))
    M['tvbody'] = mat('Bar_TVBody', color=(0.02, 0.02, 0.022), rough=0.35)
    M['tv'] = mat('Bar_TVScreen', tex='tv.jpg', emit='tv.jpg', rough=0.2)
    M['jukebox'] = mat('Bar_JukeboxFront', tex='jukebox.jpg', emit='jukebox_e.jpg', rough=0.3)
    M['jukebody'] = mat('Bar_JukeboxBody', color=(0.22, 0.07, 0.04), rough=0.3, metal=0.2)
    M['dart'] = mat('Bar_Dartboard', tex='dartboard.png', rough=0.8, alpha=True)
    M['chalk'] = mat('Bar_Chalkboard', tex='chalkboard.jpg', rough=0.9)
    for k in ('poster_band', 'poster_league', 'sign_cash', 'sign_minors', 'sign_staff', 'sign_restroom'):
        M[k] = mat('Bar_' + k.title().replace('_', ''), tex=k + '.jpg', rough=0.85)
    for k in ('lumberjack', 'coldbeer', 'open', 'cocktails'):
        M['neon_' + k] = mat('Neon_' + k.title(), tex='neon_%s.png' % k, emit='neon_%s_e.jpg' % k, alpha=True, rough=0.4)
    for k, col in (('white', (0.9, 0.88, 0.8)), ('red', (0.7, 0.05, 0.03)), ('yellow', (0.9, 0.7, 0.05)), ('blue', (0.05, 0.1, 0.6)),
                   ('black', (0.02, 0.02, 0.02)), ('green', (0.03, 0.4, 0.12)), ('orange', (0.9, 0.35, 0.03)), ('purple', (0.3, 0.05, 0.4)),
                   ('maroon', (0.35, 0.03, 0.04))):
        M['ball_' + k] = mat('Bar_Ball' + k.title(), color=col, rough=0.12)
    M['cue'] = mat('Bar_Cue', color=(0.55, 0.38, 0.18), rough=0.35)
    M['paper'] = mat('Bar_Paper', color=(0.85, 0.82, 0.72), rough=0.9)
    M['register'] = mat('Bar_Register', color=(0.12, 0.12, 0.13), rough=0.4, metal=0.3)
    M['exit'] = mat('Bar_ExitSign', color=(0.9, 0.08, 0.05), rough=0.3, emit_color=(1.0, 0.1, 0.05))
    M['cooler'] = mat('Bar_CoolerGlass', color=(0.05, 0.07, 0.08), rough=0.05, metal=0.5, emit_color=(0.05, 0.09, 0.1))
    M['handle_r'] = mat('Bar_TapRed', color=(0.6, 0.06, 0.04), rough=0.3)
    M['handle_g'] = mat('Bar_TapGold', color=(0.8, 0.6, 0.15), rough=0.3, metal=0.6)
    M['handle_k'] = mat('Bar_TapBlack', color=(0.03, 0.03, 0.03), rough=0.3)
    M['handle_w'] = mat('Bar_TapWood', color=(0.35, 0.18, 0.08), rough=0.5)
defmats()

# ------------------------------------------------------------------ part builder
PARTS = {'solid': [], 'decor': [], 'neon': []}

def _uv_world(bm, mname, planar=None):
    """box-map every face from its position (tiling textures), or planar-map faces that face `planar`"""
    uvl = bm.loops.layers.uv.verify()
    su, sv, rot = UVS.get(mname, (1, 1, False))
    for f in bm.faces:
        n = f.normal
        if planar is not None and n.dot(planar['n']) > 0.9:
            for l in f.loops:
                p = l.vert.co - planar['o']
                l[uvl].uv = (p.dot(planar['u']) / planar['su'], p.dot(planar['v']) / planar['sv'])
            continue
        ax = max(range(3), key=lambda i: abs(n[i]))
        for l in f.loops:
            x, y, z = l.vert.co          # Blender: x, y=-z_local, z=y_local
            if ax == 2: u, v = x, y      # horizontal faces
            elif ax == 0: u, v = -y if n[0] > 0 else y, z
            else: u, v = x if n[1] < 0 else -x, z
            if rot: u, v = v, u
            l[uvl].uv = (u / su, v / sv)

def part(name, bm, mname, group='solid', uv=True, planar=None, smooth=False):
    if uv: _uv_world(bm, M[mname].name if mname in M else mname, planar)
    if smooth:
        for f in bm.faces: f.smooth = abs(f.normal.z) < 0.7 if smooth == 'side' else True
        for e in bm.edges:
            if len(e.link_faces) == 2 and e.link_faces[0].smooth != e.link_faces[1].smooth: e.smooth = False
    me = bpy.data.meshes.new(name); bm.to_mesh(me); bm.free()
    me.materials.append(M[mname])
    ob = bpy.data.objects.new(name, me); COL.objects.link(ob)
    PARTS[group].append(ob)
    return ob

def box(name, lo, hi, mname, group='solid', bevel=0.0, planar=None, faces=None):
    """axis-aligned box in bar-local coords lo=(x0,y0,z0) hi=(x1,y1,z1)"""
    bm = bmesh.new()
    a, b = B(*lo), B(*hi)
    c0 = Vector((min(a.x, b.x), min(a.y, b.y), min(a.z, b.z))); c1 = Vector((max(a.x, b.x), max(a.y, b.y), max(a.z, b.z)))
    v = [bm.verts.new((c1.x if i & 1 else c0.x, c1.y if i & 2 else c0.y, c1.z if i & 4 else c0.z)) for i in range(8)]
    for q in ((0, 2, 3, 1), (4, 5, 7, 6), (0, 1, 5, 4), (2, 6, 7, 3), (0, 4, 6, 2), (1, 3, 7, 5)):
        bm.faces.new([v[i] for i in q])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    if bevel > 0:
        bmesh.ops.bevel(bm, geom=list(bm.edges), offset=bevel, segments=2, affect='EDGES', profile=0.5, clamp_overlap=True)
    bm.normal_update()
    return part(name, bm, mname, group, planar=planar)

def cyl(name, c, r, h, mname, group='solid', axis='y', seg=16, r2=None, cap=True, planar=None):
    """cylinder (or cone with r2) starting at bar-local point c, length h along axis"""
    bm = bmesh.new()
    bmesh.ops.create_cone(bm, cap_ends=cap, cap_tris=False, segments=seg, radius1=r, radius2=r if r2 is None else r2, depth=h)
    # created along Blender Z, centred: move base to 0
    bmesh.ops.translate(bm, verts=bm.verts, vec=(0, 0, h / 2))
    R = {'y': Matrix.Identity(3), 'x': Matrix.Rotation(math.pi / 2, 3, 'Y'), 'z': Matrix.Rotation(math.pi / 2, 3, 'X')}[axis]
    bmesh.ops.rotate(bm, verts=bm.verts, cent=(0, 0, 0), matrix=R)
    bmesh.ops.translate(bm, verts=bm.verts, vec=B(*c))
    bm.normal_update()
    return part(name, bm, mname, group, planar=planar, smooth='side' if axis == 'y' else True)

def sphere(name, c, r, mname, group='decor', seg=12):
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=seg, v_segments=seg // 2 + 1, radius=r)
    bmesh.ops.translate(bm, verts=bm.verts, vec=B(*c)); bm.normal_update()
    return part(name, bm, mname, group, smooth=True)

def torus(name, c, R, r, mname, group='solid', seg=20, sseg=6):
    bm = bmesh.new(); rings = []
    for i in range(seg):
        a = 2 * math.pi * i / seg; ring = []
        for j in range(sseg):
            b = 2 * math.pi * j / sseg
            d = R + r * math.cos(b)
            ring.append(bm.verts.new(B(c[0] + d * math.cos(a), c[1] + r * math.sin(b), c[2] + d * math.sin(a))))
        rings.append(ring)
    for i in range(seg):
        for j in range(sseg):
            a0, a1 = rings[i], rings[(i + 1) % seg]
            bm.faces.new([a0[j], a1[j], a1[(j + 1) % sseg], a0[(j + 1) % sseg]])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces); bm.normal_update()
    return part(name, bm, mname, group, smooth=True)

def plane(name, center, normal, w, h, mname, group='decor', uv=(0, 0, 1, 1)):
    """textured quad facing `normal` ('+x','-x','+z','-z','+y','-y'), w along its right, h up"""
    cx, cy, cz = center
    if normal in ('+x', '-x'):
        s = 1 if normal == '+x' else -1
        right = (0, 0, -s); up = (0, 1, 0)
    elif normal in ('+z', '-z'):
        s = 1 if normal == '+z' else -1
        right = (s, 0, 0); up = (0, 1, 0)
    else:                                   # +y: lying flat, image up toward -z
        right = (1, 0, 0); up = (0, 0, -1) if normal == '+y' else (0, 0, 1)
    R = Vector(right) * (w / 2); U = Vector(up) * (h / 2); C = Vector(center)
    bm = bmesh.new()
    vs = [bm.verts.new(B(*(C - R - U))), bm.verts.new(B(*(C + R - U))), bm.verts.new(B(*(C + R + U))), bm.verts.new(B(*(C - R + U)))]
    f = bm.faces.new(vs)
    uvl = bm.loops.layers.uv.verify(); u0, v0, u1, v1 = uv
    for l, t in zip(f.loops, ((u0, v0), (u1, v0), (u1, v1), (u0, v1))): l[uvl].uv = t
    bm.normal_update()
    return part(name, bm, mname, group, uv=False)

def arch_plane(name, xc, y0, w, hrect, z, mname, group='decor', seg=16):
    """flat arched panel facing +z: a rectangle with a half-disc on top, planar-mapped"""
    pts = [(xc - w / 2, y0), (xc + w / 2, y0)]
    for i in range(seg + 1):
        a = math.pi * i / seg
        pts.append((xc + w / 2 * math.cos(a), y0 + hrect + w / 2 * math.sin(a)))
    bm = bmesh.new(); f = bm.faces.new([bm.verts.new(B(x, y, z)) for x, y in pts])
    uvl = bm.loops.layers.uv.verify(); ht = hrect + w / 2
    for l, (x, y) in zip(f.loops, pts): l[uvl].uv = ((x - (xc - w / 2)) / w, (y - y0) / ht)
    bm.normal_update()
    return part(name, bm, mname, group, uv=False)

# ------------------------------------------------------------------ room shell
def wall(name, lo, hi):
    """a wall box: wainscot panelling below WAIN, brick above, a chair rail and a skirting"""
    x0, z0 = lo; x1, z1 = hi
    box(name + '_wain', (x0, 0, z0), (x1, WAIN, z1), 'panel')
    box(name + '_brick', (x0, WAIN, z0), (x1, H, z1), 'brick')

wall('W_Left', (-XO, ZW - 0.18), (-XI, ZBO))
wall('W_Right', (XI, ZF0), (XO, ZBO))
wall('W_Back', (-XO, ZB), (XO, ZBO))
wall('W_Wing', (-XO, ZW - 0.18), (XSTEP + 0.2, ZW))
wall('W_Step', (XSTEP, ZW), (XSTEP + 0.2, ZF))
wall('W_FrontL', (XSTEP, ZF0), (DOOR_X0, ZF))
wall('W_FrontR', (DOOR_X1, ZF0), (XI, ZF))
box('W_FrontHead', (DOOR_X0, DOOR_H, ZF0), (DOOR_X1, H, ZF), 'brick')
box('Pier', (-1.40, 0, ZF), (-1.10, H, 0.62), 'brick')
box('Pier_wain', (-1.42, 0, ZF), (-1.08, WAIN, 0.64), 'panel')

# chair rails + skirting along the visible room walls (inner faces)
RAILS = [((-XI, ZW), (-XI, ZB), '+x'), ((XSTEP, ZW), (-XI, ZW), '+z'), ((XSTEP, ZW), (XSTEP, ZF), '-x'),
         ((XSTEP, ZF), (DOOR_X0, ZF), '+z'), ((DOOR_X1, ZF), (2.2, ZF), '+z'), ((-XI, ZB), (3.6, ZB), '-z'),
         ((XI, 4.0), (XI, 6.6), '-x')]
for i, ((ax, az), (bx, bz), n) in enumerate(RAILS):
    x0, x1 = sorted((ax, bx)); z0, z1 = sorted((az, bz))
    d = 0.035
    if n == '+x': x1 = x0 + d
    elif n == '-x': x0 = x1 - d
    elif n == '+z': z1 = z0 + d
    else: z0 = z1 - d
    box('Rail%d' % i, (x0, WAIN - 0.03, z0), (x1, WAIN + 0.04, z1), 'trim', bevel=0.008)
    box('Skirt%d' % i, (x0, FL, z0), (x1, FL + 0.14, z1), 'trim')

# floor and ceiling
box('Floor_Main', (-XI, -0.1, ZF), (XI, FL, ZB), 'floor')
box('Floor_Wing', (-XI, -0.1, ZW), (XSTEP, FL, ZF), 'floor')
box('Floor_Door', (DOOR_X0, -0.1, ZF0), (DOOR_X1, FL, ZF), 'floor')
box('Ceiling', (-XI, H, ZW), (XI, H + 0.05, ZB), 'tin')
# beams across the ceiling
for i, z in enumerate((1.6, 4.6, 7.6)):
    box('Beam%d' % i, (-XI, H - 0.22, z - 0.11), (XI, H, z + 0.11), 'panel')
# exposed duct along the room, with hangers and two vents
box('Duct', (0.9, H - 0.6, ZF + 0.3), (1.4, H - 0.3, ZB - 0.4), 'duct', group='decor', bevel=0.02)
for i, z in enumerate((1.0, 3.2, 5.9, 8.3)):
    box('DuctHang%d' % i, (1.12, H - 0.3, z - 0.01), (1.18, H, z + 0.01), 'blackmetal', group='decor')
for i, z in enumerate((2.6, 7.0)):
    box('DuctVent%d' % i, (0.95, H - 0.63, z - 0.25), (1.35, H - 0.6, z + 0.25), 'blackmetal', group='decor')

# doorway lining (wood reveal) and trim round the front door inside
box('DoorRevealL', (DOOR_X0, FL, ZF0), (DOOR_X0 + 0.03, DOOR_H, ZF), 'panel')
box('DoorRevealR', (DOOR_X1 - 0.03, FL, ZF0), (DOOR_X1, DOOR_H, ZF), 'panel')
box('DoorRevealT', (DOOR_X0, DOOR_H - 0.03, ZF0), (DOOR_X1, DOOR_H, ZF), 'panel')
# fillers between the facade's door frame and the inner reveal, so no light shows round the door
box('DoorFillR', (0.262, FL, ZF0), (DOOR_X1, DOOR_H, 0.035), 'panel')
box('DoorFillL', (DOOR_X0, FL, ZF0), (-0.594, DOOR_H, 0.035), 'panel')
box('DoorFillT', (DOOR_X0, 2.136, ZF0), (DOOR_X1, DOOR_H, 0.035), 'panel')
box('DoorTrimL', (DOOR_X0 - 0.09, FL, ZF), (DOOR_X0, DOOR_H + 0.09, ZF + 0.025), 'trim', bevel=0.006)
box('DoorTrimR', (DOOR_X1, FL, ZF), (DOOR_X1 + 0.09, DOOR_H + 0.09, ZF + 0.025), 'trim', bevel=0.006)
box('DoorTrimT', (DOOR_X0 - 0.09, DOOR_H, ZF), (DOOR_X1 + 0.09, DOOR_H + 0.09, ZF + 0.025), 'trim', bevel=0.006)
box('DoorMat', (DOOR_X0 + 0.05, FL, ZF + 0.05), (DOOR_X1 - 0.05, FL + 0.012, ZF + 0.75), 'rubber', group='decor')

# ------------------------------------------------------------------ storage room (behind the shutter) and restroom: closed boxes
def partition(name, lo, hi):
    x0, z0 = lo; x1, z1 = hi
    box(name + '_wain', (x0, 0, z0), (x1, WAIN, z1), 'panel')
    box(name + '_brick', (x0, WAIN, z0), (x1, H, z1), 'brick')
partition('Store_W', (2.2, ZF), (2.32, 4.0))
partition('Store_N', (2.2, 3.88), (XI, 4.0))
partition('Rest_W', (3.6, 6.6), (3.72, ZB))
partition('Rest_N', (3.6, 6.6), (XI, 6.72))
for i, (lo, hi) in enumerate((((2.17, FL, 0.25), (2.2, FL + 0.14, 3.88)), ((2.2, FL, 4.0), (XI, FL + 0.14, 4.03)),
                              ((3.57, FL, 6.6), (3.6, FL + 0.14, ZB)), ((3.6, FL, 6.57), (XI, FL + 0.14, 6.6)))):
    box('PSkirt%d' % i, lo, hi, 'trim')
for i, (lo, hi) in enumerate((((2.165, WAIN - 0.03, 0.25), (2.2, WAIN + 0.04, 3.88)), ((2.2, WAIN - 0.03, 4.0), (XI, WAIN + 0.04, 4.035)),
                              ((3.565, WAIN - 0.03, 6.6), (3.6, WAIN + 0.04, ZB)), ((3.6, WAIN - 0.03, 6.565), (XI, WAIN + 0.04, 6.6)))):
    box('PRail%d' % i, lo, hi, 'trim', bevel=0.008)

def door_on_wall(name, x0, x1, z0, z1, face, mname, sign=None, knob_side=1):
    """a closed door slab on a wall face, with a frame and a knob"""
    box(name, (x0, FL, z0), (x1, 2.1, z1), mname, bevel=0.006)
    if face in ('-x', '+x'):
        d = -1 if face == '-x' else 1
        fx = x0 if face == '-x' else x1
        for zz in (z0 - 0.07, z1):
            box(name + '_frame%d' % (zz > z0), (min(fx, fx + d * 0.03), FL, zz), (max(fx, fx + d * 0.03), 2.17, zz + 0.07), 'trim')
        box(name + '_frameT', (min(fx, fx + d * 0.03), 2.1, z0 - 0.07), (max(fx, fx + d * 0.03), 2.17, z1 + 0.07), 'trim')
        kz = z0 + 0.08 if knob_side > 0 else z1 - 0.08
        sphere(name + '_knob', (fx + d * 0.05, 1.0, kz), 0.03, 'brass')
        if sign: plane(name + '_sign', (fx + d * 0.006, 1.55, (z0 + z1) / 2), face, 0.5, 0.25, sign)
    else:
        d = -1 if face == '-z' else 1
        fz = z0 if face == '-z' else z1
        for xx in (x0 - 0.07, x1):
            box(name + '_frame%d' % (xx > x0), (xx, FL, min(fz, fz + d * 0.03)), (xx + 0.07, 2.17, max(fz, fz + d * 0.03)), 'trim')
        box(name + '_frameT', (x0 - 0.07, 2.1, min(fz, fz + d * 0.03)), (x1 + 0.07, 2.17, max(fz, fz + d * 0.03)), 'trim')
        kx = x0 + 0.08 if knob_side > 0 else x1 - 0.08
        sphere(name + '_knob', (kx, 1.0, fz + d * 0.05), 0.03, 'brass')
        if sign: plane(name + '_sign', ((x0 + x1) / 2, 1.55, fz + d * 0.006), face, 0.5, 0.25, sign)

door_on_wall('StaffDoor', 2.17, 2.2, 2.95, 3.78, '-x', 'door', 'sign_staff')
door_on_wall('RestDoor', 4.1, 4.92, 6.57, 6.6, '-z', 'door', 'sign_restroom', -1)
door_on_wall('BackDoor', 2.38, 3.23, ZB - 0.04, ZB, '-z', 'steel')
box('BackDoorBar', (2.45, 0.95, ZB - 0.1), (3.16, 1.02, ZB - 0.04), 'chrome', group='decor', bevel=0.01)
box('ExitSign', (2.6, 2.3, ZB - 0.08), (3.0, 2.48, ZB), 'exit', group='decor')

# ------------------------------------------------------------------ the bar
CX0, CX1 = -3.85, -3.35          # counter body (bartender side .. customer side)
CZ0, CZ1 = -0.30, 6.60
box('Counter', (CX0, 0, CZ0), (CX1, 1.02, CZ1), 'panel')
box('CounterKick', (CX1, 0, CZ0), (CX1 + 0.03, 0.15, CZ1), 'trim')
box('CounterTop', (CX0 - 0.1, 1.02, CZ0 - 0.06), (CX1 + 0.17, 1.08, CZ1 + 0.06), 'bartop', bevel=0.012)
box('CounterReturn', (-XI, 0, 6.66), (CX1, 1.02, 7.1), 'panel')
box('CounterReturnTop', (-XI, 1.02, 6.6), (CX1 + 0.17, 1.08, 7.16), 'bartop', bevel=0.012)
# padded arm rest along the customer edge and a brass foot rail
cyl('ArmRest', (CX1 + 0.14, 1.1, CZ0 - 0.04), 0.04, CZ1 - CZ0 + 0.08, 'vinyl', axis='z', seg=10)
cyl('FootRail', (CX1 + 0.18, 0.2, CZ0 + 0.05), 0.024, CZ1 - CZ0 - 0.1, 'brass', axis='z', seg=10)
for i, z in enumerate((0.1, 1.7, 3.3, 4.9, 6.2)):
    box('FootRailBracket%d' % i, (CX1, 0.18, z - 0.015), (CX1 + 0.19, 0.22, z + 0.015), 'brass', group='decor')
# back bar: cabinets, coolers, mirror, shelves
BX = -4.85
box('BackBar', (-XI, 0, -1.0), (BX, 0.95, 6.4), 'panel')
box('BackBarTop', (-XI, 0.95, -1.03), (BX + 0.04, 1.0, 6.43), 'bartop', bevel=0.008)
for i, z in enumerate((-0.6, 0.3, 1.2)):
    box('Cooler%d' % i, (BX, 0.12, z), (BX + 0.02, 0.82, z + 0.8), 'cooler', group='decor')
    box('CoolerHandle%d' % i, (BX + 0.02, 0.6, z + 0.7), (BX + 0.05, 0.75, z + 0.73), 'chrome', group='decor')
box('Mirror', (-XI, 1.15, 0.0), (-XI + 0.01, 2.35, 5.4), 'mirror', group='decor')
for i, y in enumerate((1.25, 1.62, 1.99)):
    box('Shelf%d' % i, (-XI, y - 0.025, -0.4), (-XI + 0.26, y, 5.8), 'tablewood', bevel=0.005)
    for zz in (-0.4, 2.7, 5.8):
        box('ShelfBracket%d_%d' % (i, zz * 10), (-XI, y - 0.12, zz - 0.01), (-XI + 0.2, y - 0.025, zz + 0.01), 'blackmetal', group='decor')

# bottles: 8 brands from the label atlas, glass colour per brand
BRANDS = [('amber', 0), ('amber', 1), ('clear', 2), ('amber', 3), ('clear', 4), ('green', 5), ('clear', 6), ('green', 7)]
def bottle(name, x, y, z, k, tall=1.0):
    glass, cell = BRANDS[k % 8]
    h = 0.24 * tall; r = 0.038
    cyl(name, (x, y, z), r, h, glass, group='decor', seg=10)
    cyl(name + '_sh', (x, y + h, z), r, 0.04, glass, group='decor', seg=10, r2=0.014)
    cyl(name + '_nk', (x, y + h + 0.04, z), 0.014, 0.07, glass, group='decor', seg=8)
    cyl(name + '_cap', (x, y + h + 0.11, z), 0.016, 0.02, 'blackmetal' if k % 2 else 'brass', group='decor', seg=8)
    # label: a quad on the bottle's front (facing the room, +x)
    u0 = (cell % 4) / 4; v1 = 1 - (cell // 4) / 2
    plane(name + '_lbl', (x + r + 0.002, y + h * 0.45, z), '+x', 0.06, 0.07, 'labels', uv=(u0 + 0.03, v1 - 0.47, u0 + 0.22, v1 - 0.03))
k = 0
for i, y in enumerate((1.25, 1.62, 1.99)):
    z = -0.25
    while z < 5.7:
        bottle('Bottle%d_%d' % (i, int(z * 100)), -XI + 0.12, y, z, k, 1.0 + 0.15 * ((k * 7) % 3 - 1))
        k += 1; z += 0.11 + 0.05 * ((k * 5) % 3)
z = 1.8
while z < 4.6:   # speed rail of bottles on the back-bar top
    bottle('BBottle%d' % int(z * 100), -5.2, 1.0, z, k, 1.1); k += 1; z += 0.13
# tap tower on the counter
TZ = 2.6; TX = (CX0 + CX1) / 2 - 0.05
box('DripTray', (TX - 0.1, 1.08, TZ - 0.35), (TX + 0.1, 1.1, TZ + 0.35), 'chrome', group='decor')
cyl('TapPost', (TX, 1.08, TZ), 0.045, 0.38, 'chrome', group='decor')
cyl('TapBar', (TX, 1.46, TZ - 0.3), 0.04, 0.6, 'chrome', axis='z', group='decor')
for i, (zz, hm) in enumerate(((-0.24, 'handle_r'), (-0.08, 'handle_g'), (0.08, 'handle_k'), (0.24, 'handle_w'))):
    cyl('Spout%d' % i, (TX + 0.04, 1.38, TZ + zz), 0.012, 0.06, 'chrome', group='decor', seg=8)
    box('TapHandle%d' % i, (TX - 0.018, 1.5, TZ + zz - 0.022), (TX + 0.018, 1.68, TZ + zz + 0.022), hm, group='decor', bevel=0.006)
# beer glasses and a few empties on the bar
for i, z in enumerate((0.5, 1.4, 3.6, 4.5, 5.3)):
    gx = CX1 + 0.02
    cyl('Pint%d' % i, (gx, 1.08, z), 0.036, 0.15, 'beer', group='decor', seg=10, r2=0.042)
for i, z in enumerate((1.1, 3.9, 5.9)):
    cyl('Empty%d' % i, (CX1 - 0.05, 1.08, z), 0.03, 0.2, 'green' if i % 2 else 'amber', group='decor', seg=8)
    cyl('Empty%d_nk' % i, (CX1 - 0.05, 1.28, z), 0.012, 0.06, 'green' if i % 2 else 'amber', group='decor', seg=6)
# cash register on the back bar, a sign over it
box('Register', (-5.3, 1.0, 5.45), (-4.92, 1.18, 5.95), 'register', group='decor', bevel=0.01)
box('RegisterTop', (-5.3, 1.18, 5.55), (-5.05, 1.32, 5.85), 'register', group='decor', bevel=0.01)
box('RegisterDisp', (-5.06, 1.2, 5.6), (-5.0, 1.29, 5.8), 'cooler', group='decor')
plane('SignCash', (-XI + 0.012, 2.15, 6.35), '+x', 0.6, 0.3, 'sign_cash')

# stools along the bar
for i in range(7):
    z = 0.35 + i * 0.95; x = -2.85
    cyl('StoolBase%d' % i, (x, FL, z), 0.2, 0.03, 'blackmetal', seg=16)
    cyl('StoolPole%d' % i, (x, FL + 0.03, z), 0.03, 0.66, 'chrome', seg=10)
    torus('StoolRing%d' % i, (x, 0.32, z), 0.15, 0.012, 'chrome', group='decor')
    cyl('StoolSeat%d' % i, (x, 0.72, z), 0.19, 0.08, 'vinyl', seg=18)

# ------------------------------------------------------------------ pool table
PX, PZ = 0.55, 5.0
PW, PL = 1.44, 2.6
x0, x1, z0, z1 = PX - PW / 2, PX + PW / 2, PZ - PL / 2, PZ + PL / 2
box('PoolBody', (x0 + 0.05, 0.5, z0 + 0.05), (x1 - 0.05, 0.78, z1 - 0.05), 'tablewood', bevel=0.02)
for i, (lx, lz) in enumerate(((x0 + 0.12, z0 + 0.12), (x1 - 0.12, z0 + 0.12), (x0 + 0.12, z1 - 0.12), (x1 - 0.12, z1 - 0.12))):
    box('PoolLeg%d' % i, (lx - 0.07, FL, lz - 0.07), (lx + 0.07, 0.5, lz + 0.07), 'tablewood', bevel=0.015)
box('PoolBed', (x0 + 0.14, 0.78, z0 + 0.14), (x1 - 0.14, 0.80, z1 - 0.14), 'felt')
for i, (lo, hi) in enumerate((((x0, 0.78, z0), (x0 + 0.14, 0.85, z1)), ((x1 - 0.14, 0.78, z0), (x1, 0.85, z1)),
                              ((x0 + 0.14, 0.78, z0), (x1 - 0.14, 0.85, z0 + 0.14)), ((x0 + 0.14, 0.78, z1 - 0.14), (x1 - 0.14, 0.85, z1)))):
    box('PoolRail%d' % i, lo, hi, 'tablewood', bevel=0.012)
for i, (lo, hi) in enumerate((((x0 + 0.14, 0.80, z0 + 0.14), (x0 + 0.18, 0.84, z1 - 0.14)), ((x1 - 0.18, 0.80, z0 + 0.14), (x1 - 0.14, 0.84, z1 - 0.14)),
                              ((x0 + 0.18, 0.80, z0 + 0.14), (x1 - 0.18, 0.84, z0 + 0.18)), ((x0 + 0.18, 0.80, z1 - 0.18), (x1 - 0.18, 0.84, z1 - 0.14)))):
    box('PoolCushion%d' % i, lo, hi, 'felt', group='decor')
for i, (px, pz) in enumerate(((x0 + 0.15, z0 + 0.15), (x1 - 0.15, z0 + 0.15), (x0 + 0.14, PZ), (x1 - 0.14, PZ), (x0 + 0.15, z1 - 0.15), (x1 - 0.15, z1 - 0.15))):
    cyl('Pocket%d' % i, (px, 0.79, pz), 0.058, 0.065, 'rubber', group='decor', seg=12)
for i, (px, pz) in enumerate(((x0 + 0.15, PZ), (x1 - 0.15, PZ))):
    for j, dz in enumerate((-0.6, 0.6)):
        cyl('Diamond%d_%d' % (i, j), (px, 0.85, PZ + dz), 0.008, 0.002, 'paper', group='decor', seg=6)
# balls: a loose rack and the cue ball
BALLS = ['yellow', 'blue', 'red', 'purple', 'orange', 'green', 'maroon', 'black', 'yellow', 'blue', 'red', 'purple', 'orange', 'green', 'maroon']
R = 0.0285; i = 0
for row in range(5):
    for col in range(row + 1):
        bx = PX + (col - row / 2) * 2.05 * R; bz = PZ - 0.55 - row * 1.78 * R
        sphere('Ball%d' % i, (bx, 0.80 + R, bz), R, 'ball_' + BALLS[i]); i += 1
sphere('BallCue', (PX + 0.1, 0.80 + R, PZ + 0.62), R, 'ball_white')
cyl('CueOnTable', (PX + 0.32, 0.86, PZ - 0.4), 0.007, 1.45, 'cue', axis='z', group='decor', seg=6, r2=0.012)
# billiard lamp over the table (hangs from the ceiling)
box('PoolLampShade', (PX - 0.22, 1.72, PZ - 0.85), (PX + 0.22, 1.86, PZ + 0.85), 'shade', group='decor', bevel=0.02)
box('PoolLampGlow', (PX - 0.18, 1.715, PZ - 0.8), (PX + 0.18, 1.725, PZ + 0.8), 'diffuser', group='decor')
for i, dz in enumerate((-0.6, 0.6)):
    cyl('PoolLampChain%d' % i, (PX, 1.86, PZ + dz), 0.006, H - 1.86, 'blackmetal', group='decor', seg=4)
# cue rack on the right wall
box('CueRack', (XI - 0.04, 0.9, 5.0), (XI, 1.7, 5.7), 'tablewood', bevel=0.008)
for i in range(4):
    cz = 5.1 + i * 0.16
    cyl('Cue%d' % i, (XI - 0.08, FL + 0.02, cz), 0.014, 1.45, 'cue', group='decor', seg=6, r2=0.007)

# ------------------------------------------------------------------ booths along the back wall
for k, xc in enumerate((-1.9, -0.25, 1.4)):
    bz0, bz1 = 8.0, ZB
    for s, (bx0, bx1) in enumerate(((xc - 0.76, xc - 0.30), (xc + 0.30, xc + 0.76))):
        box('BoothBase%d_%d' % (k, s), (bx0, 0, bz0), (bx1, 0.42, bz1), 'panel')
        box('BoothSeat%d_%d' % (k, s), (bx0, 0.42, bz0 - 0.02), (bx1, 0.52, bz1), 'vinyl', bevel=0.03)
        if s == 0: box('BoothBack%d_%d' % (k, s), (bx0, 0.52, bz0 - 0.02), (bx0 + 0.14, 1.2, bz1), 'vinyl', bevel=0.035)
        else: box('BoothBack%d_%d' % (k, s), (bx1 - 0.14, 0.52, bz0 - 0.02), (bx1, 1.2, bz1), 'vinyl', bevel=0.035)
    box('BoothTable%d' % k, (xc - 0.33, 0.72, 8.15), (xc + 0.33, 0.76, ZB - 0.02), 'tablewood', bevel=0.01)
    cyl('BoothPost%d' % k, (xc, FL, 8.8), 0.04, 0.66, 'blackmetal', seg=10)
    cyl('BoothFoot%d' % k, (xc, FL, 8.8), 0.22, 0.03, 'blackmetal', seg=14)
    # pendant over each table
    cyl('Pendant%d_cord' % k, (xc, 1.9, 8.75), 0.005, H - 1.9, 'blackmetal', group='decor', seg=4)
    cyl('Pendant%d_shade' % k, (xc, 1.72, 8.75), 0.17, 0.2, 'shade', group='decor', seg=16, r2=0.04)
    sphere('Pendant%d_bulb' % k, (xc, 1.74, 8.75), 0.04, 'bulb')
    # something on each table
    cyl('BoothPint%d' % k, (xc - 0.12, 0.76, 8.6), 0.036, 0.15, 'beer', group='decor', seg=10, r2=0.042)
    cyl('Ashtray%d' % k, (xc + 0.1, 0.76, 9.0), 0.06, 0.02, 'clear', group='decor', seg=10)
# pendants over the bar
for i, z in enumerate((0.6, 2.7, 4.8)):
    cyl('BarPendant%d_cord' % i, (-3.5, 2.15, z), 0.005, H - 2.15, 'blackmetal', group='decor', seg=4)
    cyl('BarPendant%d_shade' % i, (-3.5, 1.97, z), 0.15, 0.18, 'shade', group='decor', seg=16, r2=0.035)
    sphere('BarPendant%d_bulb' % i, (-3.5, 1.99, z), 0.035, 'bulb')

# ------------------------------------------------------------------ jukebox, darts, chalkboard, TV, posters
JX = 3.0
box('JukeBody', (JX - 0.42, 0, 4.0), (JX + 0.42, 1.12, 4.62), 'jukebody', bevel=0.02)
cyl('JukeArch', (JX, 1.12, 4.0), 0.42, 0.62, 'jukebody', axis='z', seg=24)
arch_plane('JukeFront', JX, 0.0, 0.84, 1.12, 4.625, 'jukebox')
# a dartboard in its cabinet, the throw line on the floor, and the score chalkboard
box('DartCabinet', (2.12, 1.4, 1.0), (2.2, 2.06, 1.66), 'tablewood', bevel=0.01)
plane('Dartboard', (2.118, 1.73, 1.33), '-x', 0.5, 0.5, 'dart')
box('Oche', (-0.17, FL, 0.95), (-0.12, FL + 0.003, 1.7), 'tape', group='decor')
box('ChalkFrame', (2.16, 1.25, 1.85), (2.2, 1.95, 2.77), 'trim', bevel=0.008)
plane('Chalk', (2.158, 1.6, 2.31), '-x', 0.84, 0.62, 'chalk')
# TV high in the corner behind the bar end
box('TVBox', (-XI + 0.05, 2.45, 7.95), (-XI + 0.17, 3.05, 8.95), 'tvbody', group='decor', bevel=0.01)
plane('TVScreen', (-XI + 0.172, 2.75, 8.45), '+x', 0.94, 0.53, 'tv')
box('TVArm', (-XI, 2.7, 8.4), (-XI + 0.05, 2.8, 8.5), 'blackmetal', group='decor')
# posters and signs
plane('PosterBand', (1.25, 1.75, ZF + 0.012), '+z', 0.55, 0.82, 'poster_band')
plane('PosterLeague', (XI - 0.012, 1.75, 4.4), '-x', 0.55, 0.82, 'poster_league')
plane('SignMinors', (-2.0, 1.7, ZF + 0.012), '+z', 0.6, 0.3, 'sign_minors')
# neon signs (boards with tubes painted in; alpha + emission)
plane('NeonLumberjack', (-XI + 0.02, 2.75, 2.7), '+x', 1.8, 0.675, 'neon_lumberjack', group='neon')
plane('NeonColdBeer', (XI - 0.02, 2.4, 5.3), '-x', 1.0, 0.5, 'neon_coldbeer', group='neon')
plane('NeonCocktails', (-0.25, 2.35, ZB - 0.02), '-z', 1.5, 0.536, 'neon_cocktails', group='neon')
plane('NeonOpen', (-0.13, 2.75, ZF + 0.02), '+z', 0.8, 0.32, 'neon_open', group='neon')

# ------------------------------------------------------------------ join and export
def join(obs, name):
    if not obs: return None
    with bpy.context.temp_override(object=obs[0], active_object=obs[0], selected_editable_objects=obs, selected_objects=obs):
        bpy.ops.object.join()
    o = obs[0]; o.name = name; o.data.name = name
    return o
solid = join(PARTS['solid'], 'Interior_Solid')
decor = join(PARTS['decor'], 'Interior_Decor_nocol')
neon = join(PARTS['neon'], 'Interior_Neon_nocol')
stats = {o.name: (len(o.data.polygons), len(o.data.materials)) for o in (solid, decor, neon)}
if OUT:
    os.makedirs(os.path.dirname(OUT), exist_ok=True)
    for o in bpy.context.view_layer.objects: o.select_set(False)
    for o in (solid, decor, neon): o.select_set(True)
    bpy.ops.export_scene.gltf(filepath=OUT, export_format='GLB', use_selection=True, export_apply=True, export_yup=True,
                              export_lights=False, export_cameras=False, export_image_format='AUTO')
result = {'stats': stats, 'out': OUT, 'exists': os.path.exists(OUT), 'size': os.path.getsize(OUT) if os.path.exists(OUT) else 0}
