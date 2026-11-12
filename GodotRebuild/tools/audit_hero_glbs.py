"""Native GLB contract audit; no editor import cache or rendering involved.

Usage: bundled Blender Python audit_hero_glbs.py MODEL_FOLDER REPORT.json
Artistic likeness is deliberately not a machine acceptance criterion here.
"""
import hashlib
import json
import struct
import sys
from pathlib import Path
import numpy as np

HEROES = ('asta', 'yuno', 'magna', 'vanessa', 'noelle', 'charmy')
DT = {5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}
WIDTH = {'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT4':16}

def audit(path):
    raw = path.read_bytes()
    magic,version,length = struct.unpack_from('<III',raw)
    assert magic == 0x46546c67 and version == 2 and length == len(raw), path
    size,kind = struct.unpack_from('<II',raw,12)
    assert kind == 0x4e4f534a, path
    doc = json.loads(raw[20:20+size])
    offset = 20+size
    binsize,binkind = struct.unpack_from('<II',raw,offset)
    assert binkind == 0x004e4942, path
    binary = raw[offset+8:offset+8+binsize]
    def accessor(index):
        a = doc['accessors'][index]
        view = doc['bufferViews'][a['bufferView']]
        dtype = np.dtype(DT[a['componentType']])
        width = WIDTH[a['type']]
        values = np.ndarray((a['count'],width),dtype=dtype,buffer=binary,
            offset=view.get('byteOffset',0)+a.get('byteOffset',0),
            strides=(view.get('byteStride',width*dtype.itemsize),dtype.itemsize)).copy()
        if a.get('normalized') and a['componentType'] != 5126:
            values = values.astype(float)/np.iinfo(dtype).max
        assert np.isfinite(values).all(), (path,index)
        return values
    primitives = [p for mesh in doc['meshes'] for p in mesh['primitives']]
    assert len(primitives) == len(doc['materials']) == len(doc['skins']) == 1, path
    primitive = primitives[0]
    attrs = primitive['attributes']
    assert all(k in attrs for k in ('POSITION','NORMAL','TEXCOORD_0','JOINTS_0','WEIGHTS_0')), path
    vertices = accessor(attrs['POSITION'])
    weights = accessor(attrs['WEIGHTS_0'])
    joints = accessor(attrs['JOINTS_0'])
    assert len(vertices) == len(weights) == len(joints) and len(vertices)>10000, path
    assert len(doc['skins'][0]['joints']) == 166, path
    assert joints.min() >= 0 and joints.max() < 166, path
    weight_error = float(np.abs(weights.sum(axis=1)-1).max())
    assert weights.min() >= 0 and weight_error < 1e-4, path
    indices = accessor(primitive['indices'])
    assert indices.min() >= 0 and indices.max() < len(vertices), path
    assert len(indices)%3 == 0, path
    assert sorted(a['name'].split('_')[-1] for a in doc['animations']) == ['Ability','Attack','Idle'], path
    for animation in doc['animations']:
        for sampler in animation['samplers']:
            times = accessor(sampler['input'])
            assert np.all(np.diff(times[:,0]) >= 0), (path,animation['name'])
            accessor(sampler['output'])
    material = doc['materials'][0]
    assert 'normalTexture' in material, path
    assert all(k in material['pbrMetallicRoughness'] for k in ('baseColorTexture','metallicRoughnessTexture')), path
    assert all('bufferView' in im and 'uri' not in im for im in doc['images']), path
    size3 = np.ptp(vertices,axis=0)
    assert size3[1] > 1 and size3[2] > .2, path
    return dict(name=path.stem,sha256=hashlib.sha256(raw).hexdigest(),bytes=len(raw),
        vertices=len(vertices),triangles=len(indices)//3,bones=166,primitives=1,materials=1,
        max_weight_sum_error=weight_error,bounds_min=vertices.min(axis=0).tolist(),
        bounds_max=vertices.max(axis=0).tolist(),images=len(doc['images']))

if __name__ == '__main__':
    folder = Path(sys.argv[1])
    rows = [audit(folder/f'{hero}_L{rank}.glb') for hero in HEROES for rank in range(1,6)]
    for hero in HEROES:
        counts = [r['vertices'] for r in rows if r['name'].startswith(hero+'_')]
        assert len(set(counts)) == 5, (hero,'ranks lack distinct geometry',counts)
    Path(sys.argv[2]).write_text(json.dumps(dict(passed=True,models=rows,
        artistic_likeness='not certified by structural audit'),indent=2),encoding='utf8')
    print('HERO_GLB_AUDIT_OK: 30 self-contained skinned models, finite data, normalized weights, three clips, five distinct geometries per hero')
