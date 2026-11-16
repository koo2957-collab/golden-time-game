class_name Squad
extends RefCounted
## 출동대 (예: 진압1, 구조1). 분대는 조 하나로 같이 움직이고, 4명 분대는 2인 1조 둘로 나눌 수 있다.

var id := 0
var key := ""
var name := ""
var type := ""
## 선착 (처음부터 현장) / 후착 (지원·후속 도착). 후착 진압대는 명령칸이 다르다 (포위·경계관창)
var arrival := "선착"
var color := Color.WHITE
## 지금 활동 중인 조 (조 번호 순)
var crews: Array[Crew] = []
## 합쳐서 비어 있는 조 (다시 나눌 때 같은 조 id로 되살린다). 없으면 null
var spare: Crew
## 처음 나눌 때의 조원 순서 (대원 id) — 둘 다 쉬는 채로 합치면 이 순서로 되돌린다
var home: Array[int] = []
