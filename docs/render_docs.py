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

ROW_W, ROW_H, GAP, BOX_W = 250, 59, 3, 56  # 38 for name and bars + 21 for the info strip
FOOT_H = 22
BG = (17, 18, 22)
ROW_BG = (41, 43, 51)
POWER_BG = (31, 36, 51)
BOX = {
    "lead": (92, 77, 26), "ok": (43, 84, 51), "chain": (26, 77, 84), "paused": (140, 97, 20),
    "broken": (140, 41, 36), "away": (64, 64, 71),
}
CLASS = {
    "druid": (255, 125, 10), "priest": (240, 240, 240), "warlock": (135, 135, 237),
    "mage": (64, 199, 235), "hunter": (171, 212, 115),
}
MANA, RAGE = (77, 140, 242), (230, 46, 46)
FOCUS = (255, 209, 77)
XP, RESTED, XP_BG = (166, 77, 230), (64, 120, 220), (40, 30, 55)
COIN = {"g": (255, 209, 0), "s": (199, 199, 210), "c": (232, 150, 80)}
F_TINY = font("segoeuib.ttf", 9)

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

def money_parts(copper, compact=True):
    g, s, c = copper // 10000, (copper // 100) % 100, copper % 100
    if compact and g >= 100:
        return [("{:,}".format(g), "g")]
    parts = [("{:,}".format(g), "g")] if g else []
    if (g and not compact) or s:
        parts.append((str(s), "s"))
    if not (compact and g):
        parts.append((str(c), "c"))
    return parts

def money(d, right, cy, copper, f, compact=True):
    """Money as numbers followed by coin dots, right-aligned at `right`, centred on cy."""
    r = 3.2
    parts = money_parts(copper, compact)
    widths = [text_w(d, n, f) + 2 + r * 2 + 4 for n, _ in parts]
    x = right - (sum(widths) - 4)
    for (n, k), w in zip(parts, widths):
        text(d, (x, cy), n, f, (235, 235, 240), "lm")
        cx = x + text_w(d, n, f) + 2 + r
        d.ellipse(S(cx - r, cy - r, cx + r, cy + r), fill=COIN[k])
        x += w

def bag(d, x, cy, free, f, suffix=""):
    col = (255, 85, 68) if free == 0 else (255, 170, 51) if free <= 5 else (221, 221, 221)
    d.rounded_rectangle(S(x, cy - 4, x + 9, cy + 5), radius=2 * K, fill=col)
    d.rectangle(S(x + 2, cy - 6, x + 7, cy - 4), fill=col)
    text(d, (x + 12, cy), str(free), f, col, "lm")
    if suffix:
        text(d, (x + 15 + text_w(d, str(free), f), cy), suffix, F_SMALL, (136, 136, 136), "lm")

def row(img, x, y, m):
    d = ImageDraw.Draw(img)
    cls = CLASS[m["class"]]
    # bar area
    d.rectangle(S(x, y, x + ROW_W, y + ROW_H), fill=ROW_BG)
    name_col = tuple(min(255, int(c * 1.1 + 20)) for c in cls)
    nx = x + 6
    if m.get("lvl"):
        text(d, (nx, y + 3.5), str(m["lvl"]), F_SMALLB, (255, 220, 120))
        nx += text_w(d, str(m["lvl"]), F_SMALLB) + 5
    text(d, (nx, y + 3), m["name"], F_NAME, name_col)
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
    # info strip: XP (rested behind it), then bags left and gold right
    xy = py + 6
    d.rectangle(S(hx, xy, hx + hw, xy + 3), fill=XP_BG)
    if m.get("xp") is not None:
        d.rectangle(S(hx, xy, hx + hw * min(1, m["xp"] + m.get("rest", 0)), xy + 3), fill=RESTED)
        d.rectangle(S(hx, xy, hx + hw * m["xp"], xy + 3), fill=XP)
    ly = y + ROW_H - 9
    bag(d, hx, ly, m.get("free", 0), F_TINY)
    money(d, hx + hw, ly, m.get("copper", 0), F_TINY)
    # status box
    bx = x + ROW_W + GAP
    kind, ic, label = m["status"]
    d.rectangle(S(bx, y, bx + BOX_W, y + ROW_H), fill=BOX[kind])
    if ic:
        img.alpha_composite(icon(ic, 16), (int((bx + BOX_W / 2 - 8) * K), int((y + 4) * K)))
    text(d, (bx + BOX_W / 2, y + ROW_H - 4), label, F_LABEL, (255, 255, 255), "ms")

def footer(d, x, y, w, rows):
    d.rectangle(S(x, y, x + w, y + FOOT_H), fill=(26, 28, 33))
    d.line(S(x, y, x + w, y), fill=(255, 209, 77), width=K)
    text(d, (x + 8, y + FOOT_H / 2), "TEAM", F_LABEL, (255, 209, 77), "lm")
    bag(d, x + 46, y + FOOT_H / 2, sum(m.get("free", 0) for m in rows), F_SMALLB,
        "/ %d free" % sum(m.get("slots", 0) for m in rows))
    money(d, x + w - 8, y + FOOT_H / 2, sum(m.get("copper", 0) for m in rows), F_SMALLB, compact=False)

def frame(rows, title=None, chrome=False, caption=None, pad=14):
    w = ROW_W + GAP + BOX_W
    top = pad + (24 if title else 0) + (20 if chrome else 0)
    h = top + len(rows) * (ROW_H + GAP) + FOOT_H + pad + (22 if caption else 0)
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
    footer(d, pad, y + len(rows) * (ROW_H + GAP), w, rows)
    if chrome:
        gx, gy = pad + w - 14, y + len(rows) * (ROW_H + GAP) + FOOT_H - 14
        d.rectangle(S(gx, gy, gx + 16, gy + 16), fill=(115, 115, 128, 160))
        for o in (4, 8, 12):
            d.line(S(gx + o, gy + 15, gx + 15, gy + o), fill=(220, 220, 225), width=K)
    if caption:
        text(d, (pad, h - pad - 12), caption, F_CAP, (150, 150, 160))
    return img

STATS = [
    dict(lvl=40, xp=0.62, rest=0.15, copper=521307, free=12, slots=80),
    dict(lvl=40, xp=0.58, rest=0.30, copper=34012, free=3, slots=64),
    dict(lvl=39, xp=0.91, rest=0.0, copper=1281544, free=0, slots=72),
    dict(lvl=40, xp=0.40, rest=0.10, copper=8520, free=25, slots=80),
    dict(lvl=40, xp=0.12, rest=0.45, copper=170099, free=7, slots=80),
]

def team(lyra, others, lyra_focus=None):
    return [
        dict(name="Mael", **{"class": "druid"}, hp=100, mp=72, power=RAGE, status=("lead", "crown", "LEADER"), **STATS[0]),
        dict(name="Lyra", **{"class": "priest"}, hp=95, mp=64, status=lyra, focus=lyra_focus, **STATS[1]),
        dict(name="Elya", **{"class": "warlock"}, hp=87, mp=81, status=others, focus="Defias Pillager", **STATS[2]),
        dict(name="Nyra", **{"class": "mage"}, hp=62, mp=45, status=others, focus="Defias Pillager", **STATS[3]),
        dict(name="Ayla", **{"class": "hunter"}, hp=100, mp=90, status=others, **STATS[4]),
    ]

def save(img, name):
    img = img.resize((img.width // K * 1, img.height // K * 1), Image.LANCZOS) if False else img
    img.convert("RGB").save(os.path.join(OUT, name), optimize=True)
    print("wrote", name, img.size)

# 1. hero: the team frame in "healer leads the pack" mode
save(frame(team(("ok", "crown", "> LEAD"), ("chain", "cross", "> HEAL"))), "team-frame.png")

# 2. follow chain: before / after stopping the healer, side by side
a = frame(team(("ok", "crown", "> LEAD"), ("chain", "cross", "> HEAL")), title="Healer follows you, team follows healer")
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
    dict(name="Mael", **{"class": "druid"}, hp=100, mp=72, power=RAGE, status=("lead", "crown", "LEADER"), **STATS[0]),
    dict(name="Lyra", **{"class": "priest"}, hp=100, mp=100, status=("ok", "crown", "> LEAD"), **STATS[1]),
    dict(name="Elya", **{"class": "warlock"}, hp=0, mp=0, pct="dead", status=("broken", "link-broken", "BROKEN"), **STATS[2]),
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
