"""KDTD enemies v3: anatomical sculpts and a continuous canine mesh.

No primitive-body geometry from build_enemy_models/build_tower_models is used.
MakeHuman CC0 quad topology is sculpted into five separate humanoid species;
the Warg uses a newly lofted quadruped topology and four-leg skinning.
"""
import bpy,bmesh,json,math,os,random,sys
from pathlib import Path
from mathutils import Vector,Matrix,Quaternion
from mathutils.bvhtree import BVHTree
import numpy as np
sys.path.insert(0,str(Path(__file__).parent))
from enemy_mesh_core import Mesh,RAW,UVS,FACES,GROUPS,BODY_SET,RIG,VERT_WEIGHTS,bn,create_mesh
from pack_character_materials import pack_character_materials
from enemy_face_details import mouth_rim, stable_lock, fitted_scalp
from audit_packed_model_sources import ensure_packed_model_images
from enemy_death_motion import pose_death, ground_death, DEATH_LAST_FRAME, DEATH_REVISION

ROOT=Path(__file__).resolve().parents[1];OUT=Path(os.environ.get('CADY_ENEMY_OUT',str(ROOT/'Assets'/'Enemies')))
SOURCE=ROOT.parent/'Source'/'HeroPipeline'/'MakeHuman'
EDITABLE=Path(os.environ.get('CADY_ENEMY_EDITABLE',str(ROOT.parent/'Source'/'EnemyPipeline'/'Characters')))
HEIGHTS={'goblin':2.335,'orc':2.146,'uruk':2.210,'troll':2.322,'nazgul':2.246,'warg':1.463,'boss_troll':4.65}
BOSS_BODY_HEIGHT=4.65
TAU=math.tau
RUN_CYCLE_SECONDS=20/30;RUN_CONTACT=.38;RUN_FOOT_TRAVEL=.78
COLORS={
 'goblin':dict(skin=(.25,.29,.105),cloth=(.075,.062,.035),leather=(.11,.067,.031),metal=(.15,.12,.075),hair=(.065,.057,.035),accent=(.19,.073,.035)),
 'orc':dict(skin=(.25,.255,.135),cloth=(.17,.037,.025),leather=(.105,.063,.032),metal=(.16,.13,.10),hair=(.027,.023,.018),accent=(.33,.058,.033)),
 'uruk':dict(skin=(.27,.255,.235),cloth=(.14,.025,.022),leather=(.055,.040,.029),metal=(.09,.102,.103),hair=(.014,.012,.010),accent=(.11,.012,.009)),
 'troll':dict(skin=(.32,.335,.315),cloth=(.085,.063,.035),leather=(.105,.067,.038),metal=(.135,.13,.11),hair=(.105,.105,.09),accent=(.18,.085,.043)),
 'nazgul':dict(skin=(.045,.045,.042),cloth=(.012,.014,.018),leather=(.023,.019,.014),metal=(.095,.105,.12),hair=(.006,.007,.008),accent=(.32,.012,.007)),
 'warg':dict(skin=(.15,.12,.080),cloth=(.085,.062,.038),leather=(.065,.036,.017),metal=(.13,.125,.105),hair=(.045,.033,.021),accent=(.19,.045,.020))}
COLORS['boss_troll']=dict(skin=(.29,.305,.285),cloth=(.14,.048,.025),leather=(.09,.052,.026),metal=(.16,.15,.12),hair=(.038,.035,.029),accent=(.34,.06,.025))

def clean():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 for pool in [bpy.data.actions,bpy.data.meshes,bpy.data.armatures,bpy.data.materials,bpy.data.images]:
  for item in list(pool):
   if item.users==0:pool.remove(item)

def sculpt(kind,boss=False,pectoral_sculpt=True):
 p=RAW.copy()
 # Continuous anatomical sculpt deltas also move the joint helpers. Skull
 # width is independent of shoulder width: the old product of both scales
 # flattened the troll's head into an almost featureless horizontal slab.
 width={'goblin':.82,'orc':1.29,'uruk':1.17,'troll':1.72,'nazgul':.90}[kind]
 skull_width={'goblin':1.04,'orc':1.24,'uruk':1.10,'troll':1.52,'nazgul':1.0}[kind]
 skull_height={'goblin':1.16,'orc':1.02,'uruk':1.12,'troll':1.08,'nazgul':1.0}[kind]
 skull_depth={'goblin':1.08,'orc':1.16,'uruk':1.04,'troll':1.24,'nazgul':1.0}[kind]
 for i,(x,h,d) in enumerate(RAW):
  chest=math.exp(-((h-4.0)/1.6)**2)
  p[i,0]*=width*(1+.10*chest)
  if pectoral_sculpt and kind in ['goblin','troll'] and i in BODY_SET and d>.70 and abs(x)<1.6 and 1.8<h<5.7:
   # The neutral source has paired breast protrusions. These bare-chested
   # creatures need a connected ribcage/pectoral plane, not a recoloured
   # feminine torso. Keep all joint helpers, limbs and the rest silhouette.
   fade_h=max(0,min(1,(h-1.8)/.65))*max(0,min(1,(5.7-h)/.65))
   fade_x=max(0,min(1,(1.6-abs(x))/.45))
   cap=1.30+.065*math.exp(-((abs(x)-.66)/.44)**2)-.08*((h-3.55)/1.5)**2
   p[i,2]-=max(0,d-cap)*fade_h*fade_x
  if kind=='goblin':
   if h<1.0:p[i,1]=-8.1676+(h+8.1676)*.82
   else:p[i,1]=-.65+h*.90
   # Forward upper back, compact hips and long visible forearms.
   p[i,2]+=max(0,(h-2.5)/6)*.66
   if abs(x)>2.1 and 1.8<h<4.5:p[i,0]*=1.07;p[i,1]-=.10
  if kind=='troll':
   p[i,2]*=1.42
   p[i,1]=h*.91
   if abs(x)>1.3 and 1.1<h<5.9:p[i,0]*=1.10;p[i,1]-=.18
  if kind=='uruk':
   # Long upright warrior silhouette, developed trapezius and lean waist.
   p[i,0]*=1+.05*math.exp(-((h-4.65)/.60)**2)-.035*math.exp(-((h-1.8)/.8)**2)
   p[i,2]+=.10*math.exp(-((h-5.1)/.65)**2)
  if h>5.5:
   blend=max(0,min(1,(h-5.5)/.65));blend=blend*blend*(3-2*blend)
   head_x=x*skull_width
   # Taper the goblin's chin, broaden the orc underbite, and give the uruk a
   # long square mandible rather than copying the troll's tusked muzzle.
   jaw=math.exp(-((h-6.40)/.44)**2)
   cheek=math.exp(-((h-7.05)/.28)**2)
   jaw_gain={'goblin':-.23,'orc':.24,'uruk':.16,'troll':.38,'nazgul':0}[kind]
   head_x*=1+jaw_gain*jaw+(.07 if kind=='goblin' else .025)*cheek
   if h>7.65:head_x*=1-.06*min(1,(h-7.65)/.9)
   p[i,0]=p[i,0]*(1-blend)+head_x*blend
   base_h=(-.65+5.5*.90) if kind=='goblin' else 5.5*.91 if kind=='troll' else 5.5
   head_h=base_h+(h-5.5)*skull_height
   p[i,1]=p[i,1]*(1-blend)+head_h*blend
   head_d=.45+(d-.45)*skull_depth
   if kind=='goblin':head_d+=.40
   if d>.55:
    front=min(1,(d-.55)/.5)
    brow_h=7.46+(.10 if kind=='troll' else .025)
    brow=math.exp(-((h-brow_h)/.17)**2)
    socket=math.exp(-((h-7.28)/.15)**2-((abs(x)-.34)/.23)**2)
    nose=math.exp(-((h-6.99)/.28)**2-(x/(.23 if kind=='goblin' else .36))**2)
    lower_lip=math.exp(-((h-6.55)/.13)**2-(x/.48)**2)
    snout={'goblin':.72,'orc':.34,'uruk':.17,'troll':.37,'nazgul':0}[kind]
    underbite={'goblin':.08,'orc':.37,'uruk':.16,'troll':.40,'nazgul':0}[kind]
    head_d+=front*(snout*nose+underbite*jaw+(.23 if kind=='uruk' else .48 if kind=='troll' else .30)*brow-.15*socket+.10*lower_lip)
    if kind=='troll':
     # Low broad gorilloid muzzle, overhanging brow and receding cranium.
     head_d+=front*.46*math.exp(-((h-6.65)/.48)**2-(x/.82)**4)
     head_d-=max(0,h-7.7)*.22
    # Raised cheek planes lead to a recessed crease beside the muzzle.
    head_d+=front*.11*math.exp(-((h-6.91)/.25)**2-((abs(x)-.56)/.22)**2)
    head_d-=front*.07*math.exp(-((h-6.62)/.19)**2-((abs(x)-.43)/.11)**2)
    if boss:head_d+=.16*jaw+.12*brow
   p[i,2]=p[i,2]*(1-blend)+head_d*blend
   if kind=='goblin':p[i,0]+=.035*math.exp(-((h-7.0)/.25)**2)*blend
   # Stretch the original connected auricle and its folds, rather than
   # attaching another triangular ear over a still-visible human ear.
   ear=max(0,min(1,(abs(x)-.69)/.30))*math.exp(-((h-7.25)/.47)**4)*max(0,min(1,(.70-d)/.40))
   extension={'goblin':.95,'orc':.24,'uruk':.12,'troll':.10,'nazgul':0}[kind]
   p[i,0]+=(1 if x>=0 else -1)*extension*ear
   p[i,1]+=(.44 if kind=='goblin' else .10)*ear
  # Actual skin relief: deterministic low-amplitude folds and pits, not balls.
  if kind!='nazgul' and (h>5.8 or abs(x)>2.4 or h<-.5):
   strength=.022 if kind=='troll' else .012
   p[i,2]+=strength*math.sin(x*11+h*17)*math.cos(d*23)+.008*math.sin(h*43+x*29)
 # Ground origin is derived from the sculpted body, not a guessed old height.
 ids=sorted(BODY_SET);floor=float(p[ids,1].min());scale=(HEIGHTS[kind]-.025)/(float(p[ids,1].max())-floor)
 body=np.column_stack((p[:,0]*scale,-p[:,2]*scale,(p[:,1]-floor)*scale))
 return body,p,scale

def joint(body,name):return Vector(body[list(GROUPS['joint-'+name])].mean(axis=0))

def humanoid_rig(body,kind):
 data=bpy.data.armatures.new(kind+'_AnatomicalSkeleton');arm=bpy.data.objects.new(kind+'_Armature',data)
 bpy.context.collection.objects.link(arm);bpy.context.view_layer.objects.active=arm;arm.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
 root=data.edit_bones.new('root');root.head=(0,0,0);root.tail=(0,0,.15)
 for name,info in RIG['bones'].items():
  b=data.edit_bones.new(bn(name));b.head=Vector(body[RIG['joints'][info['head']]].mean(axis=0));b.tail=Vector(body[RIG['joints'][info['tail']]].mean(axis=0))
  if (b.tail-b.head).length<.001:b.tail.z+=.004
 for name,info in RIG['bones'].items():
  b=data.edit_bones[bn(name)];b.parent=data.edit_bones[bn(info['parent'])] if info['parent'] else root;b.align_roll(Vector((0,-1,0)))
 cape=data.edit_bones.new('cape');cape.head=joint(body,'neck')+Vector((0,.12,-.12));cape.tail=cape.head+Vector((0,.15,-.65));cape.parent=data.edit_bones['chest']
 bpy.ops.object.mode_set(mode='OBJECT');arm.select_set(False)
 return arm

def material(kind,name,color):
 mat=bpy.data.materials.new(kind+'_'+name);mat.use_nodes=True;p=mat.node_tree.nodes.get('Principled BSDF')
 p.inputs['Base Color'].default_value=(*color,1);p.inputs['Roughness'].default_value=.86
 if name=='metal':p.inputs['Metallic'].default_value=.65;p.inputs['Roughness'].default_value=.64
 if name=='eyes':p.inputs['Roughness'].default_value=.26
 if name in ['skin','cloth','leather','metal','hair']:
  # Texture detail is a generated material surface, not a projected sprite.
  size=512;yy,xx=np.mgrid[0:size,0:size];rng=np.random.default_rng(sum(map(ord,kind+name)))
  grain=rng.normal(0,.035,(size,size));broad=.12*np.sin(xx*.021+np.sin(yy*.027)*2)*np.sin(yy*.016)
  # Independent albedo, roughness and tangent normal data retain surface
  # detail when the player inspects an enemy. These are generated surfaces,
  # not a projected source portrait, and remain one atlased draw surface.
  relief=.006*grain
  if name=='skin':
   folds=np.sin(xx*.17+np.sin(yy*.025))*np.cos(yy*.13)
   pores=rng.normal(0,.012,(size,size))
   broad+=.08*folds;relief=.09*folds+pores
  elif name=='metal':
   scratches=(np.sin(xx*.83+yy*.47)>.97).astype(float)
   hammered=np.sin(xx*.12)*np.sin(yy*.15)*.08
   grain+=.11*scratches;relief=hammered-scratches*.055
  elif name=='cloth':
   weave=np.sin(xx*1.1)*np.sin(yy*1.1)
   broad+=weave*.035;relief=weave*.025+.03*np.sin(xx*.041)*np.sin(yy*.06)
  elif name=='leather':
   grain_cells=np.sin(xx*.25+np.sin(yy*.13))*np.cos(yy*.29)
   relief=.045*grain_cells+.02*grain;broad+=.06*grain_cells
  else:relief=.035*np.sin(xx*.22+np.sin(yy*.08))
  a=np.ones((size,size,4),np.float32)
  for c in range(3):a[:,:,c]=np.clip(color[c]*(1+grain+broad),0,1)
  folder=OUT/'TexturesV3';folder.mkdir(exist_ok=True,parents=True);path=folder/(kind+'_'+name+'.png')
  im=bpy.data.images.new(kind+'_'+name,width=size,height=size);im.pixels.foreach_set(a.ravel());im.filepath_raw=str(path);im.file_format='PNG';im.save()
  tex=mat.node_tree.nodes.new('ShaderNodeTexImage');tex.image=im;mat.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
  rough=np.ones((size,size,4),np.float32)
  rough[:,:,:3]=np.clip(float(p.inputs['Roughness'].default_value)+relief[:,:,None]*.48,.34,.98)
  rough_image=bpy.data.images.new(kind+'_'+name+'_roughness',width=size,height=size)
  rough_image.colorspace_settings.name='Non-Color';rough_image.pixels.foreach_set(rough.ravel());rough_image.filepath_raw=str(folder/(kind+'_'+name+'_roughness.png'));rough_image.file_format='PNG';rough_image.save()
  rough_tex=mat.node_tree.nodes.new('ShaderNodeTexImage');rough_tex.image=rough_image;mat.node_tree.links.new(rough_tex.outputs['Color'],p.inputs['Roughness'])
  dy,dx=np.gradient(relief);normal=np.dstack((-dx*3,-dy*3,np.ones_like(dx)))
  normal/=np.maximum(np.linalg.norm(normal,axis=2,keepdims=True),1e-6)
  normal_pixels=np.ones((size,size,4),np.float32);normal_pixels[:,:,:3]=normal*.5+.5
  normal_image=bpy.data.images.new(kind+'_'+name+'_normal',width=size,height=size)
  normal_image.colorspace_settings.name='Non-Color';normal_image.pixels.foreach_set(normal_pixels.ravel());normal_image.filepath_raw=str(folder/(kind+'_'+name+'_normal.png'));normal_image.file_format='PNG';normal_image.save()
  normal_tex=mat.node_tree.nodes.new('ShaderNodeTexImage');normal_tex.image=normal_image
  normal_node=mat.node_tree.nodes.new('ShaderNodeNormalMap');normal_node.space='TANGENT';normal_node.inputs['Strength'].default_value=.65
  mat.node_tree.links.new(normal_tex.outputs['Color'],normal_node.inputs['Color']);mat.node_tree.links.new(normal_node.outputs['Normal'],p.inputs['Normal'])
 return mat

def materials(kind):
 colors=COLORS[kind].copy();colors.update(bone=(.43,.38,.26),black=(.003,.004,.003),eyes=(.25,.14,.012),scar=(.12,.042,.028),white=(.68,.65,.53))
 if kind=='nazgul':colors['eyes']=(.35,.008,.003)
 return {k:material(kind,k,c) for k,c in colors.items()}

def plate(m,center,width,height,depth,mat,bone,seed=0):
 # Bevelled shield-shaped steel surface, rolled rim and inner thickness.
 cx,cy,cz=center
 outline=[(-.48,.38),(-.32,.52),(.32,.52),(.49,.32),(.43,-.30),(0,-.58),(-.43,-.30)]
 verts=[(cx+x*width,cy+depth*(abs(x)*.40),cz+z*height) for x,z in outline]
 verts += [(cx+x*width*.84,cy-.035+depth*(abs(x)*.40),cz+z*height*.84) for x,z in outline]
 verts.append((cx,cy-.060,cz));faces=[]
 for i in range(7):faces.append((i,(i+1)%7,(i+1)%7+7,i+7));faces.append((i+7,(i+1)%7+7,14))
 m.add(verts,faces,mat,bone)
 m.tube(verts[:7]+[verts[0]],.006,'metal',bone,7)
 # Forged fasteners are actual geometry. A handful of asymmetric gouges
 # prevents every armour section looking like the same smooth plastic tile.
 for index in [0,1,2,3,4,6]:
  x,z=outline[index];y=cy-.025+depth*abs(x)*.40
  m.ellipsoid((cx+x*width*.84,y,cz+z*height*.84),(.009,.006,.009),'metal',bone,8,5)
 if width>.18:
  for n in range(2):
   x=cx+width*(-.20+n*.34);z=cz+height*(.14-n*.22)
   m.tube([(x,cy-.062,z),(x+width*.10,cy-.062,z+height*.035)],.0018,'scar',bone,5)

def curved_band(m,center,rx,ry,height,mat,bone):
 cx,cy,cz=center
 m.patch(4,48,lambda t,u:(cx+rx*math.sin(u*TAU),cy-ry*math.cos(u*TAU),cz+(t-.5)*height),mat,bone)

def thick_surface(m,rows,cols,fn,mat,bone):
 """Closed outer/inner garment surfaces, including their edge thickness."""
 verts=[];uv=[]
 for inner in [False,True]:
  for r in range(rows+1):
   for c in range(cols+1):
    verts.append(fn(r/rows,c/cols,inner));uv.append((c/cols,r/rows))
 layer=(rows+1)*(cols+1);faces=[]
 for r in range(rows):
  for c in range(cols):
   a=r*(cols+1)+c;faces.append((a,a+1,a+cols+2,a+cols+1));faces.append((a+layer,a+cols+1+layer,a+cols+2+layer,a+1+layer))
 for c in range(cols):
  a=c;faces.append((a,a+layer,a+1+layer,a+1))
  a=rows*(cols+1)+c;faces.append((a,a+1,a+1+layer,a+layer))
 for r in range(rows):
  a=r*(cols+1);faces.append((a,a+cols+1,a+cols+1+layer,a+layer))
  a=r*(cols+1)+cols;faces.append((a,a+layer,a+cols+1+layer,a+cols+1))
 m.add(verts,faces,mat,bone,uv)

def armor(m,body,kind,arm):
 surface=body[sorted(BODY_SET)];waist=joint(body,'pelvis').z+.08;neck=joint(body,'neck').z
 waist_section=surface[(abs(surface[:,2]-waist)<.06)&(abs(surface[:,0])<.48)]
 rx=float(abs(waist_section[:,0]).max())+.02;front=float(waist_section[:,1].min())-.03;back=float(waist_section[:,1].max())+.03;ry=(back-front)*.5;cy=(front+back)*.5
 # Closed lower clothing, ragged shaped leather faulds, wrap belt and buckle.
 m.shell(body,body,lambda x,h,d:-2.0<h<1.9 and abs(x)<3.1,'cloth',.025,.007)
 length=.38 if kind!='nazgul' else .90
 def skirt(t,u):
  a=u*TAU;r=(1+.15*t);jag=.035*math.sin(a*7.0)+.020*math.cos(a*13)
  return (math.sin(a)*rx*r,cy-math.cos(a)*ry*r,waist-t*(length+jag))
 m.patch(16,64,skirt,'leather' if kind!='nazgul' else 'cloth','hips')
 curved_band(m,(0,cy,waist),rx+.01,ry+.01,.08,'leather','hips')
 plate(m,(0,front-.025,waist),.13,.10,.04,'metal','hips')
 if kind=='nazgul':
  # Full-volume robe clears chest/abdomen. The earlier .24-radius cylinder
  # intersected the anatomical torso and exposed it through the cloth.
  top=neck-.055
  def robe(t,u,inner):
   a=u*TAU;shoulder=math.sin(min(1,t/.115)*math.pi*.5)
   fold=(.006+.015*t)*math.sin(a*17+.12*math.sin(t*7))+.005*math.sin(a*9-t*3)
   rx=.13+.24*shoulder+.07*t+fold;ry=.105+.14*shoulder+.08*t+fold
   if inner:rx-=.008;ry-=.008
   return (math.sin(a)*rx,.025-math.cos(a)*ry,top-(top-.028)*t-.018*math.sin(a*9)*t*t)
  robe_weights=[{'chest':max(0,1-(r/46)*1.6),'cape':min(1,(r/46)*1.6)} for layer in range(2) for r in range(47) for c in range(89)]
  thick_surface(m,46,88,robe,'cloth',robe_weights)
  m.shell(body,body,lambda x,h,d:1.7<h<5.8 and 1.45<abs(x)<4.5,'cloth',.042,.009)
 else:
  if kind=='goblin':
   m.shell(body,body,lambda x,h,d:2.0<h<5.9 and abs(x)<1.55 and (d<.18 or abs(x)>.95),'leather',.028,.004)
  elif kind!='troll':
   m.shell(body,body,lambda x,h,d:1.5<h<5.9 and abs(x)<1.55,'leather',.028,.004)
  else:
   # Bare anatomical chest and rocky gray shoulders distinguish a troll from
   # the uniform leather-shirt warrior silhouette used by the old pipeline.
   m.shell(body,body,lambda x,h,d:3.6<h<6.0 and d<-.15,'hair',.028,.004)
  # Overlapping angular torso plates and ridges follow the chest envelope.
  if kind!='goblin' and kind!='troll':
   for row in range(4 if kind=='uruk' else 3):
    z=waist+.14+row*(.135 if kind=='uruk' else .155)
    sec=surface[(abs(surface[:,2]-z)<.055)&(abs(surface[:,0])<.40)]
    y=float(sec[:,1].min())-.045 if len(sec) else -.25
    plate(m,(0,y,z),rx*(1.85 if kind=='uruk' else 1.95),.205 if kind=='uruk' else .24,.09 if kind=='uruk' else .12,'metal','chest' if row>0 else 'spine',row)
   if kind in ['uruk','orc']:
    # Torn red textile strips, closed around the waist rather than identical
    # brown aprons on every species. Weighted to the hips with subtle folds.
    for strip in range(5 if kind=='uruk' else 3):
     x=(strip-2)*.075 if kind=='uruk' else (strip-1)*.09
     def tabard(t,u,x=x,strip=strip):
      return (x+(u-.5)*.065,front-.060-.018*math.sin(t*5+strip),waist-t*(.42+.07*(strip%2))+.025*math.sin(u*9+strip)*t*t)
     m.patch(12,6,tabard,'accent','hips')
  # Shoulder pieces are sculpted plates, clearly separate from the anatomy.
  for suffix,sign in [('L',1),('R',-1)]:
   shoulder=arm.data.bones['upper_arm.'+suffix].head_local
   if kind=='goblin' and suffix=='L':continue
   if kind=='troll' and suffix=='L':continue
   plate(m,tuple(shoulder+Vector((sign*.025,-.075,.025))),.29 if kind=='goblin' else .40 if kind!='troll' else .52,.24 if kind=='goblin' else .29,.12,'metal','upper_arm.'+suffix)
   for spike in range(3 if kind in ['uruk','troll'] else 1 if kind=='goblin' else 2):
    x=shoulder.x+sign*(.02+spike*.06)
    m.tube([(x,.025,shoulder.z+.07),(x+sign*.04,.03,shoulder.z+.15+spike*.02),(x+sign*.07,.04,shoulder.z+.23+spike*.025)],[.027,.018,.0015],'metal','upper_arm.'+suffix,8)
 # Arm and leg fitted bracers keep the original skin weights, rather than rigid
 # capsules which separate from elbows/knees during the gait.
 for suffix in ['L','R']:
  sign=1 if suffix=='L' else -1
  m.shell(body,body,lambda x,h,d,s=sign: x*s>2.8 and 2.25<h<3.6,'leather',.025,.005)
  m.shell(body,body,lambda x,h,d,s=sign: x*s>0 and abs(x)<3.3 and -7.35<h<-4.7,'metal' if kind=='uruk' else 'leather',.023,.004)
  for index in range(3):
   start=arm.data.bones['forearm.'+suffix].head_local;end=arm.data.bones['hand.'+suffix].head_local
   p=start.lerp(end,.32+.19*index);m.tube([tuple(p+Vector((-.06,-.04,0))),tuple(p+Vector((0,-.075,0))),tuple(p+Vector((.06,-.04,0)))],.008,'metal','forearm.'+suffix,8)
  knee=arm.data.bones['shin.'+suffix].head_local
  if kind!='nazgul':plate(m,tuple(knee+Vector((0,-.06,0))),.21,.24,.06,'metal','shin.'+suffix)
 if kind=='uruk':
  # White Hand of Isengard physically painted/emblazoned over the chest plate.
  z=neck-.30;sec=surface[(abs(surface[:,2]-z)<.06)&(abs(surface[:,0])<.30)];y=float(sec[:,1].min())-.13
  m.patch(4,4,lambda t,u:((u-.5)*.075,y,z+(t-.5)*.08),'white','chest')
  for finger in range(4):
   x=-.029+finger*.019
   m.tube([(x,y-.001,z+.025),(x+(finger-1.5)*.005,y-.001,z+.095+.012*(finger in [1,2]))],[.006,.004],'white','chest',7)
  m.tube([(-.03,y,z),(-.06,y,z+.033),(-.066,y,z+.057)],[.008,.006,.003],'white','chest',7)
 return waist,neck

def mouth_cut(x,h,d):return 6.57<h<6.71 and abs(x)<.34 and d>1.42

def oral_cavity(m,body):
 # The facial surface actually opens into this cavity. Reuse its exact
 # boundary vertices/skin weights so the mouth is closed manifold geometry,
 # not a black object hovering in front of an uncut chin.
 removed=[]
 for group,face in FACES:
  if group=='body' and mouth_cut(*RAW[[q[0] for q in face]].mean(axis=0)):removed.append(face)
 edges={}
 for face in removed:
  ids=[q[0] for q in face]
  for n,a in enumerate(ids):
   b=ids[(n+1)%len(ids)];key=tuple(sorted((a,b)))
   if key in edges:edges[key][2]+=1
   else:edges[key]=[a,b,1]
 boundary=[(a,b) for a,b,count in edges.values() if count==1]
 ids=sorted({v for edge in boundary for v in edge});mapping={v:n for n,v in enumerate(ids)}
 outer=[Vector(body[i]) for i in ids];center=sum(outer,Vector())/len(outer)
 inner=[Vector((p.x*.97+center.x*.03,p.y+.010,p.z*.80+center.z*.20)) for p in outer]
 verts=[tuple(p) for p in outer+inner]+[tuple(center+Vector((0,.014,0)))]
 weights=[VERT_WEIGHTS[i] for i in ids]*2+[{'head':.6,'jaw':.4}]
 faces=[];count=len(outer)
 for a,b in boundary:
  x=mapping[a];y=mapping[b];faces.append((x,y,y+count,x+count));faces.append((x+count,y+count,count*2))
 m.add(verts,faces,'black',weights)
 m.oral_boundary=outer
 return center

def face(m,body,kind,neck,boss=False):
 surface=body[sorted(BODY_SET)];head=joint(body,'head');top=float(surface[:,2].max())
 if kind=='nazgul':
  z=neck+.26
  def hood(t,u,inner):
   a=.64+u*(TAU-1.28);cap=math.sqrt(max(.00001,1-max(0,(t-.58)/.42)**2))
   rx=(.19+.035*math.sin(t*math.pi))*cap+.004;ry=(.205-.010*t)*cap+.004
   if inner:rx=max(.001,rx-.008);ry=max(.001,ry-.008)
   return (math.sin(a)*rx,.035-math.cos(a)*ry,neck-.035+t*.455+.018*math.cos(a)*(1-t))
  thick_surface(m,30,64,hood,'cloth','head')
  # A recessed curved interior encloses the empty hood, rather than a flat
  # rectangle masquerading as a face or the open top of a cylinder.
  m.patch(22,40,lambda t,u:(math.sin(.90+u*(TAU-1.8))*(.14*math.sin(math.pi*(.12+.88*t))+.005),.035-math.cos(.90+u*(TAU-1.8))*.13,neck-.02+t*.39),'black','head')
  for side in [-1,1]:m.ellipsoid((side*.055,-.10,z+.035),(.021,.007,.009),'eyes','head',18,10)
  return
 head_surface=surface[surface[:,2]>neck+.04]
 # Measure the facial cranium, excluding the long native auricles; otherwise
 # extending a goblin's ears also incorrectly expands the hood over its ears.
 skull_ids=[i for i in BODY_SET if 6.8<RAW[i,1]<8.2 and RAW[i,2]>.7 and abs(RAW[i,0])<.78]
 head_width=float(np.percentile(abs(body[skull_ids,0]),95))
 head_height=top-neck
 body_faces=[f for group,f in FACES if group=='body']
 face_bvh=BVHTree.FromPolygons([tuple(v) for v in body],[[q[0] for q in f] for f in body_faces],all_triangles=False)
 front_limit=float(surface[:,1].min())-1.0
 def skin_point(x,z,offset=.001):
  hit=face_bvh.ray_cast(Vector((x,front_limit,z)),Vector((0,1,0)),3.0)
  if hit[0] is not None:return Vector((x,hit[0].y-offset,z))
  distances=(head_surface[:,0]-x)**2+(head_surface[:,2]-z)**2
  nearest=head_surface[np.argsort(distances)[:8]]
  return Vector((x,float(nearest[:,1].min())-offset,z))
 def skin_uv(x,z):
  hit=face_bvh.ray_cast(Vector((x,front_limit,z)),Vector((0,1,0)),3.0)
  if hit[0] is None:return (x*2+.5,z*2)
  face=body_faces[hit[2]]
  coords=body[[q[0] for q in face]]
  plane=np.column_stack((coords[:,0],coords[:,2],np.ones(len(coords))))
  tex=np.array([UVS[q[1]] for q in face])
  coeff=np.linalg.lstsq(plane,tex,rcond=None)[0]
  return tuple(np.array([x,z,1.0])@coeff)
 eyes=[]
 for side,suffix in [(1,'l'),(-1,'r')]:
  eye=joint(body,suffix+'-eye');eyes.append(eye)
  ew=.027 if kind=='goblin' else .029 if kind=='troll' else .025
  eh=.013 if kind=='goblin' else .011
  # Recessed eyes with fleshy upper/lower eyelids, not detached spherical eyes.
  m.ellipsoid(tuple(eye),(ew,.025,eh),'bone','head',24,12)
  m.ellipsoid(tuple(eye+Vector((0,-.024,0))),(.009,.0018,.008),'eyes','head',18,12)
  m.ellipsoid(tuple(eye+Vector((0,-.0255,0))),(.0035,.001,.0065 if kind=='goblin' else .0045),'black','head',16,10)
 eye_z=sum(p.z for p in eyes)/2
 mouth_center=oral_cavity(m,body);mouth_z=mouth_center.z
 lip_rx,lip_rz=mouth_rim(m,mouth_center,m.oral_boundary,skin_point,kind,skin_uv)
 half_width=head_width*({'goblin':.42,'orc':.54,'uruk':.47,'troll':.53}[kind])
 half_width=min(half_width,lip_rx*.94)
 # Every tooth has an individual tapered crown/curved fang rooted in the jaw.
 for k in range(8):
  x=(k-3.5)*half_width*.22;p=skin_point(x,mouth_z+lip_rz*.60,-.005)
  length=.007+.003*((k*7)%5)/4
  m.tube([tuple(p),tuple(p+Vector((.0008*(k-3),-.001,-length*.7))),tuple(p+Vector((.001*(k-3),-.002,-length)))],[.004,.0035,.001],'bone','jaw',8)
 for side in [-1,1]:
  x=side*half_width*.80;p=skin_point(x,mouth_z-.008,.001)
  fang={'goblin':.023,'orc':.035,'uruk':.011,'troll':.047 if not boss else .057}[kind]
  width=.0043 if kind=='goblin' else .0035 if kind=='uruk' else .007
  curve=.003 if kind in ['goblin','uruk'] else .008
  m.tube([tuple(p),tuple(p+Vector((side*curve,-.012,fang*.48))),tuple(p+Vector((side*.002,-.016,fang)))],[(width,width*.85),(width*.70,width*.58),(.0005,.0004)],'bone','jaw',12)
 # Nostrils and nasolabial contours follow the sculpted muzzle surface.
 nose_ids=[i for i in BODY_SET if abs(RAW[i,1]-6.99)<.07 and abs(RAW[i,0])<.35 and RAW[i,2]>1.0]
 nose_z=float(body[nose_ids,2].mean())
 for side in [-1,1]:
  p=skin_point(side*head_width*.13,nose_z,.0005)
  m.ellipsoid(tuple(p),(.005 if kind!='troll' else .008,.001,.003),'black','head',14,8)
 for side in [-1,1]:
  points=[skin_point(side*(.055+t*.016),eye_z-.022-t*.048,.0005) for t in [0,.25,.5,.75,1]]
  m.tube([tuple(p) for p in points],.0009,'scar','head',5)
 if kind=='goblin':
  # An actual fitted hood surface around the head, leaving the face and ears
  # exposed; its rim frames the small predatory face and hunchback silhouette.
  def hood_surface(t,u,inner):
   a=.69+(TAU-1.38)*u
   cap=math.sqrt(max(.0001,1-max(0,(t-.68)/.32)**2))
   rx=(head_width*1.55+.014*math.sin(a*9)*math.sin(math.pi*t))*cap+.012
   ry=(head_width*1.90+.008*math.sin(a*13))*cap+.012
   if inner:rx-=.007;ry-=.007
   return (math.sin(a)*rx,head.y+.035-math.cos(a)*ry,neck-.10+t*(top-neck+.25)+.012*math.sin(a*6)*t*(1-t))
  thick_surface(m,32,64,hood_surface,'cloth','head')
  def hood_cap(t,u,inner):
   return hood_surface(.70+.30*t,(-.69+1.38*u-.69)/(TAU-1.38),inner)
  thick_surface(m,12,20,hood_cap,'cloth','head')
  for side in [-1,1]:
   rim=[hood_surface(t/20,0 if side>0 else 1,False) for t in range(21)]
   m.tube(rim,.008,'leather','head',9)
 elif kind=='orc':
  # Battered half-helmet with a broad brow lip, cheek flanges and a low comb.
  m.shell(body,body,lambda x,h,d:h>7.76 or (h>7.1 and d<.25),'metal',.016,.001)
  for side in [-1,1]:
   plate(m,(side*head_width*.93,head.y-.085,eye_z-.025),.075,.14,.025,'metal','head')
  ridge=[(0,head.y-.18,top-.12),(0,head.y-.12,top-.005),(0,head.y+.02,top+.018),(0,head.y+.16,top-.11)]
  m.tube(ridge,[.010,.014,.012,.006],'metal','head',8)
 else:
  # Source sprites distinguish long-haired uruk warriors from the gray-maned,
  # bearded trolls. The former no longer reuses the orc's enclosing helmet.
  scalp=fitted_scalp(m,face_bvh,head,eye_z,neck,top)
  count=32 if kind=='uruk' else 38
  for k in range(count):
   a=.84+(TAU-1.68)*(k+.5)/count
   wander=.14*math.sin(k*2.3);radial=Vector((math.sin(a),-math.cos(a),0))
   start=.08+.18*(.5+.5*math.sin(k*1.91))
   pts=[scalp(t,a+wander*math.sin(t*math.pi),.010) for t in [start,.34,.52,.72,.91,1]]
   length=.085+.11*(.5+.5*math.sin(k*2.17))+(0 if kind=='uruk' else .025)
   pts.append(pts[-1]+radial*(.025+.018*math.sin(k))+Vector((.016*math.sin(k*1.7),.015,-length*.58)))
   pts.append(pts[-2]+radial*(.035+.014*math.sin(k))+Vector((.035*math.sin(k*1.7),.022,-length)))
   width=(.022 if kind=='uruk' else .030)*(.78+.35*(.5+.5*math.sin(k*1.7)))
   stable_lock(m,[tuple(p) for p in pts],width,width*.70)
  # Swept forelocks cover the crown itself. They are surface-following solid
  # clumps, not strips hovering behind a smooth helmet-shaped cap.
  for k in range(15):
   a=-1.04+2.08*k/14+.040*math.sin(k*1.7)
   pts=[scalp(t,math.pi-a*.72+.08*math.sin(k+t*3),.009) for t in [.90,.67,.43,.20,.035]]
   pts += [scalp(t,a+.14*math.sin(k*1.8)*math.sin(t*math.pi),.010) for t in [.19,.42,.64,.85,1]]
   pts.append(pts[-1]+Vector((.018*math.sin(k),-.003,-.004-.022*(.5+.5*math.sin(k*2.2)))))
   variance=.88+.16*math.sin(k*2.1)
   stable_lock(m,[tuple(p) for p in pts],(.012 if kind=='uruk' else .018)*variance,.008 if kind=='uruk' else .012)
  if kind=='troll':
   for k in range(31):
    x=half_width*1.18*(k/15-1);root=skin_point(x,mouth_z-.020-.023*abs(k-15)/15,.010)
    added=len(m.w);length=.12+.035*math.sin(k*2.2)+.025*(1-abs(k-15)/15)
    tip=root+Vector((.017*math.sin(k*1.8),.025,-length))
    stable_lock(m,[tuple(root),tuple(root+Vector((.010*math.sin(k),-.017,-.045))),tuple(tip+Vector((-.007,.004,.035))),tuple(tip)],.016,.010)
    for n in range(added,len(m.w)):m.w[n]={'jaw':.6,'head':.4}

def blade(m,start,end,width,bone,kind='cleaver'):
 start=Vector(start);end=Vector(end);axis=(end-start).normalized();u=axis.cross(Vector((0,1,0))).normalized();v=axis.cross(u).normalized()
 verts=[]
 for t,w in [(0,.60),(.08,1),(.80,1),(1,.02)]:
  p=start.lerp(end,t)
  for a,b in [(-1,0),(-.76,-1),(0,-1.3),(.76,-1),(1,0),(.76,1),(0,1.3),(-.76,1)]:verts.append(tuple(p+u*a*width*w+v*b*.015))
 faces=[]
 for row in range(3):
  for j in range(8):a=row*8+j;b=row*8+(j+1)%8;faces.append((a,b,b+8,a+8))
 faces.extend([tuple(range(7,-1,-1)),tuple(range(24,32))]);m.add(verts,faces,'metal',bone)
 m.tube([tuple(start-axis*.18),tuple(start)],.025,'leather',bone,12)
 m.tube([tuple(start-u*width*1.3),tuple(start+u*width*1.3)],.020,'metal',bone,10)

def shaped_blade(m,hand,kind):
 """Closed bevelled weapons with species-specific profiles and grips."""
 hand=Vector(hand)
 if kind=='goblin':
  rows=[(0,0,.60),(.01,.26,.95),(.045,.50,1.05),(.12,.72,.90),(.19,.92,.005)]
  length=.48;width=.075
 elif kind=='uruk':
  rows=[(0,0,.55),(-.005,.08,.90),(-.014,.27,1.0),(-.02,.34,.78),(-.025,.42,1.0),(-.035,.61,1.06),(-.065,.78,1.0),(-.13,1,.015)]
  length=.79;width=.085
 else:return
 verts=[]
 for curve,t,profile in rows:
  p=hand+Vector((curve,-.025-.015*t,.11+t*length))
  for a,b in [(-1,0),(-.76,-1),(0,-1.3),(.76,-1),(1,0),(.76,1),(0,1.3),(-.76,1)]:
   verts.append(tuple(p+Vector((a*width*profile,b*.013,0))))
 faces=[]
 for row in range(len(rows)-1):
  for n in range(8):a=row*8+n;b=row*8+(n+1)%8;faces.append((a,b,b+8,a+8))
 faces.extend([tuple(range(7,-1,-1)),tuple((len(rows)-1)*8+n for n in range(8))]);m.add(verts,faces,'metal','hand.R')
 m.tube([tuple(hand+Vector((0,-.025,-.09))),tuple(hand+Vector((0,-.025,.11)))],.026,'leather','hand.R',12)
 m.tube([tuple(hand+Vector((-.12,-.025,.10))),tuple(hand+Vector((.12,-.025,.10)))],.018,'metal','hand.R',10)
 for z in [-.055,-.02,.015,.05]:curved_band(m,tuple(hand+Vector((0,-.025,z))),.029,.029,.006,'cloth','hand.R')

def orc_axe(m,hand):
 hand=Vector(hand);center=hand+Vector((0,-.025,.58))
 m.tube([tuple(hand+Vector((0,-.025,-.22))),tuple(hand+Vector((0,-.025,.79)))],[.026,.036],'leather','hand.R',14)
 outline=[(-.035,-.17),(-.245,-.22),(-.36,-.11),(-.375,.10),(-.28,.28),(-.08,.19),(.055,.14),(.06,-.11)]
 verts=[]
 for side in [-1,1]:
  for x,z in outline:verts.append(tuple(center+Vector((x,side*(.003 if x<-.28 else .025),z))))
 faces=[tuple(range(7,-1,-1)),tuple(range(8,16))]
 for n in range(8):faces.append((n,(n+1)%8,(n+1)%8+8,n+8))
 m.add(verts,faces,'metal','hand.R')
 for z in [-.14,-.09,-.04,.01,.06]:curved_band(m,tuple(hand+Vector((0,-.025,z))),.030,.030,.008,'cloth','hand.R')

def weapons(m,body,kind,arm):
 hand=arm.data.bones['hand.R'].tail_local
 if kind=='boss_troll':
  # A continuous asymmetric timber-and-iron maul, not a floating primitive.
  center=hand+Vector((0,-.015,.64))
  m.tube([tuple(hand+Vector((0,-.01,-.22))),tuple(center),tuple(center+Vector((.025,-.01,.34)))],[.035,.055,.060],'leather','hand.R',16)
  m.tube([tuple(center+Vector((0,0,-.10))),tuple(center+Vector((.015,0,.04))),tuple(center+Vector((.025,0,.25))),tuple(center+Vector((.020,.005,.39)))],[(.12,.10),(.21,.17),(.22,.18),(.13,.12)],'leather','hand.R',20)
  for z in [0,.25]:
   curved_band(m,tuple(center+Vector((.02,0,z))),.224,.184,.045,'metal','hand.R')
  for row in range(2):
   for index in range(6):
    a=(index+row*.5)*TAU/6;axis=Vector((math.sin(a),math.cos(a),.14))
    start=center+Vector((.025,0,.08+row*.15))+axis*.19
    m.tube([tuple(start),tuple(start+axis*.12),tuple(start+axis*.22)],[.027,.018,.001],'metal','hand.R',8)
  for ring in range(5):
   curved_band(m,tuple(hand+Vector((0,-.015,-.14+ring*.045))),.042,.042,.009,'cloth','hand.R')
 elif kind=='troll':
  m.tube([tuple(hand+Vector((0,-.015,-.18))),tuple(hand+Vector((0,-.015,.68)))],[.037,.046],'leather','hand.R',14)
  center=hand+Vector((0,-.025,.62))
  m.tube([tuple(center+Vector((x,0,0))) for x in [-.26,-.20,.20,.26]],[.12,.17,.17,.12],'leather','hand.R',18)
  for x in [-.20,.20]:
   ring=[tuple(center+Vector((x,math.sin(TAU*n/20)*.173,math.cos(TAU*n/20)*.173))) for n in range(21)]
   m.tube(ring,.016,'metal','hand.R',8)
 elif kind=='orc':
  orc_axe(m,hand)
 elif kind in ['goblin','uruk']:
  shaped_blade(m,hand,kind)
 else:
  blade(m,hand+Vector((0,-.025,.12)),hand+Vector((-.08,-.05,.78 if kind=='nazgul' else .60 if kind=='uruk' else .45)),.090 if kind=='uruk' else .055,'hand.R')
 if kind in ['orc','goblin','uruk']:
  hand=arm.data.bones['hand.L'].tail_local;center=hand+Vector((0,-.13,.10))
  if kind=='uruk':plate(m,tuple(center),.46,.70,.10,'metal','hand.L')
  else:
   # Faceted wooden round shield with an iron rim, at the actual hand socket.
   points=[]
   for i in range(25):
    a=TAU*i/24;points.append(tuple(center+Vector((math.sin(a)*.24,-.015,math.cos(a)*.24))))
   m.add(points[:-1]+[tuple(center+Vector((0,-.045,0)))],[(i,(i+1)%24,24) for i in range(24)],'leather','hand.L')
   m.tube(points,.014,'metal','hand.L',8)
   m.tube([tuple(center+Vector((0,-.025,0))),tuple(center+Vector((0,-.14,0)))],[.054,.001],'metal','hand.L',12)
   if kind=='orc':
    for n in range(3):
     m.tube([tuple(center+Vector((-.14+n*.08,-.050,-.12))),tuple(center+Vector((-.07+n*.08,-.052,.12)))],.012,'accent','hand.L',6)

def equipment_detail(m,body,kind,arm,boss=False):
 """Fitted boots, stitched hides and anatomy-following scar topology."""
 surface=body[sorted(BODY_SET)];neck=joint(body,'neck').z
 # Boots now cover the toes instead of leaving all armoured enemies barefoot.
 if kind!='troll':
  m.shell(body,body,lambda x,h,d:h<-6.75,'leather',.014,.002)
  if kind=='uruk':m.shell(body,body,lambda x,h,d:h<-7.62 and d>.1,'metal',.022,.001)
 # Small accessories remain separate from the revised continuous facial skin.
 if kind!='nazgul':
  if kind=='goblin':
   # Stitched ragged hood collar frames the long ears and sloping jaw.
   m.tube([(-.16,.025,neck-.08),(-.14,.12,neck+.01),(0,.16,neck+.035),(.14,.12,neck+.01),(.16,.025,neck-.08)],[(.035,.022),(.04,.025),(.043,.028),(.04,.025),(.035,.022)],'cloth','neck',10)
 # Distinct functional straps crossing the torso and stitched apron edges.
 chest_top=neck-.09;waist=joint(body,'pelvis').z+.08
 if kind!='nazgul':
  for sign in ([-1,1] if boss else [-1]):
   points=[]
   for j in range(16):
    t=j/15;z=chest_top*(1-t)+(waist+.02)*t;x=sign*(.19*(1-t)-.15*t)
    near=surface[(abs(surface[:,2]-z)<.040)&(abs(surface[:,0]-x)<.08)]
    y=float(near[:,1].min())-.045 if len(near) else -.25
    points.append((x,y,z))
   m.tube(points,[(.025,.009)]*len(points),'leather','chest',8)
   for j in [2,5,8,11,14]:
    x,y,z=points[j];m.ellipsoid((x,y-.009,z),(.008,.005,.008),'metal','chest',8,5)
  for suffix in ['L','R']:
   knee=arm.data.bones['shin.'+suffix].head_local
   start=arm.data.bones['shin.'+suffix].head_local;end=arm.data.bones['foot.'+suffix].head_local
   for t in [.58,.70,.82]:
    p=start.lerp(end,t)
    for offset in [-.04,0,.04]:m.tube([tuple(p+Vector((offset-.005,-.072,.006))),tuple(p+Vector((offset+.005,-.074,-.006)))],.0025,'bone','shin.'+suffix,5)
 if boss:
  # Heavy layered thoracic armour, a broad jaw harness and a chained waist.
  for side in [-1,1]:
   for row in range(2):
    z=waist+.25+row*.23
    sec=surface[(abs(surface[:,2]-z)<.05)&(abs(surface[:,0])<.4)]
    y=float(sec[:,1].min())-.065
    plate(m,(side*.18,y,z),.42,.33,.14,'metal','chest',row)
  head=joint(body,'head');eye=joint(body,'l-eye')
  for side in [-1,1]:
   plate(m,(side*.185,head.y-.09,eye.z-.105),.12,.25,.04,'metal','head')
  for link in range(19):
   a=TAU*link/19;rx=.39;ry=.25
   center=Vector((math.sin(a)*rx,.015-math.cos(a)*ry,waist+.025*math.sin(a*3)))
   pts=[]
   for n in range(13):
    theta=TAU*n/12;pts.append(tuple(center+Vector((math.cos(a)*.022*math.cos(theta),math.sin(a)*.022*math.cos(theta),.037*math.sin(theta)))))
   m.tube(pts,.0055,'metal','hips',6)

def humanoid(kind):
 boss=kind=='boss_troll';species='troll' if boss else kind
 body,raw,scale=sculpt(species,boss)
 # The reference rig's joint landmarks include surface vertices. Keep their
 # reviewed positions while reshaping only the visible pectoral skin; a
 # breast-depth edit must not silently relocate spine/shoulder bind bones.
 rig_body=sculpt(species,boss,False)[0] if species in ['goblin','troll'] else body
 arm=humanoid_rig(rig_body,kind);m=Mesh()
 # Complete deformed anatomy is retained under fitted clothing, except the
 # Nazgul face which is intentionally hidden within a hollow cloth hood.
 m.shell(body,raw,lambda x,h,d:h<5.8 if species=='nazgul' else not mouth_cut(x,h,d),'skin',0)
 waist,neck=armor(m,body,species,arm);face(m,body,species,neck,boss);weapons(m,body,kind,arm)
 equipment_detail(m,body,species,arm,boss)
 mats=materials(kind);obj=create_mesh(m,mats,arm,kind,1)
 if boss:
  # Bake the true boss dimensions into mesh/rest bones, rather than relying on
  # an oversized runtime billboard or an unaccounted root transform.
  factor=BOSS_BODY_HEIGHT/HEIGHTS['troll']
  obj.data.transform(Matrix.Scale(factor,4));arm.data.transform(Matrix.Scale(factor,4));arm['gait_scale']=factor
 return obj,arm

def warg_rig():
 data=bpy.data.armatures.new('warg_CanineSkeleton');arm=bpy.data.objects.new('warg_Armature',data);bpy.context.collection.objects.link(arm);bpy.context.view_layer.objects.active=arm;arm.select_set(True);bpy.ops.object.mode_set(mode='EDIT')
 def bone(name,head,tail,parent=None):
  b=data.edit_bones.new(name);b.head=head;b.tail=tail
  if parent:b.parent=data.edit_bones[parent]
 bone('root',(0,0,0),(0,0,.15));bone('hips',(0,.45,.65),(0,.28,.85),'root');bone('spine',(0,.28,.85),(0,-.10,.96),'hips');bone('chest',(0,-.10,.96),(0,-.43,1.08),'spine');bone('neck',(0,-.43,1.08),(0,-.68,1.13),'chest');bone('head',(0,-.68,1.13),(0,-1.10,1.10),'neck');bone('cape',(0,.60,.95),(0,1.16,1.02),'hips');bone('jaw',(0,-.75,.97),(0,-1.23,.87),'head')
 for side,suffix in [(-1,'L'),(1,'R')]:
  x=side*.23
  bone('shoulder.'+suffix,(x,-.40,.95),(x,-.44,.81),'chest');bone('upper_arm.'+suffix,(x,-.44,.81),(x,-.39,.43),'shoulder.'+suffix);bone('forearm.'+suffix,(x,-.39,.43),(x,-.46,.12),'upper_arm.'+suffix);bone('hand.'+suffix,(x,-.46,.12),(x,-.64,.065),'forearm.'+suffix)
  bone('thigh.'+suffix,(x,.45,.80),(x,.59,.43),'hips');bone('shin.'+suffix,(x,.59,.43),(x,.44,.12),'thigh.'+suffix);bone('foot.'+suffix,(x,.44,.12),(x,.25,.06),'shin.'+suffix)
 bpy.ops.object.mode_set(mode='OBJECT');arm.select_set(False);return arm

def warg():
 arm=warg_rig();m=Mesh();rows=[(.80,.76,.17,.23),(.66,.88,.33,.30),(.43,.93,.36,.33),(.13,.95,.30,.29),(-.15,1.0,.36,.34),(-.39,1.04,.33,.37),(-.59,1.14,.24,.25),(-.77,1.17,.23,.25),(-.94,1.12,.22,.18),(-1.12,1.07,.15,.105),(-1.29,1.05,.105,.07)]
 verts=[];weights=[];uv=[];faces=[];seg=40
 for row,(y,z,rx,rz) in enumerate(rows):
  if y>.3:w={'hips':min(1,(y-.3)/.3),'spine':max(0,1-(y-.3)/.3)}
  elif y>-.3:w={'spine':max(0,1-(-y+.0)/.4),'chest':max(0,(-y+.0)/.4)}
  elif y>-.6:w={'chest':max(0,1-(-y-.3)/.3),'neck':max(0,(-y-.3)/.3)}
  else:w={'head':1}
  total=sum(w.values());w={k:v/total for k,v in w.items() if v>0}
  for j in range(seg):
   a=j/seg*TAU;wave=1+.035*math.sin(a*5+y*11)
   verts.append((math.sin(a)*rx*wave,y,z+math.cos(a)*rz*wave));weights.append(w.copy());uv.append((j/seg,row/(len(rows)-1)))
 for row in range(len(rows)-1):
  for j in range(seg):a=row*seg+j;b=row*seg+(j+1)%seg;faces.append((a,b,b+seg,a+seg))
 faces.extend([tuple(range(seg-1,-1,-1)),tuple((len(rows)-1)*seg+j for j in range(seg))]);m.add(verts,faces,'skin',weights,uv)
 # Long open jaw and a dark mouth cavity rather than a round muzzle.
 m.tube([(0,-.77,.96),(0,-1.02,.865),(0,-1.27,.875)],[(.145,.065),(.13,.045),(.075,.028)],'skin','jaw',24)
 m.patch(5,24,lambda t,u:((u-.5)*(.26-.13*t),-.91-t*.33,.94+.025*math.sin(u*math.pi)),'black','head')
 m.tube([(0,-1.26,1.07),(0,-1.33,1.04)],[(.11,.06),(.075,.04)],'black','head',18)
 for side in [-1,1]:
  eye=Vector((side*.205,-.83,1.23));m.ellipsoid(tuple(eye),(.018,.018,.015),'eyes','head',18,10)
  m.tube([(side*.16,-.87,1.245),(side*.21,-.84,1.265),(side*.25,-.79,1.26)],[.019,.022,.010],'skin','head',9)
  # Pointed canine ears, with inner surfaces and a proper thick base.
  x=side*.16;points=[(x,-.66,1.30),(x+side*.13,-.59,1.463),(x+side*.13,-.52,1.26),(x-side*.01,-.54,1.26),(x+side*.06,-.57,1.32)]
  m.add(points,[(0,1,4),(1,2,4),(2,3,4),(3,0,4),(0,3,2,1)],'hair','head')
  for k in range(6):
   y=-.96-k*.047;z=1.0-.03*k/6
   m.tube([(side*(.16-.012*k),y,z),(side*(.15-.012*k),y,z-.055 if k in [0,4] else z-.030)],[.011,.001],'bone','head',8)
  for fore in [True,False]:
   suffix='L' if side<0 else 'R';x=side*.23;y=-.44 if fore else .45
   upper=('upper_arm.' if fore else 'thigh.')+suffix;lower=('forearm.' if fore else 'shin.')+suffix;paw=('hand.' if fore else 'foot.')+suffix
   pts=[(x,y,.82),(x+side*.03,y+(.06 if fore else .13),.59),(x,y+.02,.40),(x,y-.025,.17)]
   # One connected limb surface, weights blending through its joint loops.
   start=len(m.v);m.tube(pts,[(.12,.15),(.11,.115),(.065,.075),(.055,.055)],'skin',upper,20)
   for i in range(start,len(m.v)):
    z=m.v[i][2];t=max(0,min(1,(.61-z)/.25));m.w[i]={upper:1-t,lower:t}
   m.tube([(x,y-.04,.12),(x,y-.16,.07),(x,y-.24,.06)],[(.08,.075),(.115,.06),(.08,.035)],'skin',paw,20)
   for claw in range(3):
    xx=x+(claw-1)*.058
    m.tube([(xx,y-.20,.063),(xx,y-.29,.035)],[.015,.001],'bone',paw,8)
 # Sculpted fur locks along the neck/haunches and a skinned tapering tail.
 for k in range(48):
  a=TAU*(k%8)/8;y=-.46+float(k//8)*.19;x=math.sin(a)*.29;z=.96+math.cos(a)*.29
  m.lock([(x,y,z),(x*1.13,y+.07,z+.015),(x*1.15,y+.12,z-.01),(x*1.16,y+.20,z-.025)],.038,.017)
  for i in range(len(m.w)-13*12,len(m.w)):m.w[i]={'chest' if y<0 else 'hips':1}
 m.tube([(0,.70,.96),(.04,.93,1.01),(.075,1.20,1.0),(.025,1.46,.87)],[(.095,.075),(.11,.075),(.075,.05),(.002,.002)],'hair','cape',20)
 mats=materials('warg');return create_mesh(m,mats,arm,'warg',1),arm

def _move_world(pose,offset):pose.location=pose.bone.matrix_local.to_3x3().inverted()@Vector(offset)
def _aim_bone(pose,head,tail):
 rest=pose.bone;rotation=(rest.tail_local-rest.head_local).rotation_difference(tail-head);pose.matrix=Matrix.Translation(head)@rotation.to_matrix().to_4x4()@rest.matrix_local.to_3x3().to_4x4()
def _solve_limb(rig,upper_name,lower_name,foot_name,ankle,knee_pole):
 upper=rig.pose.bones[upper_name];lower=rig.pose.bones[lower_name];foot=rig.pose.bones[foot_name]
 parent_delta=upper.parent.matrix@upper.parent.bone.matrix_local.inverted()
 hip=parent_delta@upper.bone.head_local;target=Vector(ankle);delta=target-hip
 # MakeHuman divides both anatomical segments into primary and twist bones.
 # The primary bone.length is therefore NOT the hip-to-knee / knee-to-ankle
 # distance. Limiting reach to those half-lengths made the feet float ~0.5 m.
 # Solve using actual joint origins, retaining all intermediate twist bones.
 rest_upper=lower.bone.head_local-upper.bone.head_local
 rest_lower=foot.bone.head_local-lower.bone.head_local
 l1,l2=rest_upper.length,rest_lower.length
 distance=max(.01,min(delta.length,l1+l2-.001));direction=delta.normalized()
 target=hip+direction*distance
 along=(l1*l1-l2*l2+distance*distance)/(2*distance)
 pole=Vector(knee_pole);bend=(pole-direction*pole.dot(direction)).normalized()
 knee=hip+direction*along+bend*math.sqrt(max(.0001,l1*l1-along*along))
 # Rotate each complete segment from its REST joint vector. Aiming the short
 # primary tail directly at the knee would introduce another angular error.
 upper_rotation=rest_upper.rotation_difference(knee-hip)
 upper.matrix=Matrix.Translation(hip)@upper_rotation.to_matrix().to_4x4()@upper.bone.matrix_local.to_3x3().to_4x4()
 bpy.context.view_layer.update()
 lower_rotation=rest_lower.rotation_difference(target-knee)
 lower.matrix=Matrix.Translation(knee)@lower_rotation.to_matrix().to_4x4()@lower.bone.matrix_local.to_3x3().to_4x4()
 bpy.context.view_layer.update()
 foot.matrix=Matrix.Translation(target)@foot.bone.matrix_local.to_3x3().to_4x4()
def _foot_trajectory(phase,base_y,ankle_height,travel=RUN_FOOT_TRAVEL,contact=RUN_CONTACT,lift=.19):
 phase%=1
 if phase<contact:return base_y-travel*.5+travel*phase/contact,ankle_height
 swing=(phase-contact)/(1-contact);smooth=swing*swing*(3-2*swing);return base_y+travel*.5-travel*smooth,ankle_height+lift*math.sin(math.pi*swing)

def animate(arm,kind,mesh):
 data=arm.animation_data_create();bones=arm.pose.bones
 gait_scale=float(arm.get('gait_scale',1.0))
 for b in bones:b.rotation_mode='XYZ'
 for clip,last,step in [('Idle',49,3),('Run',21,1),('Hit',13,1),('Death',DEATH_LAST_FRAME,1)]:
  frames=list(range(1,last+1,step));action=bpy.data.actions.new('enemy_'+kind+'_'+clip);data.action=action
  for track in data.nla_tracks:track.mute=True
  for frame in frames:
   bpy.context.scene.frame_set(frame);t=(frame-1)/(frames[-1]-1);wave=math.sin(t*TAU);pulse=math.sin(t*math.pi)
   for b in bones:b.rotation_euler=(0,0,0);b.location=(0,0,0);b.scale=(1,1,1)
   # Lower anatomical A-pose into relaxed, menacing hands-down stance.
   if kind!='warg':
    for side,sign in [('L',1),('R',-1)]:
     b=bones['upper_arm.'+side];basis=b.bone.matrix_local.to_quaternion();b.rotation_euler=(basis.inverted()@Quaternion((0,1,0),sign*.53)@basis).to_euler();bones['forearm.'+side].rotation_euler[0]=-.14
     for finger in range(1,6):
      for j in range(1,4):bones['finger%d-%d.%s'%(finger,j,side)].rotation_euler[0]=.23 if side=='L' else .65
   if clip=='Idle':
    bones['spine'].rotation_euler[0]=.018*wave;bones['chest'].rotation_euler[1]=.020*wave;bones['head'].rotation_euler[1]=-.025*wave;bones['cape'].rotation_euler[0]=.035*wave
    if kind=='goblin':bones['spine'].rotation_euler[0]-=.12;bones['neck'].rotation_euler[0]+=.08
    if kind in ['troll','boss_troll']:bones['spine'].rotation_euler[0]-=.045
    if kind!='warg':bones['jaw'].rotation_euler[0]=.012+.010*wave
   elif clip=='Run':
    _move_world(bones['hips'],(.015*wave*gait_scale,0,(-.12+.012*math.cos(t*TAU*2))*gait_scale));bones['spine'].rotation_euler[0]=-.20 if kind=='goblin' else -.135 if kind in ['troll','boss_troll'] else -.09;bones['chest'].rotation_euler[1]=.04*wave;bones['head'].rotation_euler[0]=.05;bones['cape'].rotation_euler[0]=-.12-.08*wave;bpy.context.view_layer.update()
    for index,suffix in enumerate(['L','R']):
     phase=(t+index*.5)%1
     if kind=='warg':
      for fore in [True,False]:
       limb_phase=(phase+(.5 if not fore else 0))%1;base_y=-.46 if fore else .44;y,z=_foot_trajectory(limb_phase,base_y,.12,.66,.42);upper=('upper_arm.' if fore else 'thigh.')+suffix;lower=('forearm.' if fore else 'shin.')+suffix;foot=('hand.' if fore else 'foot.')+suffix;x=bones[upper].bone.head_local.x
       _solve_limb(arm,upper,lower,foot,(x,y,z),(0,1 if fore else -1,0))
     else:
      foot=bones['foot.'+suffix].bone;ankle=foot.head_local;y,z=_foot_trajectory(phase,ankle.y,ankle.z,RUN_FOOT_TRAVEL*gait_scale,RUN_CONTACT,.19*gait_scale);x=bones['thigh.'+suffix].bone.head_local.x
      _solve_limb(arm,'thigh.'+suffix,'shin.'+suffix,'foot.'+suffix,(x,y,z),(0,-1,0));a=math.cos(TAU*phase);bones['upper_arm.'+suffix].rotation_euler[0]+=.30*a;bones['forearm.'+suffix].rotation_euler[0]=-.25-.12*a
   elif clip=='Hit':
    bones['chest'].rotation_euler[0]=.40*pulse;bones['head'].rotation_euler[0]=-.25*pulse;bones['spine'].rotation_euler[2]=.18*pulse;_move_world(bones['hips'],(0,.045*pulse,-.035*pulse))
   else:
    pose_death(arm,kind,t,_move_world,_solve_limb,bpy.context.view_layer.update)
    ground_death(arm,mesh,_move_world,bpy.context.view_layer.update,padding=.012 if kind in ['troll','boss_troll'] else .004)
   for b in bones:b.keyframe_insert('rotation_euler',frame=frame,group=b.name);b.keyframe_insert('location',frame=frame,group=b.name)
   if clip=='Death' and kind=='nazgul':bones['cape'].keyframe_insert('scale',frame=frame,group='cape')
  data.action=None;track=data.nla_tracks.new();track.name=clip;track.strips.new(clip,1,action);track.mute=True
 for b in bones:b.rotation_euler=(0,0,0);b.location=(0,0,0);b.scale=(1,1,1)
 travel=.66 if kind=='warg' else RUN_FOOT_TRAVEL*gait_scale;contact=.42 if kind=='warg' else RUN_CONTACT
 arm['run_cycle_seconds']=RUN_CYCLE_SECONDS;arm['run_stride_m']=travel/contact;arm['run_reference_mps']=travel/contact/RUN_CYCLE_SECONDS
 arm['death_motion_revision']=DEATH_REVISION
 bpy.context.scene.frame_set(1)

def preview(kind,arm):
 scene=bpy.context.scene;scene.render.engine='BLENDER_EEVEE';scene.render.resolution_x=1000;scene.render.resolution_y=1200;scene.render.resolution_percentage=100;scene.render.image_settings.file_format='PNG';scene.world.color=(.10,.10,.10);scene.view_settings.view_transform='AgX'
 for track in arm.animation_data.nla_tracks:track.mute=track.name!='Idle'
 scene.frame_set(1);view_scale=float(arm.get('gait_scale',1.0));target=Vector((0,-.03,1.1 if kind!='warg' else .75))*view_scale
 for loc,power,size in [((2,-4,5),700,4),((-3,-2,3),450,4),((1,3,4),850,3)]:
  bpy.ops.object.light_add(type='AREA',location=loc);light=bpy.context.object;light.data.energy=power;light.data.size=size;light.rotation_euler=(target-light.location).to_track_quat('-Z','Y').to_euler()
 bpy.ops.object.camera_add(location=(3.2,-5.5,2.5));cam=bpy.context.object;cam.data.lens=48 if kind=='boss_troll' else 62;scene.camera=cam
 folder=Path(os.environ.get('CADY_ENEMY_PREVIEW_OUT',str(ROOT/'Builds'/'enemy-v3-previews')));folder.mkdir(exist_ok=True,parents=True)
 for view,loc in [('threequarter',(3.2,-5.5,2.5)),('front',(0,-6.2,1.65)),('side',(6.2,0,1.65))]:
  cam.location=Vector(loc)*view_scale;cam.rotation_euler=(target-cam.location).to_track_quat('-Z','Y').to_euler();scene.render.filepath=str(folder/(kind+'_'+view+'.png'));bpy.ops.render.render(write_still=True)
 if os.environ.get('CADY_ENEMY_HEAD_PREVIEWS','0')=='1' and kind!='warg':
  scene.render.resolution_x=850;scene.render.resolution_y=900
  focus=arm.matrix_world@arm.pose.bones['head'].head+Vector((0,0,.035*view_scale))
  cam.data.lens=70
  for view,direction in [('head_front',(0,-1,.04)),('head_threequarter',(.65,-.76,.04)),('head_side',(1,0,.04))]:
   cam.location=focus+Vector(direction)*1.40*view_scale
   cam.rotation_euler=(focus-cam.location).to_track_quat('-Z','Y').to_euler()
   scene.render.filepath=str(folder/(kind+'_'+view+'.png'));bpy.ops.render.render(write_still=True)

def build(kind):
 clean();obj,arm=warg() if kind=='warg' else humanoid(kind);animate(arm,kind,obj)
 obj['enemy_pipeline']='anatomical-v3';obj['source_reference']=str(ROOT.parent/'Assets'/'Enemies'/(('troll' if kind=='boss_troll' else kind)+'.png'));obj['kind']=kind
 obj['surface_revision']='species-sculpt-surface-lips-stable-hair-20261111';obj['boss']=kind=='boss_troll'
 OUT.mkdir(parents=True,exist_ok=True);EDITABLE.mkdir(parents=True,exist_ok=True)
 pack_character_materials(obj,'enemy_v3_'+kind,OUT/'Atlases',resolution=2048)
 # Verify the actual atlas images feeding this mesh, not unrelated original
 # tile images retained by unused material data blocks. Packed editables
 # must survive cleanup or relocation of the temporary Builds directory.
 ensure_packed_model_images([obj])
 # The project checkpoint owns recovery; repeated automated generation must
 # not leave a second full packed .blend alongside every editable source.
 bpy.context.preferences.filepaths.save_version=0
 bpy.ops.wm.save_as_mainfile(filepath=str(EDITABLE/(kind+'.blend')))
 bpy.ops.object.select_all(action='DESELECT');arm.select_set(True);obj.select_set(True);bpy.context.view_layer.objects.active=arm
 bpy.ops.export_scene.gltf(filepath=str(OUT/(kind+'.glb')),export_format='GLB',use_selection=True,export_animations=True,export_skins=True,export_nla_strips=True,export_force_sampling=True,export_anim_slide_to_zero=True,export_materials='EXPORT',export_extras=True,export_cameras=False,export_lights=False)
 bounds=[Vector(v.co) for v in obj.data.vertices]
 print('ENEMY_V3_BUILT',kind,'vertices',len(obj.data.vertices),'bones',len(arm.data.bones),'height',max(v.z for v in bounds)-min(v.z for v in bounds),'materials',len(obj.data.materials),'stride_mps',arm['run_reference_mps'],flush=True)
 previews=os.environ.get('CADY_ENEMY_PREVIEWS','1')
 if previews=='1' or kind in previews.split(','):preview(kind,arm)

if __name__=='__main__':
 bpy.context.scene.render.fps=30
 for kind in os.environ.get('CADY_ENEMIES','goblin,orc,uruk,troll,nazgul,warg,boss_troll').split(','):build(kind)
 print('ALL_ENEMY_V3_ASSETS_BUILT',flush=True)
