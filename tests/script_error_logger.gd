extends Logger
## 테스트 실행기가 테스트 도중의 스크립트 오류(SCRIPT ERROR)를 세는 기록기 (2026-11-24).
## GDScript 는 실행 중 오류가 나면 그 함수만 멈추고 돌아오므로, 단정(assert)이 하나도 실패하지 않은 채 '통과'로 세어졌다
## (예: 타입을 알 수 없어 컴파일이 안 된 스크립트 → 모든 테스트가 통과로 나옴). 오류가 나면 그 테스트를 실패로 센다.

var errors: PackedStringArray = []
var _mutex := Mutex.new()


func _log_error(function: String, file: String, line: int, code: String, rationale: String, _editor_notify: bool,
		error_type: int, _script_backtraces: Array[ScriptBacktrace]) -> void:
	if error_type != Logger.ERROR_TYPE_SCRIPT:
		return
	_mutex.lock()
	errors.append("%s (%s:%d %s)" % [rationale if rationale != "" else code, file.get_file(), line, function])
	_mutex.unlock()


func take() -> PackedStringArray:
	_mutex.lock()
	var out := errors
	errors = PackedStringArray()
	_mutex.unlock()
	return out
