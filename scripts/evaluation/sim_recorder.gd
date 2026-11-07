class_name SimRecorder
extends RefCounted
## 평가용 상태 기록. 1초마다 사건 기록에 남지 않는 상태(연소 칸 수, 직접 지휘 수, 내부 대원)를 샘플링한다.
## 판정(Evaluator)은 활동이 끝난 뒤 사건 기록과 이 기록만 읽는다.

const EVERY_TICKS := 10

## 초마다: 연소 중인 칸 수
var burning: PackedInt32Array = []
## 초마다: 현장지휘관이 직접 지휘하는 수
var direct: PackedInt32Array = []
## 초마다: 건물 안 대원 수
var indoor: PackedInt32Array = []
## 공기호흡기 경보 뒤 건물 안에 있던 구간 [{ff, start_tick, end_tick}] (end_tick -1: 끝까지 안)
var air_exposures: Array[Dictionary] = []

var _open_air: Dictionary = {}  # ff id -> air_exposures index


func step(sim: SimWorld, tick: int) -> void:
	if tick % EVERY_TICKS != 0:
		return
	burning.append(sim.fire.grid.burning.size())
	direct.append(sim.command.direct_count())
	var b := sim.building
	var n := 0
	for ff in sim.units.firefighters:
		var inside := not b.cell(ff.level, floori(ff.pos.x), floori(ff.pos.y)) in BuildingData.OUTDOOR
		if inside:
			n += 1
		var alarmed := ff.air_alarm_logged and inside and not ff.incapacitated
		if alarmed and not _open_air.has(ff.id):
			_open_air[ff.id] = air_exposures.size()
			air_exposures.append({"ff": ff.id, "start_tick": tick, "end_tick": -1})
		elif not alarmed and _open_air.has(ff.id):
			air_exposures[_open_air[ff.id]].end_tick = tick
			_open_air.erase(ff.id)
	indoor.append(n)


## 초 단위 샘플 수
func seconds() -> int:
	return burning.size()
