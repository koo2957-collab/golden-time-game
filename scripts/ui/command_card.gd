class_name CommandCard
extends RefCounted
## 명령 카드 상태 (기획안 9-1 "명령 카드 하나로 통일", P10-2).
## data/commands.json 하나를 원형 메뉴·하단 명령 카드·단축키(Q W E R A S)가 같이 쓴다.
##   - 세트: team(진압·구조) · ems(구급) · vehicle(차량). 아무것도 안 고르면 세트 없음("") — 카드는 숨는다
##   - 지휘관 명령은 카드가 아니라 항상 보이는 '지휘관 명령 칸'이다 (load_board, G3 2026-11-14 결정)
##   - act: false 항목은 누르면 하위 칸을 펼친다. 실행 항목에 sub가 있으면 실행(대상 클릭 대기) 중에 세부 동작을 펼친다
##   - Esc·뒤로 → 첫 칸. 화면은 만들지 않는다 (Hud·MissionUi가 그린다)

signal changed

const PATH := "res://data/commands.json"
## 칸 순서 = 키보드 배치 (윗줄 Q W E R, 아랫줄 A S)
const KEYS: Array[String] = ["Q", "W", "E", "R", "A", "S"]
const SET_TITLES := {"team": "팀 명령", "ems": "구급대 명령", "vehicle": "차량 명령"}

var sets: Dictionary = {}
var set_name := ""
## 펼친 상위 항목 id ("" = 첫 칸)
var parent := ""
## 항목을 쓸 수 있는지 (항목 Dictionary -> bool). 기본은 need가 later가 아니면 쓸 수 있다
var enabled_fn: Callable


func _init() -> void:
	sets = load_sets()


static func load_sets() -> Dictionary:
	var data: Variant = JsonData.load_file(PATH)
	if data is Dictionary and data.get("sets") is Dictionary:
		return data.sets
	push_error("명령 카드 파일을 읽지 못함: %s" % PATH)
	return {}


## 지휘관 명령 칸의 묶음들: [{id, label, items: [{id, label, hint}]}] (보고·지원·안전·구역)
static func load_board() -> Array[Dictionary]:
	return _load_list("commander_board")


## 지휘관 명령 칸 옆의 확인 단추 (명령이 아닌 것): [{id, label, hint}]
static func load_tools() -> Array[Dictionary]:
	return _load_list("commander_tools")


## 지휘관 명령 칸의 모든 명령 id (묶음 순서대로)
static func board_ids() -> PackedStringArray:
	var out: PackedStringArray = []
	for g in load_board():
		for it: Dictionary in g.get("items", []):
			out.append(str(it.id))
	return out


static func _load_list(key: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var data: Variant = JsonData.load_file(PATH)
	if data is Dictionary and data.get(key) is Array:
		out.assign(data[key])
	else:
		push_error("명령 카드 파일에 %s 가 없음: %s" % [key, PATH])
	return out


## 고른 대상이 바뀌면 세트를 바꾸고 첫 칸으로
func set_target(p_set: String) -> void:
	if p_set == set_name:
		return
	set_name = p_set
	parent = ""
	changed.emit()


## 지금 보이는 칸들 (첫 칸 또는 펼친 하위 칸)
func items() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var main: Array = sets.get(set_name, [])
	if parent != "":
		var p := _find(main, parent)
		if not p.is_empty():
			out.assign(p.get("sub", []))
			return out
	out.assign(main)
	return out


## 단축키 순서대로 6칸 (빈 칸은 빈 Dictionary)
func slots() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var list := items()
	for k in KEYS:
		var found: Dictionary = {}
		for it in list:
			if str(it.get("key", "")) == k:
				found = it
		out.append(found)
	return out


func title() -> String:
	var base: String = SET_TITLES.get(set_name, "명령")
	if parent == "":
		return base
	var p := _find(sets.get(set_name, []), parent)
	return "%s ▸ %s" % [base, str(p.get("label", ""))]


func parent_item() -> Dictionary:
	return _find(sets.get(set_name, []), parent) if parent != "" else {}


func is_enabled(item: Dictionary) -> bool:
	if item.is_empty() or str(item.get("need", "")) == "later":
		return false
	return enabled_fn.call(item) if enabled_fn.is_valid() else true


## 단축키 → 항목
func item_for_key(key: String) -> Dictionary:
	for it in items():
		if str(it.get("key", "")) == key:
			return it
	return {}


## 칸을 누른다 (단축키·버튼·원형 메뉴 공통). 실행할 명령 id를 돌려준다 ("" = 하위 칸만 펼침·못 씀)
func press(key: String) -> String:
	return press_item(item_for_key(key))


func press_item(item: Dictionary) -> String:
	if not is_enabled(item):
		return ""
	var id := str(item.id)
	if parent == "" and item.has("sub"):
		parent = id
		changed.emit()
		if item.get("act", true) == false:
			return ""
	return id


## 명령을 실행한 뒤·대상 고르기가 끝난 뒤: 고르는 중이 아니면 첫 칸으로 돌아간다
func settle(choosing: bool) -> void:
	if choosing or parent == "":
		return
	parent = ""
	changed.emit()


## Esc·뒤로. 돌아갔으면 true
func back() -> bool:
	if parent == "":
		return false
	parent = ""
	changed.emit()
	return true


## 모든 세트의 실행 id (도움말·테스트용)
func all_ids(p_set: String) -> PackedStringArray:
	var out: PackedStringArray = []
	for it: Dictionary in sets.get(p_set, []):
		out.append(str(it.id))
		for s: Dictionary in it.get("sub", []):
			out.append(str(s.id))
	return out


static func _find(list: Array, id: String) -> Dictionary:
	for it: Dictionary in list:
		if str(it.get("id", "")) == id:
			return it
	return {}
