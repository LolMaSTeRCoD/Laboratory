"""Read-only enemy GLB contract/contact audit and actual exported-pose review.

blender --background --python tools/review_enemy_death.py -- \
  --input Builds/death-20261119/enemy-final/runtime --baseline Assets/Enemies \
  --output-dir Builds/death-20261119/enemy-final/review --render key

--input accepts a GLB or directory; --kinds filters directories. No historical
Builds helpers, editable saves, Godot imports or canonical writes are required.
"""
import argparse
import hashlib
import json
import struct
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
from render_hero_review import select_pose, setup_studio

KINDS = ('goblin', 'orc', 'uruk', 'troll', 'nazgul', 'warg', 'boss_troll')
DTYPES = {5120: 'i1', 5121: 'u1', 5122: '<i2', 5123: '<u2', 5125: '<u4', 5126: '<f4'}
WIDTHS = {'SCALAR': 1, 'VEC2': 2, 'VEC3': 3, 'VEC4': 4, 'MAT4': 16}


def sha256(data):
    return hashlib.sha256(data).hexdigest()


def read_glb(path):
    """Minimal interleaved-accessor reader for embedded, non-sparse GLB v2."""
    raw = path.read_bytes()
    assert struct.unpack_from('<III', raw) == (0x46546c67, 2, len(raw)), path
    chunks = {}
    offset = 12
    while offset < len(raw):
        size, kind = struct.unpack_from('<II', raw, offset)
        offset += 8
        assert offset + size <= len(raw), path
        chunks[kind] = raw[offset:offset + size]
        offset += size
    doc = json.loads(chunks[0x4e4f534a])
    binary = chunks[0x004e4942]

    def view(index):
        item = doc['bufferViews'][index]
        assert item.get('buffer', 0) == 0
        start = item.get('byteOffset', 0)
        return binary[start:start + item['byteLength']]

    def accessor(index):
        item = doc['accessors'][index]
        assert 'sparse' not in item, ('Unsupported sparse accessor', path, index)
        buffer_view = doc['bufferViews'][item['bufferView']]
        assert buffer_view.get('buffer', 0) == 0
        dtype = np.dtype(DTYPES[item['componentType']])
        width = WIDTHS[item['type']]
        values = np.ndarray((item['count'], width), dtype=dtype, buffer=binary,
            offset=buffer_view.get('byteOffset', 0) + item.get('byteOffset', 0),
            strides=(buffer_view.get('byteStride', width * dtype.itemsize), dtype.itemsize)).copy()
        if item.get('normalized') and item['componentType'] != 5126:
            values = values.astype(float) / np.iinfo(dtype).max
            if dtype.kind == 'i':
                values = np.maximum(-1, values)
        assert np.isfinite(values).all(), (path, index)
        return values

    return doc, accessor, view


def signature(path):
    doc, accessor, view = read_glb(path)
    nodes = doc['nodes']
    def ah(index):
        return sha256(accessor(index).tobytes())
    clips = {}
    durations = {}
    for animation in doc['animations']:
        channels = []
        for channel in animation['channels']:
            sampler = animation['samplers'][channel['sampler']]
            times = accessor(sampler['input'])[:, 0]
            assert np.all(np.diff(times) >= 0), (path, animation['name'])
            target = channel['target']
            channels.append((nodes[target['node']]['name'], target['path'],
                             sampler.get('interpolation', 'LINEAR'), ah(sampler['input']), ah(sampler['output'])))
        clips[animation['name']] = sorted(channels)
        times = [accessor(s['input'])[:, 0] for s in animation['samplers']]
        durations[animation['name']] = float(max(t[-1] for t in times) - min(t[0] for t in times))
    rest = []
    for node in nodes:
        row = {k: node[k] for k in ('name', 'matrix', 'translation', 'rotation', 'scale') if k in node}
        if 'children' in node:
            row['children'] = [nodes[i].get('name', str(i)) for i in node['children']]
        rest.append(row)
    prims = [p for mesh in doc['meshes'] for p in mesh['primitives']]
    return doc, accessor, dict(
        clips=clips, durations=durations, rest_nodes=rest,
        skin_joints=[[nodes[i]['name'] for i in skin['joints']] for skin in doc['skins']],
        inverse_bind=[ah(skin['inverseBindMatrices']) for skin in doc['skins']],
        mesh=[{'indices': ah(p['indices']), 'attributes': {k: ah(i) for k, i in p['attributes'].items()}}
              for p in prims],
        materials=doc['materials'],
        images=[sha256(view(image['bufferView'])) for image in doc['images']])


def bounds(meshes):
    graph = bpy.context.evaluated_depsgraph_get()
    points = []
    for obj in meshes:
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        xyz = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
        mesh.vertices.foreach_get('co', xyz)
        xyz = xyz.reshape((-1, 3))
        matrix = np.array(evaluated.matrix_world)
        points.append(xyz @ matrix[:3, :3].T + matrix[:3, 3])
        evaluated.to_mesh_clear()
    points = np.concatenate(points)
    return points.min(axis=0), points.max(axis=0), points


def contact_surfaces(meshes):
    """Measure weighted anatomical/armour support on the actual final mesh."""
    wanted = ('hips', 'chest', 'head', 'upper_arm.L', 'upper_arm.R',
              'forearm.L', 'forearm.R', 'hand.L', 'hand.R')
    minima = {}
    graph = bpy.context.evaluated_depsgraph_get()
    for obj in meshes:
        evaluated = obj.evaluated_get(graph)
        mesh = evaluated.to_mesh()
        names = {g.index: g.name for g in obj.vertex_groups if g.name in wanted}
        for vertex in mesh.vertices:
            z = (evaluated.matrix_world @ vertex.co).z
            for group in vertex.groups:
                name = names.get(group.group)
                if name and group.weight >= .4:
                    minima[name] = min(minima.get(name, float('inf')), z)
        evaluated.to_mesh_clear()
    return minima


def render_phases(scene, meshes, low, high, output, kind, options):
    if options.render == 'none':
        return []
    phases = [1.0]
    if options.render == 'all' or kind in ('warg', 'troll', 'boss_troll', 'nazgul'):
        phases.insert(0, .65)
    if options.phases:
        phases = [float(value) for value in options.phases.split(',')]
    camera = setup_studio(scene, Vector((low[0], low[1], .006)), Vector(high), options.resolution, 32)
    scene.render.resolution_y = options.resolution
    # Scale the studio as well as the camera for the genuinely larger boss.
    studio_scale = max(1.0, (high[2] - low[2]) / 2.3)
    for obj in scene.objects:
        if obj.type == 'LIGHT':
            obj.location *= studio_scale
            obj.data.energy *= studio_scale * studio_scale
            obj.data.size *= studio_scale
    images = []
    for phase in phases:
        pose, frame = select_pose(scene, 'Death', phase)
        frame_low, frame_high, _ = bounds(meshes)
        focus = Vector((frame_low + frame_high) * .5)
        direction = Vector((3.4, -5.0, 2.8)).normalized()
        camera.location = focus + direction * max(4.0, float(np.linalg.norm(frame_high - frame_low)) * 2)
        camera.rotation_euler = (focus - camera.location).to_track_quat('-Z', 'Y').to_euler()
        right = camera.rotation_euler.to_quaternion() @ Vector((1, 0, 0))
        up = camera.rotation_euler.to_quaternion() @ Vector((0, 1, 0))
        corners = [Vector((x, y, z)) for x in (frame_low[0], frame_high[0])
                   for y in (frame_low[1], frame_high[1]) for z in (frame_low[2], frame_high[2])]
        width = max(v.dot(right) for v in corners) - min(v.dot(right) for v in corners)
        height = max(v.dot(up) for v in corners) - min(v.dot(up) for v in corners)
        camera.data.ortho_scale = max(width, height, .7) * 1.14
        image_path = output / f'{kind}_death_{round(phase * 100):03}.png'
        scene.render.filepath = str(image_path)
        bpy.ops.render.render(write_still=True)
        images.append({'phase': phase, 'frame': frame, 'path': str(image_path),
                       'camera': list(camera.location), 'focus': list(focus),
                       'ortho_scale': camera.data.ortho_scale, 'pose_selection': pose})
    return images


def review(path, baseline, output, options):
    kind = path.stem
    before = sha256(path.read_bytes())
    baseline_hash = sha256(baseline.read_bytes())
    doc, accessor, candidate = signature(path)
    _, _, original = signature(baseline)
    checks = {key: candidate[key] == original[key] for key in
              ('rest_nodes', 'skin_joints', 'inverse_bind', 'mesh', 'materials', 'images')}
    unchanged = {name: candidate['clips'].get(name) == original['clips'][name]
                 for name in original['clips'] if not name.endswith('_Death')}
    death = f'enemy_{kind}_Death'
    checks.update(unaffected_clips=unchanged, death_changed=candidate['clips'][death] != original['clips'][death])
    expected_bones = 22 if kind == 'warg' else 165
    prims = [p for mesh in doc['meshes'] for p in mesh['primitives']]
    assert len(prims) == len(doc['materials']) == len(doc['skins']) == 1, path
    primitive = prims[0]
    attrs = primitive['attributes']
    assert all(name in attrs for name in ('POSITION', 'NORMAL', 'TEXCOORD_0', 'JOINTS_0', 'WEIGHTS_0'))
    weights = accessor(attrs['WEIGHTS_0'])
    joints = accessor(attrs['JOINTS_0'])
    error = float(np.max(abs(weights.sum(axis=1) - 1)))
    checks['valid_skin'] = bool(weights.min() >= 0 and error < 1e-4 and joints.min() >= 0
                                and joints.max() < expected_bones and len(doc['skins'][0]['joints']) == expected_bones)
    checks['required_clips'] = sorted(a['name'].split('_')[-1] for a in doc['animations']) == ['Death', 'Hit', 'Idle', 'Run']
    death_scale_tracks = []
    for animation in doc['animations']:
        if animation['name'] != death:
            continue
        for channel in animation['channels']:
            if channel['target']['path'] != 'scale':
                continue
            values = accessor(animation['samplers'][channel['sampler']]['output'])
            bone = doc['nodes'][channel['target']['node']]['name']
            death_scale_tracks.append(dict(bone=bone, first=values[0].tolist(), last=values[-1].tolist()))
            assert np.allclose(values[0], 1, atol=1e-5), (path, bone, 'First-frame scale must be one')
            assert bone == 'cape' or np.allclose(values, 1, atol=1e-5), (path, bone, 'Only cloth may settle in thickness')
    checks['death_scale_starts_one'] = True
    checks['death_scale_only_cloth'] = True
    assert all(value for key, value in checks.items() if key != 'unaffected_clips') and all(unchanged.values()), (path, checks)
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    scene = bpy.context.scene
    meshes = [obj for obj in scene.objects if obj.type == 'MESH' and any(m.type == 'ARMATURE' for m in obj.modifiers)]
    rig = next(obj for obj in scene.objects if obj.type == 'ARMATURE')
    rows = []
    # Half-frame spacing checks interpolation as well as all authored frames.
    count = round(candidate['durations'][death] * 30 * 2) + 1
    for index in range(count):
        phase = index / (count - 1)
        _, frame = select_pose(scene, 'Death', phase)
        low, high, points = bounds(meshes)
        bone_positions = {name: list(rig.matrix_world @ rig.pose.bones[name].head)
                          for name in ('hips', 'head', 'root', 'hand.L', 'hand.R', 'shin.L', 'shin.R')}
        rows.append(dict(phase=phase, frame=frame, bounds_min=low.tolist(), bounds_max=high.tolist(),
                         vertices_below_ground=int(np.sum(points[:, 2] < -.01)),
                         root_angle=rig.pose.bones['root'].matrix_basis.to_quaternion().angle, **bone_positions))
    lowest = min(row['bounds_min'][2] for row in rows)
    checks['head_drops'] = rows[0]['head'][2] - rows[-1]['head'][2] > .45
    checks['root_does_not_pitch'] = max(row['root_angle'] for row in rows) < .001
    checks['ground_clearance'] = lowest >= -.008
    all_low = np.min([row['bounds_min'] for row in rows], axis=0)
    all_high = np.max([row['bounds_max'] for row in rows], axis=0)
    final_contact = contact_surfaces(meshes)
    images = render_phases(scene, meshes, all_low, all_high, output, kind, options)
    assert sha256(path.read_bytes()) == before and sha256(baseline.read_bytes()) == baseline_hash
    passed = all(value for key, value in checks.items() if key != 'unaffected_clips') and all(unchanged.values())
    report = dict(kind=kind, input=str(path), baseline=str(baseline), input_sha256=before,
                  baseline_sha256=baseline_hash, input_unchanged=True, baseline_unchanged=True,
                  passed=passed, checks=checks, bones=expected_bones, vertices=len(accessor(attrs['POSITION'])),
                  max_weight_sum_error=error, clip_seconds=candidate['durations'],
                  death_scale_tracks=death_scale_tracks,
                  min_ground_z=lowest, head_drop=rows[0]['head'][2] - rows[-1]['head'][2],
                  final_contact_min_z=final_contact,
                  largest_half_frame_root_delta=max(abs(a['root'][2] - b['root'][2]) for a, b in zip(rows, rows[1:])),
                  samples=rows, images=images)
    (output / f'{kind}.audit.json').write_text(json.dumps(report, indent=2), encoding='utf8')
    print('ENEMY_DEATH_AUDIT', kind, 'PASS' if passed else 'FAIL',
          'samples', count, 'min_z', lowest, 'head_drop', report['head_drop'], flush=True)
    return report


def main():
    argv = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--input', type=Path, required=True)
    parser.add_argument('--baseline', type=Path, required=True)
    parser.add_argument('--output-dir', '--output', type=Path, required=True)
    parser.add_argument('--kinds', '--kind', default='all')
    parser.add_argument('--render', choices=('none', 'key', 'all'), default='none',
                        help='key: every endpoint plus warg/troll/boss/nazgul at phase .65')
    parser.add_argument('--phases', help='Override render phases, comma separated; requires --render')
    parser.add_argument('--resolution', type=int, default=720)
    parser.add_argument('--merge-existing', action='store_true',
                        help='Retain previous model audits only when their input/baseline hashes still match')
    options = parser.parse_args(argv)
    kinds = KINDS if options.kinds == 'all' else tuple(options.kinds.split(','))
    if any(kind not in KINDS for kind in kinds):
        parser.error('Unknown enemy kind')
    inputs = [options.input / f'{kind}.glb' for kind in kinds] if options.input.is_dir() else [options.input]
    if len(inputs) > 1 and not options.baseline.is_dir():
        parser.error('Multiple inputs require a baseline directory')
    output = options.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    rows = []
    for path in inputs:
        baseline = options.baseline / path.name if options.baseline.is_dir() else options.baseline
        if not path.is_file() or not baseline.is_file():
            parser.error('Input/baseline must exist: ' + str(path) + ', ' + str(baseline))
        rows.append(review(path.resolve(), baseline.resolve(), output, options))
    reused = []
    previous_path = output / 'audit.json'
    if options.merge_existing and previous_path.is_file():
        updated = {row['kind'] for row in rows}
        for row in json.loads(previous_path.read_text(encoding='utf8'))['models']:
            if row['kind'] in updated:
                continue
            assert sha256(Path(row['input']).read_bytes()) == row['input_sha256'], ('Stale input audit', row['kind'])
            assert sha256(Path(row['baseline']).read_bytes()) == row['baseline_sha256'], ('Stale baseline audit', row['kind'])
            rows.append(row)
            reused.append(row['kind'])
    rows.sort(key=lambda row: KINDS.index(row['kind']))
    summary = dict(passed=all(row['passed'] for row in rows), models=rows, reused_model_audits=reused,
                   mode='read-only; actual imported GLB; every authored frame and half frame',
                   authoring_hashes={name: sha256((Path(__file__).parent / name).read_bytes())
                                     for name in ('build_enemy_assets.py', 'enemy_death_motion.py')})
    (output / 'audit.json').write_text(json.dumps(summary, indent=2), encoding='utf8')
    if not summary['passed']:
        raise RuntimeError('Enemy death audit failed; inspect ' + str(output / 'audit.json'))
    print('ALL_ENEMY_DEATH_AUDITS_PASS', len(rows), output, flush=True)


if __name__ == '__main__':
    main()
