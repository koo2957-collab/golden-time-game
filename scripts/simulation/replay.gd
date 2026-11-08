class_name Replay
extends RefCounted
## 다시 하기: 같은 시나리오를 처음부터 다시 만들고, 기록된 명령을 내린 틱에 그대로 넣으며 target 틱까지 빠르게 진행한다.
## 시뮬레이션은 결정론적이므로(시드 난수만 쓴다) 그 시점의 상태가 원래 판과 같아진다.
## 화면이 멈추지 않도록 step()을 여러 프레임에 나눠 부른다.

var sim: SimWorld
var target_tick := 0
var _entries: Array[Dictionary] = []
var _next := 0


## path 시나리오로 새로 시작해 entries([{tick, command}])를 target_tick까지 재생할 준비. 실패하면 null
static func begin(path: String, entries: Array[Dictionary], p_target_tick: int, p_seed := -1, automation := "", realism := "", growth: Dictionary = {}) -> Replay:
	var r := Replay.new()
	r.sim = SimWorld.from_scenario(path, true, p_seed)
	if r.sim == null:
		return null
	r.sim.apply_growth(growth)
	if realism != "":
		r.sim.apply_realism(realism)
	if automation != "":
		r.sim.tactical.set_level(automation)
	r.target_tick = maxi(0, p_target_tick)
	for e in entries:
		if int(e.tick) < r.target_tick:
			r._entries.append(e)
	return r


## 최대 max_ticks틱 진행. 끝났으면 true
func step(max_ticks: int) -> bool:
	var n := 0
	while sim.clock.tick < target_tick and n < max_ticks:
		while _next < _entries.size() and int(_entries[_next].tick) <= sim.clock.tick:
			sim.issue(_entries[_next].command)
			_next += 1
		sim.step_ticks(1)
		n += 1
	return done()


func done() -> bool:
	return sim.clock.tick >= target_tick


func progress() -> float:
	return 1.0 if target_tick <= 0 else clampf(float(sim.clock.tick) / target_tick, 0.0, 1.0)
