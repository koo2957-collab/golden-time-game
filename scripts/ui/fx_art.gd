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
## 연기층 앞면 커튼 플립북 (tools/blender/smoke_fx.py로 구움). 없으면 null
static var curtain: Texture2D
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
## 위 = 천장, meta body_v 높이가 연기층 아랫면. 이웃한 두 장을 겹쳐 부드럽게 재생한다. 그림이 없으면 false
static func draw_curtain(ci: CanvasItem, top_a: Vector2, top_b: Vector2, bot_b: Vector2, bot_a: Vector2, u0: float, u1: float, modulate: Color, seed: int) -> bool:
	if not load_all() or curtain == null:
		return false
	var m: Dictionary = meta.get("smoke_curtain", {})
	var frames := int(m.get("frames", 24))
	var f := Time.get_ticks_msec() / 1000.0 * float(m.get("fps", 6.0)) + float(posmod(seed * 7, frames))
	var f0 := posmod(int(floorf(f)), frames)
	var w := f - floorf(f)
	var inset := 0.5 / float(curtain.get_height())
	var pts := PackedVector2Array([top_a, top_b, bot_b, bot_a])
	for pair: Array in [[f0, 1.0], [(f0 + 1) % frames, w]]:
		var v0 := float(pair[0]) / frames + inset
		var v1 := (float(pair[0]) + 1.0) / frames - inset
		var c := Color(modulate, modulate.a * float(pair[1]))
		ci.draw_polygon(pts, PackedColorArray([c, c, c, c]), PackedVector2Array([Vector2(u0, v0), Vector2(u1, v0), Vector2(u1, v1), Vector2(u0, v1)]), curtain)
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
