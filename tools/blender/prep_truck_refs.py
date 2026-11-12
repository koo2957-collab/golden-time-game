# 차량 참고 그림(사용자 제공: 앞·옆·뒤 정면 그림 한 장)에서 면별 그림을 잘라 낸다 (시스템 Python + Pillow).
# 실행: python tools/blender/prep_truck_refs.py "<참고 그림 폴더>"
#   결과: art_source/vehicle_refs/<이름>_<front|side|side_r|rear>.png (bake.py 의 photo 차량이 쓴다)
# 영역은 2400x1792 원본 기준의 대략적인 사각형 — 그 안에서 차체(채도 높거나 어두운 픽셀)의 테두리로 다시 맞춘다.
# 배경(밝은 회색)은 가장자리에서 번져 들어가며 지우고, 위쪽은 은색·아래쪽(차체 밑)은 어두운 색으로 채운다 (상자 면에 입혔을 때 회색 배경이 묻지 않게).
import os
import sys
from PIL import Image, ImageDraw

SRC = sys.argv[1] if len(sys.argv) > 1 else "."
OUT = os.path.join(os.path.dirname(__file__), "..", "..", "art_source", "vehicle_refs")
MARK = (255, 0, 255)

# 이름: (파일, {면: (x0, y0, x1, y1)})
REFS = {
    "pump": ("펌프차.png", {"front": (100, 90, 780, 800), "side": (850, 130, 2330, 800), "rear": (1700, 960, 2330, 1710)}),
    "tanker": ("탱크차.png", {"front": (60, 110, 760, 795), "side": (780, 120, 2340, 795), "side_r": (120, 960, 1720, 1685), "rear": (1740, 960, 2330, 1685)}),
    "rescue": ("구조공작차.png", {"front": (100, 120, 780, 830), "side": (820, 150, 2320, 830), "rear": (830, 930, 1620, 1665)}),
}


def body_bbox(im):
    hsv = im.convert("HSV")
    h, s, v = hsv.split()
    sat = s.point(lambda x: 255 if x > 90 else 0)
    dark = v.point(lambda x: 255 if x < 105 else 0)
    from PIL import ImageChops
    return ImageChops.lighter(sat, dark).getbbox()


def is_bg(px):
    r, g, b = px[:3]
    return min(r, g, b) > 178 and max(r, g, b) - min(r, g, b) < 14


def clear_bg(im):
    w, h = im.size
    px = im.load()
    seeds = [(x, 0) for x in range(0, w, 6)] + [(x, h - 1) for x in range(0, w, 6)] + \
        [(0, y) for y in range(0, h, 6)] + [(w - 1, y) for y in range(0, h, 6)]
    for xy in seeds:
        if px[xy] != MARK and is_bg(px[xy]):
            ImageDraw.floodfill(im, xy, MARK, thresh=16)
    px = im.load()
    for y in range(h):
        fill = (38, 38, 42) if y > h * 0.8 else (158, 161, 166)
        for x in range(w):
            if px[x, y] == MARK:
                px[x, y] = fill
    return im


def main():
    os.makedirs(OUT, exist_ok=True)
    for name, (fname, views) in REFS.items():
        src = Image.open(os.path.join(SRC, fname)).convert("RGB")
        for view, box in views.items():
            crop = src.crop(box)
            bb = body_bbox(crop)
            crop = crop.crop(bb)
            crop = clear_bg(crop)
            if crop.width > 1024:
                crop = crop.resize((1024, round(crop.height * 1024 / crop.width)), Image.LANCZOS)
            path = os.path.join(OUT, "%s_%s.png" % (name, view))
            crop.save(path)
            print(name, view, crop.size)


main()
