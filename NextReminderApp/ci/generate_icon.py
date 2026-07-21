#!/usr/bin/env python3
import math
import struct
import sys
import zlib

W = H = 1024
pixels = bytearray(W * H * 4)


def clamp(value, low=0.0, high=1.0):
    return max(low, min(high, value))


def mix(a, b, amount):
    return a + (b - a) * amount


def blend(dst, src, alpha):
    alpha = clamp(alpha)
    return tuple(int(mix(dst[i], src[i], alpha)) for i in range(3))


def set_pixel(x, y, rgb):
    index = (y * W + x) * 4
    pixels[index:index + 4] = bytes((rgb[0], rgb[1], rgb[2], 255))


def segment_distance(px, py, ax, ay, bx, by):
    vx, vy = bx - ax, by - ay
    wx, wy = px - ax, py - ay
    denominator = vx * vx + vy * vy
    amount = clamp((wx * vx + wy * vy) / denominator if denominator else 0)
    qx, qy = ax + amount * vx, ay + amount * vy
    return math.hypot(px - qx, py - qy)


orange = (255, 111, 0)
bright = (255, 176, 48)
dark_orange = (155, 48, 0)
graphite = (27, 29, 36)
black = (5, 6, 9)

for y in range(H):
    for x in range(W):
        radial = clamp(1 - math.hypot(x - 465, y - 405) / 760)
        diagonal = math.exp(-((y - (930 - 0.64 * x)) / 45) ** 2)
        base = (int(5 + 22 * radial), int(6 + 20 * radial), int(9 + 24 * radial))
        base = blend(base, dark_orange, diagonal * 0.50)

        # Rounded-square orange rim.
        dx = max(abs(x - 512) - 435, 0)
        dy = max(abs(y - 512) - 435, 0)
        rim = math.hypot(dx, dy)
        if 0 < rim < 20:
            base = blend(base, orange, 1 - rim / 20)

        # Bell silhouette and metallic highlight.
        dome_value = ((x - 512) / 258) ** 2 + ((y - 430) / 245) ** 2
        dome = dome_value < 1 and y >= 245
        width = 245 + max(0, y - 460) * 0.39
        skirt = 420 <= y <= 720 and abs(x - 512) < width
        if dome or skirt:
            light = clamp(1 - math.hypot(x - 405, y - 285) / 520)
            metal = (int(22 + 44 * light), int(23 + 42 * light), int(29 + 45 * light))
            base = blend(base, metal, 0.97)
            if abs(dome_value - 1) < 0.028 or abs(abs(x - 512) - width) < 7:
                base = blend(base, orange, 0.78)

        # Bell top, lip and clapper.
        top_radius = math.hypot(x - 512, y - 214)
        if top_radius < 59:
            base = blend(base, graphite, 0.98)
            if 51 < top_radius < 59:
                base = blend(base, bright, 0.92)
        clapper_radius = math.hypot(x - 512, y - 775)
        if clapper_radius < 56:
            base = blend(base, graphite, 0.98)
            if 48 < clapper_radius < 56:
                base = blend(base, orange, 0.95)
        if 700 <= y <= 750 and abs(x - 512) < 334:
            lip_y = 716 + 22 * ((x - 512) / 334) ** 2
            if abs(y - lip_y) < 12:
                base = blend(base, orange, 0.96)

        # Clock face with glowing ring.
        radius = math.hypot(x - 512, y - 500)
        if radius < 183:
            face_light = clamp(1 - math.hypot(x - 450, y - 420) / 340)
            face = (int(8 + 25 * face_light), int(9 + 25 * face_light), int(12 + 29 * face_light))
            base = blend(base, face, 0.99)
        if 174 < radius < 194:
            base = blend(base, bright if radius < 183 else orange, 0.99)

        for angle in (0, math.pi / 2, math.pi, 3 * math.pi / 2):
            tx = 512 + math.cos(angle) * 137
            ty = 500 + math.sin(angle) * 137
            if math.hypot(x - tx, y - ty) < 9:
                base = blend(base, bright, 1.0)

        # Glowing check mark.
        distance = min(
            segment_distance(x, y, 423, 512, 495, 580),
            segment_distance(x, y, 495, 580, 630, 429),
        )
        if distance < 31:
            base = blend(base, dark_orange, (1 - distance / 31) * 0.78)
        if distance < 18:
            base = blend(base, bright, 0.98)

        set_pixel(x, y, base)


def chunk(tag, data):
    return (
        struct.pack('>I', len(data))
        + tag
        + data
        + struct.pack('>I', zlib.crc32(tag + data) & 0xFFFFFFFF)
    )


raw = bytearray()
stride = W * 4
for y in range(H):
    raw.append(0)
    raw.extend(pixels[y * stride:(y + 1) * stride])

png = b'\x89PNG\r\n\x1a\n'
png += chunk(b'IHDR', struct.pack('>IIBBBBB', W, H, 8, 6, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(bytes(raw), 9))
png += chunk(b'IEND', b'')
with open(sys.argv[1], 'wb') as output:
    output.write(png)
