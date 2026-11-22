# 불꽃 그림 (2026-11-22 사용자 결정 — 참고 그림 '화재성장속도, 4단계'·'롤오버, 플레쉬오버, 백드레프트'):
# Blender 부피(빛을 내는 가스)를 구워 반복 재생 그림(플립북)으로 만든다. 연기 그림(smoke_fx.py)과 같은 방식.
# 실행: blender -b --factory-startup -P tools/blender/fire_fx.py -- <작업 폴더> <종류> [one|quick]
#   종류: s | m | l | xl | all   (쉼표로 여럿)
#   one: 장 하나만 렌더해 <작업 폴더>/fire_<종류>_one.png 로 (모양 고르기, 결과 그림은 안 바꾼다). quick: 표본 수를 줄여 빨리
#   결과: art/fx/fire_<종류>.png (장을 세로로 쌓음) + art/fx/fx.json 의 "fire_<종류>"
#
# 네 크기 (참고 그림의 Slow → Ultrafast 처럼 크기만 봐도 불의 세기가 읽히게):
#   s   작은 불: 불꽃 한 줄기 (폭 0.7m × 높이 1.0m)
#   m   중간 불: 혀 몇 갈래가 모인 불 (1.3m × 1.6m)
#   l   큰 불: 굵은 불기둥 (2.0m × 2.4m — 천장 높이)
#   xl  불바다: 넓게 깔려 천장까지 넘실대는 불 (3.2m × 2.6m)
# 게임은 불의 열방출률로 화염 높이를 셈해(Heskestad 식) 맞는 크기의 그림을 골라 늘여 그린다 (scripts/ui/fire_draw.gd).
# 그림 아래 가운데 = 불 뿌리. 검은 바탕에 빛만 렌더한 뒤, 밝기를 불투명도로 바꿔 투명 배경 그림으로 만든다.

import bpy
import json
import math
import os
import sys

import numpy as np

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
WORK = os.path.abspath(ARGS[0]) if ARGS else os.path.join(os.path.dirname(__file__), "_fire_work")
KIND = ARGS[1] if len(ARGS) > 1 else "m"
MODE = ARGS[2] if len(ARGS) > 2 else ""
ONE = MODE == "one"
QUICK = MODE in ("quick", "one")
PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FX_JSON = os.path.join(PROJECT, "art", "fx", "fx.json")

LOOP = 16            # 반복 재생 장 수
SOURCE = "tools/blender/fire_fx.py — Blender Cycles 빛을 내는 부피 노이즈(정면 정사영), 시간 루프"

# 종류별 설정. px = 렌더 크기, w·h = 그림이 나타내는 폭·높이(m), r = 불 뿌리 반지름 (x, y),
# tongues = 불꽃 혀 무늬의 가로 배율(클수록 잘게 갈라진다), rise = 한 장에 무늬가 올라가는 높이(m), fps = 재생 속도
KINDS = {
    "s": {"px": (64, 96), "w": 0.7, "h": 1.05, "r": (0.2, 0.18), "tongues": 3.6, "rise": 0.055, "w_step": 0.05,
          "fps": 14.0, "gain": 1.0, "samples": 24},
    "m": {"px": (112, 144), "w": 1.3, "h": 1.67, "r": (0.42, 0.3), "tongues": 2.8, "rise": 0.075, "w_step": 0.045,
          "fps": 12.0, "gain": 1.0, "samples": 24},
    "l": {"px": (160, 208), "w": 2.0, "h": 2.6, "r": (0.7, 0.45), "tongues": 2.2, "rise": 0.1, "w_step": 0.04,
          "fps": 10.0, "gain": 1.0, "samples": 24},
    "xl": {"px": (240, 208), "w": 3.2, "h": 2.77, "r": (1.35, 0.6), "tongues": 1.9, "rise": 0.11, "w_step": 0.04,
           "fps": 9.0, "gain": 1.0, "samples": 24},
}
# 불꽃 꼭대기는 그림 높이의 이 비율까지 (그 위는 혀가 날름거릴 여유)
TOP_RATIO = 0.93
# 불꽃 한가운데에 쌓이는 빛의 세기 (1을 넘는 곳이 노랗게, 크게 넘으면 하얗게 날아간다)
STRENGTH = 2.6


def log(*a):
    print("[fire_fx]", *a, flush=True)


def reset_scene(cfg):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 12 if QUICK else cfg["samples"]
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = "OPENIMAGEDENOISE"
    sc.cycles.volume_step_rate = 0.5
    sc.cycles.max_bounces = 1
    sc.render.film_transparent = False
    sc.render.resolution_x = cfg["px"][0]
    sc.render.resolution_y = cfg["px"][1]
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGB"
    sc.view_settings.view_transform = "Standard"
    world = bpy.data.worlds.new("world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.0, 0.0, 0.0, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.0
    sc.world = world
    return sc


class G:
    def __init__(self, nt):
        self.nt = nt
        self.n = nt.nodes
        self.l = nt.links

    def link(self, a, b):
        self.l.new(a, b)

    def math(self, op, a, b=None):
        m = self.n.new("ShaderNodeMath")
        m.operation = op
        for i, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                m.inputs[i].default_value = float(v)
            else:
                self.link(v, m.inputs[i])
        return m.outputs[0]

    def add(self, a, b):
        return self.math("ADD", a, b)

    def sub(self, a, b):
        return self.math("SUBTRACT", a, b)

    def mul(self, a, b):
        return self.math("MULTIPLY", a, b)

    def div(self, a, b):
        return self.math("DIVIDE", a, b)

    def noise(self, name, vec, scale, detail, rough, dist=0.0):
        t = self.n.new("ShaderNodeTexNoise")
        t.name = name
        t.noise_dimensions = "4D"
        t.inputs["Scale"].default_value = scale
        t.inputs["Detail"].default_value = detail
        t.inputs["Roughness"].default_value = rough
        t.inputs["Distortion"].default_value = dist
        self.link(vec, t.inputs["Vector"])
        return t.outputs["Fac"]

    def smooth(self, v, lo, hi, inv=False):
        mr = self.n.new("ShaderNodeMapRange")
        mr.interpolation_type = "SMOOTHSTEP"
        mr.clamp = True
        self.link(v, mr.inputs["Value"])
        for key, x in (("From Min", lo), ("From Max", hi)):
            if isinstance(x, (int, float)):
                mr.inputs[key].default_value = float(x)
            else:
                self.link(x, mr.inputs[key])
        return self.sub(1.0, mr.outputs["Result"]) if inv else mr.outputs["Result"]

    def remap(self, v, a, b, c, d):
        mr = self.n.new("ShaderNodeMapRange")
        mr.clamp = True
        self.link(v, mr.inputs["Value"])
        mr.inputs["From Min"].default_value = a
        mr.inputs["From Max"].default_value = b
        mr.inputs["To Min"].default_value = c
        mr.inputs["To Max"].default_value = d
        return mr.outputs["Result"]


def make_box(cfg):
    mesh = bpy.data.meshes.new("fire_box")
    hw = cfg["w"] * 0.5
    hy = max(cfg["r"][1] * 1.8, 0.3)
    xs, ys, zs = (-hw, hw), (-hy, hy), (0.0, cfg["h"])
    verts = [(x, y, z) for x in xs for y in ys for z in zs]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new("fire_box", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def make_material(obj, cfg):
    """불꽃의 세기 I(x, y, z): 뿌리는 넓고 위로 갈수록 좁아지는 몸통 × 날름거리는 혀 × 잔 무늬.
    무늬는 위로 흐른다 (flow). 세기를 색(검붉음 → 주황 → 노랑 → 흰 노랑)과 밝기로 바꿔 빛을 낸다."""
    mat = bpy.data.materials.new("fire")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    g = G(nt)
    out = g.n.new("ShaderNodeOutputMaterial")
    em = g.n.new("ShaderNodeEmission")
    g.link(em.outputs["Emission"], out.inputs["Volume"])

    tc = g.n.new("ShaderNodeTexCoord")
    mp = g.n.new("ShaderNodeMapping")
    mp.name = "flow"
    g.link(tc.outputs["Object"], mp.inputs["Vector"])
    sep = g.n.new("ShaderNodeSeparateXYZ")
    g.link(tc.outputs["Object"], sep.inputs["Vector"])
    x, y, z = sep.outputs["X"], sep.outputs["Y"], sep.outputs["Z"]
    flow = mp.outputs["Vector"]

    top = cfg["h"] * TOP_RATIO
    rx, ry = cfg["r"]
    zn = g.div(z, top)                                   # 0 뿌리 … 1 꼭대기
    # 큰 무늬: 혀의 갈래 (가로로 잘게, 세로로 길게 늘인 노이즈가 위로 흐른다)
    stretch = g.n.new("ShaderNodeMapping")
    stretch.inputs["Scale"].default_value = (cfg["tongues"], cfg["tongues"], cfg["tongues"] * 0.38)
    g.link(flow, stretch.inputs["Vector"])
    big = g.noise("big", stretch.outputs["Vector"], 1.0, 2.5, 0.55, 0.6)
    streak = g.n.new("ShaderNodeMapping")
    streak.inputs["Scale"].default_value = (1.0, 1.0, 0.45)
    g.link(flow, streak.inputs["Vector"])
    fine = g.noise("fine", streak.outputs["Vector"], 5.0 / max(cfg["w"], 0.5) + 2.5, 4.0, 0.55, 0.3)
    bign = g.remap(big, 0.3, 0.7, -1.0, 1.0)
    # 기둥 무늬: 가로로는 잘고 세로로는 거의 변하지 않는다 → 자리마다 혀의 높이가 달라 꼭대기가 뾰족뾰족하다
    column = g.n.new("ShaderNodeMapping")
    column.inputs["Scale"].default_value = (cfg["tongues"] * 1.7, cfg["tongues"] * 1.7, cfg["tongues"] * 0.1)
    g.link(flow, column.inputs["Vector"])
    coln = g.remap(g.noise("col", column.outputs["Vector"], 1.0, 1.5, 0.5, 0.0), 0.32, 0.68, -1.0, 1.0)
    # 몸통: 타원 단면, 위로 갈수록 좁아진다. 좌우로 흔들리는 정도는 위쪽이 크다
    sway = g.mul(g.mul(bign, 0.35), g.math("POWER", zn, 1.3))
    xs = g.div(g.add(x, g.mul(sway, rx)), rx)
    ys = g.div(y, ry)
    r = g.math("SQRT", g.add(g.mul(xs, xs), g.mul(ys, ys)))
    taper = g.add(g.mul(g.math("POWER", g.sub(1.0, g.math("MINIMUM", zn, 1.0)), 0.6), 0.72), 0.28)
    d = g.div(r, taper)
    dn = g.add(d, g.mul(bign, g.add(0.2, g.mul(zn, 0.55))))
    body = g.smooth(dn, 0.3, 1.0, inv=True)
    # 그림 옆 가장자리에서는 사라진다 (무늬가 상자 밖으로 잘리지 않게)
    body = g.mul(body, g.smooth(g.math("ABSOLUTE", x), cfg["w"] * 0.34, cfg["w"] * 0.46, inv=True))
    # 혀: 자리마다 불꽃 높이가 다르다 (기둥 무늬가 낮은 곳은 일찍 끊긴다)
    reach = g.add(0.7, g.mul(coln, 0.36))
    tip = g.smooth(zn, g.mul(reach, 0.3), reach, inv=True)
    foot = g.smooth(z, 0.0, 0.04 * cfg["h"])
    # 잔 무늬: 어두운 틈이 생겨 갈래가 보인다 (위로 갈수록 틈이 많다)
    lick = g.smooth(fine, g.add(0.3, g.mul(zn, 0.16)), 0.66)
    inten = g.mul(g.mul(g.mul(body, tip), foot), g.add(g.mul(lick, 1.25), 0.12))
    # 뿌리 가까이는 더 뜨겁다 (밝은 속불)
    core = g.add(0.75, g.mul(g.smooth(zn, 0.0, 0.5, inv=True), 0.5))
    inten = g.mul(inten, core)

    ramp = g.n.new("ShaderNodeValToRGB")
    ramp.color_ramp.interpolation = "LINEAR"
    els = ramp.color_ramp.elements
    els[0].position = 0.0
    els[0].color = (0.0, 0.0, 0.0, 1.0)
    els[1].position = 1.0
    els[1].color = (1.0, 0.93, 0.62, 1.0)
    for pos, col in ((0.15, (0.5, 0.03, 0.0, 1.0)), (0.42, (1.0, 0.16, 0.01, 1.0)), (0.75, (1.0, 0.45, 0.04, 1.0))):
        e = els.new(pos)
        e.color = col
    g.link(g.math("MINIMUM", inten, 1.0), ramp.inputs["Fac"])
    g.link(ramp.outputs["Color"], em.inputs["Color"])
    # 두께(보는 방향 길이)가 클수록 빛이 쌓이므로 두께로 나눈다 — 한가운데를 지나는 빛이 STRENGTH 쯤 쌓인다
    g.link(g.mul(inten, STRENGTH * cfg["gain"] / (ry * 2.0)), em.inputs["Strength"])
    obj.data.materials.append(mat)
    return nt


def make_camera(cfg):
    sc = bpy.context.scene
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    # 정사영 크기 = 긴 변의 길이 (m)
    aspect = cfg["px"][0] / cfg["px"][1]
    cam.ortho_scale = cfg["w"] if aspect >= 1.0 else cfg["h"]
    co = bpy.data.objects.new("cam", cam)
    co.location = (0.0, -10.0, cfg["h"] * 0.5)
    co.rotation_euler = (math.radians(90), 0.0, 0.0)
    sc.collection.objects.link(co)
    sc.camera = co


def set_frame(nt, cfg, k):
    nt.nodes["big"].inputs["W"].default_value = k * cfg["w_step"]
    nt.nodes["fine"].inputs["W"].default_value = k * cfg["w_step"] * 1.6 + 7.0
    nt.nodes["col"].inputs["W"].default_value = k * cfg["w_step"] * 0.8 + 3.0
    nt.nodes["flow"].inputs["Location"].default_value = (0.0, 0.0, -k * cfg["rise"])


def render_frames(nt, cfg):
    os.makedirs(WORK, exist_ok=True)
    sc = bpy.context.scene
    paths = []
    frames = [5] if ONE else range(LOOP * 2)
    for k in frames:
        set_frame(nt, cfg, k)
        p = os.path.join(WORK, "fire_%s_%02d.png" % (KIND, k))
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        log(KIND, "render", k + 1, "/", LOOP * 2)
        paths.append(p)
    return paths


def load_rgb(path):
    img = bpy.data.images.load(path)
    w, h = img.size
    a = np.array(img.pixels[:], dtype=np.float32).reshape(h, w, 4)
    bpy.data.images.remove(img)
    return np.flipud(a)[..., :3]  # 위가 0번 줄


def to_rgba(rgb):
    """검은 바탕의 빛 → 투명 배경 그림: 불투명도 = 가장 밝은 색 성분(조금 키움), 색 = 그 빛깔을 가장 밝게 편 것.
    어두운 가장자리가 '어두운 색'이 아니라 '옅은 주황'이 되어, 밝은 바닥 위에서도 갈색 얼룩으로 보이지 않는다"""
    peak = rgb.max(axis=2, keepdims=True)
    alpha = np.clip(peak * 1.3, 0.0, 1.0) ** 0.9
    col = np.where(peak > 1e-4, rgb / np.maximum(peak, 1e-4), 0.0)
    return np.concatenate([np.clip(col, 0.0, 1.0), alpha], axis=2)


def save_png(arr, png):
    h, w = arr.shape[:2]
    img = bpy.data.images.new(os.path.basename(png), w, h, alpha=True)
    img.pixels = np.flipud(arr).clip(0.0, 1.0).ravel().tolist()
    img.filepath_raw = png
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    log("saved", png, w, "x", h)


def assemble(paths, cfg):
    frames = [load_rgb(p) for p in paths]
    out = []
    for k in range(LOOP):
        s = k / LOOP
        # 시간 루프: G(k) = F(k+L)(1 - k/L) + F(k)(k/L) — 빛은 더하면 되므로 그대로 섞는다
        out.append(to_rgba(frames[k + LOOP] * (1.0 - s) + frames[k] * s))
    atlas = np.concatenate(out, axis=0)  # 장을 세로로 쌓는다 (위가 0번)
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
    reset_scene(cfg)
    obj = make_box(cfg)
    nt = make_material(obj, cfg)
    make_camera(cfg)
    paths = render_frames(nt, cfg)
    if ONE:
        save_png(to_rgba(load_rgb(paths[0])), os.path.join(WORK, "fire_%s_one.png" % kind))
    else:
        assemble(paths, cfg)


def main():
    kinds = list(KINDS) if KIND == "all" else KIND.split(",")
    for k in kinds:
        bake(k)


main()
