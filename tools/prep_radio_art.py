# 무전·판단 장면 그림 준비 (2026-11-14, G3): 사용자 제공 그림으로 말하는 사람 그림을 만들고, 장면 바탕의 먹물 번짐을 만든다.
# 실행: python tools/prep_radio_art.py <현장대원 그림> <현장지휘관 그림> <출력 폴더 art>
#   art/portraits/crew_fire·rescue·ems.png — 현장대원(무전 장면): 가장자리가 먹물처럼 번져 바탕에 묻힌다. 헬멧을 출동대 종류 색으로
#   art/portraits/crew_command.png        — 현장지휘관 (지휘관이 거는 무전)
#   art/portraits/half_fire·rescue·ems.png — 조장의 판단 장면: 얼굴의 반쪽만 (프로스트펑크 독백 방식, 사용자 예시 그림)
#   art/ui/ink_blot.png — 가운데가 불투명하고 가장자리가 번진 검은 얼룩 (프로스트펑크 사건 창 방식)
# 필요: pillow, numpy
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

# 현장대원 그림(1024×572)에서 쓸 영역과 얼굴 가운데 세로선
CREW_BOX = (0, 0, 690, 572)
CREW_FACE_X = 352
# 헬멧 겉면 영역 (현장대원 그림 좌표): 이 안의 어두운 칸을 종류 색으로 물들인다
CREW_HELMET = (232, 0, 468, 150)
# 헬멧 색 (data/art.json helmet_color, 2026-11-11 사용자 결정). None = 그림 그대로(검정)
KINDS = {"fire": None, "rescue": (255, 122, 26), "ems": (238, 238, 238)}
SIZE = 640


def ink_mask(w: int, h: int, seed: int, cut_right: bool = False) -> np.ndarray:
    """가장자리가 먹물처럼 번진 알파 (0~1). cut_right: 오른쪽 변은 번지지 않고 곧게 자른다 (반쪽 얼굴)"""
    rng = np.random.default_rng(seed)
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    # 변까지의 거리 (0 = 변, 1 = 가운데)
    dl = xx / (w * 0.5)
    dr = (w - 1 - xx) / (w * 0.5)
    dt = yy / (h * 0.5)
    db = (h - 1 - yy) / (h * 0.5)
    if cut_right:
        dr = np.full_like(dr, 9.0)
    d = np.minimum(np.minimum(dl, dr), np.minimum(dt * 1.6, db * 0.9))
    noise = Image.fromarray((rng.uniform(0.0, 1.0, (max(2, h // 22), max(2, w // 22))) * 255).astype(np.uint8), "L").resize((w, h), Image.BICUBIC)
    n = np.array(noise).astype(np.float32) / 255.0
    fine = Image.fromarray((rng.uniform(0.0, 1.0, (max(2, h // 5), max(2, w // 5))) * 255).astype(np.uint8), "L").resize((w, h), Image.BILINEAR)
    f = np.array(fine).astype(np.float32) / 255.0
    edge = 0.16 + 0.26 * n + 0.05 * f
    m = np.clip((d - edge * 0.35) / (edge * 1.5), 0.0, 1.0)
    # 부드럽게 번지게 (찢긴 종이처럼 보이지 않도록)
    soft = Image.fromarray((m * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(max(3.0, w / 90.0)))
    out = np.array(soft).astype(np.float32) / 255.0
    if cut_right:
        # 곧게 자른 변은 흐려지지 않게 되돌린다
        k = np.clip((w - 1 - xx) / 14.0, 0.0, 1.0)
        out = out * k + m * (1.0 - k)
    return out


def tint_helmet(a: np.ndarray, box, color) -> None:
    if color is None:
        return
    x0, y0, x1, y1 = box
    region = a[y0:y1, x0:x1, :3]
    r, g, b = region[:, :, 0], region[:, :, 1], region[:, :, 2]
    lum = region.mean(axis=2)
    sat = region.max(axis=2) - region.min(axis=2)
    # 헬멧 겉면: 헬멧 모양(위쪽 반 타원) 안의 칸만. 노란 반사띠·금색 표지와 얼굴 가리개(아래쪽 가운데)는 뺀다
    hh, ww = y1 - y0, x1 - x0
    yy, xx = np.mgrid[0:hh, 0:ww].astype(np.float32)
    dome = ((xx - ww * 0.5) / (ww * 0.5)) ** 2 + ((yy - hh * 0.62) / (hh * 0.62)) ** 2
    inside = np.clip((1.0 - dome) / 0.12, 0.0, 1.0)
    visor = (yy > hh * 0.52) & (xx > ww * 0.2) & (xx < ww * 0.86)
    gold = (g > 110) & (r > 120) & (b < g * 0.8)
    weight = inside * (~visor) * (~gold) * np.clip((150.0 - lum) / 50.0, 0.0, 1.0)
    shade = np.clip(lum / 58.0, 0.25, 1.4)[..., None]
    tinted = np.clip(np.array(color, dtype=np.float32)[None, None, :] * shade, 0, 255)
    w3 = weight[..., None]
    a[y0:y1, x0:x1, :3] = region * (1.0 - w3) + tinted * w3


def save(arr: np.ndarray, alpha: np.ndarray, path: str, height: int) -> None:
    out = np.dstack([arr[:, :, :3], np.clip(alpha * 255.0, 0, 255)]).astype(np.uint8)
    img = Image.fromarray(out, "RGBA")
    scale = height / img.height
    img = img.resize((round(img.width * scale), height), Image.LANCZOS)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    print("그림", os.path.basename(path), img.size)


def portraits(crew_src: str, cmd_src: str, out_dir: str) -> None:
    crew = np.array(Image.open(crew_src).convert("RGB")).astype(np.float32)
    x0, y0, x1, y1 = CREW_BOX
    for key, color in KINDS.items():
        a = crew.copy()
        tint_helmet(a, CREW_HELMET, color)
        part = a[y0:y1, x0:x1]
        save(part, ink_mask(part.shape[1], part.shape[0], 11), os.path.join(out_dir, "portraits", "crew_%s.png" % key), SIZE)
        # 판단 장면: 얼굴 가운데선의 왼쪽만 (가운데선은 곧게, 왼쪽은 번지게)
        half = a[:, max(0, CREW_FACE_X - 300):CREW_FACE_X]
        save(half, ink_mask(half.shape[1], half.shape[0], 23, True), os.path.join(out_dir, "portraits", "half_%s.png" % key), SIZE)
    cmd = np.array(Image.open(cmd_src).convert("RGB")).astype(np.float32)
    part = cmd[40:900, 60:960]
    save(part, ink_mask(part.shape[1], part.shape[0], 31), os.path.join(out_dir, "portraits", "crew_command.png"), SIZE)
    half = cmd[40:900, 190:500]
    save(half, ink_mask(half.shape[1], half.shape[0], 37, True), os.path.join(out_dir, "portraits", "half_command.png"), SIZE)


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
    print("그림", os.path.basename(path))


if __name__ == "__main__":
    portraits(sys.argv[1], sys.argv[2], sys.argv[3])
    ink_blot(sys.argv[3])
