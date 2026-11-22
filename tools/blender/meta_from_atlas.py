# 구운 원본 폴더(art_source/baked)가 없는 PC에서 새 동작만 덧붙여 구울 수 있게,
# 게임에 들어 있는 그림 묶음 설명(art/sprites/<종류>_<이름>.json)에서 굽기용 meta.json 을 되살린다.
#   실행: python tools/blender/meta_from_atlas.py characters firefighter_v2
#   (이미 meta.json 이 있으면 건드리지 않는다)
import json, os, sys

kind, name = sys.argv[1], sys.argv[2]
root = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
src = os.path.join(root, "art", "sprites", "%s_%s.json" % (kind, name))
folder = os.path.join(root, "art_source", "baked", kind, name)
dst = os.path.join(folder, "meta.json")
if os.path.exists(dst):
    print("META_EXISTS", dst)
    sys.exit(0)
atlas = json.load(open(src, encoding="utf-8"))
meta = {"kind": atlas["kind"], "scale": atlas["scale"], "frame": atlas["frame"], "anchor": atlas["anchor"], "directions": atlas["directions"],
        "anims": {a: {"frames": v["frames"], "note": "아틀라스에서 되살림"} for a, v in atlas["anims"].items()}}
for k in ("nominal", "h_m", "size_m", "type", "nozzle", "stand"):
    if k in atlas:
        meta[k] = atlas[k]
os.makedirs(folder, exist_ok=True)
json.dump(meta, open(dst, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
print("META_WRITTEN", dst, "anims", len(meta["anims"]))
