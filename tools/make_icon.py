#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
生成「简记」App 图标（1024x1024 PNG，无透明通道）。
纯 Python 实现：行跨度填充 + zlib 打包 PNG，不依赖 Pillow / numpy。

设计：绿色渐变底 + 白色小票（带撕纸齿）+ 三条账单横线。
"""

import zlib
import struct
import os

SS = 2                 # 超采样倍数
OUT = 1024             # 最终边长
W = OUT * SS

# 颜色（RGB）
C_TOP = (0x4C, 0xE1, 0x80)
C_BOTTOM = (0x1C, 0x9E, 0x47)
WHITE = (0xFF, 0xFF, 0xFF)
BAR = (0x25, 0xAE, 0x54)


def lerp(a, b, t):
    return int(round(a + (b - a) * t))


buf = bytearray(W * W * 3)

# ---------- 1. 渐变背景 ----------
for y in range(W):
    t = y / (W - 1)
    # 轻微加速曲线，让上半部分更亮
    tt = t ** 0.85
    r = lerp(C_TOP[0], C_BOTTOM[0], tt)
    g = lerp(C_TOP[1], C_BOTTOM[1], tt)
    b = lerp(C_TOP[2], C_BOTTOM[2], tt)
    row = bytes((r, g, b)) * W
    buf[y * W * 3:(y + 1) * W * 3] = row


def fill_span(y, x_start, x_end, color):
    """在 y 行填充 [x_start, x_end) 区间"""
    if x_end <= x_start:
        return
    x_start = max(0, int(x_start))
    x_end = min(W, int(x_end))
    if x_end <= x_start:
        return
    line = bytes(color) * (x_end - x_start)
    buf[y * W * 3 + x_start * 3: y * W * 3 + x_end * 3] = line


def fill_rounded_rect(x0, y0, x1, y1, radius, color, skip_rows_from_top=0):
    """圆角矩形（坐标是 1024 设计空间）"""
    X0, Y0, X1, Y1 = x0 * SS, y0 * SS, x1 * SS, y1 * SS
    R = radius * SS
    for y in range(int(Y0), int(Y1)):
        inset = 0.0
        if y < Y0 + R:
            dy = (Y0 + R) - y
            inset = R - (R * R - dy * dy) ** 0.5
        elif y > Y1 - R:
            dy = y - (Y1 - R)
            inset = R - (R * R - dy * dy) ** 0.5
        fill_span(y, X0 + inset, X1 - inset, color)


# ---------- 2. 小票主体 ----------
# 阴影层（半透明绿，简单叠一圈稍大的浅色）
fill_rounded_rect(288, 240, 736, 772, 58, (0x17, 0x7C, 0x39))
fill_rounded_rect(292, 236, 732, 768, 54, WHITE)

# 撕纸齿：底部 4 个向下的三角
TEETH = 4
t_x0, t_x1 = 292, 732
t_y = 768
t_h = 46
seg = (t_x1 - t_x0) / TEETH
for i in range(TEETH):
    cx0 = t_x0 + seg * i
    for row in range(int(t_y * SS), int((t_y + t_h) * SS)):
        # 该行三角形的高度进度
        prog = (row / SS - t_y) / t_h
        half = (seg * SS / 2) * (1 - prog)
        center = (cx0 + seg / 2) * SS
        fill_span(row, center - half, center + half, WHITE)

# ---------- 3. 账单横线 ----------
fill_rounded_rect(352, 356, 672, 402, 23, BAR)
fill_rounded_rect(352, 452, 612, 498, 23, BAR)
fill_rounded_rect(352, 548, 652, 594, 23, BAR)

# 第四条短一点，暗示「更多」
fill_rounded_rect(352, 644, 552, 690, 23, BAR)

# ---------- 4. 降采样 ----------
out = bytearray(OUT * OUT * 3)
for oy in range(OUT):
    sy = oy * SS
    for ox in range(OUT):
        sx = ox * SS
        r = g = b = 0
        for dy in range(SS):
            base = (sy + dy) * W * 3 + sx * 3
            for dx in range(SS):
                r += buf[base + dx * 3]
                g += buf[base + dx * 3 + 1]
                b += buf[base + dx * 3 + 2]
        n = SS * SS
        o = (oy * OUT + ox) * 3
        out[o] = r // n
        out[o + 1] = g // n
        out[o + 2] = b // n


# ---------- 5. 写 PNG ----------
def write_png(path, width, height, rgb):
    raw = bytearray()
    stride = width * 3
    for y in range(height):
        raw.append(0)  # filter type 0
        raw.extend(rgb[y * stride:(y + 1) * stride])

    def chunk(tag, data):
        return (struct.pack(">I", len(data)) + tag + data +
                struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF))

    png = b"\x89PNG\r\n\x1a\n"
    png += chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(bytes(raw), 9))
    png += chunk(b"IEND", b"")

    with open(path, "wb") as f:
        f.write(png)
    return len(png)


if __name__ == "__main__":
    here = os.path.dirname(os.path.abspath(__file__))
    target = os.path.join(
        here, "..", "QingDianJiZhang", "Resources",
        "Assets.xcassets", "AppIcon.appiconset", "AppIcon-1024.png"
    )
    target = os.path.normpath(target)
    os.makedirs(os.path.dirname(target), exist_ok=True)
    size = write_png(target, OUT, OUT, out)
    print("written:", target, size, "bytes")
