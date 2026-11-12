"""Surface-fitted oral rims and stable closed hair locks for enemy sculpts."""
import math
import numpy as np
from mathutils import Vector

TAU=math.tau


def mouth_rim(mesh, center, boundary, skin_point, species, skin_uv=None):
    """Bridge the coarse anatomical cut with a continuous sculpted lip edge.

    Both boundaries follow the face. The inner edge goes back into the real
    cavity; this is neither an opaque rectangle nor a painted mouth image.
    """
    center=Vector(center)
    rx=max(abs(p.x-center.x) for p in boundary)
    rz=max(abs(p.z-center.z) for p in boundary)
    outer_rx=rx*1.33
    outer_rz=max(.012,rz*1.40)
    inner_rx=rx*.88
    inner_rz=max(.005,rz*.57)
    rows=6;cols=72;verts=[];weights=[];faces=[];uv=[]
    for row in range(rows+1):
        t=row/rows
        for col in range(cols):
            a=TAU*col/cols
            x=center.x+(inner_rx+(outer_rx-inner_rx)*t)*math.cos(a)
            z=center.z+(inner_rz+(outer_rz-inner_rz)*t)*math.sin(a)
            p=skin_point(x,z,.0009)
            # A soft lip volume, merging back into the original skin at its
            # outer edge. At the opening it slopes behind the lower jaw.
            p.y-=.0025*math.sin(math.pi*t)
            if t<.20:p.y+=.002*(1-t/.20)
            verts.append(tuple(p));uv.append(skin_uv(x,z) if skin_uv else (x*2+.5,z*2))
            jaw=.65 if math.sin(a)<0 else .18
            weights.append({'head':1-jaw,'jaw':jaw})
    for row in range(rows):
        for col in range(cols):
            a=row*cols+col;b=row*cols+(col+1)%cols
            faces.append((a,b,b+cols,a+cols))
    mesh.add(verts,faces,'skin',weights,uv)
    return inner_rx,inner_rz


def stable_lock(mesh, points, width, depth, material='hair', weights='head'):
    """A closed tapered clump with parallel-transported elliptical frames."""
    control=[Vector(p) for p in points]
    count=24; sides=9;curve=[]
    for i in range(count+1):
        t=i/count
        if len(control)==4:
            curve.append(control[0]*(1-t)**3+control[1]*3*t*(1-t)**2+control[2]*3*t*t*(1-t)+control[3]*t**3)
        else:
            # Multi-point locks track the actual skull rather than cutting
            # straight through its crown between two Bezier handles.
            q=min(len(control)-2,int(t*(len(control)-1)))
            u=t*(len(control)-1)-q
            p0=control[max(0,q-1)];p1=control[q];p2=control[q+1];p3=control[min(len(control)-1,q+2)]
            curve.append((p1*2+(p2-p0)*u+(p0*2-p1*5+p2*4-p3)*u*u+(-p0+p1*3-p2*3+p3)*u*u*u)*.5)
    tangent=[(curve[min(count,i+1)]-curve[max(0,i-1)]).normalized() for i in range(count+1)]
    # Begin with the thin axis pointing through the head/back. Transport it,
    # rather than switching world reference when the tangent becomes vertical.
    thin=Vector((0,1,0));thin-=tangent[0]*thin.dot(tangent[0])
    if thin.length<.01:thin=Vector((1,0,0))-tangent[0]*tangent[0].x
    thin.normalize();verts=[];uv=[];faces=[]
    for i,p in enumerate(curve):
        if i:
            rotation=tangent[i-1].rotation_difference(tangent[i])
            thin=rotation@thin
            thin-=tangent[i]*thin.dot(tangent[i]);thin.normalize()
        wide=tangent[i].cross(thin).normalized()
        t=i/count
        taper=(.80+.20*math.sin(math.pi*t))*(1-t)**.72*min(1,.12+t*9)
        w=max(.0003,width*taper);d=max(.00025,depth*taper)
        for j in range(sides):
            a=TAU*j/sides
            verts.append(tuple(p+wide*(w*math.cos(a))+thin*(d*math.sin(a))))
            uv.append((j/sides,t))
    for i in range(count):
        for j in range(sides):
            a=i*sides+j;b=i*sides+(j+1)%sides;faces.append((a,b,b+sides,a+sides))
    faces.extend([tuple(range(sides-1,-1,-1)),tuple(count*sides+j for j in range(sides))])
    mesh.add(verts,faces,material,weights,uv)


def fitted_scalp(mesh, bvh, head, eye_z, neck, top):
    """A continuous ray-fitted scalp with a smooth anatomical hairline.

    Sampling the complete forehead avoids the square boundary produced by
    selecting source faces. The cap and every long lock share this surface.
    """
    head=Vector(head)
    def point(t,a,offset=.006):
        front=max(0,math.cos(a))**3;back=max(0,-math.cos(a))**2
        line=eye_z+.024+.083*front-(eye_z-neck+.055)*back
        # A weathered uneven hairline, smoothly sampled (not source-face
        # stair steps). This is deliberately not a uniform bowl/helmet edge.
        line+=.009*math.sin(a*7)+.006*math.sin(a*11+.7)
        z=top-.001-(top-.001-line)*math.sin(t*math.pi*.5)
        radial=Vector((math.sin(a),-math.cos(a),0))
        origin=Vector((0,head.y+.018,z))+radial*1.2
        hit=bvh.ray_cast(origin,-radial,2.4)
        if hit[0] is None:
            return Vector((radial.x*.004,head.y+.018+radial.y*.004,top+.004))
        return hit[0]+radial*offset
    rows=24;cols=96;verts=[];uv=[];faces=[]
    for row in range(rows+1):
        for col in range(cols):
            a=TAU*col/cols;t=row/rows
            p=point(t,a)
            verts.append(tuple(p));uv.append((col/cols,t))
    for row in range(rows):
        for col in range(cols):
            a=row*cols+col;b=row*cols+(col+1)%cols
            faces.append((a,a+cols,b+cols,b))
    mesh.add(verts,faces,'hair','head',uv)
    return point
