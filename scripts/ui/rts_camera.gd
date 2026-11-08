class_name RtsCamera
extends Camera2D
## RTS 카메라. 방향키 이동, 휠 버튼 끌기 이동, 마우스 휠로 커서 위치 기준 줌.
## 실제 시간으로 움직이므로 일시정지 중에도 조작할 수 있다.

const PAN_SPEED_PX := 900.0
const ZOOM_STEP := 1.15
const ZOOM_MIN := 0.5
const ZOOM_MAX := 3.0
var bounds := Rect2()
## 화면 가장자리 자동 스크롤 (기획안 9-3). 마우스가 가장자리 EDGE_PX 안에 있으면 그쪽으로 흐른다
var edge_scroll := true
const EDGE_PX := 20.0
var _dragging := false


func setup(p_bounds: Rect2, start_zoom: float) -> void:
	bounds = p_bounds
	position = bounds.get_center()
	zoom = Vector2(start_zoom, start_zoom)


## 화면 전환 시: 이동 범위를 바꾸고 center 지점을 화면 가운데에 둔다 (줌은 유지).
func retarget(p_bounds: Rect2, center: Vector2) -> void:
	bounds = p_bounds
	position = center
	_clamp()


func _process(delta: float) -> void:
	var dir := Input.get_vector("camera_left", "camera_right", "camera_up", "camera_down")
	if edge_scroll and dir == Vector2.ZERO and DisplayServer.window_is_focused() and Input.mouse_mode == Input.MOUSE_MODE_CONFINED:
		var m := get_viewport().get_mouse_position()
		var s := get_viewport().get_visible_rect().size
		dir = Vector2(-1.0 if m.x < EDGE_PX else (1.0 if m.x > s.x - EDGE_PX else 0.0),
			-1.0 if m.y < EDGE_PX else (1.0 if m.y > s.y - EDGE_PX else 0.0))
	if dir != Vector2.ZERO:
		position += dir * PAN_SPEED_PX * delta / zoom.x
		_clamp()


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _dragging:
		position -= event.relative / zoom.x
		_clamp()
		return
	if not event is InputEventMouseButton:
		return
	if event.button_index == MOUSE_BUTTON_MIDDLE:
		_dragging = event.pressed
		return
	if event.is_action_pressed("zoom_in"):
		_zoom_at(event.position, ZOOM_STEP)
	elif event.is_action_pressed("zoom_out"):
		_zoom_at(event.position, 1.0 / ZOOM_STEP)


## screen_pos(커서) 아래의 지점이 줌 후에도 같은 화면 위치에 남도록 확대·축소한다.
func _zoom_at(screen_pos: Vector2, factor: float) -> void:
	var offset := screen_pos - get_viewport().get_visible_rect().size / 2.0
	var world_under_cursor := position + offset / zoom.x
	var z := clampf(zoom.x * factor, ZOOM_MIN, ZOOM_MAX)
	zoom = Vector2(z, z)
	position = world_under_cursor - offset / z
	_clamp()


func _clamp() -> void:
	if bounds.has_area():
		position = position.clamp(bounds.position, bounds.end)
