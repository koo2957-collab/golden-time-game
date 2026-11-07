class_name Witness
extends RefCounted
## 관계인·목격자 (SOP 101-2.2②, 202-1.2, 2.1). 지휘관이 가까이 가서 질문하면 진술한다.
## 진술은 틀릴 수 있다 (reliable = false). 게임 중에는 알려주지 않고 디브리핑(M6)에서 밝힌다.

var index := 0
var name := ""
## 출처 (신고자·가족·목격자). 화면에 보인다
var source := ""
var pos := Vector2.ZERO
## 현장에 나타나는 틱
var arrive_tick := 0
## 질문 key -> {text, reliable, rooms?, hazard?}
var statements: Dictionary = {}
## 이미 들은 질문 key -> 들은 틱
var asked: Dictionary = {}


static func from_dict(i: int, d: Dictionary) -> Witness:
	var w := Witness.new()
	w.index = i
	w.name = str(d.get("name", "관계인"))
	w.source = str(d.get("source", "관계인"))
	var p: Array = d.get("pos", [0, 0])
	w.pos = Vector2(int(p[0]) + 0.5, int(p[1]) + 0.5)
	w.arrive_tick = roundi(float(d.get("arrive_s", 0)) / SimClock.TICK_DT)
	w.statements = d.get("statements", {})
	return w


func present(tick: int) -> bool:
	return tick >= arrive_tick


func label() -> String:
	return "%s (%s)" % [name, source]
