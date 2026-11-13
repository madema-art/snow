#!/usr/bin/env python3
"""Bakes the SNOW world: a 360-degree alpine massif (course massif_v4).

Writes world/massif_v4.bin (zlib) holding a 1024 x 1024 macro height field over
+-12.8 km and four 512 x 512 masks. The game samples it in SnowMountain and adds
fine relief, cliff bands, cornice lips and kickers at runtime, so this file
holds only the large-scale geography. Deterministic: run it again and the same
mountain comes out. Requires numpy (Pillow only for the preview image).

    python3 tools/build_massif.py [--preview work/massif_preview.png]

Compass: north = -Z, east = +X, south = +Z, west = -X. Azimuth 0 = north,
increasing clockwise (east = 90).

Faces (azimuths are approximate):
  N   steep, icy, cliff bands, narrow couloirs; high glacial valley floor
  NE  hanging snowfields and a long ridge
  E   long forested flank, rocks and technical lines; a forest river valley
  SE  rolling spurs and glades
  S   broad open snowfields, ramps and rollers; the lowest, widest valley
  SW  big open couloir and ramps toward a meadow basin
  W   deep ravines between massive ridgelines, cornices, gap jumps
  NW  rock spires and a long serrated ridge
"""
import math
import struct
import sys
import zlib

import numpy as np

N = 1280                 # height samples per side
M = 640                  # mask samples per side
EXTENT = 16000.0         # half width of the baked square (m)
SCALE = 1.25             # skeleton coordinates are authored in km at 1/SCALE
SUMMIT_HEIGHT = 3620.0
SEED = 4404

# Per-compass keyframes (N, NE, E, SE, S, SW, W, NW).
BASE_RADIUS = [8750, 9600, 10100, 9750, 10600, 9500, 9100, 8800]   # where the mountain meets its valley floor
FLOOR = [1050, 860, 600, 520, 380, 460, 720, 940]                # valley floor elevation
CONCAVITY = [1.95, 1.7, 1.35, 1.45, 1.15, 1.4, 1.6, 1.85]       # steepness near the top
OUTER = [1.25, 1.32, 1.22, 1.36, 1.4, 1.28, 1.2, 1.24]           # where the surrounding ranges rise (x base radius)
CLIFFS = [0.85, 0.5, 0.2, 0.22, 0.08, 0.3, 0.55, 0.6]          # cliff-band strength
FOREST = [0.3, 0.55, 1.0, 0.75, 0.35, 0.45, 0.55, 0.4]           # forest density
TREELINE = [1750, 1950, 2250, 2200, 2150, 2050, 1950, 1800]      # treeline elevation
ROUGH = [1.25, 1.0, 0.8, 0.85, 0.55, 0.8, 1.1, 1.2]              # rock relief

# Flank shape by the direction a slope faces (N, NE, E, SE, S, SW, W, NW):
# drop A (m) reached over length L (m) below a crest, plus a steady grade.
# North-facing slopes are short and brutal, south-facing ones long and open.
FLANK_DROP = [360, 300, 220, 150, 80, 170, 280, 320]
FLANK_LENGTH = [480, 560, 700, 900, 1100, 800, 560, 500]
FLANK_GRADE = 0.42

# Ridge skeleton (km east, km south, elevation m). Peaks join along the summit
# ridge; eight aretes run out to the valleys, each with a side spur.
S0 = (0.0, 0.0, 3650.0)
P1 = (-1.9, -1.45, 3390.0)    # north-west peak
P2 = (1.7, 1.3, 3300.0)       # south-east peak
RIDGES = [
    [S0, (-0.9, -0.62, 3330.0), P1],                                           # summit ridge NW
    [S0, (0.8, 0.68, 3235.0), P2],                                             # summit ridge SE
    [P1, (-3.0, -2.6, 2900.0), (-4.3, -4.6, 2180.0), (-5.0, -6.7, 1250.0)],    # NW arete
    [S0, (-0.1, -1.6, 3180.0), (-0.45, -3.6, 2480.0), (0.05, -5.6, 1700.0), (-0.3, -7.3, 1130.0)],  # N arete
    [S0, (1.2, -1.0, 3120.0), (2.9, -2.6, 2560.0), (4.3, -4.5, 1760.0), (5.4, -6.1, 1000.0)],      # NE arete
    [P2, (3.1, 0.75, 2900.0), (5.1, 1.2, 2020.0), (7.5, 0.9, 860.0)],          # E arete
    [P2, (2.9, 2.7, 2700.0), (4.3, 4.5, 1880.0), (5.5, 6.3, 840.0)],           # SE arete
    [S0, (-0.35, 1.65, 3190.0), (-0.65, 3.7, 2390.0), (0.2, 5.8, 1350.0), (0.0, 7.7, 560.0)],     # S arete
    [S0, (-1.35, 1.0, 3140.0), (-3.0, 2.3, 2480.0), (-4.8, 3.9, 1580.0), (-6.0, 5.7, 760.0)],     # SW arete
    [P1, (-3.1, -0.55, 2930.0), (-5.0, -0.2, 2160.0), (-7.0, 0.45, 1180.0), (-8.1, 0.2, 880.0)],  # W arete
]
# Side spurs: [ridge index, point index to branch from, azimuth deg, length km, end elevation].
SPURS = [
    [2, 2, 270, 2.2, 1500], [3, 2, 40, 2.0, 1650], [4, 2, 100, 2.4, 1500], [5, 1, 30, 2.0, 1600],
    [6, 1, 80, 2.2, 1450], [7, 2, 130, 2.2, 1350], [8, 2, 200, 2.4, 1300], [9, 1, 330, 2.0, 1650],
    [3, 3, 320, 1.6, 1300], [7, 3, 220, 1.8, 900], [8, 3, 160, 1.6, 900], [4, 3, 30, 1.6, 1100],
]

def ang_interp(theta, table):
    """Smooth periodic interpolation of 8 compass keyframes (theta in radians)."""
    t = np.mod(theta, 2 * np.pi) / (2 * np.pi) * 8.0
    i0 = np.floor(t).astype(int) % 8
    f = t - np.floor(t)
    tab = np.asarray(table, dtype=np.float64)
    # Catmull-Rom on a ring.
    p0 = tab[(i0 - 1) % 8]
    p1 = tab[i0]
    p2 = tab[(i0 + 1) % 8]
    p3 = tab[(i0 + 2) % 8]
    return 0.5 * ((2 * p1) + (-p0 + p2) * f + (2 * p0 - 5 * p1 + 4 * p2 - p3) * f * f + (-p0 + 3 * p1 - 3 * p2 + p3) * f ** 3)


class Noise:
    """Vectorised 2D gradient noise with fBm and ridged variants."""

    def __init__(self, seed):
        rng = np.random.default_rng(seed)
        self.perm = rng.permutation(512).astype(np.int64)
        self.perm = np.concatenate([self.perm, self.perm])
        angles = rng.uniform(0, 2 * np.pi, 512)
        self.gx = np.cos(angles)
        self.gy = np.sin(angles)

    def grad(self, ix, iy, fx, fy):
        h = self.perm[(self.perm[ix & 511] + iy) & 1023] & 511
        return self.gx[h] * fx + self.gy[h] * fy

    def noise(self, x, y):
        ix = np.floor(x).astype(np.int64)
        iy = np.floor(y).astype(np.int64)
        fx = x - ix
        fy = y - iy
        u = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
        v = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
        n00 = self.grad(ix, iy, fx, fy)
        n10 = self.grad(ix + 1, iy, fx - 1, fy)
        n01 = self.grad(ix, iy + 1, fx, fy - 1)
        n11 = self.grad(ix + 1, iy + 1, fx - 1, fy - 1)
        return (n00 + (n10 - n00) * u + (n01 - n00) * v + (n00 - n10 - n01 + n11) * u * v) * 1.4

    def fbm(self, x, y, octaves, lac=2.03, gain=0.5):
        total = np.zeros_like(x)
        amp = 1.0
        norm = 0.0
        for o in range(octaves):
            total += self.noise(x + o * 17.1, y - o * 9.3) * amp
            norm += amp
            amp *= gain
            x = x * lac
            y = y * lac
        return total / norm

    def ridged(self, x, y, octaves, lac=2.1, gain=0.55):
        total = np.zeros_like(x)
        amp = 1.0
        norm = 0.0
        weight = np.ones_like(x)
        for o in range(octaves):
            n = 1.0 - np.abs(self.noise(x + o * 31.7, y + o * 7.9))
            n = n * n * weight
            weight = np.clip(n * 1.6, 0, 1)
            total += n * amp
            norm += amp
            amp *= gain
            x = x * lac
            y = y * lac
        return total / norm


def angdiff(a, b):
    return (a - b + np.pi) % (2 * np.pi) - np.pi


def flow_accumulation(h):
    """D8 flow accumulation (cells draining through each cell)."""
    n = h.shape[0]
    pad = np.pad(h, 1, mode="edge")
    best = np.zeros_like(h)
    rcv = np.arange(n * n).reshape(n, n)
    idx = np.arange(n * n).reshape(n, n)
    ipad = np.pad(idx, 1, mode="edge")
    for dy in (-1, 0, 1):
        for dx in (-1, 0, 1):
            if dx == 0 and dy == 0:
                continue
            nb = pad[1 + dy:n + 1 + dy, 1 + dx:n + 1 + dx]
            drop = (h - nb) / (1.4142 if dx and dy else 1.0)
            better = drop > best
            best = np.where(better, drop, best)
            rcv = np.where(better, ipad[1 + dy:n + 1 + dy, 1 + dx:n + 1 + dx], rcv)
    order = np.argsort(-h, axis=None)
    acc = np.ones(n * n)
    rflat = rcv.ravel()
    acc_l = acc.tolist()
    r_l = rflat.tolist()
    for i in order.tolist():
        j = r_l[i]
        if j != i:
            acc_l[j] += acc_l[i]
    return np.array(acc_l).reshape(n, n), best


def fill_pits(h, d, outlets):
    """Priority-flood: every cell drains to the map edge (no closed hollows a
    stopped rider could be trapped in). Filled flats get a gentle tilt."""
    import heapq
    n = h.shape[0]
    flat = h.ravel().tolist()
    out = list(flat)
    done = bytearray(n * n)
    heap = []
    seeds = set(np.flatnonzero(outlets.ravel()).tolist())
    for i in range(n):
        seeds.update((i, (n - 1) * n + i, i * n, i * n + n - 1))
    for k in seeds:
        done[k] = 1
        heapq.heappush(heap, (out[k], k))
    eps = 0.07 * d       # filled hollows keep a 0.07 grade: a rider glides out
    while heap:
        hv, k = heapq.heappop(heap)
        r, c = divmod(k, n)
        for dr, dc in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            rr, cc = r + dr, c + dc
            if 0 <= rr < n and 0 <= cc < n:
                j = rr * n + cc
                if not done[j]:
                    done[j] = 1
                    if out[j] <= hv + eps:
                        out[j] = hv + eps
                    heapq.heappush(heap, (out[j], j))
    filled = np.array(out).reshape(n, n)
    print("  pits filled:", int((filled - h > 0.5).sum()), "cells", flush=True)
    return filled


def slope_of(h, d):
    gy, gx = np.gradient(h, d)
    return np.sqrt(gx * gx + gy * gy)


def blur(a, passes=1):
    for _ in range(passes):
        a = (np.roll(a, 1, 0) + np.roll(a, -1, 0) + np.roll(a, 1, 1) + np.roll(a, -1, 1) + 4 * a) / 8.0
    return a


def build():
    d = 2 * EXTENT / (N - 1)
    coords = -EXTENT + np.arange(N) * d
    X, Z = np.meshgrid(coords, coords)          # rows = z, columns = x
    noise = Noise(SEED)
    r = np.sqrt(X * X + Z * Z)
    theta = np.arctan2(X, -Z)                    # 0 north, +pi/2 east
    # Slow wander of the azimuth so faces never meet along straight radial lines.
    warp = noise.fbm(X / 5200.0, Z / 5200.0, 3) * 0.35
    th = theta + warp * np.clip(r / 3000.0, 0, 1)

    R = ang_interp(th, BASE_RADIUS) * (1.0 + 0.05 * noise.fbm(np.cos(th) * 2.0 + 5.0, np.sin(th) * 2.0 + 5.0, 2))
    floor = ang_interp(th, FLOOR)
    outer = ang_interp(th, OUTER)
    u = r / R
    # --- The massif: every point takes the highest of the flanks falling away
    # from the ridge skeleton (a smooth maximum, so valleys get round bottoms).
    segments = []
    def lift(p):
        d = math.hypot(p[0], p[1])
        return (p[0] * SCALE, p[1] * SCALE, p[2] + 320.0 * min(1.0, max(0.0, (d - 2.5) / 3.0)))
    ridges = [[lift(p) for p in ridge] for ridge in RIDGES]
    for ridge in ridges:
        for a0, a1 in zip(ridge[:-1], ridge[1:]):
            segments.append((a0, a1))
    for ri, pi, az, length, end in SPURS:
        base = ridges[ri][pi]
        a = math.radians(az)
        tip = (base[0] + math.sin(a) * length * SCALE, base[1] - math.cos(a) * length * SCALE, end)
        segments.append(((base[0], base[1], base[2] - 60.0), tip))
    K = 55.0
    acc = np.zeros_like(X)
    # Ridges meander: distances to the skeleton are measured in a warped space.
    WX = X + 520.0 * noise.fbm(X / 2300.0 + 3.1, Z / 2300.0 - 8.2, 3) + 160.0 * noise.fbm(X / 700.0, Z / 700.0 + 4.0, 2)
    WZ = Z + 520.0 * noise.fbm(X / 2300.0 - 6.4, Z / 2300.0 + 1.7, 3) + 160.0 * noise.fbm(X / 700.0 + 9.0, Z / 700.0, 2)
    for (ax, az_, ae), (bx, bz, be) in segments:
        ax *= 1000.0; az_ *= 1000.0; bx *= 1000.0; bz *= 1000.0
        vx, vz = bx - ax, bz - az_
        length2 = vx * vx + vz * vz
        t = np.clip(((WX - ax) * vx + (WZ - az_) * vz) / length2, 0.0, 1.0)
        cx = ax + vx * t
        cz = az_ + vz * t
        dx_, dz_ = WX - cx, WZ - cz
        dist = np.sqrt(dx_ * dx_ + dz_ * dz_)
        facing = np.arctan2(dx_, -dz_)
        crest = ae + (be - ae) * t
        crest += noise.fbm(t * 5.0 + ax * 0.001, ae * 0.01, 2) * 70.0 * np.sin(t * np.pi)
        drop = ang_interp(facing, FLANK_DROP) * (1.0 - np.exp(-dist / ang_interp(facing, FLANK_LENGTH))) + FLANK_GRADE * dist
        acc += np.exp(np.clip((crest - drop - SUMMIT_HEIGHT) / K, -700, 50))
    h = SUMMIT_HEIGHT + K * np.log(acc + 1e-300)
    # A rounded summit dome: the board can point any way and roll off gently.
    # The summit: a small, nearly flat top (~8 m) that falls away at a steady
    # 0.42 grade in every direction -- gentle enough to roll off anywhere, and a
    # straight (not convex) slope, so from the top you can see down every face.
    dome = SUMMIT_HEIGHT + 3.4 - 0.42 * np.sqrt(r * r + 8.0 ** 2)
    h = np.maximum(h, dome) + 20.0 * np.log1p(np.exp(-np.abs(h - dome) / 20.0))
    # Valley floors around the base (gently falling outward) and the surrounding
    # ranges beyond them, broken by passes where rivers leave.
    plain = floor - 0.025 * np.clip(r - R * 0.8, 0.0, None) + noise.fbm(X / 3000.0, Z / 3000.0, 3) * 35.0
    h = np.maximum(h, plain) + K * np.log1p(np.exp(-np.abs(h - plain) / K))
    # The ranges' front wanders in and out by kilometres; foothills dot the floors.
    front = outer + 0.16 * noise.fbm(np.cos(theta) * 1.7 + X / 9000.0, np.sin(theta) * 1.7 + Z / 9000.0, 3)
    rise = np.clip((u - front) / 0.45, 0.0, 1.0)
    foot = np.clip((u - 1.1) / 0.15, 0.0, 1.0) * np.clip(noise.fbm(X / 2600.0 - 40.0, Z / 2600.0 + 12.0, 3) - 0.12, 0.0, None)
    h += foot * 1300.0
    h += noise.fbm(X / 2200.0 + 60.0, Z / 2200.0, 2) * 60.0 * np.clip(u - 0.95, 0.0, 1.0)
    ranges = noise.ridged(X / 2600.0, Z / 2600.0, 5)
    gaps = 0.55 + 0.45 * noise.fbm(X / 4200.0 + 11.0, Z / 4200.0 - 3.0, 2)
    h += rise ** 1.5 * (800.0 + 1800.0 * ranges) * np.clip(gaps + 0.25, 0.0, 1.0)
    beyond = np.clip(u - 1.0, 0.0, None)
    # Rock relief: stronger high on the mountain and on rough faces.
    rough = ang_interp(th, ROUGH)
    alt = np.clip((h - floor) / (SUMMIT_HEIGHT - floor), 0.0, 1.0)
    uc = np.clip(u, 0.0, 1.0)
    relief = noise.ridged(X / 900.0 + 3.0, Z / 900.0 - 7.0, 5) - 0.45
    h += relief * (18.0 + 60.0 * alt) * rough * np.clip(1.1 - beyond * 2.0, 0.25, 1.0)
    h += noise.fbm(X / 1600.0, Z / 1600.0, 4) * 45.0

    # Small-scale unevenness so water (and the gullies it cuts) wanders.
    h += noise.fbm(X / 280.0 + 70.0, Z / 280.0 - 30.0, 3) * 14.0 * np.clip(alt * 1.5, 0.2, 1.0)
    # Stream-power erosion: dendritic gullies and spurs on every face.
    print("eroding", flush=True)
    for it in range(32):
        acc, s = flow_accumulation(h)
        area = acc * d * d
        incision = 0.0011 * np.sqrt(area) * np.clip(s, 0, 1.2)
        incision *= np.clip(alt + 0.25, 0.0, 1.0)
        h -= np.clip(incision, 0, 5.0)
        h = 0.88 * h + 0.12 * blur(h)   # gully walls stay rideable (no slot canyons)
        if it % 7 == 0:
            print("  pass", it, "max incision", float(incision.max()), flush=True)
    acc, s = flow_accumulation(h)

    # --- Cliff bands, carved here (not at runtime) so the pit fill below can
    # guarantee that no band ever encloses a hollow a rider could be trapped in.
    alt = np.clip((h - floor) / (SUMMIT_HEIGHT - floor), 0.0, 1.0)
    gully = np.clip(np.log(acc) / 9.0, 0, 1)
    patches = noise.fbm(X / 700.0 + 40.0, Z / 700.0, 3)
    cliff = ang_interp(th, CLIFFS) * np.clip((alt - 0.12) / 0.18, 0, 1) * np.clip((0.97 - alt) / 0.1, 0, 1)
    cliff *= np.clip(0.55 + patches * 1.6, 0, 1)
    cliff *= 1.0 - np.clip((gully - 0.55) / 0.2, 0, 1)        # couloirs follow the gullies
    cliff *= np.clip((u - 0.06) / 0.08, 0, 1)                  # never on the summit cap
    cliff = blur(np.clip(cliff, 0, 1), 6)
    broad = slope_of(blur(h, 3), d)
    gate = np.clip((broad - 0.38) / 0.24, 0, 1)
    gaps = np.clip((noise.fbm(X / 700.0 + 13.0, Z / 700.0 - 21.0, 1) + 0.2) / 0.55, 0, 1)
    weight = np.clip(cliff * gate * gaps / 0.6, 0, 1) * 0.82
    spacing = 140.0
    wobble = noise.fbm(X / 420.0 - 5.0, Z / 420.0 + 9.0, 2)
    phase = h / spacing + wobble * 0.12
    frac = phase - np.floor(phase)
    riser = np.clip((frac - 0.8) / 0.2, 0, 1)
    riser = riser * riser * (3 - 2 * riser)
    terraced = (np.floor(phase) + riser - wobble * 0.12) * spacing
    h = h + weight * (terraced - h)
    h = 0.75 * h + 0.25 * blur(h)                                # no cubic overshoot at the lips
    # Mountain hollows (including any left by the bands) drain to the valley
    # floors, which stay basins: they are where every descent ends.
    h = fill_pits(h, d, (u > 0.92) & (h < floor + 100.0))
    acc, s = flow_accumulation(h)

    # The top stays a clean, rideable dome (erosion must not notch it).
    dome = SUMMIT_HEIGHT + 3.4 - 0.42 * np.sqrt(r * r + 8.0 ** 2)
    cap = np.clip(1.0 - r / 260.0, 0.0, 1.0)
    h = h * (1.0 - cap) + np.maximum(h, dome) * cap

    slope = slope_of(h, d)
    alt = np.clip((h - floor) / (SUMMIT_HEIGHT - floor), 0.0, 1.0)
    # --- masks (computed at full resolution, stored at M)
    # The stored cliff mask marks where bands were carved (rock colour, rocks).
    cliff = np.clip(weight / 0.82 + 0.3 * cliff, 0, 1)
    treeline = ang_interp(th, TREELINE)
    forest = ang_interp(th, FOREST) * np.clip((treeline - h) / 250.0, 0, 1)
    forest *= np.clip((0.95 - slope) / 0.35, 0, 1)
    forest *= np.clip(0.5 + noise.fbm(X / 1100.0 - 20.0, Z / 1100.0, 3) * 1.4, 0.15, 1)
    # Valley floors: the bottom of the mountain, on every side. Low, gentle and
    # beyond the mountain's base -- never a ravine floor high on the flanks.
    floor_mask = (h < floor + 90.0) & (u > 0.86) & (slope < 0.24)
    finish = blur(floor_mask.astype(np.float64), 2)
    forest *= 1.0 - 0.6 * finish                                 # meadows on the floors
    # Cornices: the lee (east-north-east) lip of high, sharp crests.
    crest = h - (np.roll(h, 3, 0) + np.roll(h, -3, 0) + np.roll(h, 3, 1) + np.roll(h, -3, 1)) * 0.25
    lee = np.roll(crest, 2, 1)
    cornice = np.clip((lee - 14.0) / 30.0, 0, 1) * np.clip((alt - 0.45) / 0.2, 0, 1)

    sx = int(np.argmax(h) % N)
    sz = int(np.argmax(h) // N)
    summit = (float(coords[sx]), float(coords[sz]), float(h[sz, sx]))
    print("summit", summit, "min", float(h.min()), "max", float(h.max()))
    return h, cliff, forest, finish, cornice, summit, slope, X, Z


def down(a):
    f = N // M
    return a.reshape(M, f, M, f).mean(axis=(1, 3))


def write(path, h, masks, summit):
    lo = float(h.min()) - 10.0
    scale = 0.08                               # metres per height unit (5.2 km range)
    q = np.clip(np.round((h - lo) / scale), 0, 65535).astype("<u2")
    header = struct.pack("<8sIIffffff", b"SNOWMAP1", N, M, EXTENT, lo, scale, summit[0], summit[1], summit[2])
    body = q.tobytes()
    for m in masks:
        body += np.clip(np.round(down(m) * 255.0), 0, 255).astype(np.uint8).tobytes()
    raw = header + body
    with open(path, "wb") as f:
        f.write(struct.pack("<I", len(raw)))
        f.write(zlib.compress(raw, 9))
    print("wrote", path, len(raw), "bytes raw")


def preview(path, h, cliff, forest, finish, cornice):
    from PIL import Image
    d = 2 * EXTENT / (N - 1)
    gy, gx = np.gradient(h, d)
    light = np.array([-0.5, 0.6, -0.62])
    light /= np.linalg.norm(light)
    n = np.dstack([-gx, np.ones_like(h), -gy])
    n /= np.linalg.norm(n, axis=2, keepdims=True)
    shade = np.clip(n @ light, 0, 1)
    t = np.clip((h - 300) / 3400, 0, 1)
    snow = np.array([0.95, 0.96, 0.98])
    low = np.array([0.55, 0.62, 0.55])
    col = low[None, None] * (1 - t[..., None]) + snow[None, None] * t[..., None]
    col = col * (0.35 + 0.75 * shade[..., None])
    col[..., 0] -= forest * 0.35
    col[..., 2] -= forest * 0.25
    col[..., 0] += cliff * 0.25
    col[..., 2] += finish * 0.35
    col[..., 1] -= cornice * 0.4
    img = (np.clip(col, 0, 1) * 255).astype(np.uint8)
    Image.fromarray(img).save(path)
    print("preview", path)


if __name__ == "__main__":
    h, cliff, forest, finish, cornice, summit, slope, X, Z = build()
    write("world/massif_v4.bin", h, [finish, cliff, forest, cornice], summit)
    if "--preview" in sys.argv:
        preview(sys.argv[sys.argv.index("--preview") + 1], h, cliff, forest, finish, cornice)
