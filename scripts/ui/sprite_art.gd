class_name SpriteArt
extends RefCounted
## 구운 그림(P15) 불러오기·그리기. 연결은 data/art.json, 아틀라스는 res://art/sprites (tools/import_sprites.gd).
## 그림이 없으면 null을 돌려주고, 부르는 쪽은 지금처럼 도형으로 그린다.
## 방향: 칸 좌표 각도 45° 단위 (0 = +x 화면 오른쪽 아래, 2 = +y 왼쪽 아래 …). 가구는 4방향(앞이 0 +y, 1 -x, 2 -y, 3 +x)

const ART_PATH := "res://data/art.json"

static var _config: Dictionary = {}
static var _loaded := false
static var _sets: Dictionary = {}  # id -> SpriteSet (없으면 null)


class SpriteSet:
	extends RefCounted
	var id := ""
	var scale := 1.0
	var directions := 8
	var pages: Array[Texture2D] = []
	var anims: Dictionary = {}
	var meta: Dictionary = {}

	func has(anim: String) -> bool:
		return anims.has(anim)

	func frames(anim: String) -> int:
		return int(anims[anim].frames) if anims.has(anim) else 0

	## feet: 그림 기준점(발밑·차체 가운데)이 올 화면 좌표. size: 추가 배율(가구 늘리기 등).
	## helmet: 대원 헬멧 색 — 흰 헬멧만 따로 구운 층(묶음의 stripe 칸)에 곱해 덧그린다. 알파 0이면 몸 그림의 회색 헬멧 그대로
	func draw(ci: CanvasItem, anim: String, dir: int, frame: int, feet: Vector2, modulate := Color.WHITE,
			helmet := Color(0, 0, 0, 0), size := 1.0) -> bool:
		var a: Dictionary = anims.get(anim, {})
		if a.is_empty():
			return false
		var n := maxi(1, int(a.frames))
		var key := "%d_%d" % [posmod(dir, directions), posmod(frame, n)]
		var cell: Array = a.cells.get(key, [])
		if cell.is_empty():
			return false
		var k := size / scale
		_blit(ci, cell, feet, k, modulate)
		if helmet.a > 0.0:
			var sc: Array = a.stripe.get(key, [])
			if not sc.is_empty():
				_blit(ci, sc, feet, k, Color(helmet, helmet.a * modulate.a))
		return true

	func _blit(ci: CanvasItem, cell: Array, feet: Vector2, k: float, modulate: Color) -> void:
		var tex := pages[int(cell[0])]
		var src := Rect2(float(cell[1]), float(cell[2]), float(cell[3]), float(cell[4]))
		var dst := Rect2(feet + Vector2(float(cell[5]), float(cell[6])) * k, src.size * k)
		ci.draw_texture_rect_region(tex, dst, src, modulate)


static func config() -> Dictionary:
	if not _loaded:
		_loaded = true
		var d: Variant = JsonData.load_file(ART_PATH)
		_config = d if d is Dictionary else {}
	return _config


static func enabled() -> bool:
	return bool(config().get("enabled", false))


## 묶음 (없으면 null)
static func get_set(id: String) -> SpriteSet:
	if id == "" or not enabled():
		return null
	if _sets.has(id):
		return _sets[id]
	var s := _load(id)
	_sets[id] = s
	return s


static func _load(id: String) -> SpriteSet:
	var dir := str(config().get("dir", "res://art/sprites"))
	var path := "%s/%s.json" % [dir, id]
	if not FileAccess.file_exists(path):
		return null
	var meta: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not meta is Dictionary:
		return null
	var s := SpriteSet.new()
	s.id = id
	s.meta = meta
	s.scale = float(meta.get("scale", 1.0))
	s.directions = int(meta.get("directions", 8))
	s.anims = meta.get("anims", {})
	for p: String in meta.get("pages", []):
		var tex: Texture2D = null
		if ResourceLoader.exists(p):
			tex = load(p)
		else:
			# 아직 Godot이 가져오지 않은 그림 (새로 구운 직후 등)
			var img := Image.load_from_file(ProjectSettings.globalize_path(p))
			if img:
				tex = ImageTexture.create_from_image(img)
		if tex == null:
			return null
		s.pages.append(tex)
	return s


## 칸 좌표 방향 → 8방향 번호
static func dir8(v: Vector2) -> int:
	return posmod(roundi(atan2(v.y, v.x) / (PI / 4.0)), 8)


## 동작 프레임 (화면 시간 기준, 동작마다 fps)
static func frame_at(anim: String, frames: int, phase := 0.0) -> int:
	if frames <= 1:
		return 0
	var fps := float(config().get("fps", {}).get(anim, 6.0))
	return int(floor(Time.get_ticks_msec() / 1000.0 * fps + phase)) % frames


static func vehicle_set(type: String) -> SpriteSet:
	return get_set(str(config().get("vehicles", {}).get(type, "")))


static func furniture_set(name: String) -> SpriteSet:
	var f: Dictionary = config().get("furniture", {})
	var names: Dictionary = f.get("names", {})
	if names.has(name):
		return get_set(str(names[name]))
	for kw: Array in f.get("keywords", []):
		if name.contains(str(kw[0])):
			return get_set(str(kw[1]))
	return null


static func victim_set(label: String) -> SpriteSet:
	var v: Dictionary = config().get("victims", {})
	for w: String in v.get("female_words", []):
		if label.contains(w):
			return get_set(str(v.get("female", "")))
	return get_set(str(v.get("male", "")))


## 헬멧 색: 출동대 종류(진압대·구조대·구급대 …)로만 정한다 (data/art.json helmet_color, 없으면 default)
static func helmet_color(squad_type: String) -> Color:
	var c: Dictionary = config().get("helmet_color", {})
	return Color(str(c.get(squad_type, c.get("default", "#3A3A3E"))))
