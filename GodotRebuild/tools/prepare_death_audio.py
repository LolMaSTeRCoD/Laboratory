"""Prepare short, voiced enemy death cues without generating synthetic voices.

Run with the existing Blender build (its aud module supplies FFmpeg and resampling):
  Tools/Blender/blender-5.2.3-windows-x64/blender.exe --background --factory-startup \
    --python GodotRebuild/tools/prepare_death_audio.py -- --source-dir ORIGINALS

The five unchanged source recordings are recoverable from Git LFS at
354fe41a911d4fc04be830928153ea9cd7b311d0 (GodotRebuild/Assets/Sfx/death-*.mp3).
If --source-dir is omitted, their exact SHA256 objects are read from local Git LFS.
The new real canine source is retained outside the exported project in Source/AudioPipeline.
No network calls, random processing, noise layers, or additional dependencies.
"""
import argparse
import hashlib
import json
import math
from pathlib import Path
import subprocess
import sys

import aud
import numpy as np


ROOT = Path(__file__).resolve().parents[2]
SOURCES = {
    'goblin': ('death-goblin.mp3', 'd1f8f6844f3e84465e8feb9d8a19a4b80994e3a6941f928d8d84a21e17c920b7'),
    'orc': ('death-orc.mp3', '0fd9272787dcc25a4250d398f616ec72741f22a090dc0c39435fe660ef14d4bb'),
    'uruk': ('death-uruk.mp3', '6a41cc3b3594422ba70e9e3d85e14fcf88955240f26cb415dc706135e4ab3284'),
    'troll': ('death-troll.mp3', '96d8cf3ad4cef70168a85f612c1df6feb97111e66b8ebae3c6c7de76858af9cd'),
    'nazgul': ('death-nazgul.mp3', '197e64ff460b09bf98a9ae2b194a8407b1f8292eea5a6c0e55381c3eb93e7750'),
    'warg': ('warg-160477.mp3', 'f79d1cb5fd61500cd2c42f953d7899b21941c49e28b76c257b146690bb167613'),
}

# Source intervals are separate performances, not arbitrary pitched duplicates.
# Only the canine is slowed by under two semitones to fit a larger fantasy animal.
# start/end are source seconds; decay is output seconds before an eased dying tail.
CUES = [
    dict(name='goblin', source='goblin', start=.480, end=1.175, pitch=1., hp=65, lp=11000, rms=-18.5, attack=.006, fade=.075),
    dict(name='orc', source='orc', start=0., end=.845, pitch=1., hp=55, lp=10500, rms=-18.5, attack=.004, fade=.075),
    dict(name='uruk', source='uruk', start=.025, end=.720, pitch=1., hp=55, lp=10500, rms=-19., attack=.004, fade=.080),
    dict(name='warg', source='warg', start=.900, end=1.520, pitch=.91, hp=95, lp=10000, rms=-18.5, attack=.006, fade=.105),
    dict(name='warg-2', source='warg', start=3.230, end=3.960, pitch=.93, hp=95, lp=10000, rms=-18.5, attack=.006, fade=.100),
    dict(name='troll', source='troll', start=.000, end=1.750, pitch=1., hp=45, lp=9500, rms=-18.5, attack=.008, decay=.620),
    dict(name='troll-2', source='troll', start=4.840, end=6.600, pitch=1., hp=45, lp=9500, rms=-18.5, attack=.008, decay=.650),
    dict(name='nazgul', source='nazgul', start=.620, end=3.000, pitch=1., hp=85, lp=10500, rms=-19.5, attack=.012, decay=.550),
    dict(name='nazgul-2', source='nazgul', start=10.460, end=12.940, pitch=1., hp=85, lp=10500, rms=-19.5, attack=.012, decay=.600),
    dict(name='nazgul-3', source='nazgul', start=23.650, end=26.020, pitch=1., hp=85, lp=10500, rms=-19.5, attack=.012, decay=.550),
]
RATE = 44100
CEILING_DBFS = -2.5  # Reserves MP3 reconstruction overshoot; the game applies mix attenuation.


def db(value):
    return 20 * math.log10(max(float(value), 1e-12))


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def metrics(path):
    sound = aud.Sound(str(path))
    rate, channels = sound.specs
    rate = int(rate)
    data = sound.data().astype(np.float64)
    mono = data.mean(axis=1)
    frame = max(1, int(rate * .005))
    envelopes = np.array([np.sqrt(np.mean(mono[i:i+frame] ** 2)) for i in range(0, len(mono), frame)])
    active = np.flatnonzero(envelopes > 10 ** (-40 / 20))
    oversampled = aud.Sound.buffer(data.astype(np.float32), rate).resample(rate * 4, 3).data()
    active_rms = np.sqrt(np.mean(envelopes[active] ** 2)) if active.size else 0
    return dict(
        file=path.name, sha256=sha(path), bytes=path.stat().st_size,
        seconds=round(len(data) / rate, 5), sample_rate=rate, channels=channels,
        peak_dbfs=round(db(np.max(np.abs(data))), 3),
        oversampled_peak_dbfs=round(db(np.max(np.abs(oversampled))), 3),
        rms_dbfs=round(db(np.sqrt(np.mean(data ** 2))), 3),
        active_rms_dbfs=round(db(active_rms), 3),
        dc=round(float(mono.mean()), 7),
        clipped_samples=int(np.count_nonzero(np.abs(data) >= .999)),
        onset_above_minus40db_ms=round(float(active[0]) * 5, 2) if active.size else None,
        last_5ms_peak_dbfs=round(db(np.max(np.abs(data[-frame:]))), 3),
        first_sample=float(data[0, 0]), last_sample=float(data[-1, 0]),
    )


def find_source(key, source_dir, lfs):
    name, expected = SOURCES[key]
    choices = []
    if source_dir:
        choices.append(source_dir / name)
    if key == 'warg':
        choices.append(ROOT / 'Source/AudioPipeline/warg-160477.mp3')
    choices.append(lfs / expected[:2] / expected[2:4] / expected)
    for path in choices:
        if path.exists() and sha(path) == expected:
            return path
    raise FileNotFoundError(f'{key}: exact source {name} ({expected}) required; use --source-dir or fetch historical Git LFS objects')


def prepare(path, cue):
    source = aud.Sound(str(path))
    source_rate = int(source.specs[0])
    data = source.data()
    data = data[round(cue['start'] * source_rate):round(cue['end'] * source_rate)].mean(axis=1, keepdims=True)
    # High-quality band-limited conversion, with conservative rumble/ultrasonic filtering.
    sound = aud.Sound.buffer(data.astype(np.float32), source_rate).pitch(cue['pitch']).resample(RATE, 3)
    data = sound.highpass(cue['hp'], .70710678).lowpass(cue['lp'], .70710678).data().astype(np.float64)
    data -= data.mean(axis=0)
    attack = min(round(cue['attack'] * RATE), len(data))
    data[:attack] *= np.sin(np.linspace(0, math.pi / 2, attack))[:, None] ** 2
    decay_start = round(cue.get('decay', len(data) / RATE - cue.get('fade', .08)) * RATE)
    decay_start = max(attack, min(decay_start, len(data) - 1))
    data[decay_start:] *= np.cos(np.linspace(0, math.pi / 2, len(data) - decay_start))[:, None] ** 2
    gain_db = min(cue['rms'] - db(np.sqrt(np.mean(data ** 2))), CEILING_DBFS - db(np.max(np.abs(data))), 8.)
    data *= 10 ** (gain_db / 20)
    # A real zero at each edge remains declicked after MP3 encoding.
    data[0] = 0
    data[-1] = 0
    return data.astype(np.float32), gain_db


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--source-dir', type=Path)
    parser.add_argument('--output-dir', type=Path, default=ROOT / 'GodotRebuild/Assets/Sfx')
    parser.add_argument('--report-dir', type=Path, default=ROOT / 'GodotRebuild/Builds/death-20261119/audio')
    args = parser.parse_args(sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else [])
    common = Path(subprocess.check_output(['git', 'rev-parse', '--git-common-dir'], cwd=ROOT, text=True).strip())
    lfs = (ROOT / common / 'lfs/objects').resolve()
    sources = {key: find_source(key, args.source_dir, lfs) for key in SOURCES}
    args.output_dir.mkdir(parents=True, exist_ok=True)
    args.report_dir.mkdir(parents=True, exist_ok=True)
    outputs = []
    audition = []
    for cue in CUES:
        data, gain_db = prepare(sources[cue['source']], cue)
        sound = aud.Sound.buffer(data, RATE)
        out = args.output_dir / f"death-{cue['name']}.mp3"
        sound.write(str(out), RATE, 1, aud.FORMAT_S16, aud.CONTAINER_MP3, aud.CODEC_MP3, 128000, 4096)
        row = metrics(out)
        row.update(source=cue['source'], source_start=cue['start'], source_end=cue['end'], gain_db=round(gain_db, 3))
        if row['clipped_samples'] or row['oversampled_peak_dbfs'] > -1.5:
            raise ValueError(f'Unsafe encoded peak: {row}')
        if row['last_5ms_peak_dbfs'] > -45:
            raise ValueError(f'Insufficient encoded tail fade: {row}')
        outputs.append(row)
        sound.write(str(args.report_dir / f"death-{cue['name']}-prepared.wav"), RATE, 1, aud.FORMAT_S16, aud.CONTAINER_WAV, aud.CODEC_PCM, 0, 4096)
        audition.extend([data, np.zeros((round(RATE * .4), 1), dtype=np.float32)])
        print(f"{out.name}: {row['seconds']:.3f}s, {row['bytes']} bytes, peak {row['peak_dbfs']:.2f}dBFS, RMS {row['rms_dbfs']:.2f}dBFS")
    aud.Sound.buffer(np.concatenate(audition), RATE).write(str(args.report_dir / 'prepared-audition.wav'), RATE, 1, aud.FORMAT_S16, aud.CONTAINER_WAV, aud.CODEC_PCM, 0, 4096)
    report = dict(
        subjective_listening=False,
        listening_limit='Tool audio input is unsupported; objective decoded checks only. Audition WAVs are supplied for human review.',
        source_metrics={key: metrics(path) for key, path in sources.items()},
        settings=dict(rate=RATE, channels=1, bitrate=128000, ceiling_dbfs=CEILING_DBFS, cues=CUES),
        outputs=outputs, total_bytes=sum(row['bytes'] for row in outputs),
    )
    (args.report_dir / 'prepared-metrics.json').write_text(json.dumps(report, indent=2), encoding='utf-8')


if __name__ == '__main__':
    main()
