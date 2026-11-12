# Enemy geometry credits

Humanoid anatomical topology, original UV coordinates, skin weights and the
base skeleton use **MakeHuman hm08 / MakeHuman Community, CC0 1.0 Universal**.
The retained source files are `base.obj`, `default.mhskel` and
`default_weights.mhw` in `G:/Cady/Source/HeroPipeline/MakeHuman`; the original
`license.txt` documents the CC0 asset release separately from the MakeHuman
application's source-code license.

Creature proportions and facial/pectoral sculpts, fitted clothing, armor,
weapons, hair clumps, oral cavities, procedural PBR materials and animation
clips were authored/generated for this project. The warg has a project-built
lofted quadruped mesh and a separate project-built 22-bone rig.

Existing project enemy sprites in `G:/Cady/Assets/Enemies` were used as visual
references, not projected character textures. The geometry is not an
official or extracted *The Lord of the Rings* asset. Its character/creature
designs and names remain the property of their respective rights holders;
MakeHuman's CC0 topology does not grant rights to those character designs.

Editable models: `G:/Cady/Source/EnemyPipeline/Characters`.
Reproduction: `G:/Cady/GodotRebuild/tools/build_enemy_assets.py` and its
`enemy_mesh_core.py` / `enemy_face_details.py` helpers.
