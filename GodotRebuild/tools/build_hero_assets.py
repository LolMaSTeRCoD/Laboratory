"""KDTD character pipeline v2.

Anatomical topology, UVs and deformation weights: MakeHuman hm08, CC0.
All character sculpt deltas, garments, hair, props and animation below are new.
No mesh, billboard or code from the previous tower generator is imported.
"""
import bpy, bmesh, json, math, os, random, sys
from pathlib import Path
from mathutils import Vector, Quaternion
from mathutils.bvhtree import BVHTree
import numpy as np
sys.path.insert(0,str(Path(__file__).parent))
from pack_character_materials import pack_character_materials
from hero_surface_materials import material as pbr_hero_material
from hero_costumes import add_mantle, add_bulls_crest, add_noelle_skirt_and_gaiters, add_costume_details, add_rank_details

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT.parent / 'Source' / 'HeroPipeline' / 'MakeHuman'
OUT = Path(os.environ.get('CADY_HERO_OUT',str(ROOT / 'Assets' / 'Heroes')))
EDITABLE = Path(os.environ.get('CADY_HERO_EDITABLE',str(ROOT.parent / 'Source' / 'HeroPipeline' / 'Characters')))
TAU = math.tau

HEROES = {
 'asta': dict(height=2.12, width=1.11, head=1.50, jaw=.93, female=False,
  skin=(.73,.50,.36), hair=(.27,.28,.235), cloth=(.07,.14,.21), main=(.018,.023,.030),
  pants=(.025,.047,.075), leather=(.25,.13,.055), iris=(.28,.50,.10), accent=(.30,.018,.026)),
 'yuno': dict(height=2.30, width=.93, head=1.24, jaw=.89, female=False,
  skin=(.72,.48,.33), hair=(.018,.023,.030), cloth=(.032,.042,.058), main=(.016,.023,.036),
  pants=(.022,.030,.040), leather=(.12,.075,.035), iris=(.49,.42,.12), accent=(.05,.35,.21)),
 'magna': dict(height=2.25, width=1.02, head=1.23, jaw=1.03, female=False,
  skin=(.64,.36,.22), hair=(.36,.29,.51), cloth=(.035,.045,.075), main=(.019,.022,.030),
  pants=(.025,.027,.052), leather=(.045,.04,.05), iris=(.15,.29,.50), accent=(.85,.12,.015)),
 'vanessa': dict(height=2.34, width=.94, head=1.23, jaw=.82, female=True,
  skin=(.73,.47,.34), hair=(.50,.22,.32), cloth=(.20,.033,.070), main=(.018,.022,.029),
  pants=(.20,.033,.070), leather=(.19,.06,.09), iris=(.40,.26,.53), accent=(.52,.08,.22)),
 'noelle': dict(height=2.20, width=.88, head=1.30, jaw=.81, female=True,
  skin=(.76,.53,.40), hair=(.62,.63,.70), cloth=(.77,.76,.72), main=(.018,.023,.033),
  pants=(.73,.72,.72), leather=(.24,.09,.065), iris=(.45,.17,.49), accent=(.28,.12,.34)),
 'charmy': dict(height=1.62, width=1.06, head=1.72, jaw=.88, female=True,
  skin=(.82,.60,.45), hair=(.075,.047,.028), cloth=(.84,.82,.72), main=(.018,.022,.025),
  pants=(.19,.045,.040), leather=(.085,.24,.34), iris=(.16,.53,.31), accent=(.78,.72,.55)),
}

RENAME = {'spine03':'spine', 'spine01':'chest', 'neck03':'neck'}
for side in ['L','R']:
 for a,b in [('shoulder01','shoulder'),('upperarm01','upper_arm'),('lowerarm01','forearm'),
             ('wrist','hand'),('upperleg01','thigh'),('lowerleg01','shin')]:
  RENAME[a+'.'+side] = b+'.'+side
def bn(name): return RENAME.get(name,name)

def read_obj(path):
 vs=[];uv=[];faces=[];groups={};group=''
 for line in path.read_text().splitlines():
  p=line.split()
  if not p: continue
  if p[0]=='v':vs.append(tuple(map(float,p[1:4])))
  elif p[0]=='vt':uv.append(tuple(map(float,p[1:3])))
  elif p[0]=='g':group=p[1]
  elif p[0]=='f':
   f=[tuple(int(i)-1 if i else -1 for i in q.split('/')) for q in p[1:]]
   faces.append((group,f));groups.setdefault(group,set()).update(q[0] for q in f)
 return np.array(vs,dtype=float),uv,faces,groups

RAW, UVS, FACES, GROUPS = read_obj(SOURCE/'base.obj')
BODY_SET=set(GROUPS['body'])
RIG = json.loads((SOURCE/'default.mhskel').read_text())
WEIGHTS = json.loads((SOURCE/'default_weights.mhw').read_text())['weights']
VERT_WEIGHTS = [{} for _ in RAW]
for name, rows in WEIGHTS.items():
 for i,w in rows:VERT_WEIGHTS[i][bn(name)]=w

NORMAL_CACHE={}

# CC0 hm08 head deltas; this is actual facial geometry, not a face image.
# Six independent face profiles, calibrated against the official front art.
# These deltas deform anatomical vertices and matching eye/lash helpers; they
# do not add a face photograph or alter the deformation weights/skeleton.
ANIME_HEAD_PROFILES = {
 'asta': dict(anime=.90,asian=.55,eye=1.15,nose_depth=.38,nose_width=.20,
              eye_x=1.10,eye_z=1.06,eye_tilt=.10,jaw=1.06,cheek=1.02,crown=.90,lip_height=.70,nose_tip=.045),
 'yuno': dict(anime=.76,asian=.46,eye=.92,nose_depth=.22,nose_width=.22,
              eye_x=1.09,eye_z=.90,eye_tilt=.09,jaw=.90,cheek=.97,crown=.92,lip_height=.66,nose_tip=.025),
 'magna': dict(anime=.68,asian=.43,eye=.95,nose_depth=.14,nose_width=.10,
              eye_x=1.04,eye_z=.95,eye_tilt=.12,jaw=1.10,cheek=1.03,crown=.92,lip_height=.76,nose_tip=.015),
 'vanessa': dict(anime=.65,asian=.53,eye=1.02,nose_depth=.32,nose_width=.24,
              eye_x=1.10,eye_z=.92,eye_tilt=.10,jaw=.92,cheek=1.02,crown=.92,lip_height=.94,nose_tip=.025),
 'noelle': dict(anime=.84,asian=.58,eye=1.20,nose_depth=.48,nose_width=.35,
              eye_x=1.16,eye_z=1.00,eye_tilt=.045,jaw=1.01,cheek=1.04,crown=.94,lip_height=.94,nose_tip=.05),
 'charmy': dict(anime=.82,asian=.58,eye=1.00,nose_depth=.48,nose_width=.34,
              eye_x=1.06,eye_z=1.14,eye_tilt=.015,jaw=1.12,cheek=1.03,crown=.95,lip_height=1.0,nose_tip=.035),
}

BODY_NEIGHBORS={i:set() for i in BODY_SET}
for group,face in FACES:
 if group!='body':continue
 ids=[q[0] for q in face]
 for a,b in zip(ids,ids[1:]+ids[:1]):
  BODY_NEIGHBORS[a].add(b);BODY_NEIGHBORS[b].add(a)

def soften_anime_face(points):
 # Remove high-frequency nasolabial creasing where the broad anime delta
 # combines with the anatomical base. Vertex count, UVs and skin weights
 # remain untouched; narrow lip-edge vertices are relaxed only lightly.
 strength={}
 for i in BODY_SET:
  x,h,d=RAW[i]
  if abs(x)>.65 or h<6.25 or h>7.22 or d<1.16:continue
  weight=math.exp(-((abs(x)-.20)/.25)**4-((h-6.77)/.37)**4)
  lip_weight=sum(w for bone,w in VERT_WEIGHTS[i].items() if bone.startswith('oris'))
  strength[i]=weight*(1-.80*min(1,lip_weight))
 before=points.copy()
 for factor in [.44,-.20,.44,-.20,.44,-.20]:
  old=points.copy()
  for i,weight in strength.items():
   neighbors=list(BODY_NEIGHBORS[i])
   if neighbors:points[i]+=factor*weight*(old[neighbors].mean(axis=0)-old[i])
 print('ANIME_FACE_RELAX','vertices',len(strength),'max_source_delta',float(np.linalg.norm(points-before,axis=1).max()),flush=True)
def anatomical_normals(body):
 key=id(body)
 if key in NORMAL_CACHE:return NORMAL_CACHE[key]
 normals=np.zeros_like(body)
 for group,f in FACES:
  if group!='body':continue
  ids=[q[0] for q in f]
  n=np.cross(body[ids[1]]-body[ids[0]],body[ids[2]]-body[ids[0]])
  for i in ids:normals[i]+=n
 lens=np.linalg.norm(normals,axis=1);lens[lens<1e-8]=1;normals/=lens[:,None]
 NORMAL_CACHE.clear();NORMAL_CACHE[key]=normals
 return normals

def clean():
 NORMAL_CACHE.clear()
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 for pool in [bpy.data.actions,bpy.data.meshes,bpy.data.armatures,bpy.data.materials,bpy.data.images]:
  for item in list(pool):
   if item.users == 0:pool.remove(item)

def sculpt(hero):
 cfg=HEROES[hero];p=RAW.copy()
 profile=ANIME_HEAD_PROFILES.get(hero,{})
 targets=[('asian-female-young.target' if cfg['female'] else 'asian-male-young.target',profile.get('asian',.90 if hero=='asta' else .75)),
          ('l-eye-scale-incr.target',profile.get('eye',2.8 if hero=='asta' else 2.1)),('r-eye-scale-incr.target',profile.get('eye',2.8 if hero=='asta' else 2.1)),
          ('nose-scale-depth-decr.target',profile.get('nose_depth',1.05 if hero=='asta' else .65)),('nose-scale-horiz-decr.target',profile.get('nose_width',.55 if hero=='asta' else .35)),
          ('chin-width-decr.target',0 if hero=='charmy' else .28 if cfg['female'] else .12)]
 if profile:
  target='cartoon01/targets/cartoon/jaldmic_anime_head_and_body_v6_chiby.target' if hero=='charmy' else 'anime-head-only.target'
  targets.append((target,profile['anime']))
 for file,amount in targets:
  for line in (SOURCE/file).read_text().splitlines():
   s=line.split()
   if len(s)==4 and not s[0].startswith('#'):
    i=int(s[0])
    # The CC0 child morph includes body deltas; this pass owns the head only.
    head_weight=max(0,min(1,(RAW[i,1]-5.30)/.55)) if hero=='charmy' and 'chiby' in file else 1.0
    p[i]+=np.array(list(map(float,s[1:])))*amount*head_weight
 if profile:soften_anime_face(p)
 if profile:
  # Reshape each socket and its actual lid loops together. A shallow elliptical
  # eye behind an angular aperture avoids the former protruding spherical eye.
  for side in ['l','r']:
   ids=list(GROUPS['helper-'+side+'-eye']);center=p[ids].mean(axis=0)
   rx=float(np.ptp(p[ids,0]))*.5;rz=float(np.ptp(p[ids,1]))*.5
   sign=1 if side=='l' else -1
   for i,(x,h,d) in enumerate(p.copy()):
    if x*sign<0 or d<center[2]-.25:continue
    wx=math.exp(-((x-center[0])/max(.01,rx*1.45))**6)
    wz=math.exp(-((h-center[1])/max(.01,rz*1.65))**6)
    weight=wx*wz
    p[i,0]+=(x-center[0])*(profile['eye_x']-1)*weight
    p[i,1]+=((h-center[1])*(profile['eye_z']-1)+sign*(x-center[0])*profile['eye_tilt'])*weight
  # Character-specific jaw planes and cheek breadth, with a smaller human
  # nasolabial/lip volume while retaining a complete closed nose/lip topology.
  lip_ids=[i for i in BODY_SET if sum(w for n,w in VERT_WEIGHTS[i].items() if n.startswith('oris'))>.65]
  lip_center=float(np.median(p[lip_ids,1]))
  eye_level=float(np.mean([p[list(GROUPS['helper-'+s+'-eye']),1].mean() for s in ['l','r']]))
  for i,(x,h,d) in enumerate(p.copy()):
   if h<5.65:continue
   jaw=math.exp(-((h-6.20)/.38)**2)
   cheek=math.exp(-((h-6.90)/.40)**2)
   p[i,0]*=1+(profile['jaw']-1)*jaw+(profile['cheek']-1)*cheek
   if h>eye_level+.22:p[i,1]=eye_level+.22+(h-eye_level-.22)*profile['crown']
   if d>1.10:
    lip_weight=min(1.0,sum(w for n,w in VERT_WEIGHTS[i].items() if n.startswith('oris')))
    p[i,1]+=(lip_center-h)*(1-profile['lip_height'])*lip_weight
    p[i,2]-=(0 if hero=='charmy' else .065 if hero in ['noelle','vanessa'] else .030)*lip_weight
    nose=math.exp(-(x/.20)**2-((h-6.98)/.30)**2)
    p[i,2]-=profile['nose_tip']*nose
 # Individual proportions, and a larger anime cranium with a tapered jaw.
 head_size=1.45 if hero=='charmy' else cfg['head']
 p[:,0]*=cfg['width']
 for i,(x,h,d) in enumerate(p.copy()):
  t=max(0,min(1,(h-5.65)/.65))
  if t:
   p[i,0]=x*(1+(head_size-1)*t)
   p[i,1]=5.7+(h-5.7)*(1+(head_size-1)*(.48 if hero=='asta' else .78)*t)
   p[i,2]=d*(1+(.12 if cfg['female'] else .08)*t)
   chin=math.exp(-((h-6.25)/.38)**2)
   p[i,0]*=1-(1-(1.02 if hero=='charmy' else cfg['jaw']))*chin
  if hero=='asta' and h<5.6 and h>1.2:
   p[i,0]*=1+.06*math.exp(-((h-4)/1.5)**2)
  if cfg['female'] and .4<h<3.5 and abs(x)<1.9:
   p[i,0]*=.96
  if hero=='vanessa' and 2.4<h<4.5 and abs(x)<1.5:
   p[i,2]+=.08*math.exp(-((h-3.5)/.8)**2)*max(0,d)
  if h<-6.8 and d>0:p[i,2]*=.82
 # Relax only facial relief, preserving lip/nostril edges, outline, UVs and
 # weights. Nasolabial grooves from the anatomical adult base are not part of
 # the neutral anime expression, especially on the small child character.
 relief_weights={}
 for i in BODY_SET:
  x,h,d=RAW[i]
  if d<1.08 or abs(x)>.72 or h<6.10 or h>7.26:continue
  fold=math.exp(-((abs(x)-.32)/.32)**4-((h-6.74)/.42)**4)
  central_nose=math.exp(-(x/.17)**4-((h-7.03)/.23)**4)
  lip=min(1.0,sum(w for n,w in VERT_WEIGHTS[i].items() if n.startswith('oris')))
  relief_weights[i]=max(0,min(.65,.46*fold+.22*lip))*(1-central_nose*.90)
 for _ in range(80 if hero=='charmy' else 28):
  old=p.copy()
  for i,weight in relief_weights.items():
   neighbors=list(BODY_NEIGHBORS[i])
   if neighbors:p[i,2]+=weight*(float(old[neighbors,2].mean())-old[i,2])
 # Charmy's official short, compact silhouette needs different anatomy, not
 # another adult body uniformly scaled down. Broaden the cheek plane, reduce
 # the adult chest curvature and shorten the lower-body segment continuously.
 if hero=='charmy':
  eye_level=float(np.mean([p[list(GROUPS['helper-'+s+'-eye']),1].mean() for s in ['l','r']]))
  lip_ids=[i for i in BODY_SET if sum(w for n,w in VERT_WEIGHTS[i].items() if n.startswith('oris'))>.65]
  mouth_level=float(np.median(p[lip_ids,1]))
  for i,(x,h,d) in enumerate(p.copy()):
   if h<1.0:p[i,1]=-8.1676+(h+8.1676)*.83
   else:p[i,1]=-.55849+(h-1.0)*.92
   if 1.3<h<5.2 and abs(x)<1.9:p[i,2]*=.80
   if h>5.5:
    # A broad, rounded lower cheek and a short chin are local changes, not
    # a compression of the entire skull. The previous crown squeeze created
    # an alien wedge and made the cheeks look gaunt.
    lower=math.exp(-((h-mouth_level+.10)/.87)**2)
    p[i,0]*=1.015+.10*lower
    p[i,1]+=.13*math.exp(-((h-mouth_level+.42)/.65)**2)
 # Put the feet on z=0; adjust rest x stride to a natural standing width.
 p[:,0]*=.83
 scale=cfg['height']/(p[list(GROUPS['body']),1].max()+8.1676)
 converted=np.column_stack((p[:,0]*scale,-p[:,2]*scale,(p[:,1]+8.1676)*scale))
 return converted,p,scale

class Mesh:
 def __init__(self):self.v=[];self.f=[];self.m=[];self.w=[];self.uv=[]
 def add(self,verts,faces,mat,weights='head',uv=None):
  off=len(self.v);self.v.extend(tuple(v) for v in verts)
  if uv is None and len(verts):
   xs=[v[0] for v in verts];zs=[v[2] for v in verts]
   x0=min(xs);z0=min(zs);dx=max(1e-6,max(xs)-x0);dz=max(1e-6,max(zs)-z0)
   uv=[((v[0]-x0)/dx,(v[2]-z0)/dz) for v in verts]
  self.w.extend([weights.copy() if isinstance(weights,dict) else {weights:1} for _ in verts]
                if isinstance(weights,(str,dict)) else weights)
  for f in faces:
   self.f.append(tuple(off+i for i in f));self.m.append(mat)
   self.uv.append([uv[i] if uv else (verts[i][0]*3,verts[i][2]*3) for i in f])
 def shell(self,body,raw,predicate,mat,offset=.012,fold=0,hem=None,adjust=None,world_predicate=None):
  selected=[]
  for group,f in FACES:
   if group!='body':continue
   c=RAW[[q[0] for q in f]].mean(axis=0)
   if predicate(*c) and (world_predicate is None or world_predicate(*body[[q[0] for q in f]].mean(axis=0))):selected.append(f)
  ids=sorted({q[0] for f in selected for q in f});mapping={v:i for i,v in enumerate(ids)}
  edges={}
  for f in selected:
   for j,q in enumerate(f):
    key=tuple(sorted((q[0],f[(j+1)%len(f)][0])));edges[key]=edges.get(key,0)+1
  boundary={i for edge,count in edges.items() if count==1 for i in edge}
  hem_ids=[i for i in ids if hem is not None and abs(RAW[i,1]-hem)<.25]
  hem_z=float(np.mean([body[i,2] for i in hem_ids])) if hem_ids else None
  verts=[];normals=anatomical_normals(body)
  for i in ids:
   x,y,z=body[i];r=math.hypot(x,y)
   if r>.01:
    extra=offset+fold*(.5+.5*math.sin(z*58+x*21))*math.sin(z*11)**2
    x+=normals[i,0]*extra;y+=normals[i,1]*extra;z+=normals[i,2]*extra
   if hem_z is not None and i in boundary and abs(RAW[i,1]-hem)<.65:z=hem_z
   if adjust is not None:x,y,z=adjust(i,(x,y,z),i in boundary)
   verts.append((x,y,z))
  self.add(verts,[],mat,[VERT_WEIGHTS[i] for i in ids])
  off=len(self.v)-len(verts)
  for f in selected:
   self.f.append(tuple(off+mapping[q[0]] for q in f));self.m.append(mat)
   self.uv.append([UVS[q[1]] for q in f])
 def tube(self,points,radii,mat,bone='head',sides=14):
  pts=[Vector(p) for p in points];v=[];uv=[];f=[]
  for i,p in enumerate(pts):
   tangent=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
   ref=Vector((0,1,0)) if abs(tangent.y)<.9 else Vector((1,0,0))
   u=tangent.cross(ref).normalized();w=tangent.cross(u).normalized()
   radius=radii[i] if isinstance(radii,list) else radii
   a,b=radius if isinstance(radius,tuple) else (radius,radius)
   for j in range(sides):
    theta=TAU*j/sides;v.append(tuple(p+u*a*math.cos(theta)+w*b*math.sin(theta)))
    uv.append((j/sides,i/(len(pts)-1)))
  for i in range(len(pts)-1):
   for j in range(sides):a=i*sides+j;b=i*sides+(j+1)%sides;f.append((a,b,b+sides,a+sides))
  f.extend([tuple(range(sides-1,-1,-1)),tuple((len(pts)-1)*sides+j for j in range(sides))])
  self.add(v,f,mat,bone,uv)
 def patch(self,rows,cols,fn,mat,weights='chest',thickness=0):
  v=[];uv=[];f=[];ww=[]
  for r in range(rows+1):
   for c in range(cols+1):
    a=r/rows;b=c/cols;v.append(fn(a,b));uv.append((b,a))
    ww.append(weights(a,b) if callable(weights) else ({weights:1} if isinstance(weights,str) else weights))
  for r in range(rows):
   for c in range(cols):a=r*(cols+1)+c;f.append((a,a+1,a+cols+2,a+cols+1))
  if thickness>0:
   normals=np.zeros((len(v),3));points=np.array(v);boundary={}
   for face in f:
    n=np.cross(points[face[1]]-points[face[0]],points[face[2]]-points[face[0]])
    for i in face:normals[i]+=n
    for j,a in enumerate(face):
     edge=tuple(sorted((a,face[(j+1)%len(face)])));boundary[edge]=boundary.get(edge,0)+1
   lengths=np.linalg.norm(normals,axis=1);lengths[lengths<1e-8]=1;normals/=lengths[:,None]
   count=len(v);v.extend(tuple(q) for q in points-normals*thickness)
   f.extend(tuple(i+count for i in reversed(face)) for face in f.copy())
   for (a,b),uses in boundary.items():
    if uses==1:f.append((a,b,b+count,a+count))
   uv+=uv.copy();ww+=ww.copy()
  self.add(v,f,mat,ww,uv)
 def lock(self,points,width,depth,mat='hair'):
  pts=[Vector(p) for p in points];n=12;curve=[];r=[]
  for i in range(n+1):
   t=i/n;p=pts[0]*(1-t)**3+pts[1]*3*t*(1-t)**2+pts[2]*3*t*t*(1-t)+pts[3]*t**3
   curve.append(tuple(p));taper=(math.sin(math.pi*(.12+.88*t))**.65)*(.95-.90*t)
   r.append((max(.0005,width*taper),max(.0004,depth*taper)))
  self.tube(curve,r,mat,'head',12)
 def ellipsoid(self,center,radii,mat,bone='head',seg=32,rings=18):
  c=Vector(center);v=[];uv=[];f=[]
  for j in range(rings+1):
   phi=math.pi*(.0001+(j/rings)*.9998)
   for i in range(seg):
    theta=TAU*i/seg;v.append((c.x+radii[0]*math.sin(phi)*math.cos(theta),c.y+radii[1]*math.sin(phi)*math.sin(theta),c.z+radii[2]*math.cos(phi)));uv.append((i/seg,j/rings))
  for j in range(rings):
   for i in range(seg):a=j*seg+i;b=j*seg+(i+1)%seg;f.append((a,b,b+seg,a+seg))
  self.add(v,f,mat,bone,uv)

def rig(body,hero):
 data=bpy.data.armatures.new(hero+'_AnatomicalRig');obj=bpy.data.objects.new(hero+'_Rig',data)
 bpy.context.collection.objects.link(obj);bpy.context.view_layer.objects.active=obj;obj.select_set(True)
 bpy.ops.object.mode_set(mode='EDIT')
 def joint(key):return Vector(body[RIG['joints'][key]].mean(axis=0))
 for name,info in RIG['bones'].items():
  b=data.edit_bones.new(bn(name));b.head=joint(info['head']);b.tail=joint(info['tail'])
  if hero in ANIME_HEAD_PROFILES and name in ['eye.L','eye.R']:
   side=name[-1].lower()
   helper=body[list(GROUPS['helper-'+side+'-eye'])]
   eye_center=Vector((helper.min(axis=0)+helper.max(axis=0))*.5)
   shift=eye_center-b.head;b.head+=shift;b.tail+=shift
  if (b.tail-b.head).length<.001:b.tail.z+=.005
 for name,info in RIG['bones'].items():
  b=data.edit_bones[bn(name)]
  if info['parent']:b.parent=data.edit_bones[bn(info['parent'])]
  # Consistent roll in character space so arms bend about the correct axis.
  b.align_roll(Vector((0,-1,0)))
 for name,x in [('cape',0),('cape.L',-.18),('cape.R',.18)]:
  b=data.edit_bones.new(name);b.head=(x,.035,1.75);b.tail=(x,.15,1.15);b.parent=data.edit_bones['chest']
  if hero=='charmy':
   neck=float(body[list(GROUPS['joint-neck']),2].mean());b.head=(x*.7,.025,neck-.02);b.tail=(x*.7,.10,neck-.28)
 bpy.ops.object.mode_set(mode='OBJECT');obj.select_set(False)
 return obj

def texture_material(hero,name,color,kind):
 return pbr_hero_material(hero,name,color,kind,OUT)

def materials(hero):
 cfg=HEROES[hero];colors={k:cfg[k] for k in ['skin','hair','cloth','main','pants','leather','accent']}
 colors.update(white=(.81,.79,.73),gold=(.56,.36,.10),silver=(.40,.44,.48),steel=(.075,.085,.090),lens=(.018,.035,.065),black=(.008,.010,.014),iris=cfg['iris'],eye=(.91,.91,.86),lip=(.42,.21,.17))
 mats={}
 for name,col in colors.items():
  kind='skin' if name in ['skin','lip'] else ('hair' if name=='hair' else ('metal' if name in ['gold','silver','steel'] else ('iris' if name=='iris' else ('eye' if name in ['eye','lens'] else ('leather' if name=='leather' else 'fabric')))))
  mats[name]=texture_material(hero,name,col,kind)
 if hero=='noelle':mats['mint']=texture_material(hero,'mint',(.17,.43,.33),'fabric')
 if hero=='vanessa':mats['ribbon']=texture_material(hero,'ribbon',(.26,.22,.43),'fabric')
 return mats

def charmy_garments(m,body,p,level,scale):
 # Patterned from the official anime silhouette: roomy cream tunic with a
 # kangaroo pocket, cropped burgundy trousers, flats and a blue crossbody bag.
 # Unlike adult hero variants this is neither a fitted bodice nor a miniskirt.
 stage=0 if level<3 else 1 if level<5 else 2
 neck=float(body[list(GROUPS['joint-neck']),2].mean());waist=float(body[list(GROUPS['joint-pelvis']),2].mean())+.075
 torso_top=neck-.018;hem=waist-.235
 surface=body[sorted(BODY_SET)]
 def tunic(t,u):
  z=hem+(torso_top-hem)*t;a=TAU*u
  rx=float(np.interp(t,[0,.25,.60,.82,1],[.272,.250,.225,.255,.087]))
  ry=float(np.interp(t,[0,.35,.75,1],[.184,.182,.170,.090]))
  fold=.0035*math.sin(a*12+t*2)*math.sin(math.pi*t)
  return (math.sin(a)*(rx+fold),-.015-math.cos(a)*(ry+fold),z)
 m.patch(32,72,tunic,'cloth',lambda t,u:{'spine':1-t*.65,'chest':t*.65},thickness=.003)
 for t in [0,.028]:m.tube([tunic(t,u) for u in np.linspace(0,1,73)],.0028,'white','spine',7)
 # Pouch pocket follows the curved tunic front; actual edge loops and seam.
 def pocket(t,u):
  x=(u-.5)*(.265-.045*(1-t));z=waist-.125+t*.130
  y=-.015-.187*math.sqrt(max(.05,1-(x/.255)**2))-.014
  return (x,y,z)
 m.patch(12,20,pocket,'white','spine',thickness=.002)
 m.tube([pocket(1,u) for u in np.linspace(0,1,21)],.0025,'gold' if stage>=1 else 'cloth','spine',7)
 for edge in [0,1]:m.tube([pocket(t,edge) for t in np.linspace(0,1,13)],.0018,'accent','spine',6)
 # Sleeves retain deforming anatomical skin weights rather than rigid tubes.
 forearms=[]
 for side in ['l','r']:
  elbow=Vector(body[list(GROUPS['joint-'+side+'-elbow'])].mean(axis=0));wrist=Vector(body[list(GROUPS['joint-'+side+'-hand'])].mean(axis=0))
  raw_e=RAW[list(GROUPS['joint-'+side+'-elbow'])].mean(axis=0);raw_w=RAW[list(GROUPS['joint-'+side+'-hand'])].mean(axis=0)
  forearms.append((raw_e,raw_w-raw_e,elbow,wrist,side))
 def arms(x,h,d):
  e,axis,_,_,_=forearms[0 if x>0 else 1]
  phase=float(np.dot(np.array((x,h,d))-e,axis)/np.dot(axis,axis))
  return abs(x)>1.33 and 2.10<h<5.95 and phase<.80
 m.shell(body,p,arms,'cloth',.022,.003)
 m.shell(body,p,lambda x,h,d:-4.8<h<1.3 and abs(x)<2.4,'pants',.019,.004,hem=-4.8)
 for _,_,elbow,wrist,side in forearms:
  axis=(wrist-elbow).normalized();u=axis.cross(Vector((0,1,0))).normalized();v=axis.cross(u).normalized();center=elbow.lerp(wrist,.77)
  m.patch(5,36,lambda t,a,c=center,u=u,v=v,axis=axis:tuple(c+axis*(t-.5)*.06+(u*math.cos(a*TAU)+v*math.sin(a*TAU))*.047),'white','forearm.'+side.upper(),thickness=.002)
  if stage>=1:
   # Coherent fluted cotton-gauntlet surface: no orbiting upgrade symbols.
   wool_center=elbow.lerp(wrist,.94)
   def cotton(t,a,c=wool_center,u=u,v=v,axis=axis):
    phi=math.pi*(.001+.998*t);theta=TAU*a
    radius=(.059+.009*stage)*math.sin(phi)*(1+.12*math.cos(theta*7)*math.sin(phi*4)**2)
    return tuple(c+axis*(math.cos(phi)*(.072+.01*stage))+(u*math.cos(theta)+v*math.sin(theta))*radius)
   m.patch(18,40,cotton,'white','forearm.'+side.upper())
 # Cream low flats: closed lofts following the feet, leaving calves exposed.
 for side in ['l','r']:
  ankle=Vector(body[list(GROUPS['joint-'+side+'-ankle'])].mean(axis=0));sign=1 if side=='l' else -1
  front=min(body[i,1] for i in GROUPS['body'] if RAW[i,1]<-7.4 and RAW[i,0]*sign>0)-.005
  rings=[(ankle.y+.035,.037,.047),(ankle.y+.004,.052,.066),(front+.045,.057,.048),(front,.025,.026)]
  verts=[];faces=[]
  for y,w,h in rings:
   for j in range(24):
    a=TAU*j/24;verts.append((ankle.x+w*math.cos(a),y,.012+h*(.5+.5*math.sin(a))))
  for r in range(3):
   for j in range(24):a=r*24+j;b=r*24+(j+1)%24;faces.append((a,b,b+24,a+24))
  faces.extend([tuple(range(23,-1,-1)),tuple(range(72,96))]);m.add(verts,faces,'accent','foot.'+side.upper())
 # Shoulder seam and hanging front panels use the same character-sized
 # construction as the other heroes, not a domed rigid collar.
 top,_,crest=add_mantle(m,body,'charmy',stage,GROUPS)
 m.costume_crest=crest
 # Blue satchel, front flap, seam, brass clasp, diagonal shoulder strap.
 bagx=.222;bagy=-.018;bagz=waist-.18
 def bag(t,u):
  a=TAU*u;return (bagx+.074*math.sin(a),bagy-.053*math.cos(a),bagz+.09-t*.20)
 m.patch(16,48,bag,'leather','spine',thickness=.004)
 m.patch(12,20,lambda t,u:(bagx+(u-.5)*.144,bagy-.056-.006*math.sin(math.pi*t),bagz+.105-t*.10),'leather','spine',thickness=.002)
 m.tube([(bagx-.068,bagy-.062,bagz+.105),(bagx-.068,bagy-.062,bagz-.09),(bagx+.068,bagy-.062,bagz-.09),(bagx+.068,bagy-.062,bagz+.105)],.002,'silver','spine',7)
 m.ellipsoid((bagx,bagy-.066,bagz+.020),(.009,.004,.017),'gold','spine',12,8)
 if level in [2,4]:
  # Intermediate ranks add physical reinforced satchel corners; the principal
  # costume stages are still base / cotton gauntlets / sheep-emblem master.
  for sign in [-1,1]:
   m.tube([(bagx+sign*.046,bagy-.063,bagz-.073),(bagx+sign*.065,bagy-.063,bagz-.073),(bagx+sign*.065,bagy-.063,bagz-.047)],.003,'gold','spine',8)
  if level==4:
   m.tube([(bagx-.055,bagy-.063,bagz+.070),(bagx+.055,bagy-.063,bagz+.070)],.0028,'white','spine',8)
 def satchel_strap(t,u):
  z=top-.20-(top-.20-bagz-.08)*t
  phase=max(0,min(1,(z-hem)/max(.001,torso_top-hem)))
  rx=float(np.interp(phase,[0,.25,.60,.82,1],[.272,.250,.225,.255,.087]))
  ry=float(np.interp(phase,[0,.35,.75,1],[.184,.182,.170,.090]))
  x=-.17+.375*t+(u-.5)*.026
  y=-.015-ry*math.sqrt(max(.03,1-(x/rx)**2))-.008
  attachment=max(0,(t-.86)/.14)
  y=y*(1-attachment)+(bagy-.060)*attachment
  return x,y,z
 m.patch(32,3,satchel_strap,'leather',lambda t,u:{'chest':1-t,'spine':t},thickness=.002)
 # Three stages gain stitched cotton motifs and a small sheep-shaped charm.
 if stage>=2:
  c=Vector((bagx,bagy-.071,bagz-.04))
  def wool(t,u):
   ph=math.pi*(.001+.998*t);a=TAU*u;r=1+.08*math.cos(a*9)*math.sin(ph*5)**2
   return tuple(c+Vector((.045*math.sin(ph)*math.cos(a)*r,-.026*math.sin(ph)*math.sin(a)*r,.05*math.cos(ph))))
  m.patch(20,40,wool,'white','spine')
  m.ellipsoid(tuple(c+Vector((0,-.028,.008))),(.021,.013,.027),'accent','spine',20,12)
  for sign in [-1,1]:
   m.ellipsoid(tuple(c+Vector((sign*.016,-.040,.016))),(.003,.002,.004),'black','spine',10,6)
   m.tube([tuple(c+Vector((sign*.014,-.011,.027))),tuple(c+Vector((sign*.032,-.016,.012))),tuple(c+Vector((sign*.024,-.024,.005)))],.007,'gold','spine',10)
 return top,waist

def garments(m,body,p,hero,level,scale):
 if hero=='charmy':return charmy_garments(m,body,p,level,scale)
 cfg=HEROES[hero];female=cfg['female'];stage=0 if level<3 else (1 if level<5 else 2)
 waist=body[list(GROUPS['joint-pelvis'])].mean(axis=0)[2]+.12
 shirt_hem=float(RAW[list(GROUPS['joint-pelvis']),1].mean())+.12/scale-.10
 def torso(x,h,d):return shirt_hem<h<5.90 and abs(x)<(1.95 if female else 1.70)
 forearm_planes=[]
 for side in ['l','r']:
  e=RAW[list(GROUPS['joint-'+side+'-elbow'])].mean(axis=0)
  w=RAW[list(GROUPS['joint-'+side+'-hand'])].mean(axis=0)
  forearm_planes.append((e,w-e,side))
 def sleeve_phase(x,h,d):
  e,axis,side=forearm_planes[0 if x>0 else 1]
  return float(np.dot(np.array((x,h,d))-e,axis)/np.dot(axis,axis))
 def arms(x,h,d):return abs(x)>1.25 and 2.25<h<5.95 and sleeve_phase(x,h,d)<.84
 def cuff_boundary(i,point,boundary):
  x,h,d=RAW[i];phase=sleeve_phase(x,h,d)
  if not boundary or phase<.60:return point
  side='l' if x>0 else 'r'
  elbow=Vector(body[list(GROUPS['joint-'+side+'-elbow'])].mean(axis=0));wrist=Vector(body[list(GROUPS['joint-'+side+'-hand'])].mean(axis=0))
  axis=(wrist-elbow).normalized();q=Vector(point);center=elbow.lerp(wrist,.82)
  return tuple(q-axis*(q-center).dot(axis))
 body_surface=body[sorted(BODY_SET)]
 def cloth_drape(i,point,boundary):
  x,y,z=point
  # A woven bodice bridges the chest instead of copying individual nipples and
  # breast separation from the anatomical mesh underneath it.
  if 2.7<RAW[i,1]<5.5 and abs(x)<.27 and y<-.035:
   section=body_surface[(np.abs(body_surface[:,2]-z)<.10)&(np.abs(body_surface[:,0])<.29)]
   if len(section):
    front=float(np.min(section[:,1]))-.035+.07*(abs(x)/.29)**4
    y=min(y,front)
  return x,y,z
 def tailored_torso(material):
  # A smooth sewn envelope prevents anatomical sampling rows from making
  # stair-step ridges and jagged intersections at the shoulders/neck.
  neck_z=float(body[list(GROUPS['joint-neck']),2].mean())
  bottom=waist+.23 if hero=='vanessa' else waist-.145 if hero=='asta' else waist-.035
  upper=neck_z-.19 if hero=='vanessa' else neck_z-.09 if hero in ['asta','magna'] else neck_z-.015
  steps=np.linspace(0,1,41);fronts=[];backs=[]
  for t in steps:
   z=bottom+(upper-bottom)*t
   limit=.25 if hero=='vanessa' else .25-.12*t**5
   section=body_surface[(np.abs(body_surface[:,2]-z)<.045)&(np.abs(body_surface[:,0])<limit)]
   fronts.append(float(np.percentile(section[:,1],2))-.030 if len(section) else -.15)
   backs.append(float(np.percentile(section[:,1],98))+.025 if len(section) else .12)
  # Interpolation alone cannot smooth the abrupt transition to neck topology.
  for _ in range(3):
   for values in [fronts,backs]:
    previous=values.copy()
    for k in range(1,len(values)-1):values[k]=previous[k]*.5+(previous[k-1]+previous[k+1])*.25
  m.bodice_front_at_z=lambda z:float(np.interp((z-bottom)/max(.001,upper-bottom),steps,fronts))
  def point(t,u):
   z=bottom+(upper-bottom)*t
   front=float(np.interp(t,steps,fronts));back=float(np.interp(t,steps,backs))
   if hero=='vanessa':rx=.215+.025*math.sin(math.pi*t)
   else:rx=float(np.interp(t,[0,.30,.68,.86,1],[.215,.202,.242,.275,.095]))
   if hero=='asta' and t<.36:
    hip=body_surface[(np.abs(body_surface[:,2]-z)<.045)&(np.abs(body_surface[:,0])<.38)]
    if len(hip):
     hip_width=float(np.abs(hip[:,0]).max())+.025
     rx=max(rx,hip_width*(1-min(1,t/.36))+.215*min(1,t/.36))
   ry=(back-front)*.5;cy=(front+back)*.5;a=u*TAU
   fold=.0025*math.sin(8*a+1.8*t)*math.sin(math.pi*t)
   if hero=='vanessa':z-=.045*max(0,math.cos(a))**4*t**4
   cosine=math.cos(a);front_curve=math.copysign(abs(cosine)**.55,cosine)
   return (math.sin(a)*(rx+fold),cy-front_curve*(ry+fold),z)
  m.patch(36,80,point,material,lambda t,u:{'spine':1-t,'chest':t},thickness=.0025)
 # Clothes are fitted continuous shells of anatomical quad topology with skin weights.
 if hero in ['asta','magna']:
  tailored_torso('white')
  m.shell(body,p,arms,'cloth',.025,.004,adjust=cuff_boundary)
 elif hero=='yuno':
  tailored_torso('cloth');m.shell(body,p,arms,'cloth',.026,.004,adjust=cuff_boundary)
 elif hero=='noelle':
  tailored_torso('white');m.shell(body,p,arms,'white',.036,.006,adjust=cuff_boundary)
 elif hero=='vanessa':
  tailored_torso('cloth')
  # Long fingerless gloves end at the wrist. A rectangular height mask also
  # swallowed part of the hands, producing mitten-shaped protrusions in Idle.
  m.shell(body,p,lambda x,h,d:abs(x)>2.1 and .08<sleeve_phase(x,h,d)<1.025,'cloth',.020,.003)
 if hero=='magna':
  # Magna's open, dark jacket is distinct from Asta's white tunic. Tailored
  # front panels, an open V and metal zip teeth surround the undershirt.
  neck_z=float(body[list(GROUPS['joint-neck']),2].mean())
  for side in [-1,1]:
   def jacket_point(t,u,side=side):
    z=waist-.035+(neck_z-waist-.055)*t
    inner=.012+.078*t*t
    x=side*(inner+u*(.195-inner)+.018*math.sin(t*math.pi))
    section=body_surface[(np.abs(body_surface[:,2]-z)<.07)&(np.abs(body_surface[:,0])<.29)]
    y=float(section[:,1].min())-.035 if len(section) else -.18
    return (x,y+.042*u*u,z)
   m.patch(24,16,jacket_point,'cloth',lambda t,u:{'spine':1-t,'chest':t})
   m.tube([jacket_point(t,0) for t in np.linspace(0,1,25)],.0032,'silver','chest',7)
 if hero=='yuno':
  # Long, fitted double-breasted uniform beneath the separate cape.
  m.patch(18,72,lambda t,u:((.220+.023*t)*math.sin(.08+u*(TAU-.16)),
       -.175*math.cos(.08+u*(TAU-.16)),waist+.045-t*.43),'cloth','spine')
 if female:
  # Keep the fitted underlayer above the pleated skirt. A long shared leg
  # mask made Noelle's separate skirt read as two bicycle-short legs.
  shorts_hem=-.72
  m.shell(body,p,lambda x,h,d:shorts_hem<h<1.6 and abs(x)<1.95,'cloth' if hero=='vanessa' else 'accent',.022,.003,hem=shorts_hem)
 if not female:
  hem=-5.0 if hero=='asta' else -6.35
  m.shell(body,p,lambda x,h,d:h<shirt_hem+.30 and h>hem and abs(x)<3.20,'pants',.025,.006,hem=hem)
  boot_top={'asta':-6.1,'yuno':-4.65,'magna':-4.55}[hero]
  m.shell(body,p,lambda x,h,d:-7.65<h<boot_top,'main',.021,.003,hem=boot_top)

 elif hero=='vanessa':
  boot_top=-3.25
  m.shell(body,p,lambda x,h,d:-7.45<h<boot_top,'cloth',.020,.003,hem=boot_top)
 # Separate cuff pattern, with a stable circular opening around the forearm.
 if hero!='vanessa':
  for side in ['l','r']:
   elbow=Vector(body[list(GROUPS['joint-'+side+'-elbow'])].mean(axis=0));wrist=Vector(body[list(GROUPS['joint-'+side+'-hand'])].mean(axis=0))
   center=elbow.lerp(wrist,.82);axis=(wrist-elbow).normalized();u=axis.cross(Vector((0,1,0))).normalized();v=axis.cross(u).normalized()
   m.patch(4,40,lambda t,a,c=center,u=u,v=v,axis=axis:tuple(c+axis*(t-.5)*.080+(u*math.cos(a*TAU)+v*math.sin(a*TAU))*.059),'white','forearm.'+side.upper())
 # Closed shoes for the booted heroes; Noelle's own sandals are built below.
 for side in ([] if hero=='noelle' else ['l','r']):
  ankle=Vector(body[list(GROUPS['joint-'+side+'-ankle'])].mean(axis=0))
  toe=Vector(body[list(GROUPS['joint-'+side+'-foot-2'])].mean(axis=0))
  sign=1 if side=='l' else -1
  foot_front=min(body[i,1] for i in GROUPS['body'] if RAW[i,1]<-7.4 and RAW[i,0]*sign>0)-.008
  x=ankle.x;v=[];f=[]
  for y,w,h in [(ankle.y+.065,.042,.08),(ankle.y+.025,.067,.14),(ankle.y-.06,.070,.11),(foot_front+.055,.074,.075),(foot_front,.028,.045)]:
   for j in range(24):
    a=TAU*j/24;v.append((x+w*math.cos(a),y,.045+h*(.5+.5*math.sin(a))))
  for i in range(4):
   for j in range(24):a=i*24+j;b=i*24+(j+1)%24;f.append((a,b,b+24,a+24))
  f.extend([tuple(range(23,-1,-1)),tuple(range(96,120))]);m.add(v,f,'main' if hero!='vanessa' else 'cloth','foot.'+side.upper())
 # Independent shoulder construction, fitted front opening and long
 # back/side drape for Yuno. Geometry is closed on the inside.
 neck_z=body[list(GROUPS['joint-neck'])].mean(axis=0)[2]
 top,bottom,crest=add_mantle(m,body,hero,stage,GROUPS)
 m.costume_crest=crest
 collar=top+.015
 # A closed standing collar bridges the neckline; it also covers the overlap
 # where the separately patterned tunic and shoulder mantle meet.
 if hero!='vanessa':
  neck_section=body_surface[(np.abs(body_surface[:,2]-(neck_z+.01))<.035)&(np.abs(body_surface[:,0])<.14)]
  neck_front=float(neck_section[:,1].min())-.008 if len(neck_section) else -.095
  neck_back=float(neck_section[:,1].max())+.008 if len(neck_section) else .065
  neck_cy=(neck_front+neck_back)*.5;neck_ry=(neck_back-neck_front)*.5
  neck_rx=max(abs(neck_section[:,0]))+.008 if len(neck_section) else .085
  opening=.48 if hero in ['asta','magna'] else .12
  m.patch(7,64,lambda t,u:(math.sin(opening+u*(TAU-2*opening))*(neck_rx+.025*(1-t)),neck_cy-math.cos(opening+u*(TAU-2*opening))*(neck_ry+.020*(1-t)),neck_z-.045+t*.070),'cloth' if hero in ['asta','magna','yuno'] else 'white','neck',thickness=.0025)
 # Waist belt shell with distinct engraved metal buckle and utility pouch.
 waist_section=body_surface[(np.abs(body_surface[:,2]-waist)<.04)&(np.abs(body_surface[:,0])<.31)]
 belt_rx=max(.235,max(abs(waist_section[:,0]))+.045)
 belt_front=float(waist_section[:,1].min())-.055;belt_back=float(waist_section[:,1].max())+.045
 belt_cy=(belt_front+belt_back)/2;belt_ry=(belt_back-belt_front)/2
 m.patch(3,64,lambda t,u:(math.sin(TAU*u)*belt_rx,belt_cy-math.cos(TAU*u)*belt_ry,waist+(t-.5)*.070),'leather','spine')
 for x in [-.034,.034]:m.tube([(x,belt_front-.006,waist-.03),(x,belt_front-.006,waist+.03)],.005,'silver' if hero=='magna' else 'gold','spine',8)
 for z in [-.03,.03]:m.tube([(-.034,belt_front-.006,waist+z),(.034,belt_front-.006,waist+z)],.005,'gold','spine',8)
 if hero in ['asta','noelle','vanessa']:
  # A closed leather grimoire satchel, with a fitted flap and side seams.
  verts=[];faces=[];rings=28
  for z,rx,ry in [(waist-.02,.047,.065),(waist-.05,.049,.069),(waist-.22,.045,.062),(waist-.25,.035,.051)]:
   for j in range(rings):
    a=TAU*j/rings;verts.append((.21+rx*math.cos(a),.035+ry*math.sin(a),z))
  for row in range(3):
   for j in range(rings):
    a=row*rings+j;b=row*rings+(j+1)%rings;faces.append((a,b,b+rings,a+rings))
  faces.extend([tuple(range(rings-1,-1,-1)),tuple(range(3*rings,4*rings))])
  m.add(verts,faces,'leather','spine')
  m.patch(12,14,lambda t,u:(.21+(u-.5)*.087,-.036-.006*math.sin(math.pi*t),waist-.026-.092*t+.014*(2*u-1)**2),'leather','spine',thickness=.002)
  m.tube([(.21,-.046,waist-.052),(.21,-.046,waist-.138)],.007,'leather','spine',8)
  for x in [.201,.219]:m.tube([(x,-.051,waist-.094),(x,-.051,waist-.116)],.0025,'gold','spine',6)
  for z in [-.094,-.116]:m.tube([(.201,-.051,waist+z),(.219,-.051,waist+z)],.0025,'gold','spine',6)
  for side in [-1,1]:m.tube([(.21+side*.043,-.023,waist-.06),(.21+side*.039,-.020,waist-.218),(.21+side*.028,-.014,waist-.243)],.0016,'gold','spine',6)
 if hero=='yuno':
  for z in np.linspace(waist-.23,top-.16,6):
   section=body_surface[(np.abs(body_surface[:,2]-z)<.08)&(np.abs(body_surface[:,0])<.20)]
   front=float(section[:,1].min())-.040 if len(section) else -.19
   for x in [-.065,.065]:m.ellipsoid((x,front,float(z)),(.012,.007,.012),'gold','chest' if z>waist+.12 else 'spine',12,8)
 if hero=='noelle':
  add_noelle_skirt_and_gaiters(m,body,RAW,GROUPS,waist)
 if hero=='vanessa':
  m.patch(20,32,lambda t,u:((u-.5)*(.35+.33*t),.07+.1*math.sin(math.pi*u)+.08*t,waist-.64*t),'cloth','cape')
 add_costume_details(m,body,hero,level,top,waist,GROUPS,RAW)
 # Rank changes are sewn into the individual costume: antimagic sleeve,
 # leaf embroidery, riveted gloves, Valkyrie plates or Rouge charm.
 add_rank_details(m,body,RAW,hero,level,top,waist,GROUPS)
 return top,waist

def face_hair(m,body,hero,level):
 cfg=HEROES[hero];profile=ANIME_HEAD_PROFILES[hero]
 head_center=Vector(body[list(GROUPS['joint-head'])].mean(axis=0))
 face_surface=BVHTree.FromPolygons([Vector(v) for v in body],[[q[0] for q in f] for group,f in FACES if group=='body'])
 eye_centers=[]
 for side in ['l','r']:
  helper=body[list(GROUPS['helper-'+side+'-eye'])]
  lower=body[list(GROUPS['helper-'+side+'-eyelashes-1'])]
  upper=body[list(GROUPS['helper-'+side+'-eyelashes-2'])]
  center=Vector((helper.min(axis=0)+helper.max(axis=0))*.5)
  eye_bone='eye.'+side.upper();sign=1 if side=='l' else -1
  # Construct a closed, curved eyeball volume from the actual eyelid guides.
  # A full untrimmed sphere exposed white crescents below the female sockets.
  # The anatomical aperture is now the boundary of the sclera, from all views.
  xmin=max(float(lower[:,0].min()),float(upper[:,0].min()))
  xmax=min(float(lower[:,0].max()),float(upper[:,0].max()))
  eye_width=(xmax-xmin)*.5;center.x=(xmin+xmax)*.5
  edge_fits=[]
  for guide in [lower,upper]:
   q=(guide[:,0]-center.x)/max(.001,eye_width)
   edge_fits.append((np.polyfit(q,guide[:,2],4),np.polyfit(q,guide[:,1],3)))
  def eye_edges(q):
   low_z=float(np.polyval(edge_fits[0][0],q));up_z=float(np.polyval(edge_fits[1][0],q))
   low_y=float(np.polyval(edge_fits[0][1],q));up_y=float(np.polyval(edge_fits[1][1],q))
   mid=(low_z+up_z)*.5;half=max(.0001,(up_z-low_z)*.5*max(0,1-abs(q)**3)**.18)
   return mid-half,mid+half,low_y,up_y
  lo,hi,_,_=eye_edges(0);center.z=(lo+hi)*.5;eye_height=(hi-lo)*.5
  def eye_point(t,u):
   q=(u-.5)*2;lo,hi,ly,uy=eye_edges(q)
   y=ly+(uy-ly)*t-.0018*math.sin(t*math.pi)*math.sqrt(max(0,1-q*q))+.0045
   x=xmin+(xmax-xmin)*u;z=lo+(hi-lo)*t
   hit,_,_,_=face_surface.ray_cast(Vector((x,-3,z)),Vector((0,1,0)),6)
   # Lash helpers protruded 7-10mm past the actual outer socket. A body hit
   # close to the guide is the front skin and masks the shell from profile;
   # a much deeper hit is the open socket/back of the head and is preserved.
   if hit is not None and abs(hit.y-y)<.028:y=max(y,hit.y+.0007)
   return (x,y,z)
  eye_verts=[];eye_faces=[];eye_uv=[];rows=24;cols=48
  for r in range(rows+1):
   for c in range(cols+1):eye_verts.append(eye_point(r/rows,c/cols));eye_uv.append((c/cols,r/rows))
  front_count=len(eye_verts)
  eye_verts.extend((x,y+.016,z) for x,y,z in eye_verts.copy());eye_uv+=eye_uv.copy()
  for r in range(rows):
   for c in range(cols):
    a=r*(cols+1)+c;face=(a,a+1,a+cols+2,a+cols+1)
    eye_faces.extend([face,tuple(i+front_count for i in reversed(face))])
  perimeter=list(range(cols+1))+[r*(cols+1)+cols for r in range(1,rows+1)]+list(range(rows*(cols+1)+cols-1,rows*(cols+1)-1,-1))+[r*(cols+1) for r in range(rows-1,0,-1)]
  for j,a in enumerate(perimeter):
   b=perimeter[(j+1)%len(perimeter)];eye_faces.append((a,b,b+front_count,a+front_count))
  m.add(eye_verts,eye_faces,'eye',eye_bone,eye_uv)
  center.y=eye_point(.5,.5)[1]
  eye_centers.append(center)
  iris_height=min(eye_height*.91,eye_width*.63)
  iris_width=min(iris_height*.78,eye_width*.46)
  def curved_disc(rx,rz,material):
   verts=[];uv=[];faces=[];segments=48;rings=12
   for ring in range(rings+1):
    radius=ring/rings
    for j in range(segments+1):
     a=TAU*j/segments;dx=rx*radius*math.cos(a);dz=rz*radius*math.sin(a)
     q=max(-.999,min(.999,dx/max(.001,eye_width)));lo,hi,_,_=eye_edges(q)
     z=max(lo+.0002,min(hi-.0002,center.z+dz))
     t=(z-lo)/max(.001,hi-lo);u=(center.x+dx-xmin)/max(.001,xmax-xmin)
     x,y,_=eye_point(t,u);y-=.0010 if material=='black' else .0007
     verts.append((x,y,z));uv.append((.5+.5*radius*math.cos(a),.5+.5*radius*math.sin(a)))
   for ring in range(rings):
    for j in range(segments):
     a=ring*(segments+1)+j;faces.append((a,a+1,a+segments+2,a+segments+1))
   m.add(verts,faces,material,eye_bone,uv)
  curved_disc(iris_width,iris_height,'iris')
  curved_disc(iris_width*.46,iris_height*.48,'black')
  m.ellipsoid(tuple(center+Vector((-eye_width*.10,-.0014,eye_height*.22))),(.0015,.0005,.0019),'eye',eye_bone,12,8)
  # Black Clover eyes are defined by angular eyelid edges, not detached white
  # spheres. Follow the actual morphed lash guide and project onto the skin.
  for is_upper,guide in [(True,upper),(False,lower)]:
   path=[]
   for t in np.linspace(0,1,29):
    x=xmin+(xmax-xmin)*t
    lo,hi,ly,uy=eye_edges((t-.5)*2)
    z=hi if is_upper else lo;y=(uy if is_upper else ly)-.0007
    hit,_,_,_=face_surface.ray_cast(Vector((x,-3,z)),Vector((0,1,0)),6)
    if hit is not None and abs(hit.y-y)<.028:y=hit.y-.0007
    path.append((x,y,z))
   thickness=.0018 if is_upper else .00075
   if hero in ['vanessa','noelle']:thickness*=1.35 if is_upper else 1.0
   if hero=='asta' and is_upper:thickness*=1.15
   radii=[max(.00035,thickness*(.40+.60*math.sin(math.pi*(.08+.84*t)))) for t in np.linspace(0,1,29)]
   m.tube(path,radii,'black','head',8)
   if is_upper and hero in ['vanessa','noelle']:
    outer=Vector(path[-1] if sign>0 else path[0])
    for k in range(2):
     m.tube([tuple(outer+Vector((0,0,-k*.002))),tuple(outer+Vector((sign*(.006+.003*k),-.001,.004+.002*k)))],[.0015,.0003],'black','head',7)
  # Individual brow angles: Asta's sharp determination, Yuno's level gaze,
  # Vanessa's arch, Noelle's raised outer brow, Charmy's soft round expression.
  brow=[];brow_width=eye_width*(1.03 if hero in ['asta','yuno'] else .95)
  for t in np.linspace(0,1,23):
   q=(t-.5)*2;x=center.x+q*brow_width
   offset={"asta":.017,"yuno":.015,"magna":.015,"vanessa":.018,"noelle":.020,"charmy":.023}[hero]
   z=center.z+eye_height+offset
   if hero=='asta':z+=sign*q*.007
   elif hero=='yuno':z+=sign*q*.0035
   elif hero=='vanessa':z+=.007*math.sin(math.pi*t)+sign*q*.003
   elif hero=='charmy':z+=.006*math.sin(math.pi*t)
   else:z+=.004*math.sin(math.pi*t)+sign*q*.003
   hit,_,_,_=face_surface.ray_cast(Vector((x,-3,z)),Vector((0,1,0)),6)
   y=hit.y-.0026 if hit is not None else center.y-.001
   brow.append((x,y,z))
  thick=.0026 if hero=='asta' else .0022 if hero in ['yuno','magna'] else .0015
  m.tube(brow,[max(.00035,thick*math.sin(math.pi*(.10+.80*t))) for t in np.linspace(0,1,23)],'hair' if hero=='asta' else 'black','head',8)
 # Fit the scalp to the deformed head. The rear hairline reaches the nape;
 # a closed cap and under-layer avoid bald gaps when viewed from the side.
 eye_z=sum(c.z for c in eye_centers)/2
 top=max(body[i][2] for i in GROUPS['body'])
 band_z=eye_z+(.068 if hero=='asta' else .075)
 scalp=np.array([body[i] for i in GROUPS['body'] if abs(body[i,2]-band_z)<.018])
 band_rx=max(abs(scalp[:,0]))+.006
 band_cy=(scalp[:,1].min()+scalp[:,1].max())*.5
 band_ry=(scalp[:,1].max()-scalp[:,1].min())*.5+.006
 rx=band_rx;ry=band_ry;cy=band_cy
 def hairline(a):
  front=max(0,math.cos(a))
  back=eye_z-(.070 if hero in ['asta','yuno'] else .030)
  if hero=='magna':
   return eye_z+.045+max(0,math.cos(a))*(.020+.065*abs(math.sin(a))**.7)
  return back+(band_z+.015-back)*front
 def cap(t,u):
  a=TAU*u;e=t*math.pi*.5
  point=Vector((math.sin(a)*rx*1.018*math.cos(e),cy-math.cos(a)*ry*1.018*math.cos(e),hairline(a)+(top+.005-hairline(a))*math.sin(e)))
  normal=Vector((math.sin(a)*math.cos(e),-math.cos(a)*math.cos(e),math.sin(e)))
  hit,_,_,_=face_surface.ray_cast(point+normal*.30,-normal,.60)
  if hit is not None and hit.z>eye_z-.13:point=hit+normal*.007
  # Shallow combed ridges keep the supporting scalp from reading as a helmet.
  ridge=.0035*(.5+.5*math.cos(a*(15 if hero in ['asta','yuno'] else 19)+e*1.7))**3*math.sin(math.pi*t)
  point+=normal*ridge
  return tuple(point)
 scalp_face_start=len(m.f)
 m.patch(26,96,cap,'hair','head',thickness=.002)
 if hero=='magna':
  for face_index in range(scalp_face_start,len(m.f)):
   c=np.array([m.v[i] for i in m.f[face_index]]).mean(axis=0)
   if abs(c[0])<.036 and c[1]<cy+.035:m.m[face_index]='black'
 def hair_path(points,width,depth,material='hair'):
  # Closed, tapered elliptical locks. Tangent and radial frames give each
  # strand real thickness from front/profile/back instead of flat triangles.
  pts=[Vector(p) for p in points];verts=[];faces=[];uv=[];sides=12;previous_u=None
  for i,p in enumerate(pts):
   t=i/(len(pts)-1);tangent=(pts[min(i+1,len(pts)-1)]-pts[max(0,i-1)]).normalized()
   radial=Vector((p.x,p.y-cy,max(0,p.z-eye_z)*.25))
   if radial.length<.001:radial=Vector((0,-1,0))
   radial.normalize();u=tangent.cross(radial) if previous_u is None else previous_u-tangent*previous_u.dot(tangent)
   if u.length<.01:u=tangent.cross(Vector((0,0,1)))
   if u.length<.01:u=tangent.cross(Vector((1,0,0)))
   u.normalize()
   if previous_u is not None and u.dot(previous_u)<0:u=-u
   previous_u=u.copy();v=u.cross(tangent).normalized()
   # Roots taper under the scalp instead of displaying oval end caps.
   p=p-radial*.016*(1-t)**6
   taper=max(.002,math.sin(math.pi*(.035+.965*t))**.52*(1-.70*t))
   for j in range(sides):
    a=TAU*j/sides
    ridge=1+.12*max(0,math.sin(a))**4
    verts.append(tuple(p+u*(math.cos(a)*width*taper)+v*(math.sin(a)*depth*taper*ridge)))
    uv.append((j/sides,t))
  for i in range(len(pts)-1):
   for j in range(sides):a=i*sides+j;b=i*sides+(j+1)%sides;faces.append((a,b,b+sides,a+sides))
  faces.extend([tuple(range(sides-1,-1,-1)),tuple((len(pts)-1)*sides+j for j in range(sides))])
  m.add(verts,faces,material,'head',uv)
 def lock(points,width,depth,material='hair',front_band=False):
  p=[Vector(q) for q in points]
  curve=[]
  for t in np.linspace(0,1,23):
   point=p[0]*(1-t)**3+p[1]*3*t*(1-t)**2+p[2]*3*t*t*(1-t)+p[3]*t**3
   if front_band and abs(point.z-band_z)<.070:
    band_y=cy-(ry+.011)*math.sqrt(max(.08,1-(point.x/(rx+.011))**2))-.008
    point.y=band_y
   curve.append(tuple(point))
  hair_path(curve,width,depth,material)
 def scalp_lock(a,root,end,reach,lift,width,depth):
  # An entire lock follows the scalp before leaving it. This hides its root
  # beneath adjacent locks, rather than attaching a little leaf to a helmet.
  path=[]
  for t in np.linspace(0,1,37):
   theta=a+.11*math.sin(math.pi*t)
   start=root;finish=end
   if hero=='asta':
    # Upper clumps start above the complete wrapped headband. The rear
    # scalp also covers the nape, so a constant cap parameter alone put
    # the back clump roots below the band and created hanging cones.
    h0=hairline(theta)
    minimum=math.asin(max(0,min(.96,(band_z+.025-h0)/max(.001,top+.005-h0))))/(math.pi*.5)
    start=max(root,minimum);finish=max(end,min(.98,start+.13))
   p=Vector(cap(start+(finish-start)*t,theta/TAU))
   normal=Vector((math.sin(theta),-math.cos(theta),.25)).normalized()
   emergence=max(0,(t-.38)/.62)**1.7
   p+=normal*(reach*emergence)+Vector((0,0,lift*emergence))
   p-=normal*.006*(1-t)**3
   path.append(tuple(p))
  hair_path(path,width,depth)
 if hero=='asta':
  # Broad, interlocking silver spikes with roots buried in the scalp. The
  # front is a separated asymmetrical fringe rather than a row of short fins.
  for k in range(21):
   a=TAU*k/21+.08
   scalp_lock(a,.10,.79+.055*math.sin(k*1.8),.031+.009*math.sin(k*2.3),.019+.011*math.sin(k*1.3),.033,.010)
  for k in range(17):
   a=.60+(TAU-1.20)*k/16
   scalp_lock(a,.015,.48+.045*math.sin(k*1.7),.035,.010,.027,.009)
  lock([(-.012,cy+.010,top-.014),(-.026,cy+.012,top+.016),(-.024,cy+.018,top+.047),(.002,cy+.024,top+.055)],.023,.009)
  lock([(.012,cy+.018,top-.015),(.020,cy+.025,top+.012),(.034,cy+.032,top+.029),(.050,cy+.040,top+.018)],.023,.008)
  fringe=[(-.112,-.140,.036),(-.078,-.104,.022),(-.033,-.047,.006),(.004,.025,.012),(.047,.082,.025),(.099,.137,.041)]
  for k,(x,endx,endz) in enumerate(fringe):
   root=(x*.78,cy-ry-.007,band_z-.023)
   lock([root,(x,cy-ry-.018,band_z-.018),(endx,cy-ry-.024,eye_z+endz+.018),(endx,cy-ry-.020,eye_z+endz)],.014 if k!=2 else .018,.0055,front_band=True)
  for side in [-1,1]:
   for k in range(4):
    lock([(side*rx*.87,cy+.010+k*.028,band_z+.005),(side*rx*1.06,cy+.016+k*.029,eye_z+.038),(side*rx*1.14,cy+.025+k*.03,eye_z-.025),(side*rx*(1.14-k*.05),cy+.032+k*.032,eye_z-.045-k*.015)],.024,.010)
 elif hero=='yuno':
  for k in range(21):
   a=TAU*k/21+.06
   scalp_lock(a,.93,.19+.04*math.sin(k*1.7),.017,.004+.007*math.sin(k*2.0),.028,.008)
  for k in range(13):
   a=.66+(TAU-1.32)*k/12
   scalp_lock(a,.73,.17,.021,.006,.025,.008)
  fringe=[(-.094,-.123,.007),(-.055,-.083,.043),(-.020,-.027,.003),(.017,.033,.021),(.057,.090,.039),(.092,.123,.004)]
  for k,(x,endx,endz) in enumerate(fringe):
   root=cap(.77,(math.asin(max(-.8,min(.8,x/rx*.62)))%TAU)/TAU)
   lock([root,(x-.016,cy-ry*.78,top-.024),(endx,cy-ry-.008,eye_z+endz+.055),(endx,cy-ry-.007,eye_z+endz)],.030 if k in [2,3] else .028,.009)
  lock([(-.023,cy+.016,top-.016),(-.036,cy+.020,top+.021),(-.027,cy+.022,top+.040),(-.004,cy+.026,top+.048)],.024,.009)
  lock([(-.009,cy+.021,top-.017),(.009,cy+.025,top+.020),(.010,cy+.029,top+.026),(.026,cy+.033,top+.021)],.020,.008)
  for side in [-1,1]:
   for k in range(3):
    lock([(side*rx*.83,cy+.018+k*.025,band_z-.018),(side*rx*1.02,cy+.035+k*.027,eye_z+.018),(side*rx*1.10,cy+.048+k*.030,eye_z-.060),(side*rx*(1.05-k*.045),cy+.050+k*.032,eye_z-.095-k*.018)],.026,.011)
 elif hero=='magna':
  for side in [-1,1]:
   for k in range(10):
    a=side*(.30+.22*k)
    scalp_lock(a,.08+.018*k,.87,.012,.025-.001*k,.026,.008)
  for k in range(3):
   a=(k-1)*.10;path=[]
   for t in np.linspace(0,1,37):
    p=Vector(cap(min(.97,t*1.10),a/TAU))
    p+=Vector((.005*math.sin(math.pi*t),.018*t*t,max(0,(t-.70)/.30)*(.047-k*.006)))
    path.append(tuple(p))
   hair_path(path,.029-k*.003,.009,'black')
 elif hero=='vanessa':
  # A continuous waved hair mass avoids a wig assembled from thick ribbons.
  # The separate thin locks merely articulate the main three-dimensional shape.
  def waved_volume(t,u):
   a=.77+(TAU-1.54)*u
   if t<=.34:
    p=Vector(cap(.995*(1-t/.34),a/TAU))
   else:
    s=(t-.34)/.66;p=Vector(cap(0,a/TAU))
    wave=.028*math.sin(s*math.pi*2.8+math.sin(a)*.7)*math.sin(s*math.pi*.85)
    p.x+=math.sin(a)*(.010*s+wave)
    p.y+=-math.cos(a)*(.012*s+wave*.60)+.021*s
    p.z-=.43*s
   return tuple(p)
  m.patch(45,88,waved_volume,'hair','head',thickness=.013)
  for k in range(19):
   u=k/18
   path=[]
   for t in np.linspace(0,1,43):
    p=Vector(waved_volume(t,u))
    radial=Vector((p.x,p.y-cy,0)).normalized()
    p+=radial*.004
    p.z-=.016*math.sin(k*1.7)*t
    path.append(tuple(p))
   hair_path(path,.014,.007)
  for k in range(4):
   root=cap(.90-k*.025,(-.42+k*.045)%TAU/TAU)
   tip=(rx*(.60+.06*k),cy-ry*.89,eye_z+.055-.015*k)
   lock([root,(-rx*.015,cy-ry*.80,top+.010),(.12,cy-ry*1.03,eye_z+.145),tip],.030-k*.002,.010)
  for side in [-1,1]:
   for k in range(2):
    path=[]
    for t in np.linspace(0,1,39):
     path.append((side*(rx*.87+(.018+.018*t)*math.sin(t*math.pi*2.2+k*.55)),cy-ry*.57+.020*t,eye_z+.13-t*(.385+.020*k)))
    hair_path(path,.021,.010)
 elif hero=='noelle':
  for k in range(10):
   x=(k-4.5)*rx*.162
   endz=eye_z+.081+.012*(abs(k-4.5)/4.5)**1.5
   lock([(x*.62,cy-ry*.24,top-.025),(x*.88,cy-ry*.78,top-.016),(x*1.04,cy-ry-.012,endz+.034),(x*1.04,cy-ry-.010,endz)],rx*.115,.008)
  for side in [-1,1]:
   tie=Vector((side*rx*1.015,cy+.024,eye_z+.070))
   def tail(t,u,s=side,c=tie):
    a=TAU*u
    radius=.046*math.sin(math.pi*(.06+.94*t))**.48
    center=c+Vector((s*(.020+.047*math.sin(math.pi*t)),.055*t,-.585*t))
    return tuple(center+Vector((math.cos(a)*radius,math.sin(a)*radius*.77,0)))
   m.patch(42,56,tail,'hair','head')
   for k in range(5):
    a=TAU*k/5;path=[]
    for t in np.linspace(0,1,39):
     p=Vector(tail(t,k/5))
     p+=Vector((math.cos(a)*.003,math.sin(a)*.003,0))
     path.append(tuple(p))
    hair_path(path,.012,.006)
   lock([(side*rx*.70,cy-ry*.47,top-.030),(side*rx*1.02,cy-ry*.65,eye_z+.075),(side*rx*1.03,cy-ry*.53,eye_z-.045),(side*rx*.97,cy-ry*.44,eye_z-.115)],.024,.009)
   for direction in [-1,1]:
    def bow(t,u,s=side,d=direction,c=tie):
     width=.057*math.sin(math.pi*(.07+.78*t))
     return tuple(c+Vector((s*(.009+.061*t),-.023-.014*math.sin(math.pi*t)+(u-.5)*.010,d*(.006+.025*t)+(u-.5)*width)))
    m.patch(18,12,bow,'accent','head',thickness=.0035)
   m.ellipsoid(tuple(tie+Vector((side*.016,-.022,0))),(.014,.010,.017),'accent','head',18,10)
 elif hero=='charmy':
  # Swept scalp ridges lead continuously into the bun; no blunt fringe stubs.
  for k in range(16):
   u=k/16;path=[]
   for t in np.linspace(.08,.94,33):
    p=Vector(cap(t,u))
    radial=Vector((p.x,p.y-cy,max(0,p.z-eye_z)*.30)).normalized()
    p+=radial*.0018
    path.append(tuple(p))
   hair_path(path,.008,.0035)
  def bun(t,u):
   phi=math.pi*(.001+t*.998);a=TAU*u;ridge=1+.040*math.cos(a*13+phi*3)
   return (.008+.062*math.sin(phi)*math.cos(a)*ridge,cy+.028+.054*math.sin(phi)*math.sin(a)*ridge,top+.052+.064*math.cos(phi))
  m.patch(28,80,bun,'hair','head')
  for side in [-1,1]:
   lock([(side*rx*.80,cy-ry*.34,band_z+.030),(side*rx*.99,cy-ry*.40,eye_z+.051),(side*rx*.97,cy-ry*.29,eye_z-.021),(side*rx*.88,cy-ry*.22,eye_z-.032)],.019,.008)
 if hero=='asta':
  cloth_rx=rx+.011;cloth_ry=ry+.011
  m.patch(6,80,lambda t,u:(cloth_rx*math.sin(TAU*u),cy-cloth_ry*math.cos(TAU*u),band_z+(t-.5)*.046),'main','head',thickness=.003)
  # Raised Black Bulls horn/skull stitch, replacing the previous five beads.
  ex=cloth_rx*.70;ey=cy-cloth_ry*.73-.009;ez=band_z
  for side in [-1,1]:
   m.tube([(ex+side*.014,ey,ez+.016),(ex+side*.012,ey-.002,ez+.002),(ex+side*.006,ey-.002,ez-.002),(ex+side*.007,ey,ez-.014)],.0029,'gold','head',8)
   m.tube([(ex+side*.006,ey,ez+.004),(ex+side*.017,ey,ez+.008),(ex+side*.022,ey+.002,ez+.018)],.0025,'gold','head',8)
  m.tube([(ex-.007,ey,ez-.011),(ex,ey-.002,ez-.018),(ex+.007,ey,ez-.011)],.0025,'gold','head',8)
 if hero=='magna':
  for center in eye_centers:
   sign=1 if center.x>0 else -1
   outline=[(-.033,.012),(.033,.012+sign*.004),(.026,-.015),(-.027,-.014)]
   verts=[(center.x+x,center.y+y,center.z+z) for y in [-.002,-.006] for x,z in outline]
   m.add(verts,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)],'lens','head')
   m.tube([(center.x+x,center.y-.007,center.z+z) for x,z in outline+[outline[0]]],.0021,'steel','head',8)
   m.tube([(center.x+sign*.033,center.y-.004,center.z+.010),(sign*rx*.95,cy-ry*.18,center.z+.006),(sign*rx*1.02,cy+.02,center.z-.008)],.0023,'steel','head',8)
  a,b=eye_centers;m.tube([(a.x-.026,a.y-.005,a.z+.006),(0,min(a.y,b.y)-.007,a.z+.008),(b.x+.026,b.y-.005,b.z+.006)],.0022,'steel','head',8)


def props(m,body,hero,level,top,waist):
 if hero=='asta':
  # Closed bevelled Demon Slayer cross-section with broad blade and central ridge.
  hand=Vector(body[list(GROUPS['joint-r-hand-3'])].mean(axis=0))
  base=hand+Vector((-.018,-.012,.10));tip=base+Vector((-.20,.03,1.22))
  axis=(tip-base).normalized();u=Vector((0,1,0));w=axis.cross(u).normalized()
  v=[];f=[]
  for t,half in [(0,.10),(.07,.170),(.76,.155),(.94,.14),(1,.075)]:
   p=base+(tip-base)*t
   for x,y in [(-half,0),(-half*.82,-.024),(0,-.037),(half*.82,-.024),(half,0),(half*.82,.024),(0,.037),(-half*.82,.024)]:v.append(tuple(p+w*x+u*y))
  for r in range(4):
   for j in range(8):a=r*8+j;b=r*8+(j+1)%8;f.append((a,b,b+8,a+8))
  f.extend([tuple(range(7,-1,-1)),tuple(range(32,40))]);first_face=len(m.f);m.add(v,f,'black','hand.R')
  for index in range(first_face,first_face+32):
   if (index-first_face)%8 in [0,3,4,7]:m.m[index]='steel'
  m.tube([tuple(base-axis*.21),tuple(base)],.023,'leather','hand.R',16)
  for k in range(7):
   p=base-axis*(.025+k*.025)
   m.tube([tuple(p-u*.022-w*.004),tuple(p+u*.022+w*.004)],.0025,'steel','hand.R',6)
  m.tube([tuple(base-w*.17),tuple(base+w*.17)],.026,'silver','hand.R',12)
  # The Demon Slayer has a forged central ridge and a dark cross near the
  # guard. Shallow inlaid seams are real surface geometry on both blade faces.
  for side in [-1,1]:
   normal=u*side
   def blade_mark(t,x):
    half=float(np.interp(t,[0,.07,.76,.94,1],[.10,.170,.155,.14,.075]))
    ridge=.037-(.013*min(1,abs(x)/max(.001,half*.82)))
    return tuple(base+(tip-base)*t+w*x+normal*(ridge+.0010))
   m.tube([blade_mark(t,0) for t in np.linspace(.10,.86,28)],.0015,'steel','hand.R',6)
   m.tube([blade_mark(.23,x) for x in np.linspace(-.10,.10,15)],.0030,'cloth','hand.R',6)
   m.tube([blade_mark(t,0) for t in np.linspace(.14,.34,15)],.0040,'cloth','hand.R',6)
   for k,(t,x) in enumerate([(.37,-.082),(.56,.072),(.72,-.061)]):
    m.tube([blade_mark(t+q*.018,x+q*.015) for q in np.linspace(-1,1,9)],.0010,'steel','hand.R',5)
 elif hero in ['yuno','vanessa','noelle']:
  # A bound grimoire with real spine, page block and leather covers.
  center=Vector((.32,-.10,waist+.14));v=[]
  for x,y,z in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]:v.append(tuple(center+Vector((x*.075,y*.023,z*.10))))
  f=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
  m.add(v,f,'leather','spine')
  for k in range(7):m.tube([(center.x-.07,center.y-.025,center.z-.08+k*.025),(center.x+.07,center.y-.025,center.z-.08+k*.025)],.0018,'white','spine',6)
 # Crests follow the costume surface. They remain small sewn geometry.
 if hero=='yuno':
  x=-.185;y=-.198;z=top-.25
  star=[]
  for k in range(25):
   a=TAU*k/24;r=.038 if k%2==0 else .023
   star.append((x+math.sin(a)*r,y-.003,z+math.cos(a)*r))
  m.tube(star,.0028,'gold','chest',7)
  for side in [-1,1]:m.tube([(x+side*.018,y-.005,z-.008),(x,y-.006,z+.013),(x-side*.018,y-.005,z-.008)],.0025,'gold','chest',6)
 else:
  add_bulls_crest(m,getattr(m,'costume_crest',(-.19,-.18,top-.20)),.76 if hero=='charmy' else .90)

def create_mesh(m,mats,armature,hero,level):
 mesh=bpy.data.meshes.new(hero+'_L%d_AnatomicalTopology'%level);mesh.from_pydata(m.v,[],m.f);mesh.update()
 bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(mesh);bm.free()
 obj=bpy.data.objects.new(hero+'_L%d_Character'%level,mesh);bpy.context.collection.objects.link(obj)
 keys=list(mats)
 for mat in mats.values():mesh.materials.append(mat)
 uv=mesh.uv_layers.new(name='UVMap')
 for face,mat,coords in zip(mesh.polygons,m.m,m.uv):
  face.material_index=keys.index(mat);face.use_smooth=True
  for loop,coord in zip(face.loop_indices,coords):uv.data[loop].uv=coord
 groups={bone.name:obj.vertex_groups.new(name=bone.name) for bone in armature.data.bones}
 for i,weights in enumerate(m.w):
  total=sum(weights.values())
  if total<=.0001:weights={'root':1};total=1
  # Keep four strongest influences, matching the runtime skin budget.
  rows=sorted(weights.items(),key=lambda x:-x[1])[:4];total=sum(x[1] for x in rows)
  for name,w in rows:
   if name in groups and w>.0001:groups[name].add([i],w/total,'REPLACE')
 mod=obj.modifiers.new('AnatomicalSkin','ARMATURE');mod.object=armature;obj.parent=armature
 obj['pipeline']='anatomical-v2';obj['source_topology']='MakeHuman hm08 CC0';obj['character']=hero
 return obj

def animate(arm,hero):
 ad=arm.animation_data_create();bones=arm.pose.bones
 for b in bones:b.rotation_mode='XYZ'
 def pose(clip,t):
  for b in bones:b.rotation_euler=(0,0,0);b.location=(0,0,0)
  # Arms lower from the A-pose; joint rotations use the rig's consistent roll.
  for side,sign in [('L',1),('R',-1)]:
   bone=bones['upper_arm.'+side]
   basis=bone.bone.matrix_local.to_quaternion()
   bone.rotation_euler=(basis.inverted() @ Quaternion((0,1,0),sign*.55) @ basis).to_euler()
   bones['forearm.'+side].rotation_euler[0]=-.10
   for finger in range(1,6):
    for j in range(1,4):bones['finger%d-%d.%s'%(finger,j,side)].rotation_euler[0]=.08 if hero!='asta' or side=='L' else (.55 if j==1 else .72)
  breath=math.sin(t*TAU)
  bones['spine'].rotation_euler[0]=.018*breath
  bones['chest'].rotation_euler[1]=.025*breath
  bones['head'].rotation_euler[1]=-.025*breath
  bones['cape'].rotation_euler[0]=.025*math.sin(t*TAU+.3)
  bones['cape.L'].rotation_euler[0]=.035*math.sin(t*TAU+.7)
  bones['cape.R'].rotation_euler[0]=.035*math.sin(t*TAU-.7)
  if clip=='Idle':
   # Natural, subtle eyelid blinks on facial bones, with relaxed hand motion.
   blink=max(0,1-abs(t-.72)/.045)
   for side in ['L','R']:bones['oculi01.'+side].rotation_euler[0]=.15*blink
  else:
   # Anticipation -> cast/strike -> recovery, distinct for each hero.
   a=math.sin(math.pi*max(0,min(1,(t-.12)/.77)))**1.4
   bones['chest'].rotation_euler[1]+=(.30 if hero=='asta' else .16)*a
   bones['spine'].rotation_euler[0]-=.10*a
   if hero=='charmy':
    # Cotton area spell: balanced squat, both palms cast outwards, then recover.
    # Independent shoulder/elbow/wrist/finger rotations deform the skinned mesh.
    bones['spine'].rotation_euler[0]=-.07*a
    bones['chest'].rotation_euler[1]=.04*a
    for side,sign in [('L',1),('R',-1)]:
     bones['upper_arm.'+side].rotation_euler[0]-=.72*a
     bones['upper_arm.'+side].rotation_euler[2]+=sign*.22*a
     bones['forearm.'+side].rotation_euler[0]=-.10-.56*a
     bones['hand.'+side].rotation_euler[0]=-.24*a
     bones['thigh.'+side].rotation_euler[0]=.11*a
     bones['shin.'+side].rotation_euler[0]=-.18*a
     for finger in range(1,6):
      for j in range(1,4):bones['finger%d-%d.%s'%(finger,j,side)].rotation_euler[0]=.12-.10*a
   elif hero=='asta':
    bones['upper_arm.R'].rotation_euler[0]+=-.95*a
    bones['upper_arm.R'].rotation_euler[2]+=-.50*a
    bones['forearm.R'].rotation_euler[0]=-.10-.55*a
    bones['hand.R'].rotation_euler[1]=.30*a
   else:
    bones['upper_arm.R'].rotation_euler[0]+=-.95*a
    bones['upper_arm.R'].rotation_euler[2]+=.20*a
    bones['forearm.R'].rotation_euler[0]=-.10-.55*a
    bones['hand.R'].rotation_euler[0]=-.30*a
    bones['upper_arm.L'].rotation_euler[0]+=-.30*a
    for j in range(1,4):bones['finger2-%d.R'%j].rotation_euler[0]=-.10*a
   bones['head'].rotation_euler[1]-=.10*a
   bones['cape'].rotation_euler[0]-=.12*a
 for clip,frames in [('Idle',61),('Attack',25),('Ability',37)]:
  action=bpy.data.actions.new(hero+'_'+clip);ad.action=action
  for frame in range(1,frames+1,2):
   t=(frame-1)/(frames-1);pose(clip,t)
   for b in bones:
    b.keyframe_insert('rotation_euler',frame=frame,group=b.name)
  ad.action=None;track=ad.nla_tracks.new();track.name=clip;track.strips.new(clip,1,action);track.mute=clip!='Idle'
 for b in bones:b.rotation_euler=(0,0,0)
 bpy.context.scene.frame_set(1)

def preview(hero,level,arm):
 scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=1000;scene.render.resolution_y=1200;scene.render.resolution_percentage=100
 scene.render.image_settings.file_format='PNG';scene.render.film_transparent=False;scene.world.color=(.14,.14,.14)
 scene.view_settings.view_transform='AgX';scene.render.fps=30
 # Render actual skinned idle so anatomical A-pose is never mistaken for the final stance.
 for track in arm.animation_data.nla_tracks:track.mute=track.name!='Idle'
 scene.frame_set(11)
 bpy.ops.object.camera_add(location=(3.0,-5.5,2.45));cam=bpy.context.object;cam.rotation_euler=(Vector((0,0,1.2))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.lens=60;scene.camera=cam
 for loc,power,size in [((2,-4,5),650,4),((-3,-2,3),500,4),((1,3,4),950,3)]:
  bpy.ops.object.light_add(type='AREA',location=loc);light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size;light.rotation_euler=(Vector((0,0,1.2))-light.location).to_track_quat('-Z','Y').to_euler()
 if os.environ.get('CADY_HEAD_PREVIEWS_ONLY')=='1':
  # A close geometry review must not hide the face in a full-body thumbnail.
  body,_,_=sculpt(hero)
  eyes=np.vstack([body[list(GROUPS['joint-'+side+'-eye'])] for side in ['l','r']]).mean(axis=0)
  focus=Vector((0,eyes[1]+.01,eyes[2]+.08))
  cam.data.lens=85
  scene.render.resolution_x=900;scene.render.resolution_y=1000
  for name,direction in [('front',(0,-1,0)),('side',(1,0,0)),('threequarter',(.66,-.75,0))]:
   cam.location=focus+Vector(direction)*1.75
   cam.rotation_euler=(focus-cam.location).to_track_quat('-Z','Y').to_euler()
   scene.render.filepath=str(OUT/(hero+'_L%d_head_%s.png'%(level,name)))
   bpy.ops.render.render(write_still=True)
  cam.data.lens=60;cam.location=(0,-6,1.55)
  cam.rotation_euler=(Vector((0,0,1.2))-cam.location).to_track_quat('-Z','Y').to_euler()
  scene.render.resolution_x=1000;scene.render.resolution_y=1200
  scene.render.filepath=str(OUT/(hero+'_L%d_front.png'%level));bpy.ops.render.render(write_still=True)
  return
 scene.render.filepath=str(OUT/(hero+'_L%d_preview.png'%level));bpy.ops.render.render(write_still=True)
 # Front/side/back are genuine renders of the same geometry.
 if hero=='asta' or os.environ.get('CADY_PREVIEW_ALL_ANGLES')=='1':
  for name,loc in [('front',(0,-6,1.55)),('side',(6,0,1.55)),('back',(0,6,1.55))]:
   cam.location=loc;cam.rotation_euler=(Vector((0,0,1.2))-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(OUT/(hero+'_L%d_%s.png'%(level,name)));bpy.ops.render.render(write_still=True)

def build(hero,level):
 clean();body,p,scale=sculpt(hero);arm=rig(body,hero);m=Mesh();mats=materials(hero)
 # Exposed skin remains one connected anatomical region per visible body part;
 # delete hidden torso/leg polygons rather than layering full nude bodies.
 female=HEROES[hero]['female']
 def exposed(x,h,d):
  if h>5.35:return True
  if abs(x)>3.40:return True
  if hero=='asta' and -6.30<h<-4.65:return True
  if hero=='vanessa':return (1.4<h<3.9 and abs(x)<1.65) or (-3.25<h<.3 and abs(x)<2.15)
  if hero=='noelle':return -4.9<h<.45 and abs(x)<2.15
  return False
 # A complete anatomical body is retained beneath the fitted garments. This
 # prevents silhouette holes when a shoulder or wrist bends out of the sleeve.
 if hero=='charmy':
  # No hidden adult torso under the roomy tunic: eliminates skin poking
  # through cloth while retaining the anatomical neck, hands and bare calves.
  m.shell(body,p,lambda x,h,d:h>5.28 or abs(x)>3.65 or -7.45<h<-4.70,'skin',0)
 else:
  m.shell(body,p,lambda x,h,d:h>-7.45 or hero=='noelle','skin',0)
 top,waist=garments(m,body,p,hero,level,scale);face_hair(m,body,hero,level);props(m,body,hero,level,top,waist)
 obj=create_mesh(m,mats,arm,hero,level);animate(arm,hero)
 OUT.mkdir(parents=True,exist_ok=True);EDITABLE.mkdir(parents=True,exist_ok=True)
 pack_character_materials(obj,hero+'_L%d'%level,OUT/'Atlases',resolution=2048)
 if level==1:bpy.ops.wm.save_as_mainfile(filepath=str(EDITABLE/(hero+'.blend')))
 bpy.ops.object.select_all(action='DESELECT');arm.select_set(True);obj.select_set(True);bpy.context.view_layer.objects.active=arm
 bpy.ops.export_scene.gltf(filepath=str(OUT/(hero+'_L%d.glb'%level)),export_format='GLB',use_selection=True,export_animations=True,export_skins=True,export_nla_strips=True,export_force_sampling=True,export_anim_slide_to_zero=True,export_materials='EXPORT',export_extras=True,export_cameras=False,export_lights=False)
 print('HERO_V2_BUILT',hero,level,'vertices',len(m.v),'bones',len(arm.data.bones),flush=True)
 preview_levels={int(rank) for rank in os.environ.get('CADY_PREVIEW_LEVELS','1').split(',')}
 if os.environ.get('CADY_RENDER_PREVIEWS')=='1' and level in preview_levels:preview(hero,level,arm)

if __name__=='__main__':
 for hero in os.environ.get('CADY_HEROES','asta,yuno,magna,vanessa,noelle,charmy').split(','):
  for level in map(int,os.environ.get('CADY_LEVELS','1,2,3,4,5').split(',')):build(hero,level)
 print('ALL_ANATOMICAL_HEROES_BUILT',flush=True)
