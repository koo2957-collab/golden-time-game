extends Node
## 진입점. 시작 화면(시나리오 선택)을 띄우고, 고른 시나리오로 게임 씬을 붙인다.
## 다시 시작·다시 하기는 GameManager에 값을 남기고 씬을 다시 불러와 시작 화면을 건너뛴다.
## F5: 같은 시나리오를 처음부터 다시 (데이터 파일을 다시 읽는다. 스크립트 코드 변경은 프로그램을 다시 실행해야 반영된다)
## 창 닫기(X)·Alt+F4는 바로 끄지 않고 '게임 종료' 확인 창을 띄운다 (기획안 8-4, P11-1)

@export var start_scene: PackedScene
@export var menu_scene: PackedScene

## 시작 화면에서 쓰는 종료 확인 창 (게임 중에는 world의 게임 메뉴가 띄운다)
var quit_menu: GameMenu


func _ready() -> void:
	# 실제 게임으로 실행했을 때만 화면 설정을 적용한다 (자동 테스트는 메인 씬을 직접 붙이므로 current_scene이 아니다)
	if get_tree().current_scene == self:
		DisplaySettings.apply_once(get_window())
		get_tree().set_auto_accept_quit(false)
	quit_menu = GameMenu.new()
	quit_menu.in_mission = false
	quit_menu.quit_confirmed.connect(func() -> void: get_tree().quit())
	add_child(quit_menu)
	if GameManager.skip_menu and GameManager.scenario_path != "":
		_start_world()
		return
	var menu: ScenarioMenu = menu_scene.instantiate()
	menu.start_requested.connect(_on_start_requested)
	menu.quit_requested.connect(request_quit)
	add_child(menu)
	if get_tree().current_scene == self and not Profile.has_profile():
		menu.open_profile()
	GameManager.change_state(GameManager.GameState.MENU)


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		request_quit()


## 게임 종료 확인: 게임 중이면 world(진행 중인 판을 '미완료'로 저장), 아니면 시작 화면용 확인 창
func request_quit() -> void:
	var worlds := get_tree().get_nodes_in_group("world")
	if not worlds.is_empty():
		worlds[0].request_quit()
	elif quit_menu:
		quit_menu.open_confirm("quit")


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart_scene"):
		GameManager.restart()


func _on_start_requested(path: String) -> void:
	GameManager.scenario_path = path
	for c in get_children():
		if c != quit_menu:
			c.queue_free()
	_start_world.call_deferred()


func _start_world() -> void:
	GameManager.skip_menu = false
	if start_scene:
		add_child(start_scene.instantiate())
	GameManager.change_state(GameManager.GameState.MISSION)
