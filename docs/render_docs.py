"""Render README visuals for HaploBox from the addon's real layout numbers and icons."""
import os, sys
from PIL import Image, ImageDraw, ImageFont, ImageFilter

REPO = sys.argv[1]
OUT = os.path.join(REPO, "docs")
os.makedirs(OUT, exist_ok=True)
K = 2  # render scale

FONTS = "C:/Windows/Fonts/"
def font(name, size): return ImageFont.truetype(FONTS + name, int(size * K))
F_NAME = font("segoeuib.ttf", 12.5)
F_SMALL = font("segoeui.ttf", 10)
F_SMALLB = font("segoeuib.ttf", 10)
F_LABEL = font("segoeuib.ttf", 8.5)
F_TITLE = font("segoeuib.ttf", 13)
F_CAP = font("segoeui.ttf", 11)

ROW_W, ROW_H, GAP, BOX_W = 250, 38, 3, 56
BG = (17, 18, 22)
ROW_BG = (41, 43, 51)
POWER_BG = (31, 36, 51)
BOX = {
    "lead": (92, 77, 26), "ok": (43, 84, 51), "paused": (140, 97, 20),
    "broken": (140, 41, 36), "away": (64, 64, 71),
}
CLASS = {
    "druid": (255, 125, 10), "priest": (240, 240, 240), "warlock": (135, 135, 237),
    "mage": (64, 199, 235), "hunter": (171, 212, 115),
}
MANA, RAGE = (77, 140, 242), (230, 46, 46)
FOCUS = (255, 209, 77)

ICONS = {}
def icon(name, size, color=(255, 255, 255), alpha=1.0):
    key = (name, size, color, alpha)
    if key not in ICONS:
        im = Image.open(os.path.join(REPO, "Media", name + ".tga")).convert("RGBA")
        im = im.resize((int(size * K), int(size * K)), Image.LANCZOS)
        r, g, b, a = im.split()
        a = a.point(lambda v: int(v * alpha))
        solid = Image.new("RGBA", im.size, color + (255,))
        solid.putalpha(a)
        ICONS[key] = solid
    return ICONS[key]

def S(*v): return [int(x * K) for x in v]

def text(d, xy, s, f, fill, anchor="la"):
    d.text((xy[0] * K, xy[1] * K), s, font=f, fill=fill, anchor=anchor)

def text_w(d, s, f): return d.textlength(s, font=f) / K

def row(img, x, y, m):
    d = ImageDraw.Draw(img)
    cls = CLASS[m["class"]]
    # bar area
    d.rectangle(S(x, y, x + ROW_W, y + ROW_H), fill=ROW_BG)
    name_col = tuple(min(255, int(c * 1.1 + 20)) for c in cls)
    text(d, (x + 6, y + 3), m["name"], F_NAME, name_col)
    # focus, top right: crosshair right before the name
    f = m.get("focus")
    ftxt = f if f else "-"
    fcol = FOCUS if f else (119, 119, 119)
    fw = text_w(d, ftxt, F_SMALLB if f else F_SMALL)
    fx = x + ROW_W - 6 - fw
    text(d, (fx, y + 4), ftxt, F_SMALLB if f else F_SMALL, fcol)
    img.alpha_composite(icon("focus", 11, FOCUS, 1.0 if f else 0.35), (int((fx - 14) * K), int((y + 5) * K)))
    # health
    hx, hy, hw, hh = x + 6, y + 19, ROW_W - 12, 13
    back = tuple(int(c * 0.28) for c in cls)
    d.rectangle(S(hx, hy, hx + hw, hy + hh), fill=back)
    d.rectangle(S(hx, hy, hx + hw * m["hp"] / 100, hy + hh), fill=cls)
    pct = m.get("pct", "%d%%" % m["hp"])
    tx, ty = hx + hw - 3, hy + hh / 2
    text(d, (tx + 0.6, ty + 0.6), pct, F_SMALLB, (0, 0, 0), "rm")
    text(d, (tx, ty), pct, F_SMALLB, (255, 255, 255), "rm")
    # power
    py = hy + hh + 3
    d.rectangle(S(hx, py, hx + hw, py + 4), fill=POWER_BG)
    d.rectangle(S(hx, py, hx + hw * m["mp"] / 100, py + 4), fill=m.get("power", MANA))
    # status box
    bx = x + ROW_W + GAP
    kind, ic, label = m["status"]
    d.rectangle(S(bx, y, bx + BOX_W, y + ROW_H), fill=BOX[kind])
    if ic:
        img.alpha_composite(icon(ic, 16), (int((bx + BOX_W / 2 - 8) * K), int((y + 4) * K)))
    text(d, (bx + BOX_W / 2, y + ROW_H - 4), label, F_LABEL, (255, 255, 255), "ms")

def frame(rows, title=None, chrome=False, caption=None, pad=14):
    w = ROW_W + GAP + BOX_W
    top = pad + (24 if title else 0) + (20 if chrome else 0)
    h = top + len(rows) * (ROW_H + GAP) - GAP + pad + (22 if caption else 0)
    img = Image.new("RGBA", (int((w + pad * 2) * K), int(h * K)), BG + (255,))
    d = ImageDraw.Draw(img)
    if title:
        text(d, (pad, pad), title, F_TITLE, (235, 235, 240))
    y = top
    if chrome:
        d.rectangle(S(pad, y - 20, pad + w, y - 2), fill=(26, 28, 33))
        text(d, (pad + 6, y - 11), "HaploBox team - drag to move", F_SMALL, (230, 230, 230), "lm")
        d.rounded_rectangle(S(pad + w - 50, y - 18, pad + w - 2, y - 4), radius=3 * K, fill=(120, 20, 20))
        text(d, (pad + w - 26, y - 11), "Lock", F_SMALLB, (255, 215, 0), "mm")
    for i, m in enumerate(rows):
        row(img, pad, y + i * (ROW_H + GAP), m)
    if chrome:
        gx, gy = pad + w - 14, y + len(rows) * (ROW_H + GAP) - GAP - 14
        d.rectangle(S(gx, gy, gx + 16, gy + 16), fill=(115, 115, 128, 160))
        for o in (4, 8, 12):
            d.line(S(gx + o, gy + 15, gx + 15, gy + o), fill=(220, 220, 225), width=K)
    if caption:
        text(d, (pad, h - pad - 12), caption, F_CAP, (150, 150, 160))
    return img

def team(lyra, others, lyra_focus=None):
    return [
        dict(name="Mael", **{"class": "druid"}, hp=100, mp=72, power=RAGE, status=("lead", "crown", "LEADER")),
        dict(name="Lyra", **{"class": "priest"}, hp=95, mp=64, status=lyra, focus=lyra_focus),
        dict(name="Elya", **{"class": "warlock"}, hp=87, mp=81, status=others, focus="Defias Pillager"),
        dict(name="Nyra", **{"class": "mage"}, hp=62, mp=45, status=others, focus="Defias Pillager"),
        dict(name="Ayla", **{"class": "hunter"}, hp=100, mp=90, status=others),
    ]

def save(img, name):
    img = img.resize((img.width // K * 1, img.height // K * 1), Image.LANCZOS) if False else img
    img.convert("RGB").save(os.path.join(OUT, name), optimize=True)
    print("wrote", name, img.size)

# 1. hero: the team frame in "healer leads the pack" mode
save(frame(team(("ok", "crown", "> LEAD"), ("ok", "cross", "> HEAL"))), "team-frame.png")

# 2. follow chain: before / after stopping the healer, side by side
a = frame(team(("ok", "crown", "> LEAD"), ("ok", "cross", "> HEAL")), title="Healer follows you, team follows healer")
b = frame(team(("broken", "link-broken", "BROKEN"), ("paused", "pause", "> HEAL")), title="Stop the healer: the whole team waits")
chain = Image.new("RGBA", (a.width + b.width + int(20 * K), max(a.height, b.height)), BG + (255,))
chain.alpha_composite(a, (0, 0))
d = ImageDraw.Draw(chain)
ax = a.width + int(2 * K)
text(d, ((ax + int(8 * K)) / K, chain.height / K / 2), ">", font("segoeuib.ttf", 22), (120, 120, 130), "lm")
chain.alpha_composite(b, (a.width + int(20 * K), 0))
save(chain, "follow-chain.png")

# 3. unlocked: drag bar, lock button, resize corner
mixed = [
    dict(name="Mael", **{"class": "druid"}, hp=100, mp=72, power=RAGE, status=("lead", "crown", "LEADER")),
    dict(name="Lyra", **{"class": "priest"}, hp=100, mp=100, status=("ok", "crown", "> LEAD")),
    dict(name="Elya", **{"class": "warlock"}, hp=0, mp=0, pct="dead", status=("broken", "link-broken", "BROKEN")),
]
save(frame(mixed, chrome=True), "unlocked.png")

# 4. leader alert
W, H = 620, 120
al = Image.new("RGBA", (W * K, H * K), (24, 30, 38, 255))
d = ImageDraw.Draw(al)
for i in range(H * K):  # soft vertical gradient, like a dim game scene
    c = int(24 + 20 * i / (H * K))
    d.line([(0, i), (W * K, i)], fill=(c, c + 6, c + 14))
msg = "Nyra stopped following!"
F_WARN = font("segoeuib.ttf", 26)
glow = Image.new("RGBA", al.size, (0, 0, 0, 0))
gd = ImageDraw.Draw(glow)
gd.text((W * K / 2, H * K / 2), msg, font=F_WARN, fill=(0, 0, 0, 255), anchor="mm", stroke_width=3 * K, stroke_fill=(0, 0, 0, 255))
al.alpha_composite(glow.filter(ImageFilter.GaussianBlur(3 * K)))
d = ImageDraw.Draw(al)
d.text((W * K / 2, H * K / 2), msg, font=F_WARN, fill=(255, 72, 0), anchor="mm", stroke_width=1 * K, stroke_fill=(60, 0, 0))
text(d, (W / 2, H - 14), "only on the leader's screen - followers never see it", F_CAP, (170, 170, 180), "ms")
save(al, "leader-alert.png")
