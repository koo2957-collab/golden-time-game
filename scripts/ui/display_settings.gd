class_name DisplaySettings
extends RefCounted
## 화면 설정 (user://display.json). 시작 화면의 '화면 설정'에서 바꾼다.
##   resolution: "hd" 1280×720 / "hd_plus" 1600×900 / "fhd" 1920×1080 — 창 모드의 창 크기
##   fullscreen: 전체 화면 여부. 전체 화면은 늘 모니터 해상도로 띄운다
##     (2D 화면이라 그래픽카드 부담은 작다. 저사양 PC에서 부담이 큰 쪽은 CPU라 fps 상한이 더 효과적이다)
##   fps: 화면 갱신 상한 (60 / 30). 30이면 그리는 횟수가 절반이라 저사양 PC의 CPU 부담이 크게 준다.
##   low_spec: 저사양 모드 (기획안 9-5, P14) — 30프레임 상한 + 효과 축소(단면 보기에서 쌓는 층 수를 줄임)
## 화면 배치는 늘 1920×1080 기준으로 만들고, 실제 크기에 맞게 줄이거나 늘린다 (project.godot stretch).
## 실제 게임(메인 씬)에서만 적용한다. 자동 테스트는 늘 project.godot의 기본 창으로 돈다.

const PATH := "user://display.json"
const RESOLUTIONS := {
	"hd": Vector2i(1280, 720),
	"hd_plus": Vector2i(1600, 900),
	"fhd": Vector2i(1920, 1080),
}
const RESOLUTION_ORDER: Array[String] = ["hd", "hd_plus", "fhd"]
const RESOLUTION_NAMES := {
	"hd": "HD (1280×720)",
	"hd_plus": "HD+ (1600×900)",
	"fhd": "풀HD (1920×1080)",
}
const FPS_OPTIONS: Array[int] = [60, 30]
## 파일이 없을 때의 값 = project.godot 기본 (창 1600×900)
const DEFAULTS := {"resolution": "hd_plus", "fullscreen": false, "fps": 60, "low_spec": false}
## 창 테두리·제목 표시줄 여유 (px). 창이 화면보다 크면 최대화한다
const WINDOW_MARGIN := Vector2i(16, 64)

static var _applied := false
## 저사양 모드가 켜져 있는가 (화면 코드가 효과를 줄일 때 본다)
static var low_spec := false


## 저장된 설정 (없거나 잘못된 값은 기본값으로)
static func load_settings() -> Dictionary:
	var out := DEFAULTS.duplicate()
	if FileAccess.file_exists(PATH):
		var data: Variant = JsonData.load_file(PATH)
		if data is Dictionary:
			if RESOLUTIONS.has(str(data.get("resolution", ""))):
				out.resolution = str(data.resolution)
			out.fullscreen = bool(data.get("fullscreen", out.fullscreen))
			if int(data.get("fps", 0)) in FPS_OPTIONS:
				out.fps = int(data.fps)
			out.low_spec = bool(data.get("low_spec", false))
	return out


static func save_settings(data: Dictionary) -> bool:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(data, "  "))
	return true


## 프로그램을 켤 때 한 번 적용한다 (다시 시작·다시 하기로 씬을 다시 불러와도 창을 건드리지 않는다).
## 저장된 파일이 없으면 아무것도 바꾸지 않는다.
static func apply_once(window: Window) -> void:
	if _applied:
		return
	_applied = true
	if FileAccess.file_exists(PATH):
		apply(window, load_settings())


static func apply(window: Window, s: Dictionary) -> void:
	var size: Vector2i = RESOLUTIONS[s.resolution]
	low_spec = bool(s.get("low_spec", false))
	Engine.max_fps = 30 if low_spec else int(s.fps)
	if s.fullscreen:
		window.mode = Window.MODE_FULLSCREEN
		return
	window.mode = Window.MODE_WINDOWED
	var usable := DisplayServer.screen_get_usable_rect(window.current_screen)
	if size.x + WINDOW_MARGIN.x > usable.size.x or size.y + WINDOW_MARGIN.y > usable.size.y:
		window.mode = Window.MODE_MAXIMIZED
		return
	window.size = size
	window.position = usable.position + (usable.size - size) / 2
