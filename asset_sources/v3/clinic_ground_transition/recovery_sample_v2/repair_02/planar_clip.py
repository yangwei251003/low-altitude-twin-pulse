"""Deterministic convex subtraction; points carry original triangle barycentrics.

No Blender dependency. Coordinates use Python double. No vertex sorting, mesh
welding, remeshing or tolerance-driven removal of visible triangles.
"""
from math import hypot


def cross(a, b):
    return a[0] * b[1] - a[1] * b[0]


def signed_area(points):
    return .5 * sum(cross(a, b) for a, b in zip(points, points[1:] + points[:1]))


def area(points):
    return abs(signed_area(points))


def tidy(poly):
    out = []
    for item in poly:
        if not out or hypot(item[0][0]-out[-1][0][0], item[0][1]-out[-1][0][1]) > 1e-14:
            out.append(item)
    if len(out) > 1 and hypot(out[0][0][0]-out[-1][0][0], out[0][0][1]-out[-1][0][1]) <= 1e-14:
        out.pop()
    return out if len(out) >= 3 and area([x[0] for x in out]) > 1e-20 else []


def halfplane(poly, a, b, inside):
    """Keep one closed halfplane. Intersections interpolate source barycentrics."""
    if not poly:
        return []
    edge = (b[0]-a[0], b[1]-a[1])
    def distance(item):
        p = item[0]
        d = cross(edge, (p[0]-a[0], p[1]-a[1]))
        return d if inside else -d
    result = []
    prev = poly[-1]; dp = distance(prev)
    for curr in poly:
        dc = distance(curr)
        if (dp >= 0.) != (dc >= 0.):
            t = dp / (dp-dc)
            xy = tuple(prev[0][i] + t*(curr[0][i]-prev[0][i]) for i in range(2))
            weights = tuple(prev[1][i] + t*(curr[1][i]-prev[1][i]) for i in range(3))
            result.append((xy, weights))
        if dc >= 0.:
            result.append(curr)
        prev, dp = curr, dc
    return tidy(result)


def difference(poly, clip):
    """Disjoint convex pieces outside clip, and the one covered intersection."""
    if signed_area(clip) < 0.:
        clip = list(reversed(clip))
    remainder = poly; outside = []
    for a, b in zip(clip, clip[1:] + clip[:1]):
        piece = halfplane(remainder, a, b, False)
        if piece:
            outside.append(piece)
        remainder = halfplane(remainder, a, b, True)
        if not remainder:
            break
    return outside, remainder


def subtract(poly, masks):
    pieces = [poly]; removed = []
    for mask in masks:
        next_pieces = []
        for piece in pieces:
            keep, gone = difference(piece, mask)
            next_pieces.extend(keep)
            if gone:
                removed.append(gone)
        pieces = next_pieces
    return pieces, removed


def triangle(xy):
    return [(tuple(p), tuple(1. if i == j else 0. for j in range(3))) for i, p in enumerate(xy)]


def fan(poly):
    """Fan only a convex retained polygon; preserve the source order/winding."""
    for i in range(1, len(poly)-1):
        tri = [poly[0], poly[i], poly[i+1]]
        if area([p[0] for p in tri]) > 1e-20:
            yield tri


def self_check():
    source = triangle([(0., 0.), (2., 0.), (0., 2.)])
    masks = [[(.25, .25), (1.25, .25), (.25, 1.25)]]
    keep, gone = subtract(source, masks)
    assert abs(sum(area([p[0] for p in q]) for q in keep) - 1.5) < 1e-12
    assert abs(sum(area([p[0] for p in q]) for q in gone) - .5) < 1e-12
    for q in keep + gone:
        for p, weights in q:
            assert abs(sum(weights)-1.) < 1e-12 and min(weights) >= -1e-12
            reconstructed = (2*weights[1], 2*weights[2])
            assert max(abs(a-b) for a,b in zip(p,reconstructed)) < 1e-12
    # A merely touching edge removes no positive area.
    kept, removed = subtract(source, [[(0.,0.), (2.,0.), (1.,-1.)]])
    assert not removed and abs(sum(area([p[0] for p in q]) for q in kept)-2.) < 1e-12
    return {'convex_subtraction_area': True, 'barycentric_interpolation': True, 'touching_edge_no_loss': True}


if __name__ == '__main__':
    print(self_check())
