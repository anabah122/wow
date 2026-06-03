#!/usr/bin/env python3
"""Пакетный конвертер WoW-ассетов: MPQ (StormLib) -> наш glTF/PNG/JSON (wowconv.dll).

Python открывает цепочку MPQ через StormLib (ctypes), обходит файлы и кормит байты
C-API конвертеру; C++ возвращает артефакты в памяти, Python пишет их в зеркальную
lowercase-структуру.

  python convert.py <DataDir> <dstDir> [типы] [-skip a,b,c]
    типы = m2|wmo|adt|blp, можно несколько через запятую (m2,wmo,blp); пусто = все
    -skip = сегменты пути пропустить (через запятую), напр. item,sound
"""
import ctypes as C
from ctypes import wintypes
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))

# Все .MPQ рекурсивно из data_dir, отсортированные по возрастанию приоритета
# (последний главнее). Приоритет WotLK: base-архивы < патчи; patch-N с большим N выше;
# одноимённый локальный архив (в подпапке локали, напр. ruRU/) идёт сразу после базового.
def archive_sequence(data_dir):
    found = []
    for root, _, files in os.walk(data_dir):
        for f in files:
            if f.lower().endswith(".mpq"):
                found.append(os.path.join(root, f))

    def rank(path):
        name = os.path.basename(path).lower()
        stem = name[:-4]
        # номер патча: patch-3 -> 3, patch -> 0, не-патч -> -1
        if stem == "patch" or stem.startswith("patch-"):
            tail = stem[6:]               # после "patch-"
            num = int(tail) if tail.isdigit() else (0 if stem == "patch" else 0)
            base = 1000 + num             # патчи всегда выше базовых
        else:
            order = {"common": 0, "common-2": 1, "expansion": 2, "lichking": 3}
            base = order.get(stem, 4)     # прочие base-архивы (локали и т.п.) — после известных
        # локализованные одноимённые (есть суффикс локали или лежат в подпапке локали)
        # ставим чуть выше своего базового, чтобы перекрывали англ. при равенстве
        loc = 1 if (os.sep + "enus" not in path.lower() and _is_locale_path(path)) else 0
        return (base, loc, name)

    found.sort(key=rank)
    return found


_LOCALES = ("ruru", "enus", "engb", "dede", "eses", "esmx", "frfr",
            "itit", "kokr", "ptbr", "ptpt", "zhcn", "zhtw")


def _is_locale_path(path):
    p = path.lower()
    return any((os.sep + loc + os.sep) in p or "-" + loc + "." in p for loc in _LOCALES)


SFILE_INVALID_SIZE = 0xFFFFFFFF


class _FindData(C.Structure):
    _fields_ = [
        ("cFileName", C.c_char * 1024),
        ("szPlainName", C.c_char_p),
        ("dwHashIndex", wintypes.DWORD),
        ("dwBlockIndex", wintypes.DWORD),
        ("dwFileSize", wintypes.DWORD),
        ("dwFileFlags", wintypes.DWORD),
        ("dwCompSize", wintypes.DWORD),
        ("dwFileTimeLo", wintypes.DWORD),
        ("dwFileTimeHi", wintypes.DWORD),
        ("lcLocale", wintypes.DWORD),
    ]


def _load_storm():
    dll = os.path.join(HERE, "StormLib.dll")
    if not os.path.exists(dll):
        sys.exit(f"{dll} not found")
    s = C.WinDLL(dll)
    H = C.c_void_p
    s.SFileOpenArchive.argtypes = [C.c_char_p, wintypes.DWORD, wintypes.DWORD, C.POINTER(H)]
    s.SFileOpenArchive.restype = wintypes.BOOL
    s.SFileCloseArchive.argtypes = [H]
    s.SFileOpenFileEx.argtypes = [H, C.c_char_p, wintypes.DWORD, C.POINTER(H)]
    s.SFileOpenFileEx.restype = wintypes.BOOL
    s.SFileGetFileSize.argtypes = [H, C.POINTER(wintypes.DWORD)]
    s.SFileGetFileSize.restype = wintypes.DWORD
    s.SFileReadFile.argtypes = [H, C.c_void_p, wintypes.DWORD, C.POINTER(wintypes.DWORD), C.c_void_p]
    s.SFileReadFile.restype = wintypes.BOOL
    s.SFileCloseFile.argtypes = [H]
    s.SFileFindFirstFile.argtypes = [H, C.c_char_p, C.POINTER(_FindData), C.c_char_p]
    s.SFileFindFirstFile.restype = H
    s.SFileFindNextFile.argtypes = [H, C.POINTER(_FindData)]
    s.SFileFindNextFile.restype = wintypes.BOOL
    s.SFileFindClose.argtypes = [H]
    s.SFileFindClose.restype = wintypes.BOOL
    s.SFileOpenPatchArchive.argtypes = [H, C.c_char_p, C.c_char_p, wintypes.DWORD]
    s.SFileOpenPatchArchive.restype = wintypes.BOOL
    return s


def read_from(s, h, wow_path):
    """Прочитать файл из архива h (хендл). bytes или None."""
    name = wow_path.replace("/", "\\")
    hf = C.c_void_p()
    if not s.SFileOpenFileEx(h, name.encode(), 0, C.byref(hf)):
        return None
    size = s.SFileGetFileSize(hf, None)
    if size == SFILE_INVALID_SIZE:
        s.SFileCloseFile(hf)
        return None
    buf = (C.c_uint8 * size)()
    got = wintypes.DWORD(0)
    ok = s.SFileReadFile(hf, buf, size, C.byref(got), None)
    s.SFileCloseFile(hf)
    if ok or got.value == size:
        return bytes(buf[:got.value])
    return None


def list_archive(s, h):
    """Имена всех файлов архива h (Find по своему хендлу)."""
    fd = _FindData()
    hf = s.SFileFindFirstFile(h, b"*", C.byref(fd), None)
    if not hf:
        return
    while True:
        name = fd.cFileName.decode("latin-1")
        if name and not name.startswith("("):
            yield name
        if not s.SFileFindNextFile(hf, C.byref(fd)):
            break
    s.SFileFindClose(hf)


# --- C-API (wowconv.dll) ---
def load_lib():
    dll = os.path.join(HERE, "wowconv.dll")
    if not os.path.exists(dll):
        sys.exit(f"{dll} not found — build it: cmake --build build --config Release")
    lib = C.CDLL(dll)
    P, S, Z = C.c_char_p, C.c_size_t, C.c_void_p
    B = C.POINTER(C.c_uint8)
    lib.wc_convert_m2.argtypes = [B, S, B, S, P]
    lib.wc_convert_wmo.argtypes = [B, S, C.POINTER(B), C.POINTER(S), S, P]
    lib.wc_convert_adt.argtypes = [B, S, P, C.c_int]
    lib.wc_convert_blp.argtypes = [B, S, P]
    for fn in (lib.wc_convert_m2, lib.wc_convert_wmo, lib.wc_convert_adt, lib.wc_convert_blp):
        fn.restype = C.c_int
    lib.wc_artifact_count.restype = S
    lib.wc_artifact_name.restype = P
    lib.wc_artifact_name.argtypes = [S]
    lib.wc_artifact_size.restype = S
    lib.wc_artifact_size.argtypes = [S]
    lib.wc_artifact_data.restype = B
    lib.wc_artifact_data.argtypes = [S]
    return lib


def buf(data):
    """bytes -> (POINTER(c_uint8), size)."""
    if not data:
        return None, 0
    arr = (C.c_uint8 * len(data)).from_buffer_copy(data)
    return C.cast(arr, C.POINTER(C.c_uint8)), len(data)


def artifacts(lib):
    """Список (name, bytes) из последнего wc_convert_*."""
    out = []
    for i in range(lib.wc_artifact_count()):
        name = C.cast(lib.wc_artifact_name(i), C.c_char_p).value.decode()
        n = lib.wc_artifact_size(i)
        ptr = lib.wc_artifact_data(i)
        if not ptr or n == 0:           # пустой артефакт -> пишем пустой файл, не падаем
            out.append((name, b""))
            continue
        out.append((name, bytes(C.cast(ptr, C.POINTER(C.c_uint8 * n)).contents)))
    return out


def write_artifacts(lib, dst, reldir):
    for name, data in artifacts(lib):
        path = os.path.join(dst, reldir, name)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(path, "wb") as f:
            f.write(data)


def stem_of(wow_path):
    base = wow_path.replace("\\", "/").rsplit("/", 1)[-1]
    return base.rsplit(".", 1)[0].lower()


def wdt_big_alpha(wdt_data):
    """MPHD.flags & (0x4|0x80) -> альфа MCAL хранится 8-bit (иначе 4-bit). Парсим чанки WDT."""
    i = 0
    while i + 8 <= len(wdt_data):
        tag = wdt_data[i:i+4][::-1]                      # теги в файле перевёрнуты
        size = int.from_bytes(wdt_data[i+4:i+8], "little")
        if tag == b"MPHD" and i + 8 + 4 <= len(wdt_data):
            flags = int.from_bytes(wdt_data[i+8:i+12], "little")
            return bool(flags & (0x4 | 0x80))
        i += 8 + size
    return False


def is_wmo_group(wow_path):
    s = stem_of(wow_path)
    return len(s) >= 4 and s[-4] == "_" and s[-3:].isdigit()


def output_path(dst, ext, rel):
    """Главный артефакт типа на диске — по его наличию решаем «уже сконвертировано»."""
    reldir = os.path.dirname(rel)
    stem = stem_of(rel)
    if ext == "blp":
        return os.path.join(dst, reldir, stem + ".png")
    if ext == "adt":
        return os.path.join(dst, reldir, stem, "terrain.json")
    return os.path.join(dst, reldir, stem + ".gltf")   # m2/wmo


def main():
    if len(sys.argv) < 3:
        sys.exit(__doc__)
    data_dir, dst = sys.argv[1], sys.argv[2]
    type_filters = set()          # пусто = все типы; иначе только перечисленные
    skip = []
    i = 3
    while i < len(sys.argv):
        a = sys.argv[i]
        if a == "-skip" and i + 1 < len(sys.argv):
            skip = [s for s in sys.argv[i + 1].lower().split(",") if s]
            i += 2
        else:
            type_filters |= {t.lstrip(".") for t in a.lower().split(",") if t}
            i += 1

    paths = archive_sequence(data_dir)
    if not paths:
        sys.exit(f"no MPQ archives found in {data_dir}")
    print(f"найдено {len(paths)} MPQ:", flush=True)
    for p in paths:
        print(f"  {os.path.relpath(p, data_dir)}", flush=True)

    s = _load_storm()
    lib = load_lib()
    exts = {"m2", "wmo", "adt", "blp"}
    done = {e: 0 for e in exts}
    fail = {e: 0 for e in exts}
    skip_n = {e: 0 for e in exts}
    seen = set()          # dedup: уже обработанные пути (старший приоритет первым)
    big_alpha = {}        # map-имя -> bool (формат MCAL: 8-bit при big_alpha, иначе 4-bit)

    # архивы от старшего приоритета к младшему (старший выигрывает при дублях)
    for p in reversed(paths):
        h = C.c_void_p()
        if not s.SFileOpenArchive(p.encode(), 0, 0x00000100, C.byref(h)):
            print(f"  failed to open {p}", file=sys.stderr, flush=True)
            continue
        print(f"\n=== {os.path.basename(p)} ===", flush=True)
        n_arch = 0
        for orig in list_archive(s, h):
            rel = orig.replace("\\", "/").lower()
            ext = rel.rsplit(".", 1)[-1] if "." in rel else ""
            if ext not in exts:
                continue
            if type_filters and ext not in type_filters:
                continue
            if any(f"/{seg}/" in f"/{rel}" for seg in skip):
                continue
            if ext == "wmo" and is_wmo_group(rel):
                continue
            if rel in seen:
                continue
            seen.add(rel)

            if os.path.exists(output_path(dst, ext, rel)):
                skip_n[ext] += 1
                continue

            data = read_from(s, h, orig)
            if not data:
                print(f"FAIL read [{ext}] {rel}", file=sys.stderr, flush=True)
                fail[ext] += 1
                continue
            reldir = os.path.dirname(rel)
            pb, nb = buf(data)
            if ext == "m2":
                sp, sn = buf(read_from(s, h, orig[:-3] + "00.skin"))
                rc = lib.wc_convert_m2(pb, nb, sp, sn, rel.encode())
            elif ext == "wmo":
                groups, i2 = [], 0
                while True:
                    gd = read_from(s, h, f"{orig[:-4]}_{i2:03d}.wmo")
                    if not gd:
                        break
                    groups.append(gd)
                    i2 += 1
                arr_p = (C.POINTER(C.c_uint8) * len(groups))()
                arr_s = (C.c_size_t * len(groups))()
                keep = []
                for k, gd in enumerate(groups):
                    gp, gn = buf(gd)
                    keep.append(gp)
                    arr_p[k], arr_s[k] = gp, gn
                rc = lib.wc_convert_wmo(pb, nb, arr_p, arr_s, len(groups), rel.encode())
            elif ext == "adt":
                # формат MCAL зависит от WDT MPHD big_alpha; читаем WDT карты один раз
                mapname = reldir.rsplit("/", 1)[-1]
                if mapname not in big_alpha:
                    wdt = read_from(s, h, f"{reldir}/{mapname}.wdt")
                    if wdt:                              # кэшируем только при найденном WDT
                        big_alpha[mapname] = wdt_big_alpha(wdt)
                ba = big_alpha.get(mapname, False)
                rc = lib.wc_convert_adt(pb, nb, stem_of(rel).encode(), 1 if ba else 0)
            else:
                rc = lib.wc_convert_blp(pb, nb, stem_of(rel).encode())

            if rc == 0:
                write_artifacts(lib, dst, reldir)
                done[ext] += 1
            else:
                print(f"FAIL convert [{ext}] rc={rc} {rel}", file=sys.stderr, flush=True)
                fail[ext] += 1
            lib.wc_free()

            n_arch += 1
            if n_arch % 1000 == 0:
                d = sum(done.values()); f = sum(fail.values())
                print(f"  [{os.path.basename(p)} +{n_arch}] всего ok={d} fail={f}", flush=True)
        s.SFileCloseArchive(h)

    print("\n=== DONE ===")
    for e in ("m2", "wmo", "adt", "blp"):
        print(f"  {e}: {done[e]} ok, {fail[e]} fail, {skip_n[e]} skip")
    print(f"всего: {sum(done.values())} ok -> {dst}", flush=True)


if __name__ == "__main__":
    main()
