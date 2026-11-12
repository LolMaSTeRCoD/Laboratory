"""Frozen anatomical mesh utilities for the enemy asset pipeline.

Quad topology, UV and rig weights: MakeHuman hm08 CC0.
Only reusable topology/mesh helpers are shared with the hero pipeline; enemy
sculpts, costumes and animation are independent. No legacy enemy meshes load.
"""
import bpy,bmesh,json,math,os,random,sys
from pathlib import Path
from mathutils import Vector,Quaternion,Matrix
import numpy as np
ROOT=Path(__file__).resolve().parents[1]
SOURCE=ROOT.parent/'Source'/'HeroPipeline'/'MakeHuman'
TAU=math.tau
RENAME={'root':'hips','spine03':'spine','spine01':'chest','neck03':'neck'}
for side in ['L','R']:
 for a,b in [('shoulder01','shoulder'),('upperarm01','upper_arm'),('lowerarm01','forearm'),('wrist','hand'),('upperleg01','thigh'),('lowerleg01','shin')]:RENAME[a+'.'+side]=b+'.'+side
def bn(name):return RENAME.get(name,name)
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
 def patch(self,rows,cols,fn,mat,weights='chest'):
  v=[];uv=[];f=[];ww=[]
  for r in range(rows+1):
   for c in range(cols+1):
    a=r/rows;b=c/cols;v.append(fn(a,b));uv.append((b,a))
    ww.append(weights(a,b) if callable(weights) else ({weights:1} if isinstance(weights,str) else weights))
  for r in range(rows):
   for c in range(cols):a=r*(cols+1)+c;f.append((a,a+1,a+cols+2,a+cols+1))
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
def create_mesh(m,mats,armature,hero,level):
 mesh=bpy.data.meshes.new(hero+'_AnatomicalTopology');mesh.from_pydata(m.v,[],m.f);mesh.update()
 bm=bmesh.new();bm.from_mesh(mesh);bmesh.ops.recalc_face_normals(bm,faces=bm.faces);bm.to_mesh(mesh);bm.free()
 obj=bpy.data.objects.new(hero+'_Character',mesh);bpy.context.collection.objects.link(obj)
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
 obj['pipeline']='enemy-anatomical-v3';obj['source_topology']='MakeHuman hm08 CC0';obj['character']=hero
 return obj
