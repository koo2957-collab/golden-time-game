class_name Profile
extends RefCounted
## 교육생 프로필 (기획안 8-4 화면 흐름 '프로필(이름·소속)', P11-1).
## 결과 파일·결과 CSV(교관 제출용)에만 쓰고, 순위는 만들지 않는다 (SOP 113-3.1.6 지도·개선 용도).

const PATH := "user://profile.json"


## {name, unit}. 없으면 빈 사전
static func load_profile(path := PATH) -> Dictionary:
	var d: Variant = JsonData.load_file(path) if FileAccess.file_exists(path) else null
	if not d is Dictionary:
		return {}
	return {"name": str(d.get("name", "")), "unit": str(d.get("unit", ""))}


static func has_profile(path := PATH) -> bool:
	return str(load_profile(path).get("name", "")).strip_edges() != ""


static func save_profile(p_name: String, unit: String, path := PATH) -> bool:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify({"name": p_name.strip_edges(), "unit": unit.strip_edges()}, "  "))
	return true


## 화면 한 줄: "홍길동 · ○○119안전센터" (없으면 "")
static func text(p: Dictionary) -> String:
	var parts: PackedStringArray = []
	for k in ["name", "unit"]:
		if str(p.get(k, "")) != "":
			parts.append(str(p[k]))
	return " · ".join(parts)
