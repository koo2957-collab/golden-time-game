class_name Organization
extends RefCounted
## 현장대응조직 (SOP 105).
##   단위대 (105-1.3, 2.2, 2.3): 방면(A~D면)·층·기능별로 출동대를 묶고 단위지휘관(소속 출동대장)을 지정한다
##   통솔범위 (용어 정의): 3~7, 5가 적정. 현장지휘관이 직접 지휘하는 수 = 단위대 수 + 단위대에 속하지 않은 출동대 수
##   적정을 넘으면 넘은 수만큼 직접 지휘하는 출동대에 내리는 명령이 늦게 실행된다 (관리 과부하, 105-2.1①)
##   단위대마다 작전망을 따로 쓴다 (107-2.6, 3.2)

const FUNCTION_DIVISIONS: Array[String] = ["배연", "인명구조", "급수"]


class Division:
	extends RefCounted
	var name := ""
	## 단위지휘관을 맡는 출동대 (그 출동대장)
	var supervisor := -1
	var squads: Array[int] = []
	## 이 단위대의 작전망
	var radio: Radio


## 작전망 무전이 전달될 때 (KnowledgeBoard, P10-1)
var on_delivered := Callable()
var divisions: Array[Division] = []
var span_ideal := 5
var span_max := 7
var delay_per_excess_s := 5.0
## 통솔범위 초과로 늦게 실행한 명령 수 (평가용)
var delayed_orders := 0

var _params: ParamTable
var _events: SimEventLog
var _channels := 0
var _retired: Array[Radio] = []  # 해제했지만 아직 송신 중인 작전망


func _init(params: ParamTable, p_events: SimEventLog) -> void:
	_params = params
	_events = p_events
	span_ideal = roundi(params.value("span_ideal"))
	span_max = roundi(params.value("span_max"))
	delay_per_excess_s = params.value("span_delay_per_excess_s")


## 단위대 이름 보기: 방면 → 층 → 기능
static func division_names(building: BuildingData) -> Array[String]:
	var out: Array[String] = []
	for key: String in ["A", "B", "C", "D"]:
		if building.faces.has(key):
			out.append("%s면" % key)
	for level in building.levels():
		out.append(building.floor_name(level))
	out.append_array(FUNCTION_DIVISIONS)
	return out


func division_of(squad_id: int) -> Division:
	for d in divisions:
		if squad_id in d.squads:
			return d
	return null


func division_named(name: String) -> Division:
	for d in divisions:
		if d.name == name:
			return d
	return null


## 단위대를 만들거나 고친다. 다른 단위대에 있던 출동대는 옮겨 온다 (빈 단위대는 없앤다).
func set_division(name: String, supervisor: int, squads: Array[int]) -> Division:
	var d := division_named(name)
	if d == null:
		d = Division.new()
		d.name = name
		_channels += 1
		d.radio = Radio.new(_params, _events, "작전망 %d" % _channels)
		# 단위지휘관이 받은 보고도 상황판에 오른다 (지휘관에게 전파, P10-1)
		d.radio.on_delivered = on_delivered
		divisions.append(d)
	var members := squads.duplicate()
	if not supervisor in members:
		members.push_front(supervisor)
	for other in divisions:
		if other != d:
			for s in members:
				other.squads.erase(s)
	d.supervisor = supervisor
	d.squads = members
	divisions = divisions.filter(func(x: Division) -> bool:
		if x.squads.is_empty() or not x.supervisor in x.squads:
			if x.radio.busy():
				_retired.append(x.radio)
			return false
		return true)
	return d


func clear_division(name: String) -> bool:
	var d := division_named(name)
	if d == null:
		return false
	divisions.erase(d)
	if d.radio.busy():
		_retired.append(d.radio)
	return true


## 현장지휘관이 직접 지휘하는 수 (on_scene: 현장에 도착한 출동대인지 판정하는 Callable)
func direct_count(squad_count: int, on_scene: Callable) -> int:
	var n := divisions.size()
	for id in squad_count:
		if on_scene.call(id) and division_of(id) == null:
			n += 1
	return n


## 직접 지휘하는 출동대에 내리는 명령의 지연 (초). 단위대에 속한 출동대만 받는 명령이면 지연 없음.
func order_delay_s(squads: Array[int], direct: int) -> float:
	var excess := direct - span_ideal
	if excess <= 0:
		return 0.0
	for s in squads:
		if division_of(s) == null:
			return excess * delay_per_excess_s
	return 0.0


## 작전망 전부 (해제된 단위대의 송신 중인 망 포함)
func radios() -> Array[Radio]:
	var out: Array[Radio] = []
	for d in divisions:
		out.append(d.radio)
	out.append_array(_retired)
	return out


func step(dt: float, tick: int) -> void:
	for r in radios():
		r.step(dt, tick)
	_retired = _retired.filter(func(r: Radio) -> bool: return r.busy())
