# clawd-mascot

Two ways to put a tiny animated **Clawd** in your Claude Code CLI, both driven by the same "is Claude working?" signal:

| Mode | Where it lives | Overlaps the terminal? |
|---|---|---|
| **Statusline mascot** | Claude Code status line (bottom bar) | No — it has its own row, never touches your text |
| **Overlay crab** (macOS) | A tiny transparent window floating **on top of** the terminal | Yes — exactly like the video: it sits over the UI, and clicks/typing pass straight through it |

Both animate **while Claude is generating** (walk ⚽ football 🚩 flag 👀 look-around) and stand still, blinking, when Claude is idle.

## Why two modes (the honest answer)

A terminal is a character grid — a program can't draw *on top of* Claude Code's chat text without overwriting it. So true overlap (the black-mark spot in your screenshot) is done with a separate **click-through overlay window**, not terminal output. Inside the terminal itself, the supported place for custom visuals is the **statusline**. This repo gives you both.

## Install

```bash
chmod +x install.sh
./install.sh
```

Then restart Claude Code. The installer:

- copies `clawd_statusline.py` to `~/.claude/` and configures `statusLine` (with `refreshInterval: 1` — units are seconds — so the animation ticks ~1 fps even mid-generation)
- compiles `clawd_overlay.swift` to `~/.claude/bin/clawd-overlay` (macOS + Xcode command line tools; skipped gracefully otherwise)
- **appends** three tiny hooks (`UserPromptSubmit` → `working`, `Stop`/`SessionEnd` → `idle`) that write `~/.claude/clawd_state` — your existing hooks are untouched, and `settings.json` is backed up first

## The overlay crab (the video thing)

```bash
~/.claude/bin/clawd-overlay &                 # bottom-right of screen
```

Options:

```
--corner tr|tl|br|bl   which screen corner (default br)
--margin-x N           horizontal margin in pt (default 40)
--margin-y N           vertical margin in pt (default 90, clears the input box)
--x N --y N            exact position (origin = bottom-left of screen)
--scale N              pixel size: 2 = small, 3 = default, 4 = chunky
--lane N               how wide an area he walks, in pixels (default 40)
--always               animate even when Claude is idle
--state PATH           state file to watch (default ~/.claude/clawd_state)
```

- Always on top of the terminal, **below** the menu bar, visible in every Space and over fullscreen apps.
- **Click-through**: it never steals a click or a keystroke.
- No permissions, no Dock icon, ~0% CPU.
- Stop: `pkill -f clawd-overlay`. Survive terminal close: `nohup ~/.claude/bin/clawd-overlay >/dev/null 2>&1 & disown`

## The statusline mascot

Shows `✻ <model> · ctx N%` on the left and the animation against the right edge:

```
  ✻ Opus 4.8 · ctx 18%                                [tiny animated Clawd]
```

Preview without Claude Code:

```bash
echo '{"model":{"display_name":"Opus 4.8"},"context_window":{"used_percentage":18}}' \
  | COLUMNS=$(tput cols) python3 clawd_statusline.py
```

(`COLUMNS` matters: Claude Code sets it for the statusline command; without it the art can't right-align.)

## How working/idle detection works

Hooks write a one-word state file:

- `UserPromptSubmit` → `working` (you sent a prompt, Claude is on it)
- `Stop` / `SessionEnd` → `idle`

Both mascots read `~/.claude/clawd_state`. No file → statusline animates always, overlay idles (use `--always`). A `working` older than 2 h is treated as stale (crash guard). Note: with multiple Claude Code sessions running at once, the last event wins.

## Customize

- `ORANGE = (217, 119, 87)` — mascot color (both files)
- `ACTION_SECS` — how often the action changes
- Each action is a small function (`act_walk`, `act_football`, `act_flag`, `act_look`) — copy one, add it to `ACTIONS`. Same idea in Swift (`buildScene`).

## Uninstall

- Remove the `statusLine` block and the three `clawd_state` hook entries from `~/.claude/settings.json` (or restore the backup the installer made)
- `rm ~/.claude/clawd_statusline.py ~/.claude/bin/clawd-overlay ~/.claude/clawd_state`
- `pkill -f clawd-overlay`

## Notes

- Statusline requires the workspace **trust prompt** to be accepted (same rule as hooks).
- If the status line goes blank, run the preview command above to surface errors.
- Truecolor ANSI is used for the statusline art — every modern terminal (Terminal.app, iTerm2, Ghostty, kitty, WezTerm) supports it.
- Windows/Linux: statusline mascot works anywhere Python 3 does; the overlay is macOS-only.
# terminal-claude-mascot
