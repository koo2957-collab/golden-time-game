# 확인받은 장면 파일들의 대원에게 새 상의 아랫단(반코트 한 장, 밑단이 허벅지를 따라 말려 올라감)을 입힌다 (2026-11-15).
# 실행: blender -b --factory-startup -P tools/blender/refit_coat_scenes.py -- <장면.blend> [<장면.blend> ...]
# 대원 = 'coat_upper' 조각을 가진 아마추어. 상의 천·반사띠 재질은 그 대원의 것을 그대로 쓴다.
import os
import sys

import bpy

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import firefighter_v2  # noqa: E402

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []

for path in ARGS:
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(path))
    sc = bpy.context.scene
    sc.frame_set(sc.frame_start)
    done = []
    for arm in [o for o in bpy.data.objects if o.type == "ARMATURE"]:
        kids = {o.name.split(".")[0]: o for o in bpy.data.objects if o.parent == arm}
        if "coat_upper" not in kids:
            continue
        mats = {"coat": kids["coat_upper"].active_material, "reflect": kids["band_chest"].active_material,
                "silver": kids["band_chest_s"].active_material}
        hidden = kids["coat_upper"].hide_render
        firefighter_v2.refit_coat(arm, mats)
        for o in [o for o in bpy.data.objects if o.parent == arm and o.name.split(".")[0] == "coat_skirt"]:
            o.hide_render = hidden
        done.append(arm.name)
    sc.frame_set(sc.frame_start)
    bpy.ops.wm.save_mainfile()
    print("[refit]", os.path.basename(path), done, flush=True)
