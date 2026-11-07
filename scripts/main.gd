extends Node
## 진입점. 시작 씬을 불러와 자식으로 붙인다.
## F5: 처음부터 다시 시작 (데이터 파일을 다시 읽는다. 스크립트 코드 변경은 프로그램을 다시 실행해야 반영된다)

@export var start_scene: PackedScene


func _ready() -> void:
	if start_scene:
		add_child(start_scene.instantiate())
	GameManager.change_state(GameManager.GameState.MISSION)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("restart_scene"):
		get_tree().reload_current_scene.call_deferred()
