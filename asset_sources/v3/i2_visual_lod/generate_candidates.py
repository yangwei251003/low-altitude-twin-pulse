"""Blender-only, one bounded simplification pass; never changes canonical inputs.

Exported geometry is transplanted into the original GLB container. Original
nodes, transforms, materials, textures and embedded image bytes stay intact.
The candidate is visual only; no production script or collision is generated.
"""
from __future__ import annotations

import argparse
import copy
import hashlib
import json
import math
from pathlib import Path
import struct
import sys
import time


HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_glb(path):
    data = path.read_bytes()
    magic, version, size = struct.unpack_from("<III", data)
    if magic != 0x46546C67 or version != 2 or size != len(data):
        raise ValueError("Invalid GLB header")
    offset, document, binary = 12, None, b""
    while offset < len(data):
        length, kind = struct.unpack_from("<II", data, offset)
        offset += 8
        chunk = data[offset:offset + length]
        if kind == 0x4E4F534A:
            document = json.loads(chunk)
        elif kind == 0x004E4942:
            binary = chunk
        else:
            raise ValueError("Unexpected GLB chunk")
        offset += length
    if document is None or len(document.get("buffers", [])) != 1:
        raise ValueError("Single embedded buffer required")
    if "uri" in document["buffers"][0]:
        raise ValueError("External buffer is outside this candidate pipeline")
    return document, binary


def write_glb(path, document, binary):
    document["buffers"][0]["byteLength"] = len(binary)
    text = json.dumps(document, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    text += b" " * (-len(text) % 4)
    binary += b"\0" * (-len(binary) % 4)
    data = (struct.pack("<III", 0x46546C67, 2, 28 + len(text) + len(binary))
            + struct.pack("<II", len(text), 0x4E4F534A) + text
            + struct.pack("<II", len(binary), 0x004E4942) + binary)
    with path.open("xb") as stream:
        stream.write(data)


def named_meshes(document):
    result = {}
    for node in document.get("nodes", []):
        if "mesh" not in node:
            continue
        name = node.get("name")
        if not name or name in result:
            raise ValueError("Unique named mesh nodes required")
        result[name] = node["mesh"]
    return result


def triangles(document):
    return sum(document["accessors"][part.get("indices", part["attributes"]["POSITION"])]["count"] // 3
               for mesh in document["meshes"] for part in mesh["primitives"])


def contract(document):
    nodes = named_meshes(document)
    parts = []
    for name, index in nodes.items():
        mesh = document["meshes"][index]
        rows = []
        for primitive in mesh["primitives"]:
            position = document["accessors"][primitive["attributes"]["POSITION"]]
            count = document["accessors"][primitive.get("indices", primitive["attributes"]["POSITION"])]["count"]
            rows.append({"material": primitive["material"], "triangles": count // 3,
                         "attributes": list(primitive["attributes"]),
                         "min": position["min"], "max": position["max"]})
        parts.append({"node": name, "mesh_index": index, "primitives": rows})
    return {"mesh_nodes": len(nodes), "surface_count": sum(len(p["primitives"]) for p in parts),
            "triangles": triangles(document), "material_count": len(document.get("materials", [])),
            "material_names": [m.get("name") for m in document.get("materials", [])],
            "nodes_with_exact_local_transforms": copy.deepcopy(document["nodes"]),
            "scenes": copy.deepcopy(document.get("scenes", [])), "parts": parts}


def transplant(source, source_binary, geometry, geometry_binary, bounds_tolerance):
    """Copy only new geometry accessors; preserve all source scene/image data."""
    result = copy.deepcopy(source)
    original = named_meshes(source)
    changed = named_meshes(geometry)
    if set(original) != set(changed):
        raise ValueError("Mesh node names/hierarchy would change")
    material_names = [row.get("name") for row in source.get("materials", [])]
    if len(material_names) != len(set(material_names)):
        raise ValueError("Unique original material names required")
    geometry_names = [row.get("name") for row in geometry.get("materials", [])]
    view_offset = len(result.get("bufferViews", []))
    accessor_offset = len(result.get("accessors", []))
    binary_offset = len(source_binary)
    if binary_offset % 4:
        raise ValueError("Original GLB binary must be aligned")
    for view in geometry.get("bufferViews", []):
        row = copy.deepcopy(view)
        row["buffer"] = 0
        row["byteOffset"] = row.get("byteOffset", 0) + binary_offset
        result.setdefault("bufferViews", []).append(row)
    for accessor in geometry.get("accessors", []):
        row = copy.deepcopy(accessor)
        if "sparse" in row or "bufferView" not in row:
            raise ValueError("Sparse or missing geometry accessor is unsupported")
        row["bufferView"] += view_offset
        result.setdefault("accessors", []).append(row)
    records = []
    for name, original_index in original.items():
        old_parts = source["meshes"][original_index]["primitives"]
        new_parts = geometry["meshes"][changed[name]]["primitives"]
        if len(old_parts) != len(new_parts):
            raise ValueError(f"{name}: material surface count changed")
        mapped = {}
        for part in new_parts:
            if part.get("mode", 4) != 4 or "extensions" in part or "targets" in part:
                raise ValueError(f"{name}: unexpected geometry feature")
            material = material_names.index(geometry_names[part["material"]])
            if material in mapped:
                raise ValueError(f"{name}: duplicated material surface")
            mapped[material] = part
        prepared = []
        max_bounds_error = 0.0
        surfaces = []
        for old in old_parts:
            material = old["material"]
            if material not in mapped:
                raise ValueError(f"{name}: original material slot missing")
            new = copy.deepcopy(mapped[material])
            if not set(old["attributes"]).issubset(new["attributes"]):
                raise ValueError(f"{name}: UV/normal/tangent attribute missing")
            old_position = source["accessors"][old["attributes"]["POSITION"]]
            new_position = geometry["accessors"][new["attributes"]["POSITION"]]
            differences = {}
            for key in ("min", "max"):
                error = max(abs(a - b) for a, b in zip(old_position[key], new_position[key]))
                max_bounds_error = max(max_bounds_error, error)
                differences[key + "_delta"] = [b - a for a, b in zip(old_position[key], new_position[key])]
            if max_bounds_error > bounds_tolerance:
                raise ValueError(f"{name}: material surface bounds shifted {max_bounds_error:.6f}m")
            new["material"] = material
            new["attributes"] = {key: value + accessor_offset for key, value in new["attributes"].items()}
            new["indices"] += accessor_offset
            prepared.append(new)
            surfaces.append({"material": material, "source_min": old_position["min"],
                             "source_max": old_position["max"], "candidate_min": new_position["min"],
                             "candidate_max": new_position["max"], **differences})
        result["meshes"][original_index]["primitives"] = prepared
        records.append({"node": name, "bounds_error_m": max_bounds_error,
                        "material_slots_preserved": [p["material"] for p in prepared], "surfaces": surfaces})
    # These are byte-for-byte JSON values from the original; image bufferViews
    # still point into the unmodified original prefix of the binary buffer.
    preserved = ("nodes", "scenes", "scene", "materials", "textures", "images", "samplers")
    if any(result.get(key) != source.get(key) for key in preserved):
        raise ValueError("Original scene/material/image metadata changed")
    return result, source_binary + geometry_binary, records


def triangle_count(mesh):
    mesh.calc_loop_triangles()
    return len(mesh.loop_triangles)


def geometry_snapshot(mesh):
    mesh.calc_loop_triangles()
    return ([vertex.co.copy() for vertex in mesh.vertices],
            [tuple(face.vertices) for face in mesh.loop_triangles])


def sampled_surface_error(before, after, limit):
    from mathutils.bvhtree import BVHTree
    original_tree = BVHTree.FromPolygons(*before, all_triangles=True)
    candidate_tree = BVHTree.FromPolygons(*after, all_triangles=True)
    worst = 0.0
    count = 0
    for (vertices, faces), tree in ((before, candidate_tree), (after, original_tree)):
        points = [*vertices]
        points.extend((vertices[a] + vertices[b] + vertices[c]) / 3 for a, b, c in faces)
        for point in points:
            hit = tree.find_nearest(point)
            if hit[0] is None:
                raise ValueError("Empty candidate/original surface")
            worst = max(worst, float(hit[3]))
            count += 1
            if worst > limit:
                raise ValueError(f"Surface sample displaced {worst:.6f}m > {limit:.6f}m")
    return {"samples": count, "max_sampled_surface_error_m": worst}


def simplify(row, run_dir, output_dir, manifest):
    import bpy
    source_path = ROOT / row["source"]
    if sha(source_path) != row["sha256"]:
        raise ValueError("Canonical source SHA does not match frozen manifest")
    source, source_binary = read_glb(source_path)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    # Importer merges only co-located vertices with compatible normals. No
    # position-only remove_doubles: adjoining clipped/slab components stay safe.
    bpy.ops.import_scene.gltf(filepath=str(source_path), merge_vertices=True)
    meshes = {obj.name: obj for obj in bpy.context.scene.objects if obj.type == "MESH"}
    if set(meshes) != set(named_meshes(source)):
        raise ValueError("Importer changed mesh names")
    reports = []
    for name, obj in meshes.items():
        before = geometry_snapshot(obj.data)
        count_before = len(before[1])
        target_ratio = row.get("mesh_ratios", {}).get(name, row["target_ratio"])
        bpy.ops.object.select_all(action="DESELECT")
        obj.select_set(True)
        bpy.context.view_layer.objects.active = obj
        # First remove coplanar tessellation, preserving material/UV/sharp seams
        # and open cut boundaries. Then one collapse pass only if still needed.
        planar = obj.modifiers.new("LOD_Coplanar_Once", "DECIMATE")
        planar.decimate_type = "DISSOLVE"
        planar.angle_limit = math.radians(manifest["planar_angle_degrees"])
        planar.use_dissolve_boundaries = False
        planar.delimit = {"NORMAL", "MATERIAL", "SEAM", "SHARP", "UV"}
        bpy.ops.object.modifier_apply(modifier=planar.name)
        after_planar = triangle_count(obj.data)
        target_count = max(4, math.ceil(count_before * target_ratio))
        if after_planar > target_count:
            collapse = obj.modifiers.new("LOD_Collapse_Once", "DECIMATE")
            collapse.decimate_type = "COLLAPSE"
            collapse.ratio = target_count / after_planar
            collapse.use_collapse_triangulate = True
            bpy.ops.object.modifier_apply(modifier=collapse.name)
        after = geometry_snapshot(obj.data)
        distance = sampled_surface_error(before, after, manifest["max_sampled_surface_error_m"])
        reports.append({"node": name, "before": count_before, "after_planar": after_planar,
                        "after": len(after[1]), "requested_ratio": target_ratio, **distance})
    geometry_path = run_dir / (row["id"] + "_geometry.glb")
    # Geometry export deliberately omits image work. Final candidates retain
    # original encoded images/material definitions through transplant().
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.export_scene.gltf(filepath=str(geometry_path), export_format="GLB",
                             use_selection=True, export_materials="EXPORT", export_image_format="NONE",
                             export_normals=True, export_tangents=True, export_texcoords=True,
                             export_animations=False, export_cameras=False, export_lights=False,
                             export_yup=True, export_apply=False)
    geometry, geometry_binary = read_glb(geometry_path)
    final, final_binary, bounds = transplant(source, source_binary, geometry, geometry_binary,
                                            manifest["max_surface_bounds_error_m"])
    before_count, after_count = triangles(source), triangles(final)
    ratio = after_count / before_count
    if ratio > manifest["max_retained_triangle_ratio"]:
        raise ValueError(f"Insufficient simplification: retained {ratio:.3f}")
    output_path = output_dir / (row["id"] + "_lod.glb")
    # Blend remains an editable simplified source. Canonical blends are never opened.
    bpy.ops.file.pack_all()
    blend_path = run_dir / (row["id"] + "_editable.blend")
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), check_existing=False)
    write_glb(output_path, final, final_binary)
    check, _ = read_glb(output_path)
    if triangles(check) != after_count:
        raise ValueError("Written candidate geometry readback failed")
    return {"id": row["id"], "status": "candidate_needs_camera_and_collision_review",
            "source": row["source"], "source_sha256": row["sha256"],
            "candidate": str(output_path.relative_to(ROOT)), "candidate_sha256": sha(output_path),
            "editable_blend": str(blend_path.relative_to(ROOT)),
            "triangles_before": before_count, "triangles_after": after_count,
            "source_contract": contract(source), "candidate_contract": contract(final),
            "retained_ratio": ratio, "mesh_reports": reports, "bounds_reports": bounds,
            "original_nodes_materials_images_preserved": True,
            "collision_generated_or_modified": False, "camera_verified": False}


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--run-dir", required=True, type=Path)
    parser.add_argument("--output-dir", required=True, type=Path)
    parser.add_argument("--asset", default="all")
    args = parser.parse_args(sys.argv[sys.argv.index("--") + 1:])
    manifest = json.loads((HERE / "manifest.json").read_text(encoding="utf-8"))
    args.run_dir = args.run_dir.resolve()
    args.output_dir = args.output_dir.resolve()
    if not args.run_dir.is_relative_to(HERE / "runs"):
        raise ValueError("Run output must stay in this source directory")
    if not args.output_dir.is_relative_to(ROOT / "assets/v3/environment/i2_visual_lod"):
        raise ValueError("Candidate output escaped assigned directory")
    records = []
    began = time.monotonic()
    report_path = args.run_dir / "result.json"
    for row in manifest["assets"]:
        if args.asset not in ("all", row["id"]):
            continue
        start = time.monotonic()
        print("I2_LOD_BEGIN " + row["id"], flush=True)
        try:
            record = simplify(row, args.run_dir, args.output_dir, manifest)
        except Exception as error:
            # One attempt, no alternate export/rebake/iterative retuning.
            record = {"id": row["id"], "status": "cancelled", "reason": str(error)}
            print("I2_LOD_CANCEL " + row["id"] + " " + str(error), flush=True)
        record["seconds"] = round(time.monotonic() - start, 3)
        records.append(record)
        report_path.write_text(json.dumps({"records": records, "elapsed_seconds": time.monotonic() - began,
                                          "production_integrated": False}, ensure_ascii=False, indent=2), encoding="utf-8")
        print("I2_LOD_END " + row["id"] + " " + record["status"], flush=True)
    if not records:
        raise ValueError("Unknown asset id")


if __name__ == "__main__":
    main()
