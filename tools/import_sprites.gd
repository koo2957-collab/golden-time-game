extends SceneTree
## P15: Blender로 구운 프레임(art_source/baked, tools/blender/bake.py)을 종류별 아틀라스로 묶는다.
## 실행: godot --headless --path . -s res://tools/import_sprites.gd [-- 종류/이름]
##   art_source/baked/<종류>/<이름>/meta.json + <동작>_<방향>_<프레임>.png (+ _stripe.png)
##   → res://art/sprites/<종류>_<이름>_<쪽>.png (아틀라스) + res://art/sprites/<종류>_<이름>.json (자른 위치·기준점)
## 프레임마다 투명한 둘레를 잘라내 메모리를 줄인다. 그림의 기준점(발밑)은 meta.json anchor.
## 게임은 data/art.json에서 어떤 대상에 어떤 묶음을 쓰는지 읽는다 (scripts/ui/sprite_art.gd).

const SRC := "art_source/baked"
const DST := "res://art/sprites"
const PAGE_W := 2048
const PAGE_MAX_H := 4096
const PAD := 1


func _initialize() -> void:
	var only := ""
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		only = args[0]
	var root := ProjectSettings.globalize_path("res://") + SRC
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(DST))
	var total_bytes := 0
	var count := 0
	for kind in DirAccess.get_directories_at(root):
		for name in DirAccess.get_directories_at(root + "/" + kind):
			if only != "" and only != "%s/%s" % [kind, name]:
				continue
			var bytes := _pack(root + "/" + kind + "/" + name, "%s_%s" % [kind, name])
			if bytes > 0:
				total_bytes += bytes
				count += 1
	print("아틀라스 %d묶음, 텍스처 메모리 약 %.1f MB (RGBA8, 압축 전)" % [count, total_bytes / 1048576.0])
	quit()


## 한 묶음을 아틀라스로. 텍스처 바이트 수를 돌려준다 (없으면 0)
func _pack(folder: String, id: String) -> int:
	var meta_text := FileAccess.get_file_as_string(folder + "/meta.json")
	if meta_text == "":
		return 0
	var meta: Dictionary = JSON.parse_string(meta_text)
	var dirs := int(meta.directions)
	var anchor := Vector2i(int(meta.anchor[0]), int(meta.anchor[1]))
	# 1) 프레임을 읽어 둘레를 잘라 둔다
	var pieces: Array[Dictionary] = []  # {key, img, offset}
	for anim: String in meta.anims:
		var frames := int(meta.anims[anim].frames)
		for d in dirs:
			for f in frames:
				for layer in ["", "_stripe"]:
					var path := "%s/%s_%d_%d%s.png" % [folder, anim, d, f, layer]
					if not FileAccess.file_exists(path):
						continue
					var img := Image.load_from_file(path)
					if img == null:
						continue
					img.convert(Image.FORMAT_RGBA8)
					var used := img.get_used_rect()
					if used.size.x == 0 or used.size.y == 0:
						used = Rect2i(0, 0, 1, 1)
					pieces.append({"anim": anim, "dir": d, "frame": f, "layer": layer, "img": img.get_region(used),
						"offset": used.position - anchor})
	if pieces.is_empty():
		return 0
	# 2) 줄(선반) 쌓기: 높이 순으로 왼쪽부터, 넘치면 다음 줄, 쪽 높이를 넘으면 다음 쪽
	var order := range(pieces.size())
	order.sort_custom(func(a: int, b: int) -> bool: return pieces[a].img.get_height() > pieces[b].img.get_height())
	var pages: Array[Image] = []
	var page_h: Array[int] = []
	var x := 0
	var y := 0
	var row_h := 0
	var page := 0
	var places := {}
	var page_w: Array[int] = [0]
	for i: int in order:
		var im: Image = pieces[i].img
		var w := im.get_width() + PAD
		var h := im.get_height() + PAD
		if x + w > PAGE_W:
			x = 0
			y += row_h
			row_h = 0
		if y + h > PAGE_MAX_H:
			page_h.append(y + row_h)
			page_w.append(0)
			page += 1
			x = 0
			y = 0
			row_h = 0
		places[i] = [page, x, y]
		x += w
		page_w[page] = maxi(page_w[page], x)
		row_h = maxi(row_h, h)
	page_h.append(y + row_h)
	for p in page_h.size():
		# 쓴 만큼만 (2의 거듭제곱으로 맞추지 않는다 — Compatibility 렌더러도 NPOT 텍스처를 쓴다)
		pages.append(Image.create_empty(page_w[p], page_h[p], false, Image.FORMAT_RGBA8))
	# 3) 붙이고 위치 기록
	var anims := {}
	for i in pieces.size():
		var pc: Dictionary = pieces[i]
		var pl: Array = places[i]
		var im: Image = pc.img
		pages[pl[0]].blit_rect(im, Rect2i(Vector2i.ZERO, im.get_size()), Vector2i(pl[1], pl[2]))
		var a: Dictionary = anims.get(pc.anim, {"frames": int(meta.anims[pc.anim].frames), "cells": {}, "stripe": {}})
		var key := "%d_%d" % [pc.dir, pc.frame]
		var cell := [pl[0], pl[1], pl[2], im.get_width(), im.get_height(), pc.offset.x, pc.offset.y]
		if pc.layer == "":
			a.cells[key] = cell
		else:
			a.stripe[key] = cell
		anims[pc.anim] = a
	var page_paths: Array[String] = []
	var bytes := 0
	for p in pages.size():
		var path := "%s/%s_%d.png" % [DST, id, p]
		pages[p].save_png(path)
		page_paths.append(path)
		bytes += pages[p].get_width() * pages[p].get_height() * 4
	var out := {"id": id, "kind": meta.kind, "scale": meta.scale, "frame": meta.frame, "anchor": meta.anchor,
		"directions": dirs, "pages": page_paths, "anims": anims}
	for k in ["nominal", "h_m", "size_m", "type"]:
		if meta.has(k):
			out[k] = meta[k]
	var f := FileAccess.open("%s/%s.json" % [DST, id], FileAccess.WRITE)
	f.store_string(JSON.stringify(out))
	f.close()
	print("  %s: 프레임 %d장 → %d쪽 (%s)" % [id, pieces.size(), pages.size(), ", ".join(pages.map(func(im: Image) -> String: return "%dx%d" % [im.get_width(), im.get_height()]))])
	return bytes

