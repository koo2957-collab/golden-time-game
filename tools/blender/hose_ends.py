# 대원 그림에 구워진 호스의 양 끝 자리를 장면 파일에서 재서 data/ui/hose_ends.json 에 적는다 (2026-11-24).
#   실행: blender -b --factory-startup -P tools/blender/hose_ends.py
# 왜: 대원이 든 호스는 대원 그림에 구워져 있고 바닥 호스는 게임이 그린다 — 둘이 만나려면 게임이 "그림 속 호스가 어디서 끝나는지"를
#     알아야 한다 (관창 끝 자리를 적어 물줄기를 잇는 것과 같은 방식). 그림 속 호스는 그 사람 기준으로 움직이지 않으므로
#     그림을 다시 굽지 않고 자리만 잰다.
# 적는 값: 동작마다 front(관창 쪽 끝)·back(펌프차 쪽 끝) = [앞으로 fwd_m, 오른쪽으로 right_m, 높이 h_m] — 그 사람 발밑 기준, 보는 방향 기준.
#   관창수(관창만 들고 호스 조각은 없음)는 back 만 = 관창 결합구 자리 (뒤 사람의 호스가 거기서 시작한다).
# 장면 목록·사람 이름은 tools/blender/bake_config.json 의 scenes 를 그대로 읽는다 (HOSE_SCENES 에 든 장면만).

import json
import os

import bpy
import mathutils

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.abspath(os.path.join(HERE, "..", ".."))
OUT = os.path.join(PROJECT, "data", "ui", "hose_ends.json")
HOSE_SCENES = ("spray_squad", "spray_pair", "spray_low_squad", "spray_low_pair")

CFG = json.load(open(os.path.join(HERE, "bake_config.json"), encoding="utf-8"))


def rel(p, rig):
    """월드 좌표 p 를 그 사람 기준 [앞, 오른쪽, 높이]로 (모델 앞 = -Y, 오른쪽 = -X)"""
    o = rig.matrix_world.translation
    return [round(-(p.y - o.y), 3), round(-(p.x - o.x), 3), round(max(0.0, p.z), 3)]


def children(rig):
    out = []
    todo = [rig]
    while todo:
        cur = todo.pop()
        for o in bpy.data.objects:
            if o.parent == cur:
                out.append(o)
                todo.append(o)
    return out


ends = {}
for spec in CFG.get("scenes", []):
    if spec.get("name") not in HOSE_SCENES:
        continue
    bpy.ops.wm.open_mainfile(filepath=os.path.join(PROJECT, spec["blend"]))
    bpy.context.scene.frame_set(int(spec.get("frame_start", 1)))
    bpy.context.view_layer.update()
    for anim, actor in spec["actors"].items():
        if isinstance(actor, str):
            actor = {"rig": actor}
        rig = bpy.data.objects[actor["rig"]]
        mine = children(rig)
        entry = {"scene": spec["name"]}
        # 이 사람 그림에 들어가는 호스 곡선 (장면에 저장된 보이기 상태 그대로 — bake.py 와 같다)
        pts = []
        for o in mine:
            if o.type == "CURVE" and o.name.split(".")[0].startswith("hose") and not o.hide_render:
                for sp in o.data.splines:
                    seq = sp.bezier_points if sp.type == "BEZIER" else sp.points
                    pts.append(o.matrix_world @ seq[0].co.to_3d())
                    pts.append(o.matrix_world @ seq[len(seq) - 1].co.to_3d())
        if pts:
            # 앞(-Y)으로 가장 나간 점이 관창 쪽 끝, 가장 뒤가 펌프차 쪽 끝
            entry["front"] = rel(min(pts, key=lambda p: p.y), rig)
            entry["back"] = rel(max(pts, key=lambda p: p.y), rig)
        elif actor.get("nozzle_from"):
            cp = next((o for o in mine if o.name.split(".")[0] == actor["nozzle_from"]), None)
            if cp is not None:
                box = [cp.matrix_world @ mathutils.Vector(c) for c in cp.bound_box]
                entry["back"] = rel(sum(box, mathutils.Vector()) / 8.0, rig)
        if len(entry) > 1:
            ends[anim] = entry
            print("[hose_ends]", anim, entry, flush=True)

# 한 줄에 동작 하나씩 — 사람이 읽고 견주기 쉽게
lines = ["{",
         ' "note": "대원 그림에 구워진 호스의 양 끝 자리 (2026-11-24). 그 사람 발밑 기준, 보는 방향 기준 [앞으로 m, 오른쪽으로 m, 높이 m]. '
         'front = 관창 쪽 끝, back = 펌프차 쪽 끝 (관창수는 back 만 = 관창 결합구). 게임이 바닥 호스를 back 까지 이어 그리고, '
         '꺾인 곳에서는 뒤 사람의 front 를 앞 사람의 back 에 맞춰 세운다 (scripts/ui/hose_draw.gd, floor_layer.gd _spray_layout). '
         '손으로 고치지 말고 장면을 고친 뒤 tools/blender/hose_ends.py 를 다시 돌린다.",',
         ' "source": "tools/blender/hose_ends.py 가 장면 파일(tools/blender/scenes/spray_*.blend — 사용자가 블렌더에서 확인한 방수 자세)에서 잰 값",',
         ' "ends": {']
names = sorted(ends)
for i, anim in enumerate(names):
    lines.append('  %s: %s%s' % (json.dumps(anim), json.dumps(ends[anim], ensure_ascii=False), "," if i < len(names) - 1 else ""))
lines += [" }", "}"]
with open(OUT, "w", encoding="utf-8", newline="\n") as f:
    f.write("\n".join(lines) + "\n")
print("[hose_ends] wrote", OUT, len(ends), flush=True)
