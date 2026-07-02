#!/usr/bin/env python3
"""
Clawd statusline for Claude Code.

A pixel-art Clawd mascot in Anthropic orange that lives in the
Claude Code status line and plays different actions while Claude is
working: walking, kicking a football, waving a flag, blinking and
looking around. When Claude is idle, Clawd stands still and blinks.

How it animates: Claude Code re-runs the statusline command after each
assistant message and, with "refreshInterval": 1 in the statusLine
config (units: seconds), once a second on a timer. Each run picks a
frame from the wall clock, so successive runs produce successive frames.

How it knows Claude is working: hooks (installed by install.sh) write
"working" to ~/.claude/clawd_state on UserPromptSubmit and "idle" on
Stop / SessionEnd. No state file -> always animate.

Rendering: 6-pixel-tall sprite packed into 3 terminal lines using the
half-block character ▀ (foreground = top pixel, background = bottom
pixel). Terminal width comes from the COLUMNS env var, which Claude
Code sets before running the script (stdout is a pipe here, so
os.get_terminal_size() would lie).

Install (in ~/.claude/settings.json):
  "statusLine": { "type": "command",
                  "command": "python3 ~/.claude/clawd_statusline.py",
                  "padding": 0,
                  "refreshInterval": 1 }
"""

import json
import math
import os
import sys
import time

# ---------------------------------------------------------------- colors
ORANGE = (217, 119, 87)    # Anthropic / Clawd orange #D97757
DARK   = (30, 30, 30)      # eyes
WHITE  = (235, 235, 235)   # football
FLAG_C = (217, 119, 87)    # flag cloth
POLE_C = (150, 150, 150)   # flag pole

O, D, W, F, P = ORANGE, DARK, WHITE, FLAG_C, POLE_C
_ = None

SPRITE_W = 10       # sprite width in pixels
SPRITE_H = 6        # sprite height in pixel rows (3 half-block lines)
LANE = 22           # playfield width in pixels (columns)
FRAME_SECS = 1.0    # matches the 1s refreshInterval
ACTION_SECS = 12    # switch to a new action every N seconds

STATE_FILE = os.path.expanduser("~/.claude/clawd_state")
STATE_MAX_AGE = 2 * 60 * 60   # ignore a "working" flag older than 2h


# ---------------------------------------------------------------- sprite
def clawd(eyes="open", legs=0, look=0):
    """Build a 10px-wide, 6-row Clawd sprite.

    Returns a list of 6 rows, each row is a list of color tuples or None.
    Row layout:
      0: head top
      1: eyes
      2: arms (wider body)
      3: body
      4: legs
      5: feet
    """
    row0 = [_, O, O, O, O, O, O, O, O, _]    # head top
    row1 = [_, O, O, O, O, O, O, O, O, _]    # eyes row (default closed)

    if eyes == "open":
        li = 2 + look
        ri = 7 + look
        li = max(1, min(li, 8))
        ri = max(1, min(ri, 8))
        row1[li] = D
        row1[ri] = D

    row2 = [O, O, O, O, O, O, O, O, O, O]    # arms (full width 10px)
    row3 = [_, O, O, O, O, O, O, O, O, _]    # body

    leg_variants = [
        # Standing: 3 leg pairs
        ([_, O, O, _, O, O, _, O, O, _],
         [_, O, O, _, O, O, _, O, O, _]),
        # Walk frame 1
        ([_, _, O, _, O, O, _, O, _, _],
         [_, _, O, _, O, O, _, O, _, _]),
        # Walk frame 2
        ([_, O, _, _, _, O, _, _, O, _],
         [_, O, _, _, _, O, _, _, O, _]),
    ]
    row4, row5 = leg_variants[legs % len(leg_variants)]

    return [list(r) for r in [row0, row1, row2, row3, row4, row5]]


# ---------------------------------------------------------------- grid ops
def place_sprite(grid, sprite, x):
    """Place sprite rows onto the grid at position x."""
    for r, row in enumerate(sprite):
        if r < len(grid):
            for c, color in enumerate(row):
                if color is not None and 0 <= x + c < LANE:
                    grid[r][x + c] = color


def put_pixel(grid, row, col, color):
    """Set a single pixel in the grid."""
    if 0 <= row < len(grid) and 0 <= col < LANE:
        grid[row][col] = color


# ---------------------------------------------------------------- actions
def act_walk(f, grid):
    """Walk right across the lane, turn around, walk back."""
    span = max(LANE - SPRITE_W, 1)
    pos = f % (2 * span)
    x = pos if pos < span else 2 * span - pos
    look = 1 if pos < span else -1
    place_sprite(grid, clawd(legs=f, look=look), x)


def act_football(f, grid):
    """Run up, kick, ball flies across the lane. Loops."""
    cycle = f % 16
    if cycle < 4:                               # run-up
        x = cycle
        place_sprite(grid, clawd(legs=cycle, look=1), x)
        put_pixel(grid, 5, x + SPRITE_W + 2, W)  # ball waiting on ground
    elif cycle == 4:                             # the kick
        place_sprite(grid, clawd(legs=2, look=1), 4)
        put_pixel(grid, 5, 4 + SPRITE_W + 2, W)
    elif cycle <= 7:                             # ball rising
        place_sprite(grid, clawd(legs=0, look=1), 4)
        ball_x = 4 + SPRITE_W + 2 + (cycle - 4) * 2
        ball_y = 5 - (cycle - 4)
        if ball_x < LANE:
            put_pixel(grid, max(ball_y, 0), ball_x, W)
    else:                                        # ball rolling away
        place_sprite(grid, clawd(legs=0, look=1), 4)
        ball_x = 4 + SPRITE_W + 2 + (cycle - 4)
        if ball_x < LANE:
            put_pixel(grid, 5, ball_x, W)


def act_flag(f, grid):
    """Stand and wave a flag beside the body."""
    x = 4
    place_sprite(grid, clawd(legs=0, look=0), x)
    pole_x = x + SPRITE_W + 1
    if pole_x < LANE:
        # Pole runs from row 1 to row 5
        for r in range(1, 6):
            put_pixel(grid, r, pole_x, P)
        # Flag cloth at top of pole
        wave = f % 3
        put_pixel(grid, 0, pole_x, P)
        put_pixel(grid, 0, pole_x + 1, F)
        put_pixel(grid, 1, pole_x + 1, F)
        if wave != 1 and pole_x + 2 < LANE:
            put_pixel(grid, 0, pole_x + 2, F)


def act_look(f, grid):
    """Idle personality: look left, right, blink."""
    x = 6
    seq = [0, 0, 1, 1, 0, -1, -1, 0]
    look = seq[f % len(seq)]
    eyes = "closed" if f % 11 == 7 else "open"
    place_sprite(grid, clawd(eyes=eyes, legs=0, look=look), x)


def act_idle(f, grid):
    """Claude is idle: stand still, blink every now and then."""
    x = 6
    eyes = "closed" if f % 17 == 5 else "open"
    place_sprite(grid, clawd(eyes=eyes, legs=0, look=0), x)


ACTIONS = [act_walk, act_football, act_flag, act_look]


# ---------------------------------------------------------------- state
def claude_is_working():
    """True when the hook-maintained state file says Claude is generating.

    Missing/unreadable file (hooks not installed) -> True, so the mascot
    still animates like before.
    """
    try:
        with open(STATE_FILE) as fh:
            state = fh.read().strip()
        if state != "working":
            return False
        # Guard against a stale "working" left behind by a crash.
        return (time.time() - os.path.getmtime(STATE_FILE)) < STATE_MAX_AGE
    except (OSError, UnicodeDecodeError):
        return True


# ---------------------------------------------------------------- render
def half_block(top_c, bot_c):
    """Encode two vertically stacked pixels into one character."""
    if top_c is None and bot_c is None:
        return " "
    if top_c is not None and bot_c is not None:
        r, g, b = top_c
        r2, g2, b2 = bot_c
        return f"\x1b[38;2;{r};{g};{b}m\x1b[48;2;{r2};{g2};{b2}m▀\x1b[0m"
    if top_c is not None:
        r, g, b = top_c
        return f"\x1b[38;2;{r};{g};{b}m▀\x1b[0m"
    r, g, b = bot_c
    return f"\x1b[38;2;{r};{g};{b}m▄\x1b[0m"


def render_lines(grid, width=LANE):
    """Pack pixel rows into half-block terminal lines (2 rows per line).

    Renders only the first `width` columns, so a very narrow terminal
    clips the art instead of overflowing/wrapping.
    """
    width = max(0, min(width, LANE))
    lines = []
    for pair in range(0, len(grid), 2):
        top_row = grid[pair] if pair < len(grid) else [None] * LANE
        bot_row = grid[pair + 1] if pair + 1 < len(grid) else [None] * LANE
        line = "".join(half_block(top_row[c], bot_row[c]) for c in range(width))
        lines.append(line)
    return lines


def terminal_columns():
    """Terminal width. Claude Code sets COLUMNS for the statusline command;
    stdout is a pipe, so os.get_terminal_size() is only a dev fallback."""
    try:
        cols = int(os.environ.get("COLUMNS", ""))
        if cols > 0:
            return cols
    except ValueError:
        pass
    try:
        return os.get_terminal_size().columns
    except OSError:
        return 80


# ---------------------------------------------------------------- main
def main():
    # Session data from Claude Code (may be absent when testing by hand)
    try:
        data = json.load(sys.stdin)
    except Exception:
        data = {}
    if not isinstance(data, dict):
        data = {}
    m = data.get("model")
    model = (m.get("display_name") if isinstance(m, dict) else None) or "Claude"
    cw = data.get("context_window")
    ctx = cw.get("used_percentage") if isinstance(cw, dict) else None
    ctx_txt = (f" · ctx {int(ctx)}%"
               if isinstance(ctx, (int, float)) and math.isfinite(ctx) else "")

    now = time.time()
    frame = int(now / FRAME_SECS)
    if claude_is_working():
        action = ACTIONS[int(now // ACTION_SECS) % len(ACTIONS)]
    else:
        action = act_idle

    grid = [[None] * LANE for _ in range(SPRITE_H)]
    action(frame, grid)

    cols = terminal_columns()

    dim, reset = "\x1b[2m", "\x1b[0m"
    text_label = f"✻ {model}{ctx_txt}"
    text_visible_len = len(text_label) + 2  # +2 for leading spaces

    # Three tiers so we never exceed `cols` (an overflow wraps ugly):
    #   wide   -> model/ctx label on the left, art on the right edge
    #   medium -> art only, right-aligned (label wouldn't fit)
    #   narrow -> art only, clipped to the terminal width
    if cols >= text_visible_len + LANE + 2:
        art_w, show_label = LANE, True
    elif cols >= LANE:
        art_w, show_label = LANE, False
    else:
        art_w, show_label = cols, False

    art_lines = render_lines(grid, art_w)

    try:
        for i, art_line in enumerate(art_lines):
            if show_label and i == 0:
                gap = max(cols - text_visible_len - art_w, 1)
                print(f"  {dim}{text_label}{reset}{' ' * gap}{art_line}")
            else:
                gap = max(cols - art_w, 0)
                print(f"{' ' * gap}{art_line}")
    except BrokenPipeError:
        pass


if __name__ == "__main__":
    main()
