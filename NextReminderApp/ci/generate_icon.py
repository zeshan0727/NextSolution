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


def smoothstep(edge0, edge1, value):
    if edge0 == edge1:
        return 0.0
    amount = clamp((value - edge0) / (edge1 - edge0))
    return amount * amount * (3.0 - 2.0 * amount)


def blend(dst, src, alpha):
    alpha = clamp(alpha)
    return tuple(int(mix(dst[index], src[index], alpha)) for index in range(3))


def color_mix(first, second, amount):
    amount = clamp(amount)
    return tuple(int(mix(first[index], second[index], amount)) for index in range(3))


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


def ring_color(angle):
    # Travel clockwise around the C ring: cyan -> blue -> violet -> magenta.
    normalized = (angle + math.pi) / (2 * math.pi)
    cyan = (15, 213, 255)
    blue = (43, 102, 255)
    violet = (112, 65, 255)
    magenta = (196, 63, 255)
    if normalized < 0.34:
        return color_mix(cyan, blue, normalized / 0.34)
    if normalized < 0.70:
        return color_mix(blue, violet, (normalized - 0.34) / 0.36)
    return color_mix(violet, magenta, (normalized - 0.70) / 0.30)


navy = (6, 12, 25)
navy_highlight = (24, 39, 70)
white = (249, 252, 255)
check_shadow = (11, 20, 40)

center_x, center_y = 478, 510
ring_radius = 305
ring_width = 62

for y in range(H):
    for x in range(W):
        distance_from_center = math.hypot(x - 470, y - 425)
        radial = clamp(1.0 - distance_from_center / 760.0)
        corner_vignette = smoothstep(780, 260, math.hypot(x - 512, y - 512))
        diagonal = math.exp(-((y - (960 - 0.70 * x)) / 145.0) ** 2)

        base = (
            int(navy[0] + 18 * radial * corner_vignette),
            int(navy[1] + 25 * radial * corner_vignette),
            int(navy[2] + 41 * radial * corner_vignette),
        )
        base = blend(base, navy_highlight, diagonal * 0.16)

        # Subtle premium inner border.
        edge_distance = min(x, y, W - 1 - x, H - 1 - y)
        if 24 < edge_distance < 36:
            base = blend(base, (63, 91, 145), (1 - abs(edge_distance - 30) / 6) * 0.18)

        dx = x - center_x
        dy = y - center_y
        radius = math.hypot(dx, dy)
        angle = math.atan2(dy, dx)

        # Open gap on the upper-right creates a distinct C-shaped progress ring.
        in_gap = -0.58 < angle < 0.17
        ring_distance = abs(radius - ring_radius)
        current_ring_color = ring_color(angle)

        if not in_gap and ring_distance < ring_width + 44:
            glow = clamp(1.0 - ring_distance / (ring_width + 44))
            base = blend(base, current_ring_color, glow * glow * 0.34)

        if not in_gap and ring_distance < ring_width:
            core = clamp(1.0 - ring_distance / ring_width)
            edge_softness = smoothstep(0.0, 0.22, core)
            shine = clamp(1.0 - math.hypot(x - 365, y - 275) / 620)
            ring_pixel = blend(current_ring_color, white, shine * 0.12)
            base = blend(base, ring_pixel, 0.90 * edge_softness)

        # Rounded glowing endpoints for the C ring.
        for endpoint_angle in (-0.58, 0.17):
            endpoint_x = center_x + math.cos(endpoint_angle) * ring_radius
            endpoint_y = center_y + math.sin(endpoint_angle) * ring_radius
            endpoint_distance = math.hypot(x - endpoint_x, y - endpoint_y)
            endpoint_color = ring_color(endpoint_angle)
            if endpoint_distance < 88:
                base = blend(base, endpoint_color, (1 - endpoint_distance / 88) ** 2 * 0.30)
            if endpoint_distance < ring_width:
                base = blend(base, endpoint_color, smoothstep(ring_width, 0, endpoint_distance) * 0.94)

        # Strong white check mark with a soft navy shadow and blue-violet glow.
        check_distance = min(
            segment_distance(x, y, 315, 510, 455, 642),
            segment_distance(x, y, 455, 642, 715, 350),
        )
        if check_distance < 82:
            base = blend(base, (73, 80, 255), (1 - check_distance / 82) ** 2 * 0.26)
        if check_distance < 56:
            base = blend(base, check_shadow, (1 - check_distance / 56) * 0.72)
        if check_distance < 37:
            core = smoothstep(37, 0, check_distance)
            highlight = color_mix((225, 233, 244), white, core)
            base = blend(base, highlight, 0.98)

        # Small four-point sparkle in the upper-right, symbolizing smart automation.
        sparkle_x, sparkle_y = 789, 238
        sx, sy = abs(x - sparkle_x), abs(y - sparkle_y)
        sparkle_shape = min(sx / 17 + sy / 66, sx / 66 + sy / 17)
        sparkle_distance = math.hypot(x - sparkle_x, y - sparkle_y)
        if sparkle_distance < 92:
            base = blend(base, (174, 84, 255), (1 - sparkle_distance / 92) ** 2 * 0.34)
        if sparkle_shape < 1.0:
            base = blend(base, white, smoothstep(1.0, 0.0, sparkle_shape))

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
