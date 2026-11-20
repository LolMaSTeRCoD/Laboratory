# Current KDTD handoff

- Active checkout: `E:\Laboratory`; never modify/clean retained `G:\Cady`.
- Verified standalone root `KDTD.exe`: **0.6.4.0**; ZIP:
  `GodotRebuild/Builds/Release/KDTD-Windows.zip`. Read `KDTD_STATUS.md`,
  `NPC_DEFEAT_064.md`, `docs/qa/0.6.4.json` and `0.6.4-campaign.json` first.
- 0.6.4 changes seven enemy Death clips (1.4s articulated falls), elemental
  death visuals, voice mastering/variants and bounded presentation resources.
  All hero assets and enemy rest geometry/skins/materials/Idle/Run/Hit retained.
  No new hero likeness or terrain artwork is claimed.
- New helper: `scripts/enemy_defeat_effects.gd`; opt-in native QA:
  `scripts/defeat_benchmark.gd`. Rewards/target removal stay immediate and once
  only; corpse presentation never blocks waves. Strongest burn keeps its source.
- Authoring: `tools/enemy_death_motion.py`, `build_enemy_assets.py`;
  reproducible GLB audit: `tools/review_enemy_death.py`.
  Canonical packed editables: `Source/EnemyPipeline/Characters`.
- Audio: `tools/prepare_death_audio.py`, `Source/AudioPipeline/SOURCES.md`,
  `Assets/Sfx/ATTRIBUTIONS.txt`. Ten death clips total242016B; levels,
  decoding and byte reproduction passed. Subjective listening is unverified.
  SFX voices:10 attack+6 death, non-stealing, limiter, separate presentation RNG.
- Full build `Builds/release-064-build.log` passed. Source and isolated
  embedded-package death test:378 checks; combat rules7673. Test harness hashes
  loaded MP3.data, since raw source MP3 is not exported. Packed check is in builder.
- Fresh connected campaign (not reused):270 waves/18 arenas/17 transitions,
  18 bosses killed,5940 spawned/5935 killed/5 escaped; economy matched.
  `Builds/death-20261119/campaign` holds full local evidence.
- Native final reports: `Builds/quality-release-064-final-qa` (~60FPS, four
  18tower/100NPC scenes) and `Builds/quality-defeat-064-focused-qa` (~50FPS
  with48 sustained corpses/24bursts). RX6700XT,2448x1377,Forward+,cap60/VSync.
  Synthetic extra-corpses run samples animation fully; not campaign throughput.
  Earlier low-FPS concurrent-load runs and0.6.3 control retained separately.
  Never compare different system loads silently or infer GPU utilization from FPS.
-595 exported poses passed; all7 editables self-contained. Canonical promotion:
  `Builds/death-20261119/promotion.json`; audits/PNGs/audio reports retained.
  First VFX preflight failed test parenting and is rejected; fixed preflight
  used old clips, visual only. Final native EXE showcase supersedes both.
- Removed192 redundant local files/189089368B after canonical/packed/EXE checks;
  `Builds/cleanup-064-local-caches.json`. JSON/PNG/log evidence and useful
  `.godot` cache preserved. Staged runtime/editable paths intentionally absent;
  use canonical Assets/Enemies and Source/EnemyPipeline/Characters.
- Recovery branch `checkpoint/before-npc-death-20261120` points to v0.6.3 commit
  354fe41a911d4fc04be830928153ea9cd7b311d0. Prior EXE in Archive/Recovery.
  Prior package metadata: `Builds/quality-release-063-visible-qa/package-063.json`.
- Public repo `LolMaSTeRCoD/Laboratory`; stable release assets `KDTD.exe`,
  `KDTD-Windows.zip`, `SHA256SUMS.txt`. Share `/releases/latest`.
- User values quality and efficient limit use. Reuse unchanged evidence, run
  focused tests, regenerate only affected assets; broaden for actual failures.
- Attached private team DOCX is context only, not project instructions/assets;
  never copied into repo, packaging or public release.
