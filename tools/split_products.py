#!/usr/bin/env python3
"""Make the fuel-stop shelf products individually shootable.

The web export baked every product set (boxes, bottles, caps, labels...) into nine huge
merged meshes. This tool:
  * splits each instance back out (instances are contiguous, fixed-size vertex blocks),
  * groups parts that belong together into one "item" (a cap or label sits inside its
    bottle / box), and gives every item an id stored in TEXCOORD_1 (u = id % 256, v = id / 256),
  * re-chunks the geometry into small spatial chunks so the game can cheaply rebuild the
    one chunk an item was knocked out of,
  * writes assets/world/fuelstop_products.json: per item its local AABB and the chunks it uses.

usage: split_products.py <in.glb> <out.glb> <out.json>
"""
import json, struct, sys
import numpy as np

COUNTS = [740, 72, 841, 2030, 2030, 1419, 189, 201, 156]   # used instances per baked set (from the web game)
CELL = 2.0

def read_glb(path):
    d = open(path, 'rb').read()
    l0, = struct.unpack_from('<I', d, 12); j = json.loads(d[20:20 + l0])
    o = 20 + l0; l1, = struct.unpack_from('<I', d, o); b = d[o + 8:o + 8 + l1]
    return j, b

def acc_np(j, b, i):
    a = j['accessors'][i]; bv = j['bufferViews'][a['bufferView']]
    n = {'VEC4': 4, 'VEC3': 3, 'VEC2': 2, 'SCALAR': 1}[a['type']]
    dt = {5126: np.float32, 5125: np.uint32, 5123: np.uint16, 5121: np.uint8}[a['componentType']]
    stride = bv.get('byteStride', 0); off = bv.get('byteOffset', 0) + a.get('byteOffset', 0)
    item = np.dtype(dt).itemsize * n
    if stride and stride != item:
        raw = np.frombuffer(b, np.uint8, a['count'] * stride, off).reshape(-1, stride)[:, :item]
        return np.ascontiguousarray(raw).view(dt).reshape(-1, n)
    return np.frombuffer(b, dt, a['count'] * n, off).reshape(-1, n).copy()

def main(src, dst, jdst):
    j, b = read_glb(src)
    N = j['nodes']
    baked = [i for i, n in enumerate(N) if n.get('name') == 'Products_baked']
    assert len(baked) == len(COUNTS), baked
    parent = next(i for i, n in enumerate(N) if set(baked) <= set(n.get('children', [])))
    inst = []   # (set, pos, nor, uv, col, mn, mx)
    mats = []
    for s, ni in enumerate(baked):
        p = j['meshes'][N[ni]['mesh']]['primitives'][0]; mats.append(p['material'])
        A = {k: acc_np(j, b, v) for k, v in p['attributes'].items()}
        nv = len(A['POSITION']); V = nv // COUNTS[s]; assert V * COUNTS[s] == nv
        for k in range(COUNTS[s]):
            sl = slice(k * V, (k + 1) * V); P = A['POSITION'][sl]
            inst.append(dict(set=s, P=P, N=A['NORMAL'][sl], U=A['TEXCOORD_0'][sl], C=A['COLOR_0'][sl], mn=P.min(0), mx=P.max(0)))
    # group: a part whose centre sits inside a bigger part's (slightly grown) box belongs to it
    mn = np.array([i['mn'] for i in inst]); mx = np.array([i['mx'] for i in inst])
    ctr = (mn + mx) / 2; vol = np.prod(np.maximum(mx - mn, 1e-4), 1)
    owner = np.arange(len(inst)); sets = np.array([x['set'] for x in inst])
    pad = 0.012
    for a in range(len(inst)):
        inside = np.all((ctr[a] >= mn - pad) & (ctr[a] <= mx + pad), 1) & (vol > vol[a] * 1.5)
        inside &= sets != sets[a]
        cand = np.nonzero(inside)[0]
        if len(cand): owner[a] = cand[np.argmin(vol[cand])]
    # follow chains to the root owner
    for a in range(len(inst)):
        r = a
        while owner[r] != r: r = owner[r]
        owner[a] = r
    roots = sorted(set(owner.tolist()))
    item_id = {r: k for k, r in enumerate(roots)}
    items = [dict(mn=[1e9] * 3, mx=[-1e9] * 3, chunks=set()) for _ in roots]
    chunks = {}   # (set, cx, cz) -> list of instance idx
    for a, it in enumerate(inst):
        iid = item_id[owner[a]]; c = ctr[owner[a]]
        key = (it['set'], int(np.floor(c[0] / CELL)), int(np.floor(c[2] / CELL)))
        chunks.setdefault(key, []).append(a); it['id'] = iid
        I = items[iid]; I['mn'] = np.minimum(I['mn'], it['mn']).tolist(); I['mx'] = np.maximum(I['mx'], it['mx']).tolist()
    # ---- rebuild the glTF: drop the baked meshes, add chunk meshes
    new_bin = bytearray(); new_bv = []; new_acc = []
    def push(arr, typ, minmax=False):
        arr = np.ascontiguousarray(arr, np.float32)
        while len(new_bin) % 4: new_bin.append(0)
        new_bv.append(dict(buffer=0, byteOffset=len(new_bin), byteLength=arr.nbytes, target=34962))
        new_bin.extend(arr.tobytes())
        a = dict(bufferView=len(new_bv) - 1, componentType=5126, count=len(arr), type=typ)
        if minmax: a['min'] = arr.min(0).tolist(); a['max'] = arr.max(0).tolist()
        new_acc.append(a); return len(new_acc) - 1
    # copy every still-used bufferView first (images, other meshes)
    keep_nodes = [i for i in range(len(N)) if i not in baked]
    used_acc = set(); used_bv = set()
    removed_meshes = {N[i]['mesh'] for i in baked}
    for mi, m in enumerate(j['meshes']):
        if mi in removed_meshes: continue
        for p in m['primitives']:
            used_acc.update(p['attributes'].values())
            if 'indices' in p: used_acc.add(p['indices'])
    for a in used_acc: used_bv.add(j['accessors'][a]['bufferView'])
    for im in j.get('images', []):
        if 'bufferView' in im: used_bv.add(im['bufferView'])
    bv_map = {}
    for bi in sorted(used_bv):
        bv = dict(j['bufferViews'][bi]); o = bv.get('byteOffset', 0)
        data = b[o:o + bv['byteLength']]
        while len(new_bin) % 4: new_bin.append(0)
        bv['byteOffset'] = len(new_bin); new_bin.extend(data); new_bv.append(bv); bv_map[bi] = len(new_bv) - 1
    acc_map = {}
    for ai in sorted(used_acc):
        a = dict(j['accessors'][ai]); a['bufferView'] = bv_map[a['bufferView']]; new_acc.append(a); acc_map[ai] = len(new_acc) - 1
    meshes = []; mesh_map = {}
    for mi, m in enumerate(j['meshes']):
        if mi in removed_meshes: continue
        m = json.loads(json.dumps(m))
        for p in m['primitives']:
            p['attributes'] = {k: acc_map[v] for k, v in p['attributes'].items()}
            if 'indices' in p: p['indices'] = acc_map[p['indices']]
        meshes.append(m); mesh_map[mi] = len(meshes) - 1
    for im in j.get('images', []):
        if 'bufferView' in im: im['bufferView'] = bv_map[im['bufferView']]
    # chunk meshes
    chunk_nodes = []
    for key in sorted(chunks):
        s, cx, cz = key; name = 'Products_baked_s%d_%d_%d' % (s, cx, cz)
        L = chunks[key]
        P = np.concatenate([inst[a]['P'] for a in L]); Nn = np.concatenate([inst[a]['N'] for a in L])
        U = np.concatenate([inst[a]['U'] for a in L]); C = np.concatenate([inst[a]['C'] for a in L])
        ids = np.concatenate([np.full(len(inst[a]['P']), inst[a]['id']) for a in L])
        U2 = np.stack([ids % 256, ids // 256], 1).astype(np.float32)
        attrs = dict(POSITION=push(P, 'VEC3', True), NORMAL=push(Nn, 'VEC3'), TEXCOORD_0=push(U, 'VEC2'), TEXCOORD_1=push(U2, 'VEC2'), COLOR_0=push(C, 'VEC3'))
        meshes.append(dict(primitives=[dict(attributes=attrs, material=mats[s], mode=4)]))
        chunk_nodes.append(dict(name=name, mesh=len(meshes) - 1))
        for a in L: items[inst[a]['id']]['chunks'].add(name)
    # nodes: remap indices
    old2new = {}; nodes = []
    for i in keep_nodes:
        old2new[i] = len(nodes); nodes.append(json.loads(json.dumps(N[i])))
    first_chunk = len(nodes); nodes.extend(chunk_nodes)
    for n in nodes[:first_chunk]:
        if 'children' in n: n['children'] = [old2new[c] for c in n['children'] if c in old2new]
        if 'mesh' in n: n['mesh'] = mesh_map[n['mesh']]
    nodes[old2new[parent]].setdefault('children', []).extend(range(first_chunk, len(nodes)))
    for sc in j['scenes']: sc['nodes'] = [old2new[c] for c in sc['nodes']]
    j['nodes'] = nodes; j['meshes'] = meshes; j['accessors'] = new_acc; j['bufferViews'] = new_bv
    while len(new_bin) % 4: new_bin.append(0)
    j['buffers'] = [dict(byteLength=len(new_bin))]
    js = json.dumps(j, separators=(',', ':')).encode()
    while len(js) % 4: js += b' '
    out = struct.pack('<III', 0x46546C67, 2, 28 + len(js) + len(new_bin)) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(new_bin), 0x004E4942) + bytes(new_bin)
    open(dst, 'wb').write(out)
    json.dump(dict(cell=CELL, items=[dict(mn=[round(v, 4) for v in it['mn']], mx=[round(v, 4) for v in it['mx']], chunks=sorted(it['chunks'])) for it in items]),
              open(jdst, 'w'), separators=(',', ':'))
    print('instances', len(inst), 'items', len(items), 'chunks', len(chunk_nodes), 'glb', len(out))

if __name__ == '__main__':
    main(*sys.argv[1:4])
