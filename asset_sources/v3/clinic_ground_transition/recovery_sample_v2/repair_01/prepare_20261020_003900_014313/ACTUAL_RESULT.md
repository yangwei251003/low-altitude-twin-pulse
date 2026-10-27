# Prepare actual result — FAIL, no bake

Blender PID11616 naturally exited0 in53.813s with0ERROR. The engine slot was returned and no further engine was launched. The original result.json says PASS, but its component validation was incomplete; this note and post_run_gate_audit.json explicitly supersede that readiness claim without rewriting the original evidence.

All1,965 originally negative-normal pixels have a real high hit and non-reversed geometric/interpolated corner normal. Ground top/side/bottom class checks pass. The independent component audit against projection_groups.json found **one wrong solid hit**: pixel(860,849), expected solid_05, hits solid_00 high triangle74 at1.391881mm ray distance; its normal differs by81.917897degrees. This is a reconstructable closed-source cross-component hit, not just a hypothetical padding fault. The script failed to test solid component identity.

The saved prepared_repair.blend preserves the actual scene and all projection tools. It is not approved for baking. Geometry/BakeUV digests are unchanged; copied target basis differences are at most0.033129degrees(normal) and0.033905degrees(tangent), with0sign flips. Corrected copied side source UV has8,192 positive-area triangles: minimumRocky1.2121302e-5, Sandy7.7576641e-6. Original67input files still match SHA.

The next decision should use this evidence: a matching-component source/cage-ray check can show whether the already prepared isolation removes the one wrong hit. Do not ignore the miss by dropping this pixel, changing the normal threshold, moving the stone, or relabeling the source. No script, cage, material or geometry change has been made following this run; root must decide the next bounded step.
