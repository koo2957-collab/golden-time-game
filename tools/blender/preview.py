# 장면 미리보기: 게임과 같은 각도(비스듬히 위)와 옆에서 본 모습으로 몇 장을 뽑아 한 장으로 붙인다 (장면 파일은 저장하지 않는다)
# 실행: blender -b --factory-startup <장면.blend> -P preview.py -- <결과.png> [장 번호들 "1,9,17,25"] [가운데 "x,y,z"] [폭 m]
import bpy, sys, math, os, mathutils

args = sys.argv[sys.argv.index("--") + 1:]
out = args[0]
frames = [int(x) for x in (args[1] if len(args) > 1 else "1,9,17,25").split(",")]
center = mathutils.Vector([float(x) for x in (args[2] if len(args) > 2 else "0,0,0.9").split(",")])
span = float(args[3]) if len(args) > 3 else 4.0
sc = bpy.context.scene
for eng in ("BLENDER_EEVEE", "BLENDER_EEVEE_NEXT"):
    try:
        sc.render.engine = eng
        break
    except TypeError:
        continue
sc.render.film_transparent = False
sc.render.image_settings.file_format = "PNG"
sc.view_settings.view_transform = "Standard"
if sc.world is None:
    sc.world = bpy.data.worlds.new("w")
sc.world.use_nodes = True
bg = sc.world.node_tree.nodes.get("Background")
if bg:
    bg.inputs[0].default_value = (0.55, 0.57, 0.6, 1.0)
    bg.inputs[1].default_value = 0.9
if not any(o.type == "LIGHT" for o in bpy.data.objects):
    sun = bpy.data.objects.new("pv_sun", bpy.data.lights.new("pv_sun", "SUN"))
    sun.data.energy = 3.2
    sun.rotation_euler = (math.radians(40), 0, math.radians(-20))
    sc.collection.objects.link(sun)
W = 420
sc.render.resolution_x = W
sc.render.resolution_y = W
sc.render.resolution_percentage = 100
cam = bpy.data.objects.new("pv_cam", bpy.data.cameras.new("pv_cam"))
cam.data.type = "ORTHO"
cam.data.ortho_scale = span
cam.data.clip_end = 300.0
sc.collection.objects.link(cam)
sc.camera = cam
# 보는 쪽: (이름, 방위각 도 — 모델 앞(-Y)을 0으로 시계 반대, 내려다보는 각 도)
views = [("game", 45.0, 35.0), ("side", 90.0, 8.0), ("front", 0.0, 8.0)]
tiles = []
tmp = out + ".tile.png"
for vname, az, elev in views:
    a = math.radians(az)
    e = math.radians(elev)
    # 카메라 자리: 모델 앞쪽(-Y)에서 az만큼 돌아간 곳
    direction = mathutils.Vector((math.sin(a) * math.cos(e), -math.cos(a) * math.cos(e), math.sin(e)))
    cam.location = center + direction * 60.0
    cam.rotation_euler = (center - cam.location).to_track_quat("-Z", "Y").to_euler()
    for f in frames:
        sc.frame_set(f)
        sc.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        img = bpy.data.images.load(tmp)
        px = list(img.pixels)
        tiles.append(px)
        bpy.data.images.remove(img)
cols = len(frames)
rows = len(views)
sheet = bpy.data.images.new("sheet", W * cols, W * rows, alpha=True)
buf = [0.0] * (W * cols * W * rows * 4)
for r in range(rows):
    for c in range(cols):
        px = tiles[r * cols + c]
        for y in range(W):
            src = y * W * 4
            dst = (((rows - 1 - r) * W + y) * W * cols + c * W) * 4
            buf[dst:dst + W * 4] = px[src:src + W * 4]
sheet.pixels = buf
sheet.filepath_raw = out
sheet.file_format = "PNG"
sheet.save()
if os.path.exists(tmp):
    os.remove(tmp)
print("PREVIEW_SAVED", out)
