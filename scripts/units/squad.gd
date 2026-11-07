class_name Squad
extends RefCounted
## 출동대 (예: 진압1, 구조1). 여러 조로 구성된다.

var id := 0
var key := ""
var name := ""
var type := ""
## 선착 (처음부터 현장) / 후착 (지원·후속 도착). 후착 진압대는 명령칸이 다르다 (포위·경계관창)
var arrival := "선착"
var color := Color.WHITE
var crews: Array[Crew] = []
