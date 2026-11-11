// Draws the background of the install window: a soft green wash and an arrow from the
// app to the Applications folder. Finder draws the icon names in black in a light window
// and in white in a dark one, so the wash is a middle tone that both read on.
// Usage: swift script/make_dmg_background.swift <out.png> <scale>
// Then: swift script/make_dmg_background.swift Resources/DMG/background.png 1
//       swift script/make_dmg_background.swift Resources/DMG/background@2x.png 2
import AppKit

let args = CommandLine.arguments
let scale = CGFloat(Double(args[2]) ?? 1)
let width = Int(640 * scale), height = Int(400 * scale)
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let ctx = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
ctx.scaleBy(x: scale, y: scale)
func rgb(_ r: CGFloat, _ g: CGFloat, _ b: CGFloat, _ a: CGFloat = 1) -> CGColor { CGColor(srgbRed: r / 255, green: g / 255, blue: b / 255, alpha: a) }
// Glade's green, lightest at the top. Where the names sit (about two thirds down) both
// black and white text keep a contrast of about 4.5:1.
let wash = CGGradient(colorsSpace: space, colors: [rgb(75, 142, 110), rgb(57, 124, 94)] as CFArray, locations: [0, 1])!
ctx.drawLinearGradient(wash, start: CGPoint(x: 0, y: 400), end: CGPoint(x: 0, y: 0), options: [])
// Arrow between the two icons, which sit at x = 170 and x = 470.
ctx.setStrokeColor(rgb(255, 255, 255, 0.55))
ctx.setLineWidth(6)
ctx.setLineCap(.round)
ctx.setLineJoin(.round)
let y: CGFloat = 400 - 185
ctx.move(to: CGPoint(x: 270, y: y))
ctx.addLine(to: CGPoint(x: 366, y: y))
ctx.strokePath()
ctx.move(to: CGPoint(x: 348, y: y + 18))
ctx.addLine(to: CGPoint(x: 368, y: y))
ctx.addLine(to: CGPoint(x: 348, y: y - 18))
ctx.strokePath()
let rep = NSBitmapImageRep(cgImage: ctx.makeImage()!)
rep.size = NSSize(width: 640, height: 400)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: args[1]))
