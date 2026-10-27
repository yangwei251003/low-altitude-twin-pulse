# P3 — dense double-bar tread, baked normal candidate

Static preparation only. Root viewed P2 beside the native reference and rejected the sparse scratch-like deck. P2's exact source/PNG/log are retained; no statement of visual acceptance. P2 PID43412 naturally exited 0 in 45.766s, one image only, 21 model meshes / 35,052 evaluated triangles / two source materials / 42 surfaces; 66 structural checks and input hashes held. Its actual image is `../p2/source_review_20261019_094556_fe91bd/01-east-4m-module.png`, SHA `2c943645770b65c24a1266731d2e82b5172f7aaeb21498e0ea298393ea1b70cc`.

## Limited P3 change

Restore a dense, manufactured anti-slip sheet rather than sparse individually visible marks. Pitch 95mm, alternating ±45° pairs, each short ridge 60×8mm, pair-center spacing17mm, crest1.8mm. Sixteen cells/32 short ridges form an editable380×380mm high-poly patch. All relief stays inside the periodic border; the tile has a flat source plane underneath, so low areas receive real normals rather than missing rays.

`normal_tile.py` will use Blender's native selected-to-active tangent-normal bake, CPU2,512², explicit `TreadUV`, then reopen the saved PNG and require actual non-flat pixel coverage. No texture is fabricated with Python. High geometry and its receiver stay in a separately named hidden source collection, editable in the saved source. They are not part of the21 model meshes or a runtime collision.

The actual landing models no longer contain thousands of tread prisms: the full fixed assembly has12,532 pre-bevel triangles, with0 tread pieces, before any engine run. Source dimensions, the correct-size21 modules, guards, shoulders and original body envelopes remain. The four low plate fixings stay real geometry. Only walking-plate top faces carry the normal; fasteners, frame trim, vertical edges and guards do not. `TreadUV` is explicit physical X/Z divided by0.38m, with its own matching tangent frame. It is independent of the weather-image UV and active bake UV.

The approved P4 steel colors and metallic response remain. Local walking polish reduces roughness by up to0.17 from the base0.61 while unpolished/abraded regions retain roughly0.61–0.69. No white color is added to imitate glare. The existing finite dark scuffs and plate joints remain. Guard paint/geometry are untouched in this limited round; optional stronger edge metal is not added before the deck can be judged.

Same P1/P2 camera `(0,4.5,-5.5)`→`(4.7,.22,.3)`, ortho7.5m, same studio lights/exposure/12samples; one isolated east4m module PNG only. Full source remains editable. No runtime GLB, no gameplay/collision claim, no global asset write.

After root allocates a serialized window:

```powershell
python -u asset_sources/v3/shared_access_landings/p3/run_source.py --run-authorized-once
```

Hidden CPU2,240s own-tree bound. The normal bake precedes the one source preview and has a separate PNG/report checkpoint. If either fails, keep its original log and report before further work. Static AST/66 source checks are available; native bake, tangent correctness and actual appearance are not yet verified.
