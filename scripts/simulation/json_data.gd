class_name JsonData
extends RefCounted
## JSON 데이터 파일 읽기.


## 파일을 읽어 파싱한 값을 반환한다. 실패하면 오류를 남기고 null을 반환한다.
static func load_file(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		push_error("데이터 파일이 없습니다: %s" % path)
		return null
	var json := JSON.new()
	var err := json.parse(FileAccess.get_file_as_string(path))
	if err != OK:
		push_error("JSON 형식 오류: %s (%d행) %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data
