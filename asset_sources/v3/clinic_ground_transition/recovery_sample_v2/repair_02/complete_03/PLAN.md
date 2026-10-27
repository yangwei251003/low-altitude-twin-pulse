# Complete 03 — authorized shading tolerance

Retains complete_02 geometry/UV/topology and matched-group AO pipeline. Changes only double-component angle evaluation to atan2(cross,dot), logs raw/unit vector errors, and uses <=0.1 degree local-copy shading tolerance authorized by root. This is not bitwise normal identity. Position, UV, winding, footprint/overlap checks remain unchanged. Source Normal and BaseColor are not rebaked.

One CPU2 private 240s run: local boundary repair, 11-group AO with all high occluders, reopen exact source, locked-camera high/low renders. New substantive failure stops with diagnostic blend and logs.
