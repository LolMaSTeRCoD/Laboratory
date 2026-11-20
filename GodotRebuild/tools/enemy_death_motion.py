"""Articulated, non-looping enemy collapse; rig topology stays untouched.

All offsets are metres in the author's Z-up rest space. Humanoids first lose
their knees, then their chest and finally their head/arms settle. Canines brace
with the front paws before their haunches roll down. No whole-character pitch
is used: the pelvis is the hinge, while limb targets retain surface contact.
"""
from mathutils import Vector, Quaternion, Matrix

DEATH_LAST_FRAME = 43  # 1.4 seconds at the existing 30 fps export rate.
DEATH_REVISION = 'articulated-collapse-20261119'


def ease(t, start, end):
    u = max(0.0, min(1.0, (t - start) / (end - start)))
    return u * u * (3.0 - 2.0 * u)


def envelope(t, start, peak, end):
    return ease(t, start, peak) * (1.0 - ease(t, peak, end))


def turn(bone, x=0.0, y=0.0, z=0.0):
    """Add a rest-world-axis rotation without assuming a bone's local roll."""
    basis = bone.bone.matrix_local.to_quaternion()
    rotation = (Quaternion((0, 0, 1), z) @ Quaternion((0, 1, 0), y)
                @ Quaternion((1, 0, 0), x))
    bone.rotation_euler = (bone.rotation_euler.to_quaternion()
                           @ basis.inverted() @ rotation @ basis).to_euler('XYZ')


def humanoid(arm, kind, t, scale, move_world, solve_limb, update):
    bones = arm.pose.bones
    heavy = kind in ('troll', 'boss_troll')
    delay = .045 if heavy else 0.0
    buckle = ease(t, .055, .40 + delay)
    fall = ease(t, .20 + delay, .73 + delay)
    settle = ease(t, .73 + delay, 1.0)
    recoil = envelope(t, 0.0, .105, .32)
    brace = envelope(t, .12, .40 + delay, .79 + delay)
    head_lag = envelope(t, .25 + delay, .52 + delay, .88)
    impact = envelope(t, .69 + delay, .79 + delay, .93)
    hip = bones['hips'].bone.head_local
    final_hip_height = (.55 if heavy else .45) * scale
    down = (.18 * buckle + max(0.0, hip.z - final_hip_height - .18 * scale) / scale * fall) * scale
    move_world(bones['hips'], ((.025 * recoil + .055 * fall) * scale,
                              (.035 * recoil - .13 * fall) * scale, -down + .018 * impact * scale))
    # Knees release before the body's weight pitches forward. A modest hip
    # roll makes shoulder and hip contact happen at different instants.
    turn(bones['hips'], x=-.055 * recoil + (1.12 if heavy else 1.22) * fall,
         y=.105 * fall, z=-.065 * buckle + .095 * settle)
    turn(bones['spine'], x=-.10 * recoil + .19 * buckle + .035 * fall,
         y=-.05 * brace, z=.045 * recoil + .05 * fall)
    turn(bones['chest'], x=.12 * recoil + .12 * fall - .035 * settle,
         y=.055 * brace, z=-.055 * brace)
    turn(bones['neck'], x=-.11 * head_lag - .12 * settle, z=.065 * settle)
    turn(bones['head'], x=-.10 * recoil - .13 * head_lag - .08 * settle,
         y=.10 * settle, z=.065 * fall)
    turn(bones['jaw'], x=.055 * brace + .025 * settle)
    # The full Nazgul robe has a long weighted hem: the short-cloth recoil
    # would raise it like a rigid flag after the body has already settled.
    cape_settle = -.07 if kind == 'nazgul' else .23
    turn(bones['cape'], x=-.18 * fall + cape_settle * ease(t, .58, .96), z=.04 * impact)
    if kind == 'nazgul':
        # Its robe is a closed volume driven by one existing cloth bone.
        # Compress only its depth as the fabric loses support; retain the
        # length/width and all rest geometry/weights and non-Death actions.
        bones['cape'].scale.z = 1.0 - .55 * ease(t, .42, .97)
    update()
    for side, sign, asymmetry in [('L', 1, 0.0), ('R', -1, .045)]:
        fold = ease(t, .30 + asymmetry + delay, .85 + delay)
        foot = bones['foot.' + side].bone.head_local
        # Feet stay planted through the first knee buckle, then slide only as
        # the pelvis reaches the ground. Knees release to opposite sides.
        target = Vector((foot.x + sign * .08 * fold * scale,
                         foot.y + (.44 if side == 'L' else .62) * fold * scale,
                         foot.z - .012 * fold * scale))
        pole = Vector((sign * .85 * fold, -1.0 + 1.08 * fold, .15 * fold))
        solve_limb(arm, 'thigh.' + side, 'shin.' + side, 'foot.' + side, target, pole)
        # Hands reach to catch the fall and lose the brace independently;
        # elbows remain bent after contact instead of becoming rigid paddles.
        arm_lag = ease(t, .27 + asymmetry, .78 + asymmetry)
        arm_settle = ease(t, .66 + asymmetry, .98)
        turn(bones['shoulder.' + side], z=sign * (.045 * brace + .055 * arm_settle))
        turn(bones['upper_arm.' + side], x=-.43 * brace + .24 * arm_lag,
             y=-sign * (.12 * brace + .18 * arm_settle), z=sign * .10 * arm_settle)
        turn(bones['forearm.' + side], x=-.45 * brace - (.12 if side == 'L' else .20) * arm_settle)
        turn(bones['hand.' + side], x=.12 * brace - .09 * arm_settle,
             z=sign * .12 * arm_settle)
    if heavy:
        heavy_settle(arm, kind, t, scale, solve_limb, update)


def heavy_settle(arm, kind, t, scale, solve_limb, update):
    """Let a heavy torso sag onto one folded forearm, with its maul beside it."""
    late = ease(t, .52, .96)
    if late <= 0.0:
        return
    bones = arm.pose.bones
    turn(bones['hips'], y=.08 * late)
    turn(bones['spine'], y=.19 * late)
    turn(bones['chest'], y=.14 * late, z=-.06 * late)
    turn(bones['neck'], x=.08 * late, y=-.06 * late)
    turn(bones['head'], x=.10 * late, y=.12 * late, z=-.10 * late)
    update()
    # The boss's actual spiked maul has a larger radius than the troll's
    # mallet. Raise that wrist alone so its rim cannot lift the whole corpse.
    weapon_height = .42 if kind == 'boss_troll' else .27
    for side, target, pole in [('L', (.30, -.56, .16), (1, .12, .20)),
                               ('R', (-.16, -.62, weapon_height), (-1, .35, -.35))]:
        upper = bones['upper_arm.' + side]
        elbow = bones['forearm.' + side]
        hand = bones['hand.' + side]
        attitude = hand.matrix.to_3x3().copy()
        # Flatten the loaded maul shaft, and the free hand's fingers, rather
        # than allowing either to hang below the intended forearm contact.
        axis = (attitude @ hand.bone.matrix_local.to_3x3().inverted() @ Vector((0, 0, 1))
                if side == 'R' else attitude.col[1].normalized())
        flat = Vector((axis.x, axis.y, 0))
        if flat.length > .001:
            flat.normalize()
            relaxed = axis.rotation_difference(flat).to_matrix() @ attitude
            attitude = attitude.to_quaternion().slerp(relaxed.to_quaternion(), late).to_matrix()
        target = hand.head.lerp(Vector(target) * scale, late)
        current_pole = (elbow.head - upper.head).normalized()
        pole = current_pole.lerp(Vector(pole).normalized(), late)
        solve_limb(arm, upper.name, elbow.name, hand.name, target, pole)
        hand.matrix = Matrix.Translation(target) @ attitude.to_4x4()
        update()


def canine(arm, t, move_world, solve_limb, update):
    bones = arm.pose.bones
    fore = ease(t, .06, .43)
    haunch = ease(t, .24, .70)
    roll = ease(t, .42, .89)
    settle = ease(t, .78, 1.0)
    recoil = envelope(t, 0.0, .12, .37)
    move_world(bones['hips'], (.15 * roll, -.08 * fore,
                              -.12 * fore - .29 * haunch - .05 * settle))
    turn(bones['hips'], x=.10 * fore - .04 * settle, y=.83 * roll, z=-.10 * haunch)
    turn(bones['spine'], x=.14 * fore - .09 * haunch, y=.13 * roll)
    turn(bones['chest'], x=.10 * fore - .11 * haunch, y=.11 * roll)
    turn(bones['neck'], x=-.16 * recoil + .18 * ease(t, .35, .80), y=-.09 * roll)
    turn(bones['head'], x=-.15 * recoil - .10 * settle, z=-.10 * settle)
    turn(bones['jaw'], x=.10 * fore - .06 * settle)
    turn(bones['cape'], x=-.16 * haunch, z=.22 * roll - .06 * settle)
    update()
    for side, sign in [('L', -1), ('R', 1)]:
        for front in (True, False):
            fold = fore if front else haunch
            upper = ('upper_arm.' if front else 'thigh.') + side
            lower = ('forearm.' if front else 'shin.') + side
            paw = ('hand.' if front else 'foot.') + side
            origin = bones[paw].bone.head_local
            target = Vector((origin.x + sign * .11 * fold + .12 * roll,
                             origin.y + (-.10 if front else .11) * fold,
                             origin.z))
            solve_limb(arm, upper, lower, paw, target,
                       (sign * .80 * roll, 1 if front else -1, .08))


def pose_death(arm, kind, t, move_world, solve_limb, update):
    if kind == 'warg':
        canine(arm, t, move_world, solve_limb, update)
    else:
        humanoid(arm, kind, t, float(arm.get('gait_scale', 1.0)),
                 move_world, solve_limb, update)


def ground_death(arm, mesh, move_world, update, padding=.004):
    """Bake accessory-aware contact, including long weapons and armour hems.

    This is author-time clearance, not a runtime rigidbody or collider. The
    continuous soft clamp avoids a one-frame root pop at first contact.
    """
    import bpy
    update()
    evaluated = mesh.evaluated_get(bpy.context.evaluated_depsgraph_get())
    low = min((evaluated.matrix_world @ Vector(corner)).z for corner in evaluated.bound_box)
    needed = padding - low
    clearance = .5 * (needed + (needed * needed + .000004) ** .5)
    move_world(arm.pose.bones['root'], (0.0, 0.0, clearance))
    update()
