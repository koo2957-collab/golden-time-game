extends RefCounted
## 연기 읽기 (2026-11-24 사용자 결정): 개구부로 나오는 연기의 색·속도·뻗는 길이를 그 방의 시뮬레이션 값으로 정한다.
## 화면 계산만 한다. 수치는 data/ui/smoke_look.json (교재 근거는 그 파일의 note).
##   색: 짙기(가시거리)·산소 부족·상부층 온도가 클수록 흰색 → 회색 → 검은색. 방수가 열을 빼앗으면 흰 수증기가 섞인다
##   속도·길이: 상부층이 뜨거울수록 빠르게 뿜어 나오고 멀리 뻗는다 (부력 속도 ∝ √온도차). 식은 연기는 느리게 떠오른다
## class_name 을 쓰지 않는다 (새 이름은 편집기 가져오기 전에는 등록되지 않는다) — preload 해서 쓴다.

const PATH := "res://data/ui/smoke_look.json"

static var _style: Dictionary = {}


static func style() -> Dictionary:
	if _style.is_empty():
		var data: Variant = JsonData.load_file(PATH)
		if data is Dictionary:
			for key: String in data:
				if data[key] is Dictionary and (data[key] as Dictionary).has("value"):
					_style[key] = data[key]["value"]
	return _style


static func _num(key: String, fallback: float) -> float:
	return float(style().get(key, fallback))


static func _col(key: String, fallback: Color) -> Color:
	var v: Variant = style().get(key, null)
	if v is Array and (v as Array).size() >= 3:
		return Color(float(v[0]), float(v[1]), float(v[2]))
	return fallback


## 방이 내는 연기의 모습 {color, dark 0~1, heat 0~1, steam 0~1, rate 재생 배율, reach 뻗는 길이 배율}
static func look(fire: FireSim, c: Compartment) -> Dictionary:
	var dens := 1.0 - clampf(fire.visibility_m(c) / maxf(0.1, _num("visibility_ref_m", 10.0)), 0.0, 1.0)
	var o2_full := _num("o2_full", 0.23)
	var lack := clampf((o2_full - c.y_o2) / maxf(0.001, o2_full - _num("o2_low", 0.12)), 0.0, 1.0)
	var t_amb := _num("t_ambient_c", 20.0)
	var heat := clampf((c.t_upper - t_amb) / maxf(1.0, _num("t_hot_c", 450.0) - t_amb), 0.0, 1.0)
	var dark := clampf(_num("w_density", 0.45) * dens + _num("w_o2", 0.4) * lack + _num("w_heat", 0.35) * heat, 0.0, 1.0)
	var white := _col("white", Color(0.86, 0.86, 0.88))
	var gray := _col("gray", Color(0.52, 0.52, 0.54))
	var black := _col("black", Color(0.1, 0.1, 0.11))
	var color := white.lerp(gray, dark * 2.0) if dark < 0.5 else gray.lerp(black, (dark - 0.5) * 2.0)
	var steam := clampf(c.cooling_kw / maxf(1.0, _num("steam_ref_kw", 400.0)), 0.0, 1.0) * _num("steam_max", 0.85)
	if steam > 0.0:
		color = color.lerp(_col("steam", Color(0.95, 0.96, 0.97)), steam)
	var speed := sqrt(heat)
	return {"color": color, "dark": dark, "heat": heat, "steam": steam,
		"rate": lerpf(_num("rate_min", 0.45), _num("rate_max", 1.8), speed),
		"reach": lerpf(_num("reach_min", 0.65), _num("reach_max", 1.5), speed)}
