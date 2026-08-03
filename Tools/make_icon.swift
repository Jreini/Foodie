// Generates Foodie's app icon: an original fork-and-knife mark on the app's
// warm orange gradient. Drawn from scratch rather than rendering an SF Symbol,
// because Apple's SF Symbols license forbids using them in app icons.
//
// Run: swift make_icon.swift <output.png>

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

let side = 1024
let outputPath = CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "app_icon_1024.png"

let colorSpace = CGColorSpaceCreateDeviceRGB()

guard let ctx = CGContext(
    data: nil,
    width: side,
    height: side,
    bitsPerComponent: 8,
    bytesPerRow: 0,
    space: colorSpace,
    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
) else {
    FileHandle.standardError.write(Data("could not create context\n".utf8))
    exit(1)
}

// Work top-down so the coordinates below read the way they're drawn.
ctx.translateBy(x: 0, y: CGFloat(side))
ctx.scaleBy(x: 1, y: -1)

// MARK: - Background

// Matches AppTheme.primaryGradient: the icon should feel like the app it opens.
let gradient = CGGradient(
    colorsSpace: colorSpace,
    colors: [
        CGColor(red: 1.00, green: 0.42, blue: 0.22, alpha: 1),
        CGColor(red: 1.00, green: 0.60, blue: 0.34, alpha: 1)
    ] as CFArray,
    locations: [0, 1]
)!

// iOS masks the icon itself, so this fills the full square edge to edge.
ctx.drawLinearGradient(
    gradient,
    start: CGPoint(x: 0, y: 0),
    end: CGPoint(x: CGFloat(side), y: CGFloat(side)),
    options: []
)

// MARK: - Helpers

func roundedRect(_ x: CGFloat, _ y: CGFloat, _ w: CGFloat, _ h: CGFloat, _ r: CGFloat) -> CGPath {
    CGPath(roundedRect: CGRect(x: x, y: y, width: w, height: h),
           cornerWidth: r, cornerHeight: r, transform: nil)
}

ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))

// MARK: - Fork
//
// Three tines dropping into a shoulder, then a straight handle. Kept blocky
// and high-contrast so it still reads at 40pt on a home screen.

let forkCenter: CGFloat = 412
let tineWidth: CGFloat = 46
let tineTop: CGFloat = 232
let tineBottom: CGFloat = 420
let tineGap: CGFloat = 26

for offset in [-(tineWidth + tineGap), 0, tineWidth + tineGap] {
    ctx.addPath(roundedRect(
        forkCenter + offset - tineWidth / 2,
        tineTop,
        tineWidth,
        tineBottom - tineTop,
        tineWidth / 2
    ))
}
ctx.fillPath()

// Shoulder joining the tines.
let shoulderWidth = tineWidth * 3 + tineGap * 2
ctx.addPath(roundedRect(
    forkCenter - shoulderWidth / 2,
    tineBottom - 70,
    shoulderWidth,
    170,
    52
))
ctx.fillPath()

// Handle.
let forkHandleWidth: CGFloat = 60
ctx.addPath(roundedRect(
    forkCenter - forkHandleWidth / 2,
    500,
    forkHandleWidth,
    296,
    forkHandleWidth / 2
))
ctx.fillPath()

// MARK: - Knife
//
// A blade with a rounded tip and a straight spine, over a matching handle.

let knifeCenter: CGFloat = 656
let bladeWidth: CGFloat = 96
let bladeTop: CGFloat = 232
let bladeBottom: CGFloat = 520
// Softens where the blade meets the handle; a square corner there reads as
// unfinished next to the fully rounded fork.
let cornerEase: CGFloat = 24

let blade = CGMutablePath()
let bladeLeft = knifeCenter - bladeWidth / 2
let bladeRight = knifeCenter + bladeWidth / 2

// Straight spine up the left, rounded tip, then the belly sweeping out and
// down the right — the silhouette that reads as "knife" rather than "spatula".
blade.move(to: CGPoint(x: bladeLeft, y: bladeBottom - cornerEase))
blade.addLine(to: CGPoint(x: bladeLeft, y: bladeTop + 72))
blade.addQuadCurve(
    to: CGPoint(x: bladeLeft + 54, y: bladeTop),
    control: CGPoint(x: bladeLeft, y: bladeTop + 6)
)
blade.addQuadCurve(
    to: CGPoint(x: bladeRight, y: bladeTop + 214),
    control: CGPoint(x: bladeRight, y: bladeTop + 76)
)
blade.addLine(to: CGPoint(x: bladeRight, y: bladeBottom - cornerEase))
blade.addQuadCurve(
    to: CGPoint(x: bladeRight - cornerEase, y: bladeBottom),
    control: CGPoint(x: bladeRight, y: bladeBottom)
)
blade.addLine(to: CGPoint(x: bladeLeft + cornerEase, y: bladeBottom))
blade.addQuadCurve(
    to: CGPoint(x: bladeLeft, y: bladeBottom - cornerEase),
    control: CGPoint(x: bladeLeft, y: bladeBottom)
)
blade.closeSubpath()

ctx.addPath(blade)
ctx.fillPath()

// Handle, overlapping the blade slightly so they read as one object.
let knifeHandleWidth: CGFloat = 60
ctx.addPath(roundedRect(
    knifeCenter - knifeHandleWidth / 2,
    500,
    knifeHandleWidth,
    296,
    knifeHandleWidth / 2
))
ctx.fillPath()

// MARK: - Write

guard let image = ctx.makeImage() else {
    FileHandle.standardError.write(Data("could not render image\n".utf8))
    exit(1)
}

let url = URL(fileURLWithPath: outputPath)
guard let destination = CGImageDestinationCreateWithURL(
    url as CFURL,
    UTType.png.identifier as CFString,
    1,
    nil
) else {
    FileHandle.standardError.write(Data("could not create destination\n".utf8))
    exit(1)
}

CGImageDestinationAddImage(destination, image, nil)
guard CGImageDestinationFinalize(destination) else {
    FileHandle.standardError.write(Data("could not write png\n".utf8))
    exit(1)
}

print("wrote \(outputPath)")
