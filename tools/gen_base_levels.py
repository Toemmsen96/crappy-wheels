"""Generates the built-in levels 2-5 as level JSON (LevelData format 1).

Usage: python3 tools/gen_base_levels.py levels/base [level2 ...]
The same files go into Base/ of the crappy-wheels-levels repository, which
the backend checks leaderboard runs against.

Tracks are written as surface polylines in driving order; the solid side is on
the right of the driving direction (below for a floor driven rightwards, above
for a ceiling driven leftwards). Each segment becomes a 20 px thick tile whose
top face lies on the polyline.
"""
import json
import math
import sys

THICK = 20.0
OVERLAP = 2.0
BALL_RADIUS = 19.31


def r4(v):
    return round(v, 4)


class Level:
    def __init__(self, ident, name, description):
        self.ident = ident
        self.name = name
        self.description = description
        self.tiles = []
        self.balls = []
        self.boosts = []
        self.start = (0.0, 0.0)
        self.finish = (0.0, 0.0)

    def track(self, points, collision=True):
        for (ax, ay), (bx, by) in zip(points, points[1:]):
            dx, dy = bx - ax, by - ay
            length = math.hypot(dx, dy)
            if length < 1e-6:
                continue
            nx, ny = -dy / length, dx / length  # Right of the driving direction.
            cx = (ax + bx) / 2 + nx * THICK / 2
            cy = (ay + by) / 2 + ny * THICK / 2
            self.tiles.append({"x": r4(cx), "y": r4(cy), "rotation": r4(math.atan2(dy, dx)),
                               "length": r4(length + OVERLAP), "collision": collision})

    def wall(self, x, y_top, y_bottom):
        """A vertical block whose top face is at y_top."""
        self.tiles.append({"x": r4(x), "y": r4((y_top + y_bottom) / 2), "rotation": r4(math.pi / 2),
                           "length": r4(y_bottom - y_top), "collision": True})

    def ball(self, x, y, scale, collision=True):
        self.balls.append({"x": r4(x), "y": r4(y), "scale": r4(scale), "collision": collision})

    def ball_on(self, x, surface_y, scale, collision=True):
        """A ball resting on a flat floor whose top is at surface_y."""
        self.ball(x, surface_y - BALL_RADIUS * scale, scale, collision)

    def boost(self, x, y, angle, scale=1.0, strength=1000.0):
        """A pad whose centre is a little above the surface point (x, y), pushing along angle."""
        nx, ny = math.sin(angle), -math.cos(angle)  # Left of the push, i.e. up off the surface.
        self.boosts.append({"x": r4(x + nx * 10 * scale), "y": r4(y + ny * 10 * scale),
                            "rotation": r4(angle), "scale": r4(scale), "strength": r4(strength)})

    def to_dict(self):
        return {
            "format_version": 1,
            "id": self.ident,
            "name": self.name,
            "author": "Toemmsen96",
            "description": self.description,
            "start": {"x": r4(self.start[0]), "y": r4(self.start[1])},
            "finish": {"x": r4(self.finish[0]), "y": r4(self.finish[1])},
            "tiles": self.tiles,
            "balls": self.balls,
            "boosts": self.boosts,
        }


# --- Path helpers: each returns a list of points, to be chained. ---

def line(a, b, step=60.0):
    n = max(1, math.ceil(math.dist(a, b) / step))
    return [(a[0] + (b[0] - a[0]) * i / n, a[1] + (b[1] - a[1]) * i / n) for i in range(n + 1)]


def func(f, x0, x1, step=25.0):
    n = max(1, math.ceil(abs(x1 - x0) / step))
    return [(x0 + (x1 - x0) * i / n, f(x0 + (x1 - x0) * i / n)) for i in range(n + 1)]


def hill(x0, x1, y, height):
    """A smooth bump (height > 0 is up) from x0 to x1 on base line y."""
    return func(lambda x: y - height * (1 - math.cos(2 * math.pi * (x - x0) / (x1 - x0))) / 2, x0, x1)


def ease(x0, y0, x1, y1):
    """A smooth S-curve from (x0, y0) to (x1, y1), flat at both ends."""
    return func(lambda x: y0 + (y1 - y0) * (1 - math.cos(math.pi * (x - x0) / (x1 - x0))) / 2, x0, x1)


def arc(cx, cy, r, a0, a1, step=22.0):
    """Points on a circle, angles in radians in screen space (y down), from a0 to a1."""
    n = max(2, math.ceil(abs(a1 - a0) * r / step))
    return [(cx + r * math.cos(a0 + (a1 - a0) * i / n), cy + r * math.sin(a0 + (a1 - a0) * i / n)) for i in range(n + 1)]


def chain(*parts):
    points = []
    for part in parts:
        for p in part:
            if not points or math.dist(points[-1], p) > 1e-6:
                points.append(p)
    return points


# --- Levels ---

def level2():
    lv = Level("level2", "Level 2: Rolling Hills",
               "Easy going over gentle hills and little jumps. Come up short and you just roll through the dip.")
    lv.start = (0, -12)
    pts = chain(line((-120, 0), (260, 0)), hill(260, 660, 0, 35), line((660, 0), (720, 0)))
    k, end = kicker_gap(720, 0, 15, 40, 70, 0, 120, 0)
    pts = chain(pts, k)
    x, y = end
    pts = chain(pts, hill(x, x + 400, y, 60), line((x + 400, y), (x + 460, y)))
    x += 460
    k, end = kicker_gap(x, y, 16, 40, 80, 0, 140, 25)
    pts = chain(pts, k)
    x, y = end
    pts = chain(pts, line((x, y), (x + 60, y)), hill(x + 60, x + 420, y, -45))
    lv.ball(x + 240, y + 50, 0.6, collision=False)  # Scenery in the dip.
    x += 420
    pts = chain(pts, hill(x, x + 480, y, 60), line((x + 480, y), (x + 560, y)))
    x += 560
    k, end = kicker_gap(x, y, 18, 50, 90, 0, 140, 20)
    pts = chain(pts, k)
    x, y = end
    pts = chain(pts, line((x, y), (x + 80, y)))
    x += 80
    lv.boost(x - 40, y, 0, 1.0, 600)
    k, end = kicker_gap(x, y, 18, 50, 120, 0, 160, 25)
    pts = chain(pts, k)
    x, y = end
    pts = chain(pts, hill(x, x + 380, y, 50), line((x + 380, y), (x + 620, y)))
    x += 620
    lv.track(pts)
    lv.wall(x + 10, y - 80, y + 10)
    lv.finish = (x - 90, y - 15)
    return lv


def ramp_up(x, y, angle_deg, ramp_len, r=160.0):
    """From flat ground at (x, y), curve up to angle_deg, then go straight for
    ramp_len. Returns (points, lip)."""
    a = math.radians(angle_deg)
    curve = arc(x, y - r, r, math.pi / 2, math.pi / 2 + a)
    curve = [(2 * x - px, py) for px, py in curve]  # Mirrored: bends upwards to the right.
    cx, cy = curve[-1]
    lip = (cx + ramp_len * math.cos(a), cy - ramp_len * math.sin(a))
    return chain(curve, line((cx, cy), lip)), lip


def ramp_point(x, y, angle_deg, along, r=160.0):
    """The point `along` px up the straight part of ramp_up(x, y, angle_deg, ...)."""
    a = math.radians(angle_deg)
    cx, cy = x + r * math.sin(a), y - r * (1 - math.cos(a))
    return cx + along * math.cos(a), cy - along * math.sin(a)


def kicker_gap(x, y, angle_deg, ramp_len, gap, pit_depth, land_len, land_drop):
    """A ramp from flat ground at (x, y) curving up to angle_deg, a straight lip of
    ramp_len, a pit gap wide, and a deck a little below the lip that runs downhill
    land_drop over land_len. Coming up short lands in the pit, whose floor slopes
    gently up to the deck, so the car can still drive out. Returns (points, end)."""
    a = math.radians(angle_deg)
    r = 160.0
    # Curve from flat to the ramp angle: circle above the floor.
    curve = arc(x, y - r, r, math.pi / 2, math.pi / 2 + a)
    curve = [(2 * x - px, py) for px, py in curve]  # Mirror: the curve bends upwards to the right.
    cx, cy = curve[-1]
    lip = (cx + ramp_len * math.cos(a), cy - ramp_len * math.sin(a))
    deck = (lip[0] + gap, lip[1] + 12)
    floor_y = y + pit_depth
    face = (lip[0] + 25, floor_y)  # Steep face under the lip.
    floor_end = (lip[0] + 25 + gap * 0.15, floor_y)
    end = (deck[0] + land_len, y + land_drop)
    pts = chain(
        curve,
        line((cx, cy), lip),
        line(lip, face, 200),
        line(face, floor_end),
        line(floor_end, (deck[0] - 30, deck[1] + 4)),
        ease(deck[0] - 30, deck[1] + 4, deck[0] + 20, deck[1]),
        ease(deck[0] + 20, deck[1], end[0], end[1]),
    )
    return pts, end


def level3():
    lv = Level("level3", "Level 3: Jump Street",
               "Ramp after ramp. Hit the boost pads and fly over the gaps, or take the slow way through.")
    lv.start = (0, -12)
    pts = line((-120, 0), (300, 0))
    lv.boost(220, 0, 0)
    k1, end = kicker_gap(300, 0, 18, 60, 110, 5, 160, 20)
    pts = chain(pts, k1, line(end, (end[0] + 160, end[1])))
    x, y = end[0] + 160, end[1]
    lv.boost(x - 70, y, 0)
    k2, end = kicker_gap(x, y, 20, 70, 150, 5, 180, 40)
    pts = chain(pts, k2, line(end, (end[0] + 60, end[1])))
    # A quick little one straight after.
    x, y = end[0] + 60, end[1]
    k, end = kicker_gap(x, y, 16, 40, 80, 0, 120, 15)
    pts = chain(pts, k, line(end, (end[0] + 120, end[1])))
    # A boost pad on the ramp itself throws the car over a wide pit.
    x, y = end[0] + 120, end[1]
    lv.boost(*ramp_point(x, y, 22, 25), -math.radians(22), 1.0, 900)
    k, end = kicker_gap(x, y, 22, 60, 230, 0, 160, 30)
    pts = chain(pts, k)
    x, y = end
    pts = chain(pts, line((x, y), (x + 140, y)))
    x += 140
    # Downhill run-up for the big one.
    pts = chain(pts, ease(x, y, x + 260, y + 90))
    x, y = x + 260, y + 90
    pts = chain(pts, line((x, y), (x + 100, y)))
    lv.boost(x + 40, y, 0, 1.0, 1400)
    x += 100
    k3, end = kicker_gap(x, y, 24, 80, 190, 0, 220, 50)
    pts = chain(pts, k3)
    x, y = end
    pts = chain(pts, line((x, y), (x + 100, y)))
    x += 100
    # One for the finish line.
    lv.boost(x - 50, y, 0, 1.0, 800)
    k, end = kicker_gap(x, y, 20, 50, 160, 0, 160, 30)
    pts = chain(pts, k)
    x, y = end
    pts = chain(pts, line((x, y), (x + 300, y)))
    lv.track(pts)
    lv.wall(x + 310, y - 90, y + 10)
    lv.finish = (x + 210, y - 15)
    return lv


def ceiling_over(lv, floor_pts, clearance):
    """A ceiling following floor_pts at `clearance` above it. Its solid side is up,
    so it is laid out right to left."""
    lv.track([(x, y - clearance) for x, y in reversed(floor_pts)])


def level4():
    lv = Level("level4", "Level 4: Cave Run",
               "Through the mountain and over the top. Mind your head in the cave.")
    lv.start = (0, -12)
    pts = line((-120, 0), (60, 0))
    # A jump down towards the cave mouth.
    k, end = kicker_gap(60, 0, 16, 40, 90, 0, 120, 30)
    pts = chain(pts, k)
    pts = chain(pts, ease(end[0], end[1], 420, 70))
    cave_start = 420
    cave = chain(
        line((cave_start, 70), (520, 70)),
        hill(520, 820, 70, 25),
        line((820, 70), (900, 70)),
        hill(900, 1200, 70, -30),
        line((1200, 70), (1280, 70)),
        hill(1280, 1600, 70, 35),
        line((1600, 70), (1700, 70)),
    )
    pts = chain(pts, cave)
    ceiling_over(lv, cave, 80)
    # Cave mouth: a wall down to the ceiling's start, so it looks like rock.
    lv.wall(cave_start - 10, -120, 70 - 80 + 2)
    # Stalactites hanging from the ceiling, high enough to pass under.
    for x in (660, 1050, 1440):
        y_ceiling = [p for p in cave if p[0] >= x][0][1] - 80
        lv.ball(x, y_ceiling - 6, 0.9)
    # Out of the cave: a steep climb with boost pads on it.
    x, y = 1700, 70
    climb = ease(x, y, x + 300, y - 160)
    pts = chain(pts, climb)
    lv.boost(1760, 64, -math.radians(14), 1.0, 700)
    lv.boost(1850, 7, -math.radians(34), 1.0, 700)
    x, y = x + 300, y - 160
    pts = chain(pts, line((x, y), (x + 140, y)))
    x += 140
    # Steps down the far side: short drops onto flat landings.
    for _ in range(2):
        pts = chain(pts, line((x, y), (x + 8, y + 30), 200), line((x + 8, y + 30), (x + 110, y + 30)))
        x, y = x + 110, y + 30
    # Then two jumps down the hillside.
    k, end = kicker_gap(x, y, 18, 40, 110, 0, 130, 40)
    pts = chain(pts, k)
    x, y = end
    pts = chain(pts, line((x, y), (x + 60, y)))
    x += 60
    k, end = kicker_gap(x, y, 20, 40, 130, 0, 140, 40)
    pts = chain(pts, k)
    x, y = end
    lv.track(pts)
    pts2 = chain(line((x, y), (x + 120, y)), ease(x + 120, y, x + 360, y - 70))
    x, y = x + 360, y - 70
    lv.boost(x - 170, y + 52, -math.radians(20), 1.0, 600)
    pts2 = chain(pts2, line((x, y), (x + 60, y)), ease(x + 60, y, x + 300, y + 80), line((x + 300, y + 80), (x + 380, y + 80)))
    x, y = x + 380, y + 80
    # A last jump onto the finish straight.
    k, end = kicker_gap(x, y, 20, 50, 150, 0, 140, 20)
    pts2 = chain(pts2, k)
    x, y = end
    pts2 = chain(pts2, line((x, y), (x + 300, y)))
    lv.track(pts2)
    x += 300
    lv.wall(x + 10, y - 90, y + 10)
    lv.finish = (x - 90, y - 15)
    return lv


def level5():
    lv = Level("level5", "Level 5: Mountain Climb",
               "All the way up. Steep slopes need the boost pads, and if you slip, you roll back down.")
    lv.start = (0, -12)
    pts = line((-120, 0), (260, 0))
    x, y = 260, 0
    # Each stage: a steeper climb with pads, then a ledge to catch your breath.
    stages = [(260, 110, 1, False), (240, 140, 2, True), (220, 160, 2, True), (260, 200, 3, False)]
    for run, rise, pads, jump in stages:
        climb = ease(x, y, x + run, y - rise)
        pts = chain(pts, climb)
        for i in range(pads):
            t = (i + 1) / (pads + 1)
            px = x + run * t
            py = y - rise * (1 - math.cos(math.pi * t)) / 2
            slope = math.atan(rise * math.pi / 2 / run * math.sin(math.pi * t))
            lv.boost(px, py, -slope, 1.0, 650)
        x, y = x + run, y - rise
        pts = chain(pts, line((x, y), (x + 150, y)))
        x += 150
        if jump:
            # Across a gap on the ledge, landing a little higher up.
            lv.boost(x - 50, y, 0, 1.0, 900)
            k, end = kicker_gap(x, y, 20, 50, 150, 0, 120, -15)
            pts = chain(pts, k, line(end, (end[0] + 80, end[1])))
            x, y = end[0] + 80, end[1]
    # Two jumps between peaks near the summit.
    k, end = kicker_gap(x, y, 20, 60, 200, 0, 140, -20)
    lv.boost(x + 40, y, 0, 1.0, 900)
    pts = chain(pts, k)
    x, y = end
    pts = chain(pts, line((x, y), (x + 100, y)))
    x += 100
    k, end = kicker_gap(x, y, 24, 50, 220, 0, 120, -30)
    lv.boost(x - 30, y, 0, 1.0, 1000)
    pts = chain(pts, k)
    x, y = end
    pts = chain(pts, line((x, y), (x + 120, y)))
    x += 120
    # The summit: a last steep pitch.
    pts = chain(pts, ease(x, y, x + 200, y - 120))
    lv.boost(x + 100, y - 60, -math.radians(43), 1.0, 900)
    x, y = x + 200, y - 120
    pts = chain(pts, line((x, y), (x + 260, y)))
    lv.track(pts)
    lv.wall(x + 270, y - 90, y + 10)
    lv.finish = (x + 170, y - 15)
    return lv


LEVELS = {"level2": level2, "level3": level3, "level4": level4, "level5": level5}

if __name__ == "__main__":
    out_dir = sys.argv[1]
    names = sys.argv[2:] or list(LEVELS)
    for name in names:
        level = LEVELS[name]()
        with open(f"{out_dir}/{name}.json", "w") as f:
            f.write(json.dumps(level.to_dict(), indent="\t", sort_keys=True) + "\n")
        print(f"{name}: {len(level.tiles)} tiles, {len(level.balls)} balls, {len(level.boosts)} boosts")
