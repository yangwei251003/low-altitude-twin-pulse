"""Small CPU-only checks for this asset's 2D atlas; no Blender imports."""
import math
from collections import Counter, defaultdict


def cross(a, b, c):
    return (b[0]-a[0])*(c[1]-a[1])-(b[1]-a[1])*(c[0]-a[0])


def bounds(points):
    return min(p[0] for p in points), min(p[1] for p in points), max(p[0] for p in points), max(p[1] for p in points)


def box_distance(a, b):
    return math.hypot(max(a[0]-b[2], b[0]-a[2], 0), max(a[1]-b[3], b[1]-a[3], 0))


def intersection_area(a, b):
    poly = list(a)
    for i in range(3):
        p, q = b[i], b[(i+1) % 3]
        out = []
        for j, current in enumerate(poly):
            previous = poly[j-1]
            dc, dp = cross(p, q, current), cross(p, q, previous)
            if (dc >= 0) != (dp >= 0):
                t = dp/(dp-dc)
                out.append(tuple(previous[k]+t*(current[k]-previous[k]) for k in range(2)))
            if dc >= 0:
                out.append(current)
        poly = out
        if not poly:
            return 0.0
    return abs(sum(poly[i][0]*poly[(i+1) % len(poly)][1]-poly[(i+1) % len(poly)][0]*poly[i][1] for i in range(len(poly))))/2


def check_triangle_overlap(triangles):
    """Exact clipping on candidates; the grid only limits candidate pairs."""
    bins = defaultdict(list)
    checked = set()
    total = 0
    for i, tri in enumerate(triangles):
        assert cross(*tri) > 1e-10, 'Nonpositive/collapsed atlas triangle'
        x0, y0, x1, y1 = bounds(tri)
        cells = [(x, y) for x in range(math.floor(x0/32), math.floor(x1/32)+1)
                 for y in range(math.floor(y0/32), math.floor(y1/32)+1)]
        for cell in cells:
            for j in bins[cell]:
                if (j, i) in checked:
                    continue
                checked.add((j, i))
                other = triangles[j]
                # Shared UV vertices are exact values from the same source.
                common = set(tri) & set(other)
                assert len(common) != 3, 'Duplicate atlas triangle'
                if len(common) == 2:
                    p, q = tuple(common)
                    u = next(v for v in tri if v not in common)
                    v = next(v for v in other if v not in common)
                    if cross(p, q, u)*cross(p, q, v) <= 0:
                        continue
                overlap = intersection_area(tri, other)
                # Absolute double-precision arithmetic tolerance in pixel².
                assert overlap < 1e-7, ('UV interior overlap', i, j, overlap)
                total += 1
            bins[cell].append(i)
    return total


def boundary_segments(triangles):
    counts = Counter()
    directed = {}
    for tri in triangles:
        for i in range(3):
            a, b = tri[i], tri[(i+1) % 3]
            key = tuple(sorted((a, b)))
            counts[key] += 1
            directed[key] = (a, b)
    assert all(n <= 2 for n in counts.values()), 'Nonmanifold UV island'
    edges = [directed[e] for e, n in counts.items() if n == 1]
    outgoing = defaultdict(list)
    for a, b in edges:
        outgoing[a].append(b)
    # Collapse only unambiguous, collinear boundary vertices to accelerate
    # distance checks. Hole loops remain separate; no convex-hull shortcut.
    visited, result = set(), []
    for a, b in edges:
        if (a, b) in visited:
            continue
        chain = [a, b]
        visited.add((a, b))
        while len(outgoing[chain[-1]]) == 1:
            c = outgoing[chain[-1]][0]
            edge = (chain[-1], c)
            if edge in visited:
                break
            visited.add(edge)
            if abs(cross(chain[-2], chain[-1], c)) < 1e-7 and sum((chain[-1][k]-chain[-2][k])*(c[k]-chain[-1][k]) for k in range(2)) >= 0:
                chain[-1] = c
            else:
                chain.append(c)
            if c == chain[0]:
                break
        result.extend(zip(chain, chain[1:]))
    assert visited == set(edges) and result
    return result


def point_segment(p, a, b):
    d = (b[0]-a[0], b[1]-a[1])
    length2 = d[0]*d[0]+d[1]*d[1]
    t = max(0, min(1, ((p[0]-a[0])*d[0]+(p[1]-a[1])*d[1])/length2)) if length2 else 0
    return math.hypot(p[0]-a[0]-t*d[0], p[1]-a[1]-t*d[1])


def shortest_distances(islands):
    """Per-island nearest boundary distance, not rectangle separation."""
    bb = [bounds([p for tri in ts for p in tri]) for ts in islands]
    edges = [boundary_segments(ts) for ts in islands]
    segment_boxes = [[bounds(edge) for edge in es] for es in edges]
    best = [float('inf')]*len(islands)
    nearest = [-1]*len(islands)
    pairs = sorted((box_distance(bb[i], bb[j]), i, j) for i in range(len(bb)) for j in range(i+1, len(bb)))
    for lower, i, j in pairs:
        if lower >= best[i] and lower >= best[j]:
            continue
        distance = float('inf')
        for ei, (a, b) in enumerate(edges[i]):
            for ej, (c, d) in enumerate(edges[j]):
                if box_distance(segment_boxes[i][ei], segment_boxes[j][ej]) >= distance:
                    continue
                distance = min(distance, point_segment(a, c, d), point_segment(b, c, d),
                               point_segment(c, a, b), point_segment(d, a, b))
        if distance < best[i]: best[i], nearest[i] = distance, j
        if distance < best[j]: best[j], nearest[j] = distance, i
    return best, nearest


def occupied_pixels(triangles, size):
    """Unique level-0 pixel centres covered, with no bake dilation included."""
    rows = defaultdict(list)
    for tri in triangles:
        _, ymin, _, ymax = bounds(tri)
        for row in range(max(0, math.ceil(ymin-.5)), min(size-1, math.floor(ymax-.5))+1):
            y = row+.5
            xs = []
            for i in range(3):
                a, b = tri[i], tri[(i+1) % 3]
                if (a[1] <= y < b[1]) or (b[1] <= y < a[1]):
                    xs.append(a[0]+(y-a[1])*(b[0]-a[0])/(b[1]-a[1]))
            if len(xs) == 2:
                lo, hi = max(0, math.ceil(min(xs)-.5)), min(size-1, math.floor(max(xs)-.5))
                if lo <= hi: rows[row].append((lo, hi))
    count = 0
    for intervals in rows.values():
        end = -1
        for lo, hi in sorted(intervals):
            if hi > end: count += hi-max(lo, end+1)+1
            end = max(end, hi)
    return count


def self_check():
    a = [(0., 0.), (2., 0.), (0., 2.)]
    b = [(2., 0.), (2., 2.), (0., 2.)]
    assert intersection_area(a, b) == 0 and intersection_area(a, a) == 2
    assert abs(intersection_area(a, [(0., 0.), (1., 0.), (0., 1.)])-.5) < 1e-12
    assert check_triangle_overlap([a, b]) == 0
    try: check_triangle_overlap([a, a])
    except AssertionError: pass
    else: raise AssertionError('Duplicate negative fixture was accepted')
    shifted = [[(x+12, y) for x, y in t] for t in [a, b]]
    distances, _ = shortest_distances([[a, b], shifted])
    assert distances == [10., 10.] and occupied_pixels([a, b], 32) == 4
    return {'independent_cases': 7, 'passed': True, 'scope': '2D math only, no source/Blender validation'}


if __name__ == '__main__':
    print(self_check())
