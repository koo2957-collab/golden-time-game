# 불꽃·연기 그림 준비 (2026-11-25 사용자 제공 '화염이미지.png' — 흰 바탕의 불 + 검은 연기 세 덩어리, 게임과 같은 내려다보는 시점):
# 블렌더로 구운 불꽃(정면 시점, 뿌옇고 결이 없다) 대신 이 그림에서 불과 연기를 오려 내 게임 그림으로 쓴다.
# 실행: python tools/prep_fire_art.py <화염 그림> <출력 폴더 art> [check <확인용 폴더>]
#   art/fx/fire_s·m·l·xl.png — 불꽃 네 크기 (장을 세로로 쌓은 반복 재생 그림). 그림 아래에서 base_v 높이 = 불 뿌리(바닥 가운데)
#   art/fx/smoke_billow.png  — 불 위로 피어오르는 연기 덩어리 (밝은 회색 — 게임에서 연기 색을 곱한다)
#   art/fx/fx.json 의 "fire_<크기>" · "smoke_billow"
# 움직임: 그림 한 장을 위로 흘러가는 무늬로 조금씩 일그러뜨려 장을 만든다 (뿌리는 고정, 위로 갈수록 크게 일렁인다).
#   무늬가 한 바퀴 돌면 처음과 이어진다. 게임은 이웃한 두 장을 겹쳐 부드럽게 재생한다 (FxArt.draw_flip).
# check: 오려 낸 불·연기를 어두운 바탕 위에 올린 확인용 그림만 저장한다 (art 는 건드리지 않는다)
#
# 스프라이트 시트로 (2026-11-25 사용자 제공 '화염연기 스프라이트 시트이미지.png' — 8 × 6 칸, 불이 붙어 커졌다가 사그라드는 장면들):
#   python tools/prep_fire_art.py <화염 그림> <출력 폴더 art> sheet <시트 그림>
#   불꽃은 시트의 장면들을 그대로 장으로 쓴다 — 장마다 불꽃 모양이 실제로 다르다 (한 장을 일그러뜨린 것보다 살아 있다).
#   시트의 바탕은 투명이 아니라 바둑판 무늬가 그려져 있어, 불꽃(붉고 노란 칸)만 색으로 가려 오려 낸다.
#   연기 덩어리(smoke_billow)는 화염 그림에서 그대로 만든다 (시트의 연기는 바둑판 무늬가 비쳐 쓰지 않는다)
# 필요: pillow, numpy
import json
import os
import sys

import numpy as np
from PIL import Image, ImageFilter

# 장 수: 가장 큰 그림(xl)을 세로로 쌓아도 4096px 을 넘지 않게 (오래된 내장 그래픽의 그림 크기 한도)
FRAMES = 12
SOURCE = "tools/prep_fire_art.py — 사용자 제공 화염이미지.png 에서 오려 일렁임을 더함"

# 그림(2816×1536)에서 불 덩어리마다 쓸 영역 (x0, y0, x1, y1) — 불꽃만 (연기는 색으로 갈라 낸다).
# skip = 그 안에서 뺄 영역 (이웃 덩어리가 걸친 곳)
FIRES = {
    "small": {"box": (1140, 760, 1640, 1400), "skip": []},
    "tall": {"box": (700, 380, 1200, 1140), "skip": []},
    "wide": {"box": (1390, 320, 2110, 1160), "skip": [(1390, 800, 1590, 1160)]},
}
# 게임의 네 크기: 어느 덩어리로, 그림 한 장 크기(px), 나타내는 폭·높이(m — 불꽃 부분), 일렁임 세기
KINDS = {
    "s": {"from": "small", "px": (96, 112), "w": 0.7, "fps": 12.0, "sway": 0.05, "seed": 3},
    "m": {"from": "small", "px": (160, 184), "w": 1.3, "fps": 11.0, "sway": 0.06, "seed": 11},
    "l": {"from": "tall", "px": (208, 304), "w": 2.0, "fps": 10.0, "sway": 0.07, "seed": 23},
    "xl": {"from": "wide", "px": (304, 336), "w": 3.2, "fps": 9.0, "sway": 0.07, "seed": 37},
}
# 연기 덩어리: 그림에서 쓸 영역 (왼쪽 불 위의 연기 기둥)
SMOKE_BOX = (1640, 20, 2300, 400)
SMOKE_PX = (192, 168)


def load(path):
    return np.array(Image.open(path).convert("RGB")).astype(np.float32) / 255.0


def split_layers(rgb):
    """흰 바탕의 그림 → (불꽃 RGBA, 연기 RGBA). 값은 0~1, 색은 바탕을 걷어 낸 제 색"""
    lo = rgb.min(axis=2)
    hi = rgb.max(axis=2)
    # 흰 바탕에서 벗어난 만큼이 불투명도 (흰색에 가까우면 투명)
    alpha = np.clip((1.0 - lo) * 1.15, 0.0, 1.0)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    # 불 기운: 밝고 붉은·노란 칸 (검은 연기는 0)
    fire = np.clip((r - b) * 2.4, 0.0, 1.0) * np.clip((r - 0.35) * 2.2, 0.0, 1.0)
    fire = np.clip(fire * 1.25, 0.0, 1.0)
    # 불꽃 속(흰 노랑)은 바탕색과 가까워 투명하게 잡힌다 → 불꽃 안쪽이면 불투명하게 메운다
    body = Image.fromarray((np.clip(fire * alpha * 3.0, 0, 1) * 255).astype(np.uint8), "L")
    inside = np.array(body.filter(ImageFilter.MaxFilter(9)).filter(ImageFilter.GaussianBlur(6))).astype(np.float32) / 255.0
    inside = np.clip((inside - 0.45) * 3.0, 0.0, 1.0)
    # 메울 곳: 불꽃 안쪽의 밝은 노란 칸 (흰 바탕은 색 기운이 없어 빠진다 — 가장자리에 흰 테두리가 생기지 않게).
    # 깊은 안쪽의 새하얀 칸(색 기운이 없다)도 메운다
    solid = Image.fromarray((inside * 255).astype(np.uint8), "L")
    # 깊은 안쪽 = 안쪽 범위를 구멍(새하얀 칸)까지 메운 뒤 가장자리에서 한참 들어온 곳
    filled = solid.filter(ImageFilter.MaxFilter(31)).filter(ImageFilter.MinFilter(31))
    deep = np.array(filled.filter(ImageFilter.MinFilter(25)).filter(ImageFilter.GaussianBlur(4))).astype(np.float32) / 255.0
    inside = np.maximum(inside, deep)
    core = inside * np.clip((hi - 0.75) * 4.0, 0.0, 1.0) * np.maximum(np.clip((hi - lo) * 9.0, 0.0, 1.0), deep)
    # 색 기운이 옅은 뿌연 빛(불꽃 둘레의 허연 안개)은 옅게
    haze = np.clip((hi - lo) * 3.5 + 0.15, 0.0, 1.0)
    fa = np.clip(np.maximum(alpha * fire * haze, core), 0.0, 1.0)
    # 색: 흰 바탕을 걷어 낸다 (C = a·F + (1-a)·1 → F). 메운 속은 그림 색 그대로 (새하얀 칸은 흰 노랑으로)
    a3 = np.maximum(alpha, 1e-3)[..., None]
    unmixed = np.clip((rgb - (1.0 - a3)) / a3, 0.0, 1.0)
    hot = np.minimum(rgb, np.array([1.0, 0.96, 0.78], dtype=np.float32))
    fcol = unmixed * (1.0 - core[..., None]) + hot * core[..., None]
    flame = np.dstack([fcol, fa])
    sa = np.clip(alpha * (1.0 - fire) * (1.0 - inside), 0.0, 1.0)
    smoke = np.dstack([unmixed, sa])
    return flame, smoke


def crop(layer, box, skips=()):
    x0, y0, x1, y1 = box
    out = layer[y0:y1, x0:x1].copy()
    if skips:
        keep = np.ones(out.shape[:2], dtype=np.float32)
        for sx0, sy0, sx1, sy1 in skips:
            keep[max(0, sy0 - y0):max(0, sy1 - y0), max(0, sx0 - x0):max(0, sx1 - x0)] = 0.0
        # 잘라 낸 경계가 칼로 자른 듯 보이지 않게 흐린다
        soft = np.array(Image.fromarray((keep * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(18))).astype(np.float32) / 255.0
        out[..., 3] *= np.minimum(keep, soft) * np.clip(soft * 2.0 - 1.0, 0.0, 1.0) + 0.0
    return out


def trim(img, pad=6, floor=0.06):
    """투명한 가장자리를 잘라 낸다"""
    ys, xs = np.where(img[..., 3] > floor)
    if ys.size == 0:
        return img
    y0, y1 = max(0, ys.min() - pad), min(img.shape[0], ys.max() + pad + 1)
    x0, x1 = max(0, xs.min() - pad), min(img.shape[1], xs.max() + pad + 1)
    return img[y0:y1, x0:x1]


def keep_main(img, floor=0.12):
    """가장 큰 덩어리만 남긴다 (흩어진 불티·이웃 덩어리 조각을 뺀다) — 큰 덩어리를 흐리게 키운 범위 밖은 지운다"""
    mask = (img[..., 3] > floor).astype(np.uint8)
    h, w = mask.shape
    label = np.zeros((h, w), dtype=np.int32)
    best, best_n, cur = 0, 0, 0
    small = Image.fromarray(mask * 255, "L").resize((max(1, w // 4), max(1, h // 4)), Image.BILINEAR)
    m = (np.array(small) > 60)
    lab = np.zeros(m.shape, dtype=np.int32)
    for sy in range(m.shape[0]):
        for sx in range(m.shape[1]):
            if not m[sy, sx] or lab[sy, sx]:
                continue
            cur += 1
            stack = [(sy, sx)]
            lab[sy, sx] = cur
            n = 0
            while stack:
                y, x = stack.pop()
                n += 1
                for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    yy, xx = y + dy, x + dx
                    if 0 <= yy < m.shape[0] and 0 <= xx < m.shape[1] and m[yy, xx] and not lab[yy, xx]:
                        lab[yy, xx] = cur
                        stack.append((yy, xx))
            if n > best_n:
                best, best_n = cur, n
    keep = Image.fromarray(((lab == best) * 255).astype(np.uint8), "L").resize((w, h), Image.BILINEAR).filter(ImageFilter.GaussianBlur(8))
    k = np.clip(np.array(keep).astype(np.float32) / 255.0 * 3.0, 0.0, 1.0)
    out = img.copy()
    out[..., 3] *= k
    return out


def fit(img, px, side=0.0, top=0.0):
    """그림을 px 크기 안에 맞춰 넣는다 (가로세로 비 유지, 아래 가운데 맞춤).
    side·top = 양옆·위에 비워 둘 여백 (그림 크기에 대한 비율) — 일렁일 때 불꽃이 그림 가장자리에서 잘리지 않게"""
    w, h = px
    src = Image.fromarray((np.clip(premul(img), 0, 1) * 255).astype(np.uint8), "RGBA")
    scale = min(w * (1.0 - 2.0 * side) / src.width, h * (1.0 - top) / src.height)
    size = (max(1, round(src.width * scale)), max(1, round(src.height * scale)))
    src = src.resize(size, Image.LANCZOS)
    canvas = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    canvas.paste(src, ((w - size[0]) // 2, h - size[1]))
    return unpremul(np.array(canvas).astype(np.float32) / 255.0)


def premul(a):
    b = a.copy()
    b[..., :3] *= b[..., 3:4]
    return b


def unpremul(a):
    b = a.copy()
    al = np.maximum(b[..., 3:4], 1e-4)
    b[..., :3] = np.where(b[..., 3:4] > 1e-4, b[..., :3] / al, 0.0)
    return b


def tile_noise(rng, w, h, cells):
    """세로로 이어지는(위아래가 맞물리는) 부드러운 무늬 (-1~1)"""
    gh = max(2, cells)
    gw = max(2, round(cells * w / h))
    grid = rng.uniform(-1.0, 1.0, (gh, gw)).astype(np.float32)
    grid = np.concatenate([grid, grid, grid], axis=0)
    big = np.array(Image.fromarray(((grid + 1.0) * 127.5).astype(np.uint8), "L").resize((w, h * 3), Image.BICUBIC)).astype(np.float32) / 127.5 - 1.0
    return big[h:h * 2]


def sample(img, xs, ys):
    """두 칸 사이를 고르게 섞어 읽는다 (그림 밖은 투명)"""
    h, w = img.shape[:2]
    x0 = np.floor(xs).astype(np.int32)
    y0 = np.floor(ys).astype(np.int32)
    fx = (xs - x0)[..., None]
    fy = (ys - y0)[..., None]
    out = np.zeros(xs.shape + (4,), dtype=np.float32)
    for dy in (0, 1):
        for dx in (0, 1):
            xx = x0 + dx
            yy = y0 + dy
            ok = (xx >= 0) & (xx < w) & (yy >= 0) & (yy < h)
            wgt = (fx if dx else 1.0 - fx) * (fy if dy else 1.0 - fy)
            out += np.where(ok[..., None], img[np.clip(yy, 0, h - 1), np.clip(xx, 0, w - 1)], 0.0) * wgt
    return out


def animate(img, sway, seed, rise=1.0, root=0.12):
    """그림 한 장 → 일렁이는 장들. 무늬가 위로 한 바퀴 흘러가는 동안의 모습 (끝과 처음이 이어진다).
    sway = 일그러뜨리는 폭 (그림 폭에 대한 비율), root = 아래에서 이 비율까지는 움직이지 않는다 (불 뿌리)"""
    rng = np.random.default_rng(seed)
    h, w = img.shape[:2]
    pm = premul(img)
    big = [tile_noise(rng, w, h, 3), tile_noise(rng, w, h, 3)]
    fine = [tile_noise(rng, w, h, 7), tile_noise(rng, w, h, 7)]
    yy, xx = np.mgrid[0:h, 0:w].astype(np.float32)
    up = np.clip(((h - 1 - yy) / h - root) / (1.0 - root), 0.0, 1.0) ** 0.8   # 0 뿌리 … 1 꼭대기
    frames = []
    for k in range(FRAMES):
        shift = int(round(k * h * rise / FRAMES))
        sh2 = int(round(k * h * rise * 2.0 / FRAMES))
        dx = (np.roll(big[0], -shift, axis=0) * 0.7 + np.roll(fine[0], -sh2, axis=0) * 0.3) * sway * w * up
        dy = (np.roll(big[1], -shift, axis=0) * 0.6 + np.roll(fine[1], -sh2, axis=0) * 0.4) * sway * 0.8 * h * up
        frames.append(unpremul(sample(pm, xx + dx, yy + dy)))
    return frames


def save_atlas(frames, path):
    atlas = np.concatenate(frames, axis=0)
    Image.fromarray((np.clip(atlas, 0, 1) * 255).astype(np.uint8), "RGBA").save(path)
    print("그림", os.path.basename(path), atlas.shape[1], "x", atlas.shape[0])


def flame_top_v(img):
    """불꽃 꼭대기 위의 빈 여백 (그림 높이에 대한 비율)"""
    ys = np.where(img[..., 3].max(axis=1) > 0.2)[0]
    return round(float(ys.min()) / img.shape[0], 3) if ys.size else 0.0


def base_v(img):
    """불 뿌리(바닥 가운데)의 높이 — 그림 아래에서부터의 비율. 위에서 내려다본 불이라 밑면이 둥글다:
    맨 아래 가장자리가 아니라, 불꽃 폭이 가장 넓은 밑동의 가운데쯤이 바닥에 닿은 자리다"""
    a = img[..., 3] > 0.3
    rows = a.sum(axis=1)
    ys = np.where(rows > 0)[0]
    if ys.size == 0:
        return 0.0
    bottom = ys.max()
    low = rows[int(bottom - (bottom - ys.min()) * 0.25):bottom + 1]
    widest = int(bottom - (low.size - 1 - int(np.argmax(low))))
    return round(float(img.shape[0] - 1 - (bottom + widest) * 0.5) / img.shape[0], 3)


def over_dark(img, bg=(0.2, 0.2, 0.22)):
    c = img[..., :3] * img[..., 3:4] + np.array(bg, dtype=np.float32) * (1.0 - img[..., 3:4])
    return Image.fromarray((np.clip(c, 0, 1) * 255).astype(np.uint8), "RGB")


def smoke_sprite(smoke):
    """검은 연기 덩어리 → 밝은 회색(명암은 그대로) — 게임이 연기 색(흰 → 회 → 검)을 곱한다"""
    img = crop(smoke, SMOKE_BOX)
    # 큰 연기 구름의 한가운데를 둥글게 떠낸다 (가장자리는 부드럽게) — 뭉게뭉게한 결이 살아 있는 덩어리 하나
    hh, ww = img.shape[:2]
    yy, xx = np.mgrid[0:hh, 0:ww].astype(np.float32)
    rad = np.sqrt(((xx - ww * 0.5) / (ww * 0.5)) ** 2 + ((yy - hh * 0.5) / (hh * 0.5)) ** 2)
    img[..., 3] *= np.clip((1.0 - rad) / 0.32, 0.0, 1.0)
    img = trim(img, 4, 0.08)
    lum = img[..., :3].mean(axis=2)
    body = lum[img[..., 3] > 0.5]
    lo = float(np.percentile(body, 4))
    hi = float(np.percentile(body, 96))
    # 명암(뭉게뭉게한 덩어리의 그늘)은 그대로 두고 밝기만 올린다
    lit = np.clip(0.38 + (lum - lo) / max(1e-3, hi - lo) * 0.62, 0.0, 0.92)
    alpha = np.where(img[..., 3] < 0.08, 0.0, img[..., 3])
    out = np.dstack([lit, lit, lit, alpha])
    return fit(out, SMOKE_PX, 0.08, 0.08)


# 시트의 칸 자리 (테두리 선 안쪽, px) — 가로 8칸 × 세로 6줄
SHEET_XS = [(30, 356), (380, 704), (727, 1051), (1074, 1396), (1420, 1742), (1766, 2089), (2112, 2437), (2460, 2786)]
SHEET_YS = [(23, 249), (278, 502), (533, 754), (786, 1007), (1039, 1259), (1293, 1512)]
# 크기별로 쓸 칸 (줄, 칸): 한창 타는 큰 불(셋째 줄 + 넷째 줄 앞 두 칸) / 두 갈래가 합쳐지는 넓은 불(둘째 줄)
SHEET_BIG = [(2, k) for k in range(8)] + [(3, 0), (3, 1)]
SHEET_WIDE = [(1, k) for k in range(8)]
SHEET_KINDS = {
    "s": {"cells": SHEET_BIG, "px": (96, 112), "w": 0.7, "fps": 9.0},
    "m": {"cells": SHEET_BIG, "px": (160, 184), "w": 1.3, "fps": 8.5},
    "l": {"cells": SHEET_BIG, "px": (224, 288), "w": 2.0, "fps": 8.0},
    "xl": {"cells": SHEET_WIDE, "px": (336, 304), "w": 3.2, "fps": 7.5},
}


def key_sheet_fire(c):
    """바둑판 바탕 위의 불꽃 → RGBA. 불 둘레의 옅은 빛은 바둑판이 비치므로 걸러 내고, 가장자리 색은 불꽃 색을 번지게 해 메운다"""
    r, b = c[..., 0], c[..., 2]
    hi = c.max(axis=2)
    fire = np.clip((r - b - 0.13) * 3.2, 0.0, 1.0) * np.clip((r - 0.35) * 2.4, 0.0, 1.0)
    fire = np.clip(fire * 1.3, 0.0, 1.0)
    body = Image.fromarray((fire * 255).astype(np.uint8), "L")
    inside = np.array(body.filter(ImageFilter.MaxFilter(5)).filter(ImageFilter.GaussianBlur(3))).astype(np.float32) / 255.0
    inside = np.clip((inside - 0.5) * 3.0, 0.0, 1.0)
    core = inside * np.clip((hi - 0.8) * 6.0, 0.0, 1.0)      # 불꽃 속의 흰 노랑 (바둑판보다 훨씬 밝다)
    a = np.clip(np.maximum(fire, core), 0.0, 1.0)
    # 색: 진한 곳은 그림 색 그대로, 옅은 가장자리는 진한 곳의 색을 번지게 한 것 (바둑판 회색이 섞이지 않게)
    strong = np.clip((a - 0.6) / 0.3, 0.0, 1.0)
    num = np.array(Image.fromarray((np.clip(c * strong[..., None], 0, 1) * 255).astype(np.uint8), "RGB").filter(ImageFilter.GaussianBlur(3))).astype(np.float32) / 255.0
    den = np.array(Image.fromarray((strong * 255).astype(np.uint8), "L").filter(ImageFilter.GaussianBlur(3))).astype(np.float32) / 255.0
    spread = np.where(den[..., None] > 0.02, num / np.maximum(den[..., None], 0.02), np.array([1.0, 0.45, 0.08], dtype=np.float32))
    col = c * strong[..., None] + np.clip(spread, 0.0, 1.0) * (1.0 - strong[..., None])
    return np.dstack([np.clip(col, 0.0, 1.0), a])


def sheet_frames(sheet, cells):
    """그 칸들의 불꽃 장면 (모두 같은 범위로 잘라 불 뿌리 자리가 장마다 같다)"""
    out = []
    for row, colm in cells:
        x0, x1 = SHEET_XS[colm]
        y0, y1 = SHEET_YS[row]
        f = key_sheet_fire(sheet[y0:y1, x0:x1])
        f[:46, :74, 3] = 0.0                       # 칸 왼쪽 위에 적힌 장 번호
        out.append(f)
    h = min(f.shape[0] for f in out)
    w = min(f.shape[1] for f in out)
    out = [f[f.shape[0] - h:, (f.shape[1] - w) // 2:(f.shape[1] - w) // 2 + w] for f in out]
    union = np.max(np.stack([f[..., 3] for f in out]), axis=0)
    ys, xs = np.where(union > 0.1)
    y0, y1 = max(0, ys.min() - 3), min(h, ys.max() + 4)
    x0, x1 = max(0, xs.min() - 3), min(w, xs.max() + 4)
    return [f[y0:y1, x0:x1] for f in out]


def fires_from_sheet(sheet_path, fx_dir, meta):
    sheet = load(sheet_path)
    cache = {}
    for kind, cfg in SHEET_KINDS.items():
        key = id(cfg["cells"])
        if key not in cache:
            cache[key] = sheet_frames(sheet, cfg["cells"])
        # 그림 높이는 장면의 가로세로 비에 맞춘다 (위쪽에 빈 자리를 남기지 않게)
        fh, fw = cache[key][0].shape[:2]
        cfg = dict(cfg)
        cfg["px"] = (cfg["px"][0], int(np.ceil(cfg["px"][0] * 0.94 * fh / fw / 0.98 / 2.0) * 2))
        frames = [fit(f, cfg["px"], 0.03, 0.02) for f in cache[key]]
        save_atlas(frames, os.path.join(fx_dir, "fire_%s.png" % kind))
        # 크기·뿌리 자리는 모든 장을 겹친 모습으로 잰다 (가장 큰 장도 넘치지 않게)
        union = frames[0].copy()
        union[..., 3] = np.max(np.stack([f[..., 3] for f in frames]), axis=0)
        top = flame_top_v(union)
        bv = base_v(union)
        xs = np.where(union[..., 3].max(axis=0) > 0.2)[0]
        flame_w_px = float(xs.max() - xs.min() + 1) if xs.size else float(cfg["px"][0])
        flame_h_px = float(cfg["px"][1]) * (1.0 - top - bv)
        meta["fire_" + kind] = {"w": cfg["px"][0], "h": cfg["px"][1], "frames": len(frames), "fps": cfg["fps"], "width_m": cfg["w"],
                                "height_m": round(cfg["w"] * flame_h_px / max(1.0, flame_w_px), 3), "flame_top_v": top, "base_v": bv,
                                "flame_w_u": round(flame_w_px / float(cfg["px"][0]), 3),
                                "source": "tools/prep_fire_art.py — 사용자 제공 화염연기 스프라이트 시트이미지.png 의 장면들"}


def main():
    src = sys.argv[1]
    art = sys.argv[2]
    check = sys.argv[4] if len(sys.argv) > 4 and sys.argv[3] == "check" else ""
    flame, smoke = split_layers(load(src))
    cuts = {}
    for name, cfg in FIRES.items():
        cuts[name] = trim(keep_main(crop(flame, cfg["box"], cfg["skip"])))
    billow = smoke_sprite(smoke)
    if check:
        os.makedirs(check, exist_ok=True)
        for name, img in cuts.items():
            over_dark(img).save(os.path.join(check, "cut_%s.png" % name))
        over_dark(billow).save(os.path.join(check, "cut_smoke.png"))
        whole = Image.fromarray((np.clip(premul(flame), 0, 1) * 255).astype(np.uint8), "RGBA").resize((1408, 768), Image.LANCZOS)
        over_dark(unpremul(np.array(whole).astype(np.float32) / 255.0)).save(os.path.join(check, "layer_flame.png"))
        whole = Image.fromarray((np.clip(premul(smoke), 0, 1) * 255).astype(np.uint8), "RGBA").resize((1408, 768), Image.LANCZOS)
        over_dark(unpremul(np.array(whole).astype(np.float32) / 255.0), (0.55, 0.55, 0.58)).save(os.path.join(check, "layer_smoke.png"))
        print("확인용 그림", check)
        return
    fx_dir = os.path.join(art, "fx")
    fx_json = os.path.join(fx_dir, "fx.json")
    meta = json.load(open(fx_json, encoding="utf-8")) if os.path.exists(fx_json) else {}
    sheet_path = sys.argv[4] if len(sys.argv) > 4 and sys.argv[3] == "sheet" else ""
    if sheet_path:
        fires_from_sheet(sheet_path, fx_dir, meta)
    for kind, cfg in ({} if sheet_path else KINDS).items():
        img = fit(cuts[cfg["from"]], cfg["px"], 0.11, 0.1)
        frames = animate(img, cfg["sway"], cfg["seed"])
        save_atlas(frames, os.path.join(fx_dir, "fire_%s.png" % kind))
        top = flame_top_v(img)
        bv = base_v(img)
        # 불꽃 부분(뿌리 ~ 꼭대기)의 높이 (m): 폭 w m 인 그림의 가로세로 비에서
        ys = np.where(img[..., 3].max(axis=1) > 0.2)[0]
        xs = np.where(img[..., 3].max(axis=0) > 0.2)[0]
        flame_w_px = float(xs.max() - xs.min() + 1) if xs.size else float(cfg["px"][0])
        flame_h_px = float(cfg["px"][1]) * (1.0 - top - bv)
        height_m = round(cfg["w"] * flame_h_px / max(1.0, flame_w_px), 3)
        meta["fire_" + kind] = {"w": cfg["px"][0], "h": cfg["px"][1], "frames": FRAMES, "fps": cfg["fps"], "width_m": cfg["w"],
                                "height_m": height_m, "flame_top_v": top, "base_v": bv,
                                "flame_w_u": round(flame_w_px / float(cfg["px"][0]), 3), "source": SOURCE}
    frames = animate(billow, 0.07, 51, rise=1.0, root=0.0)
    save_atlas(frames, os.path.join(fx_dir, "smoke_billow.png"))
    meta["smoke_billow"] = {"w": SMOKE_PX[0], "h": SMOKE_PX[1], "frames": FRAMES, "fps": 6.0, "source": SOURCE}
    json.dump(meta, open(fx_json, "w", encoding="utf-8"), ensure_ascii=False, indent=2, sort_keys=True)


main()
