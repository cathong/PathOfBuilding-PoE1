import CoreGraphics
import CoreText
import Foundation
import ImageIO
import UniformTypeIdentifiers

let atlasPixels = 2048
let linePixels: CGFloat = 32
let baselineFromTop: CGFloat = 27
let padding: CGFloat = 2

struct AtlasError: Error, CustomStringConvertible {
    let description: String
    init(_ description: String) { self.description = description }
}

func makeMask() throws -> CGContext {
    guard let context = CGContext(
        data: nil, width: atlasPixels, height: atlasPixels, bitsPerComponent: 8,
        bytesPerRow: atlasPixels, space: CGColorSpaceCreateDeviceGray(),
        bitmapInfo: CGImageAlphaInfo.none.rawValue
    ) else { throw AtlasError("Could not allocate grayscale glyph atlas") }
    context.setFillColor(gray: 0, alpha: 1)
    context.fill(CGRect(x: 0, y: 0, width: atlasPixels, height: atlasPixels))
    context.setFillColor(gray: 1, alpha: 1)
    context.setAllowsAntialiasing(true)
    context.setShouldAntialias(true)
    context.setShouldSmoothFonts(false)
    context.setShouldSubpixelPositionFonts(false)
    return context
}

func writeAtlas(_ mask: CGContext, to file: URL) throws -> Int {
    guard let pixels = mask.data?.assumingMemoryBound(to: UInt8.self) else {
        throw AtlasError("Could not read atlas pixels")
    }
    let pixelCount = atlasPixels * atlasPixels
    var rgba = Data(repeating: 255, count: pixelCount * 4)
    var covered = 0
    rgba.withUnsafeMutableBytes { raw in
        let bytes = raw.bindMemory(to: UInt8.self)
        for i in 0..<pixelCount {
            bytes[4 * i + 3] = pixels[i]
            if pixels[i] > 0 { covered += 1 }
        }
    }
    guard covered > 0,
          let provider = CGDataProvider(data: rgba as CFData),
          let image = CGImage(
              width: atlasPixels, height: atlasPixels, bitsPerComponent: 8,
              bitsPerPixel: 32, bytesPerRow: atlasPixels * 4,
              space: CGColorSpaceCreateDeviceRGB(),
              bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue),
              provider: provider, decode: nil, shouldInterpolate: false,
              intent: .defaultIntent
          ),
          let target = CGImageDestinationCreateWithURL(
              file as CFURL, UTType.png.identifier as CFString, 1, nil
          )
    else { throw AtlasError("Could not create nonempty PNG at \(file.path)") }
    CGImageDestinationAddImage(target, image, nil)
    guard CGImageDestinationFinalize(target) else {
        throw AtlasError("Could not write \(file.path)")
    }
    return covered
}

func glyphIn(_ font: CTFont, text: String) -> CGGlyph? {
    let utf16 = Array(text.utf16)
    var ids = Array(repeating: CGGlyph(0), count: utf16.count)
    CTFontGetGlyphsForCharacters(font, utf16, &ids, ids.count)
    return ids.first.flatMap { $0 == 0 ? nil : $0 }
}

func format(_ value: CGFloat) -> String {
    String(format: "%.7f", locale: Locale(identifier: "en_US_POSIX"), Double(value))
}

func run() throws {
    let args = CommandLine.arguments
    guard (3...4).contains(args.count) else {
        throw AtlasError("Usage: generate CODEPOINTS.txt OUTPUT_DIR [POSTSCRIPT_FONT]")
    }
    let input = URL(fileURLWithPath: args[1])
    let output = URL(fileURLWithPath: args[2], isDirectory: true)
        .appendingPathComponent("CJK", isDirectory: true)
    try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
    let codePoints = try String(contentsOf: input, encoding: .utf8)
        .split(whereSeparator: \.isWhitespace).compactMap { UInt32($0) }
    let fontName = args.count == 4 ? args[3] : "PingFangSC-Regular"
    let primary = CTFontCreateWithName(fontName as CFString, linePixels, nil)
    let selectedName = CTFontCopyPostScriptName(primary) as String
    print("Font: \(selectedName), line=\(linePixels), baseline=\(baselineFromTop)")

    var mask = try makeMask()
    var page = 1
    var cursorX = 0
    var cursorY = 0
    var shelfHeight = 0
    var pageNames: [String] = []
    var rows: [String] = []
    var missing: [UInt32] = []
    var fallbackCount = 0
    var coveredPixels = 0

    func finishPage() throws {
        let fileName = "atlas-\(page).png"
        coveredPixels += try writeAtlas(mask, to: output.appendingPathComponent(fileName))
        pageNames.append("Locales/CJK/\(fileName)")
    }

    for codePoint in codePoints {
        guard let scalar = UnicodeScalar(codePoint) else { continue }
        let text = String(scalar)
        var font = primary
        var glyph = glyphIn(font, text: text)
        if glyph == nil {
            let fallback = CTFontCreateForString(
                primary, text as CFString, CFRange(location: 0, length: text.utf16.count)
            )
            let name = CTFontCopyPostScriptName(fallback) as String
            if !name.lowercased().contains("lastresort") {
                font = fallback
                glyph = glyphIn(font, text: text)
                if glyph != nil { fallbackCount += 1 }
            }
        }
        guard var id = glyph else {
            missing.append(codePoint)
            continue
        }

        var advance = CGSize.zero
        CTFontGetAdvancesForGlyphs(font, .default, &id, &advance, 1)
        let bounds = CTFontGetBoundingRectsForGlyphs(font, .default, &id, nil, 1)
        if bounds.isNull || bounds.isEmpty {
            rows.append("    [\(codePoint)]={1,0,0,0,0,0,0,0,0,\(format(advance.width / linePixels))},")
            continue
        }
        let left = floor(bounds.minX) - padding
        let right = ceil(bounds.maxX) + padding
        let top = ceil(bounds.maxY) + padding
        let bottom = floor(bounds.minY) - padding
        let w = Int(right - left)
        let h = Int(top - bottom)
        guard w > 0, h > 0, w <= atlasPixels, h <= atlasPixels else {
            throw AtlasError("Invalid bounds for \(codePoint): \(bounds)")
        }

        if cursorX + w > atlasPixels {
            cursorX = 0
            cursorY += shelfHeight
            shelfHeight = 0
        }
        if cursorY + h > atlasPixels {
            try finishPage()
            mask = try makeMask()
            page += 1
            cursorY = 0
        }

        var origin = CGPoint(
            x: CGFloat(cursorX) - left,
            y: CGFloat(atlasPixels - cursorY) - top
        )
        CTFontDrawGlyphs(font, &id, &origin, 1, mask)
        let size = CGFloat(atlasPixels)
        let values: [CGFloat] = [
            CGFloat(cursorX) / size, CGFloat(cursorY) / size,
            CGFloat(cursorX + w) / size, CGFloat(cursorY + h) / size,
            left / linePixels, (baselineFromTop - top) / linePixels,
            CGFloat(w) / linePixels, CGFloat(h) / linePixels,
            advance.width / linePixels,
        ]
        rows.append("    [\(codePoint)]={\(page),\(values.map(format).joined(separator: ","))},")
        cursorX += w
        shelfHeight = max(shelfHeight, h)
    }

    try finishPage()
    let pages = pageNames.map { "\"\($0)\"" }.joined(separator: ",")
    let lua = """
    -- Generated by generate.swift. Glyph values are:
    -- page, u0, v0, u1, v1, x offset, y offset, width, height, advance
    -- Geometry is normalized by the requested DrawString line height.
    return {
      pages={\(pages)},
      glyphs={
    \(rows.joined(separator: "\n"))
      },
    }
    """
    try lua.write(to: output.appendingPathComponent("glyphs.lua"), atomically: true, encoding: .utf8)
    print("Glyphs: \(rows.count)/\(codePoints.count); pages: \(pageNames.count); fallback: \(fallbackCount); covered pixels: \(coveredPixels)")
    if !missing.isEmpty {
        print("Missing: " + missing.prefix(30).map { String(format: "U+%04X", $0) }.joined(separator: ", "))
    }
}

do {
    try run()
} catch {
    fputs("\(error)\n", stderr)
    exit(1)
}
