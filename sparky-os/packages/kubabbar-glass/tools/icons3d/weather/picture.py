# SPDX-License-Identifier: GPL-3.0-only
"""PNG and SVGStereo output from the two full-view projections."""
import math
import struct
import xml.etree.ElementTree as ET
import zlib

import numpy as np

SVG = 'http://www.w3.org/2000/svg'
STEREO = 'https://github.com/Sparky-OS/svgstereo'
LAYOUT = 'sideBySideLeftFirst'
ET.register_namespace('',SVG)
ET.register_namespace('stereo',STEREO)


def chunk(kind, data):
    body = kind+data
    return struct.pack('>I',len(data))+body+struct.pack('>I',zlib.crc32(body))


def write_png(path, views, pair_mark=False):
    left,right = views
    h,w,_ = left.shape
    assert left.shape==right.shape and left.dtype==right.dtype==np.uint16
    padding = (-w)%8 if pair_mark else 0
    rgba = np.concatenate((left,np.zeros((h,padding,4),np.uint16),right),axis=1)
    stride = 2*w+padding
    raw = b''.join(b'\0'+row.astype('>u2').tobytes() for row in rgba)
    header = struct.pack('>IIBBBBB',stride,h,16,6,0,0,0)
    stereo = chunk(b'sTER',b'\1') if pair_mark else b''
    path.write_bytes(b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',header)+chunk(b'sRGB',b'\0')+stereo+
                     chunk(b'IDAT',zlib.compress(raw,4))+chunk(b'IEND',b''))


def project(point, size, camera, distance, hfov, sign):
    base,convergence = camera
    x,y,z = point
    focal = size/(2*math.tan(hfov/2))
    offset = sign*base/2
    depth = distance-z
    return size/2+focal*((x-offset)/depth+offset/convergence), size/2-focal*y/depth


def add(parent, element, **attrs):
    return ET.SubElement(parent,f'{{{SVG}}}{element}',attrs)


def draw_svg(path, phases, camera, distance, hfov, size=64):
    root=ET.Element(f'{{{SVG}}}svg',{'viewBox':f'0 0 {2*size} {size}','width':str(2*size),'height':str(size),
                                    'overflow':'hidden',f'{{{STEREO}}}layout':LAYOUT})
    for index,pose in enumerate(phases):
        hidden = -4*size
        offscreen = 0 if index==0 else hidden
        group=add(root,'g',id=f'frame-{index}',transform=f'translate({offscreen} 0)')
        if len(phases)>1:
            # Standard players switch discretely. Qt 6.11 spaces these values
            # uniformly, so the transition can last at most one millisecond.
            values=';'.join(f'{(0 if tick//100%len(phases)==index else hidden)-offscreen} 0'
                            for tick in range(100*len(phases)+1))
            add(group,'animateTransform',attributeName='transform',type='translate',calcMode='discrete',
                values=values,dur='1200ms',repeatCount='indefinite',additive='sum')
        for eye,sign in enumerate((-1,1)):
            view=add(group,'g',transform=f'translate({eye*size} 0)')
            for shape in sorted(pose,key=lambda s:sum(v[2] for v in s.outline)/len(s.outline)):
                points=[project(p,size,camera,distance,hfov,sign) for p in shape.outline]
                if any(min(x,y)<1 or max(x,y)>size-1 for x,y in points):
                    raise ValueError(f'{shape.name} overlaps the SVG margin: {points[:3]}')
                point_text=' '.join(f'{x:.5f},{y:.5f}' for x,y in points)
                add(view,'polygon',points=point_text,fill='#'+shape.colour,opacity=f'{shape.alpha:.6f}',
                    **{'data-feature':shape.name})
    ET.ElementTree(root).write(path,encoding='utf-8',xml_declaration=True)


def join_report(params, phases, disc_back):
    from geometry import model
    endpoint=model(params,11/12+1/12,disc_back)
    a,b=phases[0],endpoint
    assert len(a)==len(b)
    assert a==b
    return dict(advanced_geometry_max=0,advanced_alpha_max=0)
