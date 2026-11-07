extends TestSuite


func test_load_house() -> void:
	var b := BuildingData.from_file(BUILDING_PATH)
	assert_true(b != null, "주택 도면 로드")
	if b == null:
		return
	assert_eq(b.width, 72, "가로 셀 수 (동쪽 도로 = 대기1단계 장소)")
	assert_eq(b.height, 40, "세로 셀 수")
	assert_eq(b.road_rows(1), Vector2i(28, 39), "차도 12셀(6m)")
	assert_eq(b.cell(1, 5, 26), BuildingData.Cell.SIDEWALK, "보도")
	assert_eq(b.levels(), [1, 2] as Array[int], "층 목록")
	assert_eq(b.cell(1, 8, 3), BuildingData.Cell.WALL, "외곽벽 모서리")
	assert_eq(b.cell(1, 13, 20), BuildingData.Cell.DOOR, "현관문")
	assert_eq(b.cell(2, 0, 0), BuildingData.Cell.VOID, "2층 외부는 빈 공간")
	assert_eq(b.room_at(1, 12, 15).get("name"), "거실", "방 판정")
	assert_eq(b.stair_links(1).size(), 8, "1~2층 연결 계단 셀 수")
	assert_eq(b.footprint(1), Rect2i(8, 3, 24, 18), "건물 범위")


func test_invalid_grid_reports_errors() -> void:
	var b := BuildingData.new()
	b._parse({"width": 3, "height": 2, "floors": [{"level": 1, "grid": ["...", ".X"]}]})
	assert_true(not b.load_errors.is_empty(), "잘못된 행 길이를 오류로 보고")
