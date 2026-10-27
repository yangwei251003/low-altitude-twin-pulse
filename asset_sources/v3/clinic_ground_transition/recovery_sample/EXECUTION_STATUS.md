# Recovery sample — execution stopped

Stage A first attempt: PID 23812, exit 3, 1.672 s. Missing local module search path; failed inputs/logs preserved in `build_20261019_224648_006150`. Only the deterministic entrypoint path was corrected in both stage scripts.

Second attempt: PID 22984, exit 3, 5.578 s. `EditableEmbeddedAggregate_01` is buried 17.602 mm and exposed only 0.318 mm; the required 0.5 mm minimum exposed extent failed. This is a real construction failure, not a path/serialization issue. It stopped before checkpoint save, so no `.blend` or rendered PNG exists. Inputs/logs and exact measured offsets are retained in `build_20261019_225030_169314`.

No Stage B, baking, preview, GLB or runtime write occurred. No parameter or geometric repair was attempted after this failure. Engine window explicitly returned to root; original P13 and recovery_study remain untouched. Prepared README/manifest retain their historical pre-execution bytes.

## Authorized contact repair and completed comparison

Root authorized actual local-normal positioning of the existing six stones. Stage A PID 35868 exit 0 / 11.469 s; Stage B PID 36288 exit 0 / 114.969 s. See `ACTUAL_REVIEW.md`: height method has useful evidence, but baked low has black rim artifacts and both sources have side UV stretch. Visual result rejected, no automatic retry or export.
