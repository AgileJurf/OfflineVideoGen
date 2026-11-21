import AppKit
import ImageIO
import UniformTypeIdentifiers

// Render the source geometry into an opaque RGB image for App Store validation.
// Usage: swift scripts/generate_app_icon.swift path/to/AppIcon.png
let size = NSSize(width: 1024, height: 1024)
let context = CGContext(data: nil, width: 1024, height: 1024, bitsPerComponent: 8,
                        bytesPerRow: 4096, space: CGColorSpaceCreateDeviceRGB(),
                        bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
NSGraphicsContext.saveGraphicsState()
NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
NSColor(calibratedRed: 0.045, green: 0.085, blue: 0.12, alpha: 1).setFill()
NSBezierPath(rect: NSRect(origin: .zero, size: size)).fill()
let gradient = NSGradient(starting: NSColor(calibratedRed: 0.22, green: 0.95, blue: 0.76, alpha: 1),
                          ending: NSColor(calibratedRed: 0.12, green: 0.59, blue: 0.84, alpha: 1))!
let back = NSBezierPath(roundedRect: NSRect(x: 206, y: 292, width: 570, height: 474), xRadius: 90, yRadius: 90)
NSColor(calibratedRed: 0.12, green: 0.4, blue: 0.42, alpha: 1).setFill()
back.fill()
let front = NSBezierPath(roundedRect: NSRect(x: 270, y: 222, width: 570, height: 474), xRadius: 90, yRadius: 90)
gradient.draw(in: front, angle: -45)
NSColor(calibratedRed: 0.045, green: 0.085, blue: 0.12, alpha: 1).setFill()
let play = NSBezierPath()
play.move(to: NSPoint(x: 475, y: 348))
play.line(to: NSPoint(x: 475, y: 570))
play.line(to: NSPoint(x: 655, y: 459))
play.close()
play.fill()
NSGraphicsContext.restoreGraphicsState()
let output = URL(fileURLWithPath: CommandLine.arguments[1])
let destination = CGImageDestinationCreateWithURL(output as CFURL, UTType.png.identifier as CFString, 1, nil)!
CGImageDestinationAddImage(destination, context.makeImage()!, nil)
guard CGImageDestinationFinalize(destination) else { fatalError("Could not write app icon") }
