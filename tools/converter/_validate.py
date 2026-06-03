import importlib.util, os, posixpath, json, time, ctypes
from collections import Counter

spec = importlib.util.spec_from_file_location('cv', 'convert.py')
cv = importlib.util.module_from_spec(spec); spec.loader.exec_module(cv)
chain = cv.Chain(r'c:/WoWCore/WOW335/Data')
lib = cv.load_lib()


def has(src):
    if not src:
        return False
    return chain.index.get(src.replace('/', '\\').lower().encode()) is not None


def resolve(model_rel, uri):
    # texUri даёт относительный путь (с ../), pathTo — абсолютный (lowercase, ведущий /)
    if uri.startswith('/'):
        return uri.lstrip('/')
    if '../' in uri or './' in uri:
        return posixpath.normpath(posixpath.join(posixpath.dirname(model_rel), uri))
    return uri


def src_of(ref, conv_ext, src_exts):
    base = ref[:-len(conv_ext)] if ref.lower().endswith(conv_ext) else ref
    return [base + e for e in src_exts]


def any_has(variants):
    return any(has(v.lstrip('/')) for v in variants)


mt = mw = ma = 0
bad_m2 = bad_wmo = bad_adt = 0
miss = []
t0 = time.time(); processed = 0

for rel in chain.paths():
    ext = rel.rsplit('.', 1)[-1] if '.' in rel else ''
    if ext not in ('m2', 'wmo', 'adt'):
        continue
    if ext == 'wmo' and cv.is_wmo_group(rel):
        continue
    data = chain.read(rel)
    if not data:
        continue
    p, n = cv.buf(data)

    if ext == 'm2':
        sk = chain.read(rel[:-3] + '00.skin'); sp, sn = cv.buf(sk)
        if lib.wc_convert_m2(p, n, sp, sn, rel.encode()) != 0:
            lib.wc_free(); continue
        arts = {nm: d for nm, d in cv.artifacts(lib)}; lib.wc_free()
        gl = json.loads(arts[cv.stem_of(rel) + '.gltf'])
        mt += 1; lb = 0
        for im in gl.get('images', []):
            ap = resolve(rel, im['uri'])
            if not any_has(src_of(ap, '.png', ['.blp'])):
                miss.append(('m2', rel, im['uri'], ap)); lb += 1
        if lb:
            bad_m2 += 1

    elif ext == 'wmo':
        groups = []; i = 0
        while True:
            gd = chain.read(f"{rel[:-4]}_{i:03d}.wmo")
            if not gd:
                break
            groups.append(gd); i += 1
        arr_p = (ctypes.POINTER(ctypes.c_uint8) * len(groups))()
        arr_s = (ctypes.c_size_t * len(groups))()
        keep = []
        for k, gd in enumerate(groups):
            gp, gn = cv.buf(gd); keep.append(gp); arr_p[k], arr_s[k] = gp, gn
        if lib.wc_convert_wmo(p, n, arr_p, arr_s, len(groups), rel.encode()) != 0:
            lib.wc_free(); continue
        arts = {nm: d for nm, d in cv.artifacts(lib)}; lib.wc_free()
        mw += 1; lb = 0
        gl = json.loads(arts[cv.stem_of(rel) + '.gltf'])
        for im in gl.get('images', []):
            ap = resolve(rel, im['uri'])
            if not any_has(src_of(ap, '.png', ['.blp'])):
                miss.append(('wmo-tex', rel, im['uri'], ap)); lb += 1
        wj = json.loads(arts[cv.stem_of(rel) + '.wmo.json'])
        for v in (wj.get('doodadNames') or {}).values():
            ap = resolve(rel, v)
            if not any_has(src_of(ap, '.gltf', ['.m2', '.mdx'])):
                miss.append(('wmo-dd', rel, v, ap)); lb += 1
        if lb:
            bad_wmo += 1

    else:  # adt
        if lib.wc_convert_adt(p, n, cv.stem_of(rel).encode()) != 0:
            lib.wc_free(); continue
        arts = {nm: d for nm, d in cv.artifacts(lib)}; lib.wc_free()
        tj = json.loads(arts[cv.stem_of(rel) + '/terrain.json'])
        ma += 1; lb = 0
        for t in tj.get('tiles', []):
            if not any_has(src_of(t, '.png', ['.blp'])):
                miss.append(('adt-tile', rel, t, t)); lb += 1
        for v in tj.get('doodadNames', []):
            if not any_has(src_of(v, '.gltf', ['.m2', '.mdx'])):
                miss.append(('adt-dd', rel, v, v)); lb += 1
        for v in tj.get('wmoNames', []):
            if not any_has(src_of(v, '.gltf', ['.wmo'])):
                miss.append(('adt-wmo', rel, v, v)); lb += 1
        if lb:
            bad_adt += 1

    processed += 1
    if processed % 1000 == 0:
        print(f"[{processed}] m2={mt} wmo={mw} adt={ma} | bad m2={bad_m2} wmo={bad_wmo} adt={bad_adt} miss={len(miss)} {time.time()-t0:.0f}s", flush=True)

print(f"\n=== TOTAL m2={mt} wmo={mw} adt={ma} ===")
print(f"models with missing refs: m2={bad_m2} wmo={bad_wmo} adt={bad_adt}")
print(f"total missing refs: {len(miss)}")
print("by kind:", dict(Counter(k for k, *_ in miss)))
with open('_miss.txt', 'w', encoding='utf-8') as f:
    for k, m, r, s in miss:
        f.write(f"{k}\t{m}\t{r}\t{s}\n")
print("\nfirst 40 missing:")
for k, m, r, s in miss[:40]:
    print(f"  [{k}] {m}  ref={r}")
