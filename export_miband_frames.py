#!/usr/bin/env python3
import os
import math
from PIL import Image

SPRITE_W = 12
SPRITE_H = 8

# Colors in RGBA format (transparent background is crucial for watchfaces!)
COLORS = {
    "O": (217, 119, 87, 255),    # orange
    "D": (30, 30, 30, 255),      # dark
    "W": (235, 235, 235, 255),   # white
    "P": (150, 150, 150, 255),   # grey
    "F": (217, 119, 87, 255),    # orange
    "Y": (245, 200, 80, 255),    # yellow
    "B": (100, 180, 240, 255),   # blue
    "G": (120, 210, 120, 255),   # green
    "R": (235, 60, 60, 255),     # red
    ".": (0, 0, 0, 0)            # transparent
}

def crab_sprite(claw, legs, eyes):
    claw_rows = [
        [".C........C.",
         ".C........C."],
        ["CC........CC",
         ".C........C."]
    ]
    r0 = claw_rows[claw % 2][0].replace("C", "O")
    r1 = claw_rows[claw % 2][1].replace("C", "O")
    
    r2 = "..OOOOOOOO.."
    r3 = list("..OOOOOOOO..")
    if eyes == "closed":
        pass
    elif eyes == "left":
        r3[3] = "D"
        r3[7] = "D"
    elif eyes == "right":
        r3[4] = "D"
        r3[8] = "D"
    else: # open
        r3[4] = "D"
        r3[7] = "D"
    r3 = "".join(r3)
    r4 = ".OOOOOOOOOO."
    r5 = "..OOOOOOOO.."
    
    leg_rows = [
        ["..O.O..O.O..",
         "..O.O..O.O.."],
        [".O..O..O..O.",
         ".O..O..O..O."],
        ["..O..OO..O..",
         "..O..OO..O.."]
    ]
    l = leg_rows[legs % 3]
    return [r0, r1, r2, r3, r4, r5, l[0], l[1]]

class Scene:
    def __init__(self, lane):
        self.lane = lane
        self.grid = [["."] * lane for _ in range(SPRITE_H)]
        
    def place(self, sprite, x):
        for r, row in enumerate(sprite):
            for c, ch in enumerate(row):
                if ch != ".":
                    col = x + c
                    if 0 <= col < self.lane:
                        self.grid[r][col] = ch
                        
    def put(self, r, c, ch):
        if 0 <= r < SPRITE_H and 0 <= c < self.lane:
            self.grid[r][c] = ch

def build_scene(action, frame, lane):
    s = Scene(lane)
    
    if action == "walk":
        span = max(lane - SPRITE_W, 1)
        pos = frame % (2 * span)
        x = pos if pos < span else 2 * span - pos
        eyes = "right" if pos < span else "left"
        step = frame % 4
        hop_y = 1 if (step == 1 or step == 2) else 0
        if hop_y > 0:
            shifted = Scene(lane)
            shifted.place(crab_sprite(frame % 2, frame, eyes), x)
            for r in range(SPRITE_H):
                target_r = r - hop_y
                if 0 <= target_r < SPRITE_H:
                    s.grid[target_r] = shifted.grid[r]
        else:
            s.place(crab_sprite(frame % 2, frame, eyes), x)
            
    elif action == "football":
        cycle = frame % 16
        if cycle < 4:
            s.place(crab_sprite(0, cycle, "right"), cycle)
            s.put(SPRITE_H - 1, cycle + SPRITE_W + 2, "W")
        elif cycle == 4:
            s.place(crab_sprite(1, 2, "right"), 4)
            s.put(SPRITE_H - 1, 4 + SPRITE_W + 2, "W")
        elif cycle <= 7:
            s.place(crab_sprite(0, 0, "right"), 4)
            bx = 4 + SPRITE_W + 2 + (cycle - 4) * 2
            by = SPRITE_H - 1 - (cycle - 4)
            s.put(max(by, 0), bx, "W")
        else:
            s.place(crab_sprite(0, 0, "right"), 4)
            s.put(SPRITE_H - 1, 4 + SPRITE_W + 2 + (cycle - 4), "W")
            
    elif action == "flag":
        x = 4
        s.place(crab_sprite(0, 0, "open"), x)
        pole = x + SPRITE_W + 1
        for r in range(SPRITE_H):
            s.put(r, pole, "P")
        wave = frame % 2
        for r in range(3):
            for c in range(1, 4):
                use_white = ((r + c + wave) % 2 == 0)
                s.put(r, pole + c, "W" if use_white else "D")
                
    elif action == "look":
        seq = ["open", "open", "right", "right", "open", "left", "left", "open"]
        eyes = "closed" if (frame % 11 == 7) else seq[frame % len(seq)]
        s.place(crab_sprite((frame // 4) % 2, 0, eyes), (lane - SPRITE_W) // 2)
        
    elif action == "dumbbell":
        cycle = frame % 16
        x = (lane - SPRITE_W) // 2
        if cycle < 4:
            db_y, claw = 4, 1
        elif cycle < 6:
            db_y, claw = 2, 0
        elif cycle < 10:
            db_y, claw = 0, 0
            x += -1 if (cycle % 2 == 0) else 1
        elif cycle < 12:
            db_y, claw = 2, 0
        else:
            db_y, claw = 4, 1
            
        s.place(crab_sprite(claw, 0, "open"), x)
        # Left dumbbell
        lx = x - 2
        s.put(db_y, lx, "W")
        s.put(db_y, lx + 1, "P")
        s.put(db_y, lx + 2, "W")
        s.put(db_y + 1, lx, "W")
        s.put(db_y + 1, lx + 2, "W")
        # Right dumbbell
        rx = x + SPRITE_W
        s.put(db_y, rx, "W")
        s.put(db_y, rx + 1, "P")
        s.put(db_y, rx + 2, "W")
        s.put(db_y + 1, rx, "W")
        s.put(db_y + 1, rx + 2, "W")
        
    elif action == "confetti":
        jump_y_seq = [0, 0, 1, 1, 2, 2, 1, 1]
        jump_y = jump_y_seq[(frame // 2) % len(jump_y_seq)]
        x = (lane - SPRITE_W) // 2
        if jump_y > 0:
            shifted = Scene(lane)
            shifted.place(crab_sprite(frame % 2, frame, "open"), x)
            for r in range(SPRITE_H):
                target_r = r - jump_y
                if 0 <= target_r < SPRITE_H:
                    s.grid[target_r] = shifted.grid[r]
        else:
            s.place(crab_sprite(frame % 2, frame, "open"), x)
            
        colors = ["Y", "B", "G", "W"]
        for p in range(5):
            start_x = p * (lane // 5)
            offset = int(math.sin((frame + p) * 0.7) * 2.0)
            px = (start_x + offset + lane) % lane
            py = (p * 5 + frame) % SPRITE_H
            col = colors[(p + frame) % len(colors)]
            if s.grid[py][px] == ".":
                s.grid[py][px] = col
                
    elif action == "ninja":
        cycle = frame % 16
        x = (lane - SPRITE_W) // 2
        if cycle < 4:
            jump_y, kick, bow = 0, False, False
        elif cycle < 6:
            jump_y, kick, bow = 1, False, False
        elif cycle < 11:
            jump_y, kick, bow = 2, True, False
        elif cycle < 13:
            jump_y, kick, bow = 1, False, False
        else:
            jump_y, kick, bow = 0, False, True
            
        claw = 1 if kick else 0
        legs = 2 if kick else (0 if bow else 1)
        vertical_shift = jump_y - (1 if bow else 0)
        
        if vertical_shift != 0:
            shifted = Scene(lane)
            shifted.place(crab_sprite(claw, legs, "right"), x)
            for r in range(SPRITE_H):
                target_r = r - vertical_shift
                if 0 <= target_r < SPRITE_H:
                    s.grid[target_r] = shifted.grid[r]
        else:
            s.place(crab_sprite(claw, legs, "right"), x)
            
        # Red headband
        head_r = 2 - vertical_shift
        if 0 <= head_r < SPRITE_H:
            for c in range(2, 10):
                s.put(head_r, x + c, "R")
            tail_wave = frame % 2
            if tail_wave == 0:
                s.put(head_r, x - 1, "R")
                s.put(head_r + 1, x - 2, "R")
            else:
                s.put(head_r + 1, x - 1, "R")
                s.put(head_r, x - 2, "R")
                
        # Flying kick leg
        if kick:
            kick_r = 6 - vertical_shift
            if 0 <= kick_r < SPRITE_H:
                s.put(kick_r, x + SPRITE_W, "O")
                s.put(kick_r, x + SPRITE_W + 1, "O")
                
        # Shuriken
        if cycle >= 6:
            shx = x + SPRITE_W + 2 + (cycle - 6) * 3
            if shx < lane:
                shy = 3 - vertical_shift
                if cycle % 2 == 0:
                    s.put(shy, shx, "D")
                    s.put(shy + 1, shx + 1, "D")
                else:
                    s.put(shy, shx + 1, "D")
                    s.put(shy + 1, shx, "D")
                    
    return s

def export_frames(action, lane=26, scale=4, frames_count=16):
    os.makedirs(f"miband_export/{action}", exist_ok=True)
    for f in range(frames_count):
        s = build_scene(action, f, lane)
        # Create image
        img = Image.new("RGBA", (lane * scale, SPRITE_H * scale), (0, 0, 0, 0))
        pixels = img.load()
        for gy in range(SPRITE_H):
            for gx in range(lane):
                ch = s.grid[gy][gx]
                color = COLORS[ch]
                # Fill upscaled block
                for sy in range(scale):
                    for sx in range(scale):
                        pixels[gx * scale + sx, gy * scale + sy] = color
                        
        img.save(f"miband_export/{action}/{action}_{f:02d}.png")
    print(f"Exported {frames_count} frames for '{action}' animation to miband_export/{action}/")

if __name__ == "__main__":
    actions = ["walk", "football", "flag", "look", "dumbbell", "confetti", "ninja"]
    # We export walk with a wider lane so he has room to walk!
    for act in actions:
        # Give them some extra space or keep it standard
        lane = 28 if act in ["walk", "football"] else 20
        export_frames(act, lane=lane, scale=4, frames_count=16)
