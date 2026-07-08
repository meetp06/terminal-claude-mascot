// Brand assets. The logo is bundled as a SwiftPM resource, so Bundle.module
// finds it in both `swift run` dev builds and the packaged .app (the builder
// copies PetOS_PetOS.bundle next to the executable).
import SwiftUI

enum Brand {
    static let teal = Color(red: 0x70/255, green: 0xB9/255, blue: 0xB0/255)
    static let blue = Color(red: 0x65/255, green: 0x92/255, blue: 0xB1/255)
    static let purple = Color(red: 0x82/255, green: 0x7D/255, blue: 0x90/255)
    static let bg = Color(red: 0x11/255, green: 0x12/255, blue: 0x14/255)

    static let logo: Image? = load("petos_logo")
    static let flakeNSImage: NSImage? = {
        guard let ns = loadNS("menubar_flake") else { return nil }
        ns.size = NSSize(width: 18, height: 18)   // fit the menu bar height
        ns.isTemplate = true                       // monochrome: white on dark bar
        return ns
    }()

    private static func loadNS(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png") else { return nil }
        return NSImage(contentsOf: url)
    }
    private static func load(_ name: String) -> Image? {
        guard let ns = loadNS(name) else { return nil }
        return Image(nsImage: ns)
    }
}
