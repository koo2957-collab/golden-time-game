# P15-2 대체: 사용자 참고 그림(서울소방 방화복 캐릭터, F:/golden time game/소방관 캐릭터.png)을 따라
# Blender 스크립트로 소방관 3D 모델을 직접 만든다 (TRELLIS·Mixamo 없이).
# - 사람 비율(키 1.75m), 정면 -Y, 위 +Z, 왼쪽 = +X (.L)
# - 뼈대를 만들고 옷·장비 조각을 뼈에 붙인다(단단한 조각 + 관절 구로 틈을 가림) — 게임 그림이 60~100px라 충분하고 가볍다
# - 동작(서기·걷기·웅크려 걷기·들고 걷기·방수·검색·쓰러짐)은 뼈 회전으로 프레임마다 만든다
# - 헬멧(helmet·brim)은 따로 흰색으로 찍어 게임에서 출동대 종류 색을 입힌다 (bake.py TINT_PARTS)
# bake.py가 불러 쓴다: build(colors) → Rig, rig.pose(anim, i, n)

import math

import bpy
import bmesh
import mathutils

V = mathutils.Vector
# 머리·헬멧을 실제보다 조금 키운다: 위에서 내려다보는 작은 그림에서도 헬멧 색이 읽히게 (RTS 관례)
HEAD_S = 1.22


def _hex(h, a=1.0):
    h = h.lstrip("#")
    c = [int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)]
    c = [x / 12.92 if x <= 0.04045 else ((x + 0.055) / 1.055) ** 2.4 for x in c]
    return (c[0], c[1], c[2], a)


def _mat(name, hexc, rough=0.75, metal=0.0, emit=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes.get("Principled BSDF")
    col = _hex(hexc) if isinstance(hexc, str) else hexc
    p.inputs["Base Color"].default_value = col
    p.inputs["Roughness"].default_value = rough
    p.inputs["Metallic"].default_value = metal
    if emit > 0.0:
        p.inputs["Emission Color"].default_value = col
        p.inputs["Emission Strength"].default_value = emit
    return m


# --- 뼈대 ---

# 이름: (머리, 꼬리, 부모) — 쉬는 자세(팔을 조금 벌리고 내린 자세)
BONES = {
    "hips": ((0, 0, 0.92), (0, 0, 1.02), None),
    "spine": ((0, 0, 1.02), (0, 0, 1.22), "hips"),
    "chest": ((0, 0, 1.22), (0, 0, 1.44), "spine"),
    "neck": ((0, 0, 1.44), (0, 0, 1.53), "chest"),
    "head": ((0, 0, 1.53), (0, 0, 1.80), "neck"),
}
for _s, _x in (("L", 1.0), ("R", -1.0)):
    BONES.update({
        "upper_arm." + _s: ((0.2 * _x, 0, 1.41), (0.255 * _x, 0.0, 1.13), "chest"),
        "forearm." + _s: ((0.255 * _x, 0.0, 1.13), (0.28 * _x, -0.025, 0.87), "upper_arm." + _s),
        "hand." + _s: ((0.28 * _x, -0.025, 0.87), (0.29 * _x, -0.035, 0.77), "forearm." + _s),
        "thigh." + _s: ((0.1 * _x, 0, 0.92), (0.1 * _x, 0, 0.5), "hips"),
        "shin." + _s: ((0.1 * _x, 0, 0.5), (0.1 * _x, 0.0, 0.09), "thigh." + _s),
        "foot." + _s: ((0.1 * _x, 0, 0.09), (0.1 * _x, -0.14, 0.03), "shin." + _s),
    })


def _armature():
    data = bpy.data.armatures.new("ff_rig")
    arm = bpy.data.objects.new("rig", data)
    bpy.context.scene.collection.objects.link(arm)
    bpy.context.view_layer.objects.active = arm
    arm.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    for name, (h, t, parent) in BONES.items():
        b = data.edit_bones.new(name)
        b.head = V(h)
        b.tail = V(t)
        b.roll = 0.0
        if parent:
            b.parent = data.edit_bones[parent]
            b.use_connect = False
    bpy.ops.object.mode_set(mode="OBJECT")
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    return arm


# --- 조각 만들기 ---

class Builder:
    def __init__(self, arm, colors):
        self.arm = arm
        self.parts = []
        c = colors
        self.m = {
            "coat": _mat("coat", c["coat"], 0.85),
            "pants": _mat("pants", c.get("pants", c["coat"]), 0.85),
            "hood": _mat("hood", c["hood"], 0.9),
            "reflect": _mat("reflect", c["reflect"], 0.4, 0.0, 0.35),
            "silver": _mat("silver", c.get("silver", "#C8CCCF"), 0.3, 0.3, 0.15),
            "glove": _mat("glove", c["glove"], 0.7),
            "boot": _mat("boot", c["boot"], 0.45),
            "mask": _mat("mask", c["mask"], 0.08, 0.2),
            "rubber": _mat("rubber", c["harness"], 0.6),
            "tank": _mat("tank", c["tank"], 0.35, 0.35),
            "metal": _mat("metal", "#9AA0A6", 0.3, 0.8),
            "gold": _mat("gold", "#D4A72C", 0.35, 0.7),
            "white": _mat("white", "#F2F2F2", 0.6),
            "hose": _mat("hose", "#DCD3AE", 0.75),
            "brass": _mat("brass", "#B08D3C", 0.35, 0.7),
        }
        # 헬멧: 몸 그림에서는 회색, 색 층에서는 흰색 (bake.py set_helmet)
        self.helmet_mat = _mat("helmet", (0.35, 0.35, 0.35, 1.0), 0.3)

    def _finish(self, o, mat, bone, smooth=True):
        o.data.materials.append(mat if not isinstance(mat, str) else self.m[mat])
        if smooth:
            for p in o.data.polygons:
                p.use_smooth = True
        bpy.context.view_layer.update()
        mw = o.matrix_world.copy()
        o.parent = self.arm
        o.parent_type = "BONE"
        o.parent_bone = bone
        bpy.context.view_layer.update()
        o.matrix_world = mw
        self.parts.append(o)
        return o

    def limb(self, name, a, b, r1, r2, mat, bone, verts=14, sx=1.0):
        """a→b 원뿔대 (a 쪽 반지름 r1, b 쪽 r2). sx: 옆 방향 납작함"""
        a, b = V(a), V(b)
        d = b - a
        bpy.ops.mesh.primitive_cone_add(vertices=verts, radius1=r1, radius2=r2, depth=d.length, location=(a + b) / 2)
        o = bpy.context.active_object
        o.name = name
        o.rotation_mode = "QUATERNION"
        o.rotation_quaternion = V((0, 0, 1)).rotation_difference(d.normalized())
        o.scale = (sx, 1.0, 1.0)
        return self._finish(o, mat, bone)

    def ball(self, name, c, r, mat, bone, seg=16):
        bpy.ops.mesh.primitive_uv_sphere_add(segments=seg, ring_count=max(6, seg // 2), radius=1.0, location=V(c))
        o = bpy.context.active_object
        o.name = name
        o.scale = r if isinstance(r, tuple) else (r, r, r)
        return self._finish(o, mat, bone)

    def box(self, name, c, size, mat, bone, rot=(0, 0, 0), bevel=0.0):
        bpy.ops.mesh.primitive_cube_add(size=1.0, location=V(c), rotation=rot)
        o = bpy.context.active_object
        o.name = name
        o.scale = size
        if bevel > 0.0:
            bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
            mod = o.modifiers.new("bevel", "BEVEL")
            mod.width = bevel
            mod.segments = 2
        return self._finish(o, mat, bone, smooth=bevel > 0.0)

    def band(self, name, a, b, f, r, h, mat, bone, sx=1.0):
        """a→b 축의 f(0~1) 위치에 두른 띠 (반지름 r, 두께 h)"""
        a, b = V(a), V(b)
        d = (b - a).normalized()
        c = a.lerp(b, f)
        return self.limb(name, c - d * h / 2, c + d * h / 2, r, r, mat, bone, 16, sx)

    def reflect_band(self, name, a, b, f, r, h, bone, sx=1.0):
        """반사띠: 연두 + 가운데 은색 줄 (참고 그림)"""
        self.band(name, a, b, f, r, h, "reflect", bone, sx)
        self.band(name + "_s", a, b, f, r + 0.002, h * 0.3, "silver", bone, sx)

    def loft(self, name, rings, mat, bone, n=20, y_off=0.0):
        """타원 단면을 위로 쌓은 몸통: rings = [(z, 반폭, 반깊이)]"""
        me = bpy.data.meshes.new(name)
        bm = bmesh.new()
        loops = []
        for z, w, dd in rings:
            loops.append([bm.verts.new((w * math.cos(2 * math.pi * k / n), y_off + dd * math.sin(2 * math.pi * k / n), z)) for k in range(n)])
        for r0, r1 in zip(loops, loops[1:]):
            for k in range(n):
                bm.faces.new((r0[k], r0[(k + 1) % n], r1[(k + 1) % n], r1[k]))
        bm.faces.new(list(reversed(loops[0])))
        bm.faces.new(loops[-1])
        bm.normal_update()
        bm.to_mesh(me)
        bm.free()
        o = bpy.data.objects.new(name, me)
        bpy.context.scene.collection.objects.link(o)
        return self._finish(o, mat, bone)


# 몸통(방화복 상의) 단면: 밑단이 허벅지 중간까지 내려오고 조금 퍼진다
COAT = [(0.66, 0.215, 0.16), (0.8, 0.205, 0.152), (0.95, 0.192, 0.145), (1.12, 0.2, 0.148), (1.3, 0.215, 0.15),
        (1.4, 0.205, 0.135), (1.45, 0.13, 0.1), (1.47, 0.085, 0.085), (1.55, 0.082, 0.082)]


def _coat_at(z):
    for (z0, w0, d0), (z1, w1, d1) in zip(COAT, COAT[1:]):
        if z0 <= z <= z1:
            f = (z - z0) / (z1 - z0)
            return w0 + (w1 - w0) * f, d0 + (d1 - d0) * f
    return COAT[-1][1], COAT[-1][2]


def _head(p):
    """머리 쪽 좌표를 목 위(1.53)를 중심으로 HEAD_S배"""
    base = V((0, 0, 1.53))
    return tuple(base + (V(p) - base) * HEAD_S)


def build_parts(bld):
    b = BONES
    # 상의: 허리 아래(엉덩이)·위(가슴) 두 조각 — 숙일 때 허리에서 접힌다
    lower = [r for r in COAT if r[0] <= 1.12]
    upper = [r for r in COAT if r[0] >= 1.0]
    upper[0] = (1.0,) + _coat_at(1.0)
    bld.loft("coat_lower", lower, "coat", "hips")
    bld.loft("coat_upper", upper, "coat", "chest")
    for name, z, bone in (("band_hem", 0.7, "hips"), ("band_waist", 0.84, "hips"), ("band_chest", 1.27, "chest")):
        w, d = _coat_at(z)
        bld.reflect_band(name, (0, 0, z - 0.02), (0, 0, z + 0.02), 0.5, w + 0.006, 0.045, bone, sx=1.0)
        bld.parts[-1].scale.y = (d + 0.008) / (w + 0.008)
        bld.parts[-2].scale.y = (d + 0.006) / (w + 0.006)
    # 허리 벨트(공기호흡기 허리띠)와 버클
    w, d = _coat_at(0.98)
    bld.band("belt", (0, 0, 0.96), (0, 0, 1.0), 0.5, w + 0.012, 0.05, "rubber", "hips")
    bld.parts[-1].scale.y = (d + 0.012) / (w + 0.012)
    bld.box("buckle", (0, -d - 0.016, 0.98), (0.06, 0.012, 0.045), "metal", "hips")
    # 멜빵 (앞)
    for s, x in (("L", 1), ("R", -1)):
        bld.box("strap_" + s, (0.085 * x, -0.158, 1.2), (0.045, 0.018, 0.42), "rubber", "chest", rot=(math.radians(-4), 0, math.radians(-6 * x)))
        bld.box("strap_top_" + s, (0.1 * x, -0.02, 1.43), (0.05, 0.27, 0.025), "rubber", "chest")
    # 공기호흡기: 검은 등판 + 회녹색 용기(위아래 둥근) + 밸브
    bld.box("harness_plate", (0, 0.165, 1.17), (0.24, 0.04, 0.48), "rubber", "chest", bevel=0.01)
    bld.limb("scba", (0, 0.245, 0.93), (0, 0.245, 1.4), 0.078, 0.078, "tank", "chest")
    bld.ball("scba_top", (0, 0.245, 1.4), 0.078, "tank", "chest")
    bld.ball("scba_bottom", (0, 0.245, 0.93), 0.078, "tank", "chest")
    bld.limb("scba_valve", (0, 0.245, 0.83), (0, 0.245, 0.88), 0.03, 0.03, "rubber", "chest")
    bld.band("scba_strap", (0, 0.245, 1.1), (0, 0.245, 1.14), 0.5, 0.083, 0.035, "rubber", "chest")
    # 목·두건·면체·헬멧 (머리는 HEAD_S배)
    hs = HEAD_S
    bld.ball("hood", _head((0, 0.005, 1.645)), (0.1 * hs, 0.112 * hs, 0.125 * hs), "hood", "head")
    bld.ball("collar", (0, 0, 1.5), (0.095, 0.095, 0.06), "coat", "neck")
    bld.ball("mask", _head((0, -0.06, 1.635)), (0.088 * hs, 0.065 * hs, 0.095 * hs), "mask", "head")
    bld.limb("regulator", _head((0, -0.1, 1.575)), _head((0, -0.145, 1.57)), 0.034 * hs, 0.028 * hs, "rubber", "head")
    bld.ball("helmet", _head((0, 0.012, 1.7)), (0.128 * hs, 0.142 * hs, 0.125 * hs), bld.helmet_mat, "head", seg=24)
    # 헬멧 아래 반쪽은 두건 속으로 (아래쪽 정점을 납작하게)
    hel = bld.parts[-1]
    for v in hel.data.vertices:
        v.co.z = max(v.co.z, -0.12)
    bld.limb("brim", _head((0, 0.03, 1.682)), _head((0, 0.03, 1.69)), 0.152 * hs, 0.15 * hs, bld.helmet_mat, "head", verts=28)
    bld.parts[-1].scale = (1.0, 1.0, 1.0)
    bld.parts[-1].scale.y = 1.2
    bld.band("helmet_band", _head((0, 0.012, 1.7)), _head((0, 0.012, 1.73)), 0.5, 0.129 * hs, 0.026 * hs, "reflect", "head")
    bld.parts[-1].scale.y = 1.1
    for s, x in (("L", 1), ("R", -1)):
        # 팔: 어깨 구·위팔·팔꿈치·아래팔, 반사띠 (위팔 1, 아래팔 2), 장갑
        ua_h, ua_t, _ = b["upper_arm." + s]
        fa_h, fa_t, _ = b["forearm." + s]
        ha_h, ha_t, _ = b["hand." + s]
        bld.ball("shoulder_" + s, ua_h, 0.082, "coat", "upper_arm." + s)
        bld.limb("upper_arm_" + s, ua_h, ua_t, 0.074, 0.062, "coat", "upper_arm." + s)
        bld.reflect_band("band_ua_" + s, ua_h, ua_t, 0.55, 0.071, 0.035, "upper_arm." + s)
        bld.ball("elbow_" + s, ua_t, 0.062, "coat", "forearm." + s)
        bld.limb("forearm_" + s, fa_h, fa_t, 0.062, 0.056, "coat", "forearm." + s)
        bld.reflect_band("band_fa1_" + s, fa_h, fa_t, 0.45, 0.062, 0.035, "forearm." + s)
        bld.reflect_band("band_fa2_" + s, fa_h, fa_t, 0.85, 0.06, 0.035, "forearm." + s)
        bld.limb("cuff_" + s, fa_t, V(fa_t) + (V(ha_t) - V(ha_h)) * 0.35, 0.05, 0.048, "glove", "hand." + s)
        bld.box("glove_" + s, V(ha_h).lerp(V(ha_t), 0.6), (0.038, 0.075, 0.11), "glove", "hand." + s, bevel=0.012)
        bld.box("thumb_" + s, V(ha_h).lerp(V(ha_t), 0.4) + V((-0.012 * x, -0.04, 0)), (0.022, 0.03, 0.05), "glove", "hand." + s, bevel=0.008)
        # 태극기 자리 흰 패치 (왼쪽 위팔 바깥) — 작은 그림이라 흰 점으로만
        if s == "L":
            bld.box("patch", V(ua_h).lerp(V(ua_t), 0.22) + V((0.072, 0, 0)), (0.008, 0.05, 0.035), "white", "upper_arm.L")
        # 다리: 넓은 방화복 바지, 무릎 구, 정강이 반사띠 2줄, 장화
        th_h, th_t, _ = b["thigh." + s]
        sh_h, sh_t, _ = b["shin." + s]
        ft_h, ft_t, _ = b["foot." + s]
        bld.limb("thigh_" + s, th_h, th_t, 0.098, 0.08, "pants", "thigh." + s)
        bld.ball("knee_" + s, th_t, 0.078, "pants", "shin." + s)
        bld.limb("shin_" + s, sh_h, (sh_t[0], sh_t[1], 0.13), 0.076, 0.074, "pants", "shin." + s)
        bld.reflect_band("band_sh1_" + s, sh_h, sh_t, 0.62, 0.079, 0.04, "shin." + s)
        bld.reflect_band("band_sh2_" + s, sh_h, sh_t, 0.76, 0.079, 0.04, "shin." + s)
        bld.limb("boot_shaft_" + s, (sh_t[0], 0.0, 0.02), (sh_t[0], 0.0, 0.17), 0.066, 0.068, "boot", "shin." + s)
        bld.box("boot_" + s, (ft_h[0], -0.045, 0.045), (0.115, 0.27, 0.09), "boot", "foot." + s, bevel=0.03)
        bld.box("sole_" + s, (ft_h[0], -0.045, 0.008), (0.12, 0.28, 0.018), "rubber", "foot." + s)


# 관창 길이 (손끝에서 관창 끝까지, m)
NOZZLE_LEN = 0.36


class Rig:
    def __init__(self, arm, bld):
        self.arm = arm
        self.parts = bld.parts
        self.helmet_mat = bld.helmet_mat
        self._rest = {b.name: b.matrix_local.to_3x3() for b in arm.data.bones}
        # 관창 (방수 때만 보임): 오른손에
        hr = BONES["hand.R"]
        tip = V(hr[1])
        # 관창 (2026-11-12 사용자 지적: 물이 사람 몸이 아니라 관창 끝에서 나가야 한다 — 크고 또렷하게, 뒤로 수관이 이어진다).
        # 손 뼈 방향(쉬는 자세에서 -Z)으로 NOZZLE_LEN 만큼 앞으로 — 방수 자세에서는 앞을 향한다. 끝점은 nozzle_tip()
        xr = 1.0 if tip.x >= 0 else -1.0
        nozzle = bld.limb("nozzle", tip + V((0, 0.0, 0.05)), tip + V((0, 0.0, -NOZZLE_LEN + 0.08)), 0.03, 0.036, "rubber", "hand.R")
        nozzle_tip = bld.limb("nozzle_tip", tip + V((0, 0.0, -NOZZLE_LEN + 0.08)), tip + V((0, 0.0, -NOZZLE_LEN)), 0.04, 0.03, "brass", "hand.R")
        coupling = bld.limb("nozzle_coupling", tip + V((0, 0.0, 0.05)), tip + V((0, 0.0, 0.1)), 0.036, 0.036, "brass", "hand.R")
        grip = bld.box("nozzle_grip", tip + V((0, -0.03, -0.03)), (0.03, 0.05, 0.07), "rubber", "hand.R")
        # 수관: 관창 뒤에서 팔 아래로 (손 뼈에), 허리 옆을 지나 뒤쪽 바닥으로 (골반 뼈에)
        hose_a = bld.limb("hose_a", tip + V((0, 0.0, 0.1)), tip + V((-0.03 * xr, 0.05, 0.5)), 0.03, 0.03, "hose", "hand.R")
        hose_b = bld.limb("hose_b", V((0.2 * xr, 0.02, 0.98)), V((0.24 * xr, 0.42, 0.06)), 0.03, 0.03, "hose", "hips")
        hose_c = bld.limb("hose_c", V((0.24 * xr, 0.42, 0.06)), V((0.12 * xr, 1.0, 0.04)), 0.03, 0.03, "hose", "hips")
        self.nozzle = [nozzle, nozzle_tip, coupling, grip, hose_a, hose_b, hose_c]
        self.parts = [p for p in bld.parts if p not in self.nozzle]

    def reset(self):
        for pb in self.arm.pose.bones:
            pb.rotation_quaternion = (1, 0, 0, 0)
            pb.location = (0, 0, 0)

    def rot(self, name, axis, deg):
        """뼈를 '쉬는 자세의 몸 기준 축'(X: 옆, Y: 앞뒤, Z: 위)으로 돌린다. 여러 번 부르면 차례로 쌓인다"""
        pb = self.arm.pose.bones[name]
        r0 = self._rest[name]
        cur = r0 @ pb.rotation_quaternion.to_matrix() @ r0.inverted()
        q = mathutils.Matrix.Rotation(math.radians(deg), 3, axis) @ cur
        pb.rotation_quaternion = (r0.inverted() @ q @ r0).to_quaternion()

    # 부호 약속: 아래로 뻗은 뼈(다리·팔)는 X축 -각 = 앞으로, 위로 뻗은 뼈(척추·머리)는 +각 = 앞으로 숙임

    def _arms_relaxed(self):
        for s, x in (("L", 1), ("R", -1)):
            self.rot("upper_arm." + s, "Y", -4 * x)

    def _walk(self, t, amp=1.0, arms=True):
        p = 2 * math.pi * t
        for s, ph in (("L", 0.0), ("R", math.pi)):
            a = 24 * amp * math.sin(p + ph)
            knee = 6 + 34 * amp * max(0.0, -math.cos(p + ph))
            self.rot("thigh." + s, "X", a)
            self.rot("shin." + s, "X", knee)
            self.rot("foot." + s, "X", -a * 0.4)
            if arms:
                self.rot("upper_arm." + s, "X", -a * 0.75)
                self.rot("forearm." + s, "X", -12 - 8 * amp * max(0.0, math.sin(p + ph)))
        self.rot("spine", "X", 3)
        self.rot("hips", "Z", 4 * amp * math.sin(p))
        self.rot("chest", "Z", -6 * amp * math.sin(p))

    def pose(self, anim, i, n):
        """동작 anim의 i번째(0~n-1) 프레임 자세. 반환: 눕는 자세인가 (가운데 맞춤)"""
        self.reset()
        for o in self.nozzle:
            o.hide_render = anim != "spray"
        t = i / max(1, n)
        if anim == "idle":
            self._arms_relaxed()
            br = math.sin(2 * math.pi * t)
            self.rot("chest", "X", -1.2 * br)
            self.rot("head", "X", 1.0 * br)
            for s in ("L", "R"):
                self.rot("forearm." + s, "X", -8 - 2 * br)
        elif anim == "walk":
            self._arms_relaxed()
            self._walk(t)
        elif anim == "crouch_walk":
            # 낮은 자세: 엉덩이를 낮추고 허리를 숙여 짧게 걷는다 (연기 속)
            for s in ("L", "R"):
                self.rot("thigh." + s, "X", -38)
                self.rot("shin." + s, "X", 62)
                self.rot("foot." + s, "X", -20)
            self._walk(t, 0.55)
            self.rot("spine", "X", 22)
            self.rot("chest", "X", 12)
            self.rot("head", "X", -22)
            for s, x in (("L", 1), ("R", -1)):
                self.rot("upper_arm." + s, "X", -30)
                self.rot("forearm." + s, "X", -35)
        elif anim == "carry":
            # 요구조자를 앞으로 안고 걷기
            self._walk(t, 0.6, arms=False)
            self.rot("spine", "X", -6)
            for s, x in (("L", 1), ("R", -1)):
                self.rot("upper_arm." + s, "X", -55)
                self.rot("upper_arm." + s, "Z", -12 * x)
                self.rot("forearm." + s, "X", -55)
        elif anim == "spray":
            # 방수: 다리를 앞뒤로 벌린 낮은 자세, 두 손으로 관창을 앞으로. 반동으로 조금 흔들린다
            sh = math.sin(2 * math.pi * t)
            self.rot("thigh.L", "X", -32)
            self.rot("shin.L", "X", 34)
            self.rot("foot.L", "X", -2)
            self.rot("thigh.R", "X", 18)
            self.rot("shin.R", "X", 22)
            self.rot("foot.R", "X", -40)
            self.rot("spine", "X", 14)
            self.rot("chest", "X", 4 + 1.5 * sh)
            self.rot("head", "X", -12)
            self.rot("upper_arm.R", "X", -62 + 2 * sh)
            self.rot("upper_arm.R", "Z", 14)
            self.rot("forearm.R", "X", -28)
            self.rot("hand.R", "X", 10)
            self.rot("upper_arm.L", "X", -58 + 2 * sh)
            self.rot("upper_arm.L", "Z", -26)
            self.rot("forearm.L", "X", -42)
        elif anim == "search":
            # 무릎 꿇고 검색: 오른 무릎을 바닥에, 오른손으로 바닥을 좌우로 더듬는다
            sw = math.sin(2 * math.pi * t)
            self.rot("thigh.R", "X", -8)
            self.rot("shin.R", "X", 100)
            self.rot("foot.R", "X", 30)
            self.rot("thigh.L", "X", -78)
            self.rot("shin.L", "X", 82)
            self.rot("spine", "X", 30)
            self.rot("chest", "X", 15)
            self.rot("head", "X", -20)
            self.rot("upper_arm.R", "X", -55)
            self.rot("upper_arm.R", "Z", 18 * sw)
            self.rot("forearm.R", "X", -8)
            self.rot("upper_arm.L", "X", -40)
            self.rot("forearm.L", "X", -50)
        elif anim == "down":
            # 쓰러짐: 엎드림 (앞이 바닥으로), 고개를 옆으로
            self.rot("hips", "X", 90)
            self.rot("head", "Y", 35)
            self.rot("upper_arm.L", "Y", -20)
            self.rot("upper_arm.R", "Y", 25)
            self.rot("upper_arm.R", "X", -30)
            self.rot("forearm.R", "X", -40)
            self.rot("thigh.L", "Y", -6)
            self.rot("thigh.R", "X", -18)
            self.rot("shin.R", "X", 30)
            return True
        return False

    def nozzle_tip(self):
        """관창 끝의 월드 좌표 (지금 자세). 물줄기가 시작되는 점 — 굽기에서 화면 위치로 바꿔 기록한다"""
        bpy.context.view_layer.update()
        pb = self.arm.pose.bones["hand.R"]
        axis = (pb.tail - pb.head).normalized()
        return self.arm.matrix_world @ (pb.tail + axis * NOZZLE_LEN)

    def bounds(self):
        """보이는 조각들의 월드 경계 (최소, 최대)"""
        bpy.context.view_layer.update()
        lo = V((1e9, 1e9, 1e9))
        hi = V((-1e9, -1e9, -1e9))
        for o in self.parts + [p for p in self.nozzle if not p.hide_render]:
            for c in o.bound_box:
                w = o.matrix_world @ V(c)
                lo = V((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
                hi = V((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
        return lo, hi


def build(colors):
    arm = _armature()
    bld = Builder(arm, colors)
    build_parts(bld)
    return Rig(arm, bld)
