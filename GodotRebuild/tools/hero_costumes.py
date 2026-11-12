"""Character-specific sewn clothing geometry for the anatomical hero pipeline.

The module adds closed cloth surfaces and real embroidery/fasteners; no body
billboards or portrait textures. The caller owns all mesh, skin and atlas data.
"""
import math
import numpy as np
from mathutils import Vector

TAU = math.tau


def joint(body, groups, name):
    return Vector(body[list(groups['joint-' + name])].mean(axis=0))


def add_mantle(m, body, hero, stage, groups):
    """A shoulder seam, hanging panels and open front replace the domed cape."""
    neck = joint(body, groups, 'neck')
    top = neck.z + (.016 if hero == 'charmy' else -.012)
    length = {'asta': .405, 'magna': .425, 'yuno': .91,
              'vanessa': .365, 'noelle': .365, 'charmy': .285}[hero]
    half_width = {'asta': .370, 'magna': .350, 'yuno': .330,
                  'vanessa': .337, 'noelle': .325, 'charmy': .265}[hero]
    depth = {'asta': .195, 'magna': .185, 'yuno': .175,
             'vanessa': .185, 'noelle': .175, 'charmy': .150}[hero]
    surface = body[sorted(groups['body'])]
    sections = {}

    def torso_envelope(t):
        key = round(t, 6)
        if key not in sections:
            z = top-length*t
            samples = surface[(np.abs(surface[:,2]-z)<.055)&(np.abs(surface[:,0])<.29)]
            if len(samples):
                base_depth = float(np.interp(t,[0,.18,.34,1],[.075,depth*.85,depth,depth*1.03]))
                front = min(-base_depth, float(np.percentile(samples[:,1],2))-.046)
                back = max(base_depth+.018, float(np.percentile(samples[:,1],98))+.034)
                sections[key] = ((front+back)*.5,(back-front)*.5)
            else:
                sections[key] = (.023,None)
        return sections[key]

    def point(t, u):
        opening = (.64 + .23*t) if hero == 'yuno' else (.11 + .29*t)
        a = opening + u*(TAU - 2*opening)
        # The widest part sits at the shoulder seam. Below it cloth hangs
        # down with gravity instead of following a hemispherical profile.
        rx = float(np.interp(t, [0, .14, .30, .66, 1],
                             [.087, half_width*.76, half_width, half_width*1.015, half_width*1.06]))
        ry = float(np.interp(t, [0, .18, .34, 1], [.068, depth*.85, depth, depth*1.03]))
        sx = math.sin(a)
        # Subtle overlapping folds, with a flatter chest/back panel.
        fold = (.008*math.sin(a*11 + .8 + .45*t) + .003*math.sin(a*23 - .6))*t*t
        x = math.copysign(abs(sx)**.85, sx)*(rx+fold)
        cy, safe_ry = torso_envelope(t)
        if safe_ry is not None:
            ry = max(ry,safe_ry)
        y = cy - math.cos(a)*(ry+fold)
        uneven = .012*math.cos(a*5)*t*t
        if hero == 'asta': uneven += (.018*math.sin(a)+.018*abs(math.sin(a))-.016*max(0,-math.cos(a)))*t*t
        z = top - length*t + uneven
        if hero == 'yuno':
            # Long cape hangs behind the double-breasted coat and catches
            # a little air at its lower corners, with a complete inner side.
            y += .035*t*t*(1-math.cos(a))
        return x, y, z

    def weights(t, u):
        drape = .62*max(0, (t-.18)/.82)
        side = 'cape.L' if u > .5 else 'cape.R'
        return {'chest': 1-drape, 'cape': drape*.55, side: drape*.45}

    m.patch(32, 88, point, 'main', weights, thickness=.0032)
    for edge in [0, 1]:
        m.tube([point(t, edge) for t in np.linspace(0, 1, 33)], .0034, 'gold', 'chest', 7)
    m.tube([point(1, u) for u in np.linspace(0, 1, 89)], .0040, 'gold', 'cape', 7)
    # Shoulder construction seam is sewn into the actual cloth, not a ring
    # floating around the character.
    m.tube([point(.30, u) for u in np.linspace(0, 1, 65)], .0013, 'main', 'chest', 6)
    for edge in [0, 1]:
        x, y, z = point(.17, edge)
        m.ellipsoid((x, y-.005, z), (.012, .005, .012), 'gold', 'chest', 16, 8)
    if hero != 'yuno':
        left = Vector(point(.17, 0)); right = Vector(point(.17, 1))
        cord = []
        for t in np.linspace(0, 1, 20):
            p = left.lerp(right, float(t))
            p.y -= .008; p.z -= .022*math.sin(math.pi*t)
            cord.append(tuple(p))
        m.tube(cord, .0026, 'gold' if hero in ['asta', 'magna', 'charmy'] else 'silver', 'chest', 7)
    # Fit a crest to the front left panel, following its surface depth.
    crest = point(.56 if hero != 'yuno' else .33, .95)
    # Rank embroidery must follow the actual drape rather than use a fixed
    # depth that can leave it hidden inside the body or the back of the cape.
    m.mantle_point = point
    return top, top-length, crest


def add_bulls_crest(m, center, size=1.0, bone='chest'):
    c = Vector(center)
    # Recognisable bull forehead, outward horns, cheek/jaw and nostrils.
    outline = [(-.031,.028),(-.052,.044),(-.046,.014),(-.028,.004),
               (-.025,-.022),(-.012,-.039),(0,-.043),(.012,-.039),
               (.025,-.022),(.028,.004),(.046,.014),(.052,.044),
               (.031,.028),(.015,.032),(0,.029),(-.015,.032),(-.031,.028)]
    def at(x, z): return tuple(c+Vector((x*size, -.004, z*size)))
    m.tube([at(x,z) for x,z in outline], .0022*size, 'gold', bone, 6)
    for side in [-1, 1]:
        m.tube([at(side*.025,.009),at(side*.012,.003),at(side*.010,-.009)], .0023*size, 'gold', bone, 6)
        m.tube([at(side*.014,-.025),at(side*.006,-.024)], .0020*size, 'gold', bone, 6)


def add_noelle_skirt_and_gaiters(m, body, raw, groups, waist):
    # Lavender pleats under separate long petal-shaped overskirt panels.
    def skirt(t, u):
        a = TAU*u; r = .208 + .078*t + .010*t*math.cos(a*12)
        return math.sin(a)*r, -.018-math.cos(a)*r*.72, waist-.025-.28*t
    m.patch(22, 84, skirt, 'accent', 'spine', thickness=.0025)
    # Petals wrap round the hips; the front remains short, the rear splits
    # into the original long tails instead of ending as a generic miniskirt.
    for k in range(10):
        a = .22 + k*(TAU-.44)/10
        rear = max(0, -math.cos(a))
        side = abs(math.sin(a))
        length = .28 + .49*rear + .12*side
        def panel(t, u, a=a, length=length):
            theta = a+(u-.5)*.58
            r = .235 + .100*t + .035*t*t
            scallop = .065*math.sin(math.pi*u)*t*t
            return math.sin(theta)*r, -.018-math.cos(theta)*r*.75, waist-.035-length*t-scallop
        cape_bone = 'cape.L' if math.sin(a)<0 else 'cape.R'
        m.patch(18, 10, panel, 'white', lambda t,u,b=cape_bone:{'spine':1-t*.35,b:t*.35}, thickness=.0025)
        m.tube([panel(t,0) for t in np.linspace(0,1,19)], .0018, 'silver', cape_bone, 6)
    for side in ['l', 'r']:
        knee = joint(body, groups, side+'-knee'); ankle = joint(body, groups, side+'-ankle')
        def drape(i, point, boundary, side=side, knee=knee, ankle=ankle):
            q = Vector(point)
            t = max(0,min(1,(q.z-ankle.z)/max(.001,knee.z-ankle.z)))
            c = ankle.lerp(knee,t)
            direction = Vector((q.x-c.x,q.y-c.y,0))
            if direction.length>.001:
                q += direction.normalized()*(.018+.032*math.sin(math.pi*t))
            return tuple(q)
        sign = 1 if side=='l' else -1
        m.shell(body, raw, lambda x,h,d,s=sign: -6.85<h<-4.25 and x*s>0,
                'white', .012, .003, adjust=drape)
        # The top and bottom gathered cuffs have fitted fluted cloth geometry.
        for t in [.20,.87]:
            c = ankle.lerp(knee,t)
            radius = .072 if t>.5 else .057
            m.patch(5,40,lambda r,u,c=c,radius=radius:(c.x+(radius+.003*math.cos(u*TAU*12))*math.sin(u*TAU),
                       c.y-(radius*.86+.003*math.cos(u*TAU*12))*math.cos(u*TAU),c.z+(r-.5)*.042),
                    'gold','shin.'+side.upper(),thickness=.002)
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


def add_costume_details(m, body, hero, level, top, waist, groups, raw):
    stage = 0 if level<3 else 1 if level<5 else 2
    if hero == 'yuno':
        # Soft white high collar and boot trim identify the Golden Dawn uniform.
        neck = joint(body,groups,'neck')
        def ruff(t,u):
            a=TAU*u; ridge=.004*math.sin(a*32)
            return ((.087+.018*(1-t)+ridge)*math.sin(a),
                    neck.y-(.073+.017*(1-t)+ridge)*math.cos(a),
                    neck.z-.010+t*(.054+.006*math.sin(a*24)))
        m.patch(8,96,ruff,'white','neck',thickness=.002)
        for side in ['l','r']:
            knee=joint(body,groups,side+'-knee');ankle=joint(body,groups,side+'-ankle')
            c=ankle.lerp(knee,.73)
            m.patch(5,64,lambda t,u,c=c:(c.x+(.066+.006*math.sin(u*TAU*18))*math.sin(u*TAU),
                        c.y-(.065+.006*math.sin(u*TAU*18))*math.cos(u*TAU),c.z+(t-.5)*.035),
                        'white','shin.'+side.upper(),thickness=.002)
        for side in [-1,1]:
            for k in range(3):
                m.tube([(side*.22,-.055,top-.10-k*.008),(side*.29,.012,top-.10-k*.008)],.0025,'gold','chest',6)
    elif hero == 'magna':
        # Magna's rolled waist band, glove seams and pocket chain are physical
        # costume construction, rather than another shared tunic palette.
        for k in range(4):
            m.patch(3,64,lambda t,u,k=k:(math.sin(TAU*u)*.225,-.012-math.cos(TAU*u)*.163,
                       waist+.012+k*.019+(t-.5)*.020),'white','spine',thickness=.0018)
        for k in range(15):
            t=k/14; x=.18+.085*math.sin(math.pi*t); z=waist-.03-.27*t
            y=-.105+.018*math.sin(math.pi*t)
            m.tube([(x+.006*math.sin(TAU*u),y-.003*math.cos(TAU*u),z+.010*math.cos(TAU*u))
                    for u in np.linspace(0,1,13)],.0018,'silver','spine',6)
    elif hero == 'asta':
        # Black boots with contrasting protected toes from the supplied model.
        for side in ['l','r']:
            ankle=joint(body,groups,side+'-ankle');sign=1 if side=='l' else -1
            front=min(body[i,1] for i in groups['body'] if raw[i,1]<-7.4 and raw[i,0]*sign>0)-.010
            def toe(t,u,ankle=ankle,front=front):
                x=(u-.5)*.125
                y=front+.010+t*.082
                return ankle.x+x,y,.074+.023*math.sin(math.pi*u)+.010*t
            m.patch(8,18,toe,'silver','foot.'+side.upper(),thickness=.002)
            for k in range(3):
                z=ankle.z+.048+k*.019
                m.tube([(ankle.x-.043,ankle.y-.035,z),(ankle.x+.043,ankle.y-.035,z+.008)],.003,'leather','foot.'+side.upper(),7)
    elif hero == 'noelle':
        neck=joint(body,groups,'neck')
        surface=body[sorted(groups['body'])]
        # Purple inset and rolled white V edges are fitted to the existing
        # bodice. They identify the costume without exposing a disconnected
        # painted triangle or replacing the underlying three-dimensional coat.
        def inset(t,u):
            z=waist+.16+(neck.z-.14-waist-.16)*t
            width=.018+.095*t
            x=(u-.5)*2*width
            section=surface[(np.abs(surface[:,2]-z)<.055)&(np.abs(surface[:,0])<.25)]
            front=m.bodice_front_at_z(z)-.010 if hasattr(m,'bodice_front_at_z') else float(section[:,1].min())-.039 if len(section) else -.19
            return x,front+.010*(2*u-1)**2,z
        m.patch(24,18,inset,'accent',lambda t,u:{'spine':1-t,'chest':t},thickness=.002)
        for edge in [0,1]:
            m.tube([inset(t,edge) for t in np.linspace(0,1,25)],.006,'white','chest',8)
        rope_z=neck.z-.115
        rope_section=surface[(np.abs(surface[:,2]-rope_z)<.06)&(np.abs(surface[:,0])<.20)]
        rope_front=m.bodice_front_at_z(rope_z)-.012 if hasattr(m,'bodice_front_at_z') else float(rope_section[:,1].min())-.040 if len(rope_section) else -.17
        for strand in [-1,1]:
            m.tube([((t-.5)*.20,rope_front-.004*math.sin(t*TAU*8),rope_z-.020*math.sin(math.pi*t)+strand*.004*math.cos(t*TAU*8))
                    for t in np.linspace(0,1,49)],.0045,'mint','chest',7)
        # Neck ribbon, a silver star and double waist belts with a clover buckle.
        m.patch(5,64,lambda t,u:(.077*math.sin(TAU*u),neck.y-.073*math.cos(TAU*u),neck.z+(t-.5)*.045),
                'accent','neck',thickness=.0015)
        c=Vector((0,-.106,neck.z-.020))
        star=[]
        for k in range(17):
            a=TAU*k/16;r=.022 if k%2==0 else .010
            star.append(tuple(c+Vector((math.sin(a)*r,-.001,math.cos(a)*r))))
        m.tube(star,.0025,'silver','neck',6)
        for k in range(2):
            m.patch(3,64,lambda t,u,k=k:(math.sin(TAU*u)*.241,-.010-math.cos(TAU*u)*.178,
                        waist-.025-k*.052+(t-.5)*.028),'leather','spine',thickness=.002)
        for side in [-1,1]:
            for leaf in [-1,1]:
                m.ellipsoid((side*.018,-.196,waist-.022+leaf*.010),(.018,.006,.015),'gold','spine',16,10)
    elif hero == 'vanessa':
        # Scalloped stocking edges and a diagonal purple belt mirror the
        # existing official reference without adding unrelated armour plates.
        for side in ['l','r']:
            knee=joint(body,groups,side+'-knee')
            m.patch(5,64,lambda t,u,knee=knee:(knee.x+.088*math.sin(TAU*u),knee.y-.084*math.cos(TAU*u),
                       knee.z+.16+(t-.5)*.045+.012*math.cos(TAU*u*8)),
                    'cloth','thigh.'+side.upper(),thickness=.002)
        m.patch(4,72,lambda t,u:(math.sin(TAU*u)*.246,-.013-math.cos(TAU*u)*.183,
                    waist+.012-.043*math.sin(TAU*u)+(t-.5)*.046),'ribbon','spine',thickness=.0025)
        for side in [-1,1]:
            m.tube([(side*.032,-.202,waist-.022),(side*.032,-.202,waist+.033)],.005,'silver','spine',8)


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
                m.patch(10,8,leaf,'accent','cape.L' if side<0 else 'cape.R',thickness=.0018)
            if stage==2:
                m.tube([tuple(Vector(m.mantle_point(t,seam_u))+Vector((0,.006,0))) for t in np.linspace(.44,.78,29)],.0025,'gold','cape',7)
            front_u=.023 if side>0 else .977
            for k in range(stage+1):
                def front_leaf(t,u,k=k,front_u=front_u,side=side):
                    p=Vector(m.mantle_point(.39+k*.070+.073*t,front_u+(u-.5)*.027*math.sin(math.pi*t)))
                    p.y-=.004
                    return tuple(p)
                m.patch(10,8,front_leaf,'gold' if stage==2 else 'accent','chest',thickness=.0015)
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
            y=m.bodice_front_at_z(z)-.009 if hasattr(m,'bodice_front_at_z') else -.20
            m.tube([(-.020,y,z),(.020,y-.001,z+.024)],.0018,'ribbon','chest',6)
            m.tube([(.020,y,z),(-.020,y-.001,z+.024)],.0018,'ribbon','chest',6)
        if stage==2:
            c=Vector((.212,-.044,waist-.13))
            cat=[(-.024,-.012),(-.025,.018),(-.032,.044),(-.009,.033),(.008,.033),(.030,.045),(.023,.017),(.024,-.012),(.014,-.028),(-.014,-.028),(-.024,-.012)]
            m.tube([tuple(c+Vector((x,-.002,z))) for x,z in cat],.003,'accent','spine',7)
            for side in [-1,1]:
                m.tube([tuple(c+Vector((side*.015,-.005,.013))),tuple(c+Vector((side*.006,-.005,.010)))],.002,'gold','spine',6)
