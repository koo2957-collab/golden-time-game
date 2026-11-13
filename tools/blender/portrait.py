# 무전 장면의 말하는 사람 그림 (2026-11-14, G3): 대원 3D 모델(firefighter_v2)의 상반신을 출동대 종류별 헬멧 색으로 찍는다.
# 실행: blender -b -P tools/blender/portrait.py -- <bake_config.json> <출력 폴더>
# 출력: <출력 폴더>/crew_<key>.png (320×320, 투명 배경). key와 헬멧 색은 아래 KINDS (data/art.json helmet_color와 같은 값)
import json
import math
import os
import sys

import bpy
import mathutils

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import firefighter_v2  # noqa: E402

# key: (헬멧 색, 설명) — 색은 data/art.json helmet_color (2026-11-11 사용자 결정: 진압 검정·구조 주황·구급 흰색·지휘 파랑)
KINDS = {"fire": "#3A3A3E", "rescue": "#FF7A1A", "ems": "#FFFFFF", "command": "#1F6FE5"}
SIZE = 320
SS = 2


def main():
    args = sys.argv[sys.argv.index("--") + 1:]
    config = json.load(open(args[0], encoding="utf-8"))
    out_dir = os.path.abspath(args[1])
    spec = next(c for c in config["characters"] if c.get("builder") == "firefighter_v2") if "characters" in config else None
    if spec is None:
        spec = next(c for group in config.values() if isinstance(group, list) for c in group if isinstance(c, dict) and c.get("builder") == "firefighter_v2")
    for key, helmet in KINDS.items():
        bpy.ops.wm.read_factory_settings(use_empty=True)
        sc = bpy.context.scene
        for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
            try:
                sc.render.engine = eng
                break
            except TypeError:
                continue
        sc.render.film_transparent = True
        sc.render.image_settings.file_format = "PNG"
        sc.render.image_settings.color_mode = "RGBA"
        sc.view_settings.view_transform = "Standard"
        sc.render.resolution_x = SIZE * SS
        sc.render.resolution_y = SIZE * SS
        world = bpy.data.worlds.new("w")
        sc.world = world
        world.use_nodes = True
        bg = world.node_tree.nodes.get("Background")
        bg.inputs[0].default_value = (0.6, 0.62, 0.66, 1.0)
        bg.inputs[1].default_value = 1.0
        # 주광(왼쪽 위 앞) + 보조광(오른쪽) — 얼굴 가리개에 빛이 걸리게
        for name, energy, rot in (("key", 3.4, (48, 0, -32)), ("fill", 1.1, (62, 0, 58))):
            light = bpy.data.lights.new(name, "SUN")
            light.energy = energy
            lo = bpy.data.objects.new(name, light)
            lo.rotation_euler = tuple(math.radians(a) for a in rot)
            sc.collection.objects.link(lo)
        rig = firefighter_v2.build(spec["colors"])
        rig.pose("idle", 0, 8)
        col = firefighter_v2._hex(helmet)
        for o in bpy.data.objects:
            if o.type == "MESH" and o.name in ("helmet", "brim"):
                for m in o.data.materials:
                    p = m.node_tree.nodes.get("Principled BSDF") if m and m.use_nodes else None
                    if p:
                        p.inputs["Base Color"].default_value = col
        cam = bpy.data.cameras.new("cam")
        cam.lens = 70.0
        co = bpy.data.objects.new("cam", cam)
        sc.collection.objects.link(co)
        sc.camera = co
        # 정면(-Y)에서 왼쪽으로 22° 돌아 살짝 위에서: 가슴~헬멧 꼭대기
        target = mathutils.Vector((0.0, 0.0, 1.56))
        ang = math.radians(22.0)
        dist = 2.05
        co.location = target + mathutils.Vector((math.sin(ang) * dist, -math.cos(ang) * dist, 0.16))
        co.rotation_euler = (target - co.location).to_track_quat("-Z", "Y").to_euler()
        os.makedirs(out_dir, exist_ok=True)
        path = os.path.join(out_dir, "crew_%s.png" % key)
        sc.render.filepath = path + ".tmp.png"
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(path + ".tmp.png")
        img.scale(SIZE, SIZE)
        img.filepath_raw = path
        img.file_format = "PNG"
        img.save()
        bpy.data.images.remove(img)
        os.remove(path + ".tmp.png")
        print("portrait", path)


main()
