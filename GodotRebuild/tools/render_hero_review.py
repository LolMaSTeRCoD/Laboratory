"""Render the actual imported hero GLB for visual review, without rebuilding it.

Blender --background --python render_hero_review.py -- --heroes asta --rank 1
    --output-dir Builds/hero-review --views front,head_threequarter

Input GLBs and editable sources are never saved or modified. Each image has a
matching per-model JSON report recording the input SHA256, pose and camera.
"""
import argparse
import hashlib
import json
import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
HEROES = ("asta", "yuno", "magna", "vanessa", "noelle", "charmy")
DIRECTIONS = {
    "front": (0, -1, 0),
    "threequarter": (.66, -.75, .035),
    "side": (1, 0, 0),
    "back": (0, 1, 0),
    "head_front": (0, -1, 0),
    "head_threequarter": (.66, -.75, .025),
    "head_side": (1, 0, 0),
}


def select_pose(scene, clip="Idle", phase=0.0):
    """Select imported Idle NLA strips, avoiding accidental clip blending."""
    rows = []
    for obj in list(scene.objects):
        data = obj.animation_data
        if data is None:
            continue
        tracks = list(data.nla_tracks)
        idle_tracks = [t for t in tracks if clip.lower() in t.name.lower() or any(
            clip.lower() in s.name.lower() or (s.action and clip.lower() in s.action.name.lower())
            for s in t.strips)]
        if idle_tracks:
            data.action = None
            for track in tracks:
                track.mute = track not in idle_tracks
            first = min(s.frame_start for t in idle_tracks for s in t.strips)
            rows.append({"object": obj.name, "tracks": [t.name for t in idle_tracks],
                         "first_frame": first, "last_frame": max(s.frame_end for t in idle_tracks for s in t.strips)})
        elif obj.type == "ARMATURE":
            choices = [a for a in bpy.data.actions if clip.lower() in a.name.lower()]
            if not choices:
                raise RuntimeError("Imported rig has no Idle animation: " + obj.name)
            action = choices[0]
            data.action = action
            if hasattr(action, "slots") and len(action.slots) == 1:
                data.action_slot = action.slots[0]
            rows.append({"object": obj.name, "action": action.name,
                         "first_frame": float(action.frame_range[0]), "last_frame": float(action.frame_range[1])})
    if not rows:
        raise RuntimeError("No imported animation data; cannot verify the Idle pose")
    first = min(r["first_frame"] for r in rows)
    last = max(r["last_frame"] for r in rows)
    frame = first + max(0.0,min(1.0,phase))*(last-first)
    scene.frame_set(math.floor(frame), subframe=frame - math.floor(frame))
    bpy.context.view_layer.update()
    return rows, frame


def material(name, color, roughness):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    shader = mat.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = (*color, 1)
    shader.inputs["Roughness"].default_value = roughness
    return mat


def setup_studio(scene, low, high, width, samples):
    scene.render.engine = "BLENDER_EEVEE"
    if hasattr(scene, "eevee") and hasattr(scene.eevee, "taa_render_samples"):
        scene.eevee.taa_render_samples = samples
    scene.render.resolution_x = width
    scene.render.resolution_y = round(width * 1.25)
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    scene.view_settings.look = "None"
    scene.world = bpy.data.worlds.new("ReviewNeutralWorld")
    scene.world.use_nodes = True
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (.20, .22, .26, 1)
    background.inputs["Strength"].default_value = .65
    center = (low + high) * .5
    height = max(.5, high.z - low.z)
    bpy.ops.mesh.primitive_plane_add(size=height * 12, location=(center.x, center.y, low.z - .006))
    bpy.context.object.name = "ReviewGround"
    bpy.context.object.data.materials.append(material("ReviewGroundMaterial", (.16, .18, .21), .92))
    for location, power, size, color in [
        ((2.8, -4.0, 5.0), 700, 3.4, (1.0, .94, .88)),
        ((-3.1, -2.8, 3.4), 470, 3.5, (.83, .90, 1.0)),
        ((.8, 3.0, 4.2), 950, 3.0, (1.0, 1.0, 1.0)),
    ]:
        bpy.ops.object.light_add(type="AREA", location=location)
        light = bpy.context.object
        light.data.energy = power
        light.data.shape = "DISK"
        light.data.size = size
        light.data.color = color
        light.rotation_euler = (Vector((center.x, center.y, low.z + height * .60)) - light.location).to_track_quat("-Z", "Y").to_euler()
    bpy.ops.object.camera_add()
    scene.camera = bpy.context.object
    scene.camera.name = "ReviewCamera"
    scene.camera.data.type = "ORTHO"
    return scene.camera


def review_model(path, output, options):
    before = hashlib.sha256(path.read_bytes()).hexdigest()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    scene = bpy.context.scene
    # The glTF importer adds a hidden unit-size bone-display mesh. Its bounds
    # are unrelated to the character and must not shrink the review framing.
    meshes = [o for o in scene.objects if o.type == "MESH"
              and any(mod.type == "ARMATURE" for mod in o.modifiers)]
    rigs = [o for o in scene.objects if o.type == "ARMATURE"]
    if not meshes or not rigs:
        raise RuntimeError("Expected actual skinned character geometry: " + str(path))
    pose, frame = select_pose(scene, options.clip, options.clip_phase)
    graph = bpy.context.evaluated_depsgraph_get()
    bounds = [o.evaluated_get(graph).matrix_world @ Vector(corner)
              for o in meshes for corner in o.evaluated_get(graph).bound_box]
    low = Vector(tuple(min(p[i] for p in bounds) for i in range(3)))
    high = Vector(tuple(max(p[i] for p in bounds) for i in range(3)))
    center = (low + high) * .5
    eyes = [arm.matrix_world @ bone.matrix.translation for arm in rigs
            for bone in arm.pose.bones if bone.name.lower() in {"eye.l", "eye.r"}]
    if eyes:
        head = sum(eyes, Vector()) / len(eyes) + Vector((0, .012, .045))
    else:
        raise RuntimeError("No anatomical eye bones available for reproducible head framing")
    camera = setup_studio(scene, low, high, options.resolution, options.samples)
    aspect = scene.render.resolution_x / scene.render.resolution_y
    images = []
    for view in options.views:
        is_head = view.startswith("head_")
        focus = head if is_head else center
        direction = Vector(DIRECTIONS[view]).normalized()
        camera.location = focus + direction * max(4, (high.z - low.z) * 2.7)
        camera.rotation_euler = (focus - camera.location).to_track_quat("-Z", "Y").to_euler()
        if is_head:
            camera.data.ortho_scale = options.head_scale
        else:
            right = camera.rotation_euler.to_quaternion() @ Vector((1, 0, 0))
            view_width = max(p.dot(right) for p in bounds) - min(p.dot(right) for p in bounds)
            camera.data.ortho_scale = max((high.z - low.z) * 1.14, view_width / aspect * 1.14)
        filename = output / (path.stem + "_" + view + ".png")
        scene.render.filepath = str(filename)
        bpy.ops.render.render(write_still=True)
        images.append({"view": view, "file": str(filename), "camera": list(camera.location),
                       "focus": list(focus), "ortho_scale": camera.data.ortho_scale})
        print("HERO_REVIEW_RENDER", filename, flush=True)
    after = hashlib.sha256(path.read_bytes()).hexdigest()
    if before != after:
        raise RuntimeError("Review unexpectedly changed its input: " + str(path))
    report = {"input": str(path), "input_sha256": before, "input_unchanged": True,
              "pose": options.clip, "clip_phase": options.clip_phase, "frame": frame, "pose_selection": pose,
              "view_transform": scene.view_settings.view_transform, "renderer": scene.render.engine,
              "mesh_objects": len(meshes), "bones": sum(len(a.data.bones) for a in rigs),
              "animation_actions": [a.name for a in bpy.data.actions],
              "bounds_min": list(low), "bounds_max": list(high), "images": images}
    (output / (path.stem + ".review.json")).write_text(json.dumps(report, indent=2), encoding="utf-8")
    return report


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    parser = argparse.ArgumentParser(description=__doc__)
    choice = parser.add_mutually_exclusive_group(required=True)
    choice.add_argument("--input", nargs="+", type=Path)
    choice.add_argument("--heroes", "--hero", help="Comma-separated hero names, or all")
    parser.add_argument("--clip", choices=("Idle","Attack","Ability"), default="Idle")
    parser.add_argument("--clip-phase", type=float, default=0.0)
    parser.add_argument("--rank", type=int, choices=range(1, 6), default=1)
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument("--views", default="front,threequarter,side,back")
    parser.add_argument("--head", action="store_true", help="Also render head front/3q/side")
    parser.add_argument("--head-scale", type=float, default=.72)
    parser.add_argument("--resolution", type=int, default=800, help="Image width; height is width * 1.25")
    parser.add_argument("--samples", type=int, default=32)
    options = parser.parse_args(argv)
    aliases = {"3q": "threequarter", "head3q": "head_threequarter"}
    options.views = [aliases.get(x, x) for x in options.views.split(",") if x]
    if options.head:
        options.views += [x for x in ("head_front", "head_threequarter", "head_side") if x not in options.views]
    if not options.views or any(x not in DIRECTIONS for x in options.views):
        parser.error("Unknown/empty view list; use " + ",".join(DIRECTIONS))
    if options.resolution < 128 or options.head_scale <= 0:
        parser.error("Invalid resolution/head scale")
    heroes = HEROES if options.heroes == "all" else tuple((options.heroes or "").split(","))
    if options.input:
        inputs = [p.resolve() for p in options.input]
    else:
        if any(h not in HEROES for h in heroes):
            parser.error("Unknown hero; use " + ",".join(HEROES))
        inputs = [ROOT / "Assets" / "Heroes" / f"{hero}_L{options.rank}.glb" for hero in heroes]
    if any(not p.is_file() or p.suffix.lower() != ".glb" for p in inputs):
        parser.error("Every input must be an existing .glb file")
    output = options.output_dir.resolve()
    output.mkdir(parents=True, exist_ok=True)
    rows = [review_model(p, output, options) for p in inputs]
    (output / "review-index.json").write_text(json.dumps(rows, indent=2), encoding="utf-8")
    print("HERO_REVIEW_OK", len(rows), output, flush=True)


if __name__ == "__main__":
    main()
