# Character material atlases

`pack_character_materials.py` is a Blender-side preparation helper. It combines
the material regions of one skinned mesh into one material surface. It does not
alter geometry, normals, vertex groups, weights, skeletons, shape keys or clips.

Call it after constructing UVs and before exporting GLB:

```python
from pack_character_materials import pack_character_materials
report = pack_character_materials(
    character_object, "asta_L1", atlas_directory,
    resolution=2048, gutter=4,
)
```

The original generator directory must be on `sys.path`. For enemy generation,
call once for every selected skinned mesh, using a unique character/level tag.
For hero generation, call after `create_mesh` and before saving the editable
Blender file and exporting the GLB. Old material data can remain in Blender;
only the one material assigned to the mesh is exported.

The helper packs these channels:

- sRGB albedo, including correctly converted scene-linear material constants.
- ORM with roughness in green and metalness in blue.
- Auxiliary coat weight, coat roughness and specular level.
- Emission, when present, including emission strength.
- Tangent-space normal maps, when present, including normal strength.

An extruded gutter surrounds every cell to prevent neighboring material colors
bleeding through bilinear filtering. UV orientation is unchanged. A 2K atlas
with a 4×4 grid has 504px of content per cell; 512px source maps are bilinearly
resampled by about 1.6%. A 4K atlas avoids reducing the original texel count at
the cost of more texture memory. This optimization reduces material draw calls;
it does not reduce polygon count or improve character likeness.

Unsupported graphs, displacement, volume, transparency, nonstandard IOR,
transmission, anisotropy, sheen, alternate normal UVs, and repeating UV islands
outside `[0,1]` fail explicitly before the mesh is changed. Do not catch and
silently ignore these errors in the build. Blender subsurface scattering is
reported rather than baked: the existing glTF export does not support it either.

Validation artifacts are kept outside game assets in `Builds/atlas-validation`:

- Constant-color and UV-cell regression: `ATLAS_COLOR_TEST_OK`.
- Copied goblin round trip: 10 material surfaces to 1; 8,260 vertices, 9,426
  polygons, 21 bones, 21 weight groups and four animation clips are unchanged.
- The exported copied GLB has exactly one primitive and one material.
- EEVEE before/after rendering of the same copied model: mean RGB difference
  0.00102, 95th percentile 0.00392, maximum 0.01176 on opaque character pixels.
  Those small differences come from texture quantization/resampling. The test
  verified rendered appearance, not just shader node structure.

No production GLB or character generator was changed by validation. Performance
must still be measured in the final Godot build; this test does not claim an FPS
gain or a GPU-time result.

Production integration (4 November 2026): both `build_enemy_models.py` and
`build_hero_assets.py` now call this helper before exporting every variant.
The structural model smoke tests verify the imported skinned models. The
separate opt-in `KDTD.exe -- --render-benchmark` measures the complete rendered
game; its result is not a controlled before/after comparison of this packing
operation alone.
