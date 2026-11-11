# P15: Kenney 3D 팩을 게임 입체 화면과 같은 카메라로 찍어 2D 프레임으로 굽는다 (기획안 9-4-1).
# 실행: blender -b --factory-startup -P tools/blender/bake.py -- tools/blender/bake_config.json [종류] [이름]
#   종류: characters | vehicles | furniture (생략하면 모두), 이름: 그 항목만 (예: firefighter)
# 출력: <out_dir>/<종류>/<이름>/<동작>_<방향0~7>_<프레임>.png (+ 헬멧 띠 _stripe.png), 같은 폴더에 meta.json
#   방향 k = 게임 칸 좌표에서 각도 k×45° (0 = +x, 화면 오른쪽 아래 / 2 = +y, 왼쪽 아래)
# 좌표 약속: Blender X = 칸 x, Blender Y = -칸 y (오른손 좌표 유지). 카메라는 칸 (+x, +y) 쪽 위에서 내려다본다.
# 모델 앞쪽은 Blender -Y (Kenney 사람·차 모두). 방향 k로 돌리는 각도 φ = 90° - 45°·k

import bpy
import json
import math
import os
import sys

import mathutils
from bpy_extras.object_utils import world_to_camera_view

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
CONFIG_PATH = os.path.abspath(ARGS[0]) if ARGS else os.path.join(os.path.dirname(__file__), "bake_config.json")
ONLY_KIND = ARGS[1] if len(ARGS) > 1 else ""
ONLY_NAME = ARGS[2] if len(ARGS) > 2 else ""
# 미리보기: 동작마다 첫 프레임만, 방향 0·2·5만 (빠른 확인용)
QUICK = len(ARGS) > 3 and ARGS[3] == "quick"
# 동작 확인: only=walk,carry → 그 동작만, 방향 1만, 모든 프레임
ONLY_ANIMS = ARGS[3][5:].split(",") if len(ARGS) > 3 and ARGS[3].startswith("only=") else []
ONLY_DIR = int(ARGS[4]) if len(ARGS) > 4 else 1
PROJECT = os.path.abspath(os.path.join(os.path.dirname(CONFIG_PATH), "..", ".."))
CFG = json.load(open(CONFIG_PATH, encoding="utf-8"))
PACKS = os.path.join(PROJECT, CFG["packs"])
OUT = os.path.join(PROJECT, CFG["out_dir"])
CAM = CFG["camera"]
SS = int(CAM["supersample"])
# 화면: 칸 대각선(0.5m × √2)이 2 × half_w px → 시선에 수직인 1m = K px
K = 2.0 * CAM["half_w_px"] / (CAM["cell_m"] * math.sqrt(2.0))
ELEV = math.asin(CAM["half_h_px"] / CAM["half_w_px"])  # 내려다보는 각도 (약 48.6°)
NDIR = int(CFG.get("directions", 8))
HUMAN_H = 1.75  # 사람 키 (m)


def log(*a):
    print("[bake]", *a, flush=True)


def hexcol(h, a=1.0):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    # sRGB → 선형
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (c[0], c[1], c[2], a)


def dir_angle(k):
    return math.radians(90.0 - 45.0 * k)


# --- 장면 ---

def reset():
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
    try:
        sc.eevee.taa_render_samples = 16
    except AttributeError:
        pass
    world = bpy.data.worlds.new("w")
    sc.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs[0].default_value = (0.55, 0.57, 0.6, 1.0)
    bg.inputs[1].default_value = 0.9
    # 해: 화면 왼쪽 위에서 (게임 연기·벽 그림자와 같은 쪽)
    sun = bpy.data.lights.new("sun", "SUN")
    sun.energy = 3.2
    so = bpy.data.objects.new("sun", sun)
    so.rotation_euler = (math.radians(40), 0, math.radians(-20))
    sc.collection.objects.link(so)
    return sc


def setup_camera(sc, frame_px, anchor_px, scale, target_z):
    """frame_px: 최종 그림 크기, anchor_px: 그 안에서 발밑(원점)이 올 점, scale: 게임 확대 1 대비 비율.
    원점이 anchor_px에 오도록 카메라를 옮긴다."""
    w, h = frame_px
    sc.render.resolution_x = w * SS
    sc.render.resolution_y = h * SS
    sc.render.resolution_percentage = 100
    cam = bpy.data.cameras.new("cam")
    cam.type = "ORTHO"
    cam.sensor_fit = "HORIZONTAL"
    k = K * scale  # 최종 그림의 1m 당 px
    cam.ortho_scale = w / k
    cam.clip_start = 0.1
    cam.clip_end = 200.0
    co = bpy.data.objects.new("cam", cam)
    sc.collection.objects.link(co)
    sc.camera = co
    # 시선: 칸 (+x, +y) → Blender (1, -1) 쪽에서 원점으로
    tilt = math.pi / 2 - ELEV
    co.rotation_euler = (tilt, 0.0, math.radians(45.0))
    look = co.rotation_euler.to_matrix() @ mathutils.Vector((0, 0, -1))
    # 화면에서 원점이 anchor에 오도록: 화면 가운데에서의 차이(px)를 카메라 오른쪽·위 방향(m)으로 옮긴다
    right = co.rotation_euler.to_matrix() @ mathutils.Vector((1, 0, 0))
    up = co.rotation_euler.to_matrix() @ mathutils.Vector((0, 1, 0))
    dx_m = (w / 2.0 - anchor_px[0]) / k
    dy_m = (anchor_px[1] - h / 2.0) / k
    center = mathutils.Vector((0, 0, 0)) + right * dx_m + up * dy_m
    co.location = center - look * 50.0
    return co


def render_to(path, final_px):
    sc = bpy.context.scene
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp.png"
    sc.render.filepath = tmp
    bpy.ops.render.render(write_still=True)
    img = bpy.data.images.load(tmp)
    if SS != 1:
        img.scale(final_px[0], final_px[1])
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)
    os.remove(tmp)


def flat_mat(name, color, rough=0.8, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    p.inputs["Base Color"].default_value = color
    p.inputs["Roughness"].default_value = rough
    if emit > 0.0:
        p.inputs["Emission Color"].default_value = color
        p.inputs["Emission Strength"].default_value = emit
    return m


def image_mat(name, image_path, tint=None):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    p = nt.nodes.get("Principled BSDF")
    p.inputs["Roughness"].default_value = 0.85
    tex = nt.nodes.new("ShaderNodeTexImage")
    tex.image = bpy.data.images.load(image_path, check_existing=True)
    tex.interpolation = "Closest"
    if tint:
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MULTIPLY"
        mix.inputs["Factor"].default_value = 0.85
        nt.links.new(tex.outputs["Color"], mix.inputs[6])
        mix.inputs[7].default_value = tint
        nt.links.new(mix.outputs[2], p.inputs["Base Color"])
    else:
        nt.links.new(tex.outputs["Color"], p.inputs["Base Color"])
    return m


def bbox_world(objs):
    pts = []
    for o in objs:
        if o.type == "MESH":
            pts += [o.matrix_world @ mathutils.Vector(c) for c in o.bound_box]
    mn = mathutils.Vector([min(p[i] for p in pts) for i in range(3)])
    mx = mathutils.Vector([max(p[i] for p in pts) for i in range(3)])
    return mn, mx


def write_meta(folder, meta):
    os.makedirs(folder, exist_ok=True)
    with open(os.path.join(folder, "meta.json"), "w", encoding="utf-8") as f:
        json.dump(meta, f, ensure_ascii=False, indent=1)


# --- 사람 ---

CHAR_DIR = os.path.join(PACKS, "animated-characters-retro")
HEAD_BONES = {"Head", "Neck"}
HAND_PREFIX = ("LeftHand", "RightHand")
FOOT_BONES = {"LeftFoot", "RightFoot", "LeftToes", "RightToes"}


def import_character():
    bpy.ops.import_scene.fbx(filepath=os.path.join(CHAR_DIR, "Model", "characterMedium.fbx"))
    arm = [o for o in bpy.data.objects if o.type == "ARMATURE"][0]
    mesh = [o for o in bpy.data.objects if o.type == "MESH"][0]
    arm.name = "rig"
    mesh.name = "body"
    s = HUMAN_H / 3.77
    arm.scale = (s, s, s)
    actions = {}
    for anim in ("idle", "run"):
        before = set(bpy.data.objects)
        n0 = set(bpy.data.actions)
        bpy.ops.import_scene.fbx(filepath=os.path.join(CHAR_DIR, "Animations", anim + ".fbx"))
        # 파일마다 'Targeting Pose'(2프레임 정지 자세)와 실제 동작이 함께 들어온다. 이름에 .001이 붙을 수 있어 동작 이름으로 고른다
        new_actions = [a for a in bpy.data.actions if a not in n0 and "targeting" not in a.name.lower()]
        named = [a for a in new_actions if anim.lower() in a.name.lower()]
        actions[anim] = (named or new_actions)[0]
        log("동작", anim, "→", actions[anim].name, actions[anim].frame_range[:])
        for o in set(bpy.data.objects) - before:
            bpy.data.objects.remove(o, do_unlink=True)
    # 다리 IK (원래 리그의 발 IK 제어 뼈를 그대로 목표로): 웅크리기·무릎 꿇기에서 발이 땅에 붙어 있게
    for side in ("Left", "Right"):
        c = arm.pose.bones[side + "Leg"].constraints.new("IK")
        c.target = arm
        c.subtarget = side + "FootIK"
        c.pole_target = arm
        c.pole_subtarget = side + "KneeCtrl"
        c.pole_angle = math.radians(-90)
        c.chain_count = 2
    return arm, mesh, actions


def bone_category(mesh, poly):
    weights = {}
    for vi in poly.vertices:
        for g in mesh.data.vertices[vi].groups:
            name = mesh.vertex_groups[g.group].name
            weights[name] = weights.get(name, 0.0) + g.weight
    if not weights:
        return "coat"
    b = max(weights, key=weights.get)
    if b in HEAD_BONES:
        return "head"
    if b.startswith(HAND_PREFIX):
        return "glove"
    if b in FOOT_BONES:
        return "boot"
    return "coat"


def dress(mesh, skin_png, outfit, colors):
    """plain: 원래 옷(스킨 그림). turnout: 방화복 색 + 반사띠 (면 단위). 머리는 방화두건(coat 색) — 얼굴은 면체가 가린다"""
    skin = image_mat("skin", skin_png)
    mesh.data.materials.clear()
    mesh.data.materials.append(skin)
    if outfit != "turnout":
        return
    mesh.data.materials[0] = flat_mat("hood", hexcol(colors.get("hood", colors["coat"])))
    mats = {"coat": flat_mat("coat", hexcol(colors["coat"])),
            "reflect": flat_mat("reflect", hexcol(colors["reflect"]), 0.35, 0.6),
            "glove": flat_mat("glove", hexcol(colors["glove"])),
            "boot": flat_mat("boot", hexcol(colors["boot"]))}
    index = {"head": 0}
    for key in ("coat", "reflect", "glove", "boot"):
        mesh.data.materials.append(mats[key])
        index[key] = len(mesh.data.materials) - 1
    # 반사띠: 쉬는 자세(T자)의 높이·옆 위치로 고른 띠 (가슴·허리·손목·정강이) — 키 3.77 단위
    for p in mesh.data.polygons:
        cat = bone_category(mesh, p)
        c = p.center
        if cat == "coat":
            torso = abs(c.x) < 0.5
            band = (torso and (2.0 < c.z < 2.12 or 1.42 < c.z < 1.52 or 0.3 < c.z < 0.42)) or (not torso and 1.05 < abs(c.x) < 1.2)
            if band:
                cat = "reflect"
        p.material_index = index[cat]


## 헬멧 색 그림(게임에서 역할 색을 입히는 층)에 들어가는 물체
TINT_PARTS = ("helmet", "brim")
## 헬멧 재질: 몸 그림에서는 회색(가장자리 번짐이 어느 역할 색에도 튀지 않게), 색 층에서는 흰색(곱하면 역할 색 그대로)
HELMET_BASE = (0.35, 0.35, 0.35, 1.0)
HELMET_TINT = (0.9, 0.9, 0.9, 1.0)


def _box(name, size, color, rough=0.7):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=(0, 0, 0))
    o = bpy.context.active_object
    o.name = name
    o.scale = size
    o.data.materials.append(flat_mat(name, color, rough))
    return o


def add_gear(arm, colors, tint):
    """서울소방 방화복 참고 그림(소방관 캐릭터.png)을 따라 헬멧·반사띠·면체·공기호흡기·멜빵을 단순 도형으로 뼈에 붙인다.
    헬멧 색은 역할(진압 검정·구조 주황·구급 흰색)마다 다르므로 흰 헬멧을 따로 찍어 게임에서 색을 입힌다.
    반환: 헬멧 재질 (tint가 아니면 None)"""
    # 헬멧: 머리(1단위 높이) 위 반구 + 뒤가 긴 챙 (한국 소방 헬멧)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=24, ring_count=12, radius=0.6, location=(0, 0, 0))
    helmet = bpy.context.active_object
    helmet.name = "helmet"
    for v in helmet.data.vertices:
        v.co.z = max(v.co.z, -0.05)
    helmet.scale = (1.02, 1.12, 0.9)
    helmet_mat = flat_mat("helmet", HELMET_BASE, 0.35)
    helmet.data.materials.append(helmet_mat)
    bpy.ops.mesh.primitive_cylinder_add(vertices=28, radius=0.64, depth=0.05, location=(0, 0, 0))
    brim = bpy.context.active_object
    brim.name = "brim"
    brim.scale = (1.0, 1.18, 1.0)
    brim.data.materials.append(helmet_mat)
    # 헬멧 둘레 반사띠 (연두) — 역할 색과 상관없이 늘 같은 색
    bpy.ops.mesh.primitive_cylinder_add(vertices=28, radius=0.625, depth=0.12, location=(0, 0, 0))
    hband = bpy.context.active_object
    hband.name = "helmet_band"
    hband.scale = (1.02, 1.12, 1.0)
    hband.data.materials.append(flat_mat("hband", hexcol(colors["reflect"]), 0.35))
    # 면체: 얼굴 앞 검은 유리 (앞 = -Y)
    bpy.ops.mesh.primitive_uv_sphere_add(segments=20, ring_count=10, radius=0.34, location=(0, 0, 0))
    mask = bpy.context.active_object
    mask.name = "mask"
    mask.scale = (1.05, 0.75, 1.1)
    mask.data.materials.append(flat_mat("mask", hexcol(colors["mask"]), 0.15))
    # 공기호흡기: 검은 등판 + 회녹색 용기 (등 = +Y)
    plate = _box("harness_plate", (0.5, 0.1, 0.95), hexcol(colors["harness"]))
    bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.19, depth=1.15, location=(0, 0, 0))
    tank = bpy.context.active_object
    tank.name = "scba"
    tank.data.materials.append(flat_mat("tank", hexcol(colors["tank"]), 0.35))
    # 앞 멜빵 두 줄과 허리 벨트
    strap_l = _box("strap_l", (0.11, 0.06, 0.85), hexcol(colors["harness"]))
    strap_r = _box("strap_r", (0.11, 0.06, 0.85), hexcol(colors["harness"]))
    for o, bone, off in ((helmet, "Head", (0, 0.03, 0.58)), (brim, "Head", (0, 0.1, 0.53)), (hband, "Head", (0, 0.03, 0.6)),
                         (mask, "Head", tuple(colors.get("mask_offset", (0, -0.42, 0.2)))),
                         (plate, "UpperChest", (0, 0.3, -0.2)), (tank, "UpperChest", (0, 0.44, -0.15)),
                         (strap_l, "UpperChest", (-0.2, -0.33, -0.15)), (strap_r, "UpperChest", (0.2, -0.33, -0.15))):
        b = arm.data.bones[bone]
        size = mathutils.Matrix.Diagonal(tuple(o.scale) + (1.0,))
        o.parent = arm
        o.parent_type = "BONE"
        o.parent_bone = bone
        upd()
        # 쉬는 자세에서 뼈 머리 + 오프셋(아마추어 단위)에 놓으면 그 뒤로 뼈를 따라 움직인다
        o.matrix_world = arm.matrix_world @ mathutils.Matrix.Translation(b.head_local + mathutils.Vector(off)) @ size
    return helmet_mat if tint else None


def set_helmet(mat, color):
    mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = color


def assign_action(arm, act):
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    if act is not None and hasattr(arm.animation_data, "action_slot") and len(act.slots) > 0:
        arm.animation_data.action_slot = act.slots[0]


def _fcurves(act):
    """동작의 곡선 목록 (Blender 4.4+ 슬롯 동작과 예전 동작 모두)"""
    if hasattr(act, "layers") and len(act.layers) > 0:
        out = []
        for layer in act.layers:
            for strip in layer.strips:
                for cb in strip.channelbags:
                    out += list(cb.fcurves)
        return out
    return list(act.fcurves)


def sample_pose(act, frame):
    """곡선에서 그 프레임의 뼈 자세를 직접 읽는다 {뼈: (위치, 회전, 크기)}.
    (예전에는 동작을 붙였다 떼며 frame_set으로 읽었는데, 다시 붙일 때 평가되지 않아 모든 프레임이 같은 자세였다)"""
    pose = {}
    for fc in _fcurves(act):
        dp = fc.data_path
        if not dp.startswith('pose.bones["'):
            continue
        bone = dp.split('"')[1]
        prop = dp.rsplit(".", 1)[1]
        loc, rot, sca = pose.get(bone, (mathutils.Vector((0, 0, 0)), mathutils.Quaternion((1, 0, 0, 0)), mathutils.Vector((1, 1, 1))))
        v = fc.evaluate(frame)
        if prop == "location":
            loc[fc.array_index] = v
        elif prop == "rotation_quaternion":
            rot[fc.array_index] = v
        elif prop == "scale":
            sca[fc.array_index] = v
        pose[bone] = (loc, rot, sca)
    for b in pose:
        pose[b][1].normalize()
    return pose


def capture_pose(arm):
    return {pb.name: (pb.location.copy(), pb.rotation_quaternion.copy(), pb.scale.copy()) for pb in arm.pose.bones}


def apply_pose(arm, pose):
    for pb in arm.pose.bones:
        if pb.name not in pose:
            pb.location = (0, 0, 0)
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.scale = (1, 1, 1)
            continue
        loc, rot, sca = pose[pb.name]
        pb.location = loc
        pb.rotation_quaternion = rot
        pb.scale = sca


def upd():
    bpy.context.view_layer.update()


def rot_arm(arm, name, axis, deg):
    """뼈를 아마추어 공간 축으로 돌린다 (뼈 머리 기준). 자식 뼈는 따라간다"""
    pb = arm.pose.bones[name]
    pivot = pb.head.copy()
    r = mathutils.Matrix.Rotation(math.radians(deg), 4, axis)
    pb.matrix = mathutils.Matrix.Translation(pivot) @ r @ mathutils.Matrix.Translation(-pivot) @ pb.matrix
    upd()


def move_arm(arm, name, delta):
    pb = arm.pose.bones[name]
    m = pb.matrix.copy()
    m.translation += mathutils.Vector(delta)
    pb.matrix = m
    upd()


def aim_arm(arm, name, target):
    pb = arm.pose.bones[name]
    v = pb.tail - pb.head
    q = v.rotation_difference(mathutils.Vector(target).normalized())
    pivot = pb.head.copy()
    pb.matrix = mathutils.Matrix.Translation(pivot) @ q.to_matrix().to_4x4() @ mathutils.Matrix.Translation(-pivot) @ pb.matrix
    upd()


WALK_BLEND = 0.5  # 뛰기 동작을 쉬는 자세 쪽으로 섞는 비율 (보폭·상하 흔들림을 줄여 걷기로)
WALK_ARM_SWING = 24.0  # 걷기 팔 흔들기 (도)
LEG_WORDS = ("Foot", "Toe", "Heel", "Knee", "Leg", "Hips", "Spine", "Chest", "Neck", "Head")


def walk_from_run(arm):
    """팩에 걷기가 없어 뛰기 자세를 쉬는 자세 쪽으로 섞고, 팔은 내린 채 다리와 반대로 흔든다"""
    for pb in arm.pose.bones:
        if any(w in pb.name for w in LEG_WORDS):
            pb.location = pb.location * WALK_BLEND
            pb.rotation_quaternion = mathutils.Quaternion((1, 0, 0, 0)).slerp(pb.rotation_quaternion, WALK_BLEND)
    upd()
    left = arm.pose.bones["LeftFootIK"].head.y
    right = arm.pose.bones["RightFootIK"].head.y
    s = max(-1.0, min(1.0, (right - left) / 0.5))  # +면 왼발이 앞(-Y)
    for side, sx in (("Left", 1), ("Right", -1)):
        aim_arm(arm, side + "Arm", (0.18 * sx, 0.02, -1))
        aim_arm(arm, side + "ForeArm", (0.08 * sx, -0.25, -1))
    # 왼발이 앞이면 오른팔이 앞으로 (앞으로 흔들기 = X축 음의 회전)
    rot_arm(arm, "RightArm", "X", -WALK_ARM_SWING * s)
    rot_arm(arm, "LeftArm", "X", WALK_ARM_SWING * s)


def pose_mod(arm, pose_name, i, n):
    """스크립트 자세 (아마추어 단위: 키 3.77, 앞 = -Y). i: 프레임 번호, n: 프레임 수"""
    if pose_name in ("walk", "crouch", "carry"):
        walk_from_run(arm)
    if pose_name in ("arms_down", "down", "down_up"):
        # 팩의 서기 동작은 허리에 손을 얹은 자세라 팔을 몸 옆으로 내린다
        for side, sx in (("Left", 1), ("Right", -1)):
            aim_arm(arm, side + "Arm", (0.18 * sx, 0.02, -1))
            aim_arm(arm, side + "ForeArm", (0.08 * sx, -0.18, -1))
    elif pose_name == "crouch":
        move_arm(arm, "HipsCtrl", (0, 0, -0.55))
        rot_arm(arm, "Spine", "X", 28)
        rot_arm(arm, "Head", "X", -20)
    elif pose_name == "carry":
        move_arm(arm, "HipsCtrl", (0, 0, -0.2))
        for side in ("Left", "Right"):
            aim_arm(arm, side + "Arm", (0.15 if side == "Left" else -0.15, -1, -0.55))
            aim_arm(arm, side + "ForeArm", (0, -1, 0.1))
    elif pose_name == "spray":
        move_arm(arm, "HipsCtrl", (0, 0.1, -0.5))
        rot_arm(arm, "Spine", "X", 18)
        rot_arm(arm, "Spine", "Z", [-4, 0, 4, 0][i % 4])
        aim_arm(arm, "RightArm", (0.1, -1, -0.15))
        aim_arm(arm, "RightForeArm", (0.25, -1, 0.0))
        aim_arm(arm, "LeftArm", (0.35, -1, -0.35))
        aim_arm(arm, "LeftForeArm", (-0.2, -1, -0.05))
    elif pose_name == "search":
        move_arm(arm, "LeftFootCtrl", (0, 0.75, 0.15))
        move_arm(arm, "LeftKneeCtrl", (0, 0.2, -0.6))
        move_arm(arm, "RightFootCtrl", (0, -0.35, 0))
        move_arm(arm, "HipsCtrl", (0, 0.15, -0.75))
        rot_arm(arm, "Spine", "X", 38)
        sweep = [-0.6, -0.2, 0.2, 0.6][i % 4]
        aim_arm(arm, "RightArm", (sweep - 0.3, -1, -1.1))
        aim_arm(arm, "RightForeArm", (sweep - 0.3, -1, -1.4))
        aim_arm(arm, "LeftArm", (0.3, -0.3, -1))
    upd()


def nozzle_follow(arm, nozzle):
    """관창: 오른손에서 앞으로 뻗은 원통 (매 프레임 손 위치로)"""
    pb = arm.pose.bones["RightHand"]
    hand = arm.matrix_world @ pb.head
    fwd = (arm.matrix_world.to_3x3() @ mathutils.Vector((0, -1, -0.12))).normalized()
    nozzle.location = hand + fwd * 0.18
    nozzle.rotation_euler = fwd.to_track_quat("Z", "Y").to_euler()


def bake_built_character(spec):
    """스크립트로 만든 모델(tools/blender/<builder>.py)을 굽는다. 자세는 모델 모듈이 프레임마다 만든다"""
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import importlib
    mod = importlib.import_module(spec["builder"])
    sc = reset()
    rig = mod.build(spec["colors"])
    arm = rig.arm
    setup_camera(sc, spec["frame"], spec["anchor"], spec["scale"], 0.9)
    folder = os.path.join(OUT, "characters", spec["name"])
    meta = {"kind": "characters", "name": spec["name"], "frame": spec["frame"], "anchor": spec["anchor"], "scale": spec["scale"],
            "directions": NDIR, "anims": {}, "stripe": True, "source": spec.get("source", "")}
    if spec.get("save_blend"):
        path = os.path.join(PROJECT, spec["save_blend"])
        os.makedirs(os.path.dirname(path), exist_ok=True)
        bpy.ops.wm.save_as_mainfile(filepath=path, copy=True)
        log("모델 저장", path)
    for anim in spec["anims"]:
        if ONLY_ANIMS and anim not in ONLY_ANIMS:
            continue
        a = CFG["anims"][anim]
        n = int(a["frames"])
        meta["anims"][anim] = {"frames": n, "note": a.get("note", "")}
        for i in range(1 if QUICK else n):
            arm.matrix_world = mathutils.Matrix.Identity(4)
            lie = rig.pose(anim, i, n)
            lo, hi = rig.bounds()
            # 발밑(가장 낮은 곳)을 바닥에. 누운 자세는 몸 가운데를 원점에
            off = mathutils.Vector((-(lo.x + hi.x) / 2 if lie else 0.0, -(lo.y + hi.y) / 2 if lie else 0.0, -lo.z))
            for k in ([0, 2, 5] if QUICK else ([ONLY_DIR] if ONLY_ANIMS else range(NDIR))):
                arm.matrix_world = mathutils.Matrix.Rotation(dir_angle(k), 4, "Z") @ mathutils.Matrix.Translation(off)
                upd()
                name = "%s_%d_%d.png" % (anim, k, i)
                for o in bpy.data.objects:
                    o.is_holdout = False
                set_helmet(rig.helmet_mat, HELMET_BASE)
                render_to(os.path.join(folder, name), spec["frame"])
                set_helmet(rig.helmet_mat, HELMET_TINT)
                for o in bpy.data.objects:
                    if o.type == "MESH" and o.name not in TINT_PARTS:
                        o.is_holdout = True
                render_to(os.path.join(folder, name.replace(".png", "_stripe.png")), spec["frame"])
                for o in bpy.data.objects:
                    o.is_holdout = False
        log(spec["name"], anim, "done")
    write_meta(folder, meta)


def bake_character(spec):
    if spec.get("builder"):
        return bake_built_character(spec)
    sc = reset()
    arm, mesh, actions = import_character()
    dress(mesh, os.path.join(CHAR_DIR, "Skins", spec["skin"] + ".png"), spec["outfit"], spec.get("colors", {}))
    helmet_mat = None
    if spec["outfit"] == "turnout":
        helmet_mat = add_gear(arm, spec["colors"], spec.get("stripe", False))
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=0.035, depth=0.45)
    nozzle = bpy.context.active_object
    nozzle.name = "nozzle"
    nozzle.data.materials.append(flat_mat("nozzle", hexcol("#9AA0A6"), 0.3))
    nozzle.hide_render = True
    setup_camera(sc, spec["frame"], spec["anchor"], spec["scale"], 0.9)
    folder = os.path.join(OUT, "characters", spec["name"])
    meta = {"kind": "characters", "name": spec["name"], "frame": spec["frame"], "anchor": spec["anchor"], "scale": spec["scale"],
            "directions": NDIR, "anims": {}, "stripe": helmet_mat is not None}
    base_s = arm.scale.x
    for anim in spec["anims"]:
        if ONLY_ANIMS and anim not in ONLY_ANIMS:
            continue
        a = CFG["anims"][anim]
        act = actions[a["source"]]
        f0, f1 = act.frame_range
        n = int(a["frames"])
        pose_name = a.get("pose", "")
        meta["anims"][anim] = {"frames": n, "note": a.get("note", "")}
        nozzle.hide_render = pose_name != "spray"
        assign_action(arm, None)
        for i in range(1 if QUICK else n):
            # 첫 프레임은 T자 자세일 수 있어 건너뛴다. 반복 동작은 한 바퀴를 n등분
            src = f0 + 1 + (f1 - f0 - 1) * i / max(1, n)
            apply_pose(arm, sample_pose(act, src))
            upd()
            pose_mod(arm, pose_name, i, n)
            for k in ([0, 2, 5] if QUICK else ([ONLY_DIR] if ONLY_ANIMS else range(NDIR))):
                # 쓰러짐: 엎드림(down)·반듯이(down_up). 몸 가운데가 원점에 오게 눕힌다
                lie = pose_name in ("down", "down_up")
                rz = mathutils.Matrix.Rotation(dir_angle(k), 4, "Z")
                if lie:
                    rx = mathutils.Matrix.Rotation(math.radians(90 if pose_name == "down" else -90), 4, "X")
                    shift = mathutils.Matrix.Translation((0, 0.85 if pose_name == "down" else -0.85, 0.18))
                    arm.matrix_world = rz @ shift @ rx @ mathutils.Matrix.Scale(base_s, 4)
                else:
                    arm.matrix_world = rz @ mathutils.Matrix.Scale(base_s, 4)
                upd()
                if pose_name == "spray":
                    nozzle_follow(arm, nozzle)
                    upd()
                name = "%s_%d_%d.png" % (anim, k, i)
                for o in bpy.data.objects:
                    o.is_holdout = False
                if helmet_mat is not None:
                    set_helmet(helmet_mat, HELMET_BASE)
                render_to(os.path.join(folder, name), spec["frame"])
                if helmet_mat is not None:
                    # 헬멧만 흰색으로 (다른 물체는 가림막 — 앞을 가리는 반사띠·면체는 빠진다). 게임에서 역할 색을 곱한다.
                    # 파일 이름 _stripe는 예전 '헬멧 띠' 층 이름을 그대로 쓴다 (불러오기 도구와 맞춤)
                    set_helmet(helmet_mat, HELMET_TINT)
                    for o in bpy.data.objects:
                        if o.type == "MESH" and o.name not in TINT_PARTS:
                            o.is_holdout = True
                    render_to(os.path.join(folder, name.replace(".png", "_stripe.png")), spec["frame"])
                    for o in bpy.data.objects:
                        o.is_holdout = False
        log(spec["name"], anim, "done")
    write_meta(folder, meta)


# --- 차량 ---

def vehicle_stats():
    path = os.path.join(PROJECT, "data", "units", "vehicles.json")
    return json.load(open(path, encoding="utf-8"))


def bake_vehicle(spec, scale):
    sc = reset()
    stats = vehicle_stats()
    path = os.path.join(PACKS, "car-kit", "Models", "GLB format", spec["model"] + ".glb")
    bpy.ops.import_scene.gltf(filepath=path)
    parts = [o for o in bpy.data.objects if o.type == "MESH"]
    # 색 바꾸기: hue = 색상 이동(흰·회색은 그대로), tint = 곱하기 색
    if "tint" in spec or "hue" in spec:
        done = set()
        for o in parts:
            for slot in o.material_slots:
                m = slot.material
                if m is None or not m.use_nodes or m.name in done:
                    continue
                done.add(m.name)
                nt = m.node_tree
                p = nt.nodes.get("Principled BSDF")
                link = p.inputs["Base Color"].links[0] if p.inputs["Base Color"].links else None
                if link is None:
                    continue
                if "hue" in spec:
                    hs = nt.nodes.new("ShaderNodeHueSaturation")
                    hs.inputs["Hue"].default_value = 0.5 + float(spec["hue"])
                    nt.links.new(link.from_socket, hs.inputs["Color"])
                    nt.links.new(hs.outputs["Color"], p.inputs["Base Color"])
                else:
                    mix = nt.nodes.new("ShaderNodeMix")
                    mix.data_type = "RGBA"
                    mix.blend_type = "MULTIPLY"
                    mix.inputs["Factor"].default_value = 0.9
                    nt.links.new(link.from_socket, mix.inputs[6])
                    mix.inputs[7].default_value = hexcol(spec["tint"])
                    nt.links.new(mix.outputs[2], p.inputs["Base Color"])
    root = bpy.data.objects.new("vehicle", None)
    sc.collection.objects.link(root)
    mn, mx = bbox_world(parts)
    for o in bpy.data.objects:
        if o.parent is None and o is not root and o.type in ("MESH", "EMPTY"):
            o.parent = root
    if "size_m" in spec:
        L, W, H = spec["size_m"]
    else:
        st = stats[spec["type"]]
        L, W, H = float(st["length_m"]), float(st["width_m"]), float(st["height_m"])
    cx, cy = (mn.x + mx.x) / 2, (mn.y + mx.y) / 2
    sx, sy, sz = W / (mx.x - mn.x), L / (mx.y - mn.y), H / (mx.z - mn.z)
    base = mathutils.Matrix.Diagonal((sx, sy, sz, 1.0)) @ mathutils.Matrix.Translation((-cx, -cy, -mn.z))
    if spec.get("boom"):
        # 굴절차 붐: 차체 위 접힌 팔 + 뒤쪽 바스켓 (단순 도형, 실제 크기 m)
        bpy.ops.mesh.primitive_cube_add(size=1.0)
        boom = bpy.context.active_object
        boom.scale = (0.45, L * 0.75, 0.35)
        boom.location = (0, -L * 0.05, H + 0.2)
        boom.data.materials.append(flat_mat("boom", hexcol("#D6D3CC"), 0.5))
        bpy.ops.mesh.primitive_cube_add(size=1.0)
        basket = bpy.context.active_object
        basket.scale = (1.4, 0.9, 0.9)
        basket.location = (0, L * 0.38, H * 0.7)
        basket.data.materials.append(flat_mat("basket", hexcol("#F2C230"), 0.5))
        extra = [(boom, boom.location.copy(), boom.scale.copy()), (basket, basket.location.copy(), basket.scale.copy())]
    elif spec.get("tank"):
        # 물탱크차: 지붕 위 가로 물탱크 (실제 크기 m)
        bpy.ops.mesh.primitive_cylinder_add(vertices=20, radius=1.0, depth=1.0)
        tank = bpy.context.active_object
        tank.rotation_euler = (math.radians(90), 0, 0)
        tank.data.materials.append(flat_mat("tank", hexcol("#C9CDD2"), 0.35))
        bpy.ops.object.transform_apply(rotation=True)
        tank.scale = (W * 0.42, L * 0.55, 0.55)
        tank.location = (0, L * 0.12, H * 0.92)
        extra = [(tank, tank.location.copy(), tank.scale.copy())]
    else:
        extra = []
    # 화면 크기: 대각선으로 놓였을 때까지 들어가게
    k = K * scale
    span = (L + W) * k * 0.75 + 16
    frame = [int(math.ceil(span / 8.0) * 8), int(math.ceil((span * 0.62 + H * k * math.cos(ELEV) + 16) / 8.0) * 8)]
    anchor = [frame[0] // 2, int(frame[1] * 0.62)]
    setup_camera(sc, frame, anchor, scale, 0)
    folder = os.path.join(OUT, "vehicles", spec["name"])
    for kdir in range(NDIR):
        rz = mathutils.Matrix.Rotation(dir_angle(kdir), 4, "Z")
        root.matrix_world = rz @ base
        for e, loc, size in extra:
            e.matrix_world = rz @ mathutils.Matrix.Translation(loc) @ mathutils.Matrix.Diagonal(tuple(size) + (1.0,))
        upd()
        render_to(os.path.join(folder, "idle_%d_0.png" % kdir), frame)
    write_meta(folder, {"kind": "vehicles", "name": spec["name"], "type": spec["type"], "frame": frame, "anchor": anchor, "scale": scale,
                        "directions": NDIR, "anims": {"idle": {"frames": 1}}, "size_m": [L, W, H]})
    log("vehicle", spec["name"], "done")


# --- 가구 ---

def bake_furniture(spec, scale):
    sc = reset()
    fdir = os.path.join(PACKS, "furniture-kit", "Models", "GLTF format")
    root = bpy.data.objects.new("furniture", None)
    sc.collection.objects.link(root)
    for part in spec["parts"]:
        model, ox, oy = part[0], float(part[1]), float(part[2])
        oz = float(part[3]) if len(part) > 3 else 0.0
        rot = float(part[4]) if len(part) > 4 else 0.0
        before = set(bpy.data.objects)
        bpy.ops.import_scene.gltf(filepath=os.path.join(fdir, model + ".glb"))
        new = [o for o in set(bpy.data.objects) - before]
        mn, mx = bbox_world(new)
        holder = bpy.data.objects.new(model, None)
        sc.collection.objects.link(holder)
        for o in new:
            if o.parent is None:
                o.parent = holder
        # 부품 가운데를 (ox, oy)에, 바닥을 oz에 (팩 단위)
        holder.matrix_world = mathutils.Matrix.Translation((ox, oy, oz)) @ mathutils.Matrix.Rotation(math.radians(rot), 4, "Z") \
            @ mathutils.Matrix.Translation((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
        holder.parent = root
    upd()
    meshes = [o for o in bpy.data.objects if o.type == "MESH"]
    mn, mx = bbox_world(meshes)
    nl, ns = spec["nominal"]
    L, W = nl * CAM["cell_m"] * 0.92, ns * CAM["cell_m"] * 0.92
    H = float(spec.get("h_m", 1.0))
    sx, sy, sz = L / (mx.x - mn.x), W / (mx.y - mn.y), H / max(0.01, mx.z - mn.z)
    base = mathutils.Matrix.Diagonal((sx, sy, sz, 1.0)) @ mathutils.Matrix.Translation((-(mn.x + mx.x) / 2, -(mn.y + mx.y) / 2, -mn.z))
    k = K * scale
    span = (nl + ns) * CAM["cell_m"] * k * 0.75 + 12
    frame = [int(math.ceil(span / 8.0) * 8), int(math.ceil((span * 0.62 + H * k * math.cos(ELEV) + 12) / 8.0) * 8)]
    anchor = [frame[0] // 2, int(frame[1] - span * 0.36 - 6)]
    setup_camera(sc, frame, anchor, scale, 0)
    folder = os.path.join(OUT, "furniture", spec["name"])
    # 4방향: k = 0 긴 쪽이 칸 x를 따라, 앞이 +y(화면 왼쪽 아래) / 1: 앞 -x / 2: 앞 -y / 3: 앞 +x
    for kdir in range(4):
        rz = mathutils.Matrix.Rotation(math.radians(90.0 * kdir), 4, "Z")
        root.matrix_world = rz @ base
        upd()
        render_to(os.path.join(folder, "idle_%d_0.png" % kdir), frame)
    write_meta(folder, {"kind": "furniture", "name": spec["name"], "frame": frame, "anchor": anchor, "scale": scale, "directions": 4,
                        "anims": {"idle": {"frames": 1}}, "nominal": spec["nominal"], "h_m": H})
    log("furniture", spec["name"], "done")


def main():
    if ONLY_KIND in ("", "characters"):
        for spec in CFG["characters"]:
            if ONLY_NAME in ("", spec["name"]):
                bake_character(spec)
    if ONLY_KIND in ("", "vehicles"):
        for spec in CFG["vehicles"]["list"]:
            if ONLY_NAME in ("", spec["name"]):
                bake_vehicle(spec, CFG["vehicles"]["scale"])
    if ONLY_KIND in ("", "furniture"):
        for spec in CFG["furniture"]["list"]:
            if ONLY_NAME in ("", spec["name"]):
                bake_furniture(spec, CFG["furniture"]["scale"])
    log("all done")


main()
