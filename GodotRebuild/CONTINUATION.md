# Current KDTD handoff

- Active checkout: `E:\Laboratory`; do not modify or clean `G:\Cady`.
- Working standalone game: root `KDTD.exe`, version **0.6.1.0**. Verified ZIP:
  `GodotRebuild/Builds/Release/KDTD-Windows.zip`. Results: `KDTD_STATUS.md`
  and root `docs/qa/0.6.1.json`.
- The 0.6.1 work and pre-cleanup state are saved locally in commit
  `972e4a810293c27b5887570616cf30d028fa5991`, branch
  `checkpoint/before-cleanup-20261115`. Main, including the cleanup summary
  commit `b20945a`, was pushed on 2026-11-15 to the public repository
  `LolMaSTeRCoD/Laboratory`. The latest published binary release is still
  v0.6.0; the verified 0.6.1 ZIP is local until explicitly published.
- New 2026-11-15 production connected-campaign acceptance passed: 270 waves,
  18 arenas, 17 transitions, all 18 final bosses killed, campaign won. NPC
  accounting and economy balance; no engine errors or leaks. Reports:
  `Builds/acceptance-061/report.json` and `campaign-connected-dual-aura.json`.
  This is headless production logic, not a manual GUI campaign playthrough.
- On 2026-11-15, reviewed obsolete workshop model/texture copies and raw LOD
  buffers were removed: **5,828,825,374 bytes / 6,820 files**. Details:
  `Builds/cleanup-20261115-result.json`. Current assets, editable source,
  EXE/ZIP, recovery build, Git/LFS, QA renders/logs and useful `.godot` cache
  remain. Canonical hashes and native startup passed after cleanup; all 14
  editable Blender files are self-contained.
- Old workshop `runtime`/`editable` paths in historical logs are now absent.
  Use `Assets/Heroes`, `Assets/Enemies` and root `Source/*Pipeline/Characters`.
  Do not regenerate old batches merely because historical paths are missing.
- Exact canonical character likeness remains unfinished. Small shoulder-seam
  intersections remain documented; automated checks do not certify likeness.
- User preference: maximize useful quality while avoiding redundant context,
  investigations, generation and tests. Use compact diagnostics, targeted
  regeneration and independent checks; broaden only for a real dependency or
  unresolved issue. Preserve this priority when more work is necessary.
