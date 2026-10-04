#!/usr/bin/env python3
"""Prepare the supplied character models for the game.

  cashier <in.glb> <out.glb>
      Shrinks the 4K textures of the Sketchfab "Cashier Lady" (already Mixamo-rigged).

  police <Police.obj dir> <cashier.glb> <out.glb>
      The police officer arrives as an unrigged Adobe Fuse OBJ in T-pose. The cashier is a
      Fuse/Mixamo character in the same T-pose, so we borrow her rig: her skeleton and skin
      weights are warped onto the officer's proportions (height, shoulder width, arm length)
      and every officer vertex takes the weights of the nearest warped cashier vertices.
      Output: a skinned glTF with a Mixamo-named skeleton, in metres.
"""
import io, json, os, struct, sys
import numpy as np
from PIL import Image
from scipy.spatial import cKDTree

# ---------------------------------------------------------------- glb io
def read_glb(path):
    d = open(path, 'rb').read()
    l0, = struct.unpack_from('<I', d, 12); j = json.loads(d[20:20 + l0])
    o = 20 + l0; l1, = struct.unpack_from('<I', d, o)
    return j, d[o + 8:o + 8 + l1]

def write_glb(path, j, b):
    js = json.dumps(j, separators=(',', ':')).encode(); js += b' ' * ((4 - len(js) % 4) % 4)
    b = bytes(b) + b'\0' * ((4 - len(b) % 4) % 4)
    j['buffers'] = [{'byteLength': len(b)}]
    js = json.dumps(j, separators=(',', ':')).encode(); js += b' ' * ((4 - len(js) % 4) % 4)
    out = struct.pack('<III', 0x46546C67, 2, 28 + len(js) + len(b)) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(b), 0x004E4942) + b
    open(path, 'wb').write(out); return len(out)

def acc(j, b, i):
    a = j['accessors'][i]; bv = j['bufferViews'][a['bufferView']]
    n = {'MAT4': 16, 'VEC4': 4, 'VEC3': 3, 'VEC2': 2, 'SCALAR': 1}[a['type']]
    dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a['componentType']]
    st = bv.get('byteStride', 0); o = bv.get('byteOffset', 0) + a.get('byteOffset', 0); isz = np.dtype(dt).itemsize * n
    if st and st != isz:
        return np.ascontiguousarray(np.frombuffer(b, np.uint8, a['count'] * st, o).reshape(-1, st)[:, :isz]).view(dt).reshape(-1, n)
    return np.frombuffer(b, dt, a['count'] * n, o).reshape(-1, n).copy()

def repack(j, b, blobs):
    """blobs: bufferView index -> replacement bytes"""
    out = bytearray()
    for i, bv in enumerate(j['bufferViews']):
        data = blobs.get(i, b[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']])
        while len(out) % 4: out.append(0)
        bv['byteOffset'] = len(out); bv['byteLength'] = len(data); out += data
    return out

def img_bytes(im, fmt, **kw):
    o = io.BytesIO(); im.save(o, fmt, **kw); return o.getvalue()

# ---------------------------------------------------------------- cashier
def cashier(src, dst):
    j, b = read_glb(src)
    blobs = {}
    for k, im in enumerate(j['images']):
        bv = j['bufferViews'][im['bufferView']]
        I = Image.open(io.BytesIO(b[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]))
        if I.mode == 'L': I = I.resize((256, 256), Image.LANCZOS); blobs[im['bufferView']] = img_bytes(I, 'PNG'); continue
        if I.mode == 'RGBA':
            I = I.resize((1024, 1024), Image.LANCZOS); blobs[im['bufferView']] = img_bytes(I, 'PNG', optimize=True); continue
        I = I.resize((2048, 2048), Image.LANCZOS); blobs[im['bufferView']] = img_bytes(I, 'JPEG', quality=90); im['mimeType'] = 'image/jpeg'
    # plain metal/rough materials: Godot's spec/gloss conversion turned her nearly black
    for m in j['materials']:
        sg = m.pop('extensions', {}).get('KHR_materials_pbrSpecularGlossiness', {})
        pbr = dict(metallicFactor=0.0, roughnessFactor=round(1.0 - 0.5 * sg.get('glossinessFactor', 0.0), 3))
        if 'diffuseTexture' in sg: pbr['baseColorTexture'] = sg['diffuseTexture']
        if 'diffuseFactor' in sg: pbr['baseColorFactor'] = sg['diffuseFactor']
        m['pbrMetallicRoughness'] = pbr
    j.pop('extensionsUsed', None); j.pop('extensionsRequired', None)
    # the hair cards: alpha-tested, not blended (blended hair sorts badly against itself)
    for m in j['materials']:
        if m.get('alphaMode') == 'BLEND': m['alphaMode'] = 'MASK'; m['alphaCutoff'] = 0.35
    out = repack(j, b, blobs)
    print('cashier ->', write_glb(dst, j, out) // 1024, 'KB')

def skin_data(j, b):
    """cashier: joint names, parents, bind globals (cm, skin space), all skinned vertices + weights"""
    N = j['nodes']; sk = j['skins'][0]; joints = sk['joints']
    par = {}
    for i, n in enumerate(N):
        for c in n.get('children', []): par[c] = i
    def local(i):
        n = N[i]; M = np.eye(4)
        if 'matrix' in n: return np.array(n['matrix']).reshape(4, 4).T
        if 'rotation' in n:
            x, y, z, w = n['rotation']
            M[:3, :3] = [[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                         [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                         [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]]
        if 'scale' in n: M[:3, :3] = M[:3, :3] * np.array(n['scale'])
        if 'translation' in n: M[:3, 3] = n['translation']
        return M
    root = joints[0]
    G = {}
    def glob(i):
        if i in G: return G[i]
        G[i] = local(i) if i == root or par.get(i) is None else glob(par[i]) @ local(i)
        return G[i]
    pos = np.array([glob(i)[:3, 3] for i in joints])
    jpar = [joints.index(par[i]) if par.get(i) in joints else -1 for i in joints]
    names = [N[i]['name'] for i in joints]
    V = []; W = []; J = []
    for n in N:
        if 'mesh' not in n or 'skin' not in n: continue
        for p in j['meshes'][n['mesh']]['primitives']:
            A = p['attributes']
            V.append(acc(j, b, A['POSITION'])); J.append(acc(j, b, A['JOINTS_0']).astype(int)); W.append(acc(j, b, A['WEIGHTS_0']).astype(float))
    return names, jpar, pos, np.concatenate(V), np.concatenate(J), np.concatenate(W)

# ---------------------------------------------------------------- obj
def read_obj(d):
    V, T, Nn = [], [], []; faces = []   # (material, [(v,t,n)...])
    mat = None
    for l in open(os.path.join(d, 'Police.obj')):
        s = l.split()
        if not s: continue
        if s[0] == 'v': V.append([float(x) for x in s[1:4]])
        elif s[0] == 'vt': T.append([float(x) for x in s[1:3]])
        elif s[0] == 'vn': Nn.append([float(x) for x in s[1:4]])
        elif s[0] == 'usemtl': mat = s[1]
        elif s[0] == 'f':
            c = [tuple(int(x) - 1 if x else -1 for x in (t.split('/') + ['', ''])[:3]) for t in s[1:]]
            for k in range(1, len(c) - 1): faces.append((mat, (c[0], c[k], c[k + 1])))
    return np.array(V), np.array(T), np.array(Nn), faces

def half_width(P, y, band=2.0, xmax=1e9):
    S = P[(np.abs(P[:, 1] - y) < band) & (np.abs(P[:, 0]) < xmax)]
    return np.abs(S[:, 0]).max()

# ---------------------------------------------------------------- police
def police(objdir, cashier_glb, dst):
    j, b = read_glb(cashier_glb)
    names, jpar, jp, cV, cJ, cW = skin_data(j, b)
    V, T, Nn, faces = read_obj(objdir)
    ji = {n.split(':')[-1].rsplit('_', 1)[0]: k for k, n in enumerate(names)}
    # landmarks
    top_c, top_p = cV[:, 1].max(), V[:, 1].max()
    tip_c, tip_p = np.abs(cV[:, 0]).max(), np.abs(V[:, 0]).max()
    armY_c = jp[ji['LeftArm'], 1]
    armY_p = np.median(V[np.abs(V[:, 0]) > 45][:, 1])
    sx_c = jp[ji['LeftArm'], 0]
    chest_c = half_width(cV, armY_c - 16, xmax=40); chest_p = half_width(V, armY_p - 16, xmax=40)
    sx_p = sx_c * chest_p / chest_c
    hipY_c = jp[ji['LeftUpLeg'], 1]
    hip_c = half_width(cV, hipY_c - 8); hip_p = half_width(V, hipY_c * armY_p / armY_c - 8)
    def arm_thick(P, sx, tip, ay):
        x0 = sx + 0.45 * (tip - sx); S = P[(np.abs(np.abs(P[:, 0]) - x0) < 1.5)]
        S = S[np.abs(S[:, 1] - ay) < 15]; return np.ptp(S[:, 1])
    th = arm_thick(V, sx_p, tip_p, armY_p) / arm_thick(cV, sx_c, tip_c, armY_c)
    depth = (np.ptp(V[np.abs(V[:, 1] - (armY_p - 16)) < 2][:, 2]) / np.ptp(cV[np.abs(cV[:, 1] - (armY_c - 16)) < 2][:, 2]))
    print('landmarks  cashier/police  top %.1f/%.1f tip %.1f/%.1f armY %.1f/%.1f shoulder %.1f/%.1f hips %.1f/%.1f arm %.2f depth %.2f'
          % (top_c, top_p, tip_c, tip_p, armY_c, armY_p, sx_c, sx_p, hip_c, hip_p, th, depth))
    def warp(P):
        P = P.copy(); out = np.empty_like(P)
        y = P[:, 1]
        yp = np.where(y < armY_c, y * armY_p / armY_c, armY_p + (y - armY_c) * (top_p - armY_p) / (top_c - armY_c))
        f = np.clip((y - hipY_c) / (armY_c - 18 - hipY_c), 0, 1)
        xr = (hip_p / hip_c) * (1 - f) + (sx_p / sx_c) * f
        out[:, 0] = P[:, 0] * xr; out[:, 1] = yp; out[:, 2] = P[:, 2] * depth
        arm = np.abs(P[:, 0]) > sx_c
        u = (np.abs(P[arm, 0]) - sx_c) / (tip_c - sx_c)
        out[arm, 0] = np.sign(P[arm, 0]) * (sx_p + u * (tip_p - sx_p))
        out[arm, 1] = armY_p + (P[arm, 1] - armY_c) * th
        out[arm, 2] = P[arm, 2] * th
        return out
    wV = warp(cV); wJ = warp(jp)
    # hands: the arm warp above fattens the arms to fit his jacket sleeves, which also spreads her
    # fingers far too wide. Map hand to hand instead, box to box, using the bare skin of each hand
    # (police: the Body material; cashier: everything past her sleeve), blending in over the wrist.
    body = np.zeros(len(V), bool)
    body_idx = sorted({c[0] for m, tri in faces if m == 'Body' for c in tri})
    body[body_idx] = True
    for sgn in (1.0, -1.0):
        ph = V[body & (V[:, 0] * sgn > 40)]
        ch = cV[cV[:, 0] * sgn > 64.0]
        cmin, cmax = ch.min(0), ch.max(0); pmin, pmax = ph.min(0), ph.max(0)
        cmin[0], cmax[0] = np.abs(ch[:, 0]).min(), np.abs(ch[:, 0]).max(); pmin[0], pmax[0] = np.abs(ph[:, 0]).min(), np.abs(ph[:, 0]).max()
        def hand_map(P):
            Q = np.empty_like(P)
            Q[:, 0] = sgn * (pmin[0] + (np.abs(P[:, 0]) - cmin[0]) * (pmax[0] - pmin[0]) / (cmax[0] - cmin[0]))
            for a in (1, 2): Q[:, a] = pmin[a] + (P[:, a] - cmin[a]) * (pmax[a] - pmin[a]) / (cmax[a] - cmin[a])
            return Q
        for arr, src in ((wV, cV), (wJ, jp)):
            sel = src[:, 0] * sgn > cmin[0] - 4.0
            if not sel.any(): continue
            k = np.clip((np.abs(src[sel, 0]) - (cmin[0] - 4.0)) / 4.0, 0, 1)[:, None]
            arr[sel] = arr[sel] * (1 - k) + hand_map(src[sel]) * k
        print('hand %+d: cashier x %.1f-%.1f -> police x %.1f-%.1f' % (sgn, cmin[0], cmax[0], pmin[0], pmax[0]))
    # end joints sitting at the origin in bind data keep their FK positions (already in jp)
    tree = cKDTree(wV)
    d, nb = tree.query(V, k=8)
    w = 1.0 / np.maximum(d, 0.05) ** 2
    acc_w = np.zeros((len(V), len(names)))
    for k in range(8):
        np.add.at(acc_w, (np.arange(len(V))[:, None], cJ[nb[:, k]]), (cW[nb[:, k]] * w[:, k:k + 1]))
    top4 = np.argsort(-acc_w, 1)[:, :4]
    tw = np.take_along_axis(acc_w, top4, 1); tw /= tw.sum(1, keepdims=True)
    # ---- build glTF
    S = 0.01
    bin_ = bytearray(); bvs = []; accs = []
    def push(arr, ctype, typ, target=None, minmax=False):
        arr = np.ascontiguousarray(arr)
        while len(bin_) % 4: bin_.append(0)
        bv = dict(buffer=0, byteOffset=len(bin_), byteLength=arr.nbytes)
        if target: bv['target'] = target
        bvs.append(bv); bin_.extend(arr.tobytes())
        a = dict(bufferView=len(bvs) - 1, componentType=ctype, count=len(arr), type=typ)
        if minmax: a['min'] = arr.min(0).tolist(); a['max'] = arr.max(0).tolist()
        accs.append(a); return len(accs) - 1
    images = []; textures = []
    def tex(fn, size, mode):
        I = Image.open(os.path.join(objdir, fn))
        if mode == 'rough':
            g = np.asarray(I.convert('L').resize((size, size), Image.LANCZOS), np.float32) / 255.0
            r = np.clip((1 - g) * 255, 0, 255).astype(np.uint8)
            I = Image.fromarray(np.stack([np.zeros_like(r) + 255, r, np.zeros_like(r)], 2), 'RGB')
        else:
            I = I.resize((size, size), Image.LANCZOS)
        has_a = I.mode == 'RGBA' and I.getchannel('A').getextrema()[0] < 250
        data = img_bytes(I, 'PNG', optimize=True) if has_a else img_bytes(I.convert('RGB'), 'JPEG', quality=90)
        while len(bin_) % 4: bin_.append(0)
        bvs.append(dict(buffer=0, byteOffset=len(bin_), byteLength=len(data))); bin_.extend(data)
        images.append(dict(bufferView=len(bvs) - 1, mimeType='image/png' if has_a else 'image/jpeg'))
        textures.append(dict(source=len(images) - 1, sampler=0)); return len(textures) - 1, has_a
    MATS = {'Body': ('Body', 1024), 'Top': ('Top', 512), 'Bottom': ('Bottom', 512), 'Shoes': ('Shoes', 512),
            'Hair': ('Hair', 512), 'Beard': ('Beard', 512), 'Moustache': ('Moustache', 512), 'Eyewear': ('Eyewear', 512)}
    materials = []; mat_idx = {}
    for m, (stem, size) in MATS.items():
        dt, alpha = tex('Police_%s_diffuse.png' % stem, size, 'color')
        nt, _ = tex('Police_%s_normal.png' % stem, size, 'normal')
        rt, _ = tex('Police_%s_gloss.png' % stem, size, 'rough')
        mm = dict(name='Police_' + m, pbrMetallicRoughness=dict(baseColorTexture=dict(index=dt), metallicRoughnessTexture=dict(index=rt), metallicFactor=0.0, roughnessFactor=1.0),
                  normalTexture=dict(index=nt))
        if m == 'Eyewear': mm['pbrMetallicRoughness']['metallicFactor'] = 0.3
        if alpha:
            mm['alphaMode'] = 'BLEND' if m == 'Eyewear' else 'MASK'
            if m != 'Eyewear': mm['alphaCutoff'] = 0.4
            mm['doubleSided'] = True
        mat_idx[m] = len(materials); materials.append(mm)
    prims = []
    by_mat = {}
    for m, tri in faces: by_mat.setdefault(m, []).append(tri)
    for m, tris in by_mat.items():
        keys = {}; idx = []
        for tri in tris:
            for c in tri:
                if c not in keys: keys[c] = len(keys)
                idx.append(keys[c])
        K = np.array(list(keys.keys()))
        P = V[K[:, 0]] * S; UV = T[K[:, 1]].copy(); UV[:, 1] = 1 - UV[:, 1]
        NN = Nn[K[:, 2]]; NN /= np.maximum(np.linalg.norm(NN, axis=1, keepdims=True), 1e-9)
        attrs = dict(POSITION=push(P.astype(np.float32), 5126, 'VEC3', 34962, True), NORMAL=push(NN.astype(np.float32), 5126, 'VEC3', 34962),
                     TEXCOORD_0=push(UV.astype(np.float32), 5126, 'VEC2', 34962),
                     JOINTS_0=push(top4[K[:, 0]].astype(np.uint16), 5123, 'VEC4', 34962),
                     WEIGHTS_0=push(tw[K[:, 0]].astype(np.float32), 5126, 'VEC4', 34962))
        prims.append(dict(attributes=attrs, indices=push(np.array(idx, np.uint32), 5125, 'SCALAR', 34963), material=mat_idx[m], mode=4))
    # skeleton: Mixamo names, identity orientations, translations from the warped bind positions
    nodes = [dict(name='Police', children=[1, 2])]
    nodes.append(dict(name='PoliceMesh', mesh=0, skin=0))
    jnode0 = len(nodes)
    clean = [n.split(':')[-1].rsplit('_', 1)[0] for n in names]
    for k, n in enumerate(clean):
        p = wJ[k] * S; pp = wJ[jpar[k]] * S if jpar[k] >= 0 else np.zeros(3)
        nodes.append(dict(name=('mixamorig:' + n) if k else 'Armature', translation=(p - pp).tolist()))
    for k in range(len(clean)):
        ch = [jnode0 + c for c in range(len(clean)) if jpar[c] == k]
        if ch: nodes[jnode0 + k]['children'] = ch
    nodes[0]['children'] = [1, jnode0]
    ibm = np.zeros((len(clean), 4, 4), np.float32)
    for k in range(len(clean)):
        M = np.eye(4); M[:3, 3] = -wJ[k] * S; ibm[k] = M.T
    skin = dict(joints=list(range(jnode0, jnode0 + len(clean))), skeleton=jnode0, inverseBindMatrices=push(ibm.reshape(-1, 16), 5126, 'MAT4'))
    g = dict(asset=dict(version='2.0', generator='JBR make_chars.py'), scene=0, scenes=[dict(nodes=[0])], nodes=nodes,
             meshes=[dict(name='Police', primitives=prims)], skins=[skin], materials=materials, textures=textures, images=images,
             samplers=[dict(magFilter=9729, minFilter=9987, wrapS=10497, wrapT=10497)], accessors=accs, bufferViews=bvs)
    print('police ->', write_glb(dst, g, bin_) // 1024, 'KB, verts', sum(accs[p['attributes']['POSITION']]['count'] for p in prims))

if __name__ == '__main__':
    if sys.argv[1] == 'cashier': cashier(sys.argv[2], sys.argv[3])
    else: police(sys.argv[2], sys.argv[3], sys.argv[4])
