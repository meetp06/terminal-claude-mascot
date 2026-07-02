// clawd_overlay.swift — a tiny Clawd crab that walks OVER your terminal.
//
// A borderless, transparent, always-on-top, click-through window that
// draws an animated pixel-art crab. Because it is its own window layer,
// it can overlap the terminal (or any app) without ever touching the
// text underneath — clicks and keystrokes pass straight through.
//
// It knows when Claude is working: hooks installed by install.sh write
// "working" to ~/.claude/clawd_state on UserPromptSubmit and "idle" on
// Stop / SessionEnd. "working" → Clawd walks / kicks / waves. Otherwise
// he stands and blinks.
//
// Build:  swiftc -O -swift-version 5 -o clawd-overlay clawd_overlay.swift
// Run:    ./clawd-overlay &
//
// Options:
//   --corner tr|tl|br|bl   screen corner to live in (default br)
//   --margin-x N           horizontal margin from that corner, pt (default 40)
//   --margin-y N           vertical margin, pt (default 90 — clears input box)
//   --x N --y N            absolute position (bottom-left origin), overrides corner
//   --scale N              pixel size in pt (default 3; 2 = smaller, 4 = bigger)
//   --lane N               walking lane width in pixels (default 40)
//   --always               animate even when Claude is idle
//   --state PATH           state file to watch (default ~/.claude/clawd_state)
//   --follow-claude        auto-quit ~15s after the last claude process exits
//                          (checks every 5s for a process named "claude")

import AppKit

// ---------------------------------------------------------------- config
struct Config {
    var corner = "br"
    var marginX: CGFloat = 40
    var marginY: CGFloat = 90
    var absX: CGFloat? = nil
    var absY: CGFloat? = nil
    var scale: CGFloat = 3
    var lane = 40
    var always = false
    var statePath = NSString(string: "~/.claude/clawd_state").expandingTildeInPath
    var followClaude = false
    var followName = "claude"   // process basename to follow (testing hook)
    var trackTerminal = false   // stick to the frontmost terminal window
    var followTerminal = false  // auto-quit when terminal application is quit
}

func parseArgs() -> Config {
    var c = Config()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let a = it.next() {
        // Finite-only parse: rejects NaN/inf and clamps to a sane range so
        // Int(...) can never trap on garbage CLI input.
        func num() -> CGFloat {
            let d = Double(it.next() ?? "") ?? 0
            return CGFloat(d.isFinite ? min(max(d, -100_000), 100_000) : 0)
        }
        switch a {
        case "--corner":   c.corner = it.next() ?? "br"
        case "--margin-x": c.marginX = num()
        case "--margin-y": c.marginY = num()
        case "--x":        c.absX = num()
        case "--y":        c.absY = num()
        case "--scale":    c.scale = max(1, num())
        case "--lane":     c.lane = max(16, Int(num()))
        case "--always":   c.always = true
        case "--state":    c.statePath = NSString(string: it.next() ?? c.statePath).expandingTildeInPath
        case "--follow-claude": c.followClaude = true
        case "--follow-name":   c.followName = it.next() ?? c.followName
        case "--track-terminal": c.trackTerminal = true
        case "--follow-terminal": c.followTerminal = true
        case "-h", "--help":
            print("see header of clawd_overlay.swift for options"); exit(0)
        default: break
        }
    }
    return c
}

// ---------------------------------------------------------------- sprite
// Pixel codes: "." empty, "O" orange, "D" dark (eyes), "W" white (ball),
//              "P" pole grey, "F" flag orange
let COLORS: [Character: NSColor] = [
    "O": NSColor(srgbRed: 217/255, green: 119/255, blue: 87/255, alpha: 1),
    "D": NSColor(srgbRed: 30/255, green: 30/255, blue: 30/255, alpha: 1),
    "W": NSColor(srgbRed: 235/255, green: 235/255, blue: 235/255, alpha: 1),
    "P": NSColor(srgbRed: 150/255, green: 150/255, blue: 150/255, alpha: 1),
    "F": NSColor(srgbRed: 217/255, green: 119/255, blue: 87/255, alpha: 1),
    "Y": NSColor(srgbRed: 245/255, green: 200/255, blue: 80/255, alpha: 1),
    "B": NSColor(srgbRed: 100/255, green: 180/255, blue: 240/255, alpha: 1),
    "G": NSColor(srgbRed: 120/255, green: 210/255, blue: 120/255, alpha: 1),
    "R": NSColor(srgbRed: 235/255, green: 60/255, blue: 60/255, alpha: 1),
]

let SPRITE_W = 12
let SPRITE_H = 8

// Crab body: 12 wide, 8 tall. Claw pose 0 = claws up, 1 = claws open wider.
// Legs pose 0/1/2 = stand / walk A / walk B. eyes: open, closed, left, right.
func crabSprite(claw: Int, legs: Int, eyes: String) -> [String] {
    // claws (rows 0-1)
    let clawRows: [[String]] = [
        [".C........C.",
         ".C........C."],
        ["CC........CC",
         ".C........C."],
    ]
    var r0 = clawRows[claw % 2][0]
    var r1 = clawRows[claw % 2][1]
    r0 = r0.replacingOccurrences(of: "C", with: "O")
    r1 = r1.replacingOccurrences(of: "C", with: "O")

    // head/body rows 2-5
    let r2 = "..OOOOOOOO.."
    var r3 = Array("..OOOOOOOO..")
    switch eyes {
    case "closed": break
    case "left":   r3[3] = "D"; r3[7] = "D"
    case "right":  r3[4] = "D"; r3[8] = "D"
    default:       r3[4] = "D"; r3[7] = "D"   // open, centered
    }
    let r4 = ".OOOOOOOOOO."
    let r5 = "..OOOOOOOO.."

    // legs rows 6-7
    let legRows: [[String]] = [
        ["..O.O..O.O..",
         "..O.O..O.O.."],
        [".O..O..O..O.",
         ".O..O..O..O."],
        ["..O..OO..O..",
         "..O..OO..O.."],
    ]
    let l = legRows[legs % 3]
    return [r0, r1, r2, String(r3), r4, r5, l[0], l[1]]
}

// ---------------------------------------------------------------- scene
// A scene is the sprite plus extras (ball, flag) placed on a pixel grid
// LANE wide × SPRITE_H tall. Mirrors the statusline actions.
final class Scene {
    var grid: [[Character]]
    let lane: Int
    init(lane: Int) {
        self.lane = lane
        grid = Array(repeating: Array(repeating: ".", count: lane), count: SPRITE_H)
    }
    func place(_ sprite: [String], x: Int) {
        for (r, row) in sprite.enumerated() {
            for (c, ch) in row.enumerated() where ch != "." {
                let col = x + c
                if col >= 0 && col < lane { grid[r][col] = ch }
            }
        }
    }
    func put(_ r: Int, _ c: Int, _ ch: Character) {
        if r >= 0 && r < SPRITE_H && c >= 0 && c < lane { grid[r][c] = ch }
    }
}

enum Action: CaseIterable { case walk, football, flag, look, dumbbell, confetti, ninja }

func buildScene(action: Action, frame: Int, lane: Int, idle: Bool) -> Scene {
    let s = Scene(lane: lane)
    if idle {
        // stand still, blink occasionally, slow claw bob
        let eyes = frame % 23 == 7 ? "closed" : "open"
        let claw = (frame / 8) % 2
        s.place(crabSprite(claw: claw, legs: 0, eyes: eyes), x: (lane - SPRITE_W) / 2)
        return s
    }
    switch action {
    case .walk:
        let span = max(lane - SPRITE_W, 1)
        let pos = frame % (2 * span)
        let x = pos < span ? pos : 2 * span - pos
        let eyes = pos < span ? "right" : "left"
        // Cute parabolic bounce/hop during steps
        let step = frame % 4
        let hopY = (step == 1 || step == 2) ? 1 : 0
        if hopY > 0 {
            let shiftedScene = Scene(lane: lane)
            shiftedScene.place(crabSprite(claw: frame % 2, legs: frame, eyes: eyes), x: x)
            s.grid = Array(repeating: Array(repeating: ".", count: lane), count: SPRITE_H)
            for r in 0..<SPRITE_H {
                let targetR = r - hopY
                if targetR >= 0 && targetR < SPRITE_H {
                    s.grid[targetR] = shiftedScene.grid[r]
                }
            }
        } else {
            s.place(crabSprite(claw: frame % 2, legs: frame, eyes: eyes), x: x)
        }
    case .football:
        let cycle = frame % 16
        if cycle < 4 {                       // run up
            s.place(crabSprite(claw: 0, legs: cycle, eyes: "right"), x: cycle)
            s.put(SPRITE_H - 1, cycle + SPRITE_W + 2, "W")
        } else if cycle == 4 {               // kick
            s.place(crabSprite(claw: 1, legs: 2, eyes: "right"), x: 4)
            s.put(SPRITE_H - 1, 4 + SPRITE_W + 2, "W")
        } else if cycle <= 7 {               // ball rising
            s.place(crabSprite(claw: 0, legs: 0, eyes: "right"), x: 4)
            let bx = 4 + SPRITE_W + 2 + (cycle - 4) * 2
            let by = SPRITE_H - 1 - (cycle - 4)
            s.put(max(by, 0), bx, "W")
        } else {                             // ball rolling away
            s.place(crabSprite(claw: 0, legs: 0, eyes: "right"), x: 4)
            s.put(SPRITE_H - 1, 4 + SPRITE_W + 2 + (cycle - 4), "W")
        }
    case .flag:
        let x = 4
        s.place(crabSprite(claw: 0, legs: 0, eyes: "open"), x: x)
        let pole = x + SPRITE_W + 1
        for r in 0..<SPRITE_H { s.put(r, pole, "P") }
        // checkered flag waving (toggling W/D checks)
        let wave = frame % 2
        for r in 0...2 {
            for c in 1...3 {
                let useWhite = ((r + c + wave) % 2 == 0)
                s.put(r, pole + c, useWhite ? "W" : "D")
            }
        }
    case .look:
        let seq = ["open", "open", "right", "right", "open", "left", "left", "open"]
        let eyes = frame % 11 == 7 ? "closed" : seq[frame % seq.count]
        s.place(crabSprite(claw: (frame / 4) % 2, legs: 0, eyes: eyes),
                x: (lane - SPRITE_W) / 2)
    case .dumbbell:
        let cycle = frame % 16
        var x = (lane - SPRITE_W) / 2
        let dbY: Int
        let claw: Int
        
        if cycle < 4 {           // dumbbells down
            dbY = 4; claw = 1
        } else if cycle < 6 {    // dumbbells mid
            dbY = 2; claw = 0
        } else if cycle < 10 {   // dumbbells high + struggle shake
            dbY = 0; claw = 0
            x += (cycle % 2 == 0) ? -1 : 1
        } else if cycle < 12 {   // dumbbells mid
            dbY = 2; claw = 0
        } else {                 // dumbbells down
            dbY = 4; claw = 1
        }
        
        s.place(crabSprite(claw: claw, legs: 0, eyes: "open"), x: x)
        // left dumbbell
        let lx = x - 2
        s.put(dbY, lx, "W")
        s.put(dbY, lx + 1, "P")
        s.put(dbY, lx + 2, "W")
        s.put(dbY + 1, lx, "W")
        s.put(dbY + 1, lx + 2, "W")
        // right dumbbell
        let rx = x + SPRITE_W
        s.put(dbY, rx, "W")
        s.put(dbY, rx + 1, "P")
        s.put(dbY, rx + 2, "W")
        s.put(dbY + 1, rx, "W")
        s.put(dbY + 1, rx + 2, "W")
    case .confetti:
        let jumpYSeq = [0, 0, 1, 1, 2, 2, 1, 1]
        let jumpY = jumpYSeq[(frame / 2) % jumpYSeq.count]
        let x = (lane - SPRITE_W) / 2
        s.place(crabSprite(claw: frame % 2, legs: frame, eyes: "open"), x: x)
        if jumpY > 0 {
            let shiftedScene = Scene(lane: lane)
            shiftedScene.place(crabSprite(claw: frame % 2, legs: frame, eyes: "open"), x: x)
            s.grid = Array(repeating: Array(repeating: ".", count: lane), count: SPRITE_H)
            for r in 0..<SPRITE_H {
                let targetR = r - jumpY
                if targetR >= 0 && targetR < SPRITE_H {
                    s.grid[targetR] = shiftedScene.grid[r]
                }
            }
        }
        // falling colorful confetti with sinusoidal wind flutter
        let colors: [Character] = ["Y", "B", "G", "W"]
        for p in 0..<5 {
            let startX = p * (lane / 5)
            let offset = Int(sin(Double(frame + p) * 0.7) * 2.0)
            let px = (startX + offset + lane) % lane
            let py = (p * 5 + frame) % SPRITE_H
            let col = colors[(p + frame) % colors.count]
            if s.grid[py][px] == "." {
                s.grid[py][px] = col
            }
        }
    case .ninja:
        let cycle = frame % 16
        let x = (lane - SPRITE_W) / 2
        let jumpY: Int
        let kick: Bool
        let bow: Bool
        
        switch cycle {
        case 0...3:
            jumpY = 0; kick = false; bow = false
        case 4...5:
            jumpY = 1; kick = false; bow = false
        case 6...10:
            jumpY = 2; kick = true; bow = false
        case 11...12:
            jumpY = 1; kick = false; bow = false
        default: // 13...15
            jumpY = 0; kick = false; bow = true
        }
        
        let claw = kick ? 1 : 0
        let eyes = "right"
        let legs = kick ? 2 : (bow ? 0 : 1)
        
        let verticalShift = jumpY - (bow ? 1 : 0)
        
        if verticalShift != 0 {
            let shiftedScene = Scene(lane: lane)
            shiftedScene.place(crabSprite(claw: claw, legs: legs, eyes: eyes), x: x)
            s.grid = Array(repeating: Array(repeating: ".", count: lane), count: SPRITE_H)
            for r in 0..<SPRITE_H {
                let targetR = r - verticalShift
                if targetR >= 0 && targetR < SPRITE_H {
                    s.grid[targetR] = shiftedScene.grid[r]
                }
            }
        } else {
            s.place(crabSprite(claw: claw, legs: legs, eyes: eyes), x: x)
        }
        
        // Draw the red ninja headband on Clawd
        let headR = 2 - verticalShift
        if headR >= 0 && headR < SPRITE_H {
            for c in 2...9 {
                s.put(headR, x + c, "R")
            }
            let tailWave = frame % 2
            if tailWave == 0 {
                s.put(headR, x - 1, "R")
                s.put(headR + 1, x - 2, "R")
            } else {
                s.put(headR + 1, x - 1, "R")
                s.put(headR, x - 2, "R")
            }
        }
        
        // Draw flying kick extension
        if kick {
            let kickR = 6 - verticalShift
            if kickR >= 0 && kickR < SPRITE_H {
                s.put(kickR, x + SPRITE_W, "O")
                s.put(kickR, x + SPRITE_W + 1, "O")
            }
        }
        
        // Draw spinning/flying shuriken
        if cycle >= 6 {
            let shx = x + SPRITE_W + 2 + (cycle - 6) * 3
            if shx < lane {
                let shy = 3 - verticalShift
                if cycle % 2 == 0 {
                    s.put(shy, shx, "D")
                    s.put(shy + 1, shx + 1, "D")
                } else {
                    s.put(shy, shx + 1, "D")
                    s.put(shy + 1, shx, "D")
                }
            }
        }
    }
    return s
}

// ---------------------------------------------------------------- view
final class ClawdView: NSView {
    var config: Config
    var frameCount = 0
    var lastActive = Date.distantPast

    init(config: Config) {
        self.config = config
        let w = CGFloat(config.lane) * config.scale
        let h = CGFloat(SPRITE_H) * config.scale
        super.init(frame: NSRect(x: 0, y: 0, width: w, height: h))
    }
    required init?(coder: NSCoder) { fatalError() }

    var claudeWorking: Bool {
        if config.always { return true }
        guard let raw = try? String(contentsOfFile: config.statePath, encoding: .utf8),
              raw.trimmingCharacters(in: .whitespacesAndNewlines) == "working",
              let attrs = try? FileManager.default.attributesOfItem(atPath: config.statePath),
              let m = attrs[.modificationDate] as? Date else { return false }
        // Guard against a stale "working" left behind by a crash.
        return Date().timeIntervalSince(m) < 2 * 60 * 60
    }

    @objc func tick() {
        frameCount += 1
        needsDisplay = true
    }

    override func draw(_ dirtyRect: NSRect) {
        let idle = !claudeWorking
        let actionIdx = (frameCount / 33) % Action.allCases.count  // ~10s per action
        let scene = buildScene(action: Action.allCases[actionIdx],
                               frame: frameCount, lane: config.lane, idle: idle)
        NSGraphicsContext.current?.shouldAntialias = false
        let sc = config.scale
        for (r, row) in scene.grid.enumerated() {
            for (c, ch) in row.enumerated() {
                guard let color = COLORS[ch] else { continue }
                color.setFill()
                // flip: sprite row 0 is top
                let y = CGFloat(SPRITE_H - 1 - r) * sc
                NSRect(x: CGFloat(c) * sc, y: y, width: sc, height: sc).fill()
            }
        }
    }
}

// ---------------------------------------------------------------- follow
// True while some process whose executable basename == name is running.
// Uses libproc directly (no subprocess spawning): list all pids, resolve
// each executable path, compare the last path component.
func processRunning(named name: String) -> Bool {
    var count = proc_listallpids(nil, 0)
    guard count > 0 else { return false }
    var pids = [pid_t](repeating: 0, count: Int(count) + 64)
    count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
    guard count > 0 else { return false }
    let me = getpid()
    var buf = [CChar](repeating: 0, count: 4096)   // PROC_PIDPATHINFO_MAXSIZE
    for i in 0..<Int(count) {
        let pid = pids[i]
        if pid <= 0 || pid == me { continue }
        buf[0] = 0
        if proc_pidpath(pid, &buf, UInt32(buf.count)) <= 0 { continue }
        let path = String(cString: buf)
        if (path as NSString).lastPathComponent == name { return true }
    }
    return false
}

func terminalAppRunning() -> Bool {
    let apps = NSWorkspace.shared.runningApplications
    for app in apps {
        if let bid = app.bundleIdentifier, TERMINAL_BUNDLES.contains(bid) {
            return true
        }
    }
    return false
}

// ---------------------------------------------------------------- terminal tracking
let TERMINAL_BUNDLES: Set<String> = [
    "com.apple.Terminal",
    "com.googlecode.iterm2",
    "com.mitchellh.ghostty",
    "net.kovidgoyal.kitty",
    "com.github.wez.wezterm",
    "io.alacritty",
    "dev.warp.Warp-Stable",
    "com.jetbrains.fleet",
]

/// Find the frontmost terminal window's bounds in AppKit coordinates.
/// Returns nil if no known terminal app is frontmost.
func findTerminalBounds() -> NSRect? {
    guard let frontApp = NSWorkspace.shared.frontmostApplication,
          let bid = frontApp.bundleIdentifier,
          TERMINAL_BUNDLES.contains(bid) else { return nil }
    let pid = frontApp.processIdentifier
    guard let list = CGWindowListCopyWindowInfo(
        [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
    ) as? [[String: Any]] else { return nil }
    let screenH = NSScreen.main?.frame.height ?? 0
    for info in list {
        guard let ownerPID = info[kCGWindowOwnerPID as String] as? pid_t,
              ownerPID == pid,
              let layer = info[kCGWindowLayer as String] as? Int, layer == 0,
              let bd = info[kCGWindowBounds as String] as? NSDictionary else { continue }
        var r = CGRect.zero
        guard CGRectMakeWithDictionaryRepresentation(bd, &r) else { continue }
        if r.width < 200 || r.height < 200 { continue }   // skip tiny aux windows
        // Quartz (top-left origin) → AppKit (bottom-left origin)
        return NSRect(x: r.origin.x, y: screenH - r.origin.y - r.height,
                      width: r.width, height: r.height)
    }
    return nil
}

// ---------------------------------------------------------------- app
// The delegate owns the window, view and timer so nothing is deallocated
// out from under the run loop. Window is built in applicationDidFinishLaunching
// so it gets a proper display/event connection before being ordered front.
final class AppDelegate: NSObject, NSApplicationDelegate {
    let config: Config
    var window: NSWindow!
    var view: ClawdView!
    var timer: Timer!
    var followTimer: Timer?
    var trackTimer: Timer?
    var misses = 0

    init(config: Config) { self.config = config }

    // --follow-claude: exit after 3 consecutive 5s checks find no claude.
    // The grace window survives quick restarts and multiple sessions:
    // it only fires once EVERY claude process has been gone ~15s.
    @objc func checkClaude() {
        var keepAlive = false
        if config.followClaude && processRunning(named: config.followName) {
            keepAlive = true
        }
        if config.followTerminal && terminalAppRunning() {
            keepAlive = true
        }
        
        if !config.followClaude && !config.followTerminal {
            return
        }
        
        if keepAlive {
            misses = 0
        } else {
            misses += 1
            if misses >= 3 { NSApp.terminate(nil) }
        }
    }

    @objc func trackTerminalWindow() {
        guard let bounds = findTerminalBounds() else {
            if window.isVisible { window.orderOut(nil) }
            return
        }
        let size = view.frame.size
        let margin: CGFloat = 12
        let inputMargin: CGFloat = 60   // clear Claude Code's input area
        let origin = NSPoint(
            x: bounds.maxX - size.width - margin,
            y: bounds.minY + inputMargin
        )
        window.setFrameOrigin(origin)
        if !window.isVisible { window.orderFrontRegardless() }
    }

    func applicationDidFinishLaunching(_ note: Notification) {
        view = ClawdView(config: config)
        let size = view.frame.size

        var origin = NSPoint.zero
        if !config.trackTerminal {
            let screen = NSScreen.main ?? NSScreen.screens[0]
            let vis = screen.visibleFrame
            switch config.corner {
            case "tl": origin = NSPoint(x: vis.minX + config.marginX,
                                        y: vis.maxY - config.marginY - size.height)
            case "tr": origin = NSPoint(x: vis.maxX - config.marginX - size.width,
                                        y: vis.maxY - config.marginY - size.height)
            case "bl": origin = NSPoint(x: vis.minX + config.marginX,
                                        y: vis.minY + config.marginY)
            default:   origin = NSPoint(x: vis.maxX - config.marginX - size.width,
                                        y: vis.minY + config.marginY)
            }
            if let x = config.absX { origin.x = x }
            if let y = config.absY { origin.y = y }
        }

        window = NSWindow(contentRect: NSRect(origin: origin, size: size),
                          styleMask: .borderless, backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false        // we keep the only strong ref
        window.backgroundColor = .clear
        window.isOpaque = false
        window.hasShadow = false
        window.level = .floating                   // above normal windows, below menu bar
        window.ignoresMouseEvents = true           // clicks pass through to terminal
        window.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        window.contentView = view

        if config.trackTerminal {
            // Start hidden; tracking timer will show + position when terminal is found
        } else {
            window.orderFrontRegardless()
        }

        timer = Timer(timeInterval: 0.15, target: view!,
                      selector: #selector(ClawdView.tick), userInfo: nil, repeats: true)
        RunLoop.main.add(timer, forMode: .common)

        if config.trackTerminal {
            let t = Timer(timeInterval: 0.3, target: self,
                          selector: #selector(trackTerminalWindow), userInfo: nil, repeats: true)
            RunLoop.main.add(t, forMode: .common)
            trackTimer = t
        }

        if config.followClaude || config.followTerminal {
            let t = Timer(timeInterval: 5.0, target: self,
                          selector: #selector(checkClaude), userInfo: nil, repeats: true)
            RunLoop.main.add(t, forMode: .common)
            followTimer = t
        }
    }
}

let config = parseArgs()
let app = NSApplication.shared
app.setActivationPolicy(.accessory)   // no Dock icon, no menu bar
let delegate = AppDelegate(config: config)
app.delegate = delegate
app.run()
