"""Small character-specific mouth geometry fitted to the final facial surface."""
import math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree


def _mouth_frame(body, hero, groups, faces, raw, vert_weights):
    ids = [i for i in groups['body'] if sum(v for k, v in vert_weights[i].items() if k.startswith('oris')) > .25]
    if len(ids) < 8:
        raise RuntimeError('Missing anatomical lip guides for ' + hero)
    central = float(np.quantile(np.abs(raw[ids, 0]), .65)) * .45
    upper = [i for i in ids if vert_weights[i].get('oris05', 0) > .25 and abs(raw[i, 0]) < central]
    lower = [i for i in ids if vert_weights[i].get('oris01', 0) > .25 and abs(raw[i, 0]) < central]
    if not upper or not lower:
        raise RuntimeError('Missing upper/lower anatomical lip guides for ' + hero)
    upper_edge = float(np.quantile(raw[upper, 1], .10))
    lower_edge = float(np.quantile(raw[lower, 1], .90))
    line_ids = [i for i in upper if raw[i, 1] <= upper_edge] + [i for i in lower if raw[i, 1] >= lower_edge]
    center = np.median(body[line_ids], axis=0)
    source_line = (upper_edge + lower_edge) * .5
    corner_ids = [i for i in ids if abs(raw[i, 1] - source_line) < .13]
    base_half = float(np.quantile(np.abs(body[corner_ids, 0] - center[0]), .90))
    factor = {'asta': .64, 'yuno': .52, 'magna': 1.05, 'vanessa': .60, 'noelle': .46, 'charmy': .60}[hero]
    half = base_half * factor
    if half <= 0:
        raise RuntimeError('Invalid anatomical mouth width for ' + hero)
    surface = BVHTree.FromPolygons([Vector(v) for v in body], [[q[0] for q in face] for group, face in faces if group == 'body'])
    ray_y = float(body[:, 1].min()) - 1.0
    distance = float(np.ptp(body[:, 1])) + 3.0
    def project(x, z, inset=0.0):
        hit, _, _, _ = surface.ray_cast(Vector((x, ray_y, z)), Vector((0, 1, 0)), distance)
        if hit is None:
            raise RuntimeError('Mouth surface projection missed ' + hero)
        return (x, hit.y + inset, z)
    return center, half, project


def _magna_grin(m, center, half, project):
    """A bounded opening, inset oral bowl and individually closed upper teeth."""
    cx, cz = float(center[0]), float(center[2])
    gape = half * .16
    def line(q):
        return cz + half * (.15 * q * q + .008 * q)
    def aperture(q):
        return max(0, 1 - q * q) ** .52

    # Only the actual lip-adjacent skin is opened. Preserve every parallel
    # face/material/UV array and leave all surrounding facial topology intact.
    kept_faces, kept_materials, kept_uv = [], [], []
    removed = 0
    for face, mat, uv in zip(m.f, m.m, m.uv):
        cut = False
        if mat == 'skin' and any(sum(w for name, w in m.w[i].items() if name.startswith('oris')) > .12 for i in face):
            points = np.asarray([m.v[i] for i in face])
            mean = points.mean(axis=0)
            q = (float(mean[0]) - cx) / half
            if abs(q) < .98 and line(q) - gape * .78 * aperture(q) < mean[2] < line(q) + gape * aperture(q):
                skin_y = project(float(mean[0]), float(mean[2]))[1]
                cut = abs(float(mean[1]) - skin_y) < half * .27
        if cut:
            removed += 1
        else:
            kept_faces.append(face); kept_materials.append(mat); kept_uv.append(uv)
    if not removed:
        raise RuntimeError('Magna grin did not intersect the anatomical lip surface')
    m.f, m.m, m.uv = kept_faces, kept_materials, kept_uv

    segments = 48
    front, back = [], []
    for i in range(segments):
        angle = math.tau * i / segments
        q = math.cos(angle)
        height = gape * math.sin(angle) * (1 if math.sin(angle) >= 0 else .78)
        z = line(q) + height
        front.append(project(cx + half * q, z, .00015))
        back.append(project(cx + half * q * .91, line(q) + height * .72, half * .18))
    cavity_faces = [(i, (i + 1) % segments, (i + 1) % segments + segments, i + segments)
                    for i in range(segments)]
    cavity_faces.append(tuple(range(segments, segments * 2)))
    m.add(front + back, cavity_faces, 'black', {'head': .65, 'jaw': .35})

    # A projected, tapered lip rim joins the opening to the surrounding skin;
    # the enamel sits inside it rather than floating in front of the face.
    rim = [(x, y - .00045, z) for x, y, z in front]
    m.tube(rim + [rim[0]], half * .030, 'lip', {'head': .75, 'jaw': .25}, 7)
    tooth_count = 8
    for tooth in range(tooth_count):
        q0 = -.88 + 1.76 * tooth / tooth_count + .007
        q1 = -.88 + 1.76 * (tooth + 1) / tooth_count - .007
        corners = []
        for q, upper in [(q0, False), (q1, False), (q1, True), (q0, True)]:
            z = line(q) + gape * aperture(q) * (.79 if upper else -.16)
            corners.append(project(cx + half * q, z, half * .013))
        vertices = corners + [(x, y + half * .065, z) for x, y, z in corners]
        polygons = [(0, 3, 2, 1), (4, 5, 6, 7), (0, 1, 5, 4),
                    (1, 2, 6, 5), (2, 3, 7, 6), (3, 0, 4, 7)]
        m.add(vertices, polygons, 'eye', 'head')
    print('HERO_MOUTH_EXPRESSION', 'magna', 'anatomical grin', 'opened_faces', removed,
          'width', half * 2, 'teeth', tooth_count, flush=True)
    return {'hero': 'magna', 'mode': 'inset anatomical grin', 'center': center.tolist(),
            'width': half * 2, 'opened_skin_faces': removed, 'closed_upper_teeth': tooth_count}


def add_mouth_expression(m, body, hero, groups, faces, raw, vert_weights):
    center, half, project = _mouth_frame(body, hero, groups, faces, raw, vert_weights)
    if hero == 'magna':
        return _magna_grin(m, center, half, project)
    smile = {'asta': .045, 'yuno': .0, 'magna': .12, 'vanessa': .055, 'noelle': .012, 'charmy': .105}[hero]
    asymmetry = {'asta': .012, 'vanessa': .035}.get(hero, 0)
    points = []
    radii = []
    for t in np.linspace(0, 1, 33):
        q = (float(t) - .5) * 2
        z = float(center[2]) + half * (smile * q * q + asymmetry * q)
        points.append(project(float(center[0]) + half * q, z, -.00035))
        radii.append(half * (.004 + .014 * math.sin(math.pi * float(t)) ** .6))
    m.tube(points, radii, 'lip', {'head': .75, 'jaw': .25}, 7)
    print('HERO_MOUTH_EXPRESSION', hero, 'closed', 'center', center.tolist(), 'width', half * 2, flush=True)
    return {'hero': hero, 'mode': 'closed crease', 'center': center.tolist(), 'width': half * 2}
