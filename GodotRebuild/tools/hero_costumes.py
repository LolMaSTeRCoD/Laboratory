"""Character-specific sewn clothing geometry for the anatomical hero pipeline.

The module adds closed cloth surfaces and real embroidery/fasteners; no body
billboards or portrait textures. The caller owns all mesh, skin and atlas data.
"""
import math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree
from mathutils.geometry import closest_point_on_tri
from mathutils.kdtree import KDTree

TAU = math.tau


def joint(body, groups, name):
    return Vector(body[list(groups['joint-' + name])].mean(axis=0))


def _torso_section(body, groups, z, width_limit=.31):
    surface = body[sorted(groups['body'])]
    section = surface[(np.abs(surface[:, 2]-z)<.050) & (np.abs(surface[:, 0])<width_limit)]
    if len(section) < 5:
        return -.145, .125, .205
    return (float(np.percentile(section[:, 1], 2)),
            float(np.percentile(section[:, 1], 98)),
            float(np.percentile(np.abs(section[:, 0]), 98)))


def _belt(m, body, groups, waist, height, material, tilt=0, offset=0):
    front, back, width = _torso_section(body, groups, waist)
    clearance=.039 if material=='leather' else .024
    rx=max(.196, width+clearance); cy=(front+back)*.5; ry=(back-front)*.5+clearance
    def point(t,u):
        a=TAU*u
        return (math.sin(a)*rx, cy-math.cos(a)*ry,
                waist+offset+(t-.5)*height+tilt*math.sin(a))
    m.patch(4,72,point,material,'spine',thickness=.0025)
    return point, front-clearance-.003


class _Underlayer:
    """Frozen geometry/skin weights for an outer sewn garment layer."""
    def __init__(self,m,materials,low,high,width=.38,omit_arms=False):
        self.points=np.asarray(m.v,dtype=float)
        self.weights=[dict(w) for w in m.w]
        def arm_mass(i):
            return sum(v for n,v in self.weights[i].items() if any(part in n.lower() for part in
                ['upper_arm','upperarm','lowerarm','forearm','shoulder','hand','finger','metacarpal','wrist']))
        self.faces=[f for f,mat in zip(m.f,m.m) if mat in materials and
                    max(self.points[i,2] for i in f)>low and
                    min(self.points[i,2] for i in f)<high and
                    max(abs(self.points[i,0]) for i in f)<width and
                    (not omit_arms or max(arm_mass(i) for i in f)<.04)]
        self.tree=BVHTree.FromPolygons([Vector(v) for v in self.points],self.faces)
        ids=sorted({i for f in self.faces for i in f})
        self.cloud=self.points[ids]
    @staticmethod
    def normalize(values):
        rows=sorted(((n,v) for n,v in values.items() if v>1e-7),key=lambda x:x[1],reverse=True)[:4]
        total=sum(v for _,v in rows)
        return {n:v/total for n,v in rows} if total else {'root':1.0}
    def at_face(self,hit,index):
        face=self.faces[index];best=None
        for k in range(1,len(face)-1):
            ids=(face[0],face[k],face[k+1]);a,b,c=(Vector(self.points[i]) for i in ids)
            q=closest_point_on_tri(hit,a,b,c);ab=b-a;ac=c-a;aq=q-a
            d00=ab.dot(ab);d01=ab.dot(ac);d11=ac.dot(ac);den=d00*d11-d01*d01
            if abs(den)<1e-14:continue
            wb=(d11*aq.dot(ab)-d01*aq.dot(ac))/den;wc=(d00*aq.dot(ac)-d01*aq.dot(ab))/den
            bary=np.maximum(0,np.asarray([1-wb-wc,wb,wc]));bary/=max(1e-10,float(bary.sum()))
            distance=(q-hit).length_squared
            if best is None or distance<best[0]:best=(distance,ids,bary)
        values={}
        if best:
            for i,t in zip(best[1],best[2]):
                for n,w in self.weights[i].items():values[n]=values.get(n,0)+float(t)*w
        return self.normalize(values)
    def project(self,q,center_y,clearance=.017):
        q=Vector(q);direction=Vector((q.x,q.y-center_y,0))
        if direction.length<.01:return tuple(q),None
        direction.normalize()
        hit,_,index,_=self.tree.ray_cast(q+direction*2,-direction,4)
        if hit is None:return tuple(q),None
        distance=(hit-q).dot(direction)+clearance
        if distance>0:q+=direction*distance
        return tuple(q),self.at_face(hit,index)
    def section(self,z):
        q=self.cloud[(np.abs(self.cloud[:,2]-z)<.035)&(np.abs(self.cloud[:,0])<.245)]
        return (float(np.percentile(q[:,1],1)),float(np.percentile(q[:,1],99))) if len(q)>5 else None


def add_mantle(m, body, hero, stage, groups):
    """Sewn, sloping capes with individual closure and hem patterns.

    The pattern widens continuously from the neck to a shaped lower edge.
    There is no vertical cylindrical shoulder wall or rigid shelf across the
    chest; narrow Asta closure covers his black-cloak front as in the supplied
    model, while the other openings reveal their own uniforms.
    """
    neck=joint(body,groups,'neck')
    waist=joint(body,groups,'pelvis').z+.12
    # The sleeve's shoulder vertices sit nearly at neck-joint height in the
    # anatomical source. Start above that measured shoulder line, then widen
    # promptly into a fitted slope instead of leaving bright shoulder caps.
    top=neck.z+(.035 if hero=='charmy' else .025)
    length={'asta':.405,'magna':.410,'yuno':.94,
            'vanessa':.350,'noelle':.350,'charmy':.265}[hero]
    half_width={'asta':.363,'magna':.350,'yuno':.337,
                'vanessa':.332,'noelle':.321,'charmy':.252}[hero]
    depth={'asta':.166,'magna':.161,'yuno':.156,
           'vanessa':.166,'noelle':.157,'charmy':.132}[hero]
    future_belt=None
    if hero=='yuno':
        surface=body[sorted(groups['body'])]
        strip=surface[(np.abs(surface[:,2]-waist)<.04)&(np.abs(surface[:,0])<.31)]
        belt_rx=max(.235,float(np.abs(strip[:,0]).max())+.045)
        belt_front=float(strip[:,1].min())-.055;belt_back=float(strip[:,1].max())+.045
        future_belt=(belt_rx,(belt_front+belt_back)*.5,(belt_back-belt_front)*.5)
    # The shared tunic loft was broader than the anatomical torso at its
    # upper side seam. Fit that inner layer before sampling the outer cape;
    # deleting whole white quads would leave a stair-stepped V opening.
    if hero in ['asta','magna']:
        white_ids={i for face,mat in zip(m.f,m.m) if mat=='white' for i in face}
        amount=.17 if hero=='asta' else .13
        for i in white_ids:
            if set(m.w[i])-{'spine','chest'}:continue
            x,y,z=m.v[i]
            height=max(0,min(1,(z-(top-length+.025))/.11))
            height=height*height*(3-2*height)
            side=max(0,min(1,(abs(x)-.075)/.13))
            side=side*side*(3-2*side)
            m.v[i]=(x*(1-amount*height*side),y,z)
    # Freeze the geometry already emitted by the caller: anatomy, tunic,
    # sleeves and underlayers. A body-only envelope can sit inside the tunic
    # and produce bright islands through the dark cloak after skinning.
    # Never include this cloak in its own collision/support surface.
    garment_points=np.asarray(m.v,dtype=float)
    def normalized_weights(values):
        values=sorted(((name,float(w)) for name,w in values.items() if w>1e-7),
                      key=lambda item:item[1],reverse=True)[:4]
        total=sum(w for _,w in values)
        return {name:w/total for name,w in values} if total>1e-8 else {'chest':1.0}
    # Match the same top-four normalized weights used by create_mesh().
    garment_weights=[normalized_weights(w) for w in m.w]
    torso_faces=[f for f in m.f if
                 max(abs(garment_points[i,0]) for i in f)<half_width+.085 and
                 max(garment_points[i,2] for i in f)>top-length-.08 and
                 min(garment_points[i,2] for i in f)<top+.04]
    support=BVHTree.FromPolygons([Vector(v) for v in garment_points],torso_faces) if torso_faces else None
    weight_faces=list(m.f)
    weight_support=BVHTree.FromPolygons([Vector(v) for v in garment_points],weight_faces) if weight_faces else None
    def garment_width_at(z):
        q=garment_points[(np.abs(garment_points[:,2]-z)<.018)&
                         (np.abs(garment_points[:,0])<half_width*.94)&
                         (np.abs(garment_points[:,1])<.36)]
        return float(np.percentile(np.abs(q[:,0]),99))+.014 if len(q)>4 else 0.0
    front0,back0,_=_torso_section(body,groups,top,.15)
    neck_cy=(front0+back0)*.5
    neck_ry=max(.064,(back0-front0)*.5+.008)
    sections={}
    def section(t):
        key=round(float(t),5)
        if key not in sections:
            front,back,_=_torso_section(body,groups,top-length*t)
            clearance=.017+.011*t
            cy=(front+back)*.5
            ry=max(depth*min(1,t*2.9),(back-front)*.5+clearance)
            blend=min(1,t/.30)
            sections[key]=(neck_cy*(1-blend)+cy*blend,
                           neck_ry*(1-blend)+ry*blend,
                           garment_width_at(top-length*t))
        return sections[key]
    openings={'asta':(.035,.105),'magna':(.16,.30),'yuno':(.56,.24),
              'vanessa':(.34,.31),'noelle':(.26,.30),'charmy':(.095,.24)}
    def point(t,u):
        start,widen=openings[hero];opening=start+widen*t
        a=opening+u*(TAU-2*opening)
        # Shoulder seam and lower skirt are one curved cloth pattern.
        rx=float(np.interp(t,[0,.25,.56,1],[.084,half_width*.59,half_width*.87,half_width*1.035]))
        cy,ry,garment_rx=section(t)
        neck_fade=max(0,min(1,t/.10))
        neck_fade=neck_fade*neck_fade*(3-2*neck_fade)
        rx=max(rx,min(half_width*1.025,garment_rx)*neck_fade)
        fold=(.0048*math.sin(a*9+.35)+.0020*math.sin(a*19+1.6*t))*t**1.6
        x=math.sin(a)*(rx+fold)
        y=cy-math.cos(a)*(ry+fold)
        z=top-length*t+.045*abs(math.sin(a))**1.2*t**1.35
        z+=.007*math.cos(a*5+.4)*t*t
        if hero=='asta':
            # One longer corner and the front overlap identify Asta's mantle.
            x-=.012*max(0,math.cos(a))*t
            z+=.018*math.sin(a)*t*t
        elif hero=='yuno':
            y+=.027*t*t*(1-math.cos(a));z-=.018*max(0,-math.cos(a))*t*t
            if y>future_belt[1] and abs(x)<future_belt[0]:
                belt_rx,belt_cy,belt_ry=future_belt
                outer=belt_cy+belt_ry*math.sqrt(max(0,1-(x/belt_rx)**2))+.015
                fade=max(0,min(1,(abs(z-waist)-.08)/.07))
                fade=1-fade*fade*(3-2*fade)
                y+=max(0,outer-y)*fade
        elif hero in ['vanessa','noelle']:
            z+=.012*math.cos(a*3+.55)*t*t
        if support is not None and abs(math.cos(a))>.10:
            is_front=math.cos(a)>0
            origin=Vector((x,-2.5 if is_front else 2.5,z))
            direction=Vector((0,1 if is_front else -1,0))
            hit,_,_,_=support.ray_cast(origin,direction,5.0)
            if hit is not None:
                # Clear the front/back garment shell by 18 mm. Near the side
                # seam fade the adjustment; shoulder width is fitted above.
                fade=max(0,min(1,(abs(math.cos(a))-.10)/.30))
                fade=fade*fade*(3-2*fade)
                safe=hit.y+(-.018 if is_front else .018)
                desired=min(y,safe) if is_front else max(y,safe)
                y+=fade*(desired-y)
        return x,y,z
    def nearest_garment_weights(q):
        if weight_support is None:return {'chest':1.0}
        hit,_,face_index,_=weight_support.find_nearest(q)
        if hit is None or face_index is None:return {'chest':1.0}
        face=weight_faces[face_index];best=None
        for k in range(1,len(face)-1):
            tri=(face[0],face[k],face[k+1])
            aa,bb,cc=(Vector(garment_points[i]) for i in tri)
            nearest=closest_point_on_tri(hit,aa,bb,cc)
            ab=bb-aa;ac=cc-aa;ap=nearest-aa
            d00=ab.dot(ab);d01=ab.dot(ac);d11=ac.dot(ac)
            denominator=d00*d11-d01*d01
            if abs(denominator)<1e-14:continue
            wb=(d11*ap.dot(ab)-d01*ap.dot(ac))/denominator
            wc=(d00*ap.dot(ac)-d01*ap.dot(ab))/denominator
            bary=np.maximum(0,np.asarray([1-wb-wc,wb,wc],dtype=float))
            bary/=max(1e-12,float(bary.sum()))
            distance=(nearest-hit).length_squared
            if best is None or distance<best[0]:best=(distance,tri,bary)
        if best is None:
            vertex=min(face,key=lambda i:(Vector(garment_points[i])-hit).length_squared)
            return garment_weights[vertex]
        combined={}
        for vertex,amount in zip(best[1],best[2]):
            for bone,value in garment_weights[vertex].items():
                combined[bone]=combined.get(bone,0)+float(amount)*value
        return normalized_weights(combined)
    wing_weights={}
    for sign,side in [(1,'l'),(-1,'r')]:
        shoulder=joint(body,groups,side+'-shoulder')
        anchor_t=max(.12,min(.55,(top-shoulder.z+.015)/length))
        opening=openings[hero][0]+openings[hero][1]*anchor_t
        angle=math.pi*.5 if sign>0 else math.pi*1.5
        anchor_u=(angle-opening)/(TAU-2*opening)
        wing_weights[sign]=nearest_garment_weights(Vector(point(anchor_t,anchor_u)))
    # A long coat tail is not a short shoulder wing. Its lower sheet follows
    # the anatomical torso/pelvis, with just a little independent cape sway.
    # Exclude arm faces from this support so resting forearms cannot become
    # an accidental lower-cloth anchor.
    tail_under=(_Underlayer(m,{'skin'},top-length-.12,top+.03,width=.48,omit_arms=True)
                if hero=='yuno' else None)
    weight_cache={}
    def weights(t,u):
        key=(round(float(t),6),round(float(u),6))
        if key in weight_cache:return weight_cache[key]
        # The torso follows the sewn tunic's own spine/chest blend. A smooth
        # lateral wing follows the shoulder all the way to the same side hem;
        # do not use nearest-face discontinuities or release it below the arm.
        q=point(t,u)
        lower=waist-.145 if hero=='asta' else waist-.035
        upper=neck.z-.09 if hero in ['asta','magna'] else neck.z-.015
        phase=max(0,min(1,(q[2]-lower)/max(.01,upper-lower)))
        base={'spine':1-phase,'chest':phase}
        opening=openings[hero][0]+openings[hero][1]*t
        angle=opening+u*(TAU-2*opening)
        lateral=max(0,min(1,(abs(math.sin(angle))-.40)/.55))
        lateral=lateral*lateral*(3-2*lateral)
        neckline=max(0,min(1,t/.22));neckline=neckline*neckline*(3-2*neckline)
        mix=lateral*neckline
        if hero=='yuno':
            release=max(0,min(1,(t-.22)/.38));release=release*release*(3-2*release)
            # A full-length mantle hangs from the torso/clavicle. Its sleeve
            # emerges through the opening; it must not pull the whole upper
            # sheet with the large T-pose-to-cast upper-arm rotation.
            mix*=.12*(1-release)
            drape=max(0,min(1,(t-.30)/.35));drape=drape*drape*(3-2*drape)
            skin=tail_under.project(q,section(t)[0],0)[1]
            if skin:
                tail={n:v*.90 for n,v in skin.items()}
                tail['cape']=tail.get('cape',0)+.06
                side_bone='cape.R' if math.sin(angle)>0 else 'cape.L'
                tail[side_bone]=tail.get(side_bone,0)+.04
                lower_base={n:v*(1-drape) for n,v in base.items()}
                for n,v in tail.items():lower_base[n]=lower_base.get(n,0)+drape*v
                base=lower_base
        matched=wing_weights[1 if math.sin(angle)>=0 else -1]
        combined={name:value*(1-mix) for name,value in base.items()}
        for name,value in matched.items():combined[name]=combined.get(name,0)+mix*value
        result=normalized_weights(combined)
        weight_cache[key]=result
        return result
    first_cloak_face=len(m.f)
    m.patch(30,84,point,'main',weights,thickness=.0033)
    # Hidden source clothing is not useful geometry. Keep neckline, sleeves
    # and bare areas intact, but remove faces actually occluded by this cape
    # in the rest pattern. Otherwise independently sampled inner and outer
    # garment surfaces can cross during an animated shoulder compression.
    cloth_faces=m.f[first_cloak_face:]
    cloth_bvh=BVHTree.FromPolygons([Vector(v) for v in m.v],cloth_faces)
    keep=[]
    for index,face in enumerate(m.f):
        hidden=False
        sleeve=(((hero=='noelle' and m.m[index]=='white') or
                 (hero in ['asta','charmy'] and m.m[index]=='cloth')) and
                sum(sum(v for n,v in m.w[i].items() if 'upper_arm' in n or 'shoulder' in n)
                    for i in face)/len(face)>.2)
        if index<first_cloak_face and (m.m[index]=='skin' or sleeve):
            q=np.asarray([m.v[i] for i in face]).mean(axis=0)
            if top-length+.015<q[2]<top-.025:
                cy,_,_=section(max(0,min(1,(top-q[2])/length)))
                direction=Vector((q[0],q[1]-cy,0))
                if direction.length>.02:
                    direction.normalize();target=Vector(q)
                    hit,_,_,_=cloth_bvh.ray_cast(target+direction*2,-direction,2.03)
                    hidden=hit is not None and (hit-target).dot(direction)>.002
        keep.append(not hidden)
    m.f=[f for f,ok in zip(m.f,keep) if ok]
    m.m=[v for v,ok in zip(m.m,keep) if ok]
    m.uv=[v for v,ok in zip(m.uv,keep) if ok]
    def fitted_seam(parameters,radius,material,sides=7):
        parameters=list(parameters)
        per_vertex=[weights(t,u).copy() for t,u in parameters for _ in range(sides)]
        m.tube([point(t,u) for t,u in parameters],radius,material,per_vertex,sides)
    for edge in [0,1]:
        fitted_seam(((t,edge) for t in np.linspace(0,1,31)),.0029,'gold')
    fitted_seam(((1,u) for u in np.linspace(0,1,85)),.0034,'gold')
    # Inset seam lies on the cloth instead of surrounding it as a loose ring.
    fitted_seam(((.31,u) for u in np.linspace(0,1,61)),.0011,'main',6)
    for edge in [0,1]:
        x,y,z=point(.115,edge)
        m.ellipsoid((x,y-.003,z),(.0095,.004,.0095),'gold','chest',14,8)
    if hero!='yuno':
        left=Vector(point(.115,0));right=Vector(point(.115,1))
        cord=[]
        for t in np.linspace(0,1,18):
            q=left.lerp(right,float(t));q.y-=.004;q.z-=.012*math.sin(math.pi*t)
            cord.append(tuple(q))
        m.tube(cord,.0022,'gold' if hero in ['asta','magna','charmy'] else 'silver','chest',7)
    tc=.58 if hero!='yuno' else .35;uc=.936
    crest=point(tc,uc)
    mark_cache={}
    def mark_parameters(dx,dz):
        # Invert the garment's x/z surface locally for true fitted embroidery.
        key=(round(dx,7),round(dz,7))
        if key in mark_cache:return mark_cache[key]
        t=tc-dz/length;u=uc+dx/max(.3,half_width*TAU)
        target=np.asarray([crest[0]+dx,crest[2]+dz])
        for _ in range(4):
            q=np.asarray(point(t,u));dt=(np.asarray(point(t+.0002,u))-q)/.0002
            du=(np.asarray(point(t,u+.0002))-q)/.0002
            matrix=np.asarray([[dt[0],du[0]],[dt[2],du[2]]])
            if abs(float(np.linalg.det(matrix)))<1e-8:break
            delta=np.linalg.solve(matrix,target-q[[0,2]])
            t=float(np.clip(t+delta[0],.16,.91));u=float(np.clip(u+delta[1],.82,.987))
        mark_cache[key]=(t,u)
        return t,u
    def project_mark(dx,dz):
        t,u=mark_parameters(dx,dz)
        q=Vector(point(t,u));q.y-=.0025
        return tuple(q)
    m.mantle_mark_weights=lambda dx,dz:weights(*mark_parameters(dx,dz))
    m.mantle_point=point;m.mantle_mark=project_mark;m.mantle_crest=crest
    m.mantle_crest_weights=weights(tc,uc)
    m.mantle_weights=weights
    return top,top-length,crest


def add_vanessa_bodice(m,body,groups,waist):
    """A closed, skinned garment cut from actual torso topology.

    Horizontal body slices include diagonally posed arms; lofting their width
    produced a false underarm shelf. Clip the anatomical torso itself,
    preserve its exact skin weights, then offset and thicken the cloth.
    """
    neck=joint(body,groups,'neck');bottom=waist+.235;upper=neck.z-.145
    points=np.asarray(m.v,dtype=float);source_weights=[dict(w) for w in m.w]
    skin_faces=[f for f,mat in zip(m.f,m.m) if mat=='skin']
    normals=np.zeros_like(points)
    for f in skin_faces:
        n=np.cross(points[f[1]]-points[f[0]],points[f[2]]-points[f[0]])
        for i in f:normals[i]+=n
    lengths=np.linalg.norm(normals,axis=1);normals/=np.maximum(lengths[:,None],1e-10)
    def arm_mass(w):
        return sum(v for name,v in w.items() if any(k in name for k in ['upper_arm','forearm','shoulder','hand','finger']))
    def top_at(q):
        front=max(0,min(1,(-q[1]-.02)/.10))
        return upper-.046*math.exp(-(q[0]/.052)**2)*front-.018*(1-front)
    def blend(a,b,t):
        w={n:a[2].get(n,0)*(1-t)+b[2].get(n,0)*t for n in set(a[2])|set(b[2])}
        return (a[0]*(1-t)+b[0]*t,a[1]*(1-t)+b[1]*t,w)
    def clip(poly,fn):
        out=[]
        for a,b in zip(poly,poly[1:]+poly[:1]):
            fa=fn(a);fb=fn(b)
            if fa>=0:out.append(a)
            if (fa>=0)!=(fb>=0):out.append(blend(a,b,fa/(fa-fb)))
        return out
    verts=[];weights=[];faces=[];norms=[];index={}
    torso_width=max(.165,min(.205,joint(body,groups,'l-shoulder').x+.015))
    def add_vertex(item):
        q,n,w=item;n=n/max(1e-10,np.linalg.norm(n));q=q+n*.014
        key=tuple(round(float(x),7) for x in q)
        if key in index:return index[key]
        rows=sorted(((k,v) for k,v in w.items() if v>1e-7),key=lambda x:x[1],reverse=True)[:4]
        total=sum(v for _,v in rows);ww={k:v/total for k,v in rows}
        i=len(verts);index[key]=i;verts.append(tuple(q));norms.append(n);weights.append(ww);return i
    for f in skin_faces:
        if max(points[i,2] for i in f)<bottom or min(points[i,2] for i in f)>upper:continue
        poly=[(points[i].copy(),normals[i].copy(),source_weights[i]) for i in f]
        for fn in [lambda a:a[0][2]-bottom,lambda a:top_at(a[0])-a[0][2],
                   lambda a:torso_width-abs(a[0][0]),lambda a:.10-arm_mass(a[2])]:
            poly=clip(poly,fn)
            if len(poly)<3:break
        if len(poly)>=3:faces.append(tuple(add_vertex(v) for v in poly))
    boundary={}
    for f in faces:
        for a,b in zip(f,f[1:]+f[:1]):
            key=tuple(sorted((a,b)));boundary[key]=boundary.get(key,0)+1
    count=len(verts);outer=faces.copy()
    verts.extend(tuple(np.asarray(v)-n*.003) for v,n in zip(verts.copy(),norms))
    weights+=weights.copy();faces.extend(tuple(i+count for i in reversed(f)) for f in outer)
    for (a,b),uses in boundary.items():
        if uses==1:faces.append((a,b,b+count,a+count))
    m.add(verts,faces,'cloth',weights)
    # Freeze only the emitted bodice now, before gloves or other clothing can
    # be mistaken for its front surface. A stitched cord must follow the
    # actual central cloth and its skin weights, not the foremost breast lobe.
    stitch_support=_Underlayer(m,{'cloth'},bottom-.015,upper+.02,width=.30)
    def stitch(x,z):
        z=max(bottom+.004,min(z,upper-.046*math.exp(-(x/.052)**2)-.004))
        for step in range(21):
            probe_z=z-.002*step
            hit,_,index,_=stitch_support.tree.ray_cast(Vector((x,-2.5,probe_z)),Vector((0,1,0)),5)
            if hit is not None:
                return (hit.x,hit.y-.0026,hit.z),stitch_support.at_face(hit,index)
        raise RuntimeError('Vanessa corset stitch is outside the emitted cloth shell')
    m.bodice_stitch=stitch
    for (a,b),uses in boundary.items():
        if uses==1:m.tube([verts[a],verts[b]],.0018,'accent',[weights[a]]*6+[weights[b]]*6,6)
    def front_at(z):
        q=np.asarray(verts[:count]);q=q[(abs(q[:,2]-z)<.04)&(abs(q[:,0])<.10)]
        return float(q[:,1].min()) if len(q) else -.20
    m.bodice_front_at_z=front_at


def add_bulls_crest(m,center,size=1.0,bone='chest'):
    """Raised gold bull-skull embroidery following the actual cape surface."""
    c=Vector(center)
    fitted=hasattr(m,'mantle_mark') and (c-Vector(m.mantle_crest)).length<.01
    if fitted and bone=='chest':bone=m.mantle_crest_weights
    def at(x,z):
        if fitted:return m.mantle_mark(x*size,z*size)
        return tuple(c+Vector((x*size,-.003,z*size)))
    def stitch(coords,radius,sides=7):
        coords=list(coords)
        skin=[m.mantle_mark_weights(x*size,z*size) for x,z in coords for _ in range(sides)] if fitted else bone
        m.tube([at(x,z) for x,z in coords],radius,'gold',skin,sides)
    skull=[(-.026,.023),(-.030,.005),(-.021,-.017),(-.013,-.033),
           (0,-.045),(.013,-.033),(.021,-.017),(.030,.005),(.026,.023),
           (.010,.031),(0,.027),(-.010,.031),(-.026,.023)]
    stitch(skull,.0022*size)
    for side in [-1,1]:
        horn=[(side*.023,.017),(side*.043,.022),(side*.057,.047),
              (side*.036,.037),(side*.018,.031)]
        stitch(horn,.0026*size)
        eye=[(side*.023,.010),(side*.012,.003),(side*.009,-.008)]
        stitch(eye,.0027*size,6)
        stitch([(side*.013,-.026),(side*.007,-.024)],.0021*size,6)
    stitch([(-.006,-.035),(0,-.039),(.006,-.035)],.0018*size,6)


def add_noelle_skirt_and_gaiters(m,body,raw,groups,waist):
    # Copy weights from the actual anatomical hip surface, not the chest's
    # cape bones. Long skirt petals must not twist with an attacking shoulder.
    skin_ids=sorted({i for f,material in zip(m.f,m.m) if material=='skin' for i in f})
    skin_tree=KDTree(len(skin_ids))
    for i in skin_ids:skin_tree.insert(Vector(m.v[i]),i)
    skin_tree.balance()
    source_weights=[dict(w) for w in m.w]
    def normalized(w):
        rows=sorted(((n,v) for n,v in w.items() if v>1e-7),key=lambda x:x[1],reverse=True)[:4]
        total=sum(v for _,v in rows)
        return {n:v/total for n,v in rows} if total else {'root':1.0}
    def skin_at(point):
        _,index,_=skin_tree.find(Vector(point))
        return normalized(source_weights[index])
    def drape_weights(point_fn,t,u):
        fitted=skin_at(point_fn(min(t,.20),u))
        release=max(0,min(1,(t-.20)/.80));release=release*release*(3-2*release)*.22
        out={n:v*(1-release) for n,v in fitted.items()}
        out['root']=out.get('root',0)+release
        return normalized(out)
    # Structured lavender pleats and overlapping narrow white feather panels.
    front,back,hip=_torso_section(body,groups,waist-.10,.30)
    base_radius=max(.205,min(.238,hip+.018));cy=(front+back)*.5
    def skirt(t,u):
        a=TAU*u;r=base_radius+.036*t+.006*t*math.cos(a*12)
        return math.sin(a)*r,cy-math.cos(a)*r*.74,waist-.030-.245*t
    m.patch(20,72,skirt,'accent',lambda t,u:drape_weights(skirt,t,u),thickness=.0028)
    # The anatomical shorts can extend farther back than the regular inner
    # skirt ellipse. Fit above BOTH emitted layers and inherit their actual
    # weights, rather than merely adding a fixed radius to a different rig.
    under=_Underlayer(m,{'accent','skin'},waist-.34,waist+.025)
    for k in range(10):
        a=.38+k*(TAU-.76)/9;side=abs(math.sin(a));rear=max(0,-math.cos(a))
        length=.235+.32*side**1.8+.40*rear**1.5
        def raw_panel(t,u,a=a,length=length):
            width=.65*(1-.69*t**4)
            theta=a+(u-.5)*width
            r=base_radius+.020+.045*t+.015*t*t
            z=waist-.032-length*t-.045*math.sin(math.pi*u)*t**4+.050*(1-t)**2
            # Leave the attacking hand in front of the side panel rather
            # than pushing its fingers through the stiff upper petal.
            hand_clearance=.070*max(0,math.cos(theta))*abs(math.sin(theta))**2*(1-t)**1.5
            return math.sin(theta)*r,cy-math.cos(theta)*r*.75+.020*t*t+hand_clearance,z
        cache={}
        def sample(t,u,raw_panel=raw_panel,cache=cache):
            key=(round(float(t),7),round(float(u),7))
            if key in cache:return cache[key]
            q=raw_panel(t,u);base=drape_weights(raw_panel,t,u)
            fit,skin=under.project(q,cy,.018)
            blend=max(0,min(1,(q[2]-(waist-.34))/.065))
            blend=blend*blend*(3-2*blend)
            point=tuple(Vector(q).lerp(Vector(fit),blend))
            if skin:
                values={n:v*(1-blend) for n,v in base.items()}
                for n,v in skin.items():values[n]=values.get(n,0)+v*blend
                base=_Underlayer.normalize(values)
            cache[key]=(point,base);return cache[key]
        panel=lambda t,u,sample=sample:sample(t,u)[0]
        weights=lambda t,u,sample=sample:sample(t,u)[1]
        m.patch(18,10,panel,'white',weights,thickness=.003)
        for edge in [0,1]:
            samples=[(t,edge) for t in np.linspace(0,1,19)]
            skin=[weights(t,u) for t,u in samples for _ in range(6)]
            m.tube([panel(t,u) for t,u in samples],.00115,'silver',skin,6)
    for side in ['l','r']:
        knee=joint(body,groups,side+'-knee');ankle=joint(body,groups,side+'-ankle')
        def drape(i,point,boundary,knee=knee,ankle=ankle):
            q=Vector(point);t=max(0,min(1,(q.z-ankle.z)/max(.001,knee.z-ankle.z)))
            c=ankle.lerp(knee,t);direction=Vector((q.x-c.x,q.y-c.y,0))
            if direction.length>.001:q+=direction.normalized()*(.015+.032*math.sin(math.pi*t))
            return tuple(q)
        sign=1 if side=='l' else -1
        m.shell(body,raw,lambda x,h,d,s=sign:-6.85<h<-4.25 and x*s>0,
                'white',.011,.002,adjust=drape)
        # Tiny gold sewn bands sit on the gathered fabric, not thick metal rings.
        for t in [.11,.87,.94]:
            c=ankle.lerp(knee,t);radius=.073 if t>.5 else .057
            m.patch(3,48,lambda r,u,c=c,radius=radius:(c.x+(radius+.002*math.cos(u*TAU*12))*math.sin(u*TAU),
                      c.y-(radius*.86+.002*math.cos(u*TAU*12))*math.cos(u*TAU),c.z+(r-.5)*.011),
                    'gold','shin.'+side.upper(),thickness=.0015)
        c=ankle.lerp(knee,.965)
        m.patch(5,56,lambda t,u,c=c:(c.x+(.069+.003*math.cos(u*TAU*10))*math.sin(u*TAU),
                  c.y-(.062+.003*math.cos(u*TAU*10))*math.cos(u*TAU),c.z+t*(.025+.008*math.cos(u*TAU*10))),
                'white','shin.'+side.upper(),thickness=.002)
        # Open sandals preserve the anatomical toes and instep. The sole is
        # a closed loft; straps are curved surfaces over the foot, not blocks.
        toes = joint(body,groups,side+'-foot-2')
        front = min(body[i,1] for i in groups['body'] if raw[i,1]<-7.65 and raw[i,0]*sign>0)-.008
        rings = [(ankle.y+.065,.047),(ankle.y+.020,.063),(front+.055,.070),(front,.036)]
        verts=[]; faces=[]
        for y,w in rings:
            for j in range(20):
                a=TAU*j/20
                verts.append((ankle.x+w*math.cos(a),y,.015+.012*math.sin(a)))
        for k in range(3):
            for j in range(20):
                a=k*20+j; b=k*20+(j+1)%20;faces.append((a,b,b+20,a+20))
        faces.extend([tuple(range(19,-1,-1)),tuple(range(60,80))])
        m.add(verts,faces,'leather','foot.'+side.upper())
        for y,peak in [(front+.055,.068),(ankle.y-.048,.110)]:
            for offset in [-.008,.008]:
                points=[]
                for t in np.linspace(0,1,25):
                    points.append((ankle.x+(t-.5)*.125,y+offset,.025+peak*math.sin(math.pi*t)))
                m.tube(points,.004,'gold','foot.'+side.upper(),7)
        m.tube([(ankle.x-.045,ankle.y+.006,ankle.z+.075),
                (ankle.x,ankle.y-.042,ankle.z+.045),
                (ankle.x+.045,ankle.y+.006,ankle.z+.075)],.006,'leather','foot.'+side.upper(),8)


def add_costume_details(m,body,hero,level,top,waist,groups,raw):
    stage=0 if level<3 else 1 if level<5 else 2
    if hero=='yuno':
        neck=joint(body,groups,'neck')
        def ruff(t,u):
            a=TAU*u;ridge=.0028*math.cos(a*30)
            return ((.084+.014*(1-t)+ridge)*math.sin(a),
                    neck.y-(.070+.015*(1-t)+ridge)*math.cos(a),
                    neck.z-.014+t*(.046+.004*math.sin(a*24)))
        m.patch(8,84,ruff,'white','neck',thickness=.002)
        for side in ['l','r']:
            knee=joint(body,groups,side+'-knee');ankle=joint(body,groups,side+'-ankle')
            c=ankle.lerp(knee,.77)
            m.patch(5,56,lambda t,u,c=c:(c.x+(.066+.004*math.cos(u*TAU*16))*math.sin(u*TAU),
                        c.y-(.062+.004*math.cos(u*TAU*16))*math.cos(u*TAU),c.z+(t-.5)*.026),
                    'white','shin.'+side.upper(),thickness=.002)
        for ucenter in [.06,.94]:
            # The three-leaf Golden Dawn key motif is sewn into the cape.
            for direction in [-1,0,1]:
                def leaf(t,u,d=direction,uc=ucenter):
                    angle=d*math.pi*.62
                    along=.037*t;across=(u-.5)*.024*math.sin(math.pi*t)
                    dt=along*math.cos(angle)-across*math.sin(angle)
                    du=(along*math.sin(angle)+across*math.cos(angle))*.32
                    q=Vector(m.mantle_point(.69-dt,uc+du));q.y-=.0028
                    return tuple(q)
                def leaf_weights(t,u,d=direction,uc=ucenter):
                    angle=d*math.pi*.62;along=.037*t;across=(u-.5)*.024*math.sin(math.pi*t)
                    dt=along*math.cos(angle)-across*math.sin(angle)
                    du=(along*math.sin(angle)+across*math.cos(angle))*.32
                    return m.mantle_weights(.69-dt,uc+du)
                m.patch(10,8,leaf,'gold',leaf_weights,thickness=.0015)
            samples=list(np.linspace(.695,.91,22))
            m.tube([tuple(Vector(m.mantle_point(t,ucenter))+Vector((0,-.003,0)))
                    for t in samples],.0023,'gold',[m.mantle_weights(t,ucenter) for t in samples for _ in range(6)],6)
        for side in [-1,1]:
            for k in range(2):
                m.tube([(side*.205,-.057,top-.095-k*.008),
                        (side*.265,.008,top-.112-k*.008)],.0018,'gold','chest',6)
    elif hero=='magna':
        # Fitted ribbed waist wrap and a real hanging trouser chain.
        front,back,width=_torso_section(body,groups,waist+.07)
        for k in range(3):
            _belt(m,body,groups,waist+.035+k*.025,.025,'white')
        for k in range(13):
            t=k/12;c=Vector((-.11-.15*t,front-.034+.055*t,waist-.032-.135*math.sin(math.pi*t)))
            # Alternate link planes so this reads as chain rather than a cord.
            pts=[]
            for a in np.linspace(0,TAU,13):
                pts.append(tuple(c+Vector((.0065*math.sin(a),.0027*math.cos(a)*(1 if k%2 else .4),.010*math.cos(a)))))
            m.tube(pts,.0015,'silver','spine',6)
    elif hero=='asta':
        for side in ['l','r']:
            ankle=joint(body,groups,side+'-ankle');sign=1 if side=='l' else -1
            front=min(body[i,1] for i in groups['body'] if raw[i,1]<-7.4 and raw[i,0]*sign>0)-.010
            def toe(t,u,ankle=ankle,front=front):
                return ankle.x+(u-.5)*.126,front+.008+t*.080,.072+.025*math.sin(math.pi*u)+.008*t
            m.patch(8,18,toe,'white','foot.'+side.upper(),thickness=.0028)
            # Winged upper boot edge, soft tongue and three narrow leather ties.
            def cuff(t,u,c=ankle):
                a=TAU*u;z=c.z+.070+t*(.045+.028*abs(math.sin(a))**2)
                return c.x+.064*math.sin(a),c.y-.054*math.cos(a),z
            m.patch(7,48,cuff,'main','shin.'+side.upper(),thickness=.0025)
            for k in range(3):
                z=ankle.z+.027+k*.017
                m.tube([(ankle.x-.038,ankle.y-.043,z),
                        (ankle.x+.038,ankle.y-.043,z+.006)],.0024,'leather','foot.'+side.upper(),7)
    elif hero=='noelle':
        neck=joint(body,groups,'neck')
        def front_at(z,clearance=.008):
            if hasattr(m,'bodice_front_at_z'):return m.bodice_front_at_z(z)-clearance
            front,_,_=_torso_section(body,groups,z,.25)
            return front-.028-clearance
        def inset(t,u):
            z=waist+.15+(neck.z-.145-waist-.15)*t
            width=.008+.086*t;x=(u-.5)*2*width
            return x,front_at(z)+.007*(2*u-1)**2,z
        def inset_weights(t,u):
            z=inset(t,u)[2]
            phase=max(0,min(1,(z-(waist-.035))/max(.001,neck.z-.015-(waist-.035))))
            return {'spine':1-phase,'chest':phase}
        m.patch(24,18,inset,'accent',inset_weights,thickness=.0025)
        for edge in [0,1]:
            samples=[(t,edge) for t in np.linspace(0,1,25)]
            skin=[inset_weights(a,b) for a,b in samples for _ in range(7)]
            m.tube([inset(a,b) for a,b in samples],.0040,'white',skin,7)
        rope_z=neck.z-.125;rope_y=front_at(rope_z,.014)
        for strand in [-1,1]:
            m.tube([((t-.5)*.19,rope_y-.0025*math.sin(t*TAU*8),
                     rope_z-.015*math.sin(math.pi*t)+strand*.003*math.cos(t*TAU*8))
                    for t in np.linspace(0,1,41)],.0034,'mint','chest',7)
        m.patch(5,56,lambda t,u:(.073*math.sin(TAU*u),neck.y-.069*math.cos(TAU*u),neck.z+(t-.5)*.034),
                'accent','neck',thickness=.0018)
        c=Vector((0,front_at(neck.z-.020,.004),neck.z-.020))
        star=[]
        for k in range(17):
            a=TAU*k/16;r=.020 if k%2==0 else .008
            star.append(tuple(c+Vector((math.sin(a)*r,-.002,math.cos(a)*r))))
        m.tube(star,.0021,'silver','neck',6)
        m.ellipsoid(tuple(c+Vector((0,-.004,0))),(.006,.003,.008),'accent','neck',12,8)
        for k in range(2):
            _,belt_front=_belt(m,body,groups,waist,.022,'leather',tilt=.006,offset=-.016-k*.046)
        # Four raised clover petals and a small centre sit against the belt.
        for side in [-1,1]:
            for vertical in [-1,1]:
                m.ellipsoid((side*.014,belt_front-.005,waist-.017+vertical*.011),
                            (.013,.0038,.010),'gold','spine',14,8)
        m.ellipsoid((0,belt_front-.009,waist-.017),(.007,.004,.008),'gold','spine',12,8)
        for side in [-1,1]:
            m.tube([(side*.032,belt_front-.004,waist-.014),
                    (side*.053,belt_front+.001,waist-.023)],.0022,'gold','spine',6)
    elif hero=='vanessa':
        # The overskirt is a closed draped wrap: short overlapping front, long
        # asymmetric sides/back. It covers the generic shorts beneath it.
        front,back,hip=_torso_section(body,groups,waist-.085,.31)
        cy=(front+back)*.5;base=max(.172,min(.215,hip+.014))
        under=_Underlayer(m,{'cloth','pants','skin'},waist-.38,waist+.025)
        profile_z=np.linspace(waist-.28,waist+.02,41)
        profile=np.asarray([under.section(z) or (front,back) for z in profile_z])
        for _ in range(4):
            old=profile.copy();profile[1:-1]=old[1:-1]*.5+(old[:-2]+old[2:])*.25
        def raw_wrap(t,u):
            a=TAU*u;rear=max(0,-math.cos(a));side=abs(math.sin(a))
            length=.245+.38*rear**1.25+.065*side+.040*math.sin(a)
            r=base+.012*t+.006*math.sin(a*7+1.5*t)*math.sin(math.pi*t)
            z=waist-.015-length*t+.025*math.sin(a*3+.6)*t*t
            return math.sin(a)*r,cy-math.cos(a)*r*.74+.018*t,z
        anchors={};cache={}
        def sample(t,u):
            key=(round(float(t),7),round(float(u),7))
            if key in cache:return cache[key]
            q=Vector(raw_wrap(t,u));a=TAU*u
            if u not in anchors:
                anchor=(base*math.sin(a),cy-base*.74*math.cos(a),waist-.10)
                anchors[u]=under.project(anchor,cy,.018)[1] or {'root':1.0}
            weights=anchors[u]
            # A long wrap hangs from the seat envelope. Returning abruptly
            # to the narrower starting ellipse below the shorts makes a
            # false ledge/fringe rather than a continuous draped garment.
            probe_z=max(q.z,waist-.22)
            section=(float(np.interp(probe_z,profile_z,profile[:,0])),
                     float(np.interp(probe_z,profile_z,profile[:,1])))
            fit=Vector(q)
            if section:
                # Woven fabric bridges the seat/cleavage rather than copying
                # two shorts-shaped lobes onto the outside of the back wrap.
                front,back=section;cosine=math.cos(a)
                side_bend=.030*(abs(q.x)/.245)**4
                fade=max(0,min(1,(abs(cosine)-.10)/.40))
                fade=fade*fade*(3-2*fade)
                safe=front-.020+side_bend if cosine>0 else back+.020-side_bend
                wanted=min(fit.y,safe) if cosine>0 else max(fit.y,safe)
                fit.y+=fade*(wanted-fit.y)
            fit,matched=under.project(fit,cy,.018)
            blend=max(0,min(1,(q.z-(waist-.38))/.075))
            blend=blend*blend*(3-2*blend)
            point=tuple(fit)
            if matched:
                values={n:v*(1-blend) for n,v in weights.items()}
                for n,v in matched.items():values[n]=values.get(n,0)+v*blend
                weights=_Underlayer.normalize(values)
            cache[key]=(point,weights);return cache[key]
        wrap=lambda t,u:sample(t,u)[0]
        wrap_weights=lambda t,u:sample(t,u)[1]
        m.patch(30,84,wrap,'cloth',wrap_weights,thickness=.0034)
        samples=list(np.linspace(0,1,85))
        m.tube([wrap(1,u) for u in samples],.0021,'accent',
               [wrap_weights(1,u) for u in samples for _ in range(6)],6)
        # Diagonal overlap seam on the front is attached to the cloth.
        seam=[];skin=[]
        for t in np.linspace(.02,.96,25):
            u=.965-.14*t;q=Vector(wrap(t,u));q.y-=.003;seam.append(tuple(q))
            skin.extend([wrap_weights(t,u)]*6)
        m.tube(seam,.0020,'accent',skin,6)
        _,belt_front=_belt(m,body,groups,waist,.052,'ribbon',tilt=-.040,offset=.012)
        clasp=[(-.038,-.021),(-.030,.029),(.030,.029),(.039,-.018),(.028,-.028),(-.027,-.028),(-.038,-.021)]
        m.tube([(x,belt_front-.006,waist+.013+z) for x,z in clasp],.0045,'gold','spine',8)
        m.patch(5,8,lambda t,u:((u-.5)*.048,belt_front-.007,waist-.001+t*.027),
                'ribbon','spine',thickness=.002)
        for side in ['l','r']:
            sign=1 if side=='l' else -1
            ids=[i for i in groups['body'] if abs(raw[i,1]+3.25)<.25 and raw[i,0]*sign>0]
            z=float(body[ids,2].mean());center=body[ids].mean(axis=0)
            rx=float(np.ptp(body[ids,0]))*.5+.021;ry=float(np.ptp(body[ids,1]))*.5+.021
            def stocking(t,u,c=center,z=z,rx=rx,ry=ry):
                a=TAU*u
                return c[0]+rx*math.sin(a),c[1]-ry*math.cos(a),z-.022+t*(.025+.008*math.cos(a*6))
            m.patch(5,56,stocking,'cloth','thigh.'+side.upper(),thickness=.002)
            m.tube([stocking(1,u) for u in np.linspace(0,1,57)],.0020,'accent','thigh.'+side.upper(),6)


def add_rank_details(m, body, raw, hero, level, top, waist, groups):
    """Distinct sewn/armoured rank stages, never generic orbiting upgrades."""
    stage=0 if level<3 else 1 if level<5 else 2
    if level in [2,4]:
        front=m.bodice_front_at_z(waist)-.032 if hasattr(m,'bodice_front_at_z') else -.20
        for side in [-1,1]:
            m.patch(5,4,lambda t,u,s=side:(s*.125+(u-.5)*.018,front-.003*math.sin(math.pi*t),waist+(t-.5)*.082),
                    'leather' if hero!='noelle' else 'silver','spine',thickness=.002)
            if level==4:
                for k in range(2):
                    m.ellipsoid((side*.125,front-.006,waist+(k-.5)*.036),(.0035,.002,.004),'gold','spine',10,6)
    if stage==0: return
    if hero in ['asta','magna']:
        sides=['r'] if hero=='asta' else ['l','r']
        for side in sides:
            elbow=joint(body,groups,side+'-elbow');wrist=joint(body,groups,side+'-hand')
            eraw=raw[list(groups['joint-'+side+'-elbow'])].mean(axis=0)
            wraw=raw[list(groups['joint-'+side+'-hand'])].mean(axis=0)
            direction=wraw-eraw
            sign=1 if side=='l' else -1
            def region(x,h,d,sign=sign,eraw=eraw,direction=direction):
                phase=float(np.dot(np.array((x,h,d))-eraw,direction)/np.dot(direction,direction))
                return x*sign>2.2 and .43<phase<1.08
            mat='black' if hero=='asta' and stage==2 else 'leather'
            m.shell(body,raw,region,mat,.030,.002)
            if hero=='asta' and stage==2:
                axis=(wrist-elbow).normalized();u=axis.cross(Vector((0,1,0))).normalized()
                # Antimagic seams lie on the blackened sleeve surface.
                for k in [-1,1]:
                    points=[]
                    for t in np.linspace(.50,.94,18):
                        p=elbow.lerp(wrist,float(t))+u*(.046+.003*math.sin(t*26+k))
                        p.y-=.027+k*.008
                        points.append(tuple(p))
                    m.tube(points,.002,'accent','forearm.R',6)
            if hero=='magna':
                axis=(wrist-elbow).normalized();u=axis.cross(Vector((0,1,0))).normalized()
                v=axis.cross(u).normalized();center=elbow.lerp(wrist,.80)
                for k in range(3+stage):
                    a=TAU*k/(3+stage)
                    p=center+u*math.cos(a)*.067+v*math.sin(a)*.067
                    m.ellipsoid(tuple(p),(.005,.005,.005),'silver','forearm.'+side.upper(),10,6)
    elif hero=='yuno':
        # Sewn leaves on the outside of the curved cape. Their parameterized
        # placement remains fitted when shoulder clearance or cape folds change.
        for side in [-1,1]:
            seam_u=.42 if side>0 else .58
            for k in range(2+stage):
                def leaf(t,u,k=k,seam_u=seam_u):
                    p=Vector(m.mantle_point(.46+k*.063+.080*t,seam_u+(u-.5)*.035*math.sin(math.pi*t)))
                    p.y+=.0035+.0015*math.sin(math.pi*u)
                    return tuple(p)
                m.patch(10,8,leaf,'accent',lambda t,u,k=k,seam_u=seam_u:
                        m.mantle_weights(.46+k*.063+.080*t,seam_u+(u-.5)*.035*math.sin(math.pi*t)),thickness=.0018)
            if stage==2:
                samples=list(np.linspace(.44,.78,29))
                m.tube([tuple(Vector(m.mantle_point(t,seam_u))+Vector((0,.006,0))) for t in samples],.0025,'gold',
                       [m.mantle_weights(t,seam_u) for t in samples for _ in range(7)],7)
            front_u=.023 if side>0 else .977
            for k in range(stage+1):
                def front_leaf(t,u,k=k,front_u=front_u,side=side):
                    p=Vector(m.mantle_point(.39+k*.070+.073*t,front_u+(u-.5)*.027*math.sin(math.pi*t)))
                    p.y-=.004
                    return tuple(p)
                m.patch(10,8,front_leaf,'gold' if stage==2 else 'accent',lambda t,u,k=k,front_u=front_u:
                        m.mantle_weights(.39+k*.070+.073*t,front_u+(u-.5)*.027*math.sin(math.pi*t)),thickness=.0015)
    elif hero=='noelle':
        # Fitted overlapping Valkyrie feather plates on each forearm.
        for side in ['l','r']:
            elbow=joint(body,groups,side+'-elbow');wrist=joint(body,groups,side+'-hand')
            axis=(wrist-elbow).normalized();u=axis.cross(Vector((0,1,0))).normalized()
            v=axis.cross(u).normalized();center=elbow.lerp(wrist,.76)
            for k in range(3+stage):
                a=-.85+k*1.70/(2+stage)
                outward=u*math.cos(a)+v*math.sin(a)
                tangent=-u*math.sin(a)+v*math.cos(a)
                c=center+outward*.073
                m.patch(12,8,lambda t,s,c=c,outward=outward,tangent=tangent:tuple(c+axis*((t-.5)*.17)+tangent*((s-.5)*.055*math.sin(math.pi*t))+outward*(.015*math.sin(math.pi*t)*math.sin(math.pi*s))),
                        'silver' if stage==2 else 'white','forearm.'+side.upper(),thickness=.002)
    elif hero=='vanessa':
        # Corset stitching and a small attached Rouge cat charm on her pouch.
        bottom=waist+.25
        for k in range(4+stage):
            z=bottom+.018+k*.030
            for sign in [-1,1]:
                points=[];skin=[]
                for t in np.linspace(0,1,16):
                    point,weights=m.bodice_stitch(sign*(.020-.040*t),z+.024*t)
                    points.append(point);skin.extend([weights]*6)
                m.tube(points,.0018,'ribbon',skin,6)
        if stage==2:
            c=Vector((.212,-.044,waist-.13))
            cat=[(-.024,-.012),(-.025,.018),(-.032,.044),(-.009,.033),(.008,.033),(.030,.045),(.023,.017),(.024,-.012),(.014,-.028),(-.014,-.028),(-.024,-.012)]
            m.tube([tuple(c+Vector((x,-.002,z))) for x,z in cat],.003,'accent','spine',7)
            for side in [-1,1]:
                m.tube([tuple(c+Vector((side*.015,-.005,.013))),tuple(c+Vector((side*.006,-.005,.010)))],.002,'gold','spine',6)
