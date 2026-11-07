class_name SimClock
extends RefCounted
## 고정 틱 게임 시계.
## 화면 프레임과 무관하게 일정한 간격(TICK_DT)으로 시뮬레이션을 진행시킨다.
## 같은 명령을 같은 틱에 넣으면 항상 같은 결과가 나오도록 하는 결정론의 기반이다.

const TICK_RATE := 10
const TICK_DT := 1.0 / TICK_RATE
## 프레임이 크게 밀렸을 때 한 번에 처리할 최대 틱 수 (처리 지연이 누적되는 것을 막는다)
const MAX_TICKS_PER_FRAME := 8
## 부동소수점 오차로 틱 경계를 놓치지 않기 위한 허용 오차
const EPSILON := 1e-6

var tick := 0
var speed := 1.0
var paused := false
var _accum := 0.0


## 실제 경과 시간(delta)을 받아 이번 프레임에 처리할 틱 수를 반환한다.
func consume(delta: float) -> int:
	if paused:
		return 0
	_accum += delta * speed
	var n := mini(floori(_accum / TICK_DT + EPSILON), MAX_TICKS_PER_FRAME)
	_accum = clampf(_accum - n * TICK_DT, 0.0, TICK_DT)
	return n


## 마지막 틱 이후 다음 틱까지의 진행 비율 (화면 보간용, 0~1)
func alpha() -> float:
	return clampf(_accum / TICK_DT, 0.0, 1.0)


func elapsed_seconds() -> float:
	return tick * TICK_DT
