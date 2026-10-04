"""Re-encode opaque PNG textures inside .glb files as JPEG (smaller downloads, same look)."""
import json, struct, io, sys
from PIL import Image
for f in sys.argv[1:]:
    d = open(f, 'rb').read(); jl = struct.unpack('<I', d[12:16])[0]; j = json.loads(d[20:20 + jl]); bin_ = d[20 + jl + 8:]
    bvs = j['bufferViews']; imgs = j.get('images', [])
    blobs = [bytes(bin_[bv.get('byteOffset', 0):bv.get('byteOffset', 0) + bv['byteLength']]) for bv in bvs]
    conv = 0
    for im in imgs:
        if im.get('mimeType') != 'image/png': continue
        b = blobs[im['bufferView']]; I = Image.open(io.BytesIO(b))
        if I.mode in ('RGBA', 'LA') and I.getchannel('A').getextrema()[0] < 250: continue
        o = io.BytesIO(); I.convert('RGB').save(o, 'JPEG', quality=88)
        if o.tell() < len(b): blobs[im['bufferView']] = o.getvalue(); im['mimeType'] = 'image/jpeg'; conv += 1
    out = bytearray()
    for bv, b in zip(bvs, blobs):
        while len(out) % 4: out.append(0)
        bv['byteOffset'] = len(out); bv['byteLength'] = len(b); out += b
    while len(out) % 4: out.append(0)
    j['buffers'] = [{'byteLength': len(out)}]
    js = json.dumps(j, separators=(',', ':')).encode(); js += b' ' * ((4 - len(js) % 4) % 4)
    g = struct.pack('<III', 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(out)) + struct.pack('<II', len(js), 0x4E4F534A) + js + struct.pack('<II', len(out), 0x004E4942) + bytes(out)
    open(f, 'wb').write(g); print(f, len(d) // 1024, '->', len(g) // 1024, 'KB,', conv, 'textures to JPEG')
