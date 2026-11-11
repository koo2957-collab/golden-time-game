# F04 연기 그림 (2026-11-12 사용자 결정): Blender 부피 연기를 구워 반복 재생 그림(플립북)으로 만든다.
# 실행: blender -b --factory-startup -P tools/blender/smoke_fx.py -- <작업 폴더> [quick]
#   작업 폴더: 렌더한 낱장이 들어갈 임시 폴더. 결과는 art/fx/smoke_curtain.png + art/fx/fx.json 의 "smoke_curtain"
#
# 연기층 앞면 커튼: 천장에 깔린 연기층을 정면에서 본 단면. 위(천장)는 짙고, 아랫면은 뭉게뭉게 말려 내려온다.
#   부피(4 x 0.5 x 1 단위) 안의 밀도 = 4D 노이즈. 시간에 따라 노이즈가 변하고 무늬가 아래로 흐른다.
#   정사영 카메라로 정면에서 찍고, 가로는 이음새 없이 이어지게(타일), 시간은 끝과 처음이 이어지게(루프) 섞는다.
#   그림 좌표: 위 = 천장, v = BODY_V 에 연기층 아랫면(중성대), 그 아래는 말려 내려오는 가장자리.
#   밝은 회색으로 굽고 게임에서 색을 곱한다 (검은 연기 / 회색 연기 하나로).

import bpy
import json
import math
import os
import sys

import numpy as np

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
WORK = os.path.abspath(ARGS[0]) if ARGS else os.path.join(os.path.dirname(__file__), "_smoke_work")
QUICK = len(ARGS) > 1 and ARGS[1] in ("quick", "one")
# one: 0번 장 하나만 렌더 (모양 고르기)
ONE = len(ARGS) > 1 and ARGS[1] == "one"
PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
OUT_PNG = os.path.join(PROJECT, "art", "fx", "smoke_curtain.png")
FX_JSON = os.path.join(PROJECT, "art", "fx", "fx.json")

LOOP = 24            # 반복 재생 장 수
TILE_PX = 320        # 가로 한 장(= TILE_M) 픽셀
HEIGHT_PX = 160      # 세로 (천장 ~ 가장자리 끝)
TILE_M = 2.0         # 가로 한 장이 게임에서 덮는 길이 (m)
BODY_Z = 0.25        # 부피 아래에서 이 높이가 연기층 아랫면 (그 아래는 가장자리)
FPS = 6.0            # 게임 재생 속도 (장/초)
W_STEP = 0.03        # 장마다 노이즈 변화
FLOW_STEP = 0.012    # 장마다 무늬가 아래로 흐르는 거리 (부피 단위)
SAMPLES = 16 if QUICK else 40


def log(*a):
    print("[smoke_fx]", *a, flush=True)


def reset_scene():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = SAMPLES
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = "OPENIMAGEDENOISE"
    sc.cycles.volume_step_rate = 0.5
    sc.cycles.max_bounces = 4
    sc.render.film_transparent = True
    sc.render.resolution_x = TILE_PX * 2
    sc.render.resolution_y = HEIGHT_PX
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    return sc


def make_volume():
    # 부피 상자: x 0~4 (가로 두 장), y -0.25~0.25, z 0~1
    mesh = bpy.data.meshes.new("smoke_box")
    xs, ys, zs = (0.0, 4.0), (-0.25, 0.25), (0.0, 1.0)
    verts = [(x, y, z) for x in xs for y in ys for z in zs]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new("smoke_box", mesh)
    bpy.context.scene.collection.objects.link(obj)

    mat = bpy.data.materials.new("smoke")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    n = nt.nodes
    l = nt.links
    out = n.new("ShaderNodeOutputMaterial")
    vol = n.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (0.92, 0.92, 0.94, 1.0)
    vol.inputs["Anisotropy"].default_value = 0.25
    l.new(vol.outputs["Volume"], out.inputs["Volume"])

    tc = n.new("ShaderNodeTexCoord")
    mp = n.new("ShaderNodeMapping")
    mp.name = "flow"
    l.new(tc.outputs["Object"], mp.inputs["Vector"])

    # 큰 뭉게 (아랫면 모양)
    big = n.new("ShaderNodeTexNoise")
    big.name = "big"
    big.noise_dimensions = "4D"
    big.inputs["Scale"].default_value = 2.2
    big.inputs["Detail"].default_value = 5.0
    big.inputs["Roughness"].default_value = 0.55
    big.inputs["Distortion"].default_value = 0.8
    l.new(mp.outputs["Vector"], big.inputs["Vector"])
    # 잔 무늬 (속 짙기)
    fine = n.new("ShaderNodeTexNoise")
    fine.name = "fine"
    fine.noise_dimensions = "4D"
    fine.inputs["Scale"].default_value = 3.0
    fine.inputs["Detail"].default_value = 6.0
    fine.inputs["Roughness"].default_value = 0.5
    l.new(mp.outputs["Vector"], fine.inputs["Vector"])

    sep = n.new("ShaderNodeSeparateXYZ")
    l.new(tc.outputs["Object"], sep.inputs["Vector"])

    # 아랫면 높이 = BODY_Z + (big - 0.5) × 0.6
    sub = n.new("ShaderNodeMath"); sub.operation = "SUBTRACT"; sub.inputs[1].default_value = 0.5
    l.new(big.outputs["Fac"], sub.inputs[0])
    mul = n.new("ShaderNodeMath"); mul.operation = "MULTIPLY"; mul.inputs[1].default_value = 1.3
    l.new(sub.outputs[0], mul.inputs[0])
    edge = n.new("ShaderNodeMath"); edge.operation = "ADD"; edge.inputs[1].default_value = BODY_Z
    l.new(mul.outputs[0], edge.inputs[0])
    lo = n.new("ShaderNodeMath"); lo.operation = "SUBTRACT"; lo.inputs[1].default_value = 0.07
    l.new(edge.outputs[0], lo.inputs[0])
    hi = n.new("ShaderNodeMath"); hi.operation = "ADD"; hi.inputs[1].default_value = 0.07
    l.new(edge.outputs[0], hi.inputs[0])
    mr = n.new("ShaderNodeMapRange")
    mr.interpolation_type = "SMOOTHSTEP"
    mr.clamp = True
    l.new(sep.outputs["Z"], mr.inputs["Value"])
    l.new(lo.outputs[0], mr.inputs["From Min"])
    l.new(hi.outputs[0], mr.inputs["From Max"])

    # 속 짙기 0.5 ~ 1.4 배
    fm = n.new("ShaderNodeMapRange")
    fm.inputs["From Min"].default_value = 0.3
    fm.inputs["From Max"].default_value = 0.7
    fm.inputs["To Min"].default_value = 0.1
    fm.inputs["To Max"].default_value = 1.6
    l.new(fine.outputs["Fac"], fm.inputs["Value"])

    d1 = n.new("ShaderNodeMath"); d1.operation = "MULTIPLY"
    l.new(mr.outputs["Result"], d1.inputs[0])
    l.new(fm.outputs["Result"], d1.inputs[1])
    d2 = n.new("ShaderNodeMath"); d2.operation = "MULTIPLY"; d2.inputs[1].default_value = 5.0
    l.new(d1.outputs[0], d2.inputs[0])
    l.new(d2.outputs[0], vol.inputs["Density"])

    obj.data.materials.append(mat)
    return nt


def make_light_camera():
    sc = bpy.context.scene
    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (0.55, 0.57, 0.6, 1.0)
    bg.inputs["Strength"].default_value = 0.35
    sc.world = world

    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 6.0
    so = bpy.data.objects.new("sun", sun)
    # 위·앞에서 비춘다 (윗면 밝고 아랫면 어둡게)
    so.rotation_euler = (math.radians(25), math.radians(-30), 0.0)
    sc.collection.objects.link(so)

    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = 4.0
    co = bpy.data.objects.new("cam", cam)
    co.location = (2.0, -10.0, 0.5)
    co.rotation_euler = (math.radians(90), 0.0, 0.0)
    sc.collection.objects.link(co)
    sc.camera = co


def render_frames(nt):
    os.makedirs(WORK, exist_ok=True)
    sc = bpy.context.scene
    paths = []
    for k in range(1 if ONE else LOOP * 2):
        nt.nodes["big"].inputs["W"].default_value = k * W_STEP
        nt.nodes["fine"].inputs["W"].default_value = k * W_STEP * 1.3 + 7.0
        nt.nodes["flow"].inputs["Location"].default_value = (0.0, 0.0, k * FLOW_STEP)
        p = os.path.join(WORK, "curtain_%02d.png" % k)
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        log("render", k + 1, "/", LOOP * 2)
        paths.append(p)
    return paths


def load_rgba(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return np.flipud(a)  # 위가 0번 줄


def premul(a):
    b = a.copy()
    b[..., :3] *= b[..., 3:4]
    return b


def unpremul(a):
    b = a.copy()
    al = np.maximum(b[..., 3:4], 1e-5)
    b[..., :3] = np.where(b[..., 3:4] > 1e-5, b[..., :3] / al, 0.0)
    return b


def tile_x(f):
    # 가로 두 장 너비 → 한 장: out(x) = F(x+W)(1 - x/W) + F(x)(x/W) → 끝과 처음이 이어진다
    w = TILE_PX
    t = (np.arange(w, dtype=np.float32) / w)[None, :, None]
    return f[:, w:2 * w] * (1.0 - t) + f[:, 0:w] * t


def assemble(paths):
    frames = [tile_x(premul(load_rgba(p))) for p in paths]
    out = []
    for k in range(LOOP):
        s = k / LOOP
        # 시간 루프: G(k) = F(k+L)(1 - k/L) + F(k)(k/L)
        out.append(unpremul(frames[k + LOOP] * (1.0 - s) + frames[k] * s))
    atlas = np.concatenate(out, axis=0)  # 장을 세로로 쌓는다 (위가 0번)
    h, w = atlas.shape[:2]
    img = bpy.data.images.new("smoke_curtain", w, h, alpha=True)
    img.pixels = np.flipud(atlas).clip(0.0, 1.0).ravel().tolist()
    img.filepath_raw = OUT_PNG
    img.file_format = "PNG"
    img.save()
    log("saved", OUT_PNG, w, "x", h)

    meta = json.load(open(FX_JSON, encoding="utf-8")) if os.path.exists(FX_JSON) else {}
    meta["smoke_curtain"] = {
        "w": TILE_PX, "h": HEIGHT_PX, "frames": LOOP, "fps": FPS,
        "tile_m": TILE_M, "body_v": 1.0 - BODY_Z,
        "source": "tools/blender/smoke_fx.py — Blender Cycles 부피 노이즈(정면 정사영), 가로 타일·시간 루프",
    }
    json.dump(meta, open(FX_JSON, "w", encoding="utf-8"), ensure_ascii=False, indent=2, sort_keys=True)


def main():
    reset_scene()
    nt = make_volume()
    make_light_camera()
    paths = render_frames(nt)
    if not ONE:
        assemble(paths)


main()
