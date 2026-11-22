# 열려 있는 블렌더에 검토용 장면을 띄운다 (사용자가 보면서 확인 — 블렌더 MCP 연결을 끊지 않으려고 파일을 여는 대신 장면만 가져온다)
#   블렌더 안에서 실행: SHOW_PATH(장면 파일), SHOW_FOCUS(화면 가운데에 둘 물체 이름들), SHOW_FRAMES(끝 장)를 정한 뒤 exec
import bpy

path = globals().get("SHOW_PATH", r"c:\GOLDEN TIME GAME\tools\blender\scenes\hose_carry.blend")
focus = globals().get("SHOW_FOCUS", ["FF_A", "FF_B", "FF_C"])
last = int(globals().get("SHOW_FRAMES", 16))
NAME = "review"

win = bpy.context.window_manager.windows[0]
old = bpy.data.scenes.get(NAME)
if old is not None:
    if win.scene == old:
        others = [s for s in bpy.data.scenes if s != old]
        if others:
            win.scene = others[0]
    for o in list(old.objects):
        if o is not None:
            bpy.data.objects.remove(o, do_unlink=True)
    bpy.data.scenes.remove(old)
    bpy.data.orphans_purge(do_recursive=True)
with bpy.data.libraries.load(path, link=False) as (src, dst):
    dst.scenes = list(src.scenes)[:1]
sc = dst.scenes[0]
sc.name = NAME
win.scene = sc
sc.frame_start = 1
sc.frame_end = last
sc.frame_set(1)
vl = sc.view_layers[0]
objs = [o for o in sc.objects if o is not None]
for o in objs:
    # 굽지 않는 것(숨긴 소품·다른 장면의 사람)과 손 목표점은 화면에서도 숨긴다
    hidden = o.hide_render or o.type in ("EMPTY", "CAMERA", "LIGHT")
    o.hide_viewport = hidden
    try:
        # 눈 모양 숨김(보기 층마다 따로 저장됨)도 같이 맞춘다 — 원래 장면에서 꺼 둔 옷·사람이 그대로 꺼져 있다
        o.hide_set(hidden, view_layer=vl)
        o.select_set(False, view_layer=vl)
    except RuntimeError:
        pass
for name in focus:
    o = sc.objects.get(name)
    if o is not None:
        o.hide_viewport = False
        o.hide_set(False, view_layer=vl)
        o.select_set(True, view_layer=vl)
# 가벼운 화면(솔리드)에서도 색이 보이게: 재질의 기본 색을 화면 표시 색으로 옮긴다 (이 블렌더 안에서만 — 장면 파일은 그대로)
for m in bpy.data.materials:
    if m.use_nodes and m.node_tree:
        for node in m.node_tree.nodes:
            if node.type == "BSDF_PRINCIPLED":
                base = node.inputs.get("Base Color")
                if base is not None and not base.is_linked:
                    m.diffuse_color = base.default_value
                break
shown = 0
for area in win.screen.areas:
    if area.type != "VIEW_3D":
        continue
    sp = area.spaces.active
    sp.shading.type = "SOLID"
    sp.shading.color_type = "MATERIAL"
    sp.shading.light = "STUDIO"
    sp.overlay.show_bones = False
    region = next(r for r in area.regions if r.type == "WINDOW")
    with bpy.context.temp_override(window=win, screen=win.screen, area=area, region=region, scene=sc, view_layer=vl):
        bpy.ops.view3d.view_selected()
        if not win.screen.is_animation_playing:
            bpy.ops.screen.animation_play()
    shown += 1
for name in focus:
    o = sc.objects.get(name)
    if o is not None:
        o.select_set(False, view_layer=vl)
print("SHOWN scene=%s objects=%d views=%d frames=1-%d" % (sc.name, len(objs), shown, last))
