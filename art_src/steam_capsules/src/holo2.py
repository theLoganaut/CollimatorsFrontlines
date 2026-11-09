import sys, numpy as np
from PIL import Image, ImageFilter, ImageDraw
from holo import text_mask
def compose(scene, out_path, cx, top, s1, s2, emitter, hue=(120,235,255), size=None):
    im=Image.open(scene).convert("RGB")
    a=np.asarray(im).astype(float); H,W,_=a.shape
    hue=np.array(hue,float)
    m1=text_mask("COLLIMATORS:",s1); m2=text_mask("FRONTLINES",s2)
    mask=np.zeros((H,W),bool)
    x1=cx-m1.shape[1]//2; mask[top:top+m1.shape[0],x1:x1+m1.shape[1]]|=m1
    t2=top+m1.shape[0]+s1*2+1; x2=cx-m2.shape[1]//2
    mask[t2:t2+m2.shape[0],x2:x2+m2.shape[1]]|=m2
    for r,dx in ((top+s1*3,2),(t2+s2*4+1,-2)): mask[r]=np.roll(mask[r],dx)
    # panel
    pad=8
    px0,px1=min(x1,x2)-pad,max(x1+m1.shape[1],x2+m2.shape[1])+pad
    py0,py1=top-pad,t2+m2.shape[0]+pad
    out=a.copy()
    ys,xs=np.mgrid[0:H,0:W]
    # beam from emitter to the panel's bottom edge
    ex,ey=emitter
    t=(ey-ys)/max(1,(ey-py1)); xl=ex+(px0-ex)*t; xr=ex+(px1-ex)*t
    inside=(t>=0)&(t<=1)&(xs>=xl)&(xs<=xr)
    edge=inside&((xs-xl<1.2)|(xr-xs<1.2))
    k=np.where(inside,0.05+0.10*t,0)
    out+=k[...,None]*hue
    out[edge]=out[edge]*0.6+hue*0.4*np.clip(t[edge]+0.3,0,1)[:,None]
    # panel glass: tint + scanlines + border with brighter corners
    pm=(xs>=px0)&(xs<px1)&(ys>=py0)&(ys<py1)
    out[pm]=out[pm]*0.78+np.array([20,70,95])*0.22
    out[pm&(ys%2==1)]*=0.92
    border=pm&((xs==px0)|(xs==px1-1)|(ys==py0)|(ys==py1-1))
    out[border]=out[border]*0.55+hue*0.45
    c=10
    corner=border&(((xs-px0<c)|(px1-1-xs<c))&((ys-py0<c)|(py1-1-ys<c)))
    out[corner]=np.array([200,250,255])
    # emitter dot
    out[ey-1:ey+2,ex-1:ex+2]=np.array([220,255,255])
    # glow + outline + body
    mi=Image.fromarray(mask.astype(np.uint8)*255)
    glow=np.asarray(mi.filter(ImageFilter.GaussianBlur(5))).astype(float)/255
    out+=(glow*0.7)[...,None]*hue
    eg=np.zeros((H,W),np.uint8); eg[ey,ex]=255
    eglow=np.asarray(Image.fromarray(eg).filter(ImageFilter.GaussianBlur(4))).astype(float)/255*20
    out+=np.clip(eglow,0,1)[...,None]*hue*0.8
    ring=(np.asarray(mi.filter(ImageFilter.MaxFilter(3)))>0)&~mask
    out[ring]=out[ring]*0.3+np.array([8,40,60])*0.7
    base=np.where(ys%2==0,1.0,0.74)
    col=hue[None,None,:]*base[...,None]
    hi=np.zeros((H,W),bool); hi[top:top+s1]=True; hi[t2:t2+s2]=True
    col[hi]=np.array([220,252,255])
    out[mask]=out[mask]*0.1+col[mask]*0.9
    img=Image.fromarray(np.clip(out,0,255).astype(np.uint8))
    img.save(out_path)
    return img
if __name__=="__main__":
    sc,o=sys.argv[1],sys.argv[2]; cx,top,s1,s2=map(int,sys.argv[3:7]); em=tuple(map(int,sys.argv[7].split(',')))
    img=compose(sc,o,cx,top,s1,s2,em)
    img.resize((img.width*2,img.height*2),Image.NEAREST).save(o.replace('.png','_x2.png'))
