"""Audit images actually feeding mesh materials in editable Blender models.

Run with Blender --background --python this_file.py -- --folder SOURCE --report REPORT.
Audit mode opens files read-only and never saves them. Import the packing
guard from an asset builder before save; it touches only reachable images.
"""
import argparse
import hashlib
import json
import sys
from pathlib import Path
import bpy


def used_material_images(objects):
    """Return only images upstream of active outputs on used mesh materials."""
    images={};materials={};visited=set()

    def visit_node(tree,node):
        key=(tree.as_pointer(),node.as_pointer())
        if key in visited:return
        visited.add(key)
        if node.type=='TEX_IMAGE' and node.image is not None:
            images[node.image.as_pointer()]=node.image
        if node.type=='GROUP' and node.node_tree is not None:
            walk_tree(node.node_tree)
        for socket in node.inputs:
            for link in socket.links:visit_node(tree,link.from_node)

    def walk_tree(tree):
        roots=[n for n in tree.nodes if n.type in {'OUTPUT_MATERIAL','GROUP_OUTPUT'} and getattr(n,'is_active_output',True)]
        for node in roots:visit_node(tree,node)

    for obj in objects:
        if obj.type!='MESH':continue
        indices={p.material_index for p in obj.data.polygons}
        for index in indices:
            if index>=len(obj.data.materials):continue
            material=obj.data.materials[index]
            if material is None:continue
            materials[material.as_pointer()]=material
            if material.use_nodes and material.node_tree is not None:walk_tree(material.node_tree)
    return sorted(images.values(),key=lambda i:i.name),sorted(materials.values(),key=lambda m:m.name)


def packed_entries(image):
    entries=list(getattr(image,'packed_files',[]))
    if entries:return [e.packed_file for e in entries if e.packed_file is not None]
    packed=getattr(image,'packed_file',None)
    return [packed] if packed is not None else []


def ensure_packed_model_images(objects):
    """Builder guard: pack reachable material images, never orphan source tiles."""
    images,_=used_material_images(objects)
    for image in images:
        if not packed_entries(image):image.pack()
        entries=packed_entries(image)
        if not entries or any(p.size<=0 for p in entries):
            raise RuntimeError('Material image is not self-contained: '+image.name)
    return len(images)


def audit_file(path):
    sha_before=hashlib.sha256(path.read_bytes()).hexdigest()
    bpy.ops.wm.open_mainfile(filepath=str(path),load_ui=False)
    meshes=[o for o in bpy.data.objects if o.type=='MESH']
    images,materials=used_material_images(meshes)
    rows=[]
    for image in images:
        packed=packed_entries(image)
        rows.append(dict(name=image.name,source=image.source,filepath=image.filepath,
            pixels=list(image.size),packed=bool(packed),packed_entries=len(packed),
            packed_bytes=sum(p.size for p in packed),
            valid=bool(packed) and all(p.size>0 for p in packed)))
    sha_after=hashlib.sha256(path.read_bytes()).hexdigest()
    assert sha_before==sha_after,'Audit unexpectedly modified source: '+str(path)
    used={i.as_pointer() for i in images}
    external_libraries=[l.filepath for l in bpy.data.libraries]
    return dict(file=str(path),sha256=sha_after,source_unchanged=True,
        meshes=len(meshes),used_materials=[m.name for m in materials],used_images=rows,
        other_images_not_packed_or_modified=sum(i.as_pointer() not in used for i in bpy.data.images),
        external_libraries=external_libraries,
        passed=all(r['valid'] for r in rows) and not external_libraries)


def main():
    args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--folder',required=True)
    parser.add_argument('--report',required=True)
    parser.add_argument('--recursive',action='store_true')
    options=parser.parse_args(args)
    folder=Path(options.folder)
    files=sorted(folder.rglob('*.blend') if options.recursive else folder.glob('*.blend'))
    if not files:raise RuntimeError('No editable .blend files found in '+str(folder))
    results=[]
    for file in files:
        result=audit_file(file);results.append(result)
        print('PACKED_SOURCE_AUDIT',file.name,'images',len(result['used_images']),
            'packed_bytes',sum(r['packed_bytes'] for r in result['used_images']),
            'PASS' if result['passed'] else 'FAIL',flush=True)
    report=Path(options.report);report.parent.mkdir(parents=True,exist_ok=True)
    report.write_text(json.dumps(dict(passed=all(r['passed'] for r in results),
        folder=str(folder),mode='read-only; reachable mesh material images only',
        files=results),indent=2),encoding='utf8')
    if not all(r['passed'] for r in results):raise RuntimeError('Unpacked used images or external libraries: '+str(report))
    print('ALL_EDITABLE_SOURCES_SELF_CONTAINED',len(results),report,flush=True)


if __name__=='__main__':main()
