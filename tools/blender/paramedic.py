# 구급대원 모델 (2026-11-15, 사용자 참고 그림 F:/golden time game/구급대원 이미지.jpg):
# 주황 긴팔 상의 + 검정 조끼(앞에 빨간 파우치 두 개) + 남색 하의 + 검정 신발, 흰 헬멧. 공기호흡기·면체·두건 없음.
# 둘 중 한 명은 주황 구급가방을 든다 (사용자) — 가방 조각(bag_*)은 그 대원 그림에서만 보인다.
# 뼈대·동작(Rig.pose)은 firefighter_v2와 같다 — 옷 조각만 다르다. bake.py가 build(colors)로 부른다.
import math

import firefighter_v2 as ff
from firefighter_v2 import BONES, HEAD_S, V, _head

# 상의(주황)·조끼(검정) 몸통 단면 (z, 반폭, 반깊이) — 방화복보다 날씬하다
SHIRT = [(0.9, 0.172, 0.122), (1.0, 0.168, 0.12), (1.12, 0.176, 0.126), (1.3, 0.19, 0.132), (1.4, 0.182, 0.122),
         (1.45, 0.12, 0.09), (1.47, 0.07, 0.07), (1.53, 0.066, 0.066)]
VEST = [(0.98, 0.184, 0.134), (1.12, 0.19, 0.14), (1.3, 0.203, 0.145), (1.41, 0.17, 0.122)]
PANTS_HIP = [(0.84, 0.165, 0.118), (0.92, 0.172, 0.122), (1.0, 0.17, 0.12)]


def _at(table, z):
    for (z0, w0, d0), (z1, w1, d1) in zip(table, table[1:]):
        if z0 <= z <= z1:
            f = (z - z0) / (z1 - z0)
            return w0 + (w1 - w0) * f, d0 + (d1 - d0) * f
    return table[-1][1], table[-1][2]


def build_parts(bld):
    b = BONES
    m = bld.m
    # 몸통: 골반(남색 바지 허리 + 주황 상의 밑단) · 가슴(주황 상의 + 검정 조끼)
    bld.loft("pants_hip", PANTS_HIP, "pants", "hips")
    bld.loft("shirt_lower", [r for r in SHIRT if r[0] <= 1.0] + [(1.04,) + _at(SHIRT, 1.04)], "coat", "hips")
    bld.loft("shirt_upper", [(1.0,) + _at(SHIRT, 1.0)] + [r for r in SHIRT if r[0] > 1.0], "coat", "chest")
    bld.loft("vest", VEST, "rubber", "chest")
    # 조끼 어깨끈 (앞뒤로 넘어가는 띠)
    for s, x in (("L", 1), ("R", -1)):
        bld.box("vest_strap_" + s, (0.1 * x, 0.0, 1.425), (0.07, 0.26, 0.03), "rubber", "chest")
    # 조끼 앞: 빨간 파우치 두 개(흰 사선 무늬 대신 흰 띠)
    w, d = _at(VEST, 1.08)
    for s, x in (("L", 1), ("R", -1)):
        bld.box("pouch_" + s, (0.095 * x, -d - 0.035, 1.08), (0.12, 0.07, 0.11), "red", "chest", bevel=0.012)
        bld.box("pouch_mark_" + s, (0.095 * x, -d - 0.071, 1.1), (0.1, 0.004, 0.018), "white", "chest")
    # 가슴 패치는 없다 (2026-11-15 사용자: 가슴의 국기 삭제)
    # 목·머리 (얼굴이 보인다): 살색 머리 + 검은 머리카락 + 흰 헬멧(헬멧 색은 게임에서 출동대 종류 색으로)
    hs = HEAD_S
    bld.limb("neck_skin", (0, 0, 1.46), (0, 0, 1.56), 0.05, 0.05, "skin", "neck")
    bld.ball("head_skin", _head((0, -0.005, 1.64)), (0.088 * hs, 0.1 * hs, 0.112 * hs), "skin", "head")
    bld.ball("hair", _head((0, 0.012, 1.665)), (0.091 * hs, 0.1 * hs, 0.1 * hs), "hair", "head")
    hair = bld.parts[-1]
    for v in hair.data.vertices:
        # 앞쪽(얼굴) 아래 절반은 머리카락이 없다
        if v.co.y < -0.3 and v.co.z < 0.4:
            v.co.z = max(v.co.z, 0.4)
    for s, x in (("L", 1), ("R", -1)):
        bld.ball("ear_" + s, _head((0.088 * x, 0.005, 1.635)), (0.014, 0.022, 0.03), "skin", "head")
    # 헬멧: 안전모(작은 반구 + 앞 챙). 이름은 대원 헬멧과 같게 — bake.py가 흰색으로 따로 찍어 종류 색을 입힌다
    bld.ball("helmet", _head((0, 0.008, 1.705)), (0.112 * hs, 0.128 * hs, 0.095 * hs), bld.helmet_mat, "head", seg=24)
    hel = bld.parts[-1]
    for v in hel.data.vertices:
        v.co.z = max(v.co.z, -0.05)
    bld.box("brim", _head((0, -0.12, 1.7)), (0.16 * hs, 0.06 * hs, 0.012), bld.helmet_mat, "head", bevel=0.005)
    bld.box("helmet_crest", _head((0, 0.008, 1.795)), (0.02 * hs, 0.2 * hs, 0.018 * hs), bld.helmet_mat, "head", bevel=0.006)
    for s, x in (("L", 1), ("R", -1)):
        ua_h, ua_t, _ = b["upper_arm." + s]
        fa_h, fa_t, _ = b["forearm." + s]
        ha_h, ha_t, _ = b["hand." + s]
        # 팔: 주황 긴팔, 손목에 검은 소매 끝, 맨손(살색)
        bld.ball("shoulder_" + s, ua_h, 0.066, "coat", "upper_arm." + s)
        bld.limb("upper_arm_" + s, ua_h, ua_t, 0.06, 0.051, "coat", "upper_arm." + s)
        bld.ball("elbow_" + s, ua_t, 0.05, "coat", "forearm." + s)
        bld.limb("forearm_" + s, fa_h, fa_t, 0.05, 0.043, "coat", "forearm." + s)
        bld.band("cuff_" + s, fa_h, fa_t, 0.93, 0.045, 0.035, "rubber", "forearm." + s)
        bld.box("glove_" + s, V(ha_h).lerp(V(ha_t), 0.55), (0.034, 0.07, 0.1), "skin", "hand." + s, bevel=0.012)
        bld.box("thumb_" + s, V(ha_h).lerp(V(ha_t), 0.4) + V((-0.012 * x, -0.035, 0)), (0.02, 0.028, 0.045), "skin", "hand." + s, bevel=0.008)
        if s == "L":
            # 태극기 자리 흰 패치 (왼쪽 위팔 바깥)
            bld.box("arm_patch", V(ua_h).lerp(V(ua_t), 0.22) + V((0.058, 0, 0)), (0.008, 0.045, 0.032), "white", "upper_arm.L")
        # 다리: 남색 바지, 검정 신발
        th_h, th_t, _ = b["thigh." + s]
        sh_h, sh_t, _ = b["shin." + s]
        ft_h, ft_t, _ = b["foot." + s]
        bld.limb("thigh_" + s, th_h, th_t, 0.08, 0.064, "pants", "thigh." + s)
        bld.ball("knee_" + s, th_t, 0.062, "pants", "shin." + s)
        bld.limb("shin_" + s, sh_h, (sh_t[0], sh_t[1], 0.1), 0.06, 0.05, "pants", "shin." + s)
        bld.limb("boot_shaft_" + s, (sh_t[0], 0.0, 0.03), (sh_t[0], 0.0, 0.12), 0.05, 0.052, "boot", "shin." + s)
        bld.box("boot_" + s, (ft_h[0], -0.04, 0.04), (0.1, 0.25, 0.08), "boot", "foot." + s, bevel=0.025)
        bld.box("sole_" + s, (ft_h[0], -0.04, 0.008), (0.105, 0.26, 0.016), "rubber", "foot." + s)


def bag_parts(bld):
    """주황 구급가방 (오른손에 든다): 손 아래로 매달린 상자 + 손잡이 + 반사띠 + 흰 십자 대신 흰 띠. bag_* 이름"""
    ha_h, ha_t, _ = BONES["hand.R"]
    tip = V(ha_t)
    start = len(bld.parts)
    # 손 뼈는 쉬는 자세에서 아래(-Z)를 향한다: 가방은 손 아래에 몸 옆으로 길게
    c = tip + V((-0.04, 0.0, -0.17))
    bld.box("bag_body", c, (0.13, 0.4, 0.26), "bag", "hand.R", bevel=0.025)
    bld.box("bag_band", c + V((0, 0, 0.02)), (0.135, 0.405, 0.04), "reflect", "hand.R")
    bld.box("bag_cross_h", c + V((-0.068, 0, -0.05)), (0.004, 0.11, 0.03), "white", "hand.R")
    bld.box("bag_cross_v", c + V((-0.068, 0, -0.05)), (0.004, 0.03, 0.11), "white", "hand.R")
    bld.limb("bag_handle", tip + V((-0.02, 0.0, -0.01)), tip + V((-0.03, 0.0, 0.03)), 0.012, 0.012, "rubber", "hand.R")
    return bld.parts[start:]


class EmsRig(ff.Rig):
    """대원 자세를 그대로 쓰고, '_bag'으로 끝나는 동작(idle_bag·walk_bag)은 오른손에 구급가방을 들고 팔을 거의 편다"""

    def pose(self, anim, i, n):
        bag = anim.endswith("_bag")
        lie = super().pose(anim[:-4] if bag else anim, i, n)
        for o in self.bag:
            o.hide_render = not bag
        if bag:
            # 가방 든 팔은 흔들지 않고 조금 바깥으로 (가방이 다리에 닿지 않게)
            for b in ("upper_arm.R", "forearm.R", "hand.R"):
                self.arm.pose.bones[b].rotation_quaternion = (1, 0, 0, 0)
            self.rot("upper_arm.R", "Y", 6)
        return lie

    def bounds(self):
        lo, hi = super().bounds()
        for o in [p for p in self.bag if not p.hide_render]:
            for c in o.bound_box:
                w = o.matrix_world @ V(c)
                lo = V((min(lo.x, w.x), min(lo.y, w.y), min(lo.z, w.z)))
                hi = V((max(hi.x, w.x), max(hi.y, w.y), max(hi.z, w.z)))
        return lo, hi


def build(colors):
    arm = ff._armature()
    bld = ff.Builder(arm, colors)
    bld.m["skin"] = ff._mat("skin", colors.get("skin", "#E0AC84"), 0.7)
    bld.m["hair"] = ff._mat("hair", colors.get("hair", "#1E1A18"), 0.8)
    bld.m["bag"] = ff._mat("bag", colors.get("bag", "#F06A1A"), 0.6)
    build_parts(bld)
    bag = bag_parts(bld)
    rig = EmsRig(arm, bld)
    rig.bag = bag
    rig.parts = [p for p in rig.parts if p not in bag]
    for o in bag:
        o.hide_render = True
    return rig
