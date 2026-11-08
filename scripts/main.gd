extends Node
## 진입점. 시작 화면(시나리오 선택)을 띄우고, 고른 시나리오로 게임 씬을 붙인다.
## 다시 시작·다시 하기는 GameManager에 값을 남기고 씬을 다시 불러와 시작 화면을 건너뛴다.
## F5: 같은 시나리오를 처음부터 다시 (데이터 파일을 다시 읽는다. 스크립트 코드 변경은 프로그램을 다시 실행해야 반영된다)

@export var start_scene: PackedScene
@export var menu_scene: PackedScene


func _ready() -> void:
	# 실제 게임으로 실행했을 때만 화면 설정을 적용한다 (자동 테스트는 메인 씬을 직접 붙이므로 current_scene이 아니다)
	if get_tree().current_scene == self:
		DisplaySettings.apply_once(get_window())
	if GameManager.skip_menu and GameManager.scenario_path != "":
		_start_world()
		return
	var menu: ScenarioMenu = menu_scene.instantiate()
	menu.start_requested.connect(_on_start_requested)
	add_child(menu)
	GameManager.change_state(GameManager.GameState.MENU)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart_scene"):
		GameManager.restart()


func _on_start_requested(path: String) -> void:
	GameManager.scenario_path = path
	for c in get_children():
		c.queue_free()
	_start_world.call_deferred()


func _start_world() -> void:
	GameManager.skip_menu = false
	if start_scene:
		add_child(start_scene.instantiate())
	GameManager.change_state(GameManager.GameState.MISSION)
