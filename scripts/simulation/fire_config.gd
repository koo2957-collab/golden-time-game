class_name FireConfig
extends RefCounted
## 화재 수치(data/fire/fire_params.json)와 가연물 재질(data/materials/materials.json).

var params: Dictionary = {}
var materials: Dictionary = {}  # 재질 이름 -> Dictionary


static func load_files(params_path: String, materials_path: String) -> FireConfig:
	var p: Variant = JsonData.load_file(params_path)
	var m: Variant = JsonData.load_file(materials_path)
	if not p is Dictionary or not m is Dictionary:
		return null
	var config := FireConfig.new()
	config.params = p
	for key: String in m:
		if m[key] is Dictionary:
			config.materials[key] = m[key]
	return config


func value(key: String) -> float:
	if not params.has(key):
		push_error("화재 수치 '%s'가 fire_params.json에 없습니다." % key)
		return 0.0
	return float(params[key]["value"])


func range_of(key: String) -> Vector2:
	var entry: Dictionary = params.get(key, {})
	return Vector2(float(entry.get("min", 0.0)), float(entry.get("max", 0.0)))


func has_material(material_name: String) -> bool:
	return materials.has(material_name)
