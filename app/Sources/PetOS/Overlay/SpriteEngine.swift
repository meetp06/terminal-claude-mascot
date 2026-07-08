// Pixel-art crab, ported and trimmed from clawd_overlay.swift. Parameterized by
// a body tint so each agent can look distinct (manager = warm, newbie = green).
import AppKit

enum Sprite {
    static let W = 12
    static let H = 10

    // Base palette; "O" (body) is replaced per-agent by a tint at draw time.
    static let colors: [Character: NSColor] = [
        "D": NSColor(srgbRed: 30/255, green: 30/255, blue: 30/255, alpha: 1),   // eyes
        "W": NSColor(srgbRed: 235/255, green: 235/255, blue: 235/255, alpha: 1),// white
        "P": NSColor(srgbRed: 150/255, green: 150/255, blue: 150/255, alpha: 1),// grey
        "A": NSColor(srgbRed: 112/255, green: 185/255, blue: 176/255, alpha: 1),// teal
        "B": NSColor(srgbRed: 101/255, green: 146/255, blue: 177/255, alpha: 1),// blue
        "Y": NSColor(srgbRed: 250/255, green: 204/255, blue: 80/255, alpha: 1), // yellow
        "R": NSColor(srgbRed: 245/255, green: 90/255, blue: 84/255, alpha: 1),  // red
    ]

    static func crab(legs: Int, eyes: String) -> [String] {
        let r0 = "............"
        let r1 = "............"
        let r2 = "..OOOOOOOO.."
        var r3 = Array("..OOOOOOOO..")
        switch eyes {
        case "closed": break
        case "left":  r3[3] = "D"; r3[7] = "D"
        case "right": r3[4] = "D"; r3[8] = "D"
        default:      r3[4] = "D"; r3[7] = "D"
        }
        let r4 = ".OOOOOOOOOO."
        let r5 = "..OOOOOOOO.."
        let legRows = [
            ["..O.O..O.O..", "..O.O..O.O.."],
            [".O..O..O..O.", ".O..O..O..O."],
            ["..O..OO..O..", "..O..OO..O.."],
        ]
        let l = legRows[((legs % 3) + 3) % 3]
        return [r0, r1, r2, String(r3), r4, r5, l[0], l[1]]
    }

    /// Returns an H x lane grid of characters for this frame.
    static func grid(frame: Int, lane: Int, state: PetState) -> [[Character]] {
        var g = Array(repeating: Array(repeating: Character("."), count: lane), count: H)

        func place(_ sprite: [String], x: Int, y: Int = 2) {
            for (r, row) in sprite.enumerated() {
                let tr = y + r
                guard tr >= 0, tr < H else { continue }
                for (c, ch) in row.enumerated() where ch != "." {
                    let col = x + c
                    if col >= 0, col < lane { g[tr][col] = ch }
                }
            }
        }

        func put(_ ch: Character, x: Int, y: Int) {
            guard y >= 0, y < H, x >= 0, x < lane else { return }
            g[y][x] = ch
        }

        func crabX(centeredIn lane: Int, offset: Int = 0) -> Int {
            max(0, min(lane - W, (lane - W) / 2 + offset))
        }

        switch state {
        case .sleep:
            // Rest in place, eyes closed, legs tucked; a little "z" bobs above.
            place(crab(legs: 0, eyes: "closed"), x: crabX(centeredIn: lane), y: 2)
            let zy = (frame / 10) % 2
            let zx = min((lane + W) / 2, lane - 1)
            put("W", x: zx, y: zy)

        case .wander, .work:
            let x = crabX(centeredIn: lane)
            let blink = frame % 92 > 86
            let eyes = blink ? "closed" : "open"
            let breath = frame / 30 % 2 == 0 ? 2 : 3
            place(crab(legs: 0, eyes: eyes), x: x, y: breath)
            if state == .work {
                let cx = min(lane - 3, x + W + 2)
                put("A", x: cx, y: 1)
                put("A", x: cx + 1, y: 0)
                put("B", x: cx + 2, y: 1)
            }

        case .scan:
            let x = crabX(centeredIn: lane)
            place(crab(legs: frame / 3, eyes: frame % 24 < 12 ? "left" : "right"), x: x, y: 2)
            let cx = min(lane - 3, x + W + 2)
            put("A", x: cx, y: 1)
            put("A", x: cx + 1, y: 0)
            put("A", x: cx + 2, y: 1)
            if frame % 12 < 6 { put("B", x: cx + 1, y: 2) }

        case .readFiles:
            let x = crabX(centeredIn: lane, offset: -1)
            place(crab(legs: 0, eyes: "right"), x: x, y: 2)
            let px = min(lane - 4, x + W + 1)
            put("W", x: px, y: 0); put("W", x: px + 1, y: 0); put("P", x: px + 2, y: 0)
            put("W", x: px, y: 1); put("P", x: px + 1, y: 1)
            put("W", x: px + 1, y: 2); put("W", x: px + 2, y: 2); put("P", x: px + 3, y: 2)

        case .research:
            let x = crabX(centeredIn: lane, offset: -1)
            place(crab(legs: 0, eyes: "right"), x: x, y: 2)
            let gx = min(lane - 5, x + W + 1)
            put("B", x: gx + 1, y: 0); put("B", x: gx + 2, y: 0)
            put("B", x: gx, y: 1); put("A", x: gx + 1, y: 1); put("A", x: gx + 2, y: 1); put("B", x: gx + 3, y: 1)
            put("B", x: gx + 1, y: 2); put("B", x: gx + 2, y: 2); put("W", x: gx + 4, y: 3)
            put("W", x: gx + 5, y: 4)

        case .think:
            let x = crabX(centeredIn: lane)
            place(crab(legs: 0, eyes: "closed"), x: x, y: 2)
            let start = x + 3
            for i in 0..<3 where frame / 6 % 3 >= i {
                put("W", x: start + i * 2, y: 0)
            }

        case .found:
            let x = crabX(centeredIn: lane)
            let hop = frame < 22 && frame % 10 < 5 ? 1 : 2
            place(crab(legs: frame, eyes: "open"), x: x, y: hop)
            let bx = x + W / 2
            put("Y", x: bx, y: 0)
            put("Y", x: bx - 1, y: 1); put("Y", x: bx, y: 1); put("Y", x: bx + 1, y: 1)
            put("P", x: bx, y: 2)

        case .alert:
            let x = crabX(centeredIn: lane)
            place(crab(legs: 0, eyes: "left"), x: x, y: 2)
            let ax = min(lane - 2, x + W + 2)
            put("R", x: ax, y: 0)
            put("R", x: ax, y: 1)
            put("W", x: ax, y: 3)
        }
        return g
    }
}

/// What a pet is doing, which drives its animation.
enum PetState: Equatable {
    case wander, work, sleep, scan, readFiles, research, think, found, alert
}

/// A view that draws the crab grid, tinting body pixels with `tint`.
final class AgentSpriteView: NSView {
    var tint: NSColor
    var scale: CGFloat
    let lane: Int
    var frameCount = 0
    var state: PetState = .wander
    var facingLeft = false

    init(tint: NSColor, scale: CGFloat = 3, lane: Int = 20) {
        self.tint = tint
        self.scale = scale
        self.lane = lane
        super.init(frame: NSRect(x: 0, y: 0,
                                 width: CGFloat(lane) * scale,
                                 height: CGFloat(Sprite.H) * scale))
    }
    required init?(coder: NSCoder) { fatalError() }

    func setState(_ newState: PetState) {
        if state != newState {
            state = newState
            frameCount = 0
        }
    }

    func tick() { frameCount += 1; needsDisplay = true }

    override func draw(_ dirtyRect: NSRect) {
        NSGraphicsContext.current?.shouldAntialias = false
        let grid = Sprite.grid(frame: frameCount, lane: lane, state: state)
        for (r, row) in grid.enumerated() {
            for (c, ch) in row.enumerated() where ch != "." {
                let color: NSColor = (ch == "O") ? tint : (Sprite.colors[ch] ?? tint)
                color.setFill()
                let col = facingLeft ? (lane - 1 - c) : c
                let y = CGFloat(Sprite.H - 1 - r) * scale
                NSRect(x: CGFloat(col) * scale, y: y, width: scale, height: scale).fill()
            }
        }
    }
}
