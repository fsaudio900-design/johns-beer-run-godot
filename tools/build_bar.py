#!/usr/bin/env python3
"""Build the complete bar (assets/bar/Bar.glb) around the supplied "dirty street" facade.

The supplied model (tools/bar_src/SM_Poubelle2.fbx) is only the street front: a brick facade with
a graffiti shutter, a side door, pilasters, a neon BAR sign and props, standing on a strip of
sidewalk and road. This script keeps that front exactly as it is and adds the rest of the building
in the same style:
  * side and back walls in the same brick (a seamless tile cut from the facade's own texture,
    tools/bar_src/brick_albedo.png / brick_normal.png),
  * a flat tar roof behind a short parapet, with the facade's metal ledge as coping, an AC unit,
    vent stacks and a roof hatch,
  * a back entrance: a copy of the facade's own door (frame, slab, awning), the wall lamp, the
    electrical box, drainpipes, and a pile of crates and trash bags,
  * the white "TRASH lovers" tag from the facade as a decal on the side walls.

Input geometry: tools/bar_src/geom.json, the facade mesh as Godot imported it (dumped once with
Godot 4.7; triangles are in Godot's clockwise order and are flipped for glTF here).
Units: the facade's own units (1 unit = 0.1375 m, set by its 2.2 m door); the output is in metres.
Origin: centre of the building's width, on the main facade line, at the ground. Front faces -Z.

usage: build_bar.py <bar_src dir> <out.glb> [--street]
  --street keeps the facade's own strip of road and curb (the game version drops them: the bar
  stands on Main Street's sidewalk, so only the facade's own sidewalk is kept).
"""
import io, json, math, os, struct, sys
import numpy as np
from PIL import Image

S = 0.1375                 # model units -> metres
SRC = sys.argv[1] if len(sys.argv) > 1 else 'tools/bar_src'
OUT = sys.argv[2] if len(sys.argv) > 2 else 'assets/bar/Bar.glb'
STREET = '--street' in sys.argv
BASE = -3.0                # new walls start a little below ground so no gap shows on uneven ground

# ---------------------------------------------------------------- building dimensions (model units)
X_L, X_R = 28.1, -52.9     # ends of the facade (x = +28.1 is the shutter end, -52.9 the far wing)
Z_MAIN = 13.53             # main facade plane
Z_WING = 3.1               # the wing that steps out toward the street
X_STEP = -29.6             # where the wing starts
Z_PIER, X_PIER = 8.3, -21.1  # the pier block between them
DEPTH = 70.0               # ~9.6 m deep behind the main facade
Z_BACK = Z_MAIN + DEPTH
TOP = 38.2                 # top of the facade walls
DECK = 34.6                # roof deck (parapet ~0.5 m)
PARA_T = 1.1               # parapet thickness
COPE_H, COPE_OVER = 0.55, 0.35
BRICK_U, BRICK_V = 16.46, 14.93   # model units covered by one brick tile
OX, OZ = (X_L + X_R) / 2, Z_MAIN  # origin

# ---------------------------------------------------------------- mesh builder
class Prim:
    def __init__(self, mat):
        self.mat = mat; self.P = []; self.N = []; self.U = []; self.I = []
    def tri(self, a, b, c, n, ua, ub, uc):
        a, b, c, n = map(np.asarray, (a, b, c, n))
        if np.dot(np.cross(b - a, c - a), n) < 0: b, c, ub, uc = c, b, uc, ub
        k = len(self.P)
        for p, u in ((a, ua), (b, ub), (c, uc)): self.P.append(p); self.N.append(n); self.U.append(u)
        self.I += [k, k + 1, k + 2]
    def quad(self, p0, p1, p2, p3, n, u0, u1, u2, u3):
        self.tri(p0, p1, p2, n, u0, u1, u2); self.tri(p0, p2, p3, n, u0, u2, u3)
    def add_raw(self, P, N, U, I):
        k = len(self.P)
        self.P += list(P); self.N += list(N); self.U += list(U); self.I += [k + int(i) for i in I]

def nrm(v): v = np.asarray(v, float); return v / np.linalg.norm(v)

# ---------------------------------------------------------------- brick walls
brick = Prim('brick')
def wall(a, b, y0, y1, outward, uoff=0.0):
    """vertical brick wall from (x,z) a to b, y0..y1, facing `outward` (a horizontal vector)"""
    a = np.array(a, float); b = np.array(b, float)
    L = np.linalg.norm(b - a)
    p0 = [a[0], y0, a[1]]; p1 = [b[0], y0, b[1]]; p2 = [b[0], y1, b[1]]; p3 = [a[0], y1, a[1]]
    u0, u1 = uoff / BRICK_U, (uoff + L) / BRICK_U
    v0, v1 = (TOP - y0) / BRICK_V, (TOP - y1) / BRICK_V
    brick.quad(p0, p1, p2, p3, outward, [u0, v0], [u1, v0], [u1, v1], [u0, v1])

# outer walls
wall((X_R, Z_WING), (X_R, Z_BACK), BASE, TOP, [-1, 0, 0])                     # far side
wall((X_L, Z_BACK), (X_L, Z_MAIN), BASE, TOP, [1, 0, 0], 3.0)                  # shutter side
wall((X_R, Z_BACK), (X_L, Z_BACK), BASE, TOP, [0, 0, 1], 7.0)                  # back
# parapet inner faces (seen from the roof); outline is stepped like the facade
inner = [((X_L - PARA_T, Z_MAIN + PARA_T), (X_PIER + PARA_T, Z_MAIN + PARA_T), [0, 0, 1]),
         ((X_STEP + PARA_T, Z_WING + PARA_T), (X_R + PARA_T, Z_WING + PARA_T), [0, 0, 1]),
         ((X_R + PARA_T, Z_WING + PARA_T), (X_R + PARA_T, Z_BACK - PARA_T), [1, 0, 0]),
         ((X_R + PARA_T, Z_BACK - PARA_T), (X_L - PARA_T, Z_BACK - PARA_T), [0, 0, -1]),
         ((X_L - PARA_T, Z_BACK - PARA_T), (X_L - PARA_T, Z_MAIN + PARA_T), [-1, 0, 0]),
         ((X_PIER + PARA_T, Z_MAIN + PARA_T), (X_PIER + PARA_T, Z_PIER + PARA_T), [-1, 0, 0]),
         ((X_PIER + PARA_T, Z_PIER + PARA_T), (X_STEP + PARA_T, Z_PIER + PARA_T), [0, 0, 1]),
         ((X_STEP + PARA_T, Z_PIER + PARA_T), (X_STEP + PARA_T, Z_WING + PARA_T), [-1, 0, 0])]
for a, b, n in inner: wall(a, b, DECK, TOP, n)

# ---------------------------------------------------------------- atlas-mapped parts (the facade's own texture sheet)
atlas = Prim('walls_atlas')
props = Prim('props')
def box(prim, lo, hi, uvr, faces='xXyYzZ'):
    """axis-aligned box; every face mapped onto uv rect uvr = (u0, v0, u1, v1)"""
    lo = np.array(lo, float); hi = np.array(hi, float); u0, v0, u1, v1 = uvr
    c = [[lo[0], hi[0]], [lo[1], hi[1]], [lo[2], hi[2]]]
    for ax in range(3):
        for side in (0, 1):
            if 'xyz'[ax].__getattribute__('upper' if side else 'lower')() not in faces: continue
            n = [0, 0, 0]; n[ax] = 1 if side else -1
            o = [(ax + 1) % 3, (ax + 2) % 3]
            pts = []
            for i, j in ((0, 0), (1, 0), (1, 1), (0, 1)):
                p = [0, 0, 0]; p[ax] = c[ax][side]; p[o[0]] = c[o[0]][i]; p[o[1]] = c[o[1]][j]; pts.append(p)
            uv = [[u0, v0], [u1, v0], [u1, v1], [u0, v1]]
            prim.quad(*pts, n, *uv)

# coping: the facade's metal ledge (atlas strip) along every parapet top
LEDGE = (0.7505, 0.006, 0.7585, 0.314)      # u across, v along, as on the facade
def coping(a, b):
    a = np.array(a, float); b = np.array(b, float)
    lo = np.minimum(a, b) - COPE_OVER; hi = np.maximum(a, b) + COPE_OVER
    L = max(hi[0] - lo[0], hi[1] - lo[1])
    nseg = max(1, int(math.ceil(L / 26.0)))
    along = 0 if hi[0] - lo[0] >= hi[1] - lo[1] else 1
    for k in range(nseg):
        s0 = lo.copy(); s1 = hi.copy()
        s0[along] = lo[along] + (hi[along] - lo[along]) * k / nseg; s1[along] = lo[along] + (hi[along] - lo[along]) * (k + 1) / nseg
        rect = (LEDGE[0], LEDGE[1], LEDGE[2], LEDGE[1] + (LEDGE[3] - LEDGE[1]) * (s1[along] - s0[along]) / 54.0)
        box(atlas, [s0[0], TOP, s0[1]], [s1[0], TOP + COPE_H, s1[1]], rect)
H = PARA_T / 2
for a, b in [((X_L + H, Z_MAIN), (X_PIER, Z_MAIN)), ((X_PIER, Z_PIER), (X_STEP, Z_PIER)), ((X_PIER, Z_PIER), (X_PIER, Z_MAIN)),
             ((X_STEP, Z_WING), (X_STEP, Z_PIER)), ((X_STEP, Z_WING), (X_R - H, Z_WING)),
             ((X_R, Z_WING), (X_R, Z_BACK + H)), ((X_R - H, Z_BACK), (X_L + H, Z_BACK)), ((X_L, Z_BACK + H), (X_L, Z_MAIN))]:
    a = np.array(a); b = np.array(b)
    # centre the coping on the wall line, PARA_T wide
    d = 0 if abs(b[0] - a[0]) > abs(b[1] - a[1]) else 1
    lo = np.minimum(a, b); hi = np.maximum(a, b); lo[1 - d] -= H; hi[1 - d] += H
    coping(lo, hi)

# the facade's horizontal metal ledge (y 20.5-21.6), carried round the sides and the back
LB0, LB1, LBD = 20.5, 21.6, 0.35
for a, b in [((X_R - LBD, Z_WING), (X_R, Z_BACK + LBD)), ((X_R - LBD, Z_BACK), (X_L + LBD, Z_BACK + LBD)), ((X_L, Z_MAIN), (X_L + LBD, Z_BACK + LBD))]:
    lo = np.minimum(a, b); hi = np.maximum(a, b)
    along = 0 if hi[0] - lo[0] > hi[1] - lo[1] else 1
    L = hi[along] - lo[along]; nseg = max(1, int(math.ceil(L / 26.0)))
    for k in range(nseg):
        s0 = lo.copy(); s1 = hi.copy()
        s0[along] = lo[along] + L * k / nseg; s1[along] = lo[along] + L * (k + 1) / nseg
        rect = (LEDGE[0], LEDGE[1], LEDGE[2], LEDGE[1] + (LEDGE[3] - LEDGE[1]) * (s1[along] - s0[along]) / 54.0)
        box(atlas, [s0[0], LB0, s0[1]], [s1[0], LB1, s1[1]], rect)

# roof deck: tar (the road's asphalt from the atlas), laid in patches so it doesn't visibly repeat
TAR = 9.0                 # model units per tar tile
deck = Prim('tar')
def deck_rect(x0, x1, z0, z1, seed):
    deck.quad([x0, DECK, z0], [x1, DECK, z0], [x1, DECK, z1], [x0, DECK, z1], [0, 1, 0],
              [x0 / TAR, z0 / TAR], [x1 / TAR, z0 / TAR], [x1 / TAR, z1 / TAR], [x0 / TAR, z1 / TAR])
deck_rect(X_R + PARA_T, X_L - PARA_T, Z_MAIN + PARA_T, Z_BACK - PARA_T, 1)
deck_rect(X_R + PARA_T, X_STEP + PARA_T, Z_WING + PARA_T, Z_MAIN + PARA_T, 2)
deck_rect(X_STEP + PARA_T, X_PIER + PARA_T, Z_PIER + PARA_T, Z_MAIN + PARA_T, 3)

# roof fittings, mapped onto the props sheet's grey sheet-metal panel and the drainpipe
PANEL = (0.02, 0.02, 0.21, 0.12)
PIPE = (0.805, 0.085, 0.845, 0.185)
def cyl(prim, cx, cz, y0, y1, r, uvr, seg=12, cap=True):
    u0, v0, u1, v1 = uvr
    for k in range(seg):
        a0 = 2 * math.pi * k / seg; a1 = 2 * math.pi * (k + 1) / seg
        p0 = [cx + r * math.cos(a0), y0, cz + r * math.sin(a0)]; p1 = [cx + r * math.cos(a1), y0, cz + r * math.sin(a1)]
        p2 = [p1[0], y1, p1[2]]; p3 = [p0[0], y1, p0[2]]
        n = [math.cos((a0 + a1) / 2), 0, math.sin((a0 + a1) / 2)]
        ua = u0 + (u1 - u0) * k / seg; ub = u0 + (u1 - u0) * (k + 1) / seg
        prim.quad(p0, p1, p2, p3, n, [ua, v1], [ub, v1], [ub, v0], [ua, v0])
        if cap: prim.tri([cx, y1, cz], p3, p2, [0, 1, 0], [(u0 + u1) / 2, v0], [ua, v0], [ub, v0])
metal = Prim('metal'); vent = Prim('vent')
# AC unit (1.4 x 1.0 x 1.1 m): vent grilles on its long sides, a lid, a duct into the roof
box(metal, [-6, DECK, 50], [4, DECK + 7.5, 58], (0, 0, 1, 1), 'xXyY')
box(vent, [-6, DECK, 50], [4, DECK + 7.5, 58], (0, 0, 1, 1), 'zZ')
box(metal, [-6.4, DECK + 7.5, 49.6], [4.4, DECK + 8.0, 58.4], (0, 0, 1, 0.1))
box(metal, [-2.5, DECK, 58], [0.5, DECK + 2.5, 64], (0, 0, 0.4, 0.4))
# a smaller exhaust fan over the kitchen, a roof hatch, vent stacks
box(vent, [-38, DECK, 34], [-31, DECK + 5.0, 40], (0, 0, 1, 1), 'xXzZ')
box(metal, [-38, DECK, 34], [-31, DECK + 5.0, 40], (0, 0, 1, 0.3), 'yY')
box(metal, [12, DECK, 66], [19, DECK + 1.6, 73], (0, 0, 1, 0.3))
for cx, cz, h in ((18, 32, 6.0), (20.5, 32.5, 4.5), (-44, 66, 7.0)):
    cyl(metal, cx, cz, DECK, DECK + h, 0.75, (0, 0, 1, 1))

# ---------------------------------------------------------------- the supplied facade, kept as is
G = json.load(open(os.path.join(SRC, 'geom.json')))
surfs = []
for s in G['surfs']:
    P = np.array(s['P']); N = np.array(s['N']); U = np.array(s['U']); I = np.array(s['I']).reshape(-1, 3)[:, [0, 2, 1]]   # CW -> CCW
    surfs.append((P, N, U, I))
(Pp, Np, Up, Ip), (Pw, Nw, Uw, Iw) = surfs
props.add_raw(Pp, Np, Up, Ip.reshape(-1))
if not STREET:
    # drop the road strip and the curb (everything flat and low in front of the sidewalk)
    tp = Pw[Iw]; low = (tp[:, :, 1].max(1) < 0.6) & (tp[:, :, 2].max(1) < 3.2)
    Iw = Iw[~low]
facade = Prim('walls_atlas'); facade.add_raw(Pw, Nw, Uw, Iw.reshape(-1))

# ---------------------------------------------------------------- back entrance: copies of the facade's own pieces
def take(P, N, U, I, sel_tri):
    T = I[sel_tri]; idx, inv = np.unique(T.reshape(-1), return_inverse=True)
    return P[idx], N[idx], U[idx], inv
def place(P, N, src, dst, shift=(0, 0, 0)):
    """turn a piece from the front (facing -Z at z=src[2]) round to the back wall (facing +Z)"""
    P2 = P.copy(); N2 = N.copy()
    P2[:, 0] = -(P[:, 0] - src[0]) + dst[0] + shift[0]
    P2[:, 1] = P[:, 1] + shift[1]
    P2[:, 2] = -(P[:, 2] - src[2]) + dst[2] + shift[2]
    N2[:, 0] = -N[:, 0]; N2[:, 2] = -N[:, 2]
    return P2, N2
DOOR_SRC = (-13.6, 0, Z_MAIN)
DOOR_DST = (8.0, 0, Z_BACK)
# door frame + slab (wall sheet): triangles inside the door's box
cen = Pw[Iw].mean(1); mx = Pw[Iw].max(1); mn = Pw[Iw].min(1)
door = (mn[:, 0] > -17.5) & (mx[:, 0] < -9.8) & (mx[:, 1] < 16.3) & (mn[:, 2] > 12.6) & (mx[:, 2] < 13.7)
P, N, U, I = take(Pw, Nw, Uw, Iw, door); P, N = place(P, N, DOOR_SRC, DOOR_DST); atlas.add_raw(P, N, U, I)
# props: connected pieces of the props mesh
comp = np.load(os.path.join(SRC, 'tri_comp.npy'))
# dumpster pieces: everything whose box sits inside the dumpster's footprint in front of the shutter
DUMP = set()
for c in range(int(comp.max()) + 1):
    T = Ip[comp == c]
    if len(T) == 0: continue
    q0 = Pp[T.reshape(-1)].min(0); q1 = Pp[T.reshape(-1)].max(0)
    if q0[0] > -6.0 and q1[0] < 5.0 and q0[2] > 5.2 and q1[2] < 13.3 and q1[1] < 8.5: DUMP.add(c)
def comps(ids): return np.isin(comp, ids)
def put(ids, src, dst, shift=(0, 0, 0)):
    P, N, U, I = take(Pp, Np, Up, Ip, comps(ids)); P, N = place(P, N, src, dst, shift); props.add_raw(P, N, U, I)
put([38], DOOR_SRC, DOOR_DST)                                         # awning over the door
put([34], DOOR_SRC, DOOR_DST, (-1.0, 0, 0))                           # electrical box beside it
put([75, 79], (-1.85, 0, Z_MAIN), (DOOR_DST[0] - 9.0, 0, Z_BACK), (0, -1.0, 0))   # wall lamp
# crates and trash bags from the corner by the BAR sign, piled the other side of the door
pile = [10, 11, 14, 15, 19, 20, 21]
put(pile, (-24.5, 0, 8.3), (DOOR_DST[0] + 12.0, 0, Z_BACK))
# the facade's dumpster (and what's piled on it), wheeled round the back
dump = [c for c in range(int(comp.max()) + 1) if c in DUMP]
put(dump, (-0.4, 0, Z_MAIN), (-12.0, 0, Z_BACK), (0, 0, 0.3))
# a second pile further along, mirrored so it doesn't read as a copy
put([99, 100, 101, 103, 95, 96, 91, 92, 97, 98, 93], (5.8, 0, 13.0), (-44.0, 0, Z_BACK))
# drainpipes at both back corners and one on each side wall
pipe = [0, 1, 2, 3, 4, 5, 6, 7, 8]
PIPE_SRC = (-29.5, 0, 8.3)
for x in (X_L - 3.0, X_R + 3.0):
    put(pipe, PIPE_SRC, (x, 0, Z_BACK))
    put([8], PIPE_SRC, (x, 0, Z_BACK), (0, 3.4, 0)); put([8], PIPE_SRC, (x, 0, Z_BACK), (0, 6.8, 0))
def put_side(ids, src, x, z, outward_x, shift_y=0.0):
    P, N, U, I = take(Pp, Np, Up, Ip, comps(ids))
    # front pieces face -Z; turn them to face +-X
    P2 = P.copy(); N2 = N.copy()
    if outward_x > 0:   # facing +X: (x,z) -> (z', x')
        P2[:, 0] = -(P[:, 2] - src[2]) + x; P2[:, 2] = (P[:, 0] - src[0]) + z
        N2[:, 0] = -N[:, 2]; N2[:, 2] = N[:, 0]
    else:
        P2[:, 0] = (P[:, 2] - src[2]) + x; P2[:, 2] = -(P[:, 0] - src[0]) + z
        N2[:, 0] = N[:, 2]; N2[:, 2] = -N[:, 0]
    P2[:, 1] += shift_y
    props.add_raw(P2, N2, U, I)
for ids, sy in ((pipe, 0.0), ([8], 3.4), ([8], 6.8)):
    put_side(ids, PIPE_SRC, X_L, 70.0, +1, sy)
    put_side(ids, PIPE_SRC, X_R, 55.0, -1, sy)

# ---------------------------------------------------------------- graffiti decals (the facade's "TRASH lovers" tag)
decal = Prim('decal')
def tag(x, z, y, w, outward):
    h = w * 172 / 206
    o = np.array(outward, float); side = np.cross([0, 1, 0], o)    # to the right when facing the wall
    c = np.array([x, y, z], float) + o * 0.06
    p0 = c - side * w / 2; p1 = c + side * w / 2
    decal.quad(p0, p1, p1 + [0, h, 0], p0 + [0, h, 0], o, [0, 1], [1, 1], [1, 0], [0, 0])
tag(X_L, 40.0, 7.0, 13.0, [1, 0, 0])
tag(X_R, 45.0, 9.0, 11.0, [-1, 0, 0])
tag(-30.0, Z_BACK, 6.5, 10.0, [0, 0, 1])

# ---------------------------------------------------------------- write glTF
prims = [facade, atlas, deck, brick, props, metal, vent, decal]
def img_bytes(path, size=None, fmt='JPEG', q=90):
    im = Image.open(path)
    if size: im = im.resize((size, size), Image.LANCZOS)
    o = io.BytesIO()
    if fmt == 'PNG': im.save(o, 'PNG', optimize=True)
    else: im.convert('RGB').save(o, 'JPEG', quality=q)
    return o.getvalue(), 'image/png' if fmt == 'PNG' else 'image/jpeg'
IMAGES = {
    'props_c': img_bytes(os.path.join(SRC, 'TEST_lambert3_BaseColor.png')),
    'props_n': img_bytes(os.path.join(SRC, 'TEST_lambert3_Normal.png'), q=92),
    'props_e': img_bytes(os.path.join(SRC, 'T_Poubelle_E.png'), 1024),
    'wall_c': img_bytes(os.path.join(SRC, 'T_WallPoubelle_B.png')),
    'wall_n': img_bytes(os.path.join(SRC, 'T_WallPoubelle_N.png'), q=92),
    'brick_c': img_bytes(os.path.join(SRC, 'brick_albedo.png')),
    'brick_n': img_bytes(os.path.join(SRC, 'brick_normal.png'), q=92),
    'tag': img_bytes(os.path.join(SRC, 'tag_trash.png'), fmt='PNG'),
    'tar': img_bytes(os.path.join(SRC, 'tar.png')),
    'metal': img_bytes(os.path.join(SRC, 'metal.png')),
    'vent': img_bytes(os.path.join(SRC, 'metal_vent.png')),
}
bin_ = bytearray(); bvs = []; accs = []; images = []; textures = []; img_ix = {}
def push(arr, ctype, typ, target=None, minmax=False):
    arr = np.ascontiguousarray(arr)
    while len(bin_) % 4: bin_.append(0)
    bv = dict(buffer=0, byteOffset=len(bin_), byteLength=arr.nbytes)
    if target: bv['target'] = target
    bvs.append(bv); bin_.extend(arr.tobytes())
    a = dict(bufferView=len(bvs) - 1, componentType=ctype, count=len(arr), type=typ)
    if minmax: a['min'] = arr.min(0).tolist(); a['max'] = arr.max(0).tolist()
    accs.append(a); return len(accs) - 1
def tex(name, clamp=False):
    if name not in img_ix:
        data, mime = IMAGES[name]
        while len(bin_) % 4: bin_.append(0)
        bvs.append(dict(buffer=0, byteOffset=len(bin_), byteLength=len(data))); bin_.extend(data)
        images.append(dict(bufferView=len(bvs) - 1, mimeType=mime, name='Bar_' + name))
        textures.append(dict(source=len(images) - 1, sampler=1 if clamp else 0)); img_ix[name] = len(textures) - 1
    return dict(index=img_ix[name])
MATS = {
    'walls_atlas': dict(name='Bar_Walls', pbrMetallicRoughness=dict(baseColorTexture=tex('wall_c'), metallicFactor=0.0, roughnessFactor=0.9), normalTexture=tex('wall_n')),
    'brick': dict(name='Bar_Brick', pbrMetallicRoughness=dict(baseColorTexture=tex('brick_c'), metallicFactor=0.0, roughnessFactor=0.92), normalTexture=tex('brick_n')),
    'props': dict(name='Bar_Props', pbrMetallicRoughness=dict(baseColorTexture=tex('props_c'), metallicFactor=0.0, roughnessFactor=0.8), normalTexture=tex('props_n'),
                  emissiveTexture=tex('props_e'), emissiveFactor=[1.0, 1.0, 1.0], doubleSided=True),
    'tar': dict(name='Bar_Tar', pbrMetallicRoughness=dict(baseColorTexture=tex('tar'), metallicFactor=0.0, roughnessFactor=0.95)),
    'metal': dict(name='Bar_Metal', pbrMetallicRoughness=dict(baseColorTexture=tex('metal'), metallicFactor=0.5, roughnessFactor=0.55)),
    'vent': dict(name='Bar_Vent', pbrMetallicRoughness=dict(baseColorTexture=tex('vent'), metallicFactor=0.5, roughnessFactor=0.55)),
    'decal': dict(name='Bar_Tag', pbrMetallicRoughness=dict(baseColorTexture=tex('tag', True), metallicFactor=0.0, roughnessFactor=0.85), alphaMode='BLEND'),
}
mat_list = list(MATS); mat_ix = {m: i for i, m in enumerate(mat_list)}
gl_prims = []
for p in prims:
    if not p.I: continue
    P = (np.array(p.P, np.float32) - np.array([OX, 0, OZ], np.float32)) * S
    N = np.array(p.N, np.float32); N /= np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)
    U = np.array(p.U, np.float32)
    attrs = dict(POSITION=push(P, 5126, 'VEC3', 34962, True), NORMAL=push(N, 5126, 'VEC3', 34962), TEXCOORD_0=push(U, 5126, 'VEC2', 34962))
    gl_prims.append(dict(attributes=attrs, indices=push(np.array(p.I, np.uint32), 5125, 'SCALAR', 34963), material=mat_ix[p.mat], mode=4))
g = dict(asset=dict(version='2.0', generator='JBR build_bar.py'), scene=0, scenes=[dict(nodes=[0])],
         nodes=[dict(name='Bar', mesh=0)], meshes=[dict(name='Bar', primitives=gl_prims)],
         materials=[MATS[m] for m in mat_list], textures=textures, images=images,
         samplers=[dict(magFilter=9729, minFilter=9987, wrapS=10497, wrapT=10497), dict(magFilter=9729, minFilter=9987, wrapS=33071, wrapT=33071)],
         accessors=accs, bufferViews=bvs)
while len(bin_) % 4: bin_.append(0)
g['buffers'] = [dict(byteLength=len(bin_))]
js = json.dumps(g, separators=(',', ':')).encode(); js += b' ' * ((4 - len(js) % 4) % 4)
os.makedirs(os.path.dirname(OUT), exist_ok=True)
open(OUT, 'wb').write(struct.pack('<III', 0x46546C67, 2, 28 + len(js) + len(bin_)) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(bin_), 0x004E4942) + bytes(bin_))
size_m = ((X_L - X_R) * S, TOP * S, (Z_BACK - Z_WING) * S)
print('Bar.glb: %.1f MB, %d triangles, building %.1f x %.1f x %.1f m (w x h x d)' % (os.path.getsize(OUT) / 1e6, sum(len(p.I) for p in prims) // 3, *size_m))
