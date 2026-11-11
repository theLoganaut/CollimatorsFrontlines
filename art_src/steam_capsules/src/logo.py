# Steam library logo: the capsules' hologram title on a transparent background.
# Drawn on a 1x pixel grid, then scaled 2x nearest (same grid as the capsules). Usage: python logo.py out.png [s1 s2]
import sys, numpy as np
from PIL import Image, ImageFilter
from holo import text_mask

def logo(out_path, s1=9, s2=9, hue=(120,235,255), pad=14):
    hue=np.array(hue,float)
    m1=text_mask("COLLIMATORS:",s1); m2=text_mask("FRONTLINES",s2)
    W=max(m1.shape[1],m2.shape[1])+pad*2
    gap=s1*2+1
    H=m1.shape[0]+gap+m2.shape[0]+pad*2
    mask=np.zeros((H,W),bool)
    top=pad; x1=(W-m1.shape[1])//2; mask[top:top+m1.shape[0],x1:x1+m1.shape[1]]|=m1
    t2=top+m1.shape[0]+gap; x2=(W-m2.shape[1])//2
    mask[t2:t2+m2.shape[0],x2:x2+m2.shape[1]]|=m2
    # the capsules' glitch: one row of each line slips sideways
    for r,dx in ((top+s1*3,2),(t2+s2*4+1,-2)): mask[r]=np.roll(mask[r],dx)
    ys,_=np.mgrid[0:H,0:W]
    rgb=np.zeros((H,W,3)); a=np.zeros((H,W))
    mi=Image.fromarray(mask.astype(np.uint8)*255)
    glow=np.asarray(mi.filter(ImageFilter.GaussianBlur(5))).astype(float)/255
    ga=np.clip(glow*0.75,0,1)
    rgb[:]=hue; a=ga
    ring=(np.asarray(mi.filter(ImageFilter.MaxFilter(3)))>0)&~mask
    rgb[ring]=np.array([8,40,60]); a=np.where(ring,0.9,a)
    base=np.where(ys%2==0,1.0,0.74)
    col=hue[None,None,:]*base[...,None]
    hi=np.zeros((H,W),bool); hi[top:top+s1]=True; hi[t2:t2+s2]=True
    col[hi]=np.array([220,252,255])
    rgb[mask]=col[mask]; a=np.where(mask,1.0,a)
    img=Image.fromarray(np.dstack([np.clip(rgb,0,255),np.clip(a*255,0,255)]).astype(np.uint8),"RGBA")
    img=img.resize((W*2,H*2),Image.NEAREST)
    img.save(out_path)
    return img

if __name__=="__main__":
    s=list(map(int,sys.argv[2:4])) if len(sys.argv)>3 else [9,9]
    im=logo(sys.argv[1],*s); print(im.size)
