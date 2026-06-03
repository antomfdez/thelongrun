// Renders a simple app icon (white runner on a green rounded square) into
// AppIcon.iconset/. build.sh then runs `iconutil` to produce AppIcon.icns.
import Cocoa

let iconset = "AppIcon.iconset"
try? FileManager.default.removeItem(atPath: iconset)
try? FileManager.default.createDirectory(atPath: iconset, withIntermediateDirectories: true)

func render(_ px: Int) -> Data? {
    let s = CGFloat(px)
    let img = NSImage(size: NSSize(width: s, height: s))
    img.lockFocus()
    let inset = s * 0.06
    let bg = NSBezierPath(roundedRect: NSRect(x: inset, y: inset, width: s - 2 * inset, height: s - 2 * inset),
                          xRadius: s * 0.22, yRadius: s * 0.22)
    NSColor.systemGreen.setFill(); bg.fill()
    let cfg = NSImage.SymbolConfiguration(pointSize: s * 0.55, weight: .bold)
        .applying(.init(paletteColors: [.white]))
    if let sym = NSImage(systemSymbolName: "figure.run", accessibilityDescription: nil)?
        .withSymbolConfiguration(cfg) {
        let gs = sym.size
        sym.draw(in: NSRect(x: (s - gs.width) / 2, y: (s - gs.height) / 2, width: gs.width, height: gs.height))
    }
    img.unlockFocus()
    guard let tiff = img.tiffRepresentation, let rep = NSBitmapImageRep(data: tiff) else { return nil }
    return rep.representation(using: .png, properties: [:])
}

// (filename, pixel size) pairs required for a macOS iconset.
let specs: [(String, Int)] = [
    ("icon_16x16", 16), ("icon_16x16@2x", 32),
    ("icon_32x32", 32), ("icon_32x32@2x", 64),
    ("icon_128x128", 128), ("icon_128x128@2x", 256),
    ("icon_256x256", 256), ("icon_256x256@2x", 512),
    ("icon_512x512", 512), ("icon_512x512@2x", 1024),
]
for (name, px) in specs {
    if let data = render(px) {
        try? data.write(to: URL(fileURLWithPath: "\(iconset)/\(name).png"))
    }
}
print("wrote \(iconset)")
