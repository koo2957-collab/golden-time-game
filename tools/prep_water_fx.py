# 물줄기 그림 (사용자 제공 참고 그림: 직사·분무의 옆모습과 맞은 자리)을 잘라 투명 배경 흰 물 그림으로 만든다 (시스템 Python + Pillow).
# 실행: python tools/prep_water_fx.py "<참고 그림 폴더>"
#   결과: art/fx/water_jet.png (직사 줄기, 왼쪽 = 관창), water_splash.png (직사가 맞은 자리),
#         water_fog.png (분무 원뿔, 왼쪽 = 관창), water_fog_splash.png (분무가 닿은 자리) + art/fx/fx.json "water"
# 배경이 밝은 회색이고 물이 흰색이라, 배경보다 밝은 만큼을 불투명도로 쓴다 (색은 흰색 — 게임에서 물색을 곱한다).
import json
import os
import sys
from PIL import Image, ImageChops

SRC = sys.argv[1] if len(sys.argv) > 1 else "."
OUT = os.path.join(os.path.dirname(__file__), "..", "art", "fx")
# 이름: (원본 2400x1792 에서 자를 사각형, 저장 크기, 배경보다 이만큼 밝으면 완전 불투명)
# 분무는 배경과 밝기 차이가 작아(옅은 안개) 더 크게 키운다
CUTS = {
    "water_jet": ((858, 340, 1640, 610), (512, 176), 44),
    "water_splash": ((108, 168, 696, 768), (256, 256), 44),
    "water_fog": ((928, 1050, 1580, 1660), (384, 360), 20),
    "water_fog_splash": ((72, 1032, 744, 1680), (256, 248), 24),
}


def main():
    src = Image.open(os.path.join(SRC, "소방호스 물줄기.png")).convert("RGB")
    meta = {}
    for name, (box, size, span) in CUTS.items():
        crop = src.crop(box).resize(size, Image.LANCZOS)
        lum = crop.convert("L")
        hist = lum.histogram()
        bg = max(range(256), key=lambda v: hist[v])  # 가장 흔한 밝기 = 배경
        alpha = lum.point(lambda v: int(255 * min(1.0, max(0.0, (v - bg - 3) / float(span))) ** 0.75))
        # 옅은 물안개는 배경(무채색 회색)보다 밝지 않고 푸르스름하다 → 파랑 - 빨강 차이도 불투명도로
        r, g, bl = crop.split()
        blue = ImageChops.subtract(bl, r).point(lambda v: int(255 * min(1.0, max(0.0, (v - 2) / 12.0)) * 0.8))
        alpha = ImageChops.lighter(alpha, blue)
        out = Image.new("RGBA", size, (255, 255, 255, 0))
        out.putalpha(alpha)
        out.save(os.path.join(OUT, name + ".png"))
        meta[name] = {"w": size[0], "h": size[1]}
        print(name, size, "bg", bg)
    path = os.path.join(OUT, "fx.json")
    fx = json.load(open(path, encoding="utf-8"))
    fx["water"] = {"files": meta, "source": "사용자 제공 참고 그림(소방호스 물줄기: 직사·분무) — tools/prep_water_fx.py 로 잘라 투명 배경으로"}
    json.dump(fx, open(path, "w", encoding="utf-8"), ensure_ascii=False, indent=2, sort_keys=True)


main()
