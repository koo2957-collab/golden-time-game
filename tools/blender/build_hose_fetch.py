# 펌프차 후면에서 호스 꺼내기 장면 만들기 (docs/motions.md E1, 2026-11-22)
#   실행: blender -b --factory-startup tools/blender/scenes/hose_carry.blend -P tools/blender/build_hose_fetch.py
#   결과: tools/blender/scenes/hose_fetch.blend (호스 끼고 걷기 장면의 대원 차림을 그대로 쓴다)
# 1번(관창수)·2번(관창보조)이 차 후면(열린 셔터)을 보고 나란히 서서, 접어 쌓은(아코디언) 호스를 두 손으로 잡아 몸 쪽으로 당겨 꺼내기를 되풀이한다.
# 차는 보기용(굽지 않는다) — 게임에서는 차 그림 위에 열린 셔터를 덧그린다. 모델은 -Y를 보고 선다 (차 후면이 -Y 쪽에 있다).
import bpy, bmesh, math, os
from mathutils import Vector, Matrix

HERE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(HERE, "scenes", "hose_fetch.blend")
FRAMES = 12
# 차 후면까지 거리 (m) — 게임에서도 1번은 차 후면에서 이만큼 떨어져 선다 (data/ui/hose_style.json fetch_stand_m)
REAR_Y = -0.75
# 2번은 1번의 왼쪽 옆 (m)
SIDE = 0.72
BAND_W = 0.13
BAND_T = 0.018
PITCH = 0.027

sc = bpy.context.scene


def upd():
    bpy.context.view_layer.update()


def parts(rig):
    out, todo = [], [rig]
    while todo:
        cur = todo.pop()
        for o in bpy.data.objects:
            if o.parent == cur:
                out.append(o)
                todo.append(o)
    return out


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


def box(name, lo, hi, color, parent=None):
    """세계 좌표의 상자 (보기용 소품·꺼내는 호스 뭉치)"""
    bm = bmesh.new()
    bmesh.ops.create_cube(bm, size=1.0)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    ob = bpy.data.objects.new(name, me)
    sc.collection.objects.link(ob)
    lo, hi = Vector(lo), Vector(hi)
    ob.scale = hi - lo
    ob.location = (lo + hi) * 0.5
    mat = bpy.data.materials.get(color) if isinstance(color, str) else None
    if mat is None:
        mat = bpy.data.materials.new(name + "_mat")
        mat.use_nodes = True
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        if bsdf is not None:
            bsdf.inputs["Base Color"].default_value = (*color, 1.0)
            bsdf.inputs["Roughness"].default_value = 0.8
    me.materials.append(mat)
    if parent is not None:
        upd()
        ob.parent = parent
        ob.matrix_parent_inverse = parent.matrix_world.inverted()
    return ob


# ── 0) 호스 끼고 걷기 장면에서 필요 없는 것(묶음·이어진 호스·관창·3번)은 지우거나 숨긴다
for o in list(bpy.data.objects):
    if o.name.startswith(("hc_bundle_", "hc_link_", "hc_drop_", "hc_lift_", "ctx_", "hc_nozzle_mount")):
        if o.name == "hc_nozzle_mount":
            for ch in list(o.children):
                ch.hide_render = True
                ch.hide_viewport = True
        bpy.data.objects.remove(o, do_unlink=True)
ff_a = bpy.data.objects["FF_A"]
ff_b = bpy.data.objects["FF_B"]
ff_c = bpy.data.objects["FF_C"]
for o in parts(ff_c):
    if o.type in ("MESH", "CURVE"):
        o.hide_render = True
        o.hide_viewport = True
sc.frame_start = 1
sc.frame_end = FRAMES

# ── 1) 서는 자리: 1번은 원점, 2번은 왼쪽 옆 (둘 다 차 후면을 본다)
root_b = bpy.data.objects.get("hc_root_B")
root_b.location = (SIDE, 0.0, 0.0)
upd()

# ── 2) 동작: 두 손으로 호스를 잡아(차 안쪽으로 손을 뻗음) 몸 쪽으로 당기기를 되풀이. 2번은 반 박자 늦게
hose_mat = bpy.data.materials.get("hose")
for rig, phase, side_x in ((ff_a, 0.0, 0.0), (ff_b, 0.5, SIDE)):
    act = bpy.data.actions.new("hc_fetch_" + rig.name[-1].lower())
    if rig.animation_data is None:
        rig.animation_data_create()
    rig.animation_data.action = act
    # 호스 뭉치: 두 손 사이에 든 접힌 호스 세 겹 — 손(오른손 뼈)을 따라 움직인다
    chunk = None
    for f in range(1, FRAMES + 2):
        sc.frame_set(f)
        u = ((f - 1) / FRAMES + phase) % 1.0
        reach = 0.5 * (1.0 - math.cos(2.0 * math.pi * u))  # 0 = 몸 쪽으로 당김, 1 = 차 안으로 뻗음
        for pb in rig.pose.bones:
            pb.rotation_quaternion = (1.0, 0.0, 0.0, 0.0)
            pb.location = (0.0, 0.0, 0.0)
        rig.location = (0.0, 0.0, 0.032 - 0.03 * reach)
        upd()
        # 다리는 어깨너비보다 조금 넓게 버티고 무릎을 조금 굽힌다, 허리는 뻗을 때 더 숙인다 (뼈의 +X 회전 = 앞으로 숙임)
        for bone, ang in (("spine", 0.10 + 0.22 * reach), ("chest", 0.06 + 0.10 * reach), ("head", -0.05 - 0.10 * reach),
                          ("thigh.L", -0.12), ("thigh.R", -0.12), ("shin.L", 0.20), ("shin.R", 0.20)):
            rig.pose.bones[bone].rotation_quaternion = Matrix.Rotation(ang, 4, "X").to_quaternion()
        upd()
        hand_y = -0.36 - 0.24 * reach
        hand_z = 1.16 + 0.04 * reach
        for s, x in ((".R", -0.17), (".L", 0.17)):
            hand = Vector((side_x + x, hand_y, hand_z))
            sh = rig.matrix_world @ rig.pose.bones["upper_arm" + s].head
            elbow = (sh + hand) * 0.5 + Vector((x * 0.9, 0.10, -0.12))
            aim(rig, "upper_arm" + s, elbow)
            aim(rig, "forearm" + s, hand)
            aim(rig, "hand" + s, hand + Vector((-x * 0.3, -0.08, 0.0)))
        for pb in rig.pose.bones:
            pb.keyframe_insert("rotation_quaternion", frame=f)
        rig.keyframe_insert("location", frame=f)
        if chunk is None:
            # 첫 장의 손 자리 기준으로 뭉치를 만들어 오른손 뼈에 매단다 (손을 따라 들락날락한다)
            upd()
            lo = Vector((side_x - 0.20, hand_y - 0.30, hand_z - 0.035))
            chunk = []
            for i in range(3):
                z0 = lo.z + i * PITCH
                c = box("hf_chunk_%s_%d" % (rig.name[-1], i), (lo.x, lo.y, z0), (lo.x + 0.40, lo.y + 0.42, z0 + BAND_T), "hose")
                pb = rig.pose.bones["hand.R"]
                c.parent = rig
                c.parent_type = "BONE"
                c.parent_bone = "hand.R"
                c.matrix_parent_inverse = (rig.matrix_world @ pb.matrix @ Matrix.Translation((0, pb.bone.length, 0))).inverted()
                chunk.append(c)
sc.frame_set(1)
upd()

# ── 3) 보기용 차 후면 (굽지 않는다): 몸통, 열린 셔터 안(어두운 칸), 접어 쌓은 호스, 동작 패널
box("ctx_truck", (-1.25, REAR_Y - 2.6, 0.45), (1.25 + SIDE, REAR_Y, 2.9), (0.80, 0.16, 0.10))
box("ctx_open", (-1.05, REAR_Y - 0.02, 0.85), (1.05 + SIDE, REAR_Y + 0.01, 2.05), (0.05, 0.05, 0.06))
for i in range(7):
    box("ctx_stack_%d" % i, (-0.95, REAR_Y - 0.01, 0.95 + i * 0.07), (0.55 + SIDE, REAR_Y + 0.02, 1.00 + i * 0.07), "hose")
box("ctx_panel", (0.65 + SIDE, REAR_Y - 0.01, 1.0), (1.0 + SIDE, REAR_Y + 0.02, 1.6), (0.45, 0.47, 0.50))
box("ctx_shutter", (-1.05, REAR_Y - 0.02, 2.05), (1.05 + SIDE, REAR_Y + 0.04, 2.2), (0.62, 0.64, 0.66))

for o in bpy.data.objects:
    if o.type in ("MESH", "CURVE"):
        o.hide_viewport = o.hide_render
        try:
            o.hide_set(o.hide_render)
        except RuntimeError:
            pass

bpy.ops.wm.save_as_mainfile(filepath=OUT)
print("HOSE_FETCH_SAVED", OUT)
