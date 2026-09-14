# -*- coding: utf-8 -*-
"""UI-R1 placeholder pixel asset generator (self-made, no third-party art).

Regenerates every placeholder PNG under game/assets/pixel/ so the 2D observer
prototype ships reproducible, license-clean art.

v3 note: the Kenney Tiny Farm hybrid terrain layer was withdrawn after manual
review found the tile identifications wrong (objects/troughs read as ground).
third_party/kenney_tiny_farm/ stays vendored for future per-tile manual
approval only - this generator never reads or downloads it. All drawings are simple code
shapes in a warm palette; final art can replace files 1:1 later.

Run (Python 3.10+ with Pillow):
    python game/assets/pixel/tools/generate_placeholders.py

Output layout (documented in docs/ui/ASSET_MANIFEST.md):
    tiles/terrain_16.png   8x3 atlas of 16x16 terrain tiles
    npc/npc_sheet_16.png   4x12 sheet of 16x16 frames (idle/walk/run x 4 dirs)
    props/*.png            16x16 / 16x24 world props
    items/*.png            16x16 item icons
    markers/*.png          selection ring / shadow
"""
from __future__ import annotations

import hashlib
import os
from PIL import Image, ImageDraw

HERE = os.path.dirname(os.path.abspath(__file__))
OUT_ROOT = os.path.dirname(HERE)

TILE = 16


# ---------------------------------------------------------------------------
# palette (warm island)
# ---------------------------------------------------------------------------
PAL = {
    "outline": (36, 26, 16, 255),
    # terrain
    "grass_a": (121, 184, 86, 255),
    "grass_b": (114, 173, 80, 255),
    "grass_c": (138, 201, 100, 255),
    "sand_a": (236, 217, 160, 255),
    "sand_b": (224, 198, 136, 255),
    "sand_c": (246, 229, 180, 255),
    "dirt": (201, 160, 106, 255),
    "dirt_b": (186, 145, 92, 255),
    "path": (214, 181, 130, 255),
    "forest_a": (90, 143, 67, 255),
    "forest_b": (81, 130, 60, 255),
    "shallow_a": (79, 163, 184, 255),
    "shallow_b": (92, 176, 195, 255),
    "deep_a": (42, 106, 143, 255),
    "deep_b": (36, 94, 130, 255),
    "rock_a": (157, 148, 137, 255),
    "rock_b": (125, 114, 104, 255),
    "rock_c": (184, 176, 166, 255),
    "foam": (220, 244, 244, 255),
    # props
    "trunk": (122, 79, 45, 255),
    "trunk_b": (99, 62, 34, 255),
    "leaf_a": (63, 125, 58, 255),
    "leaf_b": (84, 153, 74, 255),
    "leaf_c": (52, 104, 48, 255),
    "bush_a": (79, 143, 69, 255),
    "bush_b": (63, 118, 55, 255),
    "flame_a": (242, 161, 60, 255),
    "flame_b": (232, 99, 44, 255),
    "flame_c": (250, 214, 120, 255),
    "cloth": (217, 164, 91, 255),
    "cloth_b": (196, 141, 70, 255),
    "awning": (217, 99, 74, 255),
    "awning_b": (190, 76, 56, 255),
    "stone": (141, 133, 123, 255),
    "stone_b": (117, 108, 99, 255),
    "lighthouse_w": (240, 236, 226, 255),
    "lighthouse_r": (204, 84, 66, 255),
    "lantern": (250, 220, 110, 255),
    "berry": (196, 74, 92, 255),
    "berry_b": (222, 106, 122, 255),
    "fiber": (168, 186, 122, 255),
    "fiber_b": (146, 164, 100, 255),
    "fish_a": (150, 190, 208, 255),
    "fish_b": (110, 150, 175, 255),
    "metal": (168, 176, 188, 255),
    "metal_b": (132, 140, 155, 255),
    "wood": (158, 116, 71, 255),
    "wood_b": (133, 94, 55, 255),
    "shell": (244, 224, 208, 255),
    "shell_b": (219, 190, 172, 255),
    "water_can": (126, 168, 190, 255),
    "ring": (255, 214, 74, 255),
    "shadow": (20, 14, 8, 70),
}


def stable_noise(x: int, y: int, salt: str) -> int:
    """Deterministic per-pixel hash noise (presentation-only decoration)."""
    h = hashlib.sha256(("%s|%d|%d" % (salt, x, y)).encode()).digest()
    return h[0]


def new_img(w: int, h: int) -> Image.Image:
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def paste_tile(atlas: Image.Image, cell: tuple, painter) -> None:
    cx, cy = cell
    tile = new_img(TILE, TILE)
    painter(tile, ImageDraw.Draw(tile))
    atlas.alpha_composite(tile, (cx * TILE, cy * TILE))


def fill(draw: ImageDraw.ImageDraw, color) -> None:
    draw.rectangle([0, 0, TILE - 1, TILE - 1], fill=PAL[color])


def speckle(img: Image.Image, colors: list, salt: str, density: int = 40) -> None:
    px = img.load()
    for y in range(TILE):
        for x in range(TILE):
            if stable_noise(x, y, salt) < density:
                px[x, y] = PAL[colors[stable_noise(x, y, salt + "c") % len(colors)]]


# ---------------------------------------------------------------------------
# terrain atlas 8 x 3
# ---------------------------------------------------------------------------

def gen_terrain_atlas() -> None:
    atlas = new_img(TILE * 8, TILE * 3)

    def grass(img, d):
        fill(d, "grass_a")
        speckle(img, ["grass_b", "grass_c"], "grass")

    def grass_b2(img, d):
        fill(d, "grass_b")
        speckle(img, ["grass_a", "grass_c"], "grass2")

    def sand(img, d):
        fill(d, "sand_a")
        speckle(img, ["sand_b", "sand_c"], "sand")

    def sand_b2(img, d):
        fill(d, "sand_b")
        speckle(img, ["sand_a", "sand_c"], "sand2")

    def dirt(img, d):
        fill(d, "dirt")
        speckle(img, ["dirt_b", "path"], "dirt")

    def path(img, d):
        fill(d, "path")
        speckle(img, ["dirt", "sand_a"], "path")

    def forest(img, d):
        fill(d, "forest_a")
        speckle(img, ["forest_b", "grass_a"], "forest")

    def forest_b2(img, d):
        fill(d, "forest_b")
        speckle(img, ["forest_a", "grass_b"], "forest2")

    def shallow(img, d):
        fill(d, "shallow_a")
        for y in range(TILE):
            for x in range(TILE):
                if stable_noise(x, y, "shal") < 14:
                    img.load()[x, y] = PAL["shallow_b"] if (x + y) % 2 else PAL["foam"]

    def shallow_b2(img, d):
        fill(d, "shallow_b")
        for y in range(TILE):
            for x in range(TILE):
                if stable_noise(x, y, "shal2") < 12:
                    img.load()[x, y] = PAL["foam"]

    def deep(img, d):
        fill(d, "deep_a")
        for y in range(TILE):
            for x in range(TILE):
                if stable_noise(x, y, "deep") < 10:
                    img.load()[x, y] = PAL["deep_b"]

    def deep_b2(img, d):
        fill(d, "deep_b")
        for y in range(TILE):
            for x in range(TILE):
                if stable_noise(x, y, "deep2") < 10:
                    img.load()[x, y] = PAL["deep_a"]

    def rock_ground(img, d):
        fill(d, "rock_a")
        speckle(img, ["rock_b", "rock_c"], "rockg")

    def rock_ground_b2(img, d):
        fill(d, "rock_b")
        speckle(img, ["rock_a", "rock_c"], "rockg2")

    def cliff(img, d):
        # top face lighter, straight dark edge at bottom = cliff lip
        d.rectangle([0, 0, TILE - 1, 9], fill=PAL["rock_c"])
        d.rectangle([0, 10, TILE - 1, TILE - 1], fill=PAL["rock_b"])
        for x in range(0, TILE, 4):
            d.line([(x, 10), (x, TILE - 1)], fill=PAL["outline"])
        d.line([(0, 10), (TILE - 1, 10)], fill=PAL["outline"])
        speckle(img, ["rock_a"], "cliff")

    def gravel(img, d):
        fill(d, "rock_b")
        for i in range(8):
            x = stable_noise(i, 1, "gr") % (TILE - 3)
            y = stable_noise(i, 2, "gr") % (TILE - 3)
            d.rectangle([x, y, x + 2, y + 1], fill=PAL["rock_c"])

    def foam_edge(img, d):
        # shallow water with a foam crest along the top edge
        shallow(img, d)
        d.line([(0, 1), (TILE - 1, 1)], fill=PAL["foam"])
        d.line([(0, 3), (TILE - 1, 3)], fill=PAL["foam"])

    def farmland(img, d):
        # 翻好的耕地：土垄行
        fill(d, "dirt")
        for y in range(1, TILE, 4):
            d.line([(1, y), (TILE - 2, y)], fill=PAL["dirt_b"])
            d.line([(1, y + 1), (TILE - 2, y + 1)], fill=PAL["wood_b"])

    def sand_grass_edge(img, d):
        # sand bleeding into grass (diagonal blend)
        sand(img, d)
        for y in range(TILE):
            for x in range(TILE):
                if x + y >= 22 and stable_noise(x, y, "sge") < 60:
                    img.load()[x, y] = PAL["grass_a"]

    cells = [
        (0, 0, grass), (1, 0, grass_b2), (2, 0, sand), (3, 0, sand_b2),
        (4, 0, dirt), (5, 0, path), (6, 0, forest), (7, 0, forest_b2),
        (0, 1, shallow), (1, 1, shallow_b2), (2, 1, deep), (3, 1, deep_b2),
        (4, 1, rock_ground), (5, 1, rock_ground_b2), (6, 1, cliff), (7, 1, gravel),
        (0, 2, foam_edge), (1, 2, sand_grass_edge), (2, 2, farmland),
    ]
    for cx, cy, painter in cells:
        paste_tile(atlas, (cx, cy), painter)
    atlas.save(os.path.join(OUT_ROOT, "tiles", "terrain_16.png"))


# ---------------------------------------------------------------------------
# npc sheet: 4 cols x 12 rows (16x16 frames)
# rows: 0-3 idle dn/up/lf/rt | 4-7 walk | 8-11 run
# ---------------------------------------------------------------------------
NPC_W = 10          # body width
SKIN = PAL["sand_c"]
SHIRT = (216, 216, 220, 255)   # near-white, tintable via modulate
PANTS = (74, 59, 42, 255)
HAIR = (58, 44, 30, 255)
EYE = (36, 26, 16, 255)


def draw_npc_frame(d: ImageDraw.ImageDraw, facing: str, pose: int, kind: str) -> None:
    """pose: frame index; kind: idle/walk/run."""
    bob = 1 if (kind == "idle" and pose == 1) else 0
    lean = 1 if kind == "run" else 0
    cx = 8
    top = 2 + bob
    # legs
    stride = {0: 0, 1: 1, 2: 0, 3: -1}[pose] if kind in ("walk", "run") else 0
    stride *= 2 if kind == "run" else 1
    leg_y = 12 + bob
    if facing in ("down", "up"):
        d.rectangle([cx - 3, leg_y, cx - 1, leg_y + 2], fill=PANTS)
        d.rectangle([cx + 1, leg_y, cx + 3, leg_y + 2], fill=PANTS)
        if stride != 0:
            d.rectangle([cx - 3 + stride, leg_y, cx - 1 + stride, leg_y + 2], fill=PANTS)
    else:
        d.rectangle([cx - 2, leg_y, cx + 1, leg_y + 2], fill=PANTS)
        d.rectangle([cx - 2 + stride, leg_y, cx + 1 + stride, leg_y + 2], fill=PANTS)
    # body
    body_top = 7 + bob - lean
    d.rectangle([cx - 4, body_top, cx + 4, 11 + bob], fill=SHIRT, outline=PAL["outline"])
    # arms
    arm_y = body_top + 1
    swing = -stride
    if facing in ("down", "up"):
        d.rectangle([cx - 5, arm_y + swing, cx - 5, arm_y + 2 + swing], fill=SHIRT)
        d.rectangle([cx + 5, arm_y - swing, cx + 5, arm_y + 2 - swing], fill=SHIRT)
    else:
        top_a = min(arm_y, arm_y + swing)
        bot_a = max(arm_y, arm_y + swing)
        d.rectangle([cx - 3, top_a, cx + 3, bot_a], fill=SHIRT)
    # head
    head_top = top
    d.rectangle([cx - 3, head_top, cx + 3, head_top + 4], fill=SKIN, outline=PAL["outline"])
    # hair / face
    if facing == "down":
        d.rectangle([cx - 3, head_top, cx + 3, head_top + 1], fill=HAIR)
        d.point((cx - 2, head_top + 2), fill=EYE)
        d.point((cx + 2, head_top + 2), fill=EYE)
    elif facing == "up":
        d.rectangle([cx - 3, head_top, cx + 3, head_top + 3], fill=HAIR)
    else:  # left / right
        d.rectangle([cx - 3, head_top, cx + 3, head_top + 1], fill=HAIR)
        eye_x = cx - 2 if facing == "left" else cx + 2
        d.point((eye_x, head_top + 2), fill=EYE)


def gen_npc_sheet() -> None:
    sheet = new_img(TILE * 4, TILE * 12)
    facings = ["down", "up", "left", "right"]
    kinds = ["idle", "walk", "run"]
    frames = {"idle": 2, "walk": 4, "run": 4}
    row = 0
    for kind in kinds:
        for facing in facings:
            for f in range(frames[kind]):
                cell = new_img(TILE, TILE)
                draw_npc_frame(ImageDraw.Draw(cell), facing, f, kind)
                sheet.alpha_composite(cell, (f * TILE, row * TILE))
            row += 1
    sheet.save(os.path.join(OUT_ROOT, "npc", "npc_sheet_16.png"))


# ---------------------------------------------------------------------------
# props
# ---------------------------------------------------------------------------
def gen_props() -> None:
    def tree(img: Image.Image, d: ImageDraw.ImageDraw) -> None:
        # 16x24: canopy + trunk, anchor bottom
        d.rectangle([6, 18, 9, 23], fill=PAL["trunk"], outline=PAL["outline"])
        d.rectangle([6, 18, 9, 23], fill=PAL["trunk"])
        d.rectangle([5, 20, 10, 23], fill=PAL["trunk_b"])
        d.ellipse([1, 0, 14, 15], fill=PAL["leaf_a"], outline=PAL["outline"])
        d.ellipse([3, 2, 9, 8], fill=PAL["leaf_b"])
        d.ellipse([8, 7, 13, 13], fill=PAL["leaf_c"])
        d.point((4, 12), fill=PAL["leaf_c"])

    def stump(img, d):
        d.rectangle([4, 8, 11, 14], fill=PAL["trunk_b"], outline=PAL["outline"])
        d.ellipse([4, 5, 11, 10], fill=PAL["trunk"], outline=PAL["outline"])
        d.ellipse([6, 6, 9, 9], fill=PAL["wood_b"])

    def rock(img, d):
        d.ellipse([2, 5, 13, 14], fill=PAL["stone"], outline=PAL["outline"])
        d.ellipse([4, 6, 8, 9], fill=PAL["rock_c"])
        d.ellipse([8, 9, 12, 13], fill=PAL["stone_b"])

    def bush(img, d):
        d.ellipse([1, 6, 14, 15], fill=PAL["bush_a"], outline=PAL["outline"])
        d.ellipse([3, 8, 7, 12], fill=PAL["bush_b"])
        d.ellipse([8, 7, 12, 11], fill=PAL["bush_b"])

    def berry_bush(img, d):
        bush(img, d)
        for (x, y) in [(4, 9), (9, 8), (11, 11), (6, 12)]:
            d.ellipse([x, y, x + 1, y + 1], fill=PAL["berry"])
            d.point((x, y), fill=PAL["berry_b"])

    def campfire(img, d):
        d.rectangle([3, 12, 12, 13], fill=PAL["trunk"], outline=PAL["outline"])
        d.rectangle([5, 11, 10, 11], fill=PAL["trunk_b"])
        d.polygon([(4, 11), (8, 2), (12, 11)], fill=PAL["flame_b"], outline=PAL["outline"])
        d.polygon([(6, 11), (8, 5), (10, 11)], fill=PAL["flame_a"])
        d.point((8, 6), fill=PAL["flame_c"])

    def tent(img, d):
        d.polygon([(8, 2), (1, 14), (15, 14)], fill=PAL["cloth"], outline=PAL["outline"])
        d.polygon([(8, 2), (8, 14), (15, 14)], fill=PAL["cloth_b"])
        d.rectangle([6, 9, 9, 14], fill=PAL["outline"])
        d.rectangle([7, 10, 8, 14], fill=PAL["trunk_b"])

    def market_stall(img, d):
        d.rectangle([1, 9, 14, 10], fill=PAL["wood_b"], outline=PAL["outline"])
        d.rectangle([2, 11, 3, 14], fill=PAL["trunk_b"])
        d.rectangle([12, 11, 13, 14], fill=PAL["trunk_b"])
        for i in range(4):
            c = PAL["awning"] if i % 2 == 0 else PAL["awning_b"]
            d.rectangle([1 + i * 3.5, 4, 4.5 + i * 3.5, 9], fill=c, outline=PAL["outline"])
        d.rectangle([1, 3, 14, 4], fill=PAL["wood"], outline=PAL["outline"])
        d.ellipse([5, 9, 7, 11], fill=PAL["berry"])
        d.ellipse([9, 9, 11, 11], fill=PAL["shell"])

    def lighthouse(img: Image.Image, d: ImageDraw.ImageDraw) -> None:
        # 16x24 striped tower + lantern
        d.polygon([(6, 2), (10, 2), (9, 20), (7, 20)], fill=PAL["lighthouse_w"], outline=PAL["outline"])
        for band_y in (5, 10, 15):
            d.rectangle([6 + (band_y // 5 > 2), band_y, 10 - (band_y // 5 > 2), band_y + 2], fill=PAL["lighthouse_r"])
        d.rectangle([5, 0, 11, 3], fill=PAL["lighthouse_w"], outline=PAL["outline"])
        d.rectangle([7, 1, 9, 2], fill=PAL["lantern"])
        d.rectangle([4, 20, 12, 23], fill=PAL["stone_b"], outline=PAL["outline"])
        d.rectangle([5, 20, 11, 21], fill=PAL["stone"])

    def shell(img, d):
        d.polygon([(8, 3), (13, 13), (3, 13)], fill=PAL["shell"], outline=PAL["outline"])
        d.line([(8, 4), (5, 12)], fill=PAL["shell_b"])
        d.line([(8, 4), (11, 12)], fill=PAL["shell_b"])
        d.line([(8, 4), (8, 12)], fill=PAL["shell_b"])

    def driftwood(img, d):
        d.rectangle([2, 8, 13, 10], fill=PAL["wood"], outline=PAL["outline"])
        d.rectangle([11, 6, 13, 8], fill=PAL["wood_b"], outline=PAL["outline"])
        d.line([(4, 9), (10, 9)], fill=PAL["wood_b"])

    def poi_flag(img, d):
        # 轻量木指示牌：细杆 + 小牌（明确可穿过的 POI 标记，替代帐篷/木屋等阻挡感物件）
        d.rectangle([7, 4, 8, 14], fill=PAL["trunk_b"], outline=PAL["outline"])
        d.rectangle([3, 2, 12, 6], fill=PAL["wood"], outline=PAL["outline"])
        d.line([(4, 4), (11, 4)], fill=PAL["wood_b"])
        d.point((10, 3), fill=PAL["awning"])

    def tree_oak(img, d):
        # 16x24 阔叶树（正式命名树种的 oak 变体）
        d.rectangle([6, 18, 9, 23], fill=PAL["trunk"], outline=PAL["outline"])
        d.rectangle([5, 20, 10, 23], fill=PAL["trunk_b"])
        d.ellipse([1, 0, 14, 15], fill=PAL["leaf_a"], outline=PAL["outline"])
        d.ellipse([3, 2, 9, 8], fill=PAL["leaf_b"])
        d.ellipse([8, 7, 13, 13], fill=PAL["leaf_c"])
        d.point((4, 12), fill=PAL["leaf_c"])

    def tree_pine(img, d):
        # 16x24 松树：三层三角
        d.rectangle([7, 18, 9, 23], fill=PAL["trunk_b"], outline=PAL["outline"])
        for i, (y0, y1, half) in enumerate([(0, 7, 5), (5, 13, 6), (10, 19, 7)]):
            cx = 8
            d.polygon([(cx, y0), (cx - half, y1), (cx + half, y1)],
                      fill=PAL["leaf_c"] if i % 2 else PAL["leaf_a"], outline=PAL["outline"])

    def cabin(img: Image.Image, d: ImageDraw.ImageDraw) -> None:
        # 24x24 小木屋：坡顶 + 木墙 + 门
        d.rectangle([2, 10, 21, 22], fill=PAL["wood"], outline=PAL["outline"])
        for y in range(12, 22, 3):
            d.line([(2, y), (21, y)], fill=PAL["wood_b"])
        d.polygon([(0, 11), (12, 2), (23, 11)], fill=PAL["trunk"], outline=PAL["outline"])
        d.line([(3, 9), (20, 9)], fill=PAL["trunk_b"])
        d.rectangle([10, 14, 14, 22], fill=PAL["trunk_b"], outline=PAL["outline"])
        d.point((11, 18), fill=PAL["lantern"])

    def crate(img, d):
        d.rectangle([3, 5, 12, 14], fill=PAL["wood"], outline=PAL["outline"])
        d.line([(3, 5), (12, 14)], fill=PAL["wood_b"])
        d.line([(12, 5), (3, 14)], fill=PAL["wood_b"])
        d.rectangle([3, 5, 12, 7], fill=PAL["wood_b"])

    def barrel(img, d):
        d.rectangle([4, 4, 11, 14], fill=PAL["wood"], outline=PAL["outline"])
        for y in (6, 10):
            d.line([(4, y), (11, y)], fill=PAL["metal_b"])
        d.line([(6, 4), (6, 14)], fill=PAL["wood_b"])
        d.line([(9, 4), (9, 14)], fill=PAL["wood_b"])

    def chest(img, d):
        d.rectangle([3, 6, 12, 14], fill=PAL["trunk"], outline=PAL["outline"])
        d.rectangle([3, 6, 12, 9], fill=PAL["awning_b"])
        d.rectangle([7, 8, 9, 11], fill=PAL["metal"], outline=PAL["outline"])

    def fence_h(img, d):
        d.line([(1, 6), (14, 6)], fill=PAL["wood"], width=2)
        d.line([(1, 11), (14, 11)], fill=PAL["wood_b"], width=2)
        d.rectangle([2, 4, 3, 13], fill=PAL["wood"], outline=PAL["outline"])
        d.rectangle([12, 4, 13, 13], fill=PAL["wood"], outline=PAL["outline"])

    def fence_v(img, d):
        d.rectangle([6, 1, 7, 14], fill=PAL["wood"], outline=PAL["outline"])
        d.line([(3, 5), (12, 5)], fill=PAL["wood_b"], width=2)
        d.line([(3, 10), (12, 10)], fill=PAL["wood_b"], width=2)

    def well(img, d):
        d.ellipse([3, 8, 12, 14], fill=PAL["stone_b"], outline=PAL["outline"])
        d.ellipse([5, 9, 10, 12], fill=PAL["deep_a"], outline=PAL["outline"])
        d.rectangle([3, 2, 4, 9], fill=PAL["trunk"], outline=PAL["outline"])
        d.rectangle([11, 2, 12, 9], fill=PAL["trunk"], outline=PAL["outline"])
        d.polygon([(2, 3), (8, 0), (13, 3)], fill=PAL["cloth_b"], outline=PAL["outline"])

    def workbench(img, d):
        d.rectangle([2, 7, 13, 9], fill=PAL["wood"], outline=PAL["outline"])
        d.rectangle([3, 10, 5, 14], fill=PAL["trunk_b"])
        d.rectangle([10, 10, 12, 14], fill=PAL["trunk_b"])
        d.point((5, 6), fill=PAL["metal"])
        d.line([(9, 5), (11, 6)], fill=PAL["metal"], width=2)

    def machine(img, d):
        # 简易锯木台（工坊"机器"占位）
        d.rectangle([2, 8, 13, 14], fill=PAL["stone_b"], outline=PAL["outline"])
        d.rectangle([3, 9, 6, 11], fill=PAL["metal_b"])
        d.ellipse([8, 9, 12, 13], fill=PAL["metal"], outline=PAL["outline"])
        d.rectangle([1, 5, 14, 7], fill=PAL["wood"], outline=PAL["outline"])

    def sapling(img, d):
        d.rectangle([7, 11, 8, 14], fill=PAL["trunk_b"])
        d.ellipse([4, 5, 11, 12], fill=PAL["leaf_b"], outline=PAL["outline"])
        d.point((7, 8), fill=PAL["leaf_a"])

    def flower(img, d):
        d.line([(7, 9), (7, 14)], fill=PAL["fiber_b"], width=1)
        d.ellipse([5, 3, 9, 7], fill=PAL["berry_b"], outline=PAL["outline"])
        d.point((7, 5), fill=PAL["lantern"])
        d.line([(5, 12), (7, 10)], fill=PAL["fiber_b"])

    def weed(img, d):
        for x0 in (4, 7, 10):
            d.line([(x0, 14), (x0 - 1, 8)], fill=PAL["fiber"], width=1)
            d.line([(x0, 14), (x0 + 1, 9)], fill=PAL["fiber_b"], width=1)

    def rock_large(img, d):
        d.ellipse([1, 3, 14, 15], fill=PAL["stone"], outline=PAL["outline"])
        d.ellipse([3, 4, 8, 9], fill=PAL["rock_c"])
        d.ellipse([8, 8, 13, 14], fill=PAL["stone_b"])
        d.line([(2, 12), (13, 12)], fill=PAL["stone_b"])

    def log_pile(img, d):
        for i, y0 in enumerate((9, 6)):
            for x0 in range(3 + i, 12 - i, 4):
                d.ellipse([x0, y0, x0 + 3, y0 + 3], fill=PAL["wood"], outline=PAL["outline"])
                d.point((x0 + 1, y0 + 1), fill=PAL["wood_b"])

    def stone_pile(img, d):
        for (x0, y0, sz) in [(3, 8, 4), (8, 7, 5), (6, 10, 4)]:
            d.ellipse([x0, y0, x0 + sz, y0 + sz - 1], fill=PAL["stone"], outline=PAL["outline"])
        d.point((9, 8), fill=PAL["rock_c"])

    def crop_a(img, d):
        for x0 in (3, 7, 11):
            d.line([(x0, 14), (x0, 10)], fill=PAL["fiber_b"], width=1)
            d.point((x0, 9), fill=PAL["leaf_b"])

    def crop_b(img, d):
        for x0 in (3, 7, 11):
            d.line([(x0, 14), (x0, 8)], fill=PAL["fiber"], width=1)
            d.ellipse([x0 - 1, 5, x0 + 1, 8], fill=PAL["berry_b"], outline=PAL["outline"])

    out = os.path.join(OUT_ROOT, "props")
    for name, painter, size in [
        ("lighthouse", lighthouse, (16, 24)),
        ("stump", stump, (TILE, TILE)),
        ("rock", rock, (TILE, TILE)),
        ("bush", bush, (TILE, TILE)),
        ("berry_bush", berry_bush, (TILE, TILE)),
        ("campfire", campfire, (TILE, TILE)),
        ("tent", tent, (TILE, TILE)),
        ("market_stall", market_stall, (TILE, TILE)),
        ("shell", shell, (TILE, TILE)),
        ("driftwood", driftwood, (TILE, TILE)),
        ("poi_flag", poi_flag, (TILE, TILE)),
        ("tree_oak", tree_oak, (16, 24)),
        ("tree_pine", tree_pine, (16, 24)),
        ("cabin", cabin, (24, 24)),
        ("crate", crate, (TILE, TILE)),
        ("barrel", barrel, (TILE, TILE)),
        ("chest", chest, (TILE, TILE)),
        ("fence_h", fence_h, (TILE, TILE)),
        ("fence_v", fence_v, (TILE, TILE)),
        ("well", well, (TILE, TILE)),
        ("workbench", workbench, (TILE, TILE)),
        ("machine", machine, (TILE, TILE)),
        ("sapling", sapling, (TILE, TILE)),
        ("flower", flower, (TILE, TILE)),
        ("weed", weed, (TILE, TILE)),
        ("rock_large", rock_large, (TILE, TILE)),
        ("log_pile", log_pile, (TILE, TILE)),
        ("stone_pile", stone_pile, (TILE, TILE)),
        ("crop_a", crop_a, (TILE, TILE)),
        ("crop_b", crop_b, (TILE, TILE)),
    ]:
        img = new_img(*size)
        painter(img, ImageDraw.Draw(img))
        img.save(os.path.join(out, "%s.png" % name))


# ---------------------------------------------------------------------------
# item icons (16x16)
# ---------------------------------------------------------------------------
def gen_items() -> None:
    def wood_log(d):
        d.rectangle([2, 6, 13, 11], fill=PAL["wood"], outline=PAL["outline"])
        d.ellipse([11, 6, 15, 11], fill=PAL["wood_b"], outline=PAL["outline"])
        d.ellipse([12, 8, 14, 10], fill=PAL["wood"])
        d.line([(2, 8), (11, 8)], fill=PAL["wood_b"])

    def stick(d):
        d.line([(3, 12), (12, 4)], fill=PAL["trunk"], width=2)
        d.line([(8, 8), (11, 10)], fill=PAL["trunk_b"])

    def stone(d):
        d.ellipse([3, 5, 12, 13], fill=PAL["stone"], outline=PAL["outline"])
        d.ellipse([5, 6, 8, 9], fill=PAL["rock_c"])

    def shell_icon(d):
        d.polygon([(8, 3), (13, 13), (3, 13)], fill=PAL["shell"], outline=PAL["outline"])
        d.line([(8, 5), (6, 12)], fill=PAL["shell_b"])
        d.line([(8, 5), (10, 12)], fill=PAL["shell_b"])

    def berries(d):
        for (x, y) in [(4, 8), (8, 6), (11, 9)]:
            d.ellipse([x, y, x + 3, y + 3], fill=PAL["berry"], outline=PAL["outline"])
            d.point((x + 1, y + 1), fill=PAL["berry_b"])
        d.line([(6, 4), (9, 3)], fill=PAL["leaf_a"], width=2)

    def fiber(d):
        for i, x0 in enumerate((3, 7, 11)):
            d.arc([x0, 4, x0 + 4, 13], 90, 270, fill=PAL["fiber"] if i % 2 else PAL["fiber_b"], width=2)

    def fish(d):
        d.ellipse([3, 6, 11, 11], fill=PAL["fish_a"], outline=PAL["outline"])
        d.polygon([(10, 8), (14, 5), (14, 12)], fill=PAL["fish_b"], outline=PAL["outline"])
        d.point((5, 8), fill=PAL["outline"])

    def trap(d):
        d.rectangle([3, 7, 12, 12], outline=PAL["trunk"], width=2)
        for x in (5, 8, 11):
            d.line([(x, 7), (x, 12)], fill=PAL["trunk_b"])
        d.line([(3, 7), (12, 12)], fill=PAL["trunk_b"])

    def axe(d):
        d.line([(4, 13), (11, 4)], fill=PAL["trunk"], width=2)
        d.polygon([(9, 2), (13, 6), (10, 8)], fill=PAL["metal"], outline=PAL["outline"])

    def pickaxe(d):
        d.line([(4, 13), (11, 5)], fill=PAL["trunk"], width=2)
        d.arc([3, 1, 13, 10], 200, 340, fill=PAL["metal"], width=2)

    def hoe(d):
        d.line([(4, 13), (11, 4)], fill=PAL["trunk"], width=2)
        d.line([(8, 3), (13, 6)], fill=PAL["metal"], width=2)

    def watering_can(d):
        d.rectangle([4, 6, 10, 12], fill=PAL["water_can"], outline=PAL["outline"])
        d.line([(10, 8), (14, 6)], fill=PAL["water_can"], width=2)
        d.arc([2, 4, 7, 9], 60, 200, fill=PAL["water_can"], width=2)

    def fishing_rod(d):
        d.line([(3, 13), (12, 3)], fill=PAL["trunk"], width=2)
        d.line([(12, 3), (10, 10)], fill=PAL["outline"])
        d.ellipse([9, 10, 11, 12], outline=PAL["metal"], width=1)

    def campfire_icon(d):
        d.rectangle([3, 12, 12, 13], fill=PAL["trunk"])
        d.polygon([(4, 11), (8, 2), (12, 11)], fill=PAL["flame_b"])
        d.polygon([(6, 11), (8, 5), (10, 11)], fill=PAL["flame_a"])

    out = os.path.join(OUT_ROOT, "items")
    icons = {
        "wood_log": wood_log, "stick": stick, "stone": stone, "shell": shell_icon,
        "berries": berries, "fiber": fiber, "fish": fish, "trap": trap,
        "axe": axe, "pickaxe": pickaxe, "hoe": hoe, "watering_can": watering_can,
        "fishing_rod": fishing_rod, "campfire": campfire_icon,
    }
    for name, painter in icons.items():
        img = new_img(TILE, TILE)
        painter(ImageDraw.Draw(img))
        img.save(os.path.join(out, "%s.png" % name))


# ---------------------------------------------------------------------------
# markers
# ---------------------------------------------------------------------------
def gen_markers() -> None:
    ring = new_img(TILE, TILE)
    d = ImageDraw.Draw(ring)
    c = PAL["ring"]
    for (x0, y0, x1, y1) in [(1, 1, 5, 1), (1, 1, 1, 5), (10, 1, 14, 1), (14, 1, 14, 5),
                             (1, 10, 1, 14), (1, 14, 5, 14), (14, 10, 14, 14), (10, 14, 14, 14)]:
        d.rectangle([x0, y0, x1, y1], fill=c)
    ring.save(os.path.join(OUT_ROOT, "markers", "selection_ring.png"))

    shadow = new_img(10, 5)
    sd = ImageDraw.Draw(shadow)
    sd.ellipse([0, 0, 9, 4], fill=PAL["shadow"])
    shadow.save(os.path.join(OUT_ROOT, "markers", "shadow.png"))


def main() -> None:
    for sub in ("tiles", "npc", "props", "items", "markers"):
        os.makedirs(os.path.join(OUT_ROOT, sub), exist_ok=True)
    gen_terrain_atlas()
    gen_npc_sheet()
    gen_props()
    gen_items()
    gen_markers()
    print("generated placeholder pixel assets under", OUT_ROOT)


if __name__ == "__main__":
    main()
