"""P13 broad asymmetric erosion. Pure coordinate design, not measured geometry.

The existing P10 XY topology is retained; only its upper height and CORNER
controls change. Original free perimeter returns to Y0. No high-only stones.
"""
import math

ROUTES = [
    [(-1.10, .49), (-1.22, 1.04), (-1.52, 1.62), (-1.43, 2.10)],
    [(.40, .51), (.55, .91), (.90, 1.22), (.74, 1.72)],
    [(1.74, .51), (1.87, .99), (1.66, 1.57), (1.94, 2.14)],
]


def clamp(v, a=0.0, b=1.0):
    return max(a, min(b, v))


def smooth(v):
    v = clamp(v)
    return v * v * (3 - 2 * v)


def route_frame(points, t):
    lengths = [math.dist(a, b) for a, b in zip(points, points[1:])]
    distance = t * sum(lengths)
    for a, b, length in zip(points, points[1:], lengths):
        if distance <= length + 1e-10:
            q = clamp(distance / length)
            tangent = ((b[0] - a[0]) / length, (b[1] - a[1]) / length)
            return (a[0] + q * (b[0] - a[0]), a[1] + q * (b[1] - a[1])), (-tangent[1], tangent[0])
        distance -= length
    return points[-1], (1.0, 0.0)


def nearest(points, x, z):
    lengths = [math.dist(a, b) for a, b in zip(points, points[1:])]
    walk, total, best = 0.0, sum(lengths), None
    for a, b, length in zip(points, points[1:], lengths):
        dx, dz = b[0] - a[0], b[1] - a[1]
        q = clamp(((x - a[0]) * dx + (z - a[1]) * dz) / (length * length))
        px, pz = a[0] + q * dx, a[1] + q * dz
        distance = math.hypot(x - px, z - pz)
        signed = (dx * (z - pz) - dz * (x - px)) / length
        if best is None or distance < best[0]:
            best = distance, signed, (walk + q * length) / total
        walk += length
    return best


def halfwidth(index, t):
    return [.14 + .07 * t, .09 + .06 * math.sin(math.pi * t), .20 + .125 * t][index]


def shoulder_width(index, t):
    return [.40 + .15 * math.sin(math.pi * t), .26 + .16 * math.sin(math.pi * t), .35 + .22 * t][index]


def field(x, z, front, outer):
    f, o = front(x), outer(x)
    s = clamp((z - f) / (o - f))
    edge = smooth((3 - abs(x)) / .18) * smooth((o - z) / .28)
    base = -.035 * (1 - s)
    cut = bank = wet = silt = deposit = 0.0
    for i, route in enumerate(ROUTES):
        distance, signed, t = nearest(route, x, z)
        h, spread = halfwidth(i, t), shoulder_width(i, t)
        tail = smooth((1 - t) / [.20, .29, .25][i])
        bed = (1 - smooth((distance - h * .35) / (h * .80))) * tail
        # Relative depression, not an absolute Y or an acceptance threshold.
        cut = max(cut, [.052, .038, .027][i] * bed)
        side = signed * [1, -1, 1][i]
        # The fan has almost no raised paired bank. The bend deposits outside.
        gain = 1.0 if side > 0 else [.20, .12, .50][i]
        shoulder = math.exp(-((distance - h * 1.25) / spread) ** 2)
        shoulder *= smooth(distance / h) * gain * tail
        bank = max(bank, shoulder * [.010, .009, .002][i])
        deposit = max(deposit, shoulder * [.80, .90, .18][i])
        wet = max(wet, bed * [.85, .67, .52][i] * (1 - .30 * t))
        silt = max(silt, bed)
    # A two-dimensional irregular edge apron joins the outwash. Its strength
    # varies by broad broken bays, not an identical band on all six banks.
    edge_distance = max(0.0, z - f)
    apron = (1 - smooth((edge_distance - .07) / .68))
    apron *= (.32 + .48 * math.exp(-((x + 1.40) / .72) ** 2)
              + .30 * math.exp(-((x - .78) / .55) ** 2))
    deposit = clamp(max(deposit, apron) * (1 - .96 * silt) * edge)
    return {'height': (base - cut + bank) * edge,
            'wet': wet * edge, 'silt': silt * edge, 'deposit': deposit}
