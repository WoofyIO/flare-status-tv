// Draws the app icon layers and Top Shelf images into the asset catalog.
//
//   swift scripts/make-artwork.swift
//
// The artwork is original: a strip of uptime bars on a dark background.
import AppKit
import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let root = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().deletingLastPathComponent()
let brand = root.appendingPathComponent("FlareStatus/Assets.xcassets/App Icon & Top Shelf Image.brandassets")

let green = CGColor(red: 0.18, green: 0.82, blue: 0.48, alpha: 1)
let amber = CGColor(red: 0.96, green: 0.65, blue: 0.14, alpha: 1)
let red = CGColor(red: 1.0, green: 0.30, blue: 0.31, alpha: 1)

func render(width: Int, height: Int, opaque: Bool, _ draw: (CGContext, CGFloat, CGFloat) -> Void) -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let info = opaque ? CGImageAlphaInfo.noneSkipLast.rawValue : CGImageAlphaInfo.premultipliedLast.rawValue
    let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: info)!
    draw(context, CGFloat(width), CGFloat(height))
    return context.makeImage()!
}

func write(_ image: CGImage, _ url: URL) {
    try! FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
    CGImageDestinationAddImage(destination, image, nil)
    CGImageDestinationFinalize(destination)
}

func background(_ c: CGContext, _ w: CGFloat, _ h: CGFloat) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let colors = [CGColor(red: 0.07, green: 0.09, blue: 0.14, alpha: 1), CGColor(red: 0.03, green: 0.04, blue: 0.07, alpha: 1)] as CFArray
    let gradient = CGGradient(colorsSpace: space, colors: colors, locations: [0, 1])!
    c.drawLinearGradient(gradient, start: CGPoint(x: 0, y: h), end: CGPoint(x: w, y: 0), options: [])
    // A soft glow behind the bars.
    let glow = CGGradient(colorsSpace: space, colors: [CGColor(red: 0.18, green: 0.82, blue: 0.48, alpha: 0.22), CGColor(red: 0.18, green: 0.82, blue: 0.48, alpha: 0)] as CFArray, locations: [0, 1])!
    c.drawRadialGradient(glow, startCenter: CGPoint(x: w / 2, y: h / 2), startRadius: 0, endCenter: CGPoint(x: w / 2, y: h / 2), endRadius: min(w, h) * 0.75, options: [])
}

/// The uptime strip: rounded bars, mostly green, centred in `rect`.
func bars(_ c: CGContext, in rect: CGRect, count: Int = 9) {
    let pattern: [Int: CGColor] = [5: amber, 6: red]
    let gap = rect.width / CGFloat(count) * 0.32
    let barWidth = (rect.width - gap * CGFloat(count - 1)) / CGFloat(count)
    for index in 0..<count {
        let x = rect.minX + CGFloat(index) * (barWidth + gap)
        let bar = CGRect(x: x, y: rect.minY, width: barWidth, height: rect.height)
        c.addPath(CGPath(roundedRect: bar, cornerWidth: barWidth * 0.32, cornerHeight: barWidth * 0.32, transform: nil))
        c.setFillColor(pattern[index] ?? green)
        c.fillPath()
    }
}

func text(_ c: CGContext, _ string: String, size: CGFloat, weight: NSFont.Weight, color: NSColor, at point: CGPoint) {
    let attributes: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: size, weight: weight), .foregroundColor: color]
    let line = CTLineCreateWithAttributedString(NSAttributedString(string: string, attributes: attributes))
    c.textPosition = point
    CTLineDraw(line, c)
}

func iconBack(_ w: Int, _ h: Int) -> CGImage { render(width: w, height: h, opaque: true) { c, w, h in background(c, w, h) } }
func iconFront(_ w: Int, _ h: Int) -> CGImage {
    render(width: w, height: h, opaque: false) { c, w, h in
        bars(c, in: CGRect(x: w * 0.2, y: h * 0.28, width: w * 0.6, height: h * 0.44))
    }
}
func topShelf(_ w: Int, _ h: Int) -> CGImage {
    render(width: w, height: h, opaque: true) { c, w, h in
        background(c, w, h)
        let stripHeight = h * 0.3
        bars(c, in: CGRect(x: w * 0.12, y: h * 0.5 - stripHeight * 0.1, width: w * 0.76, height: stripHeight), count: 30)
        text(c, "Flare Status", size: h * 0.11, weight: .bold, color: .white, at: CGPoint(x: w * 0.12, y: h * 0.22))
        text(c, "Uptime at a glance", size: h * 0.06, weight: .regular, color: NSColor(white: 1, alpha: 0.6), at: CGPoint(x: w * 0.12, y: h * 0.12))
    }
}

write(iconBack(400, 240), brand.appendingPathComponent("App Icon.imagestack/Back.imagestacklayer/Content.imageset/back@1x.png"))
write(iconBack(800, 480), brand.appendingPathComponent("App Icon.imagestack/Back.imagestacklayer/Content.imageset/back@2x.png"))
write(iconFront(400, 240), brand.appendingPathComponent("App Icon.imagestack/Front.imagestacklayer/Content.imageset/front@1x.png"))
write(iconFront(800, 480), brand.appendingPathComponent("App Icon.imagestack/Front.imagestacklayer/Content.imageset/front@2x.png"))
write(iconBack(1280, 768), brand.appendingPathComponent("App Icon - App Store.imagestack/Back.imagestacklayer/Content.imageset/back@1x.png"))
write(iconFront(1280, 768), brand.appendingPathComponent("App Icon - App Store.imagestack/Front.imagestacklayer/Content.imageset/front@1x.png"))
write(topShelf(1920, 720), brand.appendingPathComponent("Top Shelf Image.imageset/top-shelf-image@1x.png"))
write(topShelf(3840, 1440), brand.appendingPathComponent("Top Shelf Image.imageset/top-shelf-image@2x.png"))
write(topShelf(2320, 720), brand.appendingPathComponent("Top Shelf Image Wide.imageset/top-shelf-image-wide@1x.png"))
write(topShelf(4640, 1440), brand.appendingPathComponent("Top Shelf Image Wide.imageset/top-shelf-image-wide@2x.png"))
print("artwork written")
