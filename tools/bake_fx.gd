extends SceneTree
## P15-FX: 불·연기 그림 굽기. Godot 셰이더(shaders/fx_*.gdshader)를 SubViewport에 그려 프레임을 저장한다.
## 실행 (창이 잠깐 뜬다 — 그리기가 필요해서 headless로는 안 된다):
##   godot --path . -s res://tools/bake_fx.gd
## 결과: art/fx/flame.png (불꽃 애니메이션 VARIANTS줄 × FRAMES칸), art/fx/smoke_noise.png (반복 연기 질감),
##       art/fx/puffs.png (Kenney 연기 덩어리 — 검은 연기·흰 김), art/fx/fx.json (프레임 크기·수)

const OUT := "res://art/fx"
const FLAME_W := 48
const FLAME_H := 96
const FRAMES := 16
const VARIANTS := 3
const NOISE := 256
const PUFF := 96
const PUFF_DIR := "art_source/kenney/smoke-particles/PNG"


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUT))
	# 1) 불꽃: 변형 3가지 × 16프레임 (한 바퀴가 이어진다)
	var sheet := Image.create_empty(FLAME_W * FRAMES, FLAME_H * VARIANTS, false, Image.FORMAT_RGBA8)
	var vp := _viewport(Vector2i(FLAME_W * 2, FLAME_H * 2))
	var rect := _rect(vp, "res://shaders/fx_flame.gdshader")
	for v in VARIANTS:
		rect.material.set_shader_parameter("seed", float(v) * 3.7 + 1.0)
		for f in FRAMES:
			rect.material.set_shader_parameter("phase", float(f) / FRAMES)
			var img := await _grab(vp)
			img.resize(FLAME_W, FLAME_H, Image.INTERPOLATE_LANCZOS)
			sheet.blit_rect(img, Rect2i(0, 0, FLAME_W, FLAME_H), Vector2i(f * FLAME_W, v * FLAME_H))
	sheet.save_png(OUT + "/flame.png")
	vp.queue_free()
	# 2) 연기층 질감 (가로·세로 반복)
	var vp2 := _viewport(Vector2i(NOISE, NOISE))
	_rect(vp2, "res://shaders/fx_smoke_noise.gdshader")
	var noise := await _grab(vp2)
	noise.save_png(OUT + "/smoke_noise.png")
	vp2.queue_free()
	# 3) Kenney 연기 덩어리 (검은 연기 6장, 흰 김 6장)
	var puffs := Image.create_empty(PUFF * 6, PUFF * 2, false, Image.FORMAT_RGBA8)
	for row in 2:
		var folder := "Black smoke" if row == 0 else "White puff"
		var prefix := "blackSmoke" if row == 0 else "whitePuff"
		for k in 6:
			var path := ProjectSettings.globalize_path("res://") + "%s/%s/%s%02d.png" % [PUFF_DIR, folder, prefix, k * 4]
			var img := Image.load_from_file(path)
			if img == null:
				continue
			img.convert(Image.FORMAT_RGBA8)
			img.resize(PUFF, PUFF, Image.INTERPOLATE_LANCZOS)
			puffs.blit_rect(img, Rect2i(0, 0, PUFF, PUFF), Vector2i(k * PUFF, row * PUFF))
	puffs.save_png(OUT + "/puffs.png")
	var meta := {"flame": {"w": FLAME_W, "h": FLAME_H, "frames": FRAMES, "variants": VARIANTS},
		"smoke_noise": {"size": NOISE}, "puffs": {"size": PUFF, "per_row": 6, "rows": ["black", "white"]},
		"source": "불꽃·연기 질감: shaders/fx_*.gdshader로 구움. 연기 덩어리: Kenney Smoke Particles (CC0)"}
	var f := FileAccess.open(OUT + "/fx.json", FileAccess.WRITE)
	f.store_string(JSON.stringify(meta, "  "))
	f.close()
	print("불·연기 그림 저장: ", ProjectSettings.globalize_path(OUT))
	quit()


func _viewport(size: Vector2i) -> SubViewport:
	var vp := SubViewport.new()
	vp.size = size
	vp.transparent_bg = true
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	return vp


func _rect(vp: SubViewport, shader_path: String) -> ColorRect:
	var r := ColorRect.new()
	r.size = Vector2(vp.size)
	var m := ShaderMaterial.new()
	m.shader = load(shader_path)
	r.material = m
	vp.add_child(r)
	return r


func _grab(vp: SubViewport) -> Image:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return vp.get_texture().get_image()
