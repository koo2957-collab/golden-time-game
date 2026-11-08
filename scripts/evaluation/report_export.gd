class_name ReportExport
extends RefCounted
## 교육 결과 출력 (기획안 8-1 ⑤ "PDF·CSV", R12): 인쇄용 HTML(브라우저에서 PDF로 저장) + 결과 CSV 한 줄.
## HTML에는 시나리오·등급·5축 점수·판정 항목·판단 요청 해설·틀린 SOP 조항이, CSV에는 교관이 모아 볼 요약이 들어간다.

const EXPORT_DIR := "user://export"
const CSV_NAME := "results.csv"


## 인쇄용 HTML 문자열
static func html(report: Dictionary) -> String:
	var h: PackedStringArray = []
	h.append("<!doctype html><html lang=\"ko\"><head><meta charset=\"utf-8\"><title>디브리핑 — %s</title>" % _esc(str(report.get("scenario_title", ""))))
	h.append("<style>body{font-family:'Malgun Gothic',sans-serif;margin:24px;color:#111}h1{font-size:22px}h2{font-size:17px;border-bottom:1px solid #999;margin-top:20px}"
		+ "table{border-collapse:collapse;width:100%}td,th{border:1px solid #bbb;padding:4px 6px;font-size:13px;text-align:left;vertical-align:top}"
		+ ".bad{color:#b91c1c}.good{color:#15803d}.dim{color:#555;font-size:12px}@media print{button{display:none}}</style></head><body>")
	h.append("<button onclick=\"window.print()\">인쇄 / PDF로 저장</button>")
	h.append("<h1>디브리핑 — %s</h1>" % _esc(str(report.get("scenario_title", ""))))
	h.append("<p>등급 <b>%s</b> · %.1f점 · %s 모드 · 난이도 %s · 활동 시간 %s · %s</p>" % [report.get("grade", ""), float(report.get("points", 0.0)),
		_esc(str(report.get("mode", ""))), _esc(str(report.get("difficulty", ""))), _clock(float(report.get("end_time_s", 0.0))), _esc(str(report.get("end_reason", "")))])
	if bool(report.get("capped", false)):
		h.append("<p class=\"bad\">등급 상한: %s</p>" % _esc("; ".join(PackedStringArray(report.get("cap_reasons", [])))))
	h.append("<h2>5축 점수</h2><table><tr><th>축</th><th>점수</th></tr>")
	for a: Dictionary in report.get("axes", []):
		h.append("<tr><td>%s</td><td>%s</td></tr>" % [_esc(str(a.name)), "%d%%" % roundi(float(a.score) * 100.0) if a.applicable else "해당 없음"])
	h.append("</table><h2>판정 항목 (SOP)</h2><table><tr><th>SOP</th><th>항목</th><th>점수</th><th>내용</th></tr>")
	for r: Dictionary in report.get("rules", []):
		if not r.get("applicable", false):
			continue
		var cls := "good" if float(r.score) >= 0.8 else ("bad" if float(r.score) < 0.5 else "")
		h.append("<tr><td>%s</td><td>%s</td><td class=\"%s\">%d%%</td><td>%s</td></tr>" % [_esc(str(r.sop)), _esc(str(r.title)), cls, roundi(float(r.score) * 100.0), _esc(str(r.get("detail", "")))])
	h.append("</table>")
	var cards: Array = report.get("card_lines", [])
	if not cards.is_empty():
		h.append("<h2>판단 요청 해설</h2><ul>")
		for l in cards:
			h.append("<li>%s</li>" % _esc(str(l)))
		h.append("</ul>")
	var intel: Array = report.get("intel_lines", [])
	if not intel.is_empty():
		h.append("<h2>도면과 구조 정보</h2><ul>")
		for l in intel:
			h.append("<li>%s</li>" % _esc(str(l)))
		h.append("</ul>")
	var growth: Array = report.get("growth_lines", [])
	if not growth.is_empty():
		h.append("<h2>대원 성장</h2><ul>")
		for l in growth:
			h.append("<li>%s</li>" % _esc(str(l)))
		h.append("</ul>")
	h.append("<h2>틀린 SOP 조항</h2><p>%s</p>" % _esc(", ".join(wrong_sops(report))))
	h.append("<p class=\"dim\">결과는 지도·개선 용도로만 씁니다 (SOP 113-3.1.6). 판정 기준값 중 '추정'은 현장 검수 전 값입니다.</p></body></html>")
	return "\n".join(h)


## 점수가 절반 아래인 판정 항목의 SOP 조항 (중복 없이)
static func wrong_sops(report: Dictionary) -> PackedStringArray:
	var out: PackedStringArray = []
	for r: Dictionary in report.get("rules", []):
		if r.get("applicable", false) and float(r.score) < 0.5 and not str(r.sop) in out:
			out.append(str(r.sop))
	return out


## CSV 한 줄: 저장 시각, 시나리오, 모드, 난이도, 등급, 점수, 5축, 틀린 SOP
static func csv_line(report: Dictionary) -> String:
	var cols: PackedStringArray = [str(report.get("saved_at", Time.get_datetime_string_from_system(false, true))), str(report.get("scenario_title", "")),
		str(report.get("mode", "")), str(report.get("difficulty", "")), str(report.get("grade", "")), "%.1f" % float(report.get("points", 0.0))]
	for a: Dictionary in report.get("axes", []):
		cols.append("%d" % roundi(float(a.score) * 100.0) if a.applicable else "")
	cols.append(" ".join(wrong_sops(report)))
	return ",".join(Array(cols).map(func(c: String) -> String: return "\"%s\"" % c.replace("\"", "'")))


## HTML 파일을 저장하고 결과 CSV에 한 줄 더한다. HTML 경로를 돌려준다 (실패하면 "")
static func save(report: Dictionary, dir := EXPORT_DIR) -> String:
	DirAccess.make_dir_recursive_absolute(dir)
	var stamp := Time.get_datetime_string_from_system(false, false).replace(":", "-")
	var path := "%s/%s_%s.html" % [dir, report.get("scenario_id", "scenario"), stamp]
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		return ""
	f.store_string(html(report))
	f.close()
	var csv_path := "%s/%s" % [dir, CSV_NAME]
	var new_file := not FileAccess.file_exists(csv_path)
	var c := FileAccess.open(csv_path, FileAccess.READ_WRITE if not new_file else FileAccess.WRITE)
	if c:
		if new_file:
			# 엑셀에서 한글이 깨지지 않게 BOM과 머리줄
			c.store_string("﻿\"저장 시각\",\"시나리오\",\"모드\",\"난이도\",\"등급\",\"점수\",\"대원 안전\",\"인명구조\",\"재산 보호\",\"화재 안정화\",\"SOP 준수\",\"틀린 SOP\"\n")
		else:
			c.seek_end()
		c.store_string(csv_line(report) + "\n")
		c.close()
	return path


static func _esc(s: String) -> String:
	return s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")


static func _clock(s: float) -> String:
	return "%02d:%02d" % [int(s) / 60, int(s) % 60]
