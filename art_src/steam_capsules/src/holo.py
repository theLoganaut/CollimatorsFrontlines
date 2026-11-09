# Hologram pixel title, drawn on the art's own pixel grid, composited over a scene.
import sys, numpy as np
from PIL import Image, ImageFilter
G = {
 'C':["01111","10000","10000","10000","10000","10000","01111"],
 'O':["01110","10001","10001","10001","10001","10001","01110"],
 'L':["10000","10000","10000","10000","10000","10000","11111"],
 'I':["11111","00100","00100","00100","00100","00100","11111"],
 'M':["10001","11011","10101","10101","10001","10001","10001"],
 'A':["01110","10001","10001","11111","10001","10001","10001"],
 'T':["11111","00100","00100","00100","00100","00100","00100"],
 'R':["11110","10001","10001","11110","10100","10010","10001"],
 'S':["01111","10000","10000","01110","00001","00001","11110"],
 'F':["11111","10000","10000","11110","10000","10000","10000"],
 'N':["10001","11001","10101","10011","10001","10001","10001"],
 'E':["11111","10000","10000","11110","10000","10000","11111"],
 ':':["0","1","1","0","1","1","0"],
 ' ':["000","000","000","000","000","000","000"],
}
def text_mask(s, scale, gap=1):
    cols=[]
    for i,ch in enumerate(s):
        g=G[ch]; w=len(g[0])
        for x in range(w): cols.append([g[y][x]=='1' for y in range(7)])
        if i<len(s)-1: cols += [[False]*7]*gap
    m=np.array(cols,dtype=bool).T
    return np.kron(m,np.ones((scale,scale),dtype=bool))

def compose(scene_path, out_path, cx, top, s1=4, s2=3, hue=(120,235,255), emitter=None):
    im=Image.open(scene_path).convert("RGB"); a=np.asarray(im).astype(float)
    H,W,_=a.shape
    m1=text_mask("COLLIMATORS:",s1); m2=text_mask("FRONTLINES",s2)
    mask=np.zeros((H,W),bool)
    x1=cx-m1.shape[1]//2; mask[top:top+m1.shape[0], x1:x1+m1.shape[1]] |= m1
    t2=top+m1.shape[0]+s1*2; x2=cx-m2.shape[1]//2
    mask[t2:t2+m2.shape[0], x2:x2+m2.shape[1]] |= m2
    # glitch: shift a couple of rows sideways
    for r,dx in ((top+s1*2,2),(t2+s2*4+1,-2)):
        mask[r]=np.roll(mask[r],dx)
    # outline ring (dark teal) for readability
    mi=Image.fromarray(mask.astype(np.uint8)*255)
    ring=np.asarray(mi.filter(ImageFilter.MaxFilter(3)))>0
    ring &= ~mask
    hue=np.array(hue,float)
    # projection beam: faint triangle from emitter to the text block
    out=a.copy()
    if emitter:
        ex,ey=emitter; ys,xs=np.mgrid[0:H,0:W]
        yb=t2+m2.shape[0]+2; xl=min(x1,x2)-4; xr=max(x1+m1.shape[1],x2+m2.shape[1])+4
        # beam: points between emitter and the text bottom edge, widening
        t=(ey-ys)/max(1,(ey-yb))
        inside=(t>=0)&(t<=1)&(xs>=ex+(xl-ex)*t)&(xs<=ex+(xr-ex)*t)
        k=np.where(inside, 0.10*t, 0)
        out+= k[...,None]*hue
    # glow
    glow=np.asarray(mi.filter(ImageFilter.GaussianBlur(6))).astype(float)/255
    out+= (glow*0.55)[...,None]*hue
    out[ring]=out[ring]*0.35+np.array([10,50,70])*0.65
    # text body: brighter top rows per letter row, scanlines every 2nd row
    ys=np.arange(H)[:,None].repeat(W,1)
    body=np.zeros_like(out)
    base=np.where((ys%2)==0,1.0,0.72)
    col=hue[None,None,:]*base[...,None]
    hi=np.zeros((H,W),bool); hi[top:top+s1]=True; hi[t2:t2+s2]=True
    col[hi]=np.array([215,250,255])
    alpha=0.88
    out[mask]=out[mask]*(1-alpha)+col[mask]*alpha
    out=np.clip(out,0,255).astype(np.uint8)
    Image.fromarray(out).save(out_path)

if __name__=="__main__":
    scene,out,cx,top=sys.argv[1],sys.argv[2],int(sys.argv[3]),int(sys.argv[4])
    em=tuple(map(int,sys.argv[5].split(","))) if len(sys.argv)>5 else None
    compose(scene,out,cx,top,emitter=em)
