"""Trailer editor: builds the trailer from a shot list, frame by frame, with ffmpeg doing the
reading and the encoding. Run it with Python 3.10+ that has numpy and Pillow, from the repo root:

    python art_src/trailer/trailer_edit.py art_src/trailer/shotlist.json            # full render
    python art_src/trailer/trailer_edit.py <shotlist> --preview                     # half size, 30 fps, fast
    python art_src/trailer/trailer_edit.py <shotlist> --from 16 --to 24             # one stretch
    python art_src/trailer/trailer_edit.py <shotlist> --stills 0.5,16.1,38.2        # PNGs to look at
    python art_src/trailer/trailer_edit.py <shotlist> --check                       # validate, render nothing

The shot list (JSON) - the top level:
  fps, size [w, h], audio (wav), footage (folder of <name>.mkv + <name>.events.json from record.sh),
  font (ttf), out (mp4), shots [...]

A shot:
  name        a label for messages
  at, dur     where it sits in the trailer and how long it runs (seconds)
  src         footage name | "image:<path>" | "black" | "white"
  in          seconds into the source, or an event: {"event": "destroyed", "n": 1, "match": {"target": "Anchor"},
              "before": 0.2} = the 1st matching event's time minus 0.2 s
  speed       a number (1 = real time, 0 = freeze), or ramps: [[shot_t, speed], ...] each from that time on
  cam         camera keys: [{"t": 0, "zoom": 2, "x": 0.5, "y": 0.4}, {"t": 2, "zoom": 1.2, "ease": "inout"}]
              x/y = the centre, in 0..1 of the source frame ("in" = where the in-point's event happened);
              missing values carry over from the key before
  follow      {"events": ["hit", "destroyed"], "zoom": 1.6, "lag": 0.2, "match": {...}}: the centre tracks
              those events' positions (cam keys still set the zoom when given)
  punch       [shot_t, ...] quick zoom-ins (4 %), or {"events": ["hit"], "amp": 0.05} on the source's events
  shake       [[shot_t, pixels], ...], or {"events": ["impact"], "px": 14, "match": {...}} on the source's events
  trans       how this shot comes in: {"type": "cut|flash|fade|dip|pixelize|whip|crt", "dur": 0.25}
              flash: a white flash after the cut; dip: through black; crt: the outgoing shot switches off
  cursor      true: draw the mouse pointer from the source's mouse / pick / drop events (Movie Maker
              doesn't record the real one), pressed in for a moment on each pick and drop
  text        {"text": "BUILD YOUR MECH", "at": 0, "dur": 1.5, "pos": "lower|center|top|bottom", "y": 0.87,
              "style": "outline", "size": 150}: "outline" is big white letters with a black outline, else the
              glass panel; "y" (0..1) overrides "pos"; a "dur" longer than the shot keeps it up over the next shots
  overlays    [{"image": path, "at": 0, "dur": 2, "x": 0.5, "y": 0.45, "width": 0.6, "slam": true, "fade_in": 0.3}]
              or {"text": "...", "style": "plain|panel", "size": 48, ...} for text (end card)
              or {"video": "operator", "in": 0.4, "at": 0, "dur": 3, "fade_out": 0.4}: footage recorded on
              black, drawn solid except its black, which shows the shot underneath; like text, a long "dur"
              carries it over the next shots
"""
import argparse, json, math, os, subprocess, sys
import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

FFMPEG = "ffmpeg"

def find_ffmpeg():
    global FFMPEG
    for c in ["ffmpeg", os.path.expandvars(r"%LOCALAPPDATA%\Microsoft\WinGet\Links\ffmpeg.exe")]:
        try:
            subprocess.run([c, "-version"], capture_output=True, check=True)
            FFMPEG = c
            return
        except Exception:
            pass
    sys.exit("trailer_edit: needs ffmpeg (winget install Gyan.FFmpeg)")

# ---------- easing ----------

def ease(kind, u):
    u = min(1.0, max(0.0, u))
    if kind == "linear": return u
    if kind == "in": return u * u * u
    if kind == "out": return 1 - (1 - u) ** 3
    return u * u * (3 - 2 * u) if kind == "smooth" else (4 * u ** 3 if u < 0.5 else 1 - (-2 * u + 2) ** 3 / 2)

# ---------- sources ----------

class Footage:
    """A recorded clip: frames read in order through ffmpeg, restarting only when asked to go back."""
    def __init__(self, folder, name):
        self.path = os.path.join(folder, name + ".mkv")
        if not os.path.exists(self.path):
            raise FileNotFoundError(f"no footage {self.path} (record it with record.sh)")
        ev = os.path.join(folder, name + ".events.json")
        self.meta = json.load(open(ev)) if os.path.exists(ev) else {"events": []}
        probe = subprocess.run(["ffprobe", "-v", "error", "-select_streams", "v", "-show_entries",
                                "stream=width,height,r_frame_rate", "-of", "csv=p=0", self.path],
                               capture_output=True, text=True).stdout.strip().split(",")
        self.w, self.h = int(probe[0]), int(probe[1])
        num, den = probe[2].split("/")
        self.fps = float(num) / float(den)
        self.proc = None
        self.next_idx = 0
        self.cur = None
        self.cur_idx = -1

    def events(self, types=None, match=None):
        out = []
        for e in self.meta.get("events", []):
            if types and e["type"] not in types:
                continue
            if match and any(str(e.get(k)) != str(v) for k, v in match.items()):
                continue
            out.append(e)
        return out

    def _open(self, idx):
        if self.proc:
            self.proc.kill()
        t = max(0.0, idx / self.fps)
        self.proc = subprocess.Popen([FFMPEG, "-v", "error", "-ss", f"{t:.4f}", "-i", self.path,
                                      "-f", "rawvideo", "-pix_fmt", "rgb24", "-"], stdout=subprocess.PIPE)
        self.next_idx = idx

    def frame(self, idx):
        idx = max(0, int(idx))
        if idx == self.cur_idx:
            return self.cur
        if self.proc is None or idx < self.next_idx or idx > self.next_idx + 240:
            self._open(idx)
        size = self.w * self.h * 3
        while self.next_idx <= idx:
            buf = self.proc.stdout.read(size)
            if len(buf) < size:  # past the end: hold the last frame
                return self.cur if self.cur is not None else np.zeros((self.h, self.w, 3), np.uint8)
            self.cur = np.frombuffer(buf, np.uint8).reshape(self.h, self.w, 3)
            self.cur_idx = self.next_idx
            self.next_idx += 1
        return self.cur

    def close(self):
        if self.proc:
            self.proc.kill()

class Still:
    def __init__(self, arr):
        self.arr = arr
        self.h, self.w = arr.shape[:2]
        self.fps = 60.0
        self.meta = {"events": []}
    def events(self, types=None, match=None): return []
    def frame(self, idx): return self.arr
    def close(self): pass

# ---------- one shot ----------

class Shot:
    def __init__(self, spec, edit):
        self.s = spec
        self.name = spec.get("name", spec.get("src", "?"))
        self.at = float(spec["at"])
        self.dur = float(spec["dur"])
        self.edit = edit
        self.src = edit.source(spec.get("src", "black"))
        self.in_pos = (0.5, 0.5)
        self.t_in = self._resolve_in(spec.get("in", 0.0))
        sp = spec.get("speed", 1.0)
        self.ramps = [[0.0, float(sp)]] if not isinstance(sp, list) else [[float(a), float(b)] for a, b in sp]
        if self.ramps[0][0] > 0:
            self.ramps.insert(0, [0.0, 1.0])
        self.keys = spec.get("cam", [])
        self.follow = spec.get("follow")
        self._follow_path = self._build_follow() if self.follow else None
        self.punches = self._build_punches(spec.get("punch", []))
        self.cursor_path = [(e["t"], e["x"], e["y"], e["type"]) for e in self.src.events(["mouse", "pick", "drop"])
                            if "x" in e] if spec.get("cursor") else []
        self.shakes = self._build_shakes(spec.get("shake", []))
        tr = spec.get("trans", {"type": "cut"})
        self.trans = tr if isinstance(tr, dict) else {"type": tr}
        self.trans.setdefault("dur", {"cut": 0, "flash": 0.12, "fade": 0.4, "dip": 0.5,
                                      "pixelize": 0.4, "whip": 0.25, "crt": 0.35}.get(self.trans["type"], 0.25))

    def _resolve_in(self, v):
        if isinstance(v, (int, float)):
            return float(v)
        evs = self.src.events([v["event"]], v.get("match"))
        n = int(v.get("n", 1))
        if self.s.get("src") in self.edit.missing:
            return 0.0
        if len(evs) < n:
            raise ValueError(f"shot {self.name}: only {len(evs)} '{v['event']}' events in {self.s.get('src')}")
        e = evs[n - 1]
        if "x" in e:
            self.in_pos = (e["x"], e["y"])
        return e["t"] - float(v.get("before", 0.0))

    def src_time(self, u):
        """Seconds into the source at shot time u (may be negative or past the end, for transitions)."""
        t = self.t_in
        for i, (start, speed) in enumerate(self.ramps):
            end = self.ramps[i + 1][0] if i + 1 < len(self.ramps) else math.inf
            if u <= start:
                break
            t += (min(u, end) - start) * speed
        if u < 0:
            t += u * self.ramps[0][1]
        return t

    def _build_follow(self):
        f = self.follow
        evs = self.src.events(f.get("events", ["hit"]), f.get("match"))
        pts = [(e["t"], e["x"], e["y"]) for e in evs if "x" in e]
        return pts

    def _build_punches(self, p):
        out = []
        if isinstance(p, dict):
            amp = float(p.get("amp", 0.04))
            for e in self.src.events(p.get("events", ["hit"]), p.get("match")):
                out.append(("src", e["t"], amp))
        else:
            for x in p:
                if isinstance(x, list):
                    out.append(("shot", float(x[0]), float(x[1])))
                else:
                    out.append(("shot", float(x), 0.04))
        return out

    def _build_shakes(self, p):
        """[[shot_t, px], ...] or {"events": ["impact"], "px": 14, "match": {...}} on the source's events."""
        if isinstance(p, dict):
            px = float(p.get("px", 14))
            return [("src", e["t"], px) for e in self.src.events(p.get("events", ["impact"]), p.get("match"))]
        return [("shot", float(a), float(b)) for a, b in p]

    def camera(self, u):
        z, x, y = 1.0, 0.5, 0.5
        if self.keys:
            ks = []
            cz, cx, cy = 1.0, 0.5, 0.5
            for k in self.keys:
                cz, cx, cy = k.get("zoom", cz), k.get("x", cx), k.get("y", cy)
                cx = self.in_pos[0] if cx == "in" else cx
                cy = self.in_pos[1] if cy == "in" else cy
                ks.append((float(k.get("t", 0)), cz, cx, cy, k.get("ease", "inout")))
            if u <= ks[0][0]:
                _, z, x, y, _ = ks[0]
            elif u >= ks[-1][0]:
                _, z, x, y, _ = ks[-1]
            else:
                for a, b in zip(ks, ks[1:]):
                    if a[0] <= u <= b[0]:
                        w = ease(b[4], (u - a[0]) / max(1e-6, b[0] - a[0]))
                        z = a[1] + (b[1] - a[1]) * w
                        x = a[2] + (b[2] - a[2]) * w
                        y = a[3] + (b[3] - a[3]) * w
                        break
        if self._follow_path:
            fz = self.follow.get("zoom")
            if fz and not self.keys:
                z = float(fz)
            x, y = self._follow_at(self.src_time(u))
        # punches and shake
        st = self.src_time(u)
        for kind, t0, amp in self.punches:
            d = (u - t0) if kind == "shot" else (st - t0)
            if 0 <= d < 0.15:
                z *= 1 + amp * (1 - d / 0.15)
        dx = dy = 0.0
        for kind, t0, px in self.shakes:
            d = (u - t0) if kind == "shot" else (st - t0)
            if 0 <= d < 0.3:
                a = px * (1 - d / 0.3)
                dx += a * math.sin(d * 97.0)
                dy += a * math.cos(d * 71.0)
        return z, x, y, dx, dy

    def _follow_at(self, st):
        pts, lag = self._follow_path, float(self.follow.get("lag", 0.2))
        if not pts:
            return 0.5, 0.5
        # the camera eases from each event's position to the next, arriving `lag` after it happens
        prev = (pts[0][0] - 1.0, pts[0][1], pts[0][2])
        for p in pts:
            if st < p[0] + lag:
                w = ease("inout", (st - prev[0] - lag) / max(1e-6, p[0] - prev[0]))
                return prev[1] + (p[1] - prev[1]) * w, prev[2] + (p[2] - prev[2]) * w
            prev = p
        return pts[-1][1], pts[-1][2]

    ARROW = [(0, 0), (0, 26), (7, 20), (12, 31), (17, 29), (12, 18), (21, 18)]

    def _draw_cursor(self, img, st):
        pts = self.cursor_path
        if st < pts[0][0]:
            return img
        x, y = pts[-1][1], pts[-1][2]
        for a, b in zip(pts, pts[1:]):
            if a[0] <= st < b[0]:
                w = (st - a[0]) / max(1e-6, b[0] - a[0])
                x, y = a[1] + (b[1] - a[1]) * w, a[2] + (b[2] - a[2]) * w
                break
        down = any(t <= st < t + 0.08 for t, _, _, k in pts if k in ("pick", "drop"))
        h, wd = img.shape[:2]
        s = wd / 1920 * (1.15 if down else 1.3)
        pil = Image.fromarray(img).copy()
        poly = [(x * wd + px * s, y * h + py * s) for px, py in self.ARROW]
        ImageDraw.Draw(pil).polygon(poly, fill=(170, 235, 228) if down else (240, 244, 244), outline=(8, 12, 16), width=max(2, int(3 * s)))
        return np.asarray(pil)

    def render(self, u, W, H):
        """This shot's picture at shot time u, as a WxH RGB array."""
        st = self.src_time(u)
        img = self.src.frame(round(st * self.src.fps))
        if self.cursor_path:
            img = self._draw_cursor(img, st)
        z, x, y, dx, dy = self.camera(u)
        sh, sw = img.shape[:2]
        cw, ch = sw / max(z, 1.0), sh / max(z, 1.0)
        cx = min(max(x * sw + dx * sw / W, cw / 2), sw - cw / 2)
        cy = min(max(y * sh + dy * sh / H, ch / 2), sh - ch / 2)
        box = (cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2)
        pil = Image.fromarray(img)
        if z <= 1.0001 and (sw, sh) == (W, H) and not (dx or dy):
            return img
        out = pil.resize((W, H), Image.LANCZOS, box=box)
        return np.asarray(out)

# ---------- text and overlays ----------

class Cards:
    def __init__(self, font_path):
        self.font_path = font_path
        self.cache = {}

    def font(self, size):
        try:
            return ImageFont.truetype(self.font_path, size)
        except Exception:
            return ImageFont.load_default()

    def panel(self, text, size, W):
        key = ("panel", text, size, W)
        if key in self.cache:
            return self.cache[key]
        f = self.font(size)
        l, t, r, b = f.getbbox(text)
        tw, th = r - l, b - t
        k = size / 64.0  # padding, border and corner brackets grow with the text
        pw, ph = int(tw + 96 * k), int(th + 52 * k)
        im = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.rectangle([0, 0, pw - 1, ph - 1], fill=(9, 26, 30, 215))
        d.rectangle([0, 0, pw - 1, ph - 1], outline=(70, 220, 210, 255), width=max(2, int(2 * k)))
        c, lw = int(14 * k), max(3, int(5 * k))  # corner brackets, like the game's glass panels
        for x0, y0, sx, sy in [(0, 0, 1, 1), (pw - 1, 0, -1, 1), (0, ph - 1, 1, -1), (pw - 1, ph - 1, -1, -1)]:
            d.line([(x0, y0), (x0 + sx * c, y0)], fill=(140, 255, 245, 255), width=lw)
            d.line([(x0, y0), (x0, y0 + sy * c)], fill=(140, 255, 245, 255), width=lw)
        d.text(((pw - tw) / 2 - l, (ph - th) / 2 - t), text, font=f, fill=(216, 243, 238, 255))
        self.cache[key] = im
        return im

    def outline(self, text, size):
        """Big white letters with a thick black outline, readable over any of the game's screens."""
        key = ("outline", text, size)
        if key in self.cache:
            return self.cache[key]
        f = self.font(size)
        sw = max(3, size // 14)
        l, t, r, b = f.getbbox(text, stroke_width=sw)
        im = Image.new("RGBA", (r - l + 8, b - t + 8), (0, 0, 0, 0))
        ImageDraw.Draw(im).text((4 - l, 4 - t), text, font=f, fill=(255, 255, 255, 255),
                                stroke_width=sw, stroke_fill=(0, 0, 0, 255))
        self.cache[key] = im
        return im

    def plain(self, text, size):
        key = ("plain", text, size)
        if key in self.cache:
            return self.cache[key]
        f = self.font(size)
        l, t, r, b = f.getbbox(text)
        im = Image.new("RGBA", (r - l + 8, b - t + 8), (0, 0, 0, 0))
        d = ImageDraw.Draw(im)
        d.text((4 - l + 3, 4 - t + 3), text, font=f, fill=(0, 0, 0, 180))
        d.text((4 - l, 4 - t), text, font=f, fill=(236, 240, 238, 255))
        self.cache[key] = im
        return im

def paste_anim(base, im, cx, cy, u, dur, slam=True, fade_in=0.12, fade_out=0.2):
    """Draws an RGBA image centred at (cx, cy), slammed in (shrinking from 125 %) and faded out."""
    if u < 0 or u > dur:
        return base
    a = min(1.0, u / max(1e-6, fade_in)) * min(1.0, (dur - u) / max(1e-6, fade_out))
    s = 1.0 + (0.25 * (1 - ease("out", u / 0.14)) if slam and u < 0.14 else 0.0)
    if s != 1.0:
        im = im.resize((max(1, int(im.width * s)), max(1, int(im.height * s))), Image.LANCZOS)
    if a < 1:
        im = im.copy()
        im.putalpha(im.getchannel("A").point(lambda v: int(v * a)))
    base.alpha_composite(im, (int(cx - im.width / 2), int(cy - im.height / 2)))
    return base

# ---------- transitions ----------

def blend(a, b, w):
    return (a.astype(np.float32) * (1 - w) + b.astype(np.float32) * w).astype(np.uint8)

def mosaic(img, block):
    if block <= 1:
        return img
    h, w = img.shape[:2]
    small = Image.fromarray(img).resize((max(1, w // block), max(1, h // block)), Image.BOX)
    return np.asarray(small.resize((w, h), Image.NEAREST))

def motion_blur_x(img, px):
    if px < 2:
        return img
    pil = Image.fromarray(img)
    k = int(px)
    acc = np.zeros_like(img, dtype=np.float32)
    steps = 6
    for i in range(steps):
        acc += np.roll(img, int(-k / 2 + k * i / (steps - 1)), axis=1).astype(np.float32)
    return (acc / steps).astype(np.uint8)

def crt_off(img, w):
    """w 0 -> 1: the picture squashes to a bright line, then the line shrinks to a dot."""
    h, wd = img.shape[:2]
    out = np.zeros_like(img)
    if w < 0.7:
        k = w / 0.7
        nh = max(2, int(h * (1 - k) ** 2))
        squashed = np.asarray(Image.fromarray(img).resize((wd, nh), Image.BILINEAR)).astype(np.float32)
        squashed = np.clip(squashed * (1 + 1.5 * k) + 60 * k, 0, 255).astype(np.uint8)
        y0 = (h - nh) // 2
        out[y0:y0 + nh] = squashed
    else:
        k = (w - 0.7) / 0.3
        lw = max(2, int(wd * (1 - k) ** 2))
        x0 = (wd - lw) // 2
        out[h // 2 - 1:h // 2 + 1, x0:x0 + lw] = 255
    return out

# ---------- the edit ----------

class Edit:
    def __init__(self, path, preview=False):
        self.dir = os.getcwd()
        self.spec = json.load(open(path))
        self.fps = 30 if preview else int(self.spec.get("fps", 60))
        W, H = self.spec.get("size", [1920, 1080])
        self.W, self.H = (W // 2, H // 2) if preview else (W, H)
        self.footage_dir = self.spec.get("footage", "build/trailer/footage")
        self.sources = {}
        self.missing = []
        self.cards = Cards(self.spec.get("font", "assets/fonts/VT323-Scaled.ttf"))
        self.shots = [Shot(s, self) for s in self.spec["shots"]]
        self.shots.sort(key=lambda s: s.at)
        self.length = max(s.at + s.dur for s in self.shots)
        self.scale = self.W / 1920.0

    def source(self, name):
        if name in self.sources:
            return self.sources[name]
        if name == "black":
            src = Still(np.zeros((self.H, self.W, 3), np.uint8))
        elif name == "white":
            src = Still(np.full((self.H, self.W, 3), 255, np.uint8))
        elif name.startswith("image:"):
            im = Image.open(name[6:]).convert("RGB")
            # fill the frame without stretching: crop the image to the frame's shape, centred
            ar, fr = im.width / im.height, self.W / self.H
            if ar > fr:
                cw = int(im.height * fr); im = im.crop(((im.width - cw) // 2, 0, (im.width + cw) // 2, im.height))
            elif ar < fr:
                ch = int(im.width / fr); im = im.crop((0, (im.height - ch) // 2, im.width, (im.height + ch) // 2))
            src = Still(np.asarray(im))
        else:  # one reader per shot, so two shots of the same clip never fight over its position
            try:
                src = Footage(self.footage_dir, name)
            except FileNotFoundError:
                if name not in self.missing:
                    self.missing.append(name)
                return Still(np.zeros((self.H, self.W, 3), np.uint8))
            self.sources[f"{name}#{len(self.sources)}"] = src
            return src
        self.sources[name] = src
        return src

    def shot_at(self, t):
        cur = None
        for s in self.shots:
            if s.at <= t + 1e-9:
                cur = s
        return cur

    def frame(self, t):
        W, H = self.W, self.H
        i = self.shots.index(self.shot_at(t)) if self.shot_at(t) else 0
        cur = self.shots[i]
        nxt = self.shots[i + 1] if i + 1 < len(self.shots) else None
        prev = self.shots[i - 1] if i > 0 else None
        u = t - cur.at
        img = cur.render(u, W, H)
        # the transition into the next shot starts before the cut
        if nxt is not None:
            tr, d = nxt.trans["type"], nxt.trans["dur"]
            lead = {"fade": d / 2, "pixelize": d / 2, "whip": d / 2, "dip": d / 2, "crt": d}.get(tr, 0)
            if lead and t >= nxt.at - lead:
                w = (t - (nxt.at - lead)) / max(1e-6, lead)  # 0 -> 1 up to the cut
                if tr == "crt":
                    img = crt_off(img, w)
                elif tr == "dip":
                    img = blend(img, np.zeros_like(img), ease("in", w))
                else:
                    other = nxt.render(t - nxt.at, W, H)
                    img = self._mix(tr, img, other, 0.5 * w)
        # ... and finishes after it
        if prev is not None or cur.trans["type"] == "flash":  # the first shot can open on a flash
            tr, d = cur.trans["type"], cur.trans["dur"]
            tail = {"fade": d / 2, "pixelize": d / 2, "whip": d / 2, "dip": d / 2, "flash": d}.get(tr, 0)
            if tail and u < tail:
                w = u / max(1e-6, tail)  # 0 -> 1 after the cut
                if tr == "flash":
                    img = blend(img, np.full_like(img, 255), 1 - ease("out", w))
                elif tr == "dip":
                    img = blend(np.zeros_like(img), img, ease("out", w))
                else:
                    other = prev.render(t - prev.at, W, H)
                    img = self._mix(tr, other, img, 0.5 + 0.5 * w)
        # text and overlays
        # any shot's text can run past its own end ("dur" longer than the shot) and stay up over the next ones
        layers = []
        for s in self.shots:
            if s.at > t:
                break
            if "text" in s.s:
                o = s.s["text"]
                if s is cur or t < s.at + float(o.get("at", 0)) + float(o.get("dur", s.dur)):
                    layers.append(("text", o, s.at, s))
            for o in s.s.get("overlays", []):
                if s is cur or t < s.at + float(o.get("at", 0)) + float(o.get("dur", s.dur)):
                    layers.append(("overlay", o, s.at, s))
        if layers:
            base = Image.fromarray(img).convert("RGBA")
            for kind, o, at, owner in layers:
                lu = t - at - float(o.get("at", 0))
                dur = float(o.get("dur", owner.dur))
                if kind == "text":
                    pos = o.get("pos", "lower")
                    cy = H * float(o.get("y", {"lower": 0.80, "center": 0.5, "top": 0.13, "bottom": 0.87}.get(pos, 0.8)))
                    if o.get("style") == "outline":
                        im = self.cards.outline(o["text"], int(o.get("size", 150) * self.scale))
                    else:
                        im = self.cards.panel(o["text"], int(o.get("size", 64) * self.scale), W)
                    paste_anim(base, im, W / 2, cy, lu, dur, slam=True, fade_out=float(o.get("fade_out", 0.2)))
                elif "image" in o:
                    im = Image.open(o["image"]).convert("RGBA")
                    tw = int(W * float(o.get("width", 0.5)))
                    im = im.resize((tw, int(im.height * tw / im.width)), Image.LANCZOS)
                    paste_anim(base, im, W * float(o.get("x", 0.5)), H * float(o.get("y", 0.5)), lu, dur,
                               slam=o.get("slam", False), fade_in=float(o.get("fade_in", 0.15)),
                               fade_out=float(o.get("fade_out", 0.2)))
                elif "video" in o:  # recorded footage on black, laid over with "lighten": the black drops out
                    if 0 <= lu <= dur:
                        key = ("video", id(o))
                        if key not in self.sources:
                            self.sources[key] = Footage(self.footage_dir, o["video"])
                        src = self.sources[key]
                        fr = src.frame(round((float(o.get("in", 0)) + lu) * src.fps))
                        if fr.shape[:2] != (H, W):
                            fr = np.asarray(Image.fromarray(fr).resize((W, H), Image.LANCZOS))
                        a = min(1.0, lu / max(1e-6, float(o.get("fade_in", 0.0)) or 1e-6)) * \
                            min(1.0, (dur - lu) / max(1e-6, float(o.get("fade_out", 0.3))))
                        # everything that isn't the recording's pure black is drawn solid (the panel stays
                        # as opaque as in the game); the black around it shows the shot underneath
                        mask = (fr.max(axis=2) > 3).astype(np.float32)
                        mask = np.asarray(Image.fromarray((mask * 255).astype(np.uint8)).filter(ImageFilter.MaxFilter(5)),
                                          np.float32)[..., None] / 255.0 * a
                        b = np.asarray(base)[..., :3].astype(np.float32)
                        rgb = (b * (1 - mask) + fr.astype(np.float32) * mask).astype(np.uint8)
                        base = Image.fromarray(rgb).convert("RGBA")
                elif o.get("style") == "panel":
                    im = self.cards.panel(o["text"], int(o.get("size", 64) * self.scale), W)
                    paste_anim(base, im, W * float(o.get("x", 0.5)), H * float(o.get("y", 0.8)), lu, dur,
                               slam=o.get("slam", False), fade_in=float(o.get("fade_in", 0.3)))
                else:
                    im = self.cards.plain(o["text"], int(o.get("size", 48) * self.scale))
                    paste_anim(base, im, W * float(o.get("x", 0.5)), H * float(o.get("y", 0.8)), lu, dur,
                               slam=o.get("slam", False), fade_in=float(o.get("fade_in", 0.3)))
            img = np.asarray(base.convert("RGB"))
        return img

    def _mix(self, tr, a, b, w):
        """w 0..1 across the whole transition (0.5 = the cut)."""
        if tr == "fade":
            return blend(a, b, ease("inout", w))
        if tr == "pixelize":
            block = int(2 + 46 * (1 - abs(w - 0.5) * 2) * self.scale)
            return mosaic(blend(a, b, ease("inout", w)), block)
        if tr == "whip":
            W = a.shape[1]
            off = int(ease("inout", w) * W)
            blur = 120 * self.scale * (1 - abs(w - 0.5) * 2)
            strip = np.concatenate([a, b], axis=1)[:, off:off + W]
            return motion_blur_x(strip, blur)
        return b if w >= 0.5 else a

    def check(self):
        ok = True
        for s in self.shots:
            print(f"  {s.at:6.2f}-{s.at + s.dur:6.2f}  {s.name:<22} src={s.s.get('src', 'black'):<16} in={s.t_in:7.2f}s"
                  f"  trans={s.trans['type']}")
        for a, b in zip(self.shots, self.shots[1:]):
            gap = b.at - (a.at + a.dur)
            if abs(gap) > 1e-6:
                print(f"  ! {'gap' if gap > 0 else 'overlap'} of {abs(gap):.3f}s between {a.name} and {b.name}")
                ok = False
        print(f"  length {self.length:.2f}s")
        if self.missing:
            print(f"  ! footage not recorded yet: {', '.join(self.missing)}")
            ok = False
        return ok

    def close(self):
        for s in self.sources.values():
            s.close()

def main():
    ap = argparse.ArgumentParser(description="Builds the trailer from a shot list.")
    ap.add_argument("shotlist")
    ap.add_argument("--preview", action="store_true", help="half size, 30 fps, quick encode")
    ap.add_argument("--from", dest="t0", type=float, default=0.0)
    ap.add_argument("--to", dest="t1", type=float, default=None)
    ap.add_argument("--stills", help="comma-separated times: write PNGs instead of a video")
    ap.add_argument("--check", action="store_true", help="list the shots and check the timeline")
    ap.add_argument("--out", help="override the output path")
    ap.add_argument("--no-audio", action="store_true")
    a = ap.parse_args()
    find_ffmpeg()
    ed = Edit(a.shotlist, a.preview)
    if a.check:
        sys.exit(0 if ed.check() else 1)
    if ed.missing:
        sys.exit(f"trailer_edit: footage not recorded yet: {', '.join(ed.missing)} (art_src/trailer/record_all.sh)")
    if a.stills:
        base = os.path.splitext(a.out or ed.spec.get("out", "build/trailer/trailer.mp4"))[0]
        os.makedirs(os.path.dirname(base) or ".", exist_ok=True)
        for t in [float(x) for x in a.stills.split(",")]:
            p = f"{base}_{t:06.2f}.png"
            Image.fromarray(ed.frame(t)).save(p)
            print("still", p)
        ed.close()
        return
    t1 = a.t1 if a.t1 is not None else ed.length
    out = a.out or ed.spec.get("out", "build/trailer/trailer.mp4")
    if a.preview:
        out = out.replace(".mp4", "_preview.mp4")
    os.makedirs(os.path.dirname(out) or ".", exist_ok=True)
    cmd = [FFMPEG, "-y", "-v", "error", "-f", "rawvideo", "-pix_fmt", "rgb24", "-s", f"{ed.W}x{ed.H}",
           "-r", str(ed.fps), "-i", "-"]
    audio = ed.spec.get("audio")
    if audio and not a.no_audio:
        cmd += ["-ss", f"{a.t0:.3f}", "-t", f"{t1 - a.t0:.3f}", "-i", audio, "-map", "0:v", "-map", "1:a",
                "-c:a", "aac", "-b:a", "320k"]
    if a.preview:
        cmd += ["-c:v", "libx264", "-preset", "ultrafast", "-crf", "23"]
    else:  # Steam: H.264, high bitrate, yuv420p
        cmd += ["-c:v", "libx264", "-preset", "slow", "-crf", "14", "-pix_fmt", "yuv420p", "-movflags", "+faststart"]
    cmd += ["-shortest", out]
    enc = subprocess.Popen(cmd, stdin=subprocess.PIPE)
    n = int(round((t1 - a.t0) * ed.fps))
    for i in range(n):
        t = a.t0 + i / ed.fps
        enc.stdin.write(np.ascontiguousarray(ed.frame(t)).tobytes())
        if i % ed.fps == 0:
            print(f"\r  {t:6.2f}s / {t1:.2f}s", end="", flush=True)
    enc.stdin.close()
    enc.wait()
    ed.close()
    print(f"\nwrote {out}")

if __name__ == "__main__":
    main()
