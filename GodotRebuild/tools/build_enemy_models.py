"""Build the game's enemy actors as skinned, animated GLB meshes with Blender."""
import bpy
import importlib.util
import math
import os
import sys
from mathutils import Vector, Matrix

ROOT = r"G:\Cady\GodotRebuild"
sys.path.insert(0,os.path.join(ROOT,"tools"))
from pack_character_materials import pack_character_materials
OUT_DIR = os.path.join(ROOT, "Assets", "Enemies")
TEXTURE_DIR = os.path.join(OUT_DIR, "Textures")
os.makedirs(TEXTURE_DIR, exist_ok=True)

spec = importlib.util.spec_from_file_location("tower_mesh_builder", os.path.join(ROOT, "tools", "build_tower_models.py"))
meshlib = importlib.util.module_from_spec(spec)
spec.loader.exec_module(meshlib)
meshlib.TEXTURE_DIR = TEXTURE_DIR

TAU = math.tau
PALETTES = {
    "goblin": {"skin":(.28,.43,.19,1),"hair":(.12,.12,.09,1),"cloth":(.20,.17,.12,1),"cloak":(.27,.25,.15,1),"trim":(.46,.34,.18,1),"metal":(.27,.29,.25,1),"accent":(.45,.12,.08,1),"glow":(.46,.72,.18,1),"eyes":(.77,.56,.12,1),"white":(.72,.68,.52,1),"pants":(.17,.16,.12,1)},
    "orc": {"skin":(.31,.39,.24,1),"hair":(.12,.10,.08,1),"cloth":(.17,.14,.12,1),"cloak":(.25,.20,.15,1),"trim":(.47,.30,.16,1),"metal":(.24,.27,.25,1),"accent":(.39,.08,.06,1),"glow":(.55,.25,.08,1),"eyes":(.79,.33,.11,1),"white":(.72,.68,.55,1),"pants":(.16,.14,.12,1)},
    "uruk": {"skin":(.34,.27,.22,1),"hair":(.08,.07,.06,1),"cloth":(.12,.12,.12,1),"cloak":(.19,.12,.10,1),"trim":(.52,.43,.28,1),"metal":(.26,.29,.30,1),"accent":(.61,.10,.06,1),"glow":(.85,.19,.06,1),"eyes":(.89,.37,.13,1),"white":(.78,.72,.61,1),"pants":(.13,.12,.11,1)},
    "troll": {"skin":(.39,.41,.37,1),"hair":(.15,.13,.11,1),"cloth":(.23,.20,.16,1),"cloak":(.28,.25,.20,1),"trim":(.50,.39,.23,1),"metal":(.25,.28,.27,1),"accent":(.36,.10,.06,1),"glow":(.55,.33,.12,1),"eyes":(.82,.45,.18,1),"white":(.77,.73,.63,1),"pants":(.19,.16,.14,1)},
    "nazgul": {"skin":(.10,.11,.14,1),"hair":(.05,.06,.09,1),"cloth":(.07,.08,.12,1),"cloak":(.10,.12,.18,1),"trim":(.30,.29,.27,1),"metal":(.18,.20,.25,1),"accent":(.25,.06,.08,1),"glow" :(.92,.08,.025,1),"eyes":(.98,.19,.035,1),"white":(.56,.55,.50,1),"pants":(.07,.08,.10,1)},
    "warg": {"skin":(.24,.25,.22,1),"hair":(.12,.10,.08,1),"cloth":(.24,.20,.16,1),"cloak":(.29,.23,.16,1),"trim":(.47,.35,.19,1),"metal":(.24,.26,.25,1),"accent":(.47,.09,.06,1),"glow":(.79,.32,.06,1),"eyes":(.91,.37,.08,1),"white":(.78,.75,.65,1),"pants":(.17,.15,.13,1)}
}
SCALE = {"goblin":.80,"orc":1.0,"uruk":1.03,"troll":1.55,"nazgul":1.08,"warg":1.0}
# The GLB cycle moves a planted foot backwards by STRIDE * contact_fraction.
# Runtime must scale playback by movement_speed / (stride / cycle_seconds),
# including the model's world scale. These values are exported as node extras.
RUN_CYCLE_SECONDS = 20.0 / 30.0
RUN_CONTACT = .38
RUN_FOOT_TRAVEL = .78
RUN_STRIDE = RUN_FOOT_TRAVEL / RUN_CONTACT


def make_enemy_rig(kind):
    """Own rest skeleton, independent of future hero generator revisions."""
    data = bpy.data.armatures.new(kind + "_Skeleton")
    rig = bpy.data.objects.new(kind + "_Armature", data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active = rig
    rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    definitions = [
        ("root",(0,0,0),(0,0,.88),None),
        ("hips",(0,0,.88),(0,0,1.12),"root"),
        ("spine",(0,0,1.12),(0,0,1.49),"hips"),
        ("chest",(0,0,1.49),(0,0,1.73),"spine"),
        ("neck",(0,0,1.73),(0,0,1.84),"chest"),
        ("head",(0,0,1.84),(0,0,2.20),"neck"),
        ("cape",(0,.16,1.64),(0,.34,.82),"chest"),
    ]
    for side, suffix in [(-1,"L"),(1,"R")]:
        x = side * .18
        definitions.extend([
            ("shoulder."+suffix,(side*.28,0,1.65),(side*.39,0,1.59),"chest"),
            ("upper_arm."+suffix,(side*.39,0,1.59),(side*.40,0,1.31),"shoulder."+suffix),
            ("forearm."+suffix,(side*.40,0,1.31),(side*.42,0,1.05),"upper_arm."+suffix),
            ("hand."+suffix,(side*.42,0,1.05),(side*.44,-.02,.94),"forearm."+suffix),
            ("thigh."+suffix,(x,0,.94),(x,0,.55),"hips"),
            ("shin."+suffix,(x,0,.55),(x,0,.16),"thigh."+suffix),
            ("foot."+suffix,(x,0,.16),(x,-.20,.08),"shin."+suffix),
        ])
    for name,head,tail,parent in definitions:
        if kind=="troll":
            factor=1.30 if any(part in name for part in ("shoulder.","upper_arm.","forearm.","hand.")) else 1.28 if any(part in name for part in ("thigh.","shin.","foot.")) else 1.0
            head=(head[0]*factor,head[1],head[2]);tail=(tail[0]*factor,tail[1],tail[2])
        bone=data.edit_bones.new(name);bone.head=head;bone.tail=tail
        if parent: bone.parent=data.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.select_set(False)
    return rig


def materials_for(kind):
    mats = {}
    for index, (name, color) in enumerate(PALETTES[kind].items()):
        seed = (sum(ord(ch) for ch in kind) * 997 + index * 7919) % 1000000
        mats[name] = meshlib.make_material("enemy_" + kind + "_" + name, color, seed, name)
        if name == "metal":
            principled=mats[name].node_tree.nodes.get("Principled BSDF")
            if principled:
                principled.inputs["Roughness"].default_value=.68
                principled.inputs["Metallic"].default_value=.48
    return mats


def armor_shell(b, center, radii, material, bone):
    """Hammered shoulder/knee shell with an asymmetric rim, not a sphere."""
    cx,cy,cz=center;rx,ry,rz=radii
    vertices=[]
    for ring in range(3):
        for i in range(8):
            angle=TAU*i/8
            scale=(1.0,.89,.40)[ring]
            vertices.append((cx+rx*math.cos(angle)*scale,cy+ry*math.sin(angle)*scale,cz+rz*(-.38,.34,.82)[ring]+.012*math.sin(i*2.1)))
    vertices.append((cx,cy,cz+rz*.96))
    faces=[]
    for ring in range(2):
        for i in range(8):faces.append((ring*8+i,ring*8+(i+1)%8,(ring+1)*8+(i+1)%8,(ring+1)*8+i))
    for i in range(8):faces.append((16+i,16+(i+1)%8,24))
    faces.append(tuple(range(7,-1,-1)))
    b.add(vertices,faces,material,bone)


def humanoid_body(kind, mats, rig):
    bones = list(rig.data.bones.keys())
    b = meshlib.MeshBuild(mats, bones)
    skin, cloth, cloak = mats["skin"], mats["cloth"], mats["cloak"]

    # Articulated legs, boots, and reinforced joints.
    for side, suffix in [(-1, "L"), (1, "R")]:
        x = side * (.16 if kind != "troll" else .23)
        b.tube([(x,0,.99),(x+side*.025,0,.73),(x+side*.035,0,.53)],[(.14,.13),(.13,.12),(.105,.10)],"pants","thigh."+suffix,14,"shin."+suffix,.68)
        b.tube([(x+side*.035,0,.55),(x+side*.035,0,.32),(x+side*.02,-.01,.13)],[(.105,.10),(.09,.085),(.075,.07)],"cloak","shin."+suffix,14,"foot."+suffix,.72)
        b.ellipsoid((x,-.055,.10),(.15,.22,.09),"metal","foot."+suffix,18,12)
        b.ellipsoid((x,-.15,.10),(.15,.16,.07),"cloth","foot."+suffix,18,12)
        b.tube([(x,-.19,.15),(x,-.19,.22),(x,-.17,.31)],[(.10,.072),(.087,.066),(.062,.047)],"trim","foot."+suffix,12)
        armor_shell(b,(x+side*.035,-.10,.54),(.12,.12,.10),"metal","shin."+suffix)

    # Tapered anatomical core and layered armor are independent solid surfaces.
    width = .34 if kind in ("orc","uruk") else .30
    if kind == "troll": width = .52
    b.loft([(0,0,.83,width*.66,.20),(0,0,.96,width*.82,.24),(0,0,1.12,width*.78,.22),(0,0,1.35,width*.84,.23),(0,0,1.60,width,.24),(0,0,1.77,width*.68,.20)],"skin","spine",28,("hips","chest",1.20))
    if kind != "troll":
        b.loft([(0,.005,.79,width*.90,.24),(0,.005,.92,width,.26),(0,0,1.13,width*.92,.25),(0,0,1.43,width*1.03,.26),(0,0,1.64,width*1.08,.25),(0,0,1.80,width*.76,.21)],"cloth","spine",28,("hips","chest",1.22))
    else:
        for side in (-1,1):
            b.ellipsoid((side*.22,-.16,1.53),(.24,.13,.17),"skin","chest",24,16)
            b.tube([(side*.10,-.23,1.71),(side*.30,-.21,1.67),(side*.43,-.16,1.61)],[(.025,.017),(.032,.021),(.018,.012)],"skin","chest",10)
        for fold in range(4):
            z=1.17+fold*.066
            b.tube([(-.22,-.215,z),(0,-.234,z-.018),(.22,-.215,z)],[(.009,.007)]*3,"cloak","spine",8)
    b.loft([(0,.02,.71,width,.25),(0,.02,.79,width*1.08,.27),(0,.02,.89,width*.92,.23)],"cloak","hips",28)
    b.tube([(-width*.90,-.22,.83),(-width*.55,-.27,.79),(0,-.29,.78),(width*.55,-.27,.79),(width*.90,-.22,.83)],[(.022,.016)]*5,"trim","hips",8)
    b.loft([(0,.01,.95,width*1.09,.27),(0,.01,1.02,width*1.16,.28),(0,.01,1.09,width*1.05,.26)],"metal","spine",24)
    b.ellipsoid((0,-.294,1.01),(.085,.028,.066),"trim","spine",14,9)

    # Neck, shaped jaw, ears, eyes, brows, and tusks.
    head_scale = 1.0 if kind != "troll" else 1.28
    b.tube([(0,0,1.69),(0,0,1.81),(0,0,1.89)],[(.105,.10),(.092,.09),(.083,.08)],"skin","neck",14)
    b.loft([(0,-.005,1.75,.09,.10),(0,-.018,1.80,.14*head_scale,.13*head_scale),(0,-.025,1.88,.175*head_scale,.16*head_scale),(0,-.018,1.98,.19*head_scale,.17*head_scale),(0,-.006,2.08,.17*head_scale,.15*head_scale),(0,.006,2.15,.11*head_scale,.11*head_scale)],"skin","head",28)
    for side in (-1,1):
        ear_len = .25 if kind == "goblin" else .17
        b.tube([(side*.17,0,1.99),(side*.25,.01,2.03),(side*(.27+ear_len),.015,2.11)],[(.07,.05),(.05,.035),(.003,.002)],"skin","head",9)
        x = side*.082
        eye_width = .088 if kind in ("orc","uruk","troll") else .105
        eye_height = .033 if kind in ("orc","uruk","troll") else .046
        b.almond_eye(x,-.175,2.00,"white","head",eye_width,eye_height)
        b.ellipsoid((x,-.190,2.00),(.017,.010,.020),"eyes","head",14,10)
        b.ellipsoid((x,-.198,2.00),(.010,.006,.022),"hair","head",10,8)
        b.ellipsoid((x-.002,-.203,2.012),(.004,.004,.006),"white","head",8,6)
        b.tube([(x-side*.046,-.18,2.028),(x,-.203,2.044),(x+side*.052,-.17,2.061)],[(.025,.019),(.031,.023),(.018,.014)],"skin","head",9)
    b.ellipsoid((0,-.19,1.93),(.10,.055,.08),"skin","head",16,9)
    b.tube([(-.045,-.24,1.89),(0,-.251,1.885),(.045,-.24,1.89)],[(.009,.006),(.008,.005),(.006,.004)],"hair","head",7)
    # Crooked nasal bridge, inset nostrils, cheek planes and lower lip provide
    # facial structure instead of a smooth ball with two large circular eyes.
    b.loft([(0,-.164,2.052,.030,.028),(0,-.198,1.996,.035,.041),(0,-.224,1.958,.063,.038)],"skin","head",12)
    for side in (-1,1):
        b.ellipsoid((side*.043,-.254,1.957),(.017,.007,.009),"hair","head",10,7)
        b.tube([(side*.14,-.142,1.991),(side*.123,-.189,1.951),(side*.102,-.192,1.909)],[(.032,.021),(.039,.025),(.019,.014)],"skin","head",9)
    b.ellipsoid((0,-.227,1.842),(.083,.036,.034),"skin","head",16,10)
    if kind in ("goblin","orc","uruk","troll"):
        for side in (-1,1):
            b.tube([(side*.052,-.224,1.875),(side*.07,-.246,1.90),(side*.078,-.242,1.96)],[(.027,.020),(.020,.014),(.002,.002)],"white","head",8)
    if kind == "orc":
        b.tube([(-.14,-.17,2.13),(-.05,-.205,2.16),(.04,-.215,2.10),(.15,-.16,2.15)],[(.022,.016),(.018,.012),(.027,.018),(.006,.004)],"accent","head",8)
        for side in (-1,1):
            b.ellipsoid((side*.19,0,1.97),(.065,.08,.04),"metal","head",12,8)
    elif kind == "goblin":
        b.ellipsoid((0,.015,2.13),(.16,.14,.07),"hair","head",18,10)
        for i in range(7):
            x=-.15+i*.05
            b.tube([(x,.0,2.16),(x-.02,.02,2.26),(x+.01,.035,2.34+.025*(i%3))],[(.055,.045),(.037,.03),(.001,.001)],"hair","head",8)
    elif kind == "uruk":
        b.loft([(0,.025,2.075,.202,.167),(0,.033,2.17,.205,.175),(0,.046,2.265,.145,.138),(0,.05,2.29,.046,.055)],"metal","head",12)
        # Central iron ridge, cheek guards and the characteristic white hand.
        b.tube([(0,-.176,2.12),(0,-.149,2.23),(0,.02,2.29),(0,.17,2.15)],[(.018,.014)]*4,"trim","head",7)
        for side in (-1,1):
            b.panel(3,3,lambda u,v,s=side:(s*(.145+.045*v),-.08-.065*v,2.11-.28*u+.03*v),"metal","head")
    elif kind == "troll":
        # Cave trolls have a bald, heavy brow and leathery folds rather than a
        # warrior's helmet/quiff. The broad jaw also changes their silhouette.
        b.ellipsoid((0,.02,2.115),(.22,.19,.13),"skin","head",24,16)
        b.ellipsoid((0,-.125,1.825),(.205,.13,.09),"skin","head",24,14)
        for fold in range(4):
            z=2.075+fold*.036
            b.tube([(-.16,-.115,z),(0,-.174,z+.013),(.16,-.115,z)],[(.009,.007)]*3,"cloak","head",8)
    elif kind == "nazgul":
        # Hood opening and the shadowed face remain real geometry, with ember eyes.
        b.loft([(0,.015,1.98,.19,.17),(0,.02,2.12,.23,.21),(0,.05,2.24,.26,.23),(0,.09,2.29,.23,.20)],"cloak","head",24)
        b.tube([(-.18,-.11,2.12),(-.14,-.19,2.00),(0,-.205,1.93),(.14,-.19,2.00),(.18,-.11,2.12)],[(.03,.02)]*5,"metal","head",8)
        for side in (-1,1):
            b.ellipsoid((side*.082,-.205,2.01),(.033,.009,.018),"glow","head",14,8)

    # Shoulder shells, forearms, gloves, plated shins, and individual fingers.
    for side, suffix in [(-1,"L"),(1,"R")]:
        shoulder, upper, fore, hand = "shoulder."+suffix,"upper_arm."+suffix,"forearm."+suffix,"hand."+suffix
        shoulder_width = .37 if kind != "troll" else .53
        if kind == "troll":
            b.ellipsoid((side*shoulder_width,0,1.62),(.20,.18,.20),"skin","chest",24,16)
        else:
            armor_shell(b,(side*shoulder_width,0,1.62),(.21,.20,.15),"metal","chest")
            b.tube([(side*(shoulder_width-.14),-.14,1.58),(side*shoulder_width,-.19,1.57),(side*(shoulder_width+.15),-.13,1.55)],[(.012,.009)]*3,"trim","chest",8)
        arm_start=len(b.v)
        b.tube([(side*.34,0,1.62),(side*.40,0,1.43),(side*.40,-.005,1.29)],[(.17,.15),(.15,.13),(.115,.10)] if kind=="troll" else [(.14,.13),(.12,.11),(.095,.09)],"skin" if kind=="troll" else "cloth",shoulder,18,upper,.36)
        b.tube([(side*.40,-.005,1.31),(side*.41,-.015,1.16),(side*.41,-.025,1.02)],[(.10,.093),(.088,.082),(.071,.066)],"skin",upper,14,fore,.50)
        b.tube([(side*.41,-.02,1.17),(side*.42,-.025,1.10),(side*.42,-.03,1.03)],[(.094,.086),(.082,.076),(.067,.062)],"metal",fore,14)
        b.tube([(side*.42,-.03,1.04),(side*.43,-.04,.97),(side*.44,-.06,.91)],[(.068,.063),(.063,.059),(.052,.049)],"skin",hand,12)
        b.ellipsoid((side*.43,-.055,.94),(.074,.062,.07),"skin",hand,16,10)
        for finger in range(4):
            fx=side*.43+side*(finger-1.5)*.027
            b.tube([(fx,-.06,.93),(fx,-.09,.89),(fx,-.11,.86)],[(.020,.017),(.015,.014),(.008,.008)],"skin",hand,7)
        b.tube([(side*.36,-.02,1.08),(side*.42,-.04,1.06),(side*.48,-.02,1.09)],[(.12,.08)]*3,"trim",fore,8)
        b.tube([(side*.28,.13,1.76),(side*.42,.16,1.63),(side*.50,.18,1.49)],[(.085,.055),(.055,.035),(.002,.001)],"metal","chest",8)
        if kind == "troll":
            for vertex_index in range(arm_start,len(b.v)):
                x,y,z=b.v[vertex_index];b.v[vertex_index]=(x*1.30,y,z)

    # Distinct armor silhouette and insignia per enemy class.
    if kind == "goblin":
        b.loft([(0,-.015,.72,.33,.23),(0,-.015,.80,.36,.24),(0,-.01,.90,.30,.20)],"cloak","hips",24)
        b.tube([(-.29,-.20,1.42),(0,-.28,1.54),(.29,-.20,1.42)],[(.032,.023)]*3,"trim","chest",8)
    elif kind == "orc":
        b.loft([(0,-.005,1.14,.34,.25),(0,-.005,1.25,.38,.28),(0,-.005,1.35,.36,.27)],"metal","chest",24)
        b.tube([(-.28,-.285,1.40),(-.13,-.298,1.51),(0,-.30,1.44),(.14,-.30,1.53),(.29,-.28,1.40)],[(.024,.017)]*5,"accent","chest",8)
        for side in (-1,1):
            for i in range(3):
                b.ellipsoid((side*(.30+i*.045),0,1.70+i*.045),(.065,.09,.07),"metal","chest",12,8)
    elif kind == "uruk":
        b.loft([(0,-.01,1.12,.32,.24),(0,-.01,1.24,.38,.28),(0,-.01,1.38,.38,.28),(0,-.01,1.47,.31,.23)],"metal","chest",26)
        b.ribbon([(-.27,-.295,1.62),(-.12,-.31,1.44),(0,-.315,1.30),(.13,-.30,1.14)],.08,"accent","chest")
        b.box((0,-.302,1.49),(.095,.012,.10),"white","chest")
        for finger in range(4):
            x=-.037+finger*.024
            b.tube([(x,-.312,1.525),(x+finger*.004-.006,-.313,1.605+.015*(finger in (1,2)))],[(.009,.006),(.006,.004)],"white","chest",7)
        b.tube([(-.04,-.312,1.49),(-.087,-.31,1.535),(-.098,-.304,1.56)],[(.014,.008),(.010,.006),(.006,.004)],"white","chest",7)
    elif kind == "troll":
        b.loft([(0,.02,.70,.53,.32),(0,.02,.84,.59,.35),(0,.02,.98,.58,.34)],"cloak","hips",28)
        b.ribbon([(-.46,-.20,1.71),(-.27,-.27,1.49),(0,-.28,1.25),(.29,-.25,1.05)],.09,"trim","chest")
        for i in range(7):
            x=-.42+i*.14
            b.tube([(x,.25,1.4),(x*1.15,.39,1.58),(x*1.24,.50,1.70+.04*(i%2))],[(.08,.06),(.05,.035),(.002,.001)],"metal","chest",8)
    else:
        b.panel(8,10,lambda u,v:(-.43+.86*v,.13+.26*math.sin(v*math.pi)+.08*math.sin(u*math.pi),1.69-.90*u+.05*math.sin(v*TAU)),"cloak","cape")
        for side in (-1,1):
            b.tube([(side*.37,.14,1.65),(side*.41,.27,1.30),(side*.34,.34,.97),(side*.29,.36,.79)],[(.018,.012)]*4,"metal","cape",7)
        b.ellipsoid((0,-.287,1.49),(.06,.015,.075),"glow","chest",14,9)

    # Individual weapon geometry is held by the animated hand bone.
    if kind in ("orc","uruk","nazgul","goblin"):
        base=(.43,-.30,1.02); tip=(.49,-.32,1.80) if kind=="nazgul" else (.62,-.31,.55)
        if kind == "goblin": tip=(.59,-.32,.63)
        blade_mat="metal" if kind!="nazgul" else "trim"
        b.tube([base,(base[0]+.02,base[1],base[2]+.35),tip],[(.10,.045),(.075,.03),(.003,.001)],blade_mat,"hand.R",10)
        b.tube([(.31,-.28,.98),(.43,-.30,1.04),(.55,-.27,1.0)],[(.035,.025)]*3,"trim","hand.R",8)
        for i in range(4):
            b.ellipsoid((.42+i*.01,-.32,.94+i*.025),(.028,.018,.023),"accent","hand.R",10,7)
    elif kind == "troll":
        b.tube([(.44,-.29,.86),(.54,-.31,.99),(.69,-.28,1.49)],[(.115,.09),(.095,.075),(.055,.045)],"cloak","hand.R",12)
        b.ellipsoid((.70,-.28,1.58),(.18,.14,.23),"metal","hand.R",18,12)
        for side in (-1,1):
            b.tube([(.70+side*.10,-.30,1.69),(.70+side*.18,-.31,1.82)],[(.052,.04),(.003,.002)],"trim","hand.R",8)
    else:
        # A jagged mane and long muzzle make the Warg read as a quadruped.
        pass

    obj = meshlib.create_mesh_object(kind,1,b,mats,rig)
    return obj


def make_warg_rig():
    data=bpy.data.armatures.new("warg_Skeleton")
    rig=bpy.data.objects.new("warg_Armature",data)
    bpy.context.collection.objects.link(rig)
    bpy.context.view_layer.objects.active=rig;rig.select_set(True)
    bpy.ops.object.mode_set(mode="EDIT")
    def bone(name,head,tail,parent=None):
        b=data.edit_bones.new(name);b.head=head;b.tail=tail
        if parent: b.parent=data.edit_bones[parent]
        return b
    bone("root",(0,0,.05),(0,0,.50))
    bone("hips",(0,0,.50),(0,.18,.78),"root")
    bone("spine",(0,.18,.78),(0,-.15,.92),"hips")
    bone("chest",(0,-.15,.92),(0,-.42,1.0),"spine")
    bone("neck",(0,-.42,1.0),(0,-.63,1.05),"chest")
    bone("head",(0,-.63,1.05),(0,-.89,1.09),"neck")
    for side,suffix in [(-1,"L"),(1,"R")]:
        bone("shoulder."+suffix,(side*.2,-.42,.85),(side*.2,-.48,.75),"chest")
        bone("upper_arm."+suffix,(side*.2,-.48,.75),(side*.2,-.48,.42),"shoulder."+suffix)
        bone("forearm."+suffix,(side*.2,-.48,.42),(side*.2,-.48,.12),"upper_arm."+suffix)
        bone("hand."+suffix,(side*.2,-.48,.12),(side*.2,-.58,.08),"forearm."+suffix)
        bone("thigh."+suffix,(side*.22,.40,.76),(side*.22,.43,.42),"hips")
        bone("shin."+suffix,(side*.22,.43,.42),(side*.22,.43,.12),"thigh."+suffix)
        bone("foot."+suffix,(side*.22,.43,.12),(side*.22,.29,.08),"shin."+suffix)
    bone("cape",(0,.43,.94),(0,.80,.82),"hips")
    bpy.ops.object.mode_set(mode="OBJECT")
    rig.select_set(False)
    return rig


def warg_body(mats,rig):
    b=meshlib.MeshBuild(mats,list(rig.data.bones.keys()))
    # Long, weighted torso with articulated shoulder and haunch masses.
    b.ellipsoid((0,.02,.94),(.39,.76,.34),"skin","spine",28,18)
    b.ellipsoid((0,-.40,.99),(.40,.40,.36),"cloak","chest",24,16)
    b.ellipsoid((0,.43,.95),(.43,.40,.37),"cloth","hips",24,16)
    b.ellipsoid((0,-.70,1.05),(.29,.32,.28),"skin","head",24,16)
    b.ellipsoid((0,-.91,.98),(.22,.30,.15),"skin","head",20,12)
    b.ellipsoid((0,-1.12,1.01),(.16,.10,.09),"hair","head",16,10)
    for side in (-1,1):
        b.ellipsoid((side*.22,-.82,1.18),(.055,.035,.048),"eyes","head",14,9)
        b.tube([(side*.15,-.73,1.23),(side*.24,-.68,1.38),(side*.30,-.64,1.42)],[(.075,.06),(.05,.035),(.002,.001)],"hair","head",9)
        b.tube([(side*.10,-1.0,.99),(side*.17,-1.05,1.02),(side*.17,-.99,1.08)],[(.028,.02),(.02,.014),(.002,.001)],"white","head",8)
    # Four legs are weighted to four independently animated limbs.
    for side,suffix in [(-1,"L"),(1,"R")]:
        for fore, y, upper, lower in [(True,-.43,"upper_arm."+suffix,"forearm."+suffix),(False,.43,"thigh."+suffix,"shin."+suffix)]:
            x=side*.23
            b.tube([(x,y,.82),(x,y,.55),(x,y,.31)],[(.145,.14),(.115,.11),(.078,.075)],"skin",upper,14,lower,.50)
            b.tube([(x,y,.34),(x,y-.025,.18),(x,y-.10,.10)],[(.082,.078),(.074,.07),(.09,.075)],"cloak",lower,12)
            paw_bone = "hand."+suffix if fore else "foot."+suffix
            b.ellipsoid((x,y-.12,.10),(.12,.21,.08),"metal",paw_bone,14,9)
    # Bridle, leather harness, plates, dorsal mane, and a long swaying tail.
    b.tube([(-.30,-.46,1.17),(0,-.52,1.27),(.30,-.46,1.17),(0,-.28,1.29),(-.30,-.46,1.17)],[(.035,.022)]*5,"metal","chest",8)
    b.tube([(0,.54,1.02),(0,.78,1.06),(0,1.02,1.20),(0,1.25,1.32)],[(.11,.09),(.085,.07),(.045,.035),(.003,.002)],"skin","cape",10)
    for i in range(9):
        y=-.25+i*.12
        b.tube([(-.10,y,1.20),(0,y+.025,1.42+.04*(i%2)),(.10,y,1.20)],[(.065,.05),(.002,.001),(.065,.05)],"hair","spine",8)
    for side in (-1,1):
        b.ellipsoid((side*.37,-.38,.99),(.06,.22,.23),"metal","chest",16,10)
        b.ellipsoid((side*.40,.34,.92),(.05,.22,.20),"metal","hips",16,10)
    obj=meshlib.create_mesh_object("warg",1,b,mats,rig)
    return obj


def _move_world(pose, offset):
    pose.location = pose.bone.matrix_local.to_3x3().inverted() @ Vector(offset)


def _aim_bone(pose, head, tail):
    rest = pose.bone
    rotation = (rest.tail_local-rest.head_local).rotation_difference(tail-head)
    pose.matrix = Matrix.Translation(head) @ rotation.to_matrix().to_4x4() @ rest.matrix_local.to_3x3().to_4x4()


def _solve_limb(rig, upper_name, lower_name, foot_name, ankle, knee_pole):
    """Bake two-bone IK. Planted feet remain on z=.16 in armature space."""
    upper = rig.pose.bones[upper_name]
    lower = rig.pose.bones[lower_name]
    foot = rig.pose.bones[foot_name]
    parent_delta = upper.parent.matrix @ upper.parent.bone.matrix_local.inverted()
    hip = parent_delta @ upper.bone.head_local
    target = Vector(ankle)
    delta = target-hip
    length1, length2 = upper.bone.length, lower.bone.length
    distance = max(.01,min(delta.length,length1+length2-.001))
    direction = delta.normalized()
    target = hip+direction*distance
    along = (length1*length1-length2*length2+distance*distance)/(2*distance)
    pole=Vector(knee_pole)
    bend = (pole-direction*pole.dot(direction)).normalized()
    knee = hip+direction*along+bend*math.sqrt(max(.0001,length1*length1-along*along))
    _aim_bone(upper,hip,knee)
    bpy.context.view_layer.update()
    _aim_bone(lower,knee,target)
    bpy.context.view_layer.update()
    foot.matrix = Matrix.Translation(target) @ foot.bone.matrix_local.to_3x3().to_4x4()


def _foot_trajectory(phase, base_y, ankle_height, travel=RUN_FOOT_TRAVEL, contact=RUN_CONTACT):
    phase %= 1.0
    if phase < contact:
        # Linear backwards travel cancels the actor's forward route movement.
        return base_y-travel*.5+travel*phase/contact, ankle_height
    swing=(phase-contact)/(1-contact)
    smooth=swing*swing*(3-2*swing)
    return base_y+travel*.5-travel*smooth, ankle_height+.19*math.sin(math.pi*swing)


def animate(rig,kind):
    data=rig.animation_data_create()
    bones=rig.pose.bones
    for pose in bones: pose.rotation_mode="XYZ"
    clips={"Idle":range(1,50,3),"Run":range(1,22),"Hit":range(1,14),"Death":range(1,35)}
    for clip,frame_range in clips.items():
        frames=list(frame_range)
        action=bpy.data.actions.new("enemy_"+kind+"_"+clip)
        rig.animation_data.action=action
        # Prevent older NLA strips from evaluating into a newly baked clip.
        for track in data.nla_tracks: track.mute=True
        for frame in frames:
            bpy.context.scene.frame_set(frame)
            t=(frame-frames[0])/(frames[-1]-frames[0])
            wave=math.sin(t*TAU)
            pulse=math.sin(t*math.pi)
            for pose in bones:
                pose.rotation_euler=(0,0,0);pose.location=(0,0,0);pose.scale=(1,1,1)
            if clip=="Idle":
                bones["spine"].rotation_euler[0]=math.radians(1.2*wave)
                bones["chest"].rotation_euler[2]=math.radians(1.8*wave)
                bones["head"].rotation_euler[1]=math.radians(-2.0*wave)
                bones["cape"].rotation_euler[0]=math.radians(3.0*wave)
            elif clip=="Run":
                _move_world(bones["hips"],(.018*wave,0,-.13+.018*math.cos(t*TAU*2)))
                bones["spine"].rotation_euler[0]=math.radians(-7)
                bones["chest"].rotation_euler[1]=math.radians(3.5*wave)
                bones["head"].rotation_euler[0]=math.radians(5)
                bones["cape"].rotation_euler[0]=math.radians(-9-7*wave)
                bpy.context.view_layer.update()
                for index,suffix in enumerate(("L","R")):
                    phase=(t+index*.5)%1.0
                    if kind=="warg":
                        for fore in (True,False):
                            limb_phase=(phase+(.5 if not fore else 0))%1.0
                            base_y=-.48 if fore else .43
                            y,z=_foot_trajectory(limb_phase,base_y,.12,.66,.42)
                            upper=("upper_arm." if fore else "thigh.")+suffix
                            lower=("forearm." if fore else "shin.")+suffix
                            foot=("hand." if fore else "foot.")+suffix
                            _solve_limb(rig,upper,lower,foot,(.20 if suffix=="R" else -.20,y,z),(0,1 if fore else -1,0))
                    else:
                        y,z=_foot_trajectory(phase,0,.16)
                        x=bones["thigh."+suffix].bone.head_local.x
                        _solve_limb(rig,"thigh."+suffix,"shin."+suffix,"foot."+suffix,(x,y,z),(0,-1,0))
                        arm_wave=math.cos(TAU*phase)
                        bones["upper_arm."+suffix].rotation_euler[0]=math.radians(25*arm_wave)
                        bones["forearm."+suffix].rotation_euler[0]=math.radians(-28-15*arm_wave)
                        bones["hand."+suffix].rotation_euler[2]=math.radians(6*arm_wave)
            elif clip=="Hit":
                bones["chest"].rotation_euler[0]=math.radians(21*pulse)
                bones["head"].rotation_euler[0]=math.radians(-15*pulse)
                bones["spine"].rotation_euler[2]=math.radians(11*pulse)
                bones["cape"].rotation_euler[0]=math.radians(16*pulse)
                _move_world(bones["hips"],(0,.045*pulse,-.04*pulse))
            else:
                # Ease into a permanent fallen pose; never stand back up at t=1.
                fall=min(1.0,t/.78);fall=fall*fall*(3-2*fall)
                bones["root"].rotation_euler[0]=math.radians(87*fall)
                _move_world(bones["root"],(0,0,.24*fall))
                bones["spine"].rotation_euler[2]=math.radians(15*fall)
                bones["head"].rotation_euler[0]=math.radians(-12*fall)
                bones["cape"].rotation_euler[0]=math.radians(24*fall)
                for suffix,side in (("L",-1),("R",1)):
                    bones["upper_arm."+suffix].rotation_euler[2]=math.radians(side*32*fall)
                    bones["forearm."+suffix].rotation_euler[0]=math.radians(-25*fall)
                    bones["thigh."+suffix].rotation_euler[0]=math.radians(side*12*fall)
            # Keys must be captured while this frame's pose is active. The old
            # code captured every key after the loop, producing static clips.
            for pose in bones:
                pose.keyframe_insert(data_path="rotation_euler",frame=frame,group=pose.name)
                pose.keyframe_insert(data_path="location",frame=frame,group=pose.name)
        data.action=None
        track=data.nla_tracks.new();track.name=clip
        strip=track.strips.new(clip,frames[0],action)
        strip.action_frame_start=frames[0];strip.action_frame_end=frames[-1]
        track.mute=True
    for pose in bones:
        pose.rotation_euler=(0,0,0);pose.location=(0,0,0)
    rig["run_cycle_seconds"]=RUN_CYCLE_SECONDS
    travel=.66 if kind=="warg" else RUN_FOOT_TRAVEL
    contact=.42 if kind=="warg" else RUN_CONTACT
    rig["run_stride_m"]=travel/contact
    rig["run_reference_mps"]=travel/contact/RUN_CYCLE_SECONDS
    bpy.context.scene.frame_set(1)


def export_enemy(kind):
    meshlib.clear_scene()
    mats=materials_for(kind)
    rig=make_warg_rig() if kind=="warg" else make_enemy_rig(kind)
    if kind=="warg": warg_body(mats,rig)
    else: humanoid_body(kind,mats,rig)
    animate(rig,kind)
    bpy.ops.object.select_all(action="DESELECT")
    rig.select_set(True);bpy.context.view_layer.objects.active=rig
    for obj in bpy.context.scene.objects:
        if obj.type=="MESH" and obj.name.startswith(kind+"_L1"):
            pack_character_materials(obj,kind,os.path.join(OUT_DIR,"Atlases"),resolution=2048)
            obj.select_set(True)
    path=os.path.join(OUT_DIR,kind+".glb")
    bpy.ops.export_scene.gltf(filepath=path,export_format="GLB",use_selection=True,export_apply=True,export_animations=True,export_lights=False,export_cameras=False,export_nla_strips=True,export_skins=True,export_materials="EXPORT",export_image_format="AUTO",export_extras=True)
    print("BUILT_ENEMY",kind,path,os.path.getsize(path))


def main():
    bpy.context.scene.unit_settings.system="METRIC"
    bpy.context.scene.render.fps=30
    for kind in ["goblin","orc","uruk","troll","nazgul","warg"]:
        export_enemy(kind)
    print("ALL_ENEMY_MODELS_BUILT")


if __name__=="__main__":
    main()
