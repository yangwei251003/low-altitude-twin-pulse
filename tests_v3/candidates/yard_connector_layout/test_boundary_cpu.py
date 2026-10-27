"""Synthetic CPU fixtures only; they do not establish a production yard area."""
import importlib.util
from pathlib import Path
import unittest

ROOT = Path(__file__).resolve().parents[3]
SCRIPT = ROOT / 'scripts_tools/v3/candidates/yard_connector_layout/build_blender_input.py'
spec = importlib.util.spec_from_file_location('yard_input', SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


def rect(x0, z0, x1, z1):
    return [(x0, 0, z0), (x1, 0, z0), (x1, 0, z1),
            (x0, 0, z0), (x1, 0, z1), (x0, 0, z1)]


class BoundaryTests(unittest.TestCase):
    def test_adjacent_triangles_are_not_internal_borders(self):
        geom, area = module.triangle_union(rect(0, 0, 2, 1))
        self.assertEqual(area, 2)
        self.assertEqual(len(module.rings(geom)), 1)
        self.assertEqual(geom.length, 6)

    def test_t_junction_resolves_without_expanding_or_snapping(self):
        geom, area = module.triangle_union(rect(0, 0, 1, 2)+rect(1, 0, 2, 1)+rect(1, 1, 2, 2))
        self.assertEqual((area, geom.area, geom.length), (4, 4, 8))

    def test_actual_hole_is_preserved(self):
        geom, area = module.triangle_union(rect(0, 0, 3, 1)+rect(0, 2, 3, 3)+rect(0, 1, 1, 2)+rect(2, 1, 3, 2))
        self.assertEqual(area, 8)
        self.assertEqual(len(module.rings(geom)[0]['holes_world_xz']), 1)

    def test_disconnected_patch_is_not_convex_hulled(self):
        geom, area = module.triangle_union(rect(0, 0, 1, 1)+rect(2, 0, 3, 1))
        self.assertEqual(area, 2)
        self.assertEqual(len(module.rings(geom)), 2)

    def test_positive_overlap_rejects(self):
        with self.assertRaisesRegex(ValueError, 'positive triangle overlap'):
            module.triangle_union(rect(0, 0, 2, 2)+rect(1, 1, 3, 3))

    def test_nonplanar_and_degenerate_reject(self):
        with self.assertRaisesRegex(ValueError, 'exactly Y0'):
            module.triangle_union([(0, 0, 0), (1, .001, 0), (0, 0, 1)])
        with self.assertRaisesRegex(ValueError, 'zero area'):
            module.triangle_union([(0, 0, 0), (1, 0, 0), (2, 0, 0)])

    def test_submillimetre_gap_is_not_filled(self):
        geom, area = module.triangle_union(rect(0, 0, 1, 1)+rect(1.0001, 0, 2.0001, 1))
        self.assertAlmostEqual(area, 2)
        self.assertEqual(len(module.rings(geom)), 2)


if __name__ == '__main__':
    unittest.main()
