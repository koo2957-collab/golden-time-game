# 무전 장면 그림 준비 (2026-11-14, G3): 사용자 제공 그림에서 말하는 사람 상반신을 잘라 내고, 장면 바탕의 먹물 번짐을 만든다.
# 실행: python tools/prep_radio_art.py <소방관 캐릭터.png> <출력 폴더 art>
#   art/portraits/crew_fire·rescue·ems·command.png — 정면 상반신, 배경 투명, 헬멧을 출동대 종류 색으로 (data/art.json helmet_color)
#   art/ui/ink_blot.png — 가운데가 불투명하고 가장자리가 번진 검은 얼룩 (프로스트펑크 사건 창 방식, 사용자 예시 그림)
# 필요: pillow, numpy
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# 원본(2730×1536)에서 정면 그림의 상반신 영역 (왼쪽, 위, 오른쪽, 아래)
BUST = (330, 120, 790, 660)
# 헬멧 영역 (상반신 그림 안 좌표): 이 안의 어두운 칸을 종류 색으로 물들인다
HELMET = (120, 10, 350, 150)
KINDS = {"fire": None, "rescue": (255, 122, 26), "ems": (245, 245, 245), "command": (31, 111, 229)}
SIZE = 512


def cut_background(img: Image.Image) -> Image.Image:
    """회색 배경을 가장자리에서부터 번져 가며 지운다 (인물 안의 회색 — 공기통·끈 — 은 남는다)"""
    rgb = img.convert("RGB")
    w, h = rgb.size
    mask = Image.new("L", (w + 2, h + 2), 0)
    work = rgb.copy()
    marker = (255, 0, 255)
    for seed in [(0, 0), (w - 1, 0), (0, h // 2), (w - 1, h // 2), (w // 2, 0), (4, h - 4), (w - 5, h - 5), (0, h - 1), (w - 1, h - 1)]:
        ImageDraw.floodfill(work, seed, marker, thresh=26)
    a = np.array(work)
    bg = (a[:, :, 0] == 255) & (a[:, :, 1] == 0) & (a[:, :, 2] == 255)
    alpha = Image.fromarray(np.where(bg, 0, 255).astype(np.uint8), "L")
    # 가장자리의 회색 테를 한 칸 깎고 부드럽게
    alpha = alpha.filter(ImageFilter.MinFilter(3)).filter(ImageFilter.GaussianBlur(1.2))
    out = rgb.convert("RGBA")
    out.putalpha(alpha)
    return out


def tint_helmet(img: Image.Image, color) -> Image.Image:
    if color is None:
        return img
    a = np.array(img).astype(np.float32)
    x0, y0, x1, y1 = HELMET
    region = a[y0:y1, x0:x1, :3]
    lum = region.mean(axis=2)
    sat = region.max(axis=2) - region.min(axis=2)
    # 헬멧 겉면: 어둡고 색이 거의 없는 칸 (노란 반사띠·금색 표지는 남긴다)
    shell = (lum < 95) & (sat < 38)
    shade = np.clip(lum / 70.0, 0.18, 1.25)[..., None]
    tinted = np.clip(np.array(color, dtype=np.float32)[None, None, :] * shade, 0, 255)
    region[shell] = tinted[shell]
    a[y0:y1, x0:x1, :3] = region
    return Image.fromarray(a.astype(np.uint8), "RGBA")


def portraits(src: str, out_dir: str) -> None:
    sheet = Image.open(src)
    bust = cut_background(sheet.crop(BUST))
    # 아래쪽은 투명하게 사라지게 (장면의 먹물 바탕에 묻힌다)
    w, h = bust.size
    fade = np.ones((h, w), dtype=np.float32)
    start = int(h * 0.72)
    fade[start:, :] = np.linspace(1.0, 0.0, h - start)[:, None]
    for key, color in KINDS.items():
        img = tint_helmet(bust.copy(), color)
        arr = np.array(img).astype(np.float32)
        arr[:, :, 3] *= fade
        img = Image.fromarray(arr.astype(np.uint8), "RGBA")
        scale = SIZE / max(w, h)
        img = img.resize((round(w * scale), round(h * scale)), Image.LANCZOS)
        canvas = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
        canvas.paste(img, ((SIZE - img.width) // 2, SIZE - img.height), img)
        path = os.path.join(out_dir, "portraits", "crew_%s.png" % key)
        os.makedirs(os.path.dirname(path), exist_ok=True)
        canvas.save(path)
        print("portrait", path)


def ink_blot(out_dir: str, w: int = 1400, h: int = 760, seed: int = 7) -> None:
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    cx, cy = w * 0.5, h * 0.5
    ang = np.arctan2((yy - cy) / (h * 0.5), (xx - cx) / (w * 0.5))
    rad = np.sqrt(((xx - cx) / (w * 0.5)) ** 2 + ((yy - cy) / (h * 0.5)) ** 2)
    # 가장자리가 들쭉날쭉한 덩어리: 각도에 따라 반지름이 달라진다 (여러 주기의 물결을 더함)
    edge = np.full_like(ang, 0.88)
    for k, amp in ((3, 0.06), (5, 0.05), (9, 0.04), (17, 0.03), (31, 0.02)):
        edge += amp * np.sin(ang * k + rng.uniform(0, 6.28))
    body = np.clip((edge - rad) / 0.07, 0.0, 1.0)
    img = Image.fromarray((body * 255).astype(np.uint8), "L")
    draw = ImageDraw.Draw(img)
    # 튄 먹물 방울: 가장자리 바깥쪽에 크고 작은 점
    for _ in range(150):
        a = rng.uniform(0, 6.28)
        r = rng.uniform(0.86, 1.04)
        px = cx + np.cos(a) * r * w * 0.5
        py = cy + np.sin(a) * r * h * 0.5
        size = rng.uniform(2, 14) * (1.2 - r) * 2.6
        tone = int(rng.uniform(110, 255))
        draw.ellipse((px - size, py - size * rng.uniform(0.6, 1.0), px + size, py + size * rng.uniform(0.6, 1.0)), fill=tone)
    # 붓 자국: 가장자리에서 바깥으로 뻗는 짧은 줄
    for _ in range(46):
        a = rng.uniform(0, 6.28)
        r0 = rng.uniform(0.8, 0.9)
        r1 = r0 + rng.uniform(0.04, 0.13)
        p0 = (cx + np.cos(a) * r0 * w * 0.5, cy + np.sin(a) * r0 * h * 0.5)
        p1 = (cx + np.cos(a) * r1 * w * 0.5, cy + np.sin(a) * r1 * h * 0.5)
        draw.line((p0, p1), fill=int(rng.uniform(120, 230)), width=int(rng.uniform(3, 11)))
    img = img.filter(ImageFilter.GaussianBlur(3.0))
    alpha = np.array(img).astype(np.float32) / 255.0
    # 번진 결: 거친 무늬를 곱해 가장자리만 얼룩지게 (가운데는 온전히 불투명)
    grain = Image.fromarray((rng.uniform(0.35, 1.0, (h // 36, w // 36)) * 255).astype(np.uint8), "L").resize((w, h), Image.BICUBIC)
    g = np.array(grain).astype(np.float32) / 255.0
    core = np.clip((0.8 - rad) / 0.1, 0.0, 1.0)
    alpha = alpha * (core + (1.0 - core) * g)
    out = np.zeros((h, w, 4), dtype=np.uint8)
    out[:, :, 0] = 9
    out[:, :, 1] = 11
    out[:, :, 2] = 15
    out[:, :, 3] = np.clip(alpha * 247, 0, 255).astype(np.uint8)
    path = os.path.join(out_dir, "ui", "ink_blot.png")
    os.makedirs(os.path.dirname(path), exist_ok=True)
    Image.fromarray(out, "RGBA").save(path)
    print("blot", path)


if __name__ == "__main__":
    portraits(sys.argv[1], sys.argv[2])
    ink_blot(sys.argv[2])
