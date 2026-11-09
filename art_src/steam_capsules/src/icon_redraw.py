# Redraw of collimators-frontline-icon.png as shapes, in the original's 160-unit coordinates.
import math, numpy as np
from PIL import Image, ImageDraw
K=16; N=160*K
def P(x,y): return (x*K,y*K)
def hexc(h,a=255): h=h.lstrip('#'); return (int(h[0:2],16),int(h[2:4],16),int(h[4:6],16),a)
img=Image.new("RGBA",(N,N),(0,0,0,0))
def layer(): return Image.new("L",(N,N),0)
def paint(mask, color):
    global img
    c=Image.new("RGBA",(N,N),color if isinstance(color,tuple) else hexc(color))
    if not isinstance(color,tuple) or True:
        img=Image.composite(c,img,mask) if c.mode=="RGBA" and color[3:]==() or True else img
def fill(mask,color):
    global img
    col=hexc(color) if isinstance(color,str) else color
    c=Image.new("RGBA",(N,N),col[:3]+(255,))
    m=np.asarray(mask).astype(float)*(col[3]/255.0)
    img=Image.composite(c,img,Image.fromarray(m.astype(np.uint8)))
def fill_arr(mask,rgb):  # rgb: HxWx3 array
    global img
    c=Image.fromarray(np.dstack([rgb.astype(np.uint8),np.full((N,N),255,np.uint8)]),"RGBA")
    img=Image.composite(c,img,mask)
def circle(d,cx,cy,r,**kw): d.ellipse([ (cx-r)*K,(cy-r)*K,(cx+r)*K,(cy+r)*K ],**kw)
def arc(d,cx,cy,r,a0,a1,w,fillv=255): d.arc([(cx-r)*K,(cy-r)*K,(cx+r)*K,(cy+r)*K],a0,a1,fill=fillv,width=int(w*K))
C=80
# outer disc
m=layer(); d=ImageDraw.Draw(m); circle(d,C,C,80,fill=255); fill(m,"#081a2f")
# bright outer ring with gaps at the cardinals
m=layer(); d=ImageDraw.Draw(m)
# PIL arc angles: 0 = right, 90 = down. Breaks at top/bottom (+-14) and the diagonals (+-2.5).
segs=[(-76,-47.5),(-42.5,42.5),(47.5,76),(104,132.5),(137.5,222.5),(227.5,256)]
for a0,a1 in segs: arc(d,C,C,78.3,a0,a1,4.2)
fill(m,"#2283a6")
m=layer(); d=ImageDraw.Draw(m)
for a in (90,270): arc(d,C,C,78.3,a-14,a+14,4.2)
fill(m,"#123d55")
# brighter ticks on the ring
m=layer(); d=ImageDraw.Draw(m)

# thin inner ring
m=layer(); d=ImageDraw.Draw(m); arc(d,C,C,71.6,0,360,1.2); fill(m,"#174a62")
# inner face
m=layer(); d=ImageDraw.Draw(m); circle(d,C,C,71,fill=255); fill(m,"#061126")
# cardinal markers (triangles pointing inward)
m=layer(); d=ImageDraw.Draw(m)
for ang in range(4):
    t=math.radians(ang*90-90); ux,uy=math.cos(t),math.sin(t); px,py=-uy,ux
    tip=(C+ux*70.3,C+uy*70.3); b=(C+ux*75.5,C+uy*75.5)
    d.polygon([P(*tip),P(b[0]+px*3.2,b[1]+py*3.2),P(b[0]-px*3.2,b[1]-py*3.2)],fill=255)
fill(m,"#46e3fc")
# the C: annulus r 45..60, cut on the right
ys,xs=np.mgrid[0:N,0:N]/K
r=np.hypot(xs-C,ys-C)
inner_disc=layer(); circle(ImageDraw.Draw(inner_disc),C,C,44.5,fill=255)
fill(inner_disc,"#0a1934")
m=layer(); d=ImageDraw.Draw(m); circle(d,C,C,61,fill=255); circle(d,C,C,44.5,fill=0)
d.rectangle([P(80,39),P(160,121.5)],fill=0)
d.rectangle([P(122.5,0),P(160,160)],fill=0)
t=np.clip(((xs-40)*0.9+(ys-25))/140,0,1)[...,None]
c0=np.array([165,246,255]); cm_=np.array([100,236,255]); c1=np.array([35,172,218])
rgb=np.where(t<0.5, c0*(1-t*2)+cm_*(t*2), cm_*(2-t*2)+c1*(t*2-1))
rim=np.clip(1-np.minimum(np.abs(r-44.5),np.abs(r-61))/1.6,0,1)
rgb=rgb*(1-0.12*rim[...,None])
fill_arr(m,rgb)
# radar sweep wedge
m=layer(); d=ImageDraw.Draw(m); d.pieslice([P(C-41,C-41),P(C+41,C+41)],-153,-71,fill=255)
fill(m,(34,103,129,215))
m=layer(); d=ImageDraw.Draw(m); d.line([P(C,C),P(C+41*math.cos(math.radians(-71)),C+41*math.sin(math.radians(-71)))],fill=255,width=int(1.2*K))
fill(m,(60,160,190,90))
# dashed range ring r=41 from 107 deg round the left to -50 deg
m=layer(); d=ImageDraw.Draw(m)
a=107
while a<310:
    arc(d,C,C,41,a,min(a+11,310),1.4); a+=16
fill(m,"#2d8ba4")
# second dashed ring on the lower left
m=layer(); d=ImageDraw.Draw(m)
for a0 in (120,140,160): arc(d,C,C,35,a0,a0+12,1.1)
fill(m,"#1f5f78")
# inner solid arc
m=layer(); d=ImageDraw.Draw(m); arc(d,C,C,24.5,172,302,1.4); fill(m,"#2f93ab")
# crosshairs
m=layer(); d=ImageDraw.Draw(m)
d.rectangle([P(79.3,35.5),P(80.9,50)],fill=255); d.rectangle([P(71,39.6),P(89,41)],fill=255)
d.rectangle([P(37,79.3),P(53,80.8)],fill=255); d.rectangle([P(47.3,75),P(48.8,85)],fill=255)
fill(m,"#3cbad2")
# chevrons >>>>> from the stem to the meter
for i in range(6):
    x=85+i*3.5; m=layer(); d=ImageDraw.Draw(m)
    d.polygon([P(x,75.3),P(x+1.8,75.3),P(x+4.2,78.6),P(x+1.8,81.9),P(x,81.9),P(x+2.4,78.6)],fill=255)
    k=(i/5)**1.5; col=tuple(int(a*(1-k)+b*k) for a,b in zip((42,121,146),(235,252,255)))+(255,)
    fill(m,col)
# the F: stem, cap, arm, flared foot into the C
m=layer(); d=ImageDraw.Draw(m)
d.rectangle([P(78.2,75),P(82.6,128)],fill=255)
d.rectangle([P(75.8,74.2),P(84.5,77.6)],fill=255)
d.rectangle([P(80,97.2),P(98.5,102.2)],fill=255)
def bez(p0,p1,p2,n=24):
    return [((1-t)**2*p0[0]+2*(1-t)*t*p1[0]+t*t*p2[0],(1-t)**2*p0[1]+2*(1-t)*t*p1[1]+t*t*p2[1]) for t in (i/n for i in range(n+1))]
foot=bez((78.2,110),(78.2,121.5),(64,123))+[(64,130),(100,130)]+bez((96,121.5),(82.6,121),(82.6,110))
d.polygon([P(*p) for p in foot],fill=255)
d.ellipse([P(C-60,C-60),P(C+60,C+60)],outline=0,width=0)
o=layer(); circle(ImageDraw.Draw(o),C,C,45.1,fill=255)
m=Image.fromarray((np.asarray(m)&np.asarray(o)))
t2=np.clip((ys-74)/56,0,1)
rgb2=np.array([66,224,251])[None,None]*(1-t2[...,None])+np.array([40,182,224])[None,None]*t2[...,None]
fill_arr(m,rgb2)
# meter: bars, the orange one, a thin rail on its right
bars=[(44.5,50.5),(51.8,57.8),(59.1,65.1),(66.4,72.4),(74,79.4),(80.8,86.8),(88.1,94.1),(95.4,101.4),(102.7,108.7),(110,114.5)]
for i,(y0,y1) in enumerate(bars):
    m=layer(); ImageDraw.Draw(m).rectangle([P(107.6,y0),P(125.2,y1)],fill=255)
    if i==4: fill(m,"#ffb346")
    else:
        k=max(0,i-4)/5
        col=tuple(int(a*(1-k)+b*k) for a,b in zip((72,230,253),(44,140,165)))+(int(255*(1-0.25*k)),)
        fill(m,col)
m=layer(); ImageDraw.Draw(m).rectangle([P(127,44),P(128.4,115)],fill=255); fill(m,"#2b869d")
img.save("icon_big_v2.png")
small=img.resize((256,256),Image.LANCZOS); small.save("icon256.png")
img.resize((160,160),Image.LANCZOS).save("icon160cmp.png")
