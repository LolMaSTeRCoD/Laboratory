# KDTD development

- The active local checkout on this workstation is `E:\Laboratory`. The previous
  `G:\Cady` copy is retained for the owner to review and remove. Make subsequent
  game changes and builds in the active checkout.
- Use the checkout root as the working directory. The active Godot project is
  `GodotRebuild/project.godot`; early C# sources are retained as project history.
- Preserve Git LFS for binary assets and editable Blender files. Do not commit
  `.godot`, `Builds`, `Archive`, installed `Tools`, or generated executables.
- `GodotRebuild/build_KDTD.ps1` resolves tools and output relative to the checkout.
  `-ReuseModels` skips model regeneration and retains the build validation steps.
- Keep `KDTD.exe` as the permanent launch/build filename at the checkout root.
- Historical cleanup plans can contain absolute paths to the old checkout.
  Regenerate and validate plans before any future cleanup; keep the location
  guards in the cleanup scripts.
- The external-source lockfile and study guides are in
  `development-tools.lock.json`, `docs/EXTERNAL_TOOLS.md`, and
  `docs/EXTERNAL_SOURCE_GUIDE.md`. Those sources are not automatically integrated
  into the game runtime.
- Check gameplay interactions when changing placement, combat, UI, camera or
  assets. Relevant headless tests are in `GodotRebuild/tests/`.
