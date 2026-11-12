# Native finished-build graphics profile

Run this deliberately only when ready for the final game window to open:

```powershell
.\tools\run_graphics_profile.ps1 -Executable G:\Cady\KDTD.exe -ProfileName optimized -Mode both
```

The native game first runs capped at 60 FPS, then uncapped. Each invocation
requests `--power-profile`: 1,200 measured intervals in each forest far/near
phase and in each additional biome stress phase. It closes itself after the
benchmark, screenshots and galleries. `-Mode capped60` / `-Mode uncapped`
selects one pass. `-Quick` requests the original 300-interval measurement.

`-ForceHighDetail` disables compact character meshes for a controlled comparison
within the same finished build. It does not restore earlier rendering code or
disable unrelated world optimizations. `-ValidateOnly` prints planned arguments
and opens no game window.

Outputs are grouped under `Builds/GraphicsProfiles/<ProfileName>-<timestamp>/`:

- `capped60/` and/or `uncapped/` each contain raw `samples.csv`, engine/stdout/
  stderr logs, native `benchmark.json`, screenshots and `summary.json`.
- The outer `summary.json` combines both runs without overwriting older results.

The sampler observes only the PID it launched. CPU percent is normalized by
the logical CPU count; one-core percent can exceed 100. Memory is working set
and private bytes. Windows formatted GPU counters are filtered to
`pid_<PID>_*_engtype_3D`; max is the busiest matching engine and sum can exceed
100 across engines/adapters. These are not whole-adapter utilization and are
not GPU frame-time queries. Missing counters stay null, including query errors.

The benchmark prints UTC, Unix and monotonic phase timestamps. The runner
correlates OS samples after completion, so image captures and loading remain
separate from `far`, `near` and `biome_*_stress`. Active high/compact mesh counts,
their vertex buffer totals, actual `Engine.max_fps`, VSync and render resolution
are recorded by the game. Counts are scene resources, not a claim about final
GPU-visible vertices after culling. A phase with fewer than five OS samples
does not support stable utilization percentiles.

An explicitly selected legacy executable is supported, for example:

```powershell
.\tools\run_graphics_profile.ps1 -Executable G:\Cady\Recovery\KDTD.previous.exe -ProfileName baseline -Mode uncapped
```

Old builds can ignore new arguments, use only 300 frames or write the previous
fixed benchmark path. The runner copies a newly written legacy report when
needed and preserves unknown phase labels. Requested mode is not proof of an
old build's actual cap. Whole-process/unknown GPU samples include loading,
capture and gallery activity; they must not be described as stress-scene GPU
utilization or compared as though workloads were matched. Do not launch old
builds when the user has requested final-build testing only.

Normal completion waits for automatic exit. The timeout kills only the PID
created by this invocation; it does not close unrelated game instances.
