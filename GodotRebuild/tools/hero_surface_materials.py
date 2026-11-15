"""Deterministic PBR cloth/leather/skin surfaces, packed by the hero atlas tool."""
from pathlib import Path
import json
import math
import bpy
import numpy as np

REVISION = 'portrait-and-fabric-20261113-v2'


def material(hero, name, color, kind, output):
    mat = bpy.data.materials.new(hero+'_'+name)
    mat.use_nodes = True
    mat.diffuse_color = (*color,1)
    principled = mat.node_tree.nodes.get('Principled BSDF')
    principled.inputs['Base Color'].default_value = (*color,1)
    roughness = {'skin':.74,'hair':.73,'fabric':.88,'leather':.68,
                 'metal':.36,'iris':.30,'eye':.23}.get(kind,.82)
    principled.inputs['Roughness'].default_value = roughness
    if kind in ['skin','hair']:
        principled.inputs['Specular IOR Level'].default_value = .28
    if kind=='metal': principled.inputs['Metallic'].default_value = .72
    if kind not in ['skin','hair','fabric','leather','metal','iris']:
        return mat
    folder = Path(output)/'TexturesV4'
    folder.mkdir(parents=True,exist_ok=True)
    prefix = folder/(hero+'_'+name)
    signature = prefix.with_suffix('.surface.json')
    settings = {'revision':REVISION,'kind':kind,'color':list(color),'size':512}
    paths = {channel:Path(str(prefix)+'_'+channel+'.png') for channel in ['base','roughness','normal']}
    rebuild = not signature.exists() or any(not p.exists() for p in paths.values())
    if not rebuild:
        rebuild = json.loads(signature.read_text()) != settings
    if rebuild:
        size=512; yy,xx=np.mgrid[0:size,0:size]
        rng=np.random.default_rng(sum((k+1)*ord(c) for k,c in enumerate(hero+name)))
        grain=rng.normal(0,1,(size,size))
        tone=grain*.006
        relief=grain*.0008
        if kind=='fabric':
            # The preceding sin(x*pi) vanished at integer texels. Offset,
            # non-integer warp/weft frequencies create an actual twill weave.
            warp=np.sin((xx+.35)*1.03+np.sin(yy*.07)*.12)
            weft=np.sin((yy+.22)*.94+np.sin(xx*.06)*.10)
            diagonal=np.sin((xx-yy)*.48)
            weave=(warp*weft*.65+diagonal*.35)
            tone+=weave*.026
            relief=weave*.021+grain*.0015
        elif kind=='leather':
            cells=np.sin(xx*.25+np.sin(yy*.17))*np.sin(yy*.22+np.cos(xx*.13))
            tone+=cells*.032
            relief=cells*.022+grain*.004
        elif kind=='hair':
            strands=np.sin(xx*.61+np.sin(yy*.014)*1.8)
            tone+=strands*.030
            relief=strands*.010+grain*.0005
        elif kind=='metal':
            brushing=np.sin(xx*1.1+yy*.025)
            scratches=(np.sin(xx*.91+yy*.37)>.993).astype(float)
            tone+=brushing*.010-scratches*.025
            relief=brushing*.004-scratches*.008
        elif kind=='skin':
            # Small pores only: the character's nose/lips/eyelids are geometry.
            broad=np.sin(xx*.018)*np.cos(yy*.014)
            tone+=broad*.008
            relief=grain*.00065
        elif kind=='iris':
            dx=(xx-size*.5)/(size*.5);dy=(yy-size*.5)/(size*.5)
            radius=np.sqrt(dx*dx+dy*dy);angle=np.arctan2(dy,dx)
            fibers=(.82+.18*np.sin(angle*79+radius*12))*(.86+.14*np.sin(angle*131-radius*7))
            limbus=1-.67*np.exp(-((radius-.95)/.055)**2)
            tone=(.78+.32*np.exp(-((radius-.48)/.22)**2))*fibers*limbus-1
            relief=np.zeros_like(tone)
        base=np.ones((size,size,4),np.float32)
        base[:,:,:3]=np.clip(np.asarray(color)[None,None,:]*(1+tone[:,:,None]),0,1)
        rough=np.ones((size,size,4),np.float32)
        rough[:,:,:3]=np.clip(roughness+relief[:,:,None]*.65+grain[:,:,None]*.005,.18,.98)
        dy,dx=np.gradient(relief)
        normals=np.dstack((-dx*2.2,-dy*2.2,np.ones_like(dx)))
        normals/=np.maximum(np.linalg.norm(normals,axis=2,keepdims=True),1e-8)
        normal=np.ones((size,size,4),np.float32)
        normal[:,:,:3]=normals*.5+.5
        for channel,pixels in [('base',base),('roughness',rough),('normal',normal)]:
            image=bpy.data.images.new(hero+'_'+name+'_'+channel,width=size,height=size)
            if channel!='base': image.colorspace_settings.name='Non-Color'
            image.pixels.foreach_set(pixels.ravel())
            image.filepath_raw=str(paths[channel]);image.file_format='PNG'
            image.save();bpy.data.images.remove(image)
        signature.write_text(json.dumps(settings),encoding='utf-8')
    def image_texture(channel):
        image=bpy.data.images.load(str(paths[channel]),check_existing=True)
        if channel!='base': image.colorspace_settings.name='Non-Color'
        node=mat.node_tree.nodes.new('ShaderNodeTexImage');node.image=image
        return node
    mat.node_tree.links.new(image_texture('base').outputs['Color'],principled.inputs['Base Color'])
    mat.node_tree.links.new(image_texture('roughness').outputs['Color'],principled.inputs['Roughness'])
    normal=image_texture('normal')
    node=mat.node_tree.nodes.new('ShaderNodeNormalMap');node.space='TANGENT'
    mat.node_tree.links.new(normal.outputs['Color'],node.inputs['Color'])
    mat.node_tree.links.new(node.outputs['Normal'],principled.inputs['Normal'])
    return mat
