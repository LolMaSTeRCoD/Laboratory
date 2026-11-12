import bpy
import bmesh
import math
import os
import random
import zlib
from mathutils import Vector

OUT_DIR = r"G:\Cady\GodotRebuild\Assets\Heroes"
TEXTURE_DIR = os.path.join(OUT_DIR, "Textures")
os.makedirs(TEXTURE_DIR, exist_ok=True)

TAU = math.pi * 2.0

PALETTES = {
    # Palettes are based on official front-view character art kept in
    # G:\Cady\Reference\BlackClover. They are not sampled or shipped as textures.
    "asta": {"skin":(0.78,0.57,0.45,1),"hair":(0.67,0.66,0.62,1),"cloth":(0.20,0.29,0.38,1),"cloak":(0.035,0.043,0.060,1),"pants":(0.085,0.105,0.15,1),"boots":(0.055,0.062,0.075,1),"leather":(0.39,0.25,0.13,1),"trim":(0.77,0.61,0.34,1),"metal":(0.17,0.18,0.20,1),"accent":(0.60,0.12,0.13,1),"glow":(0.46,0.035,0.045,1),"eyes":(0.20,0.48,0.34,1),"white":(0.90,0.88,0.83,1)},
    "yuno": {"skin":(0.78,0.60,0.47,1),"hair":(0.055,0.065,0.085,1),"cloth":(0.13,0.15,0.19,1),"cloak":(0.065,0.08,0.11,1),"pants":(0.12,0.14,0.18,1),"boots":(0.10,0.12,0.15,1),"trim":(0.78,0.65,0.34,1),"metal":(0.25,0.27,0.29,1),"accent":(0.29,0.43,0.29,1),"glow":(0.37,0.78,0.58,1),"eyes":(0.40,0.62,0.45,1),"white":(0.82,0.80,0.75,1)},
    "magna": {"skin":(0.70,0.45,0.33,1),"hair":(0.48,0.36,0.66,1),"cloth":(0.28,0.27,0.33,1),"cloak":(0.075,0.08,0.105,1),"pants":(0.12,0.12,0.16,1),"boots":(0.12,0.12,0.15,1),"trim":(0.77,0.61,0.32,1),"metal":(0.18,0.18,0.21,1),"accent":(0.28,0.37,0.56,1),"glow":(1.0,0.23,0.035,1),"eyes":(0.35,0.53,0.46,1),"white":(0.82,0.79,0.76,1)},
    "vanessa": {"skin":(0.78,0.56,0.46,1),"hair":(0.72,0.31,0.43,1),"cloth":(0.40,0.10,0.20,1),"cloak":(0.075,0.07,0.09,1),"pants":(0.43,0.12,0.22,1),"boots":(0.38,0.10,0.20,1),"trim":(0.78,0.57,0.29,1),"metal":(0.25,0.22,0.24,1),"accent":(0.54,0.12,0.25,1),"glow":(0.93,0.23,0.49,1),"eyes":(0.42,0.60,0.48,1),"white":(0.83,0.73,0.72,1)},
    "noelle": {"skin":(0.80,0.62,0.54,1),"hair":(0.77,0.78,0.82,1),"cloth":(0.84,0.83,0.80,1),"cloak":(0.065,0.075,0.10,1),"pants":(0.78,0.76,0.76,1),"boots":(0.57,0.46,0.27,1),"trim":(0.80,0.69,0.39,1),"metal":(0.44,0.48,0.53,1),"accent":(0.55,0.32,0.54,1),"glow":(0.20,0.65,0.92,1),"eyes":(0.62,0.38,0.72,1),"white":(0.92,0.90,0.86,1)}
}

MATERIAL_PROPS = {
    "skin":(0.55,0.0),"pants":(0.77,0.0),"hair":(0.78,0.0),"cloth":(0.82,0.0),"cloak":(0.78,0.0),"leather":(0.76,0.0),
    "trim":(0.34,0.32),"metal":(0.26,0.68),"accent":(0.46,0.08),"glow":(0.26,0.0),"boots":(0.52,0.0),
    "eyes":(0.24,0.0),"white":(0.48,0.0)
}

class MeshBuild:
    def __init__(self, mats, bones):
        self.mats = mats
        self.bones = bones
        self.v = []
        self.f = []
        self.fm = []
        self.weights = []

    def add(self, verts, faces, material, bone, secondary=None):
        off = len(self.v)
        # The head is deliberately proportioned as an anime hero's head, not a
        # large toy head. Keep facial features and hair on the same sculpted form.
        if bone == "head":
            verts = [(x*0.86, y*0.88, 1.98+(z-1.98)*0.89) for x,y,z in verts]
        self.v.extend(tuple(v) for v in verts)
        self.weights.extend([bone] * len(verts))
        self.f.extend([tuple(off+i for i in face) for face in faces])
        material_key=material if isinstance(material,str) else next(k for k,v in self.mats.items() if v==material)
        self.fm.extend([list(self.mats).index(material_key)] * len(faces))
        if secondary:
            for local_i, weight_map in secondary.items():
                self.weights[off+local_i] = weight_map

    def ellipsoid(self, center, radii, material, bone, seg=20, rings=12):
        cx,cy,cz=center; rx,ry,rz=radii
        verts=[(cx,cy,cz+rz)]
        for j in range(1,rings):
            phi=math.pi*j/rings
            for i in range(seg):
                theta=TAU*i/seg
                verts.append((cx+rx*math.sin(phi)*math.cos(theta),cy+ry*math.sin(phi)*math.sin(theta),cz+rz*math.cos(phi)))
        bottom=len(verts);verts.append((cx,cy,cz-rz));faces=[]
        for i in range(seg): faces.append((0,1+i,1+(i+1)%seg))
        for j in range(rings-2):
            a=1+j*seg;b=a+seg
            for i in range(seg):
                n=(i+1)%seg;faces.append((a+i,b+i,b+n,a+n))
        start=1+(rings-2)*seg
        for i in range(seg): faces.append((start+i,bottom,start+(i+1)%seg))
        self.add(verts,faces,material,bone)

    def box(self, center, size, material, bone):
        cx,cy,cz=center;sx,sy,sz=[v*0.5 for v in size]
        verts=[(cx-sx,cy-sy,cz-sz),(cx+sx,cy-sy,cz-sz),(cx+sx,cy+sy,cz-sz),(cx-sx,cy+sy,cz-sz),(cx-sx,cy-sy,cz+sz),(cx+sx,cy-sy,cz+sz),(cx+sx,cy+sy,cz+sz),(cx-sx,cy+sy,cz+sz)]
        faces=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
        self.add(verts,faces,material,bone)

    def loft(self, ringspec, material, bone, sides=20, blend_bones=None):
        verts=[];faces=[];weights={}
        # ring tuple: center_x, center_y, z, half_width, half_depth
        for ri,(cx,cy,z,rx,ry) in enumerate(ringspec):
            for s in range(sides):
                t=TAU*s/sides
                verts.append((cx+rx*math.cos(t),cy+ry*math.sin(t),z))
                if blend_bones and ri < len(ringspec):
                    lower,upper,split=blend_bones
                    amount=max(0.0,min(1.0,(z-split)/0.24))
                    weights[len(verts)-1]={lower:1-amount,upper:amount}
        for r in range(len(ringspec)-1):
            for s in range(sides):
                a=r*sides+s;b=r*sides+(s+1)%sides;c=(r+1)*sides+(s+1)%sides;d=(r+1)*sides+s
                faces.append((a,b,c,d))
        faces.append(tuple(range(sides-1,-1,-1)))
        faces.append(tuple((len(ringspec)-1)*sides+i for i in range(sides)))
        self.add(verts,faces,material,bone,weights)

    def tube(self, points, radii, material, bone, sides=10, second_bone=None, second_start=0.55):
        pts=[Vector(p) for p in points];verts=[];faces=[];weights={}
        for i,p in enumerate(pts):
            tangent=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
            ref=Vector((0,1,0))
            if abs(tangent.dot(ref))>0.94: ref=Vector((1,0,0))
            u=tangent.cross(ref).normalized();v=tangent.cross(u).normalized()
            radius=radii[i] if isinstance(radii,(tuple,list)) else radii
            if isinstance(radius,(tuple,list)): ru,rv=radius
            else: ru=rv=radius
            for j in range(sides):
                a=TAU*j/sides
                q=p+u*(ru*math.cos(a))+v*(rv*math.sin(a))
                verts.append(tuple(q))
                if second_bone:
                    t=max(0.0,min(1.0,(i/(len(pts)-1)-second_start)/0.35))
                    weights[len(verts)-1]={bone:1-t,second_bone:t}
        for r in range(len(pts)-1):
            for s in range(sides):
                a=r*sides+s;b=r*sides+(s+1)%sides;c=(r+1)*sides+(s+1)%sides;d=(r+1)*sides+s
                faces.append((a,b,c,d))
        faces.append(tuple(range(sides-1,-1,-1)))
        faces.append(tuple((len(pts)-1)*sides+i for i in range(sides)))
        self.add(verts,faces,material,bone,weights)

    def panel(self, rows, cols, point_fn, material, bone):
        verts=[];faces=[]
        for r in range(rows+1):
            for c in range(cols+1): verts.append(point_fn(r/rows,c/cols))
        for r in range(rows):
            for c in range(cols):
                a=r*(cols+1)+c;b=a+1;d=(r+1)*(cols+1)+c;e=d+1
                faces.extend([(a,d,b),(b,d,e)])
        self.add(verts,faces,material,bone)

    def almond_eye(self, cx, cy, cz, material, bone, width=0.102, height=0.052):
        # A shallow, curved almond surface reads as an anime eye from any angle.
        verts=[]; faces=[]; steps=12
        for row in range(3):
            u=(row-1)/1.0
            for i in range(steps+1):
                t=i/steps
                x=cx+(t-0.5)*width
                arch=math.sin(math.pi*t)
                z=cz+u*height*0.5*arch
                y=cy-0.012*(1.0-u*u)*arch
                verts.append((x,y,z))
        for r in range(2):
            for i in range(steps):
                a=r*(steps+1)+i; b=a+1; d=a+steps+1; c=d+1
                faces.append((a,b,c,d))
        self.add(verts,faces,material,bone)

    def ribbon(self, points, width, material, bone):
        # Broad, gently curved cloth trim, modeled as a strip with a raised seam.
        pts=[Vector(p) for p in points]; verts=[]; faces=[]
        for i,p in enumerate(pts):
            tangent=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
            side=tangent.cross(Vector((0,1,0))).normalized()*width*0.5
            verts.extend([tuple(p-side),tuple(p+side)])
        for i in range(len(pts)-1): faces.append((2*i,2*i+1,2*i+3,2*i+2))
        self.add(verts,faces,material,bone)

def clear_scene():
    bpy.ops.object.select_all(action="SELECT")
    bpy.ops.object.delete(use_global=False)
    # Actions are datablocks and survive object deletion. Purge them before
    # generating the next hero so one GLB never contains another hero's clips.
    for block in list(bpy.data.actions):
        bpy.data.actions.remove(block)
    for block in list(bpy.data.materials):
        bpy.data.materials.remove(block)
    for block in list(bpy.data.images):
        bpy.data.images.remove(block)

def make_texture(name,color,seed,kind):
    resolution=512
    image=bpy.data.images.new(name,width=resolution,height=resolution,alpha=True)
    rng=random.Random(seed)
    pixels=[]
    for y in range(resolution):
        for x in range(resolution):
            n=(rng.random()-0.5)*0.045
            weave=0.0
            if kind in ("cloth","cloak"):
                weave=0.018*math.sin(x*0.8)+0.014*math.sin(y*0.92)+0.009*math.sin((x+y)*0.42)
            elif kind in ("metal","trim"):
                weave=0.012*math.sin((x+y)*0.16)
            shade=max(0.78,min(1.16,1.0+n+weave+0.025*math.sin(y/17.0)))
            pixels.extend((min(1,color[0]*shade),min(1,color[1]*shade),min(1,color[2]*shade),1.0))
    image.pixels.foreach_set(pixels)
    image.filepath_raw=os.path.join(TEXTURE_DIR,name+".png")
    image.file_format="PNG"
    image.save()
    image.pack()
    return image

def make_material(name,color,seed,kind):
    mat=bpy.data.materials.new(name)
    mat.diffuse_color=color
    mat.use_nodes=True
    nodes=mat.node_tree.nodes
    bsdf=nodes.get("Principled BSDF")
    if not bsdf: return mat
    rough,metal=MATERIAL_PROPS[kind]
    bsdf.inputs["Roughness"].default_value=rough
    bsdf.inputs["Metallic"].default_value=metal
    if kind=="hair":
        spec=bsdf.inputs.get("Specular IOR Level")
        if spec: spec.default_value=0.08
    if kind=="skin":
        subsurface=bsdf.inputs.get("Subsurface Weight")
        if subsurface: subsurface.default_value=0.045
        coat=bsdf.inputs.get("Coat Weight")
        if coat: coat.default_value=0.08
    img=make_texture(name+"_albedo",color,seed,kind)
    tex=nodes.new("ShaderNodeTexImage");tex.image=img;tex.interpolation="Linear";tex.location=(-360,80)
    mat.node_tree.links.new(tex.outputs["Color"],bsdf.inputs["Base Color"])
    if kind=="glow":
        emission=bsdf.inputs.get("Emission Color") or bsdf.inputs.get("Emission")
        if emission: emission.default_value=color
        strength=bsdf.inputs.get("Emission Strength")
        if strength: strength.default_value=0.22
    return mat

def create_materials(hero,level):
    mats={}
    base=PALETTES[hero]
    for index,key in enumerate(base):
        col=list(base[key])
        if key=="trim" and level>=3:
            factor=1.0+0.035*(level-2)
            col[:3]=[min(1.0,c*factor) for c in col[:3]]
        if key=="accent" and level>=4:
            col[0]=min(1.0,col[0]*1.08);col[1]=min(1.0,col[1]*1.04)
        stable_seed=zlib.crc32((hero+":"+key).encode("utf-8"))%100000+level*7919
        mats[key]=make_material(hero+"_L"+str(level)+"_"+key,tuple(col),stable_seed,key)
    return mats

def add_bone(arm_data,name,head,tail,parent=None,connect=False):
    b=arm_data.edit_bones.new(name);b.head=head;b.tail=tail
    if parent: b.parent=arm_data.edit_bones[parent];b.use_connect=connect
    return b

def make_rig(hero):
    arm_data=bpy.data.armatures.new(hero+"_Skeleton")
    arm_obj=bpy.data.objects.new(hero+"_Armature",arm_data)
    bpy.context.collection.objects.link(arm_obj)
    bpy.context.view_layer.objects.active=arm_obj;arm_obj.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    add_bone(arm_data,"root",(0,0,0),(0,0,0.88))
    add_bone(arm_data,"hips",(0,0,0.88),(0,0,1.12),"root")
    add_bone(arm_data,"spine",(0,0,1.12),(0,0,1.49),"hips")
    add_bone(arm_data,"chest",(0,0,1.49),(0,0,1.73),"spine")
    add_bone(arm_data,"neck",(0,0,1.73),(0,0,1.84),"chest")
    add_bone(arm_data,"head",(0,0,1.84),(0,0,2.20),"neck")
    add_bone(arm_data,"shoulder.L",(-.28,0,1.65),(-.39,0,1.59),"chest")
    add_bone(arm_data,"upper_arm.L",(-.39,0,1.59),(-.39,0,1.31),"shoulder.L")
    add_bone(arm_data,"forearm.L",(-.39,0,1.31),(-.40,0,1.05),"upper_arm.L")
    add_bone(arm_data,"hand.L",(-.40,0,1.05),(-.40,-.02,.94),"forearm.L")
    add_bone(arm_data,"shoulder.R",(.28,0,1.65),(.39,0,1.59),"chest")
    add_bone(arm_data,"upper_arm.R",(.39,0,1.59),(.39,0,1.31),"shoulder.R")
    add_bone(arm_data,"forearm.R",(.39,0,1.31),(.40,0,1.05),"upper_arm.R")
    add_bone(arm_data,"hand.R",(.40,0,1.05),(.40,-.02,.94),"forearm.R")
    add_bone(arm_data,"thigh.L",(-.14,0,.94),(-.15,0,.55),"hips")
    add_bone(arm_data,"shin.L",(-.15,0,.55),(-.15,0,.16),"thigh.L")
    add_bone(arm_data,"foot.L",(-.15,0,.16),(-.15,-.20,.08),"shin.L")
    add_bone(arm_data,"thigh.R",(.14,0,.94),(.15,0,.55),"hips")
    add_bone(arm_data,"shin.R",(.15,0,.55),(.15,0,.16),"thigh.R")
    add_bone(arm_data,"foot.R",(.15,0,.16),(.15,-.20,.08),"shin.R")
    add_bone(arm_data,"cape",(0,.16,1.64),(0,.34,.82),"chest")
    bpy.ops.object.mode_set(mode="OBJECT")
    arm_obj.show_in_front=False
    arm_obj.select_set(False)
    return arm_obj

def create_mesh_object(hero,level,builder,materials,armature):
    mesh=bpy.data.meshes.new(hero+"_L"+str(level)+"_Mesh")
    mesh.from_pydata(builder.v,[],builder.f);mesh.update()
    bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(mesh);bm.free();mesh.update()
    obj=bpy.data.objects.new(hero+"_L"+str(level),mesh);bpy.context.collection.objects.link(obj)
    for m in materials.values(): mesh.materials.append(m)
    for p,mi in zip(mesh.polygons,builder.fm): p.material_index=mi;p.use_smooth=True
    groups={name:obj.vertex_groups.new(name=name) for name in builder.bones}
    for index,w in enumerate(builder.weights):
        if isinstance(w,str): groups[w].add([index],1.0,"REPLACE")
        else:
            for bone,weight in w.items():
                if weight>0.001: groups[bone].add([index],weight,"REPLACE")
    mod=obj.modifiers.new("Character_Skin","ARMATURE");mod.object=armature
    obj.parent=armature
    bpy.context.view_layer.objects.active=obj;obj.select_set(True)
    try:
        bpy.ops.object.mode_set(mode="EDIT")
        bpy.ops.uv.smart_project(island_margin=0.015)
        bpy.ops.object.mode_set(mode="OBJECT")
    except Exception:
        if obj.mode!="OBJECT": bpy.ops.object.mode_set(mode="OBJECT")
    obj.select_set(False)
    return obj

def add_head_hair(builder,hero,mats,level):
    hair=mats["hair"];dark=mats["cloth"];accent=mats["accent"]
    # Sculpted hair cap and locks. The locks are tapered 3D meshes, not image planes.
    builder.ellipsoid((0,0.005,2.15),(.205,.19,.14),"hair","head",24,14)
    if hero=="asta":
        # Asta's pale, irregular starburst is built from separate curved locks.
        # Each lock has a broad root and a sharp tip so the hair reads as sculpted
        # anime geometry at close range rather than a ring of identical cones.
        for i in range(15):
            a=TAU*i/15+0.09*math.sin(i*2.7)
            x=.142*math.cos(a);y=.116*math.sin(a)
            outward=.055+.065*(0.5+0.5*math.sin(i*2.31))
            lift=.16+.105*(0.5+0.5*math.sin(i*1.73+0.6))
            root=(x,y,2.16+0.018*math.sin(i*1.7))
            mid=(x+math.cos(a)*outward*.42-.018,y+math.sin(a)*outward*.36,2.22+lift*.34)
            end=(x+math.cos(a)*outward-.035,y+math.sin(a)*outward*.74,2.16+lift)
            builder.tube([root,mid,end],[(.071,.060),(.050,.041),(.001,.001)],"hair","head",12)
        # Crown locks fan backward with unequal lengths and slight curvature,
        # giving the silver hair a layered silhouette instead of a cone fence.
        for i in range(7):
            x=-.15+i*.05
            sway=(i-3)*.014
            tip_z=2.36+.09*(0.5+0.5*math.sin(i*1.8))
            builder.tube([(x,.065,2.20),(x+sway,.11,2.29),(x+sway*1.5,.17,tip_z)],[(.064,.052),(.043,.035),(.001,.001)],"hair","head",11)
        for i in range(5):
            x=-.145+i*.073
            tip_z=2.006+(.026 if i in (1,3) else -.006 if i==2 else 0.0)
            sweep=-.014 if i<2 else .018 if i>2 else -.008
            builder.tube([(x,-.108,2.19),(x+sweep,-.164,2.125),(x+sweep*1.7,-.198,tip_z)],[(.049,.038),(.032,.024),(.001,.001)],"hair","head",11)
        # Fine silver ridges catch light along a few of the larger locks.
        for i in (1,4,7,10,13):
            a=TAU*i/15+0.09*math.sin(i*2.7)
            x=.142*math.cos(a);y=.116*math.sin(a)
            builder.tube([(x*1.04,y*1.04,2.18),(x+.015,y+.012,2.27),(x+math.cos(a)*.065-.025,y+math.sin(a)*.060,2.36+.035*math.sin(i*1.73))],[(.010,.007),(.007,.005),(.001,.001)],"white","head",6)
        # Dark fabric band wraps around the forehead and temples. The small
        # four-leaf emblem is raised gold geometry rather than a flat decal.
        builder.ribbon([(-.19,-.015,2.115),(-.16,-.125,2.145),(-.08,-.181,2.16),(0,-.192,2.165),(.09,-.177,2.15),(.165,-.115,2.13),(.19,-.01,2.105)],.074,"cloak","head")
        builder.ellipsoid((-.112,-.190,2.164),(.032,.012,.026),"trim","head",14,9)
        for dx,dz in [(-.015,.014),(.015,.014),(-.015,-.014),(.015,-.014)]:
            builder.ellipsoid((-.112+dx,-.204,2.164+dz),(.010,.007,.013),"trim","head",10,7)
        builder.tube([(-.112,-.204,2.149),(-.112,-.207,2.139)],[(.004,.003)]*2,"trim","head",6)
    elif hero=="yuno":
        # Yuno's hair lies flatter and sweeps to the side; only a few lifted locks.
        for i in range(8):
            x=-.14+i*.04
            side=1 if i<4 else -1
            builder.tube([(x,-.10,2.17),(x+.035,-.16,2.22),(x+.085*side,-.11,2.32+.025*(i%3)),(x+.14*side,.02,2.38+.018*(i%2))],[(.060,.050),(.055,.046),(.034,.028),(.001,.001)],"hair","head",9)
        for i in range(4):
            x=-.12+i*.08
            builder.tube([(x,-.13,2.18),(x-.01,-.19,2.12),(x+.018,-.20,2.03+.012*(i%2))],[(.040,.031),(.033,.025),(.002,.002)],"hair","head",8)
        # A narrow side part separates the swept fringe.
        builder.tube([(.012,-.177,2.19),(.044,-.17,2.27),(.09,-.115,2.34)],[(.008,.006),(.009,.006),(.002,.002)],"accent","head",6)
        builder.tube([(.16,-.10,2.17),(.08,-.17,2.10),(-.015,-.19,2.105),(-.11,-.15,2.15)],[(.052,.039),(.048,.034),(.034,.024),(.002,.002)],"hair","head",9)
    elif hero=="magna":
        # Magna's lavender quiff, dark central crest, and swept side locks.
        for i in range(9):
            x=-.14+i*.035
            builder.tube([(x,.015,2.19),(x-.018,.03,2.30),(x+.02,.04,2.47+.035*math.sin(i*1.8))],[(.065,.055),(.048,.04),(.001,.001)],"hair","head",9)
        for i in range(3):
            x=-.075+i*.075
            builder.tube([(x,-.015,2.23),(x*.75,-.045,2.36),(x*.45,-.05,2.47+.015*(i%2))],[(.050,.045),(.038,.030),(.001,.001)],"cloth","head",8)
        for side in (-1,1):
            for i in range(3):
                x=side*(.10+i*.025)
                builder.tube([(x,.015,2.15),(x*1.16,.02,2.20),(x*1.28,.04,2.28)],[(.047,.042),(.036,.032),(.002,.002)],"hair","head",8)
        builder.ribbon([(-.18,-.04,2.14),(-.10,-.15,2.17),(0,-.19,2.18),(.10,-.15,2.17),(.18,-.04,2.14)],.055,"cloth","head")
    elif hero=="vanessa":
        # Shoulder-length, separated waves; no witch hat in this character's
        # standard Black Bulls outfit.
        for side in (-1,1):
            for strand in range(3):
                x=side*(.08+.055*strand)
                sway=side*(.025 if strand%2 else -.025)
                builder.tube([(x,.015,2.18),(x+side*.07,-.01,2.05),(x+sway,.025,1.94),(x+side*.06,.015,1.82),(x+sway,.0,1.72)],[(.064,.052),(.067,.054),(.060,.050),(.048,.040),(.006,.005)],"hair","head",9)
        for i in range(7):
            x=-.16+i*.052
            builder.tube([(x,-.12,2.20),(x-.018,-.18,2.10),(x+.02,-.19,2.045)],[(.047,.037),(.033,.026),(.003,.003)],"hair","head",8)
        builder.ellipsoid((0,.08,2.14),(.19,.16,.08),"hair","head",18,10)
    else:
        for side in (-1,1):
            x=side*.14
            builder.tube([(x,.02,2.18),(side*.22,.10,1.94),(side*.31,.08,1.64),(side*.37,.06,1.38)],[(.085,.075),(.068,.055),(.047,.04),(.004,.004)],"hair","head",9)
        for i in range(5):
            x=-.14+i*.07
            builder.tube([(x,-.14,2.20),(x-.01,-.20,2.10),(x-.02,-.195,2.055)],[(.040,.031),(.028,.022),(.002,.002)],"hair","head",8)
    if hero=="noelle":
        for side in (-1,1):
            builder.tube([(side*.13,.045,2.17),(side*.23,.12,2.10),(side*.29,.17,1.94),(side*.34,.17,1.73),(side*.37,.12,1.55),(side*.39,.08,1.36)],[(.075,.060),(.070,.055),(.060,.046),(.052,.040),(.040,.030),(.003,.003)],"hair","head",10)
            # Her side bows are modeled as crossed fabric loops, not hair bumps.
            builder.ribbon([(side*.15,-.03,2.07),(side*.27,-.04,2.15),(side*.36,-.035,2.09),(side*.25,-.02,2.03)],.045,"accent","head")
            builder.ribbon([(side*.16,-.025,2.08),(side*.27,-.045,2.00),(side*.36,-.035,2.07),(side*.25,-.02,2.12)],.038,"accent","head")
    # Ears, brows, eyes, irises, mouth and nose; all are actual curved surfaces.
    builder.ellipsoid((-.198,0,1.985),(.040,.045,.072),"skin","head",12,8)
    builder.ellipsoid((.198,0,1.985),(.040,.045,.072),"skin","head",12,8)
    for side,x in enumerate((-.078,.078)):
        eye_z=2.005
        eye_width=.116 if hero=="asta" else .12
        eye_height=.060 if hero=="asta" else .070
        builder.almond_eye(x,-.181,eye_z,"white","head",eye_width,eye_height)
        # Iris and pupil sit within the eye surface, not as protruding eyeballs.
        builder.ellipsoid((x+(-.004 if x<0 else .004),-.195,eye_z),(.023,.010,.029),"eyes","head",14,10)
        builder.ellipsoid((x+(-.004 if x<0 else .004),-.203,eye_z),(.010,.006,.020),"cloth","head",10,8)
        builder.ellipsoid((x-.001,-.208,eye_z+.009),(.004,.004,.006),"white","head",8,6)
        brow_y=-.185
        brow_z=2.071+(0.005 if side==0 else 0)
        if hero=="asta":
            inner_x=x+(.035 if x<0 else -.035)
            builder.tube([(x-.045,brow_y,brow_z-.012),(inner_x,brow_y-.014,brow_z+.018),(x+.043,brow_y,brow_z+.004)],[(.012,.008),(.015,.009),(.008,.006)],"hair","head",7)
        else:
            builder.tube([(x-.047,brow_y,brow_z-.004),(x,brow_y-.012,brow_z+.008),(x+.042,brow_y,brow_z)],[(.011,.008),(.013,.008),(.008,.006)],"hair","head",7)
    builder.tube([(-.035,-.195,1.935),(0,-.205,1.927),(.035,-.195,1.936)],[(.006,.005),(.005,.004),(.004,.003)],"accent","head",6)
    builder.tube([(0,-.179,2.02),(0,-.191,1.979),(0,-.204,1.958)],[(.009,.008),(.012,.009),(.016,.010)],"skin","head",8)
    # Character-specific identity marks and headwear.
    if hero=="magna":
        # His blue-lensed sunglasses cover the eyes as in the official design.
        for side in (-1,1):
            builder.ellipsoid((side*.076,-.176,2.005),(.074,.026,.049),"metal","head",18,12)
            builder.ellipsoid((side*.076,-.200,2.005),(.056,.014,.034),"accent","head",18,12)
        builder.tube([(-.08,-.205,2.005),(0,-.216,2.012),(.08,-.205,2.005)],[(.012,.009)]*3,"metal","head",7)
        # A small dark goatee under his broad grin.
        builder.tube([(-.055,-.171,1.84),(0,-.195,1.805),(.055,-.171,1.84)],[(.018,.013),(.027,.016),(.018,.013)],"cloth","head",8)
    elif hero=="noelle":
        builder.tube([(-.16,-.04,2.22),(-.10,-.16,2.28),(0,-.19,2.30),(.10,-.16,2.28),(.16,-.04,2.22)],[(.028,.018)]*5,"metal","head",8)
        builder.ellipsoid((0,-.198,2.29),(.035,.022,.045),"trim","head",12,8)
    elif hero=="yuno":
        builder.tube([(-.16,-.03,2.18),(-.08,-.16,2.20),(0,-.19,2.21),(.10,-.16,2.20),(.16,-.03,2.18)],[(.018,.014)]*5,"trim","head",8)

def make_blade(builder,mat,base,tip,half_width,thickness,bone):
    # Extruded, ridge-backed blade mesh, with actual bevel geometry.
    b=Vector(base);t=Vector(tip);axis=t-b
    side=Vector((axis.z,0,-axis.x)).normalized()*half_width
    ridge=(b+t)*0.5+Vector((0,-thickness,0))
    verts=[tuple(b-side),tuple(b+side),tuple(t),tuple(ridge),
           tuple(b-side+Vector((0,thickness,0))),tuple(b+side+Vector((0,thickness,0))),tuple(t+Vector((0,thickness,0)))]
    faces=[(0,1,3),(1,2,3),(2,0,3),(4,6,5),(4,5,0),(5,1,0),(5,6,1),(6,2,1),(4,0,2),(4,2,6)]
    builder.add(verts,faces,mat,bone)

def make_demon_sword(builder,mat,base,tip,half_width,thickness,bone):
    # Broad, almost rectangular anti-magic blade with a clipped point and a
    # raised central ridge; avoids the crude single triangular wedge silhouette.
    b=Vector(base);t=Vector(tip);axis=t-b;perp=Vector((axis.z,0,-axis.x)).normalized()
    profile=[(0.0,.52),(.08,.84),(.72,1.0),(.91,.84),(1.0,0.0)]
    front=[];back=[];faces=[];n=len(profile)
    for frac,width in profile:
        center=b+axis*frac
        half=half_width*width
        left=center-perp*half;right=center+perp*half
        # Three columns create bevels and a raised ridge along the blade face.
        front.extend([tuple(left+Vector((0,-thickness*.20,0))),
                      tuple(center+Vector((0,-thickness,0))),
                      tuple(right+Vector((0,-thickness*.20,0)))])
        back.extend([tuple(left+Vector((0,thickness*.55,0))),
                     tuple(center+Vector((0,thickness*.55,0))),
                     tuple(right+Vector((0,thickness*.55,0)))])
    verts=front+back;offset=len(front)
    for row in range(n-1):
        for col in range(2):
            a=row*3+col;b0=a+1;d=a+3;c=d+1
            faces.append((a,b0,c,d))
            faces.append((offset+a,offset+d,offset+c,offset+b0))
        # Side walls seal the forged blade profile.
        faces.append((row*3,offset+row*3,offset+(row+1)*3,(row+1)*3))
        faces.append((row*3+2,(row+1)*3+2,offset+(row+1)*3+2,offset+row*3+2))
    faces.extend([(0,2,offset+2,offset),(3*(n-1),offset+3*(n-1),offset+3*(n-1)+2,3*(n-1)+2)])
    builder.add(verts,faces,mat,bone)
    for side in (-1,1):
        p0=b+axis*.10+perp*(side*half_width*.68)+Vector((0,-thickness*.26,0))
        p1=b+axis*.84+perp*(side*half_width*.68)+Vector((0,-thickness*.26,0))
        p2=b+axis*.97+perp*(side*half_width*.12)+Vector((0,-thickness*.26,0))
        builder.tube([tuple(p0),tuple(p1),tuple(p2)],[(.012,.008),(.009,.006),(.001,.001)],"accent",bone,6)

def add_character_gear(builder,hero,mats,level):
    # Weapons, spell focus and signature ornaments are built from closed meshes.
    trim,metal,glow=mats["trim"],mats["metal"],mats["glow"]
    if hero=="asta":
        # Keep the signature anti-magic sword at Asta's side so it reads as
        # equipment without obscuring his face, mantle and uniform silhouette.
        sword_base=(.49,-.14,1.02);sword_tip=(.72,-.12,.12)
        make_demon_sword(builder,metal,sword_base,sword_tip,.105,.036,"hand.R")
        # Crossguard and wrapped grip are separate solid geometry, firmly seated in the hand.
        builder.tube([(.39,-.15,1.09),(.49,-.17,1.02),(.58,-.15,.96)],[(.026,.019)]*3,"trim","hand.R",9)
        builder.tube([(.45,-.13,1.07),(.39,-.11,1.15),(.34,-.10,1.20)],[(.030,.027),(.028,.025),(.024,.022)],"cloth","hand.R",9)
        for i in range(4):
            t=i*.018
            builder.tube([(.44+t,-.16,1.085+t),(.40+t,-.145,1.13+t)],[(.007,.005)]*2,"trim","hand.R",6)
        if level>=3:
            for side in (-1,1):
                builder.tube([(.34,-.19,1.02),(.20,-.23,.90),(.03,-.22,.78)],[(.018,.012),(.024,.014),(.002,.002)],"glow","hand.R",7)
    elif hero=="yuno":
        # A grimoire: beveled book cover, pages, spine and clover insignia.
        builder.box((-.48,-.10,1.39),(.34,.105,.42),"accent","hand.L")
        builder.box((-.48,-.158,1.39),(.295,.028,.375),"white","hand.L")
        builder.box((-.48,-.178,1.39),(.32,.018,.40),"cloak","hand.L")
        builder.tube([(-.48,-.193,1.56),(-.48,-.199,1.39),(-.48,-.193,1.22)],[(.012,.009)]*3,"trim","hand.L",7)
        builder.ellipsoid((-.48,-.202,1.39),(.035,.010,.042),"glow","hand.L",12,8)
        if level>=4:
            builder.tube([(-.51,-.22,1.42),(-.48,-.235,1.47),(-.45,-.22,1.42)],[(.009,.008)]*3,"trim","hand.L",6)
    elif hero=="magna":
        for k in range(3):
            z=.99+k*.035
            builder.tube([(.41,-.13,z),(.54,-.17,z+.05),(.65,-.17,z+.11)],[(.095,.07),(.072,.05),(.006,.005)],"glow","hand.R",9)
        if level>=2:
            builder.tube([(.35,-.16,1.05),(.39,-.22,1.18),(.48,-.18,1.23)],[(.04,.04),(.055,.04),(.003,.003)],"glow","hand.R",8)
        builder.tube([(-.15,-.225,2.022),(0,-.235,2.026),(.15,-.225,2.022)],[(.010,.008),(.012,.008),(.010,.008)],"metal","head",7)
    elif hero=="vanessa":
        for i in range(3):
            builder.tube([(.37,-.17,1.04),(.50,-.19,1.18+i*.04),(.67,-.13,1.30+i*.03)],[(.011,.008),(.008,.006),(.003,.002)],"glow","hand.R",6)
        builder.ellipsoid((.38,-.18,1.05),(.065,.055,.07),"trim","hand.R",12,8)
    else:
        builder.tube([(.42,-.18,.96),(.50,-.19,1.18),(.53,-.18,1.53)],[(.035,.032),(.025,.025),(.012,.012)],"metal","hand.R",10)
        builder.ellipsoid((.53,-.19,1.59),(.09,.08,.09),"glow","hand.R",16,10)
        for i in range(5):
            a=TAU*i/5
            builder.tube([(.53,-.19,1.59),(.53+.16*math.cos(a),-.19+.05*math.sin(a),1.59+.16*math.sin(a))],[(.018,.014),(.002,.002)],"white","hand.R",7)
    # Upgrade details: fitted shoulder guards, cuffs, extra trim, and visible insignia.
    if level>=2:
        for side in (-1,1):
            builder.ellipsoid((side*.34,-.015,1.64),(.17,.16,.10),"trim","chest",16,10)
            builder.ellipsoid((side*.34,-.10,1.65),(.11,.055,.065),"accent","chest",14,8)
    if level>=3:
        builder.loft([(0,0,.91,.31,.20),(0,0,1.00,.39,.24),(0,0,1.08,.34,.22)],"trim","spine",20)
        builder.ellipsoid((0,-.252,1.48),(.07,.018,.08),"glow","chest",14,8)
    if level>=4:
        for side in (-1,1):
            builder.tube([(side*.32,.12,1.70),(side*.43,.15,1.51),(side*.42,.18,1.30)],[(.055,.05),(.045,.035),(.025,.018)],"accent","cape",9)
    if level>=5:
        builder.ellipsoid((0,.20,1.73),(.26,.09,.20),"cloak","cape",18,10)
        for side in (-1,1):
            builder.tube([(side*.08,.24,1.80),(side*.20,.26,1.98),(side*.35,.22,2.10)],[(.05,.04),(.035,.026),(.002,.002)],"glow","cape",8)

def build_body(hero,level,mats,armature):
    bones=list(armature.data.bones.keys())
    b=MeshBuild(mats,bones)
    # Leg anatomy and fitted trousers, with knees and boots following separate bones.
    leg_mat="pants"
    shin_mat="pants"
    for side,suffix in [(-1,"L"),(1,"R")]:
        x=side*.145
        b.tube([(x,0,.99),(x,0,.77),(x+side*.025,0,.54)],[(.120,.12),(.108,.10),(.086,.083)],leg_mat,"thigh."+suffix,14,"shin."+suffix,0.68)
        b.tube([(x+side*.025,0,.56),(x+side*.025,0,.32),(x+side*.015,-.01,.13)],[(.082,.078),(.072,.069),(.066,.064)],shin_mat,"shin."+suffix,14,"foot."+suffix,0.70)
        b.ellipsoid((x,-.05,.11),(.125,.20,.085),"boots","foot."+suffix,18,12)
        b.ellipsoid((x,-.14,.10),(.135,.145,.066),"boots","foot."+suffix,18,12)
        b.tube([(x,-.18,.15),(x,-.18,.22),(x,-.17,.30)],[(.087,.062),(.080,.06),(.058,.044)],"trim","foot."+suffix,12)
        if hero=="asta":
            b.tube([(x,0,.16),(x,-.005,.31),(x,-.005,.48)],[(.105,.105),(.105,.102),(.092,.088)],"boots","shin."+suffix,14)
            b.tube([(x,-.092,.29),(x,-.105,.32),(x,-.096,.36)],[(.008,.006)]*3,"trim","shin."+suffix,7)
    # Core body; torso silhouette is a custom tapered garment shell, not stacked balls.
    b.loft([(0,0,.83,.22,.14),(0,0,.96,.26,.16),(0,0,1.10,.25,.15),(0,0,1.32,.24,.14),(0,0,1.54,.28,.16),(0,0,1.72,.20,.13)],"skin","spine",28,("hips","chest",1.22))
    if hero=="asta":
        # Asta's sleeveless white shirt leaves the upper arms bare.
        b.loft([(0,.005,.91,.29,.17),(0,.005,1.00,.33,.19),(0,0,1.18,.29,.17),(0,0,1.45,.30,.18),(0,0,1.62,.32,.18),(0,0,1.70,.23,.15)],"white","spine",28,("hips","chest",1.23))
        b.ribbon([(-.10,-.187,1.69),(0,-.202,1.60),(.10,-.187,1.69)],.022,"trim","chest")
    elif hero=="vanessa":
        # Open midriff and separate wine-red bodice geometry.
        b.loft([(0,.005,1.22,.27,.17),(0,.005,1.30,.31,.18),(0,0,1.38,.32,.19)],"accent","spine",26,("hips","chest",1.23))
        for side in (-1,1):
            b.ellipsoid((side*.135,-.168,1.49),(.125,.072,.105),"cloth","chest",20,12)
            b.tube([(side*.045,-.225,1.57),(side*.105,-.226,1.60),(side*.18,-.195,1.57)],[(.014,.010)]*3,"trim","chest",7)
    else:
        torso_material="white" if hero=="noelle" else "cloth"
        b.loft([(0,.005,.82,.30,.18),(0,.005,.93,.34,.20),(0,0,1.08,.31,.19),(0,0,1.40,.30,.18),(0,0,1.62,.34,.20),(0,0,1.75,.24,.16)],torso_material,"spine",28,("hips","chest",1.23))
    if hero=="vanessa":
        # Short skirt panels and her asymmetric hanging sash.
        b.loft([(0,.025,.72,.30,.20),(0,.025,.79,.35,.22),(0,.02,.87,.34,.22)],"accent","hips",32)
        b.panel(5,7,lambda u,v:(-.27-.11*u+.05*math.sin(v*math.pi),-.20-.02*math.sin(v*math.pi),.92-.36*u),"pants","hips")
        b.panel(5,7,lambda u,v:(.25+.10*u-.04*math.sin(v*math.pi),-.19-.02*math.sin(v*math.pi),.91-.32*u),"accent","hips")
    elif hero=="noelle":
        b.loft([(0,.025,.72,.27,.20),(0,.025,.78,.34,.22),(0,.02,.89,.36,.22),(0,.02,.95,.30,.19)],"cloak","hips",32)
        # Twelve modeled pleat ridges break the skirt into readable fabric panels.
        for i in range(12):
            a=TAU*i/12
            x=.32*math.cos(a);y=.025+.20*math.sin(a)
            b.tube([(x*.82,y*.82,.94),(x,y,.82),(x*1.03,y*1.03,.75)],[(.008,.006),(.012,.008),(.004,.003)],"trim","hips",6)
    elif hero!="asta":
        b.loft([(0,.02,.70,.31,.20),(0,.02,.77,.34,.21),(0,.02,.87,.31,.19)],"cloak","hips",28)
    if hero!="asta":
        b.tube([(-.30,-.17,.82),(-.20,-.21,.79),(0,-.225,.78),(.20,-.21,.79),(.30,-.17,.82)],[(.016,.011)]*5,"trim","hips",8)
    # Neck and sculpted face/head.
    b.tube([(0,0,1.68),(0,0,1.81),(0,0,1.89)],[(.09,.085),(.08,.08),(.075,.07)],"skin","neck",12)
    # Tapered cheek and jaw profile. This replaces the round toy-like head with
    # a sculpted, faceted anime face that has a readable chin and brow line.
    b.loft([(0,-.005,1.755,.085,.095),(0,-.018,1.80,.128,.128),
            (0,-.025,1.88,.158,.151),(0,-.018,1.98,.175,.158),
            (0,-.006,2.075,.161,.145),(0,.006,2.145,.105,.108)],"skin","head",28)
    # Shoulder line, shaped sleeves, forearms, wrist guards and articulated hands.
    for side,suffix in [(-1,"L"),(1,"R")]:
        shoulder="shoulder."+suffix;upper="upper_arm."+suffix;fore="forearm."+suffix;hand="hand."+suffix
        sleeve_mat="cloth" if hero=="asta" else "accent" if hero=="vanessa" else "white" if hero=="noelle" else "cloth"
        b.tube([(side*.33,0,1.62),(side*.40,0,1.43),(side*.40,-.005,1.29)],[(.125,.12),(.112,.105),(.09,.085)],sleeve_mat,shoulder,14,upper,.36)
        b.tube([(side*.40,-.005,1.31),(side*.41,-.015,1.16),(side*.41,-.025,1.02)],[(.095,.088),(.083,.078),(.066,.063)],"skin",upper,14,fore,.50)
        forearm_mat="skin" if hero=="asta" else "accent" if hero=="vanessa" else "white" if hero=="noelle" else "cloth"
        b.tube([(side*.41,-.02,1.17),(side*.42,-.025,1.10),(side*.42,-.03,1.03)],[(.089,.082),(.078,.072),(.064,.06)],forearm_mat,fore,14)
        b.tube([(side*.42,-.03,1.04),(side*.43,-.04,.97),(side*.44,-.06,.91)],[(.064,.06),(.061,.057),(.050,.047)],"skin",hand,12)
        hand_material="skin"
        b.ellipsoid((side*.43,-.055,.94),(.068,.058,.064),hand_material,hand,16,10)
        for finger in range(4):
            fx=side*.43+side*(finger-1.5)*.026
            b.tube([(fx,-.06,.93),(fx,-.09,.89),(fx,-.11,.86)],[(.018,.016),(.014,.013),(.008,.008)],hand_material,hand,7)
        b.tube([(side*.36,-.02,1.08),(side*.42,-.04,1.06),(side*.48,-.02,1.09)],[(.071,.050)]*3,"trim",fore,10)
        if hero=="asta":
            # Short blue-gray sleeves and white rolled cuffs follow the supplied
            # full-body model. Anti-magic markings unlock on the fourth tier.
            b.loft([(side*.400,-.010,1.285,.090,.082),(side*.400,-.010,1.315,.098,.088),(side*.395,-.006,1.365,.101,.090)],"white",upper,32)
            if level>=4 and suffix=="L":
                b.tube([(-.41,-.04,1.17),(-.42,-.045,1.10),(-.42,-.05,1.03)],[(.092,.084),(.080,.074),(.065,.061)],"cloak",fore,12)
                b.ellipsoid((-.43,-.068,.94),(.073,.061,.067),"cloak",hand,14,10)
                b.tube([(-.43,-.111,1.22),(-.37,-.115,1.15),(-.44,-.109,1.08),(-.40,-.104,1.02)],[(.014,.009)]*4,"glow",fore,7)
        elif hero=="noelle":
            b.ellipsoid((side*.34,-.005,1.58),(.19,.18,.15),"white","shoulder."+suffix,20,12)
            b.tube([(side*.37,-.02,1.49),(side*.42,-.035,1.42),(side*.43,-.045,1.36)],[(.012,.009)]*3,"trim",upper,7)

    # Front mantle panels drape across the shoulders as cloth surfaces.
    if hero=="asta":
        def asta_mantle_point(u,v):
            across=2.0*v-1.0
            half_width=.22+.16*u
            return (across*half_width,-.22-.055*(1.0-abs(across)),1.72-.42*u+.035*abs(across))
        b.panel(10,18,asta_mantle_point,"cloak","chest")
        for side in (-1,1):
            b.tube([(side*.21,-.22,1.72),(side*.28,-.245,1.57),(side*.34,-.245,1.43),(side*.38,-.22,1.33)],[(.010,.008),(.011,.008),(.011,.008),(.010,.008)],"trim","chest",7)
        hem=[asta_mantle_point(1.0,i/12.0) for i in range(13)]
        b.tube(hem,[(.010,.008)]*len(hem),"trim","chest",7)
    else:
        for side in (-1,1):
            panel_drop=.42 if hero=="vanessa" else .28
            b.panel(5,6,lambda u,v,s=side,d=panel_drop:(s*(.015+.35*v),-.255-0.012*math.sin(v*math.pi),1.73-d*u-.035*math.sin(v*math.pi)),"cloak","chest")
            b.tube([(side*.025,-.271,1.70),(side*.18,-.276,1.62),(side*.34,-.266,1.49)],[(.014,.010)]*3,"trim","chest",7)
    # Chest insignia, belt, buckle, and cape panel flowing behind the figure.
    if hero!="asta":
        b.ellipsoid((0,-.255,1.45),(.045,.013,.052),"trim","chest",14,10)
        for px,pz in [(-.028,1.46),(.028,1.46),(-.028,1.42),(.028,1.42)]: b.ellipsoid((px,-.268,pz),(.022,.009,.022),"accent","chest",12,8)
    if hero=="asta":
        # Broad leather utility belt, brass buckle and individual pouches.
        b.loft([(0,.01,.91,.37,.24),(0,.01,.97,.40,.25),(0,.01,1.04,.36,.23)],"leather","spine",24)
        b.box((0,-.258,.99),(.19,.046,.13),"metal","spine")
        b.box((0,-.287,.99),(.115,.018,.072),"leather","spine")
        b.tube([(-.09,-.294,.99),(0,-.300,.99),(.09,-.294,.99)],[(.008,.005)]*3,"trim","spine",6)
        b.box((.27,-.235,.99),(.11,.068,.14),"leather","spine")
        b.ellipsoid((.27,-.278,.99),(.018,.008,.018),"metal","spine",10,7)
        b.ellipsoid((-.205,-.281,1.52),(.036,.012,.042),"metal","chest",14,9)
        for dx,dz in [(-.014,.012),(.014,.012),(-.014,-.012),(.014,-.012)]:
            b.ellipsoid((-.205+dx,-.296,1.52+dz),(.009,.006,.012),"trim","chest",10,7)
        b.tube([(-.23,-.24,1.67),(-.12,-.285,1.60),(0,-.292,1.56)],[(.018,.012),(.016,.011),(.014,.010)],"trim","chest",7)
    elif hero=="magna":
        # Pale waist sash and layered inner vest echo his standard outfit.
        b.loft([(0,.01,.94,.36,.24),(0,.01,.99,.38,.25),(0,.01,1.04,.35,.23)],"white","spine",24)
        b.ellipsoid((0,-.255,1.00),(.075,.025,.06),"metal","spine",12,8)
        b.ribbon([(-.12,-.205,1.62),(0,-.224,1.48),(.12,-.205,1.34)],.028,"white","chest")
    else:
        b.loft([(0,.01,.94,.36,.24),(0,.01,.99,.37,.245),(0,.01,1.04,.34,.23)],"metal","spine",24)
        b.ellipsoid((0,-.246,1.00),(.075,.025,.06),"trim","spine",12,8)
    if hero=="asta":
        # A short, split cape with a gold hem mirrors the layered silhouette in
        # the supplied 3D reference, and is actual cloth geometry from behind.
        b.panel(7,10,lambda u,v:(-.36+.72*v,.15+.18*math.sin(v*math.pi)+.035*math.sin(u*math.pi),1.69-.48*u+.055*math.sin(v*TAU)),"cloak","cape")
        for side in (-1,1):
            b.tube([(side*.31,.18,1.66),(side*.36,.23,1.48),(side*.34,.26,1.34),(side*.25,.24,1.21)],[(.014,.010)]*4,"trim","cape",7)
    else:
        cape_drop=.42 if hero=="vanessa" else .86
        b.panel(5,8,lambda u,v,d=cape_drop:(-0.33+0.66*v,0.13+0.22*math.sin(v*math.pi)+0.04*math.sin(u*math.pi),1.67-d*u+0.04*math.sin(v*TAU)),"cloak","cape")
        # Two stitched edge seams follow the actual cape length.
        cape_end=max(1.22,1.67-cape_drop)
        for side in (-1,1):
            b.tube([(side*.31,.15,1.65),(side*.34,.24,1.48),(side*.32,.27,(1.48+cape_end)*.5),(side*.27,.31,cape_end)],[(.012,.009)]*4,"trim","cape",6)
    # Tailored, character-specific construction details make each silhouette
    # and costume unique before the signature weapon/spell gear is attached.
    if hero=="asta":
        b.tube([(-.19,-.18,1.70),(-.11,-.23,1.73),(0,-.25,1.68),(.11,-.23,1.73),(.19,-.18,1.70)],[(.024,.016)]*5,"cloth","chest",8)
        b.ellipsoid((.20,-.274,1.68),(.040,.014,.044),"trim","chest",12,8)
    elif hero=="yuno":
        # Golden Dawn formal coat: double-breasted brass buttons, gold piping,
        # a clover tab and pale fur at the collar.
        for z in (1.22,1.36,1.50,1.62):
            for side in (-1,1):
                b.ellipsoid((side*.105,-.245,z),(.025,.018,.028),"trim","chest",12,8)
        b.ribbon([(-.23,-.268,1.30),(-.16,-.281,1.18),(0,-.287,1.10),(.16,-.281,1.18),(.23,-.268,1.30)],.025,"trim","chest")
        b.ellipsoid((0,-.293,1.37),(.045,.012,.055),"accent","chest",16,10)
        for a in range(4):
            angle=TAU*a/4
            b.ellipsoid((.024*math.cos(angle),-.305,1.37+.030*math.sin(angle)),(.018,.007,.020),"glow","chest",10,7)
        for i in range(9):
            angle=TAU*i/9
            b.ellipsoid((.095*math.cos(angle),.085*math.sin(angle),1.77),(.045,.045,.035),"white","neck",12,8)
    elif hero=="magna":
        # Black Bulls short cape, gray-violet vest and wrapped forearms.
        for side in (-1,1):
            b.ribbon([(side*.39,-.12,1.22),(side*.43,-.12,1.18),(side*.45,-.10,1.14)],.045,"white","forearm."+("L" if side<0 else "R"))
            b.ellipsoid((side*.35,-.04,1.70),(.16,.16,.075),"cloak","chest",16,10)
            b.ellipsoid((side*.35,-.13,1.70),(.11,.045,.05),"trim","chest",12,8)
        b.loft([(0,-.01,1.18,.22,.17),(0,-.01,1.35,.24,.18),(0,-.01,1.56,.22,.17)],"white","chest",20)
    elif hero=="vanessa":
        # Corset panels with visible criss-cross lacing and stitched edges.
        b.tube([(-.18,-.257,1.48),(-.14,-.279,1.28),(0,-.286,1.19),(.14,-.279,1.28),(.18,-.257,1.48)],[(.022,.015)]*5,"accent","chest",8)
        for i in range(4):
            z=1.30+i*.035
            b.tube([(-.075,-.292,z),(.075,-.292,z+.035)],[(.009,.007),(.009,.007)],"trim","chest",6)
        b.ribbon([(-.27,-.22,1.62),(-.17,-.268,1.68),(0,-.285,1.69),(.17,-.268,1.68),(.27,-.22,1.62)],.024,"trim","chest")
    else:
        # Noelle's silver-blue knight trim and fitted waist armor.
        for side in (-1,1):
            b.ellipsoid((side*.33,-.12,1.65),(.14,.09,.09),"metal","chest",16,10)
            b.tube([(side*.30,-.19,1.67),(side*.35,-.19,1.58),(side*.40,-.14,1.53)],[(.016,.011),(.013,.010),(.004,.003)],"trim","chest",7)
        b.ribbon([(-.30,-.22,1.06),(-.17,-.263,1.02),(0,-.282,1.01),(.17,-.263,1.02),(.30,-.22,1.06)],.035,"accent","spine")
        b.ellipsoid((0,-.293,1.04),(.042,.015,.045),"trim","spine",14,9)
    add_head_hair(b,hero,mats,level)
    add_character_gear(b,hero,mats,level)
    # Subtle silhouette-specific proportions: the short, powerful Asta; tall,
    # lean Yuno; and more elegant proportions for the women and Magna.
    width_scale={"asta":1.0,"yuno":.88,"magna":.94,"vanessa":.91,"noelle":.90}[hero]
    height_scale={"asta":.98,"yuno":1.055,"magna":1.0,"vanessa":1.035,"noelle":1.0}[hero]
    b.v=[(x*width_scale,y*width_scale,z*height_scale) for x,y,z in b.v]
    obj=create_mesh_object(hero,level,b,mats,armature)
    return obj

def add_animation_rig(armature,hero):
    animation_data=armature.animation_data_create()
    bones=armature.pose.bones
    for bone in bones: bone.rotation_mode="XYZ"
    clips={
        "Idle":[(1,0.0),(12,1.0),(24,0.0),(36,-1.0),(48,0.0)],
        "Attack":[(1,0.0),(5,0.4),(9,1.0),(13,0.15),(20,0.0)]
    }
    for clip,keys in clips.items():
        action=bpy.data.actions.new(hero+"_"+clip)
        armature.animation_data.action=action
        for frame,amount in keys:
            bpy.context.scene.frame_set(frame)
            animated=("hips","spine","chest","head","shoulder.L","upper_arm.L","forearm.L","hand.L",
                      "shoulder.R","upper_arm.R","forearm.R","hand.R","thigh.L","thigh.R","cape")
            for name in animated:
                p=bones.get(name)
                if not p: continue
                p.rotation_euler=(0,0,0)
            if clip=="Idle":
                bones["spine"].rotation_euler[1]=math.radians(2.4*amount)
                bones["chest"].rotation_euler[1]=math.radians(1.8*amount)
                bones["head"].rotation_euler[1]=math.radians(-2.2*amount)
                bones["shoulder.L"].rotation_euler[1]=math.radians(1.4*amount)
                bones["shoulder.R"].rotation_euler[1]=math.radians(-1.4*amount)
                bones["upper_arm.L"].rotation_euler[1]=math.radians(-2.4*amount)
                bones["upper_arm.R"].rotation_euler[1]=math.radians(2.4*amount)
                bones["cape"].rotation_euler[0]=math.radians(3.5*amount)
                bones["cape"].rotation_euler[1]=math.radians(1.8*amount)
            else:
                # Attacks have a readable anticipation -> strike -> recovery arc,
                # tuned to each mage's held weapon/fighting style.
                motion={
                    "asta":(-54,34,-13,10,19),
                    "yuno":(-25,18,30,-24,13),
                    "magna":(-41,-35,-12,18,21),
                    "vanessa":(-22,17,30,-29,16),
                    "noelle":(-37,25,-15,12,18),
                }
                r_up,r_fore,l_up,l_fore,chest=motion[hero]
                bones["spine"].rotation_euler[1]=math.radians(-7.0*amount)
                bones["chest"].rotation_euler[1]=math.radians(chest*amount)
                bones["head"].rotation_euler[1]=math.radians(-8.0*amount)
                bones["shoulder.R"].rotation_euler[1]=math.radians(r_up*.30*amount)
                bones["upper_arm.R"].rotation_euler[1]=math.radians(r_up*amount)
                bones["forearm.R"].rotation_euler[1]=math.radians(r_fore*amount)
                bones["hand.R"].rotation_euler[1]=math.radians(-11.0*amount)
                bones["shoulder.L"].rotation_euler[1]=math.radians(l_up*.30*amount)
                bones["upper_arm.L"].rotation_euler[1]=math.radians(l_up*amount)
                bones["forearm.L"].rotation_euler[1]=math.radians(l_fore*amount)
                bones["hand.L"].rotation_euler[1]=math.radians(8.0*amount)
                bones["cape"].rotation_euler[0]=math.radians(-10.0*amount)
                bones["cape"].rotation_euler[1]=math.radians(4.0*amount)
            for name in animated:
                if bones.get(name):
                    armature.keyframe_insert(data_path='pose.bones["'+name+'"].rotation_euler',frame=frame,group=name)
        animation_data.action=None
        track=animation_data.nla_tracks.new();track.name=clip
        strip=track.strips.new(clip,keys[0][0],action)
        strip.action_frame_start=keys[0][0];strip.action_frame_end=keys[-1][0]
        track.mute=(clip!="Idle")
    # Restore a neutral pose in the bind state.
    for p in bones: p.rotation_euler=(0,0,0)
    bpy.context.scene.frame_set(1)

def setup_preview(hero,level):
    scene=bpy.context.scene
    scene.render.engine="BLENDER_EEVEE"
    scene.render.resolution_x=900;scene.render.resolution_y=1100;scene.render.resolution_percentage=100
    scene.render.image_settings.file_format="PNG"
    scene.render.film_transparent=True
    scene.render.image_settings.color_mode="RGBA"
    scene.world.color=(0.055,0.065,0.075)
    scene.view_settings.view_transform="AgX"
    # Studio floor and balanced key/fill lights for local visual inspection.
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,0))
    floor=bpy.context.object;floor.name="PreviewFloor"
    floor_mat=bpy.data.materials.new("PreviewGround");floor_mat.diffuse_color=(0.12,0.15,0.14,1);floor.data.materials.append(floor_mat)
    bpy.ops.object.camera_add(location=(2.45,-4.75,2.30))
    camera=bpy.context.object;camera.name="PreviewCamera"
    camera.rotation_euler=(Vector((0,0,1.23))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.lens=58;scene.camera=camera
    for name,location,power,size,color in [
        ("Key",(3.0,-4.0,5.2),780,4.0,(1.0,.82,.68)),
        ("Fill",(-3.2,-2.0,2.8),480,3.5,(.62,.77,1.0)),
        ("Rim",(0.2,3.0,4.0),950,3.0,(.42,.83,.74))]:
        bpy.ops.object.light_add(type="AREA",location=location)
        light=bpy.context.object;light.name=name;light.data.energy=power;light.data.shape="DISK";light.data.size=size;light.data.color=color
        light.rotation_euler=(Vector((0,0,1.25))-light.location).to_track_quat("-Z","Y").to_euler()
    scene.render.filepath=os.path.join(OUT_DIR,hero+"_L"+str(level)+"_preview.png")
    scene.camera.data.dof.use_dof=False

def export_variant(hero,level):
    clear_scene()
    materials=create_materials(hero,level)
    armature=make_rig(hero)
    build_body(hero,level,materials,armature)
    add_animation_rig(armature,hero)
    setup_preview(hero,level)
    path=os.path.join(OUT_DIR,hero+"_L"+str(level)+".glb")
    bpy.ops.object.select_all(action="DESELECT")
    armature.select_set(True);bpy.context.view_layer.objects.active=armature
    for obj in bpy.context.scene.objects:
        if obj.type=="MESH" and obj.name.startswith(hero+"_L"): obj.select_set(True)
    bpy.ops.export_scene.gltf(filepath=path,export_format="GLB",use_selection=True,export_apply=True,export_animations=True,export_lights=False,export_cameras=False,export_nla_strips=True,export_skins=True,export_materials="EXPORT",export_image_format="AUTO")
    bpy.context.scene.render.filepath=os.path.join(OUT_DIR,hero+"_L"+str(level)+"_preview.png")
    preview_levels=os.environ.get("CADY_PREVIEW_LEVELS","").strip()
    if os.environ.get("CADY_RENDER_PREVIEWS","0")=="1" and (not preview_levels or str(level) in preview_levels.split(",")):
        bpy.ops.render.render(write_still=True)
    print("BUILT",path,os.path.getsize(path))

def main():
    scene=bpy.context.scene
    scene.unit_settings.system="METRIC"
    scene.render.fps=30
    # First iteration: one complete asset and all five visual upgrade tiers for each tower.
    heroes=os.environ.get("CADY_HEROES","asta,yuno,magna,vanessa,noelle").split(",")
    levels=[int(x) for x in os.environ.get("CADY_LEVELS","1,2,3,4,5").split(",")]
    for hero in heroes:
        for level in levels:
            export_variant(hero,level)
    print("ALL_TOWER_MODELS_BUILT")

if __name__=="__main__":
    main()
