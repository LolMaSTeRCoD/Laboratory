"""Pack opaque glTF-compatible character materials into one UV atlas.

Run inside Blender, after UV creation and before GLB export. Geometry, rig,
skinning, shape keys and animation are untouched. Unsupported node graphs fail
before changing the mesh. This is texture packing, not a lighting bake.
"""
from pathlib import Path
import math
import bpy
import numpy as np


class AtlasError(RuntimeError):
    pass


def _srgb_to_linear(rgb):
    return np.where(rgb <= .04045, rgb / 12.92, ((rgb + .055) / 1.055) ** 2.4)


def _linear_to_srgb(rgb):
    rgb = np.maximum(rgb, 0)
    return np.where(rgb <= .0031308, rgb * 12.92, 1.055 * rgb ** (1 / 2.4) - .055)


def _pixels(image):
    if image is None or image.size[0] == 0 or image.size[1] == 0:
        raise AtlasError("A material references an empty image")
    data = np.empty(image.size[0] * image.size[1] * 4, np.float32)
    image.pixels.foreach_get(data)
    return data.reshape(image.size[1], image.size[0], 4)


def _sample(data, size):
    """Bilinear resize, retaining colors and avoiding nearest-neighbor shimmer."""
    if data.shape[:2] == (size, size):
        return data.copy()
    h, w = data.shape[:2]
    xs = np.linspace(0, w - 1, size, dtype=np.float32)
    ys = np.linspace(0, h - 1, size, dtype=np.float32)
    x0 = np.floor(xs).astype(int); x1 = np.minimum(x0 + 1, w - 1)
    y0 = np.floor(ys).astype(int); y1 = np.minimum(y0 + 1, h - 1)
    wx = (xs - x0)[None, :, None]; wy = (ys - y0)[:, None, None]
    a = data[y0[:, None], x0[None, :]]
    b = data[y0[:, None], x1[None, :]]
    c = data[y1[:, None], x0[None, :]]
    d = data[y1[:, None], x1[None, :]]
    return ((a * (1 - wx) + b * wx) * (1 - wy) + (c * (1 - wx) + d * wx) * wy).astype(np.float32)


def _value(socket, size, channels=1, seen=None):
    if not socket.is_linked:
        value = socket.default_value
        if channels == 1:
            return np.full((size, size, 1), float(value), np.float32)
        values = tuple(value) if hasattr(value, "__len__") else (float(value),) * channels
        return np.broadcast_to(np.array(values[:channels], np.float32), (size, size, channels)).copy()
    link = socket.links[0]
    node = link.from_node
    if node.type == "TEX_IMAGE":
        if node.inputs["Vector"].is_linked:
            source = node.inputs["Vector"].links[0].from_node
            if source.type != "UVMAP":
                raise AtlasError("Mapped/procedural image coordinates are not supported: " + node.name)
        if node.extension not in {"REPEAT", "EXTEND"}:
            raise AtlasError("Unsupported image extension: " + node.extension)
        data = _sample(_pixels(node.image), size)
        if link.from_socket.name == "Alpha":
            return data[:, :, 3:4]
        # Pixel buffers loaded from an sRGB PNG contain encoded samples, whereas
        # Principled socket constants are scene-linear. Blend/pack in linear.
        if node.image.colorspace_settings.name == "sRGB":
            data[:, :, :3] = _srgb_to_linear(data[:, :, :3])
        return data[:, :, :channels]
    if node.type in {"SEPARATE_COLOR", "SEPRGB"}:
        source = _value(node.inputs[0], size, 4)
        channel = {"Red": 0, "Green": 1, "Blue": 2, "R": 0, "G": 1, "B": 2}.get(link.from_socket.name)
        if channel is None:
            raise AtlasError("Unknown separate-color channel: " + link.from_socket.name)
        return source[:, :, channel:channel + 1]
    if node.type == "MATH" and node.operation == "MULTIPLY":
        return _value(node.inputs[0], size) * _value(node.inputs[1], size)
    if node.type == "MIX_RGB" and node.blend_type == "MULTIPLY":
        factor = _value(node.inputs[0], size)
        a = _value(node.inputs[1], size, channels)
        b = _value(node.inputs[2], size, channels)
        return a * ((1 - factor) + b * factor)
    raise AtlasError("Unsupported node feeding %s: %s (%s)" % (socket.name, node.name, node.type))


def _socket(principled, name, fallback=None):
    socket = principled.inputs.get(name)
    if socket is None and fallback:
        socket = principled.inputs.get(fallback)
    return socket


def _read_material(material, size):
    if material is None or not material.use_nodes:
        raise AtlasError("Every source material must use a Principled BSDF")
    outputs = [n for n in material.node_tree.nodes if n.type == "OUTPUT_MATERIAL" and n.is_active_output]
    if len(outputs) != 1 or not outputs[0].inputs["Surface"].is_linked:
        raise AtlasError("Material must have one active surface: " + material.name)
    p = outputs[0].inputs["Surface"].links[0].from_node
    if p.type != "BSDF_PRINCIPLED":
        raise AtlasError("Only direct Principled surfaces can be packed: " + material.name)
    if outputs[0].inputs["Displacement"].is_linked or outputs[0].inputs["Volume"].is_linked:
        raise AtlasError("Displacement/volume cannot be flattened into a character atlas: " + material.name)
    # IOR changes cannot vary through a core glTF metallic/roughness texture.
    ior = _socket(p, "IOR")
    if ior is not None and (ior.is_linked or abs(float(ior.default_value) - 1.5) > 1e-5):
        raise AtlasError("Nonstandard/varying IOR needs its own material: " + material.name)
    for name in ["Transmission Weight", "Transmission", "Anisotropic IOR Level", "Anisotropic", "Sheen Weight", "Sheen"]:
        socket = p.inputs.get(name)
        if socket is not None and (socket.is_linked or abs(float(socket.default_value)) > 1e-6):
            raise AtlasError("Unsupported active Principled property %s: %s" % (name, material.name))
    base = _value(p.inputs["Base Color"], size, 4)
    alpha = _value(p.inputs["Alpha"], size)
    # Original KDTD character materials are opaque. Avoid silently losing cutouts.
    if float(alpha.min()) < .999:
        raise AtlasError("Alpha materials must remain separate: " + material.name)
    base[:, :, 3:4] = alpha
    orm = np.ones((size, size, 4), np.float32)
    orm[:, :, 1:2] = _value(p.inputs["Roughness"], size)
    orm[:, :, 2:3] = _value(p.inputs["Metallic"], size)
    # Coat and specular parameters have real glTF texture extensions.
    aux = np.zeros((size, size, 4), np.float32); aux[:, :, 3] = 1
    aux[:, :, 0:1] = _value(_socket(p, "Coat Weight", "Clearcoat"), size)
    aux[:, :, 1:2] = _value(_socket(p, "Coat Roughness", "Clearcoat Roughness"), size)
    aux[:, :, 2:3] = _value(_socket(p, "Specular IOR Level", "Specular"), size)
    emission = _value(_socket(p, "Emission Color", "Emission"), size, 4)
    strength = _socket(p, "Emission Strength")
    if strength is not None:
        emission[:, :, :3] *= _value(strength, size)
    emission[:, :, 3] = 1
    normal = np.empty((size, size, 4), np.float32); normal[:] = (.5, .5, 1, 1)
    normal_input = p.inputs["Normal"]
    has_normal = normal_input.is_linked
    if has_normal:
        n = normal_input.links[0].from_node
        if n.type != "NORMAL_MAP" or n.space != "TANGENT":
            raise AtlasError("Only tangent-space Normal Map nodes can be packed: " + material.name)
        if n.uv_map and n.uv_map != "UVMap":
            raise AtlasError("Normal map uses another UV set: " + material.name)
        normal[:, :, :3] = _value(n.inputs["Color"], size, 4)[:, :, :3]
        strength = _value(n.inputs["Strength"], size)
        xyz = normal[:, :, :3] * 2 - 1
        xyz[:, :, :2] *= strength
        xyz /= np.maximum(np.linalg.norm(xyz, axis=2, keepdims=True), 1e-8)
        normal[:, :, :3] = xyz * .5 + .5
    coat_normal = _socket(p, "Coat Normal", "Clearcoat Normal")
    if coat_normal is not None and coat_normal.is_linked:
        raise AtlasError("Separate coat normals need their own material: " + material.name)
    return dict(base=base, orm=orm, aux=aux, emission=emission, normal=normal,
                has_normal=has_normal, name=material.name,
                subsurface=float(_socket(p, "Subsurface Weight", "Subsurface").default_value))


def _write_image(name, data, path, noncolor=False):
    image = bpy.data.images.new(name, width=data.shape[1], height=data.shape[0], alpha=True)
    image.colorspace_settings.name = "Non-Color" if noncolor else "sRGB"
    encoded = data.copy()
    if not noncolor:
        encoded[:, :, :3] = _linear_to_srgb(encoded[:, :, :3])
    image.pixels.foreach_set(encoded.ravel())
    image.filepath_raw = str(path); image.file_format = "PNG"; image.save()
    image.pack()
    return image


def pack_character_materials(obj, tag, output_directory, resolution=2048, gutter=4):
    """Return a packing report; mutate only obj material slots and active UVs.

    The 2K default gives 504px content cells for a 4x4 atlas, with four-pixel
    extruded gutters. Set resolution=4096 to retain source 512px maps without
    downsampling. Colors, roughness, metalness, emission and optional tangent
    normals are packed. Core glTF does not export Blender subsurface scattering;
    its presence is reported, matching the original export limitation.
    """
    if obj.type != "MESH" or obj.data.uv_layers.active is None:
        raise AtlasError("Expected a mesh with active UVs")
    mesh = obj.data
    used = sorted({p.material_index for p in mesh.polygons})
    if not used:
        raise AtlasError("Mesh has no polygons")
    if len(used) == 1 and obj.get("atlas_packed"):
        return {"already_packed": True, "material_count": 1}
    grid = int(math.ceil(math.sqrt(len(used))))
    cell = resolution // grid
    inner = cell - 2 * gutter
    if inner < 16:
        raise AtlasError("Atlas resolution is too small")
    tiles = []
    for index in used:
        if index >= len(mesh.materials):
            raise AtlasError("Polygon references nonexistent material slot")
        tiles.append(_read_material(mesh.materials[index], inner))
    uv_layer = mesh.uv_layers.active
    # Fail before mutation if repeating UVs would require per-triangle clipping.
    uv_coords = np.empty(len(uv_layer.data) * 2, np.float32)
    uv_layer.data.foreach_get("uv", uv_coords)
    uv_coords = uv_coords.reshape(-1, 2)
    if not np.all(np.isfinite(uv_coords)) or uv_coords.min() < -1e-4 or uv_coords.max() > 1.0001:
        raise AtlasError("UVs must be finite and within [0,1]; repeating islands need clipping first")
    atlases = {key: np.zeros((resolution, resolution, 4), np.float32)
               for key in ["base", "orm", "aux", "emission", "normal"]}
    for data in atlases.values(): data[:, :, 3] = 1
    atlases["normal"][:] = (.5, .5, 1, 1)
    mapping = {}
    for tile_index, (material_index, tile) in enumerate(zip(used, tiles)):
        row, col = divmod(tile_index, grid); y = row * cell; x = col * cell
        mapping[material_index] = (x, y)
        for key, atlas in atlases.items():
            padded = np.pad(tile[key], ((gutter, gutter), (gutter, gutter), (0, 0)), mode="edge")
            atlas[y:y + cell, x:x + cell] = padded
    out = Path(output_directory); out.mkdir(parents=True, exist_ok=True)
    images = {}
    has_emission = any(float(tile["emission"][:, :, :3].max()) > 1e-6 for tile in tiles)
    has_normal = any(tile["has_normal"] for tile in tiles)
    emission_scale = max(1.0, float(atlases["emission"][:, :, :3].max()))
    atlases["emission"][:, :, :3] /= emission_scale
    for key in ["base", "orm", "aux"] + (["emission"] if has_emission else []) + (["normal"] if has_normal else []):
        images[key] = _write_image(tag + "_atlas_" + key, atlases[key], out / (tag + "_atlas_" + key + ".png"), key not in {"base", "emission"})
    mat = bpy.data.materials.new(tag + "_AtlasMaterial"); mat.use_nodes = True
    p = mat.node_tree.nodes.get("Principled BSDF"); nodes = mat.node_tree.nodes; links = mat.node_tree.links
    def tex(key, noncolor=False):
        node = nodes.new("ShaderNodeTexImage"); node.image = images[key]; node.extension = "EXTEND"; node.interpolation = "Linear"
        return node
    base = tex("base"); links.new(base.outputs["Color"], p.inputs["Base Color"])
    p.inputs["Alpha"].default_value = 1
    orm = tex("orm"); sep = nodes.new("ShaderNodeSeparateColor"); links.new(orm.outputs["Color"], sep.inputs["Color"])
    links.new(sep.outputs["Green"], p.inputs["Roughness"]); links.new(sep.outputs["Blue"], p.inputs["Metallic"])
    aux = tex("aux"); sep2 = nodes.new("ShaderNodeSeparateColor"); links.new(aux.outputs["Color"], sep2.inputs["Color"])
    links.new(sep2.outputs["Red"], _socket(p, "Coat Weight", "Clearcoat"))
    links.new(sep2.outputs["Green"], _socket(p, "Coat Roughness", "Clearcoat Roughness"))
    links.new(sep2.outputs["Blue"], _socket(p, "Specular IOR Level", "Specular"))
    if has_emission:
        emission = tex("emission"); links.new(emission.outputs["Color"], _socket(p, "Emission Color", "Emission"))
        _socket(p, "Emission Strength").default_value = emission_scale
    if has_normal:
        normal = tex("normal"); n = nodes.new("ShaderNodeNormalMap"); n.space = "TANGENT"
        links.new(normal.outputs["Color"], n.inputs["Color"]); links.new(n.outputs["Normal"], p.inputs["Normal"])
    # Transform loop UVs only after all material reads and image writes succeed.
    for face in mesh.polygons:
        x, y = mapping[face.material_index]
        for loop in face.loop_indices:
            u, v = uv_coords[loop]
            # Center coordinates within the content texels and their extruded gutter.
            uv_layer.data[loop].uv = ((x + gutter + .5 + min(1, max(0, u)) * (inner - 1)) / resolution,
                                     (y + gutter + .5 + min(1, max(0, v)) * (inner - 1)) / resolution)
        face.material_index = 0
    mesh.materials.clear(); mesh.materials.append(mat)
    obj["atlas_packed"] = True; obj["atlas_source_materials"] = len(used)
    report = {"object": obj.name, "source_materials": len(used), "material_count": 1,
              "resolution": resolution, "grid": grid, "content_pixels_per_cell": inner, "gutter": gutter,
              "has_emission": has_emission, "has_normal": has_normal,
              "source_subsurface_not_exported_by_gltf": [t["name"] for t in tiles if t["subsurface"] > 1e-6],
              "images": {key: image.filepath_raw for key, image in images.items()}}
    print("CHARACTER_ATLAS_PACKED", report, flush=True)
    return report
