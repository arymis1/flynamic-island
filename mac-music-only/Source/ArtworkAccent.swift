import AppKit

struct ArtworkAccent: Equatable {
    let red: Double
    let green: Double
    let blue: Double
    static let fallback = ArtworkAccent(red: 1, green: 0.22, blue: 0.36)
    static let neutral = ArtworkAccent(red: 0.82, green: 0.82, blue: 0.84)

    // Render once per cover change. The soft 32px image expands into a smooth
    // backdrop without running a full-size live blur during playback.
    static func backdrop(from image: NSImage?) -> NSImage? {
        guard let image, let source = image.cgImage(forProposedRect: nil, context: nil, hints: nil),
              let space = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }
        let edge = 32
        var pixels = [UInt8](repeating: 0, count: edge * edge * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: edge, height: edge,
                                          bitsPerComponent: 8, bytesPerRow: edge * 4, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(source, in: CGRect(x: 0, y: 0, width: edge, height: edge))
            return true
        }
        guard rendered else { return nil }
        var scratch = pixels
        let radius = 5
        for _ in 0..<3 {
            for y in 0..<edge {
                for x in 0..<edge {
                    for channel in 0..<4 {
                        var sum = 0
                        for offset in -radius...radius { sum += Int(pixels[(y * edge + min(edge - 1, max(0, x + offset))) * 4 + channel]) }
                        scratch[(y * edge + x) * 4 + channel] = UInt8(sum / (radius * 2 + 1))
                    }
                }
            }
            for y in 0..<edge {
                for x in 0..<edge {
                    for channel in 0..<4 {
                        var sum = 0
                        for offset in -radius...radius { sum += Int(scratch[(min(edge - 1, max(0, y + offset)) * edge + x) * 4 + channel]) }
                        pixels[(y * edge + x) * 4 + channel] = UInt8(sum / (radius * 2 + 1))
                    }
                }
            }
        }
        guard let provider = CGDataProvider(data: Data(pixels) as CFData),
              let result = CGImage(width: edge, height: edge, bitsPerComponent: 8, bitsPerPixel: 32,
                                   bytesPerRow: edge * 4, space: space,
                                   bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue),
                                   provider: provider, decode: nil, shouldInterpolate: true, intent: .defaultIntent) else { return nil }
        return NSImage(cgImage: result, size: NSSize(width: edge, height: edge))
    }

    static func extract(from image: NSImage?) -> ArtworkAccent {
        guard let image, let cgImage = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return .fallback }
        var pixels = [UInt8](repeating: 0, count: 32 * 32 * 4)
        let rendered = pixels.withUnsafeMutableBytes { buffer -> Bool in
            guard let space = CGColorSpace(name: CGColorSpace.sRGB),
                  let context = CGContext(data: buffer.baseAddress, width: 32, height: 32,
                                          bitsPerComponent: 8, bytesPerRow: 128, space: space,
                                          bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue | CGBitmapInfo.byteOrder32Big.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: 32, height: 32))
            return true
        }
        return rendered ? fromRGBA(pixels) : .fallback
    }

    // Favor a representative colorful hue over black borders or white typography.
    static func fromRGBA(_ pixels: [UInt8]) -> ArtworkAccent {
        guard pixels.count >= 4 else { return .fallback }
        var weights = [Double](repeating: 0, count: 24)
        var sums = [(Double, Double, Double)](repeating: (0, 0, 0), count: 24)
        var visible = 0
        for index in stride(from: 0, through: pixels.count - 4, by: 4) {
            let alpha = Double(pixels[index + 3]) / 255
            guard alpha > 0.5 else { continue }
            visible += 1
            let r = min(1, Double(pixels[index]) / 255 / alpha)
            let g = min(1, Double(pixels[index + 1]) / 255 / alpha)
            let b = min(1, Double(pixels[index + 2]) / 255 / alpha)
            let maximum = max(r, max(g, b)), minimum = min(r, min(g, b))
            let delta = maximum - minimum
            guard maximum > 0.12, delta / maximum > 0.18 else { continue }
            var hue: Double
            if maximum == r { hue = (g - b) / delta }
            else if maximum == g { hue = (b - r) / delta + 2 }
            else { hue = (r - g) / delta + 4 }
            hue = (hue / 6 + 1).truncatingRemainder(dividingBy: 1)
            let bucket = min(23, Int(hue * 24))
            let weight = (delta / maximum) * max(0.2, maximum) * alpha
            weights[bucket] += weight
            sums[bucket].0 += r * weight
            sums[bucket].1 += g * weight
            sums[bucket].2 += b * weight
        }
        guard visible > 0 else { return .fallback }
        guard let bucket = weights.indices.max(by: { weights[$0] < weights[$1] }), weights[bucket] > 0 else { return .neutral }
        let total = weights[bucket]
        let r = sums[bucket].0 / total, g = sums[bucket].1 / total, b = sums[bucket].2 / total
        let brightness = max(r, max(g, b))
        let scale = max(0.78, min(0.96, brightness)) / brightness
        return ArtworkAccent(red: min(1, r * scale), green: min(1, g * scale), blue: min(1, b * scale))
    }
}
