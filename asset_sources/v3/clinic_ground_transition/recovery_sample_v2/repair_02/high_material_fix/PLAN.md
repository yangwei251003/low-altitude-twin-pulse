# High material display repair — static only

Read completed immutable blend and original high triangle mapping. Restore each high polygon material index from retained RepairHighFull at mapped source triangle. Keep existing three BoundaryGlobalAO material slots and shaders; no geometry, UV, Normal/BaseColor/ORM or low changes. Check original→copied slot identities and exact face-index mapping before/after reopening. Render high and unchanged low at same camera/light.

Expected110–130s; private CPU2 hard180s. Not authorized to run until root releases checkpoint window. No rebake/GLB or scope expansion.
