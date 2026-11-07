class_name ParamTable
extends RefCounted
## {"키": {"value": 값, "source": ...}} 형식 수치 표 (예: data/units/firefighter.json)

var params: Dictionary = {}


static func from_dict(data: Dictionary) -> ParamTable:
	var t := ParamTable.new()
	t.params = data
	return t


func value(key: String) -> float:
	if not params.has(key) or not params[key] is Dictionary:
		push_error("수치 '%s'가 없습니다." % key)
		return 0.0
	return float(params[key]["value"])
