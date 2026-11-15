# Current KDTD handoff

- Active checkout: `E:\Laboratory`; do not modify or clean `G:\Cady`.
- Verified standalone game: root `KDTD.exe`, **0.6.3.0**. ZIP:
  `GodotRebuild/Builds/Release/KDTD-Windows.zip`. Current results:
  `GodotRebuild/KDTD_STATUS.md`, root `docs/qa/0.6.3.json`.
- 0.6.3 changes only Asta hair/headband and occluded shoulder sleeves on five
  ranks. Other 25 hero GLBs/five editables remain byte-identical to 0.6.2.
  Source checkpoint: `checkpoint/before-asta-hair-20261115` at `77f34b4`;
  prior public release/tag v0.6.2 remains available for recovery.
- Full build, native model/packed-source audits, source isolation, gameplay
  regressions, isolated package checks and visible-window renderer passed.
  Reports: `Builds/release-063-build.log`, `Builds/asta-hair-20261115/final`,
  `Builds/asta-hair-20261115/promotion.json`, `Builds/quality-release-063-visible-qa`.
- Native profile: RX 6700 XT, Forward+, 2448x1377, capped60/VSync,
  18 towers/100 enemies, four 300-frame scenarios, mean about60 FPS.
  Winter camera is actually close (orthographic size17.747), not far.
  Use a visible native window for GPU timestamp measurements; an earlier
  background 0.6.2 test had stale counters. All owned game processes exited.
- Full connected campaign acceptance: 270 waves/18 arenas/17 transitions,
  victory,18 final bosses killed, balanced NPC/economy accounting, no errors.
  Actual run is 0.6.1, reused for0.6.3 by four identical input SHAs;
  `docs/qa/0.6.3-gameplay-reuse.json`. Not manual GUI play or a new full run.
- Removed this iteration's generated runtime/editable copies and raw LOD
  buffers only:295,183,258 bytes/332 files. Report:
  `Builds/cleanup-063-local-caches.json`; native startup passed afterwards.
  Canonical models/editable sources, EXE/ZIP, review PNGs, reports, patches,
  Git/LFS, recovery build and useful `.godot` import cache remain.
- Earlier reviewed cleanup removed5,828,825,374 bytes/6,820 files, then
  0.6.2 removed206,438,082 bytes/208 files. Historical workshop runtime/editable
  paths are intentionally absent. Use canonical `GodotRebuild/Assets/Heroes`,
  `GodotRebuild/Assets/Enemies` and `Source/*Pipeline/Characters`; do not
  regenerate obsolete prototypes just because old paths are missing.
- Public repository: `LolMaSTeRCoD/Laboratory`; releases keep the stable asset
  names `KDTD.exe`, `KDTD-Windows.zip`, `SHA256SUMS.txt`. Share `/releases/latest`.
  Verify uploaded asset digests and anonymous download links before reporting.
- Exact canonical likeness remains unfinished: face, individual hair clumps,
  rear layers and emblem need art refinement; a dark shoulder crease remains.
  Landscape/NPC artwork was unchanged in0.6.3 and remains an outstanding task.
- User preference: quality with careful limit use. Reuse valid evidence when
  inputs are unchanged; generate only affected heroes/ranks; review one real
  GLB prototype before expanding. Avoid duplicate investigations, simulations
  and full-context delegation; broaden tests only for changed dependencies.
