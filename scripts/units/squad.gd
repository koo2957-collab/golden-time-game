class_name Squad
extends RefCounted
## 출동대 (예: 진압1, 구조1). 여러 조로 구성된다.

var id := 0
var key := ""
var name := ""
var type := ""
var color := Color.WHITE
var crews: Array[Crew] = []
