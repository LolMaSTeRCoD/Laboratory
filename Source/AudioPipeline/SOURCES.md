# Enemy death voice preparation

The exported cues are authored by `GodotRebuild/tools/prepare_death_audio.py`.
Use the existing Blender executable; no Python packages or audio tools need installing.
The script reads and verifies immutable source bytes, uses Blender's high quality
resampling/FFmpeg, then checks the decoded MP3 results. It does not fetch any network data.

Five previous Freesound preview masters remain recoverable from Git LFS history at
`354fe41a911d4fc04be830928153ea9cd7b311d0`, under `GodotRebuild/Assets/Sfx/death-*.mp3`.
Their exact content SHA256 values are embedded in the script. Keep historical LFS
objects available, or pass a directory containing the original files with `--source-dir`.
The old Warg source is recoverable in that same revision; it is no longer used.

The new source `warg-160477.mp3` is the high-quality preview of **Dog's Yelping 6**,
recorded by **unfa** on a Zoom H2 (medium-sized dog). It replaces a short generic
growl with identifiable canine voice. Only two short phrases are exported, slowed
to 0.91/0.93 speed (under two semitones); there are no generated voice/noise layers.

- Author and license: https://freesound.org/people/unfa/sounds/160477/
- CC0 1.0: https://creativecommons.org/publicdomain/zero/1.0/
- Exact downloaded preview: https://cdn.freesound.org/previews/160/160477_1038806-hq.mp3
- SHA256: `f79d1cb5fd61500cd2c42f953d7899b21941c49e28b76c257b146690bb167613`
- Bytes: 300000; decoded 48 kHz stereo, 12.9532 seconds.
- Source and CC0 verified on 2026-11-19 against the original author page.

The original Goblin, Orc, Uruk, Troll and Wraith pages and licenses were also checked
on 2026-11-19. Their author credits, page links, license links and modification notice
are in `GodotRebuild/Assets/Sfx/ATTRIBUTIONS.txt`, which is included with the game.

```powershell
& .\Tools\Blender\blender-5.2.3-windows-x64\blender.exe `
  --background --factory-startup `
  --python GodotRebuild\tools\prepare_death_audio.py
```

Reports and individual WAVs are written to `GodotRebuild/Builds/death-20261119/audio`.
The concatenated `prepared-audition.wav` plays the ten cues in the script's order,
with 400 ms silence between them. These are for human review. Audio input is not
supported by the agent's tools, so this iteration verifies decoded signal quality,
source provenance and timing; it does not claim subjective listening acceptance.
