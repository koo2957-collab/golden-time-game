# 호스 끼고 걷기·정리하며 따라가기 장면 만들기 (docs/motions.md E2·A6·E3, 2026-11-21)
#   실행: blender -b --factory-startup tools/blender/scenes/driver_hose_walk.blend -P tools/blender/build_hose_carry.py
#   결과: tools/blender/scenes/hose_carry.blend (운전원이 아코디언 호스를 메고 걷는 장면을 고쳐 만든다 — 걷기 동작을 그대로 쓴다)
# 사용자(현직 소방관) 설명 2026-11-16: 진압대원은 위로 쌓은 아코디언 호스를 겨드랑이에 끼고 간다.
#   1번(관창수) = 1본쯤, 뒤로 호스가 바닥에 풀려 나간다 / 2번(관창보조) = 2본쯤 / 3번 = 뒤따르며 깔린 호스의 꼬임을 푼다
# 모델은 -Y를 보고 선다. 모델의 오른쪽 = -X.
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "scenes", "hose_carry.blend")

# 진압대원 차림으로 보일 조각 (search_pair 장면의 대원과 같게 — 도구는 뺀다)
CREW = """badge band_chest band_chest_s band_fa1_L band_fa1_L_s band_fa1_R band_fa1_R_s band_fa2_L band_fa2_L_s band_fa2_R band_fa2_R_s
band_sh1_L band_sh1_L_s band_sh1_R band_sh1_R_s band_sh2_L band_sh2_L_s band_sh2_R band_sh2_R_s band_ua_L band_ua_L_s band_ua_R band_ua_R_s
belt boot_L boot_R boot_shaft_L boot_shaft_R brim buckle coat_skirt coat_upper collar cuff_L cuff_R elbow_L elbow_R forearm_L forearm_R
glove_L glove_R harness_plate helmet helmet_band helmet_crest hood knee_L knee_R mask patch regulator scba scba_bottom scba_strap scba_top
scba_valve shin_L shin_R shoulder_L shoulder_R sole_L sole_R strap_L strap_R strap_top_L strap_top_R thigh_L thigh_R thumb_L thumb_R
upper_arm_L upper_arm_R""".split()

# 호스 (겨드랑이 아래 묶음, 몸 오른쪽): 띠 폭·두께·겹 사이 간격·앞뒤 끝 (m). 실제 40mm 호스(접힌 폭 6.3cm)를 그림에서 보이게 키웠다.
# 묶음·사람 사이·늘어진 곳·들어 올린 곳·바닥이 모두 같은 폭·두께다 — 한 줄로 이어져 보이게 (2026-11-21 사용자: 끊겨 보이지 않게)
BAND_W = 0.13
BAND_T = 0.018
GROUND = BAND_T * 0.5  # 바닥에 놓인 호스의 가운데 높이
PITCH = 0.027
BUNDLE_X = -0.275
BUNDLE_Y0 = -0.30
BUNDLE_Y1 = 0.36
BUNDLE_TOP = 1.215
LAYERS = {"FF_A": 4, "FF_B": 7}
# 뒷사람 자리 (앞사람 뒤로 m)
BEHIND = {"FF_B": 1.1, "FF_C": 3.6}

sc = bpy.context.scene


def base(name):
    return name.split(".")[0]


def parts(rig):
    out, todo = [], [rig]
    while todo:
        cur = todo.pop()
        for o in bpy.data.objects:
            if o.parent == cur:
                out.append(o)
                todo.append(o)
    return out


def upd():
    bpy.context.view_layer.update()


def dress(rig):
    """진압대원 차림: 정해 둔 조각만 보이고 나머지(운전원 옷·얼굴·도구·예전 호스)는 숨긴다"""
    for o in parts(rig):
        if o.type in ("MESH", "CURVE"):
            show = base(o.name) in CREW
            o.hide_render = not show
            o.hide_viewport = not show


def aim(rig, bone, target):
    """뼈가 target(세계 좌표)을 향하게 돌린다 (뼈 머리는 그대로)"""
    upd()
    pb = rig.pose.bones[bone]
    head = pb.head.copy()
    cur = (pb.tail - pb.head).normalized()
    want = ((rig.matrix_world.inverted() @ Vector(target)) - head).normalized()
    q = cur.rotation_difference(want)
    pb.matrix = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head) @ pb.matrix
    upd()


def key_all(rig, bones, first, last):
    for f in range(first, last + 1):
        for b in bones:
            rig.pose.bones[b].keyframe_insert("rotation_quaternion", frame=f)


def ribbon(name, path, width, thick, mat, xs=None):
    """YZ 평면의 길(path: [(y, z)])을 따라가는 납작한 띠 (폭은 X 방향). 원점 기준 세계 좌표로 만든다"""
    bm = bmesh.new()
    rings = []
    n = len(path)
    for k in range(n):
        a = Vector(path[max(k - 1, 0)])
        b = Vector(path[min(k + 1, n - 1)])
        t = (b - a).normalized() if (b - a).length > 1e-6 else Vector((1, 0))
        nrm = Vector((-t.y, t.x))
        p = Vector(path[k])
        ring = []
        for sx, sn in ((-1, -1), (1, -1), (1, 1), (-1, 1)):
            q = p + nrm * (sn * thick * 0.5)
            ring.append(bm.verts.new((sx * width * 0.5 + (xs[k] if xs else 0.0), q.x, q.y)))
        rings.append(ring)
    for k in range(n - 1):
        for i in range(4):
            j = (i + 1) % 4
            bm.faces.new((rings[k][i], rings[k][j], rings[k + 1][j], rings[k + 1][i]))
    bm.faces.new(rings[0][::-1])
    bm.faces.new(rings[-1])
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces[:])
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    me.materials.append(mat)
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    return ob


def smooth(path, sub=5):
    """점 사이를 부드럽게 잇는다 (Catmull-Rom) — 꺾인 자국 없이 휘는 호스"""
    pts = [Vector(p) for p in path]
    out = []
    n = len(pts)
    for k in range(n - 1):
        p0 = pts[max(k - 1, 0)]
        p1 = pts[k]
        p2 = pts[k + 1]
        p3 = pts[min(k + 2, n - 1)]
        for s in range(sub):
            t = s / sub
            q = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t * t + (-p0 + 3 * p1 - 3 * p2 + p3) * t * t * t)
            out.append(tuple(q))
    out.append(tuple(pts[-1]))
    return out


def hose_part(name, path, owner=None):
    """호스 한 조각 (세계 좌표의 길: [(y, z)] 또는 [(y, z, x)]) — x가 없으면 몸 오른쪽 줄(BUNDLE_X)에 놓는다.
    바닥에 닿는 곳은 x = 0 (대원이 걷는 길 한가운데 — 게임이 그리는 바닥 호스가 지나는 곳)으로 온다.
    owner(사람)가 있으면 그 사람에 매단다 (그 사람과 같이 굽는다)"""
    xs = [(p[2] if len(p) > 2 else BUNDLE_X) for p in path]
    ob = ribbon(name, [(p[0], max(p[1], GROUND)) for p in path], BAND_W, BAND_T, hose_mat, xs)
    if owner is not None:
        upd()
        ob.parent = owner
        ob.matrix_parent_inverse = owner.matrix_world.inverted()
    return ob


def bundle_path(layers):
    """위에서 아래로 겹겹이 접힌 길: 맨 위 겹은 앞→뒤, 다음 겹은 뒤→앞 … 겹 끝은 반원으로 돌아 내려간다. 맨 아래 겹은 뒤에서 끝난다"""
    pts = []
    # 맨 아래 겹이 뒤(+Y)에서 끝나도록 첫 방향을 정한다
    forward_back = layers % 2 == 1
    for i in range(layers):
        z = BUNDLE_TOP - i * PITCH
        y_from, y_to = (BUNDLE_Y0, BUNDLE_Y1) if forward_back else (BUNDLE_Y1, BUNDLE_Y0)
        steps = 6
        for s in range(steps + 1):
            pts.append((y_from + (y_to - y_from) * s / steps, z))
        if i < layers - 1:
            # 반원으로 돌아 아래 겹으로
            out = 1.0 if y_to > y_from else -1.0
            for s in range(1, 6):
                ang = math.pi * s / 6.0
                pts.append((y_to + out * math.sin(ang) * PITCH * 0.5, z - PITCH * 0.5 + math.cos(ang) * PITCH * 0.5))
        forward_back = not forward_back
    return pts


def bone_parent(ob, rig, bone, offset=Vector((0, 0, 0))):
    """세계 좌표로 만든 물체를 지금 자리 그대로 뼈에 매단다 (offset: 그 사람의 자리만큼 옮긴 뒤)"""
    upd()
    pb = rig.pose.bones[bone]
    ob.parent = rig
    ob.parent_type = "BONE"
    ob.parent_bone = bone
    bone_world = rig.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0))
    ob.matrix_parent_inverse = bone_world.inverted()
    ob.matrix_basis = Matrix.Translation(offset)


# ── 0) 장면: 1·2번의 걷기는 8장 한 주기, 3번의 낮은 자세 걷기는 16장 한 주기 (16장 동안 1·2번은 두 번 걷는다)
sc.frame_start = 1
sc.frame_end = 16
sc.frame_set(1)
ff_a = bpy.data.objects["FF_A"]
walk = ff_a.animation_data.action
hose_mat = bpy.data.materials.get("hose")

# ── 1) 1번(관창수) FF_A: 대원 차림, 오른팔로 묶음을 겨드랑이에 낀다
dress(ff_a)
for b in ("forearm.L", "forearm.R", "hand.R", "hand.L"):
    for c in ff_a.pose.bones[b].constraints:
        c.mute = True
upd()
# 위팔은 옆으로 조금 벌려 내리고(묶음 바깥), 아래팔은 묶음 바깥면을 따라 앞으로, 손은 앞 끝 아래를 받친다
ELBOW = (-0.373, -0.046, 1.21)
HAND = (-0.33, -0.29, 1.10)
aim(ff_a, "upper_arm.R", ELBOW)
aim(ff_a, "forearm.R", HAND)
aim(ff_a, "hand.R", (HAND[0] + 0.06, HAND[1] - 0.07, HAND[2] - 0.03))
key_all(ff_a, ("upper_arm.R", "forearm.R", "hand.R"), 1, 33)

# ── 2) 2번(관창보조) FF_B: 같은 걷기, 앞사람 뒤 1.1m
roots = {}
for name, back in BEHIND.items():
    rig = bpy.data.objects[name]
    root = bpy.data.objects.new("hc_root_" + name[-1], None)
    root.empty_display_size = 0.2
    sc.collection.objects.link(root)
    root.location = (0.0, back, 0.0)
    roots[name] = root
    rig.parent = root
    rig.matrix_parent_inverse = Matrix.Identity(4)
    rig.location = (0.0, 0.0, 0.032)
    rig.rotation_euler = (0.0, 0.0, 0.0)
    dress(rig)
    for pb in rig.pose.bones:
        for c in pb.constraints:
            c.mute = True
ff_b = bpy.data.objects["FF_B"]
if ff_b.animation_data is None:
    ff_b.animation_data_create()
ff_b.animation_data.action = walk
try:
    ff_b.animation_data.action_slot = ff_a.animation_data.action_slot
except Exception as e:
    print("slot:", e)
upd()

# ── 3) 호스 묶음 (접힌 띠) — 1번은 4겹(1본쯤), 2번은 7겹(2본쯤). 1번 묶음은 2번 묶음으로 이어지고 바닥으로는 2번에서 떨어진다
sc.frame_set(1)
upd()
paths = {}
for name, layers in LAYERS.items():
    rig = bpy.data.objects[name]
    off = Vector((0.0, BEHIND.get(name, 0.0), 0.0))
    path = bundle_path(layers)
    ob = ribbon("hc_bundle_" + name[-1], path, BAND_W, BAND_T, hose_mat, [BUNDLE_X] * len(path))
    bone_parent(ob, rig, "chest", off)
    paths[name] = [(y + off.y, z) for y, z in path]
# 호스는 한 줄로 이어진다 (2026-11-21 사용자): 1번 묶음의 뒤 끝 → 2번 묶음의 앞 끝, 바닥으로는 2번 묶음에서 떨어진다.
# 조각마다 앞 조각 쪽으로 조금 겹치고, 겹과 같은 방향(수평)으로 나가고 들어와 이음매가 보이지 않는다
pa = paths["FF_A"]
pb_path = paths["FF_B"]
ya, za = pa[-1]
yb, zb = pb_path[0]
link = [pa[-3], pa[-2]]
for s in range(15):
    u = s / 14.0
    ease = u * u * (3.0 - 2.0 * u)
    link.append((ya + (yb - ya) * u, za + (zb - za) * ease - 0.07 * math.sin(math.pi * u) ** 2))
link += [pb_path[1], pb_path[2]]
hose_part("hc_link_A", link, ff_a)
# 2번 맨 아래 겹의 뒤 끝에서 늘어져 바닥에 닿고 뒤로 끌린다 (그 뒤는 게임이 바닥 호스를 그린다)
# 내려오면서 몸 오른쪽(묶음)에서 길 한가운데(x = 0)로 온다 — 게임이 그리는 바닥 호스가 거기를 지난다
y, z = pb_path[-1]
BX = BUNDLE_X
drop = smooth([pb_path[-3] + (BX,), pb_path[-2] + (BX,), (y, z, BX), (y + 0.06, z - 0.015, BX), (y + 0.11, z - 0.09, BX * 0.95),
    (y + 0.14, z - 0.28, BX * 0.8), (y + 0.15, 0.62, BX * 0.6), (y + 0.16, 0.34, BX * 0.35), (y + 0.19, 0.14, BX * 0.15),
    (y + 0.27, 0.045, BX * 0.05), (y + 0.42, GROUND, 0.0), (y + 0.52, GROUND, 0.0), (y + 0.62, GROUND, 0.0)])
# (그림 한 장의 폭이 사람에서 좌우 1.08m까지라 바닥에 끌리는 부분은 2번 뒤 1m 안에서 끝낸다 — 그 뒤는 게임이 그린다)
hose_part("hc_drop_B", drop, ff_b)

# ── 3-2) 3번(관창보조2) FF_C: 낮은 자세로 걸으며 깔린 호스를 오른손으로 들어 꼬임을 편다 (E3)
#   낮은 자세 걷기는 인명검색 장면(search_pair, A7)의 조장 동작을 가져와 쓴다 (16장). 허리를 더 숙이고 팔만 새로 잡는다
ff_c = bpy.data.objects["FF_C"]
CROUCH_ACTION = "FF_AAction.107"
with bpy.data.libraries.load(os.path.join(HERE, "scenes", "search_pair.blend")) as (src, dst):
    if CROUCH_ACTION not in src.actions:
        raise RuntimeError("search_pair.blend에 낮은 자세 걷기 동작 %s 가 없다: %s" % (CROUCH_ACTION, list(src.actions)[:20]))
    dst.actions = [CROUCH_ACTION]
crouch = dst.actions[0]
crouch.name = "hc_tidy_walk"
if ff_c.animation_data is None:
    ff_c.animation_data_create()
ff_c.animation_data.action = crouch
try:
    ff_c.animation_data.action_slot = crouch.slots[0]
except Exception as e:
    print("slot C:", e)
TIDY_FRAMES = 16
c_at = Vector((0.0, BEHIND["FF_C"], 0.0))
for f in range(1, TIDY_FRAMES + 2):
    sc.frame_set(f)
    upd()
    ph = 2.0 * math.pi * (f - 1) / TIDY_FRAMES
    # 허리를 더 숙인다 (뼈의 +X 회전 = 앞으로 숙임)
    for bone, extra in (("spine", 0.42), ("chest", 0.18), ("head", -0.30)):
        pb = ff_c.pose.bones[bone]
        pb.rotation_quaternion = pb.rotation_quaternion @ Matrix.Rotation(extra, 4, "X").to_quaternion()
    upd()
    # 오른손: 몸 오른쪽 바닥의 호스를 들어 올려 앞뒤로 훑는다 (한 주기에 두 번)
    hand_r = c_at + Vector((BUNDLE_X, -0.47 + 0.08 * math.sin(2.0 * ph), 0.36 + 0.03 * math.cos(2.0 * ph)))
    sh = ff_c.matrix_world @ ff_c.pose.bones["upper_arm.R"].head
    elbow_r = (sh + hand_r) * 0.5 + Vector((-0.10, 0.10, 0.06))
    aim(ff_c, "upper_arm.R", elbow_r)
    aim(ff_c, "forearm.R", hand_r)
    aim(ff_c, "hand.R", hand_r + Vector((0.0, -0.05, -0.08)))
    # 왼손: 왼 무릎 위를 짚는다
    knee_l = ff_c.matrix_world @ ff_c.pose.bones["thigh.L"].tail
    hand_l = knee_l + Vector((0.04, -0.02, 0.10))
    shl = ff_c.matrix_world @ ff_c.pose.bones["upper_arm.L"].head
    aim(ff_c, "upper_arm.L", (shl + hand_l) * 0.5 + Vector((0.12, 0.08, 0.02)))
    aim(ff_c, "forearm.L", hand_l)
    for b in ("spine", "chest", "head", "upper_arm.R", "forearm.R", "hand.R", "upper_arm.L", "forearm.L"):
        ff_c.pose.bones[b].keyframe_insert("rotation_quaternion", frame=f)
sc.frame_set(1)
upd()
# 3번이 들어 올린 호스: 앞 바닥에서 손까지 부드럽게 올라왔다가 뒤 바닥으로 내려간다.
# 들어 올린 곳 아래에는 바닥 호스가 없다 — 같은 호스 한 줄이다 (2026-11-21 사용자: 위아래 두 장으로 보이지 않게). 양 끝은 바닥에 붙어 앞뒤 호스와 겹친다
yc = BEHIND["FF_C"]
# (그림 한 장의 폭 때문에 3번 앞뒤 1m 안에서 바닥에 닿는다 — 그 밖은 게임이 그린다)
# 바닥에서는 길 한가운데(x = 0)에 있고, 오른손(몸 오른쪽)으로 들어 올린 곳만 옆으로 온다
lift = smooth([(yc - 1.02, GROUND, 0.0), (yc - 0.94, GROUND, 0.0), (yc - 0.84, 0.04, BX * 0.1), (yc - 0.72, 0.14, BX * 0.4), (yc - 0.58, 0.27, BX * 0.85),
    (yc - 0.47, 0.32, BX), (yc - 0.32, 0.28, BX * 0.9), (yc - 0.08, 0.17, BX * 0.6), (yc + 0.25, 0.07, BX * 0.3), (yc + 0.58, 0.02, BX * 0.08),
    (yc + 0.86, GROUND, 0.0), (yc + 1.00, GROUND, 0.0)])
hose_part("hc_lift_C", lift, ff_c)

# ── 4) 예전 호스·운전원 소품: 어깨에 멘 아코디언(hdrag_)은 보이기 상태가 동작으로 켜지므로 지우고, 나머지는 숨긴다
for o in list(bpy.data.objects):
    if o.name.startswith("hdrag_"):
        bpy.data.objects.remove(o, do_unlink=True)
    elif o.name.startswith(("hyd_", "hroll_", "hcon_")):
        o.hide_render = True
        o.hide_viewport = True

# ── 5) 미리보기용 바닥 호스 (굽지 않는다 — 사람에 붙지 않음): 3번이 들어 올린 호스가 바닥에 닿은 뒤쪽으로 이어진다.
#   2번의 호스가 닿은 곳과 3번이 들어 올린 곳 사이는 두 사람의 조각이 바닥에서 겹쳐 이어진다
hose_part("ctx_ground_hose", [(yc + 0.86, GROUND, 0.0), (yc + 1.6, GROUND, 0.0), (yc + 2.4, GROUND, 0.0), (yc + 3.4, GROUND, 0.0)])
hose_part("ctx_ground_mid", [(BEHIND["FF_B"] + BUNDLE_Y1 + 0.42, GROUND, 0.0), (yc - 0.94, GROUND, 0.0)])

# 블렌더에서 열었을 때도 굽는 것과 같게 보이도록 화면 숨김을 맞춘다 (눈 모양 숨김은 보기 층에 따로 저장된다)
for o in bpy.data.objects:
    if o.type in ("MESH", "CURVE"):
        o.hide_viewport = o.hide_render
        try:
            o.hide_set(o.hide_render)
        except RuntimeError:
            pass

bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("HOSE_CARRY_SAVED", OUT)
