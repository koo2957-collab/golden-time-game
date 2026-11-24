# 불꽃 그림 — 만타플로 불 시뮬레이션으로 굽기 (2026-11-24 사용자 결정 "가장 실감 나는 화재 표시").
# 참고: Vefects 'Free Fire VFX' 미리보기 그림의 모양만 본다 (에셋 파일은 쓰지 않는다 — 공개 저장소 재배포 금지 조건).
#   흰빛이 도는 노란 심 · 진한 주황 몸통 · 빨간 끝 · 찢어져 말려 오르는 불길.
# 예전 fire_fx.py(빛을 내는 부피 노이즈)는 부드러운 덩어리로 보였다. 여기서는 블렌더 만타플로가 연료가 타며 오르는
# 불길(flame)을 실제로 계산하고, 그 값을 색 띠로 칠해 빛만 렌더한다. 카메라·크기·저장 방식은 fire_fx.py 와 같다
# (정면 정사영, 그림 아래 가운데 = 불 뿌리, 검은 바탕의 빛 → 밝기를 불투명도로, 16장 시간 루프).
#
# 실행: blender -b --factory-startup -P tools/blender/fire_sim_fx.py -- <작업 폴더> <종류> [sample|full]
#   종류: s | m | l | xl (쉼표로 여럿)
#   sample: 게임 그림을 바꾸지 않고 <작업 폴더>/fire_sim_<종류>_compare.png (지금 그림 / 새 그림 8장씩 비교)만 만든다
#   full: art/fx/fire_<종류>.png 와 art/fx/fx.json 을 새 그림으로 바꾼다 (사용자 확인 뒤)

import bpy
import json
import math
import os
import shutil
import sys

import numpy as np

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
WORK = os.path.abspath(ARGS[0]) if ARGS else os.path.join(os.path.dirname(__file__), "_fire_sim_work")
KIND = ARGS[1] if len(ARGS) > 1 else "m"
MODE = ARGS[2] if len(ARGS) > 2 else "sample"
SAMPLE = MODE != "full"
PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FX_JSON = os.path.join(PROJECT, "art", "fx", "fx.json")
SOURCE = "tools/blender/fire_sim_fx.py — Blender 만타플로 불 시뮬레이션(flame) + Cycles 빛 렌더(정면 정사영), 시간 루프"

LOOP = 16            # 반복 재생 장 수
WARM = 48            # 불이 다 자랄 때까지 버리는 시뮬레이션 장 수
SUPER = 2            # 렌더를 이 배로 크게 한 뒤 줄인다 (가장자리를 매끄럽게)

# 종류별 설정. px·w·h·fps 는 fire_fx.py 와 같다 (게임이 같은 크기로 그린다). r = 불 뿌리 반지름 (x, y),
# res = 시뮬레이션 격자 (긴 변 칸 수, sample 은 빨리), fuel = 연료 양, up = 뿜어 오르는 처음 속도(m/s)
KINDS = {
    "s": {"px": (64, 96), "w": 0.7, "h": 1.05, "r": (0.16, 0.14), "fps": 14.0, "res": (48, 72), "fuel": 1.6, "up": 1.1},
    "m": {"px": (112, 144), "w": 1.3, "h": 1.67, "r": (0.36, 0.26), "fps": 12.0, "res": (56, 88), "fuel": 1.6, "up": 1.4},
    "l": {"px": (160, 208), "w": 2.0, "h": 2.6, "r": (0.6, 0.4), "fps": 10.0, "res": (64, 104), "fuel": 1.6, "up": 1.7},
    "xl": {"px": (240, 208), "w": 3.2, "h": 2.77, "r": (1.2, 0.55), "fps": 9.0, "res": (72, 120), "fuel": 1.5, "up": 1.7},
}
TOP_RATIO = 0.93
# 불길 값(flame 0~1)에 곱하는 빛 세기 — 1을 넘는 곳이 노랗게, 크게 넘으면 하얗게
STRENGTH = 2.4
# 색 띠: flame 값 → 색 (참고 그림: 끝 빨강 → 주황 몸통 → 노랑 → 흰빛 노란 심). 주황·빨강 구간을 넓게
RAMP = [
    (0.00, (0.00, 0.00, 0.00)),
    (0.08, (0.30, 0.02, 0.00)),
    (0.25, (0.80, 0.10, 0.01)),
    (0.50, (1.00, 0.32, 0.02)),
    (0.72, (1.00, 0.58, 0.10)),
    (0.90, (1.00, 0.85, 0.40)),
    (1.00, (1.00, 0.96, 0.78)),
]
# 연료 원판을 그림 아래 가장자리보다 이만큼 아래에 둔다 (m) — 원판 자체가 빛나는 띠가 그림에 들지 않게
SOURCE_BELOW_M = 0.08


def log(*a):
    print("[fire_sim]", *a, flush=True)


def reset_scene(cfg):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    try:
        sc.render.engine = "CYCLES"
    except TypeError as e:
        log("엔진 오류", e)
        raise
    sc.cycles.device = "CPU"
    sc.cycles.samples = 16 if SAMPLE else 32
    sc.cycles.use_denoising = True
    sc.cycles.volume_step_rate = 0.5
    sc.cycles.max_bounces = 1
    sc.render.film_transparent = False
    sc.render.resolution_x = cfg["px"][0] * SUPER
    sc.render.resolution_y = cfg["px"][1] * SUPER
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("w")
    world.use_nodes = True
    sc.world = world
    bg = next(n for n in world.node_tree.nodes if n.type == "BACKGROUND")
    bg.inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    sc.frame_start = 1
    sc.frame_end = WARM + LOOP * 2
    return sc


def make_domain(cfg):
    # 불이 옆·위로 넘치지 않게 그림 칸보다 조금 크게. 바닥 = z 0
    wx, wy, hz = cfg["w"] * 1.25, cfg["w"] * 0.9, cfg["h"] * 1.2
    # 바닥은 연료 원판 아래까지 (그림 아래 가장자리 = z 0 보다 낮게)
    floor = -SOURCE_BELOW_M - 0.06
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0.0, 0.0, floor + hz * 0.5))
    dom = bpy.context.active_object
    dom.name = "domain"
    dom.scale = (wx, wy, hz)
    bpy.ops.object.transform_apply(scale=True)
    mod = dom.modifiers.new("fluid", "FLUID")
    mod.fluid_type = "DOMAIN"
    d = mod.domain_settings
    d.domain_type = "GAS"
    d.resolution_max = cfg["res"][0] if SAMPLE else cfg["res"][1]
    d.cache_directory = os.path.join(WORK, "cache_%s" % KIND)
    d.cache_type = "ALL"
    d.cache_frame_start = 1
    d.cache_frame_end = WARM + LOOP * 2
    d.use_adaptive_domain = False
    # 위·옆은 열어 둔다 (연기·불이 벽에 갇혀 고이지 않게)
    for side in ("front", "back", "right", "left", "top"):
        setattr(d, "use_collision_border_" + side, False)
    d.use_collision_border_bottom = True
    d.vorticity = 0.25            # 말려 오르는 소용돌이
    d.flame_vorticity = 0.6       # 불길 가장자리를 찢는 소용돌이 (클수록 혀가 갈라진다)
    d.burning_rate = 0.45         # 연료가 타는 빠르기 (작을수록 불길이 길다 — 0.85 는 그림 높이의 1/3 에서 꺼졌다)
    d.flame_smoke = 0.25          # 탈 때 생기는 연기 (빛만 렌더하므로 보이지 않는다)
    d.flame_max_temp = 3.0
    d.flame_ignition = 1.5
    d.alpha = 0.3                 # 연기 부력
    d.beta = 2.5                  # 열 부력
    d.use_dissolve_smoke = True
    d.dissolve_speed = 12
    # 잡음 키우기(격자 2배의 잔무늬) — 굵은 격자의 세로 줄무늬를 없앤다
    d.use_noise = True
    d.noise_scale = 2
    d.noise_strength = 1.0
    return dom


def make_flow(cfg):
    # 불 뿌리: 납작한 타원 원판 (그림 아래 가운데)
    bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=1.0, depth=0.04, location=(0.0, 0.0, -SOURCE_BELOW_M))
    src = bpy.context.active_object
    src.name = "fuel"
    src.scale = (cfg["r"][0], cfg["r"][1], 1.0)
    bpy.ops.object.transform_apply(scale=True)
    mod = src.modifiers.new("fluid", "FLUID")
    mod.fluid_type = "FLOW"
    f = mod.flow_settings
    f.flow_type = "FIRE"
    f.flow_behavior = "INFLOW"
    f.flow_source = "MESH"
    f.fuel_amount = cfg["fuel"]
    f.surface_distance = 1.2
    f.subframes = 2
    f.use_initial_velocity = True
    f.velocity_coord = (0.0, 0.0, cfg["up"])
    # 연료가 고르게 나오면 기둥처럼 보인다: 구름 무늬로 연료 양을 흔든다 (무늬를 위로 흘려 깜박이게)
    tex = bpy.data.textures.new("fuel_noise", "CLOUDS")
    tex.noise_scale = 0.35
    f.use_texture = True
    f.noise_texture = tex
    f.texture_map_type = "AUTO"
    f.texture_size = 1.0
    f.texture_offset = 0.0
    f.keyframe_insert("texture_offset", frame=1)
    f.texture_offset = 6.0
    f.keyframe_insert("texture_offset", frame=WARM + LOOP * 2)
    src.hide_render = True
    return src


def make_material(dom):
    mat = bpy.data.materials.new("flame")
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        nt.nodes.remove(n)
    out = nt.nodes.new("ShaderNodeOutputMaterial")
    attr = nt.nodes.new("ShaderNodeAttribute")
    attr.attribute_name = "flame"
    ramp = nt.nodes.new("ShaderNodeValToRGB")
    els = ramp.color_ramp.elements
    els[0].position, els[0].color = RAMP[0][0], (*RAMP[0][1], 1.0)
    els[1].position, els[1].color = RAMP[-1][0], (*RAMP[-1][1], 1.0)
    for pos, col in RAMP[1:-1]:
        e = els.new(pos)
        e.color = (*col, 1.0)
    mul = nt.nodes.new("ShaderNodeMath")
    mul.operation = "MULTIPLY"
    mul.inputs[1].default_value = STRENGTH
    em = nt.nodes.new("ShaderNodeEmission")
    nt.links.new(attr.outputs["Fac"], ramp.inputs["Fac"])
    nt.links.new(attr.outputs["Fac"], mul.inputs[0])
    nt.links.new(ramp.outputs["Color"], em.inputs["Color"])
    nt.links.new(mul.outputs[0], em.inputs["Strength"])
    nt.links.new(em.outputs["Emission"], out.inputs["Volume"])
    dom.data.materials.append(mat)


def make_camera(cfg):
    sc = bpy.context.scene
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    aspect = cfg["px"][0] / cfg["px"][1]
    cam.ortho_scale = cfg["w"] if aspect >= 1.0 else cfg["h"]
    co = bpy.data.objects.new("cam", cam)
    co.location = (0.0, -10.0, cfg["h"] * 0.5)
    co.rotation_euler = (math.radians(90), 0.0, 0.0)
    sc.collection.objects.link(co)
    sc.camera = co


def bake_sim(dom):
    cache = dom.modifiers["fluid"].domain_settings.cache_directory
    if os.path.isdir(cache):
        shutil.rmtree(cache)
    log("시뮬레이션 계산 시작", KIND)
    with bpy.context.temp_override(object=dom, active_object=dom, selected_objects=[dom]):
        bpy.ops.fluid.bake_all()
    log("시뮬레이션 계산 끝")


def render_frames():
    sc = bpy.context.scene
    paths = []
    for k in range(LOOP * 2):
        sc.frame_set(WARM + 1 + k)
        p = os.path.join(WORK, "f_%s_%02d.png" % (KIND, k))
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        paths.append(p)
        log("렌더", k + 1, "/", LOOP * 2)
    return paths


def load_rgb(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return np.flipud(a)[..., :3]


def shrink(a, k):
    if k <= 1:
        return a
    h, w = a.shape[0] // k, a.shape[1] // k
    return a[:h * k, :w * k].reshape(h, k, w, k, -1).mean(axis=(1, 3))


def to_rgba(rgb):
    peak = rgb.max(axis=2, keepdims=True)
    alpha = np.clip(peak * 1.3, 0.0, 1.0) ** 0.9
    col = np.where(peak > 1e-4, rgb / np.maximum(peak, 1e-4), 0.0)
    return np.concatenate([np.clip(col, 0.0, 1.0), alpha], axis=2)


def save_png(arr, png):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(os.path.basename(png), w, h, alpha=arr.shape[2] == 4)
    rgba = arr if arr.shape[2] == 4 else np.concatenate([arr, np.ones((h, w, 1), np.float32)], axis=2)
    img.pixels = np.flipud(rgba).clip(0.0, 1.0).ravel().tolist()
    img.filepath_raw = png
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    log("저장", png, w, "x", h)


def loop_frames(paths):
    frames = [shrink(load_rgb(p), SUPER) for p in paths]
    out = []
    for k in range(LOOP):
        s = k / LOOP
        # 시간 루프: G(k) = F(k+L)(1 - k/L) + F(k)(k/L)
        out.append(to_rgba(frames[k + LOOP] * (1.0 - s) + frames[k] * s))
    return out


def over(rgba, bg):
    a = rgba[..., 3:4]
    return rgba[..., :3] * a + bg * (1.0 - a)


def compare(new_frames, cfg):
    # 위 줄 = 지금 그림(art/fx/fire_<종류>.png), 아래 줄 = 새 그림. 8장씩, 어두운 회색 바탕(게임 바닥과 비슷하게)
    bg = np.array([0.16, 0.17, 0.19], np.float32)
    rows = []
    old_path = os.path.join(PROJECT, "art", "fx", "fire_%s.png" % KIND)
    fh = new_frames[0].shape[0]
    if os.path.exists(old_path):
        img = bpy.data.images.load(old_path)
        w, h = img.size
        a = np.flipud(np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4))
        bpy.data.images.remove(img)
        fh_old = h // LOOP
        old = [a[i * fh_old:(i + 1) * fh_old] for i in range(LOOP)]
        if fh_old == fh and old[0].shape[1] == new_frames[0].shape[1]:
            rows.append(np.concatenate([over(old[i], bg) for i in range(0, LOOP, 2)], axis=1))
    rows.append(np.concatenate([over(new_frames[i], bg) for i in range(0, LOOP, 2)], axis=1))
    sheet = np.concatenate(rows, axis=0)
    # 보기 좋게 3배로 키운다 (가까운 이웃)
    sheet = sheet.repeat(3, axis=0).repeat(3, axis=1)
    save_png(sheet, os.path.join(WORK, "fire_sim_%s_compare.png" % KIND))


def write_atlas(new_frames, cfg):
    atlas = np.concatenate(new_frames, axis=0)
    h, w = atlas.shape[:2]
    save_png(atlas, os.path.join(PROJECT, "art", "fx", "fire_%s.png" % KIND))
    meta = json.load(open(FX_JSON, encoding="utf-8")) if os.path.exists(FX_JSON) else {}
    meta["fire_" + KIND] = {"w": w, "h": h // LOOP, "frames": LOOP, "fps": cfg["fps"], "width_m": cfg["w"], "height_m": cfg["h"],
                            "flame_top_v": round(1.0 - TOP_RATIO, 3), "source": SOURCE}
    json.dump(meta, open(FX_JSON, "w", encoding="utf-8"), ensure_ascii=False, indent=2, sort_keys=True)


def bake(kind):
    global KIND
    KIND = kind
    cfg = KINDS[kind]
    os.makedirs(WORK, exist_ok=True)
    reset_scene(cfg)
    dom = make_domain(cfg)
    make_flow(cfg)
    make_material(dom)
    make_camera(cfg)
    bake_sim(dom)
    frames = loop_frames(render_frames())
    if SAMPLE:
        compare(frames, cfg)
    else:
        write_atlas(frames, cfg)


def main():
    for k in KIND.split(","):
        bake(k)


main()
