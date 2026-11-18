# Small capsule title: the library logo's look (logo.py), drawn straight on the 462x174 grid so it can
# fill the width with square font pixels. Outline and glow are scaled to the letter size, and a soft
# dark shadow sits behind the title so the horizon doesn't cut through the letters.
# s can be fractional (font pixels then come out 6 or 7 px wide): by default the title is as wide as
# the capsule allows with `margin` px left at each side for the outline and glow.
# low=True puts FRONTLINES at the bottom edge so the horizon doesn't run behind it.
# Usage: python holo_small.py scene.png out.png [s] [top]   (scene is the half-size PixelLab scene)
import sys, numpy as np
from PIL import Image, ImageFilter
from holo import text_mask
def scaled_mask(text, s):
    m=text_mask(text,1); h,w=m.shape
    H,W=int(round(h*s)),int(round(w*s))
    yi=np.minimum((np.arange(H)/s).astype(int),h-1); xi=np.minimum((np.arange(W)/s).astype(int),w-1)
    return m[yi][:,xi]
def compose(scene, out_path, s=None, top=None, margin=3, glow_sigma=4, shadow=0.5, hue=(120,235,255), low=True):
    sc=Image.open(scene).convert("RGB"); W,H=sc.size
    a=np.asarray(sc.resize((W*2,H*2),Image.NEAREST)).astype(float)[:, 2:2+462][:174]
    H,W=a.shape[:2]; hue=np.array(hue,float)
    s=s or (W-2*margin-2)/text_mask("COLLIMATORS:",1).shape[1]
    m1=scaled_mask("COLLIMATORS:",s); m2=scaled_mask("FRONTLINES",s)
    gap=int(round(s*2+1)); bh=m1.shape[0]+gap+m2.shape[0]
    top=(H-bh)//2 if top is None else top
    mask=np.zeros((H,W),bool)
    x1=(W-m1.shape[1])//2; mask[top:top+m1.shape[0],x1:x1+m1.shape[1]]|=m1
    t2=top+m1.shape[0]+gap; x2=(W-m2.shape[1])//2
    if low: t2=H-margin-1-m2.shape[0]   # FRONTLINES on the bottom edge, below the horizon
    mask[t2:t2+m2.shape[0],x2:x2+m2.shape[1]]|=m2
    for r,dx in ((top+int(s*3),2),(t2+int(s*4)+1,-2)): mask[r]=np.roll(mask[r],dx)   # the logo's glitch rows
    mi=Image.fromarray(mask.astype(np.uint8)*255)
    out=a.copy()
    sh=np.asarray(mi.filter(ImageFilter.GaussianBlur(9))).astype(float)/255
    out*=1-np.clip(sh*2.2,0,1)[...,None]*shadow
    glow=np.asarray(mi.filter(ImageFilter.GaussianBlur(glow_sigma))).astype(float)/255
    out+=np.clip(glow*0.75,0,1)[...,None]*hue
    ring=(np.asarray(mi.filter(ImageFilter.MaxFilter(3)))>0)&~mask
    out[ring]=out[ring]*0.1+np.array([8,40,60])*0.9
    ys=np.mgrid[0:H,0:W][0]
    col=hue[None,None,:]*np.where((ys//2)%2==0,1.0,0.74)[...,None]   # the logo's 2-px scanlines
    sr=int(round(s)); hi=((ys>=top)&(ys<top+sr))|((ys>=t2)&(ys<t2+sr))
    col[hi]=np.array([220,252,255])
    out[mask]=col[mask]
    Image.fromarray(np.clip(out,0,255).astype(np.uint8)).save(out_path)
if __name__=="__main__":
    a=sys.argv
    compose(a[1],a[2],float(a[3]) if len(a)>3 else None, int(a[4]) if len(a)>4 else None)
