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
##   survey:         지휘관 360° 둘러보기 (건물 둘레 한 바퀴)
##   ask:            관계인에게 질문 (value = 관계인 index, answers.questions = 질문 key 배열)
##   update_report:  상황 보완 보고 (answers: victims, hazards)
##   end:            활동 종료 선언 (SOP 113-1.1). answers.watch = 재발화 감시 (202-6.5). 디브리핑으로 넘어간다
##   evacuate:       긴급탈출 지시 (SSG 9 2.1.7, SOP 109-1.3)
##   par:            인원점검 (SOP 109-1.3, 200-4.1)
##   card_answer:    질문 카드 답 (answers.uid = 카드, value = 화면에 보인 선택지 순서)
##   preorder:       선제지시 켜기·끄기 (answers.key, value 1 = 켬 / 0 = 끔)
##   all_clear:      완진 선언 (소방전술 I 8단계 ⑥, SOP 202-6). 불이 남아 있어도 막지 않고 그때 상태를 기록한다
##   placement:      선착 차량 배치 (value = 시나리오 approach.options index, SOP 200-3.1.1)
##   role:           안전 임무 지정 (squad_ids = 조 id, value = SafetySystem.Role: 0 해제 / 1 RIT / 2 현장안전담당)
##   approach:       진입구로 가기 (squad_ids = 조 id, value = 진입구 index). 허가 전이면 문 앞에서 허가를 묻는다 (P4-5)
##   floor:          층으로 가기 (squad_ids = 조 id, value = 층, answers.entry = 밖의 조가 쓸 진입구 index 또는 -1)
##   stair:          계단 고르기 답 (squad_ids = 조 id, value = 그 층 계단 index)
##   entry_all:      동시 진입 허가 — 진입 허가를 묻는 출동대 모두 (P4-5)

## 진입 허가 요청 카드 (data/cards: ENTRY-01)
const ENTRY_CARD := "ENTRY-01"

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
		"placement":
			Placement.apply(sim, value, tick)
		"all_clear":
			sim.phases.declare_all_clear(tick)
		"card_answer":
			sim.cards.answer(int(answers.get("uid", -1)), value, tick)
		"preorder":
			sim.cards.set_preorder(str(answers.get("key", "")), value == 1, tick)
		"mission_conditions":
			sim.tactical.set_conditions(answers.get("crews", []), answers, tick)
		"transfer":
			sim.transfer.transfer(answers, tick)
		"loadout":
			sim.apply_loadout(answers.get("items", []), tick)
		"report_request":
			sim.command.request_report(answers.get("crews", []), tick)
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
		"survey":
			cmd.survey.walk_around()
		"ask":
			cmd.survey.ask(value, answers.get("questions", []), tick)
		"update_report":
			cmd.update_report(answers, tick)
		"end":
			cmd.set_watch(str(answers.get("watch", "")), tick)
			sim.end_activity("활동 종료 선언")
		"evacuate":
			cmd.order_evacuation(tick)
		"zone":
			cmd.order_zone(str(answers.get("kind", "")), answers, tick)
		"preassign":
			sim.set_preassign(answers.get("tasks", {}), tick)
		"arrive":
			cmd.resources.begin_arrival(tick, float(answers.get("gap_s", 5.0)))
		"par":
			cmd.order_par(tick)
		"role":
			for id in squad_ids:
				cmd.order_role(id, value, tick)
		"approach":
			cmd.order_approach(squad_ids, sim.entries.list[value] if value >= 0 and value < sim.entries.list.size() else null, tick)
		"floor":
			var e: EntryPoints.Entry = null
			var ei := int(answers.get("entry", -1))
			if ei >= 0 and ei < sim.entries.list.size():
				e = sim.entries.list[ei]
			cmd.order_floor(squad_ids, value, e, tick)
		"stair":
			for id in squad_ids:
				cmd.order_stair(id, value, tick)
		"entry_all":
			# 동시 진입 (P4-5, SWAT 4 '고 코드'): 진입구 앞에서 기다리는 출동대 모두에게 진입 허가.
			# 진입 허가 카드가 떠 있는 출동대는 카드에 '허가'로 답하고(판단 기록), 나머지는 진입 명령
			var sids := cmd.waiting_squads()
			var names := PackedStringArray()
			for card in sim.cards.queue.duplicate():
				var sid := int(card.ctx.get("squad_id", -1))
				if card.id != ENTRY_CARD or not sid in sids:
					continue
				for i in card.options.size():
					if str(card.options[i].get("effect", "")) == "entry_grant":
						sim.cards.answer(card.uid, i, tick)
						sids.erase(sid)
						names.append(sim.units.squads[sid].name)
						break
			for sid in sids:
				if cmd.order_entry(sid, tick):
					names.append(sim.units.squads[sid].name)
			if not names.is_empty():
				sim.events.add(tick, "entry_all", {"squads": " · ".join(names), "count": names.size()})


func to_dict() -> Dictionary:
	return {
		"type": action,
		"tick": tick,
		"squads": squad_ids.duplicate(),
		"value": value,
		"answers": answers.duplicate(true),
		"target": [target.x, target.y, target.z],
	}
