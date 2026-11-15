"""Landmark-fitted, fully volumetric Black Clover hairstyles and head props.

All dimensions follow the final sculpt rather than the old MakeHuman head size.
The scalp is a thin fitted underlayer; the silhouette comes from closed, broad,
overlapping clumps with buried roots. No hair cards or portrait textures.
"""
import math
import numpy as np
from mathutils import Vector
from mathutils.bvhtree import BVHTree

TAU = math.tau


def _unit(value, fallback=(0, -1, 0)):
    value = Vector(value)
    return value.normalized() if value.length > 1e-8 else Vector(fallback)


class _Hair:
    def __init__(self, mesh, body, groups, faces, eyes, hero):
        self.m = mesh
        self.hero = hero
        self.body = np.asarray(body)
        self.skin = self.body[sorted(groups['body'])]
        self.eyes = [Vector(p) for p in eyes]
        self.eye = sum(self.eyes, Vector()) / len(self.eyes)
        self.neck = Vector(self.body[list(groups['joint-neck'])].mean(axis=0))
        self.top = float(self.skin[:, 2].max())
        self.h = max(.10, self.top - self.neck.z)
        section = self.skin[(self.skin[:, 2] > self.eye.z + .12*self.h)
                            & (self.skin[:, 2] < self.top - .08*self.h)]
        if len(section) < 8:
            section = self.skin[self.skin[:, 2] > self.neck.z + .35*self.h]
        self.rx = max(.04, float(np.percentile(abs(section[:, 0]), 98)))
        front, back = np.percentile(section[:, 1], [2, 98])
        self.cy = float((front + back)*.5)
        self.ry = max(.04, float((back - front)*.5))
        self.center = Vector((self.eye.x, self.cy, self.eye.z + .10*self.h))
        self.tree = BVHTree.FromPolygons(
            [Vector(p) for p in self.body],
            [[q[0] for q in face] for group, face in faces if group == 'body'])

    def radial(self, p):
        return _unit((p.x-self.eye.x, p.y-self.cy,
                      max(0, p.z-self.eye.z)*.38))

    def line_z(self, angle):
        front = max(0, math.cos(angle))
        back_depth = {'asta': .34, 'yuno': .19, 'magna': .115,
                      'vanessa': .25, 'noelle': .25, 'charmy': .20}[self.hero]
        back = self.eye.z-back_depth*self.h
        brow = {'asta': .27, 'yuno': .16, 'magna': .23,
                'vanessa': .22, 'noelle': .20, 'charmy': .29}[self.hero]
        # The temple edge falls with the actual skull rather than forming a
        # single high circular hairline visible as a helmet on the forehead.
        line = back + (self.eye.z+brow*self.h-back)*front**1.8
        if self.hero == 'charmy':
            # A deliberate, smooth ear opening is above the actual ear. The
            # previous low cap followed the ear relief and let skin islands
            # protrude through the otherwise opaque dark hair.
            line += .35*self.h*abs(math.sin(angle))**8
        return line

    def cap(self, t, u, clearance=.012):
        a = TAU*u
        elevation = math.pi*.5*min(1, max(0, t))
        z0 = self.line_z(a)
        normal = _unit((math.sin(a)*math.cos(elevation),
                        -math.cos(a)*math.cos(elevation), math.sin(elevation)))
        point = Vector((self.eye.x + self.rx*math.sin(a)*math.cos(elevation),
                        self.cy-self.ry*math.cos(a)*math.cos(elevation),
                        z0+(self.top-z0)*math.sin(elevation)))
        hit, _, _, _ = self.tree.ray_cast(point+normal*self.h, -normal, self.h*2)
        if hit is not None and hit.z > self.neck.z+.10*self.h:
            point = hit
        if self.hero == 'charmy' and abs(math.sin(a)) > .65 and t < .45:
            clearance = max(clearance, .025)
        return point + normal*(clearance*self.h)

    def surface_at_z(self, a, z, clearance=.014):
        normal = Vector((math.sin(a), -math.cos(a), 0))
        start = Vector((self.eye.x, self.cy, z)) + normal*self.h*1.8
        hit, _, _, _ = self.tree.ray_cast(start, -normal, self.h*3.6)
        if hit is not None:
            return hit+normal*(clearance*self.h)
        return Vector((self.eye.x+self.rx*math.sin(a),
                       self.cy-self.ry*math.cos(a), z))+normal*clearance*self.h

    def base(self):
        rings, sides = 14, 64
        vertices, uv, faces = [], [], []
        for ring in range(rings):
            for k in range(sides):
                vertices.append(tuple(self.cap(ring/rings, k/sides)))
                uv.append((k/sides, ring/rings))
        pole = len(vertices)
        vertices.append(tuple(self.cap(1, 0)))
        uv.append((.5, 1))
        for ring in range(rings-1):
            for k in range(sides):
                a = ring*sides+k; b = ring*sides+(k+1)%sides
                faces.append((a, b, b+sides, a+sides))
        for k in range(sides):
            faces.append(((rings-1)*sides+k, (rings-1)*sides+(k+1)%sides, pole))
        faces.append(tuple(range(sides-1, -1, -1)))
        self.m.add(vertices, faces, 'hair', 'head', uv)

    def sweep(self, points, width, depth, material='hair', neck_follow=0,
              profile=None):
        """Closed, lenticular clump, parallel-transported along its spine."""
        points = [Vector(p) for p in points]
        sides = 12
        vertices, uv, faces, weights = [], [], [], []
        previous = None
        for i, point in enumerate(points):
            t = i/(len(points)-1)
            tangent = _unit(points[min(i+1, len(points)-1)]-points[max(0, i-1)], (0, 0, 1))
            radial = self.radial(point)
            lateral = radial.cross(tangent) if previous is None else previous-tangent*previous.dot(tangent)
            if lateral.length < .01:
                lateral = Vector((1, 0, 0))-tangent*tangent.x
            if lateral.length < .01:
                lateral = Vector((0, 1, 0))-tangent*tangent.y
            lateral.normalize()
            if previous is not None and lateral.dot(previous) < 0:
                lateral = -lateral
            previous = lateral.copy()
            outward = _unit(tangent.cross(lateral))
            shape = float(np.interp(t, [0, .13, .43, .78, 1],
                                    profile or [.33, 1, .94, .56, .012]))
            # The closed root end is submerged. Visible surfaces overlap with
            # neighboring clumps; there are no detached oval/leaf root caps.
            center = point-radial*(.045*self.h*(1-t)**6)
            for j in range(sides):
                a = TAU*j/sides
                # Broad shallow sculpted ridges, rather than narrow tubes
                # laid over an otherwise smooth inflated hair helmet.
                groove = 1+.08*math.cos(a*3+.55*math.sin(t*math.pi))*math.sin(math.pi*t)
                p = center+lateral*(math.cos(a)*width*shape)+outward*(math.sin(a)*depth*shape*groove)
                vertices.append(tuple(p)); uv.append((j/sides, t))
                blend = neck_follow*t*t
                weights.append({'head': 1-blend, 'neck': blend} if blend else {'head': 1})
        for row in range(len(points)-1):
            for j in range(sides):
                a = row*sides+j; b = row*sides+(j+1)%sides
                faces.append((a, b, b+sides, a+sides))
        faces.append(tuple(range(sides-1, -1, -1)))
        faces.append(tuple((len(points)-1)*sides+j for j in range(sides)))
        self.m.add(vertices, faces, material, weights, uv)

    def lock(self, controls, width, depth, material='hair', neck_follow=0, profile=None):
        p = [Vector(v) for v in controls]
        samples = [p[0]*(1-t)**3 + p[1]*(3*t*(1-t)**2)
                   + p[2]*(3*t*t*(1-t)) + p[3]*t**3 for t in np.linspace(0, 1, 19)]
        self.sweep(samples, width, depth, material, neck_follow, profile)

    def pos(self, x, y, z):
        """x/y use skull radii, z uses head height above eye level."""
        return Vector((self.eye.x+x*self.rx, self.cy+y*self.ry, self.eye.z+z*self.h))

    def fringe(self, xs, ends, widths, root_shift=0, root_height=.73,
               depth=.115, profile=None):
        for i, (x, end, width) in enumerate(zip(xs, ends, widths)):
            root = self.cap(root_height+.04*math.sin(i*1.7), (.025*x)%1)
            root.x = self.eye.x+(x*.55+root_shift)*self.rx
            self.lock([root, self.pos(x*.70+root_shift, -.72, .43),
                       self.pos(x*.93, -1.065, end+.16), self.pos(x, -1.035, end)],
                      width*self.rx, depth*self.rx, profile=profile)

    def side_nape(self, count=3, reach=1.18, length_scale=1, width_scale=1):
        for side in (-1, 1):
            for k in range(count):
                a = side*(1.12+k*.26)
                root = self.cap(.38+k*.05, (a/TAU)%1)
                end = self.pos(side*(reach-.04*k), -.08+.20*k, (-.24-.12*k)*length_scale)
                self.lock([root, self.pos(side*1.02, -.10+.22*k, .10),
                           self.pos(side*(reach+.08), -.04+.24*k, (-.14-.11*k)*length_scale), end],
                          .25*self.rx*width_scale, .13*self.rx*width_scale)
        for k in range(5):
            x = (k-2)*.35
            root = self.cap(.42, (.5+x*.055)%1)
            self.lock([root, self.pos(x*.9, 1.02, -.10*length_scale),
                       self.pos(x*1.12, 1.10, -.37*length_scale), self.pos(x*1.02, .94, (-.47+.035*abs(k-2))*length_scale)],
                      .24*self.rx*width_scale, .115*self.rx*width_scale)

    def headband(self, level):
        middle = self.eye.z+.255*self.h
        height = .145*self.h
        def band(t, u):
            a = TAU*u
            z = middle+(t-.5)*height-.026*self.h*max(0, -math.cos(a))
            return tuple(self.surface_at_z(a, z, .032))
        self.m.patch(5, 80, band, 'main', 'head', thickness=.008*self.h)
        if level >= 3:
            self.m.tube([band(.14, u) for u in np.linspace(0, 1, 81)],
                        .0025*self.h, 'gold', 'head', 6)
        # A raised, curved metal Bulls pin on the right frontal band.
        a = .61
        center = Vector(band(.51, a/TAU))
        normal = Vector((math.sin(a), -math.cos(a), 0))
        right = Vector((math.cos(a), math.sin(a), 0))
        shape = [(-.20,.36),(-.49,.50),(-.44,.19),(-.25,.11),
                 (-.21,-.20),(-.10,-.39),(0,-.43),(.10,-.39),
                 (.21,-.20),(.25,.11),(.44,.19),(.49,.50),(.20,.36),(.0,.31)]
        vertices=[]
        for depth in (0, .009*self.h):
            for x, z in shape:
                vertices.append(tuple(center+right*(x*.105*self.h)+Vector((0,0,z*.12*self.h))+normal*depth))
        n=len(shape)
        faces=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]
        faces += [(j,(j+1)%n,(j+1)%n+n,j+n) for j in range(n)]
        self.m.add(vertices, faces, 'gold', 'head')
        for side in (-1,1):
            p=center+right*(side*.014*self.h)+Vector((0,0,.004*self.h))+normal*.010*self.h
            self.m.ellipsoid(tuple(p),(.006*self.h,.006*self.h,.005*self.h),'black','head',10,6)
        # Two tied cloth ends follow the nape and stay attached to the knot.
        knot=self.surface_at_z(math.pi, middle, .036)
        self.m.ellipsoid(tuple(knot),(.050*self.h,.023*self.h,.037*self.h),'main','head',16,10)
        for side in (-1,1):
            self.lock([knot, knot+Vector((side*.035*self.h,.025*self.h,-.08*self.h)),
                       knot+Vector((side*.08*self.h,.07*self.h,-.22*self.h)),
                       knot+Vector((side*.065*self.h,.09*self.h,-.31*self.h))],
                      .045*self.h,.008*self.h,'main')

    def glasses(self):
        ordered=sorted(self.eyes,key=lambda p:p.x)
        for center in ordered:
            sign=1 if center.x>self.eye.x else -1
            w=.37*abs(ordered[1].x-ordered[0].x); h=.075*self.h
            outline=[(-1,.8),(.66,.75),(1,.18),(.83,-.58),(-.73,-.69),(-1,-.20)]
            points=[Vector((center.x+x*w,center.y-.040*self.h+.020*self.h*x*x,
                            center.z+z*h+sign*x*.015*self.h)) for x,z in outline]
            verts=[tuple(p+Vector((0,depth,0))) for depth in (0,.007*self.h) for p in points]
            n=len(points)
            faces=[tuple(range(n-1,-1,-1)),tuple(range(n,n*2))]
            faces += [(k,(k+1)%n,(k+1)%n+n,k+n) for k in range(n)]
            self.m.add(verts,faces,'lens','head')
            self.m.tube([tuple(p+Vector((0,-.002*self.h,0))) for p in points+[points[0]]],
                        .006*self.h,'steel','head',7)
            outer=points[2 if sign>0 else 0]
            self.m.tube([tuple(outer),tuple(self.pos(sign*1.01,-.30,.015)),
                         tuple(self.pos(sign*1.025,.35,-.035))],.006*self.h,'steel','head',7)
        left,right=ordered
        bridge=[(left.x+.028*self.h,left.y-.042*self.h,left.z+.018*self.h),
                (self.eye.x,min(left.y,right.y)-.065*self.h,self.eye.z+.032*self.h),
                (right.x-.028*self.h,right.y-.042*self.h,right.z+.018*self.h)]
        self.m.tube(bridge,.006*self.h,'steel','head',7)

    def asta(self, level):
        self.headband(level)
        # Short interlocking wedges sweep out and back. Unequal roots, lengths
        # and elevations avoid the former symmetric upright pineapple fan.
        ends=[(-1.36,.24,.035),(-1.00,.11,.105),(-.57,.38,.17),
              (-.10,.25,.235),(.38,.43,.14),(.91,.22,.12),(1.31,.34,.025)]
        wedge=[.72,1,.67,.26,.008]
        for k,(x,y,lift) in enumerate(ends):
            root=self.cap(.42+.08*math.sin(k*1.8),(.075*x+.012*(k%2))%1)
            end=self.pos(x,y,(self.top-self.eye.z)/self.h+lift)
            self.lock([root,self.pos(x*.70,-.43,.50+.04*(k%3)),
                       end+Vector((-x*.12*self.rx,-.13*self.ry,-.095*self.h)),end],
                      (.20+.012*(k%3))*self.rx,.108*self.rx,profile=wedge)
        angles=[.79,1.18,1.67,2.14,2.64,3.22,3.79,4.22,4.83,5.32,5.68]
        for k,a in enumerate(angles):
            root=self.cap(.32+.07*(k%3),a/TAU)
            normal=Vector((math.sin(a),-math.cos(a),.09)).normalized()
            end=self.cap(.66+.05*math.sin(k*1.8),a/TAU)+normal*((.15+.025*math.sin(k*2.4))*self.h)
            end.z+=(.035+.024*math.cos(k*1.3))*self.h
            self.lock([root,self.cap(.61,a/TAU)+normal*.035*self.h,
                       end-normal*.075*self.h,end],(.21+.012*(k%2))*self.rx,
                      .108*self.rx,profile=wedge)
        # A second elevation of smaller groups breaks the big-leaf silhouette.
        for k,x in enumerate([-.91,-.47,.08,.54,.98]):
            root=self.cap(.25+.025*(k%2),(.055*x)%1)
            end=self.pos(x*1.07,-.54+.13*(k%3),.49+.065*math.sin(k*1.9))
            self.lock([root,self.pos(x*.72,-.77,.36),
                       end+Vector((-.08*self.rx,-.02*self.ry,-.04*self.h)),end],
                      .175*self.rx,.085*self.rx,profile=wedge)
        self.side_nape(2,1.15,length_scale=.56,width_scale=.76)
        # One off-centre swept point; keep the right-hand band emblem visible.
        self.fringe([-.83,-.56,-.22,.18,.78], [.14,.105,.16,.025,.19],
                    [.16,.18,.16,.235,.14],root_shift=-.16,root_height=.62,
                    depth=.082,profile=[.46,1,.66,.25,.01])

    def yuno(self):
        # Short black clusters lie across one another and out toward the
        # silhouette, instead of making an upright ring of large leaf fins.
        wedge=[.65,1,.66,.28,.008]
        for k,a in enumerate([.17,.72,1.24,1.83,2.32,2.94,3.51,4.11,4.68,5.27,5.82]):
            root=self.cap(.37+.065*math.sin(k*1.6),a/TAU)
            normal=Vector((math.sin(a),-math.cos(a),.04)).normalized()
            end=self.cap(.69+.035*math.cos(k*1.4),a/TAU)+normal*((.095+.02*math.sin(k*1.9))*self.h)
            end.z+=(.018+.012*math.sin(k*2.1))*self.h
            self.lock([root,self.cap(.63,a/TAU)+normal*.025*self.h,
                       end-normal*.045*self.h,end],(.205+.015*(k%3))*self.rx,
                      .090*self.rx,profile=wedge)
        root=self.cap(.82,.48)
        self.lock([root,self.pos(-.12,.45,(self.top-self.eye.z)/self.h+.035),
                   self.pos(-.27,.37,(self.top-self.eye.z)/self.h+.105),
                   self.pos(-.20,.29,(self.top-self.eye.z)/self.h+.13)],
                  .13*self.rx,.075*self.rx,profile=wedge)
        self.fringe([-.86,-.61,-.31,-.02,.24,.53,.82],
                    [.09,.015,-.035,-.115,-.005,.06,.115],
                    [.15,.18,.18,.20,.165,.18,.14],root_shift=-.085,
                    root_height=.61,depth=.075,profile=[.48,1,.68,.25,.008])
        self.side_nape(2,1.045,length_scale=.58,width_scale=.72)

    def magna(self):
        for side in (-1,1):
            for k in range(5):
                a=side*(.78+.34*k)
                root=self.cap(.10+.035*k,(a/TAU)%1)
                tip=self.pos(side*(.24+.07*k),.34+.19*k,
                             (self.top-self.eye.z)/self.h+.060-.013*k)
                self.lock([root,self.pos(side*1.01,-.29+.21*k,.28),
                           tip+Vector((side*.20*self.rx,-.10*self.ry,-.07*self.h)),tip],
                          .20*self.rx,.10*self.rx,profile=[.68,1,.63,.26,.008])
        # The black widow's peak is a curved scalp surface, not a flat badge.
        def peak(t,u):
            a=(u-.5)*.58
            z0=self.eye.z+(.065+.18*abs(2*u-1))*self.h
            point=self.cap(t,a/TAU,.032)
            point.z+=(z0-self.line_z(a))*(1-t)**2
            normal=_unit((math.sin(a)*math.cos(t*math.pi*.5),
                          -math.cos(a)*math.cos(t*math.pi*.5),math.sin(t*math.pi*.5)))
            hit,_,_,_=self.tree.ray_cast(point+normal*self.h,-normal,self.h*2)
            if hit is not None:point=hit+normal*.032*self.h
            return tuple(point)
        self.m.patch(20,18,peak,'black','head',thickness=.009*self.h)
        for k in range(3):
            root=self.cap(.53,.46+.045*k)
            tip=self.pos((k-1)*.10,.14+.22*k,
                         (self.top-self.eye.z)/self.h+.115-.025*abs(k-1))
            self.lock([root,self.pos((k-1)*.11,-.10+.20*k,.49),
                       tip+Vector((-.04*self.rx,-.07*self.ry,-.055*self.h)),tip],
                      .16*self.rx,.105*self.rx,'black',profile=[.62,1,.67,.26,.008])
        self.side_nape(1,1.02,length_scale=.43,width_scale=.65)
        self.glasses()

    def vanessa(self):
        # Larger S-bends in fewer interlocking masses make shoulder waves,
        # instead of parallel vertical ribbons with tiny surface ripples.
        for k in range(9):
            a=.91+(TAU-1.82)*k/8
            def wave(t,a=a,k=k):
                if t<.28:return self.cap((.69+.035*math.sin(k))*(1-t/.28),a/TAU)
                s=(t-.28)/.72
                p=self.cap(0,a/TAU)
                radial=Vector((math.sin(a),-math.cos(a),0))
                tangent=Vector((math.cos(a),math.sin(a),0))
                wave=.36*math.sin(s*TAU*1.05+k*.25)*math.sin(math.pi*s*.94)
                p+=radial*((.055*s+wave)*self.rx)
                p+=tangent*(.15*self.rx*math.sin(s*math.pi*2.1+k*.3)*math.sin(math.pi*s))
                p.y+=.10*self.ry*s
                p.z-=(.68+.045*math.sin(k*1.7))*self.h*s
                return p
            self.sweep([wave(t) for t in np.linspace(0,1,29)],
                       .36*self.rx,.19*self.rx,neck_follow=.16,
                       profile=[.65,1,.96,.84,.15])
        # A low, asymmetric side part sweeps diagonally across the forehead.
        for k in range(2):
            root=self.cap(.70-.085*k,.95-.018*k)
            end=self.pos(.91+.06*k,-.98,.085-.045*k)
            self.lock([root,self.pos(-.12+.11*k,-.88,.39-.03*k),
                       self.pos(.62+.12*k,-1.09,.22-.04*k),end],
                      (.32-.035*k)*self.rx,.12*self.rx,
                      profile=[.62,1,.92,.56,.055])
        for side in (-1,1):
            for k in range(2):
                root=self.cap(.42+.11*k,(side*.18)%1)
                def curl(t,side=side,k=k,root=root):
                    q=root.lerp(self.pos(side*(1.03+.06*k),-.62+.09*k,-.56-.07*k),t)
                    q.x+=side*.43*self.rx*math.sin(t*math.pi*2.35+.22*k)*math.sin(math.pi*t)
                    q.y-=.29*self.ry*math.sin(t*math.pi*2.05+.15*k)*math.sin(math.pi*t)
                    return q
                self.sweep([curl(t) for t in np.linspace(0,1,27)],
                           .28*self.rx,.16*self.rx,neck_follow=.12,
                           profile=[.42,.94,1,.70,.08])

    def noelle(self):
        # Small partly overlapping groups make a soft, irregular short fringe.
        self.fringe([-.86,-.70,-.51,-.35,-.17,.01,.19,.39,.57,.74,.88],
                    [.255,.22,.235,.19,.21,.175,.205,.185,.235,.22,.265],
                    [.13,.15,.165,.14,.16,.18,.14,.17,.145,.15,.12],
                    root_shift=-.035,root_height=.55,depth=.075,
                    profile=[.38,1,.87,.54,.12])
        for side in (-1,1):
            tie=self.pos(side*1.03,.12,.24)
            for k in range(3):
                def tail(t,side=side,k=k,tie=tie):
                    return tie+Vector((side*(.08+.43*math.sin(t*math.pi*.85)+.08*(k-1))*self.rx,
                                       (.13*t+.05*(k-1))*self.h,
                                       -(1.58+.075*(k-1))*self.h*t))
                self.sweep([tail(t) for t in np.linspace(0,1,29)],
                           (.31 if k==1 else .23)*self.rx,.18*self.rx,
                           neck_follow=.12,profile=[.28,.92,1,.70,.02])
            self.lock([self.cap(.56,(side*.12)%1),
                       self.pos(side*.97,-.80,.22),self.pos(side*1.08,-.72,-.10),
                       self.pos(side*.94,-.58,-.26)],.22*self.rx,.11*self.rx)
            bowcenter=tie+Vector((side*.08*self.rx,-.35*self.ry,0))
            for direction in (-1,1):
                def bow(t,u,d=direction,s=side,c=bowcenter):
                    width=.16*self.h*math.sin(math.pi*(.06+.88*t))
                    return tuple(c+Vector((s*.15*self.h*t,
                         -.018*self.h*math.sin(math.pi*t)+(u-.5)*.028*self.h,
                         d*.12*self.h*t+(u-.5)*width)))
                self.m.patch(14,10,bow,'accent','head',thickness=.008*self.h)
            self.m.ellipsoid(tuple(bowcenter),(.035*self.h,.024*self.h,.040*self.h),
                             'accent','head',18,10)

    def charmy(self):
        # Swept broad panels hug the skull: a small tied bun is the dominant
        # feature, not an inflated cap or a row of blunt fringe cylinders.
        for k in range(9):
            a=TAU*k/9+.15
            points=[]
            for t in np.linspace(0,1,21):
                p=self.cap(.03+.88*t,(a/TAU+.045*math.sin(math.pi*t))%1)
                p+=self.radial(p)*(.010*self.h*math.sin(math.pi*t))
                points.append(p)
            self.sweep(points,.25*self.rx,.055*self.rx,
                       profile=[.15,.85,.85,.55,.01])
        center=Vector((self.eye.x+.035*self.rx,self.cy+.12*self.ry,self.top+.095*self.h))
        def bun(t,u):
            phi=math.pi*(.001+.998*t);a=TAU*u
            ridge=1+.055*math.cos(a*9+phi*1.8)*math.sin(phi)**2
            return tuple(center+Vector((.46*self.rx*math.sin(phi)*math.cos(a)*ridge,
                                        .42*self.ry*math.sin(phi)*math.sin(a)*ridge,
                                        .185*self.h*math.cos(phi))))
        self.m.patch(22,48,bun,'hair','head')
        for side in (-1,1):
            self.lock([self.cap(.23,(side*.16)%1),self.pos(side*1.025,-.53,.08),
                       self.pos(side*1.025,-.46,-.035),self.pos(side*.98,-.34,-.095)],
                      .12*self.rx,.060*self.rx)


def add_hair_and_accessories(m, body, hero, level, groups, faces, eye_centers):
    """Append one hero's hairstyle; all coordinates are final Blender space."""
    hair=_Hair(m,body,groups,faces,eye_centers,hero)
    hair.base()
    if hero=='asta':hair.asta(level)
    elif hero=='yuno':hair.yuno()
    elif hero=='magna':hair.magna()
    elif hero=='vanessa':hair.vanessa()
    elif hero=='noelle':hair.noelle()
    elif hero=='charmy':hair.charmy()
    else:raise ValueError('Unknown Black Clover hairstyle: '+str(hero))
