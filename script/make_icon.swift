// Draws the Glade app icon: a clearing seen from above. Three layers of tree canopy
// step down, each a little darker, to an open, sunlit space in the middle.
// Usage: swift script/make_icon.swift <out.png>
import AppKit
import CoreImage

let size = 1024
let space = CGColorSpace(name: CGColorSpace.sRGB)!
let full = CGRect(x: 0, y: 0, width: size, height: size)
let centre = CGPoint(x: 512, y: 512)

func color(_ hex: UInt32, _ alpha: CGFloat = 1) -> CGColor {
  CGColor(srgbRed: CGFloat((hex >> 16) & 255) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
}

let ci = CIContext(options: [.workingColorSpace: space])

func context() -> CGContext {
  CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0, space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

/// The outline of one canopy layer as a mask: everything except an opening in the
/// middle, with rounded tree crowns reaching into the opening.
func canopyMask(opening: CGFloat, crowns: Int, crownRadius: CGFloat, phase: CGFloat) -> CGImage {
  let mask = context()
  mask.setFillColor(CGColor(gray: 1, alpha: 1))
  mask.fill(full)
  mask.setBlendMode(.clear)
  mask.fillEllipse(in: CGRect(x: centre.x - opening, y: centre.y - opening, width: opening * 2, height: opening * 2))
  mask.setBlendMode(.normal)
  for index in 0..<crowns {
    let angle = phase + CGFloat(index) / CGFloat(crowns) * 2 * .pi
    // Uneven crowns, so it reads as trees and not as a cog or a flower.
    let scale: CGFloat = [1.0, 0.82, 1.12, 0.9, 1.05, 0.78, 1.0][index % 7]
    let radius = crownRadius * scale
    let distance = opening + radius * 0.42
    let point = CGPoint(x: centre.x + cos(angle) * distance, y: centre.y + sin(angle) * distance)
    mask.fillEllipse(in: CGRect(x: point.x - radius, y: point.y - radius, width: radius * 2, height: radius * 2))
  }
  // Blur, then sharpen the edge again: this rounds off the points where two crowns
  // meet, so the outline is soft like foliage instead of spiky like a cog.
  let soft = CIImage(cgImage: mask.makeImage()!).clampedToExtent().applyingGaussianBlur(sigma: 13).cropped(to: full)
  let gain: CGFloat = 16
  let edge = soft.applyingFilter("CIColorMatrix", parameters: [
    "inputAVector": CIVector(x: 0, y: 0, z: 0, w: gain),
    "inputBiasVector": CIVector(x: 0, y: 0, z: 0, w: 0.5 - gain / 2),
  ]).applyingFilter("CIColorClamp")
  return ci.createCGImage(edge, from: full)!
}

let icon = context()

// The ground in the clearing: bright where the sun lands.
let ground = CGGradient(
  colorsSpace: space,
  colors: [color(0xFFFFF4), color(0xF4FFD6), color(0xC6F5A6), color(0x74D48F)] as CFArray,
  locations: [0, 0.3, 0.62, 1]
)!
icon.drawRadialGradient(ground, startCenter: CGPoint(x: 500, y: 540), startRadius: 0, endCenter: centre, endRadius: 330, options: [.drawsAfterEndLocation])

/// Paints a canopy layer with a top-to-bottom shade and lets it cast a shadow on
/// whatever is below it.
func layer(_ mask: CGImage, top: UInt32, bottom: UInt32, shadow: CGFloat) {
  icon.saveGState()
  icon.setShadow(offset: CGSize(width: 0, height: -14), blur: shadow, color: color(0x03241B, 0.5))
  icon.beginTransparencyLayer(auxiliaryInfo: nil)
  icon.clip(to: full, mask: mask)
  let shade = CGGradient(colorsSpace: space, colors: [color(top), color(bottom)] as CFArray, locations: [0, 1])!
  icon.drawLinearGradient(shade, start: CGPoint(x: 300, y: size), end: CGPoint(x: 720, y: 0), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
  icon.endTransparencyLayer()
  icon.restoreGState()
}

// Deepest canopy first, in shade; the top layer catches the light.
layer(canopyMask(opening: 196, crowns: 9, crownRadius: 74, phase: 0.35), top: 0x1C8A5E, bottom: 0x0C4F3A, shadow: 44)
layer(canopyMask(opening: 300, crowns: 11, crownRadius: 88, phase: 0.05), top: 0x2FAE76, bottom: 0x167350, shadow: 50)
layer(canopyMask(opening: 418, crowns: 13, crownRadius: 104, phase: 0.6), top: 0x55D898, bottom: 0x239265, shadow: 56)

let rep = NSBitmapImageRep(cgImage: icon.makeImage()!)
try! rep.representation(using: .png, properties: [:])!.write(to: URL(fileURLWithPath: CommandLine.arguments[1]))
