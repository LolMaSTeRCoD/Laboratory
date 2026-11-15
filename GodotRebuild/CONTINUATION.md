# Current KDTD handoff

- Active checkout: `E:\Laboratory`; do not modify or clean `G:\Cady`.
- Working standalone game: root `KDTD.exe`, version **0.6.1.0**. Verified ZIP:
  `GodotRebuild/Builds/Release/KDTD-Windows.zip`. Results: `KDTD_STATUS.md`
  and root `docs/qa/0.6.1.json`.
- The 0.6.1 work and pre-cleanup state are saved locally in commit
  `972e4a810293c27b5887570616cf30d028fa5991`, branch
  `checkpoint/before-cleanup-20261115`. This cleanup did not publish a new
  GitHub release or push commits.
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
