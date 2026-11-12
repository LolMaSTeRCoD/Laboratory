# Charmy Pappitson — preparation notes

Reference (official anime): https://bclover.jp/season1/sp/character/character09.php
Full-body image: https://bclover.jp/season1/sp/images/character/character_image09.jpg
Viewed 2026-11-07. Reference image is for artist comparison only, not embedded in GLB or shipped as a character billboard.

New geometry is produced by tools/build_hero_assets.py with CADY_HEROES=charmy.
Anatomical topology/weights source: MakeHuman hm08 CC0, as documented by the existing pipeline.
The figure has an independent short-body proportion pass, enlarged rounded head, swept-back high bun with sculpted strand ridges, green irises, loose cream tunic with a real front pocket, burgundy cropped trousers, low cream flats, a separate Black Bulls cape and a blue crossbody satchel.

Rigs: 166 bones, four largest normalized skin weights per vertex. Clips: charmy_Idle, charmy_Attack, charmy_Ability; idle breathing, head/hand motion and blink, two-arm cotton casting with bent knees, recovery pose. Body and clothes are 3D geometry, no face or body reference photo projected into the scene.

Visual stages: L1/L2 base costume; L3/L4 fitted cotton casting gauntlets and stitched pocket edging; L5 stronger gauntlets and a small sculpted sheep charm on the satchel. The five models match the game's five mechanical ranks.

Limit: a new stylized model based on the official reference, not a supplied production anime/game model. The face cannot be claimed to be an exact canonical reproduction. The cloth, anatomy and skinning were inspected through a Blender render, with hidden torso removed to prevent skin from showing through the tunic.