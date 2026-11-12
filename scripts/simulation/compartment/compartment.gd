class_name Compartment
extends RefCounted
## 구획(방) 하나의 화재 상태. 상부 고온층 / 하부 저온층 2층 모델.

enum Stage { NONE, INCIPIENT, GROWTH, FLASHOVER, FULLY_DEVELOPED, DECAY, BURNT_OUT, EXTINGUISHED }

const STAGE_NAMES := {
	Stage.NONE: "-",
	Stage.INCIPIENT: "발화기",
	Stage.GROWTH: "성장기",
	Stage.FLASHOVER: "플래시오버",
	Stage.FULLY_DEVELOPED: "최성기",
	Stage.DECAY: "쇠퇴기",
	Stage.BURNT_OUT: "소진",
	Stage.EXTINGUISHED: "진화",
}
const O2_AMBIENT_MASS := 0.23
const AIR_DENSITY := 1.2

var index := 0
var id := ""
var name := ""
var level := 1
var rect := Rect2i()
var cells: Array[Vector2i] = []
var area := 0.0
var height := 2.4
var volume := 0.0
var surface := 0.0
var openings: Array[int] = []
## 이 방의 플래시오버 상부층 온도 (판마다 교재 범위 안에서 정해짐)
var flashover_temp := 600.0

# 상태
var t_upper := 20.0
var t_lower := 20.0
## 천장에서 연기층 하단까지의 깊이 (m) — 방 전체 평균 (연기 부피 ÷ 바닥 면적)
var layer_depth := 0.0
## 연기 선두 (기획안 5-3-1, 2026-11-12 사용자 결정 A): 연기는 출발점(불 위 또는 연기가 들어온 개구부)에서
## 천장을 따라 퍼져 벽까지 덮은 뒤에야 아래로 쌓인다. 출발점 (셀 좌표, 없으면 x < 0 → 이미 다 덮인 것으로 본다)
var smoke_origin := Vector2(-1, -1)
## 선두가 출발점에서 나아간 거리 / 방에서 가장 먼 곳까지의 거리 (m)
var smoke_reach_m := 0.0
var smoke_full_m := 0.0
## 다 덮기 전 천장류(천장을 따라 퍼지는 얇은 연기) 두께 (m)
var jet_depth_m := 0.24
## 셀 한 변 (m)
var cell_m := 0.5
## 산소 질량분율 (대기 0.23)
var y_o2 := O2_AMBIENT_MASS
## 미연소가스 (kg)
var gas := 0.0
## 그을음 (kg)
var soot := 0.0
## 가연물이 낼 수 있는 열방출률 / 실제 열방출률 (kW)
var q_potential := 0.0
## 가연물이 내는 그을음 (kg/s, 산소 부족 보정 전)
var soot_rate := 0.0
var q := 0.0
var q_max := 0.0
## 산소에 따른 불꽃연소 효율 (0~1)
var combustion_eff := 1.0
## 다른 구획에서 들어온 고온 가스의 열량 (kW)
var imported_kw := 0.0
## 방수가 고온층에서 빼앗는 열 (kW, 매 틱 다시 계산)
var cooling_kw := 0.0
## 이 구획에 뿌린 물 / 그중 수손으로 본 양 (L)
var water_applied_l := 0.0
var water_damage_l := 0.0
## 필요 방수량 (기획안 5-4, P6-1): 연소 중 면적(m²)·화재하중 계수, 필요·실제 방수량(L/분), 비율
var burning_area_m2 := 0.0
var load_factor := 1.0
## 연기 독성 배율 (탄 가연물 재질, 화재2 표 4-12). 연기를 따라 옆 구획으로 옮겨진다
var toxicity := 1.0
var required_lpm := 0.0
var applied_lpm := 0.0
var flow_ratio := 0.0
var fuel_initial := 0.0
var fuel_remaining := 0.0
var flashed := false
var flashover_tick := -1
var ever_burned := false
var smoke_logged := false
## 인명검색을 마친 틱 (-1: 안 함) (SOP 212-2.1 검색 완료 표시)
var searched_tick := -1
## 잔불정리를 마친 틱 (-1: 안 함)
var overhauled_tick := -1
## 롤오버 징후 (플래시오버 임박)
var rollover := false
var stage := Stage.NONE


func display_name() -> String:
	return "%d층 %s" % [level, name]


func stage_name() -> String:
	return STAGE_NAMES[stage]


func layer_volume() -> float:
	return layer_depth * area


## 연기 선두가 출발했는가
func smoke_started() -> bool:
	return smoke_origin.x >= 0.0


## 천장을 다 덮었는가 (선두 없이 연기층만 있으면 덮인 것으로 본다)
func smoke_covered() -> bool:
	return not smoke_started() or smoke_reach_m >= smoke_full_m


## 연기 선두가 이 지점(셀 좌표)에 닿았는가
func smoke_reaches(p: Vector2, margin_m := 0.0) -> bool:
	return smoke_covered() or smoke_origin.distance_to(p) * cell_m <= smoke_reach_m + margin_m


## 연기 선두 출발 (불 위 또는 연기가 들어온 개구부)
func start_smoke_front(at: Vector2) -> void:
	smoke_origin = at
	smoke_reach_m = 0.0
	var far := 0.0
	for corner: Vector2 in [Vector2(rect.position), Vector2(rect.end.x, rect.position.y), Vector2(rect.end), Vector2(rect.position.x, rect.end.y)]:
		far = maxf(far, at.distance_to(corner))
	smoke_full_m = far * cell_m


func clear_smoke_front() -> void:
	smoke_origin = Vector2(-1, -1)
	smoke_reach_m = 0.0
	smoke_full_m = 0.0


## 화면에 보이는 연기층 두께: 다 덮기 전에는 덮인 곳에 천장류 두께까지만
func shown_layer_depth() -> float:
	return layer_depth if smoke_covered() else minf(layer_depth, jet_depth_m)


func o2_percent() -> float:
	return y_o2 / O2_AMBIENT_MASS * 21.0


func gas_percent() -> float:
	return gas / (AIR_DENSITY * volume) * 100.0


func fuel_fraction() -> float:
	return fuel_remaining / fuel_initial if fuel_initial > 0.0 else 0.0


## 그을음 농도로 계산한 가시거리 (m)
func visibility_m(extinction_coeff: float) -> float:
	var conc := soot / volume
	if conc <= 1e-9:
		return 30.0
	return minf(30.0, 3.0 / (extinction_coeff * conc))
