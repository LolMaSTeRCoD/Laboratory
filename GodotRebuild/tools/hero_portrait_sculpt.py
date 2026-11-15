"""Character portrait proportions on the anatomical quad mesh.

This changes vertex positions, including matching rig/socket helper points.
It retains the UVs, complete head volume, connectivity and deformation weights.
No portrait image is projected onto the model.
"""
import numpy as np


PROFILES = {
    'asta': dict(lower=1.01, shift=-.10, chin=.98, neck=.96),
    'yuno': dict(lower=.90, shift=-.09, chin=1.04, neck=.98),
    'magna': dict(lower=.94, shift=-.07, chin=1.05, neck=1.00),
    'vanessa': dict(lower=.88, shift=-.13, chin=1.08, neck=.96),
    'noelle': dict(lower=.88, shift=-.13, chin=1.08, neck=.95),
    'charmy': dict(lower=.97, shift=-.30, chin=1.05, neck=1.10),
}


def smoothstep(a, b, value):
    t = np.clip((value-a)/(b-a), 0, 1)
    return t*t*(3-2*t)


def sculpt_portrait(points, raw, groups, weights, hero):
    """Apply a controlled, landmark-relative portrait pass in source coordinates."""
    profile = PROFILES[hero]
    before = points.copy()
    eye_ids = sorted(set(groups['helper-l-eye']) | set(groups['helper-r-eye']))
    eye_height = float(points[eye_ids, 1].mean())
    original = points.copy()
    # Short midfaces and full jaw planes are deliberate anime proportions.
    # Smooth attachment preserves the neck seam and moves facial rig helpers
    # with the skin rather than placing a new head on top of the old one.
    attach = smoothstep(5.55, 6.18, raw[:, 1])
    below = np.minimum(0, original[:, 1]-eye_height)
    points[:, 1] += attach*(below*(profile['lower']-1)+profile['shift'])
    jaw = np.exp(-((raw[:, 1]-6.15)/.38)**2)*attach
    points[:, 0] *= 1+(profile['chin']-1)*jaw
    if hero == 'asta':
        # Widen the actual lip region with its jaw helpers, rather than drawing
        # a larger crease over an unchanged small mouth. The smooth lateral
        # deformation preserves the connected cheek surface and depth relief.
        lip = np.asarray([min(1.0, sum(value for name, value in row.items()
                                     if name.startswith('oris'))) for row in weights])
        mouth_height = float(np.median(original[lip > .65, 1]))
        mouth = np.exp(-((raw[:, 0]/.58)**4)-((original[:, 1]-mouth_height)/.30)**4)
        points[:, 0] *= 1+.16*mouth*attach
    if hero == 'charmy':
        # The former cheek multiplier flattened the child's head into a wide
        # disk. Restore a compact, vertically round skull and a short neck.
        points[:, 0] *= 1-.17*attach
        above = np.maximum(0, original[:, 1]-eye_height)
        points[:, 1] += above*.13*attach
        hand = smoothstep(3.55, 4.20, np.abs(raw[:, 0]))
        for sign in (-1, 1):
            candidates = np.where((raw[:, 0]*sign>3.55)&(raw[:, 1]<4.7))[0]
            if len(candidates):
                anchor = original[candidates].mean(axis=0)
                local = hand[candidates, None]
                points[candidates] += (anchor-points[candidates])*.12*local
    neck = (1-smoothstep(5.45, 6.0, raw[:, 1]))*smoothstep(4.95, 5.5, raw[:, 1])
    points[:, 0] *= 1+(profile['neck']-1)*neck

    # Nose and lip relief remain on the continuous anatomical surface.
    # Their proportions are set by the CC0 morph targets in the caller.
    print('PORTRAIT_SCULPT',hero,'moved_vertices',int(np.sum(np.linalg.norm(points-before,axis=1)>.00001)),
          'max_delta',round(float(np.linalg.norm(points-before,axis=1).max()),5),flush=True)
