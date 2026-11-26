// Image measurement helpers for visual QA (see .claude/skills/visual-qa/SKILL.md). CoreGraphics only.
//
// build:  xcrun swiftc -O macOS/scripts/tools/imgtool.swift -o macOS/build/tools/imgtool
//
//   imgtool size    <png>
//   imgtool compare <reference.png> <x> <y> <candidate.png> <out-prefix>
//       Crops the reference at (x, y) to the candidate's size and writes
//         <out-prefix>-side.png  reference (top) over candidate (bottom), for viewing
//         <out-prefix>-diff.png  red = reference brighter, green = candidate brighter
//       and prints the mean absolute difference per channel (0–255; lower is closer).
//   imgtool pixel   <png> <x> <y>                         RGBA of one pixel (top-left origin)
//   imgtool inkbox  <png> <x0> <y0> <x1> <y1> [dark|light]
//       Bounding box and coverage of dark (or light) "ink" inside a region — for measuring numerals, hands
//       and text in pixels. Divide by the screenshot scale (2 for Retina) to get points.
import CoreGraphics
import Foundation
import ImageIO

struct Bitmap {
    let width: Int
    let height: Int
    let pixels: [UInt8] // RGBA, sRGB, top-left origin

    init(_ image: CGImage) {
        let w = image.width, h = image.height
        var data = [UInt8](repeating: 0, count: w * h * 4)
        data.withUnsafeMutableBytes { buffer in
            let ctx = CGContext(data: buffer.baseAddress, width: w, height: h, bitsPerComponent: 8,
                                bytesPerRow: w * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        }
        width = w
        height = h
        pixels = data
    }

    func rgba(_ x: Int, _ y: Int) -> (Int, Int, Int, Int) {
        let i = (y * width + x) * 4 // CGContext memory is top row first
        return (Int(pixels[i]), Int(pixels[i + 1]), Int(pixels[i + 2]), Int(pixels[i + 3]))
    }
}

func load(_ path: String) -> CGImage {
    guard let source = CGImageSourceCreateWithURL(URL(fileURLWithPath: path) as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
        fail("cannot read \(path)")
    }
    return image
}

func save(_ image: CGImage, _ path: String) {
    guard let dest = CGImageDestinationCreateWithURL(URL(fileURLWithPath: path) as CFURL, "public.png" as CFString, 1, nil) else {
        fail("cannot write \(path)")
    }
    CGImageDestinationAddImage(dest, image, nil)
    CGImageDestinationFinalize(dest)
}

func context(_ width: Int, _ height: Int) -> CGContext {
    CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
              space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("imgtool: \(message)\n".utf8))
    exit(1)
}

let args = Array(CommandLine.arguments.dropFirst())
func int(_ i: Int) -> Int {
    guard i < args.count, let v = Int(args[i]) else { fail("argument \(i + 1) must be an integer") }
    return v
}

switch args.first {
case "size" where args.count == 2:
    let image = load(args[1])
    print("\(image.width) x \(image.height)")

case "compare" where args.count == 6:
    let reference = load(args[1]), candidate = load(args[4])
    let x = int(2), y = int(3), w = candidate.width, h = candidate.height
    guard let crop = reference.cropping(to: CGRect(x: x, y: y, width: w, height: h)), crop.width == w, crop.height == h else {
        fail("the candidate (\(w)x\(h)) does not fit inside the reference at (\(x), \(y))")
    }
    let side = context(w, h * 2 + 8)
    side.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
    side.fill(CGRect(x: 0, y: 0, width: w, height: h * 2 + 8))
    side.draw(crop, in: CGRect(x: 0, y: h + 8, width: w, height: h))
    side.draw(candidate, in: CGRect(x: 0, y: 0, width: w, height: h))
    save(side.makeImage()!, args[5] + "-side.png")

    let a = Bitmap(crop), b = Bitmap(candidate)
    let diff = context(w, h)
    var total = 0.0
    for py in 0..<h {
        for px in 0..<w {
            let (r1, g1, b1, _) = a.rgba(px, py), (r2, g2, b2, _) = b.rgba(px, py)
            total += Double(abs(r1 - r2) + abs(g1 - g2) + abs(b1 - b2))
            let l1 = r1 + g1 + b1, l2 = r2 + g2 + b2, d = CGFloat(min(255, abs(l1 - l2))) / 255
            diff.setFillColor(CGColor(red: l1 > l2 ? d : 0, green: l2 > l1 ? d : 0, blue: 0, alpha: 1))
            diff.fill(CGRect(x: px, y: h - 1 - py, width: 1, height: 1))
        }
    }
    save(diff.makeImage()!, args[5] + "-diff.png")
    print(String(format: "mean abs diff per channel: %.2f", total / Double(w * h * 3)))

case "pixel" where args.count == 4:
    let bitmap = Bitmap(load(args[1]))
    let (r, g, b, a) = bitmap.rgba(int(2), int(3))
    print("rgba(\(r), \(g), \(b), \(a))")

case "inkbox" where args.count == 6 || args.count == 7:
    let bitmap = Bitmap(load(args[1]))
    let x0 = int(2), y0 = int(3), x1 = int(4), y1 = int(5)
    let dark = !(args.count == 7 && args[6] == "light")
    // Ink = distance from the region's background, estimated as its median luminance.
    var lums: [Int] = []
    for y in y0..<y1 { for x in x0..<x1 { let (r, g, b, _) = bitmap.rgba(x, y); lums.append((r + g + b) / 3) } }
    guard !lums.isEmpty else { fail("empty region") }
    let background = lums.sorted()[lums.count / 2]
    var minX = Int.max, minY = Int.max, maxX = Int.min, maxY = Int.min, coverage = 0.0
    for y in y0..<y1 {
        for x in x0..<x1 {
            let (r, g, b, _) = bitmap.rgba(x, y)
            let l = (r + g + b) / 3
            let ink = Double(dark ? background - l : l - background) / 255
            guard ink > 0.15 else { continue }
            coverage += min(1, ink * 1.5)
            minX = min(minX, x); minY = min(minY, y); maxX = max(maxX, x); maxY = max(maxY, y)
        }
    }
    if minX == Int.max { print("no ink"); break }
    print("bbox x \(minX)...\(maxX) y \(minY)...\(maxY)  size \(maxX - minX + 1) x \(maxY - minY + 1)  coverage \(Int(coverage)) px  background lum \(background)")

default:
    fail("usage: imgtool size|compare|pixel|inkbox … (see the comment at the top of scripts/tools/imgtool.swift)")
}
