import AppKit

// 用 SF Symbol 畫出 app 圖示，輸出為 .iconset 內的多尺寸 PNG
let outputDir = CommandLine.arguments[1]
try? FileManager.default.createDirectory(atPath: outputDir, withIntermediateDirectories: true)

func render(size: Int, scale: Int, name: String) {
    let pixels = size * scale
    let image = NSImage(size: NSSize(width: pixels, height: pixels))
    image.lockFocus()
    let rect = NSRect(x: 0, y: 0, width: pixels, height: pixels)
    let inset = rect.insetBy(dx: CGFloat(pixels) * 0.05, dy: CGFloat(pixels) * 0.05)
    let path = NSBezierPath(roundedRect: inset, xRadius: inset.width * 0.22, yRadius: inset.width * 0.22)
    let gradient = NSGradient(colors: [
        NSColor(calibratedRed: 0.22, green: 0.30, blue: 0.48, alpha: 1),
        NSColor(calibratedRed: 0.07, green: 0.09, blue: 0.16, alpha: 1),
    ])!
    gradient.draw(in: path, angle: -90)

    let config = NSImage.SymbolConfiguration(pointSize: CGFloat(pixels) * 0.5, weight: .medium)
    if let symbol = NSImage(systemSymbolName: "lock.fill", accessibilityDescription: nil)?.withSymbolConfiguration(config) {
        let tinted = NSImage(size: symbol.size, flipped: false) { r in
            symbol.draw(in: r)
            NSColor.white.set()
            r.fill(using: .sourceAtop)
            return true
        }
        let s = tinted.size
        tinted.draw(in: NSRect(x: (CGFloat(pixels) - s.width) / 2, y: (CGFloat(pixels) - s.height) / 2, width: s.width, height: s.height))
    }
    image.unlockFocus()

    guard let tiff = image.tiffRepresentation,
          let rep = NSBitmapImageRep(data: tiff),
          let png = rep.representation(using: .png, properties: [:]) else { return }
    try? png.write(to: URL(fileURLWithPath: outputDir).appendingPathComponent(name))
}

for size in [16, 32, 128, 256, 512] {
    render(size: size, scale: 1, name: "icon_\(size)x\(size).png")
    render(size: size, scale: 2, name: "icon_\(size)x\(size)@2x.png")
}
