class_name FxArt
extends RefCounted
## 불·연기 그림 (P15-FX). tools/bake_fx.gd가 Godot 셰이더로 구운 art/fx/*.png를 불러 그린다.
## 그림이 없으면 null → 부르는 쪽은 예전 도형으로 그린다. 시간은 화면 시간(Time)으로 흐른다 (시뮬레이션과 무관한 연출).

const DIR := "res://art/fx"
const FLAME_FPS := 14.0

static var _loaded := false
static var flame: Texture2D
static var noise: Texture2D
static var puffs: Texture2D
## Blender로 구운 연기 플립북 (tools/blender/smoke_fx.py, 장을 세로로 쌓음). 없으면 null
## 연기층 앞면 커튼
static var curtain: Texture2D
## 연기층 윗면 (가로·세로 타일)
static var sheet: Texture2D
## 불에서 솟아 천장에 퍼지는 기둥
static var plume: Texture2D
## 개구부 윗부분으로 흘러나와 말려 오르는 연기
static var spill: Texture2D
static var meta: Dictionary = {}


static func load_all() -> bool:
	if _loaded:
		return flame != null
	_loaded = true
	var m: Variant = JsonData.load_file(DIR + "/fx.json")
	meta = m if m is Dictionary else {}
	flame = _tex(DIR + "/flame.png")
	noise = _tex(DIR + "/smoke_noise.png")
	puffs = _tex(DIR + "/puffs.png")
	curtain = _tex(DIR + "/smoke_curtain.png")
	sheet = _tex(DIR + "/smoke_sheet.png")
	plume = _tex(DIR + "/smoke_plume.png")
	spill = _tex(DIR + "/smoke_spill.png")
	return flame != null


static func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	if not FileAccess.file_exists(path):
		return null
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(img) if img else null


## 불꽃 한 칸: base = 화면의 불 뿌리, w·h = 화면 크기(px), seed로 변형·위상을 다르게
static func draw_flame(ci: CanvasItem, base: Vector2, w: float, h: float, seed: int, modulate := Color.WHITE) -> bool:
	if not load_all():
		return false
	var f: Dictionary = meta.get("flame", {"w": 48, "h": 96, "frames": 16, "variants": 3})
	var frames := int(f.frames)
	var variant := posmod(seed, int(f.variants))
	var frame := int(floor(Time.get_ticks_msec() / 1000.0 * FLAME_FPS + float(posmod(seed * 7, frames)))) % frames
	var src := Rect2(frame * float(f.w), variant * float(f.h), float(f.w), float(f.h))
	ci.draw_texture_rect_region(flame, Rect2(base - Vector2(w * 0.5, h * 0.96), Vector2(w, h)), src, modulate)
	return true


## 덩어리 그림 종류 (art/fx/puffs.png 줄 순서)
const PUFF_BLACK := 0
const PUFF_WHITE := 1
const PUFF_FIRE := 2
const PUFF_FLASH := 3


## 연기층 앞면 커튼 (Blender 플립북). 화면 네 점: 위a·위b·아래b·아래a, u0~u1 = 가로 한 장 안의 범위(0~1).
## 위 = 천장, meta body_v 높이가 연기층 아랫면. 그림이 없으면 false
## bottom: 아래 두 점 진하기 배율 (천장이 가장 진하고 아래로 갈수록 옅게)
static func draw_curtain(ci: CanvasItem, top_a: Vector2, top_b: Vector2, bot_b: Vector2, bot_a: Vector2, u0: float, u1: float, modulate: Color, seed: int, bottom := 1.0) -> bool:
	if not load_all():
		return false
	return draw_flip(ci, curtain, "smoke_curtain", PackedVector2Array([top_a, top_b, bot_b, bot_a]), Vector2(u0, 0.0), Vector2(u1, 1.0), modulate, seed, bottom)


## 플립북 한 조각: tex = 장을 세로로 쌓은 그림, key = fx.json 이름(장 수·속도).
## 화면 네 점(pts) ↔ 한 장 안의 uv 사각형 (uv0.x,uv0.y)·(uv1.x,uv0.y)·(uv1.x,uv1.y)·(uv0.x,uv1.y).
## 이웃한 두 장을 겹쳐 부드럽게 재생하고, seed로 시작 장을 다르게 한다. bottom = 뒤 두 점(아래쪽) 진하기 배율. 그림이 없으면 false
static func draw_flip(ci: CanvasItem, tex: Texture2D, key: String, pts: PackedVector2Array, uv0: Vector2, uv1: Vector2, modulate: Color, seed: int, bottom := 1.0) -> bool:
	if tex == null:
		return false
	var m: Dictionary = meta.get(key, {})
	var frames := maxi(1, int(m.get("frames", 24)))
	var f := Time.get_ticks_msec() / 1000.0 * float(m.get("fps", 6.0)) + float(posmod(seed * 7, frames))
	var f0 := posmod(int(floorf(f)), frames)
	var w := f - floorf(f)
	var inset := 0.5 / float(tex.get_height())
	var span := 1.0 / frames
	for pair: Array in [[f0, 1.0], [(f0 + 1) % frames, w]]:
		var base := float(pair[0]) * span
		var va := clampf(base + uv0.y * span, base + inset, base + span - inset)
		var vb := clampf(base + uv1.y * span, base + inset, base + span - inset)
		var c := Color(modulate, modulate.a * float(pair[1]))
		var cb := Color(c, c.a * bottom)
		ci.draw_polygon(pts, PackedColorArray([c, c, cb, cb]), PackedVector2Array([Vector2(uv0.x, va), Vector2(uv1.x, va), Vector2(uv1.x, vb), Vector2(uv0.x, vb)]), tex)
	return true


## 그림의 평균 불투명도 (fx.json mean_alpha, 없으면 기본값)
static func mean_alpha(key: String, fallback: float) -> float:
	return clampf(float(meta.get(key, {}).get("mean_alpha", fallback)), 0.05, 1.0)


## 플립북을 아무 다각형에: uvs = 점마다 한 장 안의 좌표(0~1). 잘라 낸 조각(연기 선두 안쪽)을 그릴 때
static func draw_flip_poly(ci: CanvasItem, tex: Texture2D, key: String, pts: PackedVector2Array, uvs: PackedVector2Array, modulate: Color, seed: int) -> bool:
	if tex == null or pts.size() < 3:
		return false
	var m: Dictionary = meta.get(key, {})
	var frames := maxi(1, int(m.get("frames", 24)))
	var f := Time.get_ticks_msec() / 1000.0 * float(m.get("fps", 6.0)) + float(posmod(seed * 7, frames))
	var f0 := posmod(int(floorf(f)), frames)
	var w := f - floorf(f)
	var inset := 0.5 / float(tex.get_height())
	var span := 1.0 / frames
	var cols := PackedColorArray()
	cols.resize(pts.size())
	for pair: Array in [[f0, 1.0], [(f0 + 1) % frames, w]]:
		var base := float(pair[0]) * span
		var fu := PackedVector2Array()
		for uv in uvs:
			fu.append(Vector2(uv.x, clampf(base + uv.y * span, base + inset, base + span - inset)))
		cols.fill(Color(modulate, modulate.a * float(pair[1])))
		ci.draw_polygon(pts, cols, fu, tex)
	return true


## 덩어리 그림을 아무 직사각형에 (납작하게 눌러 그릴 때). 구워져 있지 않으면 false
static func draw_puff_rect(ci: CanvasItem, rect: Rect2, kind: int, k: int, modulate: Color) -> bool:
	if not load_all() or puffs == null:
		return false
	var p := float(meta.get("puffs", {}).get("size", 96))
	var per_row := int(meta.get("puffs", {}).get("per_row", 6))
	ci.draw_texture_rect_region(puffs, rect, Rect2(posmod(k, per_row) * p, kind * p, p, p), modulate)
	return true


## 덩어리 그림 (PUFF_* 종류). k: 0~5 모양. 그 종류가 구워져 있지 않으면 false
static func draw_puff(ci: CanvasItem, center: Vector2, size: float, kind: int, k: int, modulate: Color) -> bool:
	if not load_all() or puffs == null:
		return false
	var p := float(meta.get("puffs", {}).get("size", 96))
	var rows: int = (meta.get("puffs", {}).get("rows", ["black", "white"]) as Array).size()
	if kind < 0 or kind >= rows:
		return false
	var src := Rect2(posmod(k, 6) * p, kind * p, p, p)
	ci.draw_texture_rect_region(puffs, Rect2(center - Vector2(size, size) * 0.5, Vector2(size, size)), src, modulate)
	return true
