# F04 연기 그림 (2026-11-12 사용자 결정): Blender 부피 연기를 구워 반복 재생 그림(플립북)으로 만든다.
# 실행: blender -b --factory-startup -P tools/blender/smoke_fx.py -- <작업 폴더> <종류> [one|quick]
#   종류: curtain | sheet | plume | spill | all
#   one: 0번 장 하나만 렌더 (모양 고르기, 결과 그림은 안 바꾼다). quick: 표본 수를 줄여 빨리
#   결과: art/fx/smoke_<종류>.png (장을 세로로 쌓음) + art/fx/fx.json 의 "smoke_<종류>"
#
# 네 그림 (모두 밝은 회색으로 굽고 게임에서 색을 곱한다 — 검은 연기 / 회색 연기 하나로):
#   curtain 연기층 앞면 커튼: 천장에 깔린 연기층을 정면에서 본 단면. 위는 짙고 아랫면은 뭉게뭉게 말려 내려온다.
#           가로 타일. 그림 위 = 천장, v = body_v 에 연기층 아랫면.
#   sheet   연기층 윗면: 방 안쪽을 덮는 연기 판을 위에서 본 모습. 가로·세로 타일 (방 크기에 맞춰 이어 붙인다).
#   plume   솟는 기둥: 불에서 솟아 천장에 부딪혀 퍼지는 연기 기둥 (정면). 그림 아래 = 불 위, 위 = 천장.
#   spill   문 넘침: 개구부 윗부분(인방 아래)으로 흘러나와 위로 말려 오르는 연기 (옆에서). 그림 왼쪽 = 벽,
#           v = lintel_v 에 개구부 윗면(인방).
# 노이즈가 시간(W)에 따라 변하고 무늬가 흐르는 쪽으로 움직인다. 시간은 끝과 처음이 이어지게(루프) 섞는다.

import bpy
import json
import math
import os
import sys

import numpy as np

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
WORK = os.path.abspath(ARGS[0]) if ARGS else os.path.join(os.path.dirname(__file__), "_smoke_work")
KIND = ARGS[1] if len(ARGS) > 1 else "curtain"
MODE = ARGS[2] if len(ARGS) > 2 else ""
ONE = MODE == "one"
QUICK = MODE in ("quick", "one")
PROJECT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
FX_JSON = os.path.join(PROJECT, "art", "fx", "fx.json")

LOOP = 24            # 반복 재생 장 수
SOURCE = "tools/blender/smoke_fx.py — Blender Cycles 부피 노이즈(정사영), 시간 루프"

# 종류별 설정. px = 렌더 크기(가로, 세로), box = 부피 상자 ((x0,x1),(y0,y1),(z0,z1)),
# cam = 카메라 ("front" 정면 / "top" 위), scale = 정사영 크기, tile = 가로·세로 이음새 없애기
KINDS = {
    "curtain": {
        "px": (640, 160), "box": ((0.0, 4.0), (-0.25, 0.25), (0.0, 1.0)), "cam": "front", "scale": 4.0,
        "center": (2.0, 0.5), "tile": "x", "fps": 6.0, "samples": 40,
        "w_step": 0.03, "flow": (0.0, 0.0, 0.012),
        "meta": {"tile_m": 2.0, "body_v": 0.75},
    },
    "sheet": {
        "px": (384, 384), "box": ((0.0, 4.0), (0.0, 4.0), (0.0, 0.4)), "cam": "top", "scale": 4.0,
        "center": (2.0, 2.0), "tile": "xy", "fps": 5.0, "samples": 24,
        "w_step": 0.025, "flow": (0.01, 0.006, 0.0),
        "meta": {"tile_m": 2.0},
    },
    "plume": {
        "px": (120, 192), "box": ((-0.75, 0.75), (-0.75, 0.75), (0.0, 2.4)), "cam": "front", "scale": 2.4,
        "center": (0.0, 1.2), "tile": "", "fps": 8.0, "samples": 32,
        "w_step": 0.04, "flow": (0.0, 0.0, -0.05),
        "meta": {"height_m": 2.4},
    },
    "spill": {
        "px": (160, 200), "box": ((0.0, 1.6), (-0.4, 0.4), (0.0, 2.0)), "cam": "front", "scale": 2.0,
        "center": (0.8, 1.0), "tile": "", "fps": 8.0, "samples": 32,
        "w_step": 0.04, "flow": (-0.035, 0.0, -0.035),
        # 인방(개구부 윗면) = 아래에서 0.5 → 그림 위에서 0.75
        "meta": {"out_m": 1.6, "height_m": 2.0, "lintel_v": 0.75},
    },
}


def log(*a):
    print("[smoke_fx]", *a, flush=True)


def reset_scene(cfg):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = "CYCLES"
    sc.cycles.device = "CPU"
    sc.cycles.samples = 16 if QUICK else cfg["samples"]
    sc.cycles.use_denoising = True
    sc.cycles.denoiser = "OPENIMAGEDENOISE"
    sc.cycles.volume_step_rate = 0.5
    sc.cycles.max_bounces = 4
    sc.render.film_transparent = True
    sc.render.resolution_x = cfg["px"][0]
    sc.render.resolution_y = cfg["px"][1]
    sc.render.resolution_percentage = 100
    sc.render.image_settings.file_format = "PNG"
    sc.render.image_settings.color_mode = "RGBA"
    sc.view_settings.view_transform = "Standard"
    return sc


# ── 노드 도우미 ──
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
        # lo → 0, hi → 1 (lo < hi). inv 이면 1 - 결과. lo·hi 는 숫자 또는 소켓
        mr = self.n.new("ShaderNodeMapRange")
        mr.interpolation_type = "SMOOTHSTEP"
        mr.clamp = True
        self.link(v, mr.inputs["Value"])
        for key, x in (("From Min", lo), ("From Max", hi)):
            if isinstance(x, (int, float)):
                mr.inputs[key].default_value = float(x)
            else:
                self.link(x, mr.inputs[key])
        return self.math("SUBTRACT", 1.0, mr.outputs["Result"]) if inv else mr.outputs["Result"]

    def remap(self, v, a, b, c, d):
        mr = self.n.new("ShaderNodeMapRange")
        mr.clamp = True
        self.link(v, mr.inputs["Value"])
        mr.inputs["From Min"].default_value = a
        mr.inputs["From Max"].default_value = b
        mr.inputs["To Min"].default_value = c
        mr.inputs["To Max"].default_value = d
        return mr.outputs["Result"]


def make_box(box):
    mesh = bpy.data.meshes.new("smoke_box")
    xs, ys, zs = box
    verts = [(x, y, z) for x in xs for y in ys for z in zs]
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    mesh.from_pydata(verts, [], faces)
    obj = bpy.data.objects.new("smoke_box", mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def make_material(obj, kind):
    mat = bpy.data.materials.new("smoke")
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    g = G(nt)
    out = g.n.new("ShaderNodeOutputMaterial")
    vol = g.n.new("ShaderNodeVolumePrincipled")
    vol.inputs["Color"].default_value = (0.92, 0.92, 0.94, 1.0)
    vol.inputs["Anisotropy"].default_value = 0.25
    g.link(vol.outputs["Volume"], out.inputs["Volume"])

    tc = g.n.new("ShaderNodeTexCoord")
    mp = g.n.new("ShaderNodeMapping")
    mp.name = "flow"
    g.link(tc.outputs["Object"], mp.inputs["Vector"])
    sep = g.n.new("ShaderNodeSeparateXYZ")
    g.link(tc.outputs["Object"], sep.inputs["Vector"])
    x, y, z = sep.outputs["X"], sep.outputs["Y"], sep.outputs["Z"]
    flow = mp.outputs["Vector"]

    if kind == "curtain":
        # 아랫면 높이 = 0.25 + (big - 0.5) × 1.3, 그 위는 연기 (속 짙기는 잔 무늬)
        big = g.noise("big", flow, 2.2, 5.0, 0.55, 0.8)
        fine = g.noise("fine", flow, 3.0, 6.0, 0.5)
        edge = g.math("ADD", g.math("MULTIPLY", g.math("SUBTRACT", big, 0.5), 1.3), 0.25)
        body = g.smooth(z, g.math("SUBTRACT", edge, 0.07), g.math("ADD", edge, 0.07))
        dens = g.math("MULTIPLY", g.math("MULTIPLY", body, g.remap(fine, 0.3, 0.7, 0.1, 1.6)), 5.0)
    elif kind == "sheet":
        # 위에서 본 연기 판: 윗면 높이가 큰 무늬로 울퉁불퉁 (낮은 해가 뭉게 그림자를 만든다),
        # 군데군데 옅은 틈으로 아래가 비친다
        big = g.noise("big", flow, 0.9, 2.0, 0.5, 0.15)
        fine = g.noise("fine", flow, 1.8, 3.0, 0.5, 0.1)
        # 노이즈 값은 0.5 둘레에 몰려 있어 0.35~0.65 를 -1~1 로 펴서 쓴다
        top = g.math("ADD", g.math("MULTIPLY", g.remap(big, 0.35, 0.65, -1.0, 1.0), 0.17), 0.17)
        body = g.smooth(z, g.math("SUBTRACT", top, 0.06), g.math("ADD", top, 0.06), inv=True)
        holes = g.smooth(fine, 0.4, 0.6)
        dens = g.math("MULTIPLY", g.math("MULTIPLY", body, g.math("ADD", g.math("MULTIPLY", holes, 1.2), 0.1)), 6.0)
    elif kind == "plume":
        # 기둥 반지름: 아래 좁고 위로 갈수록 넓어지며, 천장 가까이(위 20%)에서 옆으로 크게 퍼진다
        warp = g.noise("big", flow, 1.8, 3.0, 0.5, 0.3)
        fine = g.noise("fine", flow, 3.0, 4.0, 0.5)
        r = g.math("SQRT", g.math("ADD", g.math("MULTIPLY", x, x), g.math("MULTIPLY", y, y)))
        rn = g.math("ADD", r, g.math("MULTIPLY", g.remap(warp, 0.35, 0.65, -1.0, 1.0), 0.13))
        rad = g.math("ADD", g.math("ADD", g.math("MULTIPLY", z, 0.2), 0.12),
                     g.math("MULTIPLY", g.smooth(z, 1.6, 2.4), 0.3))
        body = g.smooth(rn, g.math("MULTIPLY", rad, 0.45), rad, inv=True)
        base = g.smooth(z, 0.0, 0.3)
        dens = g.math("MULTIPLY", g.math("MULTIPLY", g.math("MULTIPLY", body, base), g.remap(fine, 0.38, 0.62, 0.2, 1.6)), 7.0)
    else:  # spill
        # 개구부 윗부분(z 0~0.5)에서 나와 바깥으로 갈수록 떠오르고 넓어진다: 중심 z = 0.28 + 0.75·x^1.5
        warp = g.noise("big", flow, 3.0, 4.0, 0.55, 0.4)
        fine = g.noise("fine", flow, 3.5, 5.0, 0.5)
        xc = g.math("MAXIMUM", x, 0.0)
        center = g.math("ADD", g.math("MULTIPLY", g.math("POWER", xc, 1.5), 0.75), 0.28)
        width = g.math("ADD", g.math("MULTIPLY", xc, 0.32), 0.24)
        d = g.math("DIVIDE", g.math("ABSOLUTE", g.math("SUBTRACT", z, center)), width)
        dn = g.math("ADD", d, g.math("MULTIPLY", g.remap(warp, 0.35, 0.65, -1.0, 1.0), 0.45))
        body = g.smooth(dn, 0.45, 1.0, inv=True)
        tail = g.smooth(x, 1.0, 1.6, inv=True)
        top = g.smooth(z, 1.6, 2.0, inv=True)
        dens = g.math("MULTIPLY", g.math("MULTIPLY", g.math("MULTIPLY", g.math("MULTIPLY", body, tail), top),
                                         g.remap(fine, 0.38, 0.62, 0.15, 1.7)), 7.0)
    g.link(dens, vol.inputs["Density"])
    obj.data.materials.append(mat)
    return nt


def make_light_camera(cfg):
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
    if cfg["cam"] == "top":
        # 비스듬한 해 — 판 윗면의 뭉게가 그림자로 도드라진다
        so.rotation_euler = (math.radians(40), 0.0, math.radians(-35))
    else:
        # 위·앞에서 비춘다 (윗면 밝고 아랫면 어둡게)
        so.rotation_euler = (math.radians(25), math.radians(-30), 0.0)
    sc.collection.objects.link(so)

    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.ortho_scale = cfg["scale"]
    co = bpy.data.objects.new("cam", cam)
    cx, cy = cfg["center"]
    if cfg["cam"] == "top":
        co.location = (cx, cy, 10.0)
        co.rotation_euler = (0.0, 0.0, 0.0)
    else:
        co.location = (cx, -10.0, cy)
        co.rotation_euler = (math.radians(90), 0.0, 0.0)
    sc.collection.objects.link(co)
    sc.camera = co


def render_frames(nt, cfg):
    os.makedirs(WORK, exist_ok=True)
    sc = bpy.context.scene
    paths = []
    n = 1 if ONE else LOOP * 2
    for k in range(n):
        nt.nodes["big"].inputs["W"].default_value = k * cfg["w_step"]
        nt.nodes["fine"].inputs["W"].default_value = k * cfg["w_step"] * 1.3 + 7.0
        fx, fy, fz = cfg["flow"]
        nt.nodes["flow"].inputs["Location"].default_value = (k * fx, k * fy, k * fz)
        p = os.path.join(WORK, "%s_%02d.png" % (KIND, k))
        sc.render.filepath = p
        bpy.ops.render.render(write_still=True)
        log(KIND, "render", k + 1, "/", n)
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
    w = f.shape[1] // 2
    t = (np.arange(w, dtype=np.float32) / w)[None, :, None]
    return f[:, w:2 * w] * (1.0 - t) + f[:, 0:w] * t


def tile_y(f):
    return np.transpose(tile_x(np.transpose(f, (1, 0, 2))), (1, 0, 2))


def assemble(paths, cfg):
    frames = []
    for p in paths:
        f = premul(load_rgba(p))
        if "x" in cfg["tile"]:
            f = tile_x(f)
        if "y" in cfg["tile"]:
            f = tile_y(f)
        frames.append(f)
    out = []
    for k in range(LOOP):
        s = k / LOOP
        # 시간 루프: G(k) = F(k+L)(1 - k/L) + F(k)(k/L)
        out.append(unpremul(frames[k + LOOP] * (1.0 - s) + frames[k] * s))
    atlas = np.concatenate(out, axis=0)  # 장을 세로로 쌓는다 (위가 0번)
    h, w = atlas.shape[:2]
    png = os.path.join(PROJECT, "art", "fx", "smoke_%s.png" % KIND)
    img = bpy.data.images.new("smoke_" + KIND, w, h, alpha=True)
    img.pixels = np.flipud(atlas).clip(0.0, 1.0).ravel().tolist()
    img.filepath_raw = png
    img.file_format = "PNG"
    img.save()
    log("saved", png, w, "x", h)

    meta = json.load(open(FX_JSON, encoding="utf-8")) if os.path.exists(FX_JSON) else {}
    entry = {"w": w, "h": h // LOOP, "frames": LOOP, "fps": cfg["fps"], "source": SOURCE}
    entry.update(cfg["meta"])
    meta["smoke_" + KIND] = entry
    json.dump(meta, open(FX_JSON, "w", encoding="utf-8"), ensure_ascii=False, indent=2, sort_keys=True)


def bake(kind):
    global KIND
    KIND = kind
    cfg = KINDS[kind]
    reset_scene(cfg)
    obj = make_box(cfg["box"])
    nt = make_material(obj, kind)
    make_light_camera(cfg)
    paths = render_frames(nt, cfg)
    if not ONE:
        assemble(paths, cfg)


def main():
    kinds = list(KINDS) if KIND == "all" else KIND.split(",")
    for k in kinds:
        bake(k)


main()
