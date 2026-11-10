class_name FireGlowLayer
extends Node2D
## 불빛 번짐 (P15-FX, 실시간 셰이더 shaders/fire_glow.gdshader). 지금 층의 보이는 타는 칸마다 바닥에 주황빛 타원을 덧칠한다.
## FloorLayer가 자식으로 두고 매 프레임 spots를 채운다. 덧칠(가산)이라 벽·대원 위에 비쳐도 자연스럽다.

## [화면 위치, 크기(px), 세기 0~1, 칸 번호]
var spots: Array = []
var _white: ImageTexture


func _ready() -> void:
	var m := ShaderMaterial.new()
	m.shader = load("res://shaders/fire_glow.gdshader")
	material = m
	var img := Image.create_empty(2, 2, false, Image.FORMAT_RGBA8)
	img.fill(Color.WHITE)
	_white = ImageTexture.create_from_image(img)


func _draw() -> void:
	for s: Array in spots:
		var at: Vector2 = s[0]
		var size: float = s[1]
		var id := int(s[3])
		# 정점 색: r·g = 칸 번호(깜빡임을 칸마다 다르게), a = 세기
		var col := Color(fmod(id * 0.0103, 1.0), fmod(id * 0.0371, 1.0), 0.0, clampf(float(s[2]), 0.0, 1.0))
		draw_texture_rect(_white, Rect2(at - Vector2(size, size * 0.6) * 0.5, Vector2(size, size * 0.6)), false, col)
