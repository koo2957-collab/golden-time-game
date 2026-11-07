class_name PlanStyle
extends RefCounted
## 전술 상황판(도면) 스타일의 공통 크기와 색상.

## 셀(0.5m) 하나의 화면 크기
const CELL_PX := 24.0

const BACKGROUND := Color("0e1319")
const GRID_LINE := Color(1, 1, 1, 0.05)
const ROOM_LABEL := Color("4a5561")
const FACE_LABEL := Color("8fa1b3")
const ROAD_LABEL := Color("6b7683")
const STAIR_LINE := Color("6b7683")
const SELECTION := Color("22c55e")
const PATH_LINE := Color(1, 1, 1, 0.45)
const UNIT_OUTLINE := Color("0e1319")
const UNIT_TEXT := Color.WHITE
const LANE_LINE := Color(0.9, 0.85, 0.6, 0.35)
const HOSE_COLOR := Color("e8dcc0")
## 소화전 흡수관 · 물탱크차 급수관
const SUPPLY_LINE := Color("64b5f6")
const HYDRANT_COLOR := Color("e53935")
const WATER_COLOR := Color(0.62, 0.84, 1.0, 0.9)
const FOG_COLOR := Color(0.75, 0.88, 1.0, 0.3)
const TANK_BG := Color(0.05, 0.07, 0.1, 0.85)
const TANK_FILL := Color("4fc3f7")
const AIR_OK := Color("e0e0e0")
const AIR_LOW := Color("ff5252")
const SMOKE_PLUME := Color(0.18, 0.18, 0.2, 0.55)
const SEARCHED := Color("81c784")
## 요구조자 상태별 색 (Victim.State 순서: 의식 있음, 의식 잃음, 사망, 구조됨)
const VICTIM_COLORS := [Color("ffd54f"), Color("ff8a65"), Color("9e9e9e"), Color("81c784")]
const FURNITURE_FILL := Color("bcc4cd")
const FURNITURE_LINE := Color("8a949f")
## 다른 층을 비춰 보일 때의 불투명도
const OTHER_FLOOR_ALPHA := 0.25

const CELL_COLORS := {
	BuildingData.Cell.GROUND: Color("222b34"),
	BuildingData.Cell.ROAD: Color("313a45"),
	BuildingData.Cell.SIDEWALK: Color("3d4651"),
	BuildingData.Cell.FLOOR: Color("d5dbe1"),
	BuildingData.Cell.WALL: Color("4b5664"),
	BuildingData.Cell.DOOR: Color("c08a3e"),
	BuildingData.Cell.WINDOW: Color("6aa7e0"),
	BuildingData.Cell.STAIRS: Color("aeb7c1"),
}


static func font() -> Font:
	return ThemeDB.fallback_font


static func to_px(cell_pos: Vector2) -> Vector2:
	return cell_pos * CELL_PX


static func to_cell(px: Vector2) -> Vector2:
	return px / CELL_PX

## 현장지휘관 (흰 몸체, 빨간 안전모)
## 관계인 (몸·머리), 실내등 켜진 창, 진술로 알려진 방 표시
const WITNESS_BODY := Color("a78b6b")
const WITNESS_HEAD := Color("f1d5b0")
## 열화상으로 찾은 불씨
const EMBER := Color("ff7a1a")
const LIT_WINDOW := Color(1.0, 0.85, 0.4, 0.9)
const REPORTED_ROOM := Color("fb923c")
## 대기1단계 장소 표시
const STAGING_COLOR := Color(0.99, 0.83, 0.3, 0.55)
const COMMANDER_BODY := Color("e5e7eb")
const COMMANDER_HELMET := Color("ef4444")
