extends Node
## 게임 전역 상태 관리. 씬을 다시 불러와도(F5·다시 하기) 남아야 하는 값을 갖는다.

enum GameState { BOOT, MENU, BRIEFING, MISSION, DEBRIEF }

var state: GameState = GameState.BOOT
## 플레이할 시나리오 경로 (시작 화면에서 고른다)
var scenario_path := ""
## true면 시작 화면 없이 scenario_path로 바로 시작한다 (다시 시작·다시 하기)
var skip_menu := false
## 플레이 방식: "평가" (힌트 없음, 디브리핑에서만 공개) / "교육" (판단이 필요한 순간 SOP 힌트)
var mode := "평가"
## 자동화 수준 (입문·중급·상급). 빈 문자열이면 시나리오 난이도를 따른다
var difficulty := ""
## 난이도: "훈련"(제한시간 2배, 일시정지·배속) / "실전"(1배속 고정, 일시정지 없음) / "악조건"(실전 + 강풍·후착대 지연·소화전 고장)
var realism := "실전"
## 다시 하기 요청 {entries: [{tick, command}], tick, seed, automation, realism}. 비어 있으면 처음부터
var replay: Dictionary = {}
## 교관 설정의 시작 화면 기본값을 한 번 적용했는가
var defaults_applied := false


func change_state(new_state: GameState) -> void:
	state = new_state


## 같은 시나리오를 처음부터 다시 (F5)
func restart() -> void:
	skip_menu = scenario_path != ""
	replay = {}
	get_tree().reload_current_scene.call_deferred()


## 시작 화면으로
func back_to_menu() -> void:
	skip_menu = false
	replay = {}
	get_tree().reload_current_scene.call_deferred()


## 같은 시나리오를 tick 시점부터 다시 (entries를 그 시점까지 재생)
func request_replay(entries: Array[Dictionary], tick: int, p_seed: int, automation: String, p_realism := "") -> void:
	skip_menu = true
	replay = {"entries": entries.duplicate(), "tick": tick, "seed": p_seed, "automation": automation, "realism": p_realism}
	get_tree().reload_current_scene.call_deferred()
