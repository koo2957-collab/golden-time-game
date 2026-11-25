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
## 물줄기 (사용자 참고 그림, tools/prep_water_fx.py): 직사 줄기·맞은 자리, 분무 원뿔·닿은 자리. 없으면 null
static var water_jet: Texture2D
static var water_splash: Texture2D
static var water_fog: Texture2D
static var water_fog_splash: Texture2D
## Blender로 구운 불꽃 플립북 (tools/blender/fire_fx.py, 장을 세로로 쌓음): {"s" · "m" · "l" · "xl": 그림}. 없는 크기는 빠진다
static var fires: Dictionary = {}
## 롤오버 천장 화염 (tools/blender/fire_fx.py roll · rollc, 2026-11-25): 위에서 본 화염 판(가로·세로 타일) · 잘린 앞면의 화염 띠(가로 타일, 위 = 천장)
static var roll_sheet: Texture2D
static var roll_curtain: Texture2D
## 전실 화재의 화염 벽 (fire_fx.py wall, 2026-11-25): 잘린 앞면에 바닥에서 천장까지 차는 화염 (가로 타일, 위 = 천장)
static var fire_wall: Texture2D
## 개구부(창·문) 밖으로 뿜는 화염을 옆에서 본 그림 (fire_fx.py vent, 2026-11-25): 왼쪽 = 벽, 아래에서 lintel_m = 개구부 윗면
static var fire_vent: Texture2D
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
	water_jet = _tex(DIR + "/water_jet.png")
	water_splash = _tex(DIR + "/water_splash.png")
	water_fog = _tex(DIR + "/water_fog.png")
	water_fog_splash = _tex(DIR + "/water_fog_splash.png")
	fires = {}
	for kind in FireDraw.KINDS:
		var tex := _tex(DIR + "/fire_%s.png" % kind)
		if tex != null:
			fires[kind] = tex
	roll_sheet = _tex(DIR + "/fire_roll.png")
	roll_curtain = _tex(DIR + "/fire_rollc.png")
	fire_wall = _tex(DIR + "/fire_wall.png")
	fire_vent = _tex(DIR + "/fire_vent.png")
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


## 불 한 채 (FireDraw.bodies 의 kind): base = 화면의 불 뿌리, w·h = 불꽃의 화면 폭·높이(px — 그림 위쪽 여백은 빼고 준다).
## seed 로 시작 장과 좌우 뒤집기를 다르게 한다. 그 크기의 그림이 없으면 false (부르는 쪽이 예전 불꽃으로)
static func draw_fire(ci: CanvasItem, kind: String, base: Vector2, w: float, h: float, seed: int, modulate := Color.WHITE) -> bool:
	if not load_all() or not fires.has(kind):
		return false
	var key := "fire_" + kind
	var full := h / maxf(0.2, 1.0 - float(meta.get(key, {}).get("flame_top_v", 0.07)))
	var left := base.x - w * 0.5
	var right := base.x + w * 0.5
	var mirror := posmod(seed, 2) == 1
	return draw_flip(ci, fires[kind], key, PackedVector2Array([Vector2(left, base.y - full), Vector2(right, base.y - full), Vector2(right, base.y), Vector2(left, base.y)]),
		Vector2(1.0 if mirror else 0.0, 0.0), Vector2(0.0 if mirror else 1.0, 1.0), modulate, seed)


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
## rate = 재생 빠르기 배율 (연기 읽기 — 뜨거운 연기는 빠르게, 식은 연기는 느리게, 2026-11-24). 0.1 단위로 끊어 쓴다:
## 장 번호가 (시각 × fps × rate)라서 rate 가 조금씩 계속 바뀌면 장이 튄다 — 단위로 끊으면 단계가 바뀔 때만 한 번 넘어간다
static func draw_flip(ci: CanvasItem, tex: Texture2D, key: String, pts: PackedVector2Array, uv0: Vector2, uv1: Vector2, modulate: Color, seed: int, bottom := 1.0, rate := 1.0) -> bool:
	if tex == null:
		return false
	var m: Dictionary = meta.get(key, {})
	var frames := maxi(1, int(m.get("frames", 24)))
	var r := maxf(0.1, snappedf(rate, 0.1))
	var f := Time.get_ticks_msec() / 1000.0 * float(m.get("fps", 6.0)) * r + float(posmod(seed * 7, frames))
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


## 플립북을 아무 다각형에: uvs = 점마다 한 장 안의 좌표(0~1). 잘라 낸 조각(연기 선두 안쪽)을 그릴 때.
## point_cols = 점마다 색·진하기 (비우면 modulate 하나로) — 가장자리를 흐리게 할 때
static func draw_flip_poly(ci: CanvasItem, tex: Texture2D, key: String, pts: PackedVector2Array, uvs: PackedVector2Array, modulate: Color, seed: int,
		point_cols := PackedColorArray()) -> bool:
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
		if point_cols.size() == pts.size():
			for i in pts.size():
				cols[i] = Color(point_cols[i], point_cols[i].a * float(pair[1]))
		else:
			cols.fill(Color(modulate, modulate.a * float(pair[1])))
		ci.draw_polygon(pts, cols, fu, tex)
	return true


## 물줄기: 관창(from) → 맞는 곳(to), 화면 좌표. straight = 직사(가는 줄기 + 튀는 물), 아니면 분무(원뿔 + 물안개).
## spread_px = 분무가 퍼지는 반지름(화면 px). 그림을 줄기 방향으로 돌려 늘이고, 위아래를 번갈아 뒤집고 길이를 조금씩 바꿔
## 흐르는 것처럼 보이게 한다 (화면 시간). seed 로 조마다 박자를 다르게. 그림이 없으면 false (도형으로)
## arc_px > 0 이면 직사 줄기가 가운데에서 그만큼 위로 휘어 오른다 (위층 창·외벽으로 올려 쏘는 경계 관창, 2026-11-24).
## on_wall = 맞은 곳이 벽면이다 — 튀는 물을 바닥처럼 납작하게 누르지 않는다
static func draw_water(ci: CanvasItem, from: Vector2, to: Vector2, straight: bool, spread_px: float, modulate: Color, seed: int,
		arc_px := 0.0, on_wall := false) -> bool:
	if not load_all():
		return false
	var body := water_jet if straight else water_fog
	var splash := water_splash if straight else water_fog_splash
	if body == null or splash == null:
		return false
	var d := to - from
	var length := d.length()
	if length < 4.0:
		return true
	var t := Time.get_ticks_msec() / 1000.0 + seed * 0.37
	var beat := int(floorf(t * 10.0))
	var ang := d.angle()
	if straight:
		_draw_jet(ci, from, d, body, modulate, t, beat, arc_px)
	var aspect := float(body.get_height()) / float(body.get_width())
	# 줄기: 두 겹 — 한 겹은 위아래를 번갈아 뒤집고, 한 겹은 길이가 출렁인다
	for layer in (0 if straight else 2):
		var flip := -1.0 if (beat + layer) % 2 == 0 else 1.0
		var stretch := 1.0 + (0.06 * sin(t * 9.0 + layer * 1.7) if layer == 1 else 0.0)
		var len_px := length * (1.12 if straight else 1.05) * stretch
		var half := (len_px * aspect * 0.5) if straight else maxf(spread_px, len_px * aspect * 0.5)
		ci.draw_set_transform(from, ang, Vector2(1.0, flip))
		ci.draw_texture_rect(body, Rect2(0.0, -half, len_px, half * 2.0), false, Color(modulate, modulate.a * (0.95 if layer == 0 else 0.5)))
	# 맞은 자리: 바닥에 퍼지므로 납작하게, 크기가 뛰고 좌우를 번갈아 뒤집는다
	var size := clampf(length * 0.4, 30.0, 70.0) if straight else maxf(spread_px * 2.4, 40.0)
	size *= 1.0 + 0.12 * sin(t * 13.0)
	ci.draw_set_transform(to, 0.0, Vector2(-1.0 if beat % 2 == 0 else 1.0, 1.0 if on_wall else 0.62))
	ci.draw_texture_rect(splash, Rect2(-size * 0.5, -size * 0.5, size, size), false, Color(modulate, modulate.a * (0.9 if straight else 0.7)))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	return true


## 직사 물줄기 (2026-11-15 사용자 지적: 관창 입보다 물줄기가 굵게 나왔다 — 그림을 길이에 비례해 통째로 늘렸기 때문).
## 관창 입 지름(mouth_m)에서 시작해 맞는 곳(end_m)까지 조금씩 퍼지는 띠로 그린다. 굵기는 길이와 무관하다.
## 물줄기 그림도 왼쪽(관창)은 가늘고 오른쪽은 굵어, 그 굵기 띠(v 범위)만 잘라 띠에 입힌다. 수치는 data/art.json water_jet
static func _draw_jet(ci: CanvasItem, from: Vector2, d: Vector2, tex: Texture2D, modulate: Color, t: float, beat: int, arc_px := 0.0) -> void:
	var cfg: Dictionary = SpriteArt.config().get("water_jet", {})
	var mouth := float(cfg.get("mouth_m", 0.09)) * IsoProjection.PX_PER_M * 0.5
	var tail := float(cfg.get("end_m", 0.45)) * IsoProjection.PX_PER_M * 0.5
	var v_mid := float(cfg.get("tex_mid_v", 0.485))
	var v_mouth := float(cfg.get("tex_mouth_half_v", 0.075))
	var v_tail := float(cfg.get("tex_end_half_v", 0.46))
	# 휘는 줄기는 마디를 늘려 매끈하게 (그리는 도형 수는 그대로 겹당 하나)
	var steps := 6 if arc_px <= 0.0 else 12
	var along := d.normalized()
	var lift := Vector2(0.0, -arc_px)
	for layer in 2:
		var flip := -1.0 if (beat + layer) % 2 == 0 else 1.0
		# 휘는 줄기는 끝이 겨눈 곳에 꼭 닿게 길이를 흔들지 않는다
		var reach := d.length() * ((1.04 + (0.05 * sin(t * 9.0 + 1.7) if layer == 1 else 0.0)) if arc_px <= 0.0 else 1.0)
		var top := PackedVector2Array()
		var bottom := PackedVector2Array()
		var uv_top := PackedVector2Array()
		var uv_bottom := PackedVector2Array()
		for i in steps + 1:
			var f := float(i) / steps
			var half := lerpf(mouth, tail, pow(f, 0.85))
			var hv := lerpf(v_mouth, v_tail, f)
			# 가운데 선: 곧은 줄 + 가운데에서 arc_px 만큼 솟는 포물선 (양 끝은 그대로)
			var c := from + along * reach * f + lift * 4.0 * f * (1.0 - f)
			var side := (along * reach + lift * 4.0 * (1.0 - 2.0 * f)).normalized().orthogonal()
			top.append(c - side * half)
			bottom.append(c + side * half)
			uv_top.append(Vector2(f, v_mid - hv * flip))
			uv_bottom.append(Vector2(f, v_mid + hv * flip))
		bottom.reverse()
		uv_bottom.reverse()
		top.append_array(bottom)
		uv_top.append_array(uv_bottom)
		var col := Color(modulate, modulate.a * (0.95 if layer == 0 else 0.5))
		var cols := PackedColorArray()
		cols.resize(top.size())
		cols.fill(col)
		ci.draw_polygon(top, cols, uv_top, tex)


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
