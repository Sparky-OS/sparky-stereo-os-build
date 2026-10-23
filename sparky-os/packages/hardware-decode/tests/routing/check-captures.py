#!/usr/bin/env python3
import argparse, array, json, struct, sys, zlib
from pathlib import Path

def png(path):
    data=path.read_bytes();pos=8;blocks=b''
    while pos<len(data):
        n=int.from_bytes(data[pos:pos+4],'big');kind=data[pos+4:pos+8];chunk=data[pos+8:pos+8+n]
        if kind==b'IHDR':
            w,h,bits,colour,_,_,interlace=struct.unpack('>IIBBBBB',chunk)
            assert colour in (2,6) and interlace==0,path
            channels=3 if colour==2 else 4
        if kind==b'IDAT':blocks+=chunk
        pos+=n+12
    stream=zlib.decompress(blocks);bpp=channels*bits//8;stride=w*bpp;prior=bytearray(stride);out=bytearray()
    for y in range(h):
        mode=stream[y*(stride+1)];row=bytearray(stream[y*(stride+1)+1:(y+1)*(stride+1)])
        for x in range(stride):
            left=row[x-bpp] if x>=bpp else 0;up=prior[x];corner=prior[x-bpp] if x>=bpp else 0
            if mode==0:predict=0
            elif mode==1:predict=left
            elif mode==2:predict=up
            elif mode==3:predict=(left+up)//2
            else:
                assert mode==4,path
                p=left+up-corner;dist=[abs(p-left),abs(p-up),abs(p-corner)];predict=[left,up,corner][dist.index(min(dist))]
            row[x]=(row[x]+predict)&255
        out.extend(row);prior=row
    values=array.array('H' if bits==16 else 'B');values.frombytes(out)
    if bits==16 and sys.byteorder=='little':values.byteswap()
    if channels==4:
        values=array.array(values.typecode,(v for i,v in enumerate(values) if i%4<3))
    return w,h,bits,values

p=argparse.ArgumentParser();p.add_argument('work',type=Path);a=p.parse_args()
for gpu in ('amd','nvidia'):
    for api in ('vulkan','opengl'):
        for film in ('h264-right8','hevc-eyes12','h264-2d8'):
            base=a.work/'captures'/f'capture-{gpu}'
            sw=png(base/f'{api}-{film}-no.png');hw=png(base/f'{api}-{film}-auto.png')
            assert sw[:3]==hw[:3],(gpu,api,film,hw[:3])
            meta=json.loads((base/f'{api}-{film}-auto.json').read_text())
            assert hw[:2]==(meta['output']['dw'],meta['output']['dh']),(gpu,api,film,hw[:3],meta)
            maximum=max(abs(x-y) for x,y in zip(sw[3],hw[3]))
            assert maximum<=(4 if hw[2]==16 else 1),(gpu,api,film,maximum)
            if film=='hevc-eyes12':assert hw[2]==16,(gpu,api,film)
            if film=='h264-right8':
                row=hw[3][20*640*3:21*640*3]
                assert sum(row[:320*3])<sum(row[320*3:]),(gpu,api,'eye order')
            meta=json.loads((base/f'{api}-{film}-auto.json').read_text())
            if film=='h264-2d8':assert meta['output']['stereo-in']=='mono',meta
            else:assert meta['output']['stereo-in']=='sbsl',meta
            print(gpu,api,film,'PNG bits',hw[2],'max component difference',maximum,'PASS')
