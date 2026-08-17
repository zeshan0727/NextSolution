#!/usr/bin/env python3
from pathlib import Path
import math, struct, zlib

ROOT = Path(__file__).resolve().parent

# Pure-Python PNG renderer so Theos builds do not need Pillow.
def inside_round_rect(x, y, n, r):
    if r <= x < n-r or r <= y < n-r:
        return True
    cx = r if x < r else n-r-1
    cy = r if y < r else n-r-1
    return (x-cx)**2 + (y-cy)**2 <= r*r

def dist_segment(px, py, ax, ay, bx, by):
    vx, vy = bx-ax, by-ay
    wx, wy = px-ax, py-ay
    vv = vx*vx + vy*vy
    t = 0 if vv == 0 else max(0, min(1, (wx*vx + wy*vy)/vv))
    qx, qy = ax+t*vx, ay+t*vy
    return math.hypot(px-qx, py-qy)

def render(size):
    scale = 4
    n = size*scale
    r = int(n*0.23)
    pix = bytearray(n*n*4)
    for y in range(n):
        for x in range(n):
            i=(y*n+x)*4
            if not inside_round_rect(x,y,n,r):
                pix[i:i+4]=bytes((0,0,0,0)); continue
            t=(x+y)/(2*(n-1))
            # Deep violet → electric blue, slightly darkened toward bottom.
            a=(118,32,226); b=(38,91,255)
            shade=0.96-0.23*(y/(n-1))
            rr=int((a[0]*(1-t)+b[0]*t)*shade)
            gg=int((a[1]*(1-t)+b[1]*t)*shade)
            bb=int((a[2]*(1-t)+b[2]*t)*shade)
            # Soft inner glow.
            d=math.hypot(x-n*0.34,y-n*0.24)/(n*0.8)
            glow=max(0,1-d)*15
            pix[i:i+4]=bytes((min(255,int(rr+glow)),min(255,int(gg+glow)),min(255,int(bb+glow)),255))

    # Draw a clean white N mark.
    thick=n*0.092
    segs=[(n*0.25,n*0.72,n*0.25,n*0.31),(n*0.25,n*0.31,n*0.63,n*0.72),(n*0.63,n*0.72,n*0.63,n*0.31)]
    for y in range(n):
        for x in range(n):
            if any(dist_segment(x,y,*s)<=thick/2 for s in segs):
                i=(y*n+x)*4
                if pix[i+3]: pix[i:i+4]=bytes((250,250,255,255))

    # Compact lock at top-right, integrated into the N.
    cx=n*0.70; body_y=n*0.29; bw=n*0.25; bh=n*0.23
    left=int(cx-bw/2); right=int(cx+bw/2); top=int(body_y); bottom=int(body_y+bh)
    shackle_cy=n*0.27; shackle_r=n*0.095; shackle_th=n*0.040
    for y in range(n):
        for x in range(n):
            i=(y*n+x)*4
            if not pix[i+3]: continue
            body=(left<=x<=right and top<=y<=bottom and inside_round_rect(x-left,y-top,max(right-left+1,bottom-top+1),int(n*0.035)))
            ring=abs(math.hypot(x-cx,y-shackle_cy)-shackle_r)<=shackle_th/2 and y<=shackle_cy+n*0.02
            if body or ring:
                pix[i:i+4]=bytes((250,250,255,255))
    # Purple keyhole cutout.
    for y in range(n):
        for x in range(n):
            if math.hypot(x-cx,y-(body_y+bh*0.43)) <= n*0.025 or (abs(x-cx)<=n*0.014 and body_y+bh*0.43<=y<=body_y+bh*0.72):
                i=(y*n+x)*4
                if pix[i+3]: pix[i:i+4]=bytes((83,49,199,255))

    # Downsample 4x with alpha-aware box filtering.
    out=bytearray(size*size*4)
    for oy in range(size):
        for ox in range(size):
            vals=[0,0,0,0]
            for sy in range(scale):
                for sx in range(scale):
                    i=(((oy*scale+sy)*n)+(ox*scale+sx))*4
                    for c in range(4): vals[c]+=pix[i+c]
            j=(oy*size+ox)*4
            out[j:j+4]=bytes(v//(scale*scale) for v in vals)
    return bytes(out)

def write_png(path, size):
    rgba=render(size)
    raw=b''.join(b'\x00'+rgba[y*size*4:(y+1)*size*4] for y in range(size))
    def chunk(tag,data):
        return struct.pack('>I',len(data))+tag+data+struct.pack('>I',zlib.crc32(tag+data)&0xffffffff)
    png=b'\x89PNG\r\n\x1a\n'+chunk(b'IHDR',struct.pack('>IIBBBBB',size,size,8,6,0,0,0))+chunk(b'IDAT',zlib.compress(raw,9))+chunk(b'IEND',b'')
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_bytes(png)

pref = ROOT/'layout'/'Library'/'PreferenceLoader'/'Preferences'
write_png(pref/'NextLockIcon.png',29)
write_png(pref/'NextLockIcon@2x.png',58)
write_png(pref/'NextLockIcon@3x.png',87)
# Larger copy used inside the preference bundle when requested by UIKit.
write_png(ROOT/'prefs'/'Resources'/'NextLockIcon.png',180)
print('Generated polished NextLock preference icons (29/58/87/180)')
