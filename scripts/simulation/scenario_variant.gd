class_name ScenarioVariant
extends RefCounted
## 시나리오 변형 (기획안 P9 "발화 세대 번호와 요구조자 배치는 시드로 무작위"):
## 시나리오 파일의 {F}·{F+1}·{F-1} 토큰을 발화층 숫자로 바꿔 읽는다.
##   "level": "{F+1}"  → 숫자 (따옴표째 바뀜)
##   "{F}01호 거실", "{F}F_01_room1" → 글 안의 숫자
## 발화층은 variation.fire_floor {base, min, max}: 시드가 있으면 min~max에서 시드로 고르고, 없으면 base.
## 요구조자 방 후보(victims[].rooms)는 RescueSystem이 같은 시드로 고른다.

const TOKEN := "\\{F([+-]\\d+)?\\}"


## 파일을 읽어 토큰을 푼 시나리오. seed < 0이면 기본 발화층(base)
static func read(path: String, seed := -1) -> Variant:
	if not FileAccess.file_exists(path):
		return JsonData.load_file(path)
	var text := FileAccess.get_file_as_string(path)
	if not text.contains("{F"):
		return JsonData.load_file(path)
	var probe := JSON.new()
	var floor := 0
	# 토큰이 따옴표 안에 있으므로 그대로도 JSON으로 읽힌다 — 먼저 variation만 본다
	if probe.parse(text) == OK and probe.data is Dictionary:
		floor = fire_floor(probe.data, seed)
	return _parse(path, resolve(text, floor))


## 메뉴 설명용: 숫자 대신 ○ (판마다 발화층이 바뀌므로)
static func read_display(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		return JsonData.load_file(path)
	var text := FileAccess.get_file_as_string(path)
	if not text.contains("{F"):
		return JsonData.load_file(path)
	var probe := JSON.new()
	if probe.parse(text) != OK or not probe.data is Dictionary:
		return JsonData.load_file(path)
	var rnd := _range(probe.data)
	if rnd.x == rnd.y:
		return _parse(path, resolve(text, rnd.x))
	var re := RegEx.create_from_string("\"" + TOKEN + "\"")
	text = re.sub(text, "0", true)
	re = RegEx.create_from_string(TOKEN)
	return _parse(path, re.sub(text, "○", true))


## 이 시드의 발화층
static func fire_floor(data: Dictionary, seed: int) -> int:
	var ff: Dictionary = data.get("variation", {}).get("fire_floor", {})
	var base := int(ff.get("base", 1))
	if seed < 0 or not bool(data.get("variation", {}).get("random_seed", false)):
		return base
	var r := _range(data)
	var rng := RandomNumberGenerator.new()
	rng.seed = hash("fire_floor:%d" % seed)
	return rng.randi_range(r.x, r.y)


static func _range(data: Dictionary) -> Vector2i:
	var ff: Dictionary = data.get("variation", {}).get("fire_floor", {})
	var base := int(ff.get("base", 1))
	return Vector2i(int(ff.get("min", base)), int(ff.get("max", base)))


## 토큰 풀기: 따옴표째인 토큰은 숫자로, 글 안의 토큰은 숫자 글자로
static func resolve(text: String, floor: int) -> String:
	var out := text
	for quoted in [true, false]:
		var re := RegEx.create_from_string(("\"" + TOKEN + "\"") if quoted else TOKEN)
		var parts: PackedStringArray = []
		var at := 0
		for m in re.search_all(out):
			parts.append(out.substr(at, m.get_start() - at))
			var off := int(m.get_string(1)) if m.get_string(1) != "" else 0
			parts.append(str(floor + off))
			at = m.get_end()
		parts.append(out.substr(at))
		out = "".join(parts)
	return out


static func _parse(path: String, text: String) -> Variant:
	var json := JSON.new()
	if json.parse(text) != OK:
		push_error("JSON 형식 오류: %s (%d행) %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
