class_name CommandOrder
extends RefCounted
## 지휘 명령. 실행하면 CommandSystem이 무전으로 송신하고, 송신이 끝나야 받는 쪽에 전달된다.
##   declare:        지휘권 선언 + 최초 상황보고 (answers)
##   entry:          내부 진입 명령 (squad_ids)
##   strategy:       전략 변경 전파 (value = CommandSystem.Strategy)
##   commander_move: 현장지휘관 이동 (target)
##   support:        지원 요청 (answers.level = 지원 수준 보기 글자)
##   division:       단위대 지정 (value = 단위지휘관 출동대, squad_ids = 소속 출동대, answers.name = 단위대 이름)
##   division_clear: 단위대 해제 (answers.name)

var tick := -1
var action := ""
var squad_ids: Array[int] = []
var value := 0
var answers: Dictionary = {}
var target := Vector3i.ZERO


static func make(p_action: String, p_squad_ids: Array[int] = [], p_value := 0, p_target := Vector3i.ZERO, p_answers: Dictionary = {}) -> CommandOrder:
	var c := CommandOrder.new()
	c.action = p_action
	c.squad_ids = p_squad_ids.duplicate()
	c.value = p_value
	c.target = p_target
	c.answers = p_answers.duplicate(true)
	return c


func execute(sim: SimWorld) -> void:
	var cmd := sim.command
	match action:
		"declare":
			cmd.declare(answers, tick)
		"entry":
			for id in squad_ids:
				cmd.order_entry(id, tick)
		"strategy":
			cmd.order_strategy(value as CommandSystem.Strategy, tick)
		"commander_move":
			cmd.move_commander(target)
		"support":
			cmd.order_support(str(answers.get("level", "")), tick)
		"division":
			cmd.order_division(str(answers.get("name", "")), value, squad_ids, tick)
		"division_clear":
			cmd.order_division_clear(str(answers.get("name", "")), tick)


func to_dict() -> Dictionary:
	return {
		"type": action,
		"tick": tick,
		"squads": squad_ids.duplicate(),
		"value": value,
		"answers": answers.duplicate(true),
		"target": [target.x, target.y, target.z],
	}
