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
	return flame != null


static func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
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
