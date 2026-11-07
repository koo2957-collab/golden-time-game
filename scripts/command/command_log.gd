class_name CommandLog
extends RefCounted
## 실행된 명령의 기록. 디브리핑 타임라인과 리플레이에 쓰인다.

var entries: Array = []


func record(command: RefCounted) -> void:
	entries.append(command)


func to_array() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for command in entries:
		out.append(command.to_dict())
	return out
