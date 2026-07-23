//
//  TEXParser.swift
//  Open Wallpaper Engine
//
//  Parse Wallpaper Engine TEXV texture container files.
//  Structure: TEXV0005 > TEXI (metadata) > TEXB (image data).
//  Supports embedded JPEG/PNG data plus the common DXT1/DXT3/DXT5 formats.
//

import Cocoa
import Foundation

struct TEXMetadata {
    let format: UInt32
    let flags: UInt32
    let textureWidth: UInt32  // power-of-2 padded
    let textureHeight: UInt32
    let width: UInt32
    let height: UInt32
}

class TEXParser {
    private let data: Data

    init(data: Data) {
        self.data = data
    }

    /// Extract the first image from this TEX container.
    func extractImage() -> NSImage? {
        if let metadata = readTEXIMetadata(),
           let mipmap = readFirstMipmap() {
            switch metadata.format {
            case 7: // DXT1 / BC1
                if let image = decodeDXT(mipmap, metadata: metadata, format: .dxt1) { return image }
            case 6: // DXT3 / BC2
                if let image = decodeDXT(mipmap, metadata: metadata, format: .dxt3) { return image }
            case 4: // DXT5 / BC3
                if let image = decodeDXT(mipmap, metadata: metadata, format: .dxt5) { return image }
            default:
                break
            }
        }

        // Find TEXB section which contains the actual image data
        guard let texbRange = findSection("TEXB") else {
            NSLog("[TEXParser] TEXB section not found in %d bytes", data.count)
            return nil
        }

        let texbData = data[texbRange]
        NSLog("[TEXParser] TEXB found: range=%d..%d (%d bytes)", texbRange.lowerBound, texbRange.upperBound, texbData.count)

        // Look for JPEG magic bytes (FFD8) within TEXB
        if let jpegOffset = findJPEGMagic(in: texbData) {
            // Try to find the JPEG end marker (FFD9) to avoid trailing garbage
            let jpegData: Data
            if let endOffset = findJPEGEnd(in: texbData, from: jpegOffset) {
                jpegData = Data(texbData[jpegOffset...endOffset])
            } else {
                jpegData = Data(texbData[jpegOffset...])
            }
            NSLog("[TEXParser] JPEG found at offset %d, size=%d", jpegOffset - texbData.startIndex, jpegData.count)
            if let image = NSImage(data: jpegData) { return image }
            // If trimmed JPEG failed, try with all remaining data
            if let image = NSImage(data: Data(texbData[jpegOffset...])) { return image }
        }

        // Look for PNG magic bytes (89504E47) within TEXB
        if let pngOffset = findPNGMagic(in: texbData) {
            let pngData = Data(texbData[pngOffset...])
            if let image = NSImage(data: pngData) { return image }
        }

        // Fallback: scan entire data for JPEG/PNG (some TEX files have non-standard layout)
        if let jpegOffset = findJPEGMagic(in: data) {
            let jpegData: Data
            if let endOffset = findJPEGEnd(in: data, from: jpegOffset) {
                jpegData = Data(data[jpegOffset...endOffset])
            } else {
                jpegData = Data(data[jpegOffset...])
            }
            if let image = NSImage(data: jpegData) { return image }
        }

        NSLog("[TEXParser] No supported image format found in TEXB (%d bytes, may be DXT)", texbData.count)
        return nil
    }

    /// Extract raw JPEG/PNG data without creating NSImage
    func extractImageData() -> Data? {
        guard let texbRange = findSection("TEXB") else { return nil }
        let texbData = data[texbRange]

        if let jpegOffset = findJPEGMagic(in: texbData) {
            return Data(texbData[jpegOffset...])
        }
        if let pngOffset = findPNGMagic(in: texbData) {
            return Data(texbData[pngOffset...])
        }
        return nil
    }

    // MARK: - Private

    /// Read TEXI metadata. The field order follows the upstream texture parser:
    /// format, flags, padded texture size, then the logical image size.
    private func readTEXIMetadata() -> TEXMetadata? {
        guard let texiMagic = "TEXI".data(using: .ascii) else { return nil }
        var i = data.startIndex
        while i + 4 <= data.endIndex {
            if data[i..<i+4] == texiMagic {
                // Skip past "TEXIxxxx\0" (null-terminated name with version)
                var j = i + 4
                while j < data.endIndex && data[j] != 0 { j += 1 }
                j += 1 // skip null byte
                guard j + 24 <= data.endIndex else { return nil }
                func u32(_ off: Int) -> UInt32 {
                    UInt32(data[j+off]) | (UInt32(data[j+off+1]) << 8)
                    | (UInt32(data[j+off+2]) << 16) | (UInt32(data[j+off+3]) << 24)
                }
                return TEXMetadata(
                    format: u32(0), flags: u32(4),
                    textureWidth: u32(8), textureHeight: u32(12),
                    width: u32(16), height: u32(20)
                )
            }
            i += 1
        }
        return nil
    }

    // MARK: - TEXB mipmaps and DXT decoding

    private enum DXTFormat: Equatable {
        case dxt1
        case dxt3
        case dxt5

        var blockSize: Int {
            switch self {
            case .dxt1: return 8
            case .dxt3, .dxt5: return 16
            }
        }
    }

    private struct TEXMipmap {
        let width: UInt32
        let height: UInt32
        let pixels: Data
    }

    private struct RGBA {
        let red: UInt8
        let green: UInt8
        let blue: UInt8
        let alpha: UInt8
    }

    /// Parse the first TEXB mipmap according to the format documented by the
    /// upstream engine. Unlike JPEG/PNG payloads, DXT pixels cannot be found
    /// by scanning for a file magic value and must be read from this structure.
    private func readFirstMipmap() -> TEXMipmap? {
        guard let container = findTEXBContainer() else { return nil }
        var cursor = container.contentOffset

        guard let imageCount = readUInt32(at: cursor), imageCount > 0 else { return nil }
        cursor += 4

        switch container.version {
        case 3:
            // TEXB0003 stores the FreeImage format after imageCount.
            cursor += 4
        case 4:
            // TEXB0004 stores FreeImage format and an MP4 flag here.
            cursor += 8
        default:
            break
        }

        guard let mipmapCount = readUInt32(at: cursor), mipmapCount > 0 else { return nil }
        cursor += 4

        if container.version == 4 {
            // Editor-only TEXB0004 fields, followed by a null-terminated JSON string.
            guard cursor + 8 <= data.count else { return nil }
            cursor += 8
            guard skipNullTerminatedString(at: &cursor), cursor + 4 <= data.count else { return nil }
            cursor += 4
        }

        guard let width = readUInt32(at: cursor),
              let height = readUInt32(at: cursor) else { return nil }
        cursor += 8

        var compression: UInt32 = 0
        var uncompressedSize: Int?
        if container.version != 1 {
            guard let parsedCompression = readUInt32(at: cursor),
                  let parsedSize = readUInt32(at: cursor + 4) else { return nil }
            compression = parsedCompression
            uncompressedSize = Int(parsedSize)
            cursor += 8
        }

        guard let storedSize = readUInt32(at: cursor) else { return nil }
        cursor += 4
        let byteCount = Int(storedSize)
        guard byteCount >= 0, cursor + byteCount <= data.count else { return nil }
        let storedPixels = Data(data[cursor..<(cursor + byteCount)])

        let pixels: Data
        switch compression {
        case 0:
            pixels = storedPixels
        case 1:
            guard let expectedSize = uncompressedSize,
                  let decompressed = decompressLZ4(storedPixels, expectedSize: expectedSize) else {
                return nil
            }
            pixels = decompressed
        default:
            return nil
        }

        return TEXMipmap(width: width, height: height, pixels: pixels)
    }

    private func decodeDXT(_ mipmap: TEXMipmap, metadata: TEXMetadata, format: DXTFormat) -> NSImage? {
        let storageWidth = Int(mipmap.width)
        let storageHeight = Int(mipmap.height)
        guard storageWidth > 0, storageHeight > 0 else { return nil }

        let logicalWidth = min(max(Int(metadata.width), 1), storageWidth)
        let logicalHeight = min(max(Int(metadata.height), 1), storageHeight)
        let blocksWide = (storageWidth + 3) / 4
        let blocksHigh = (storageHeight + 3) / 4
        let requiredBytes = blocksWide * blocksHigh * format.blockSize
        guard mipmap.pixels.count >= requiredBytes else { return nil }

        var rgba = [UInt8](repeating: 0, count: logicalWidth * logicalHeight * 4)
        for blockY in 0..<blocksHigh {
            for blockX in 0..<blocksWide {
                let offset = (blockY * blocksWide + blockX) * format.blockSize
                let block = Array(mipmap.pixels[offset..<(offset + format.blockSize)])
                writeDXTBlock(
                    block,
                    format: format,
                    blockX: blockX,
                    blockY: blockY,
                    outputWidth: logicalWidth,
                    outputHeight: logicalHeight,
                    rgba: &rgba
                )
            }
        }

        return makeImage(rgba: rgba, width: logicalWidth, height: logicalHeight)
    }

    private func writeDXTBlock(
        _ block: [UInt8],
        format: DXTFormat,
        blockX: Int,
        blockY: Int,
        outputWidth: Int,
        outputHeight: Int,
        rgba: inout [UInt8]
    ) {
        let colorStart = format == .dxt1 ? 0 : 8
        let firstColor = UInt16(block[colorStart]) | (UInt16(block[colorStart + 1]) << 8)
        let secondColor = UInt16(block[colorStart + 2]) | (UInt16(block[colorStart + 3]) << 8)
        let palette = makeColorPalette(first: firstColor, second: secondColor, forceFourColors: format != .dxt1)
        let selectors = UInt32(block[colorStart + 4])
            | (UInt32(block[colorStart + 5]) << 8)
            | (UInt32(block[colorStart + 6]) << 16)
            | (UInt32(block[colorStart + 7]) << 24)

        let dxt5AlphaPalette = format == .dxt5 ? makeDXT5AlphaPalette(first: block[0], second: block[1]) : []
        var dxt5AlphaSelectors: UInt64 = 0
        if format == .dxt5 {
            for index in 0..<6 {
                dxt5AlphaSelectors |= UInt64(block[2 + index]) << UInt64(index * 8)
            }
        }

        for pixelY in 0..<4 {
            let y = blockY * 4 + pixelY
            guard y < outputHeight else { continue }
            for pixelX in 0..<4 {
                let x = blockX * 4 + pixelX
                guard x < outputWidth else { continue }

                let pixelIndex = pixelY * 4 + pixelX
                let colorIndex = Int((selectors >> UInt32(pixelIndex * 2)) & 0x3)
                let color = palette[colorIndex]
                let alpha: UInt8
                switch format {
                case .dxt1:
                    alpha = color.alpha
                case .dxt3:
                    let packedAlpha = block[pixelIndex / 2]
                    let nibble = pixelIndex.isMultiple(of: 2) ? packedAlpha & 0x0F : packedAlpha >> 4
                    alpha = nibble * 17
                case .dxt5:
                    let alphaIndex = Int((dxt5AlphaSelectors >> UInt64(pixelIndex * 3)) & 0x7)
                    alpha = dxt5AlphaPalette[alphaIndex]
                }

                let outputIndex = (y * outputWidth + x) * 4
                rgba[outputIndex] = color.red
                rgba[outputIndex + 1] = color.green
                rgba[outputIndex + 2] = color.blue
                rgba[outputIndex + 3] = alpha
            }
        }
    }

    private func makeColorPalette(first: UInt16, second: UInt16, forceFourColors: Bool) -> [RGBA] {
        let firstColor = color565(first)
        let secondColor = color565(second)
        if forceFourColors || first > second {
            return [
                firstColor,
                secondColor,
                blend(firstColor, secondColor, firstWeight: 2, secondWeight: 1, divisor: 3),
                blend(firstColor, secondColor, firstWeight: 1, secondWeight: 2, divisor: 3),
            ]
        }
        return [
            firstColor,
            secondColor,
            blend(firstColor, secondColor, firstWeight: 1, secondWeight: 1, divisor: 2),
            RGBA(red: 0, green: 0, blue: 0, alpha: 0),
        ]
    }

    private func color565(_ value: UInt16) -> RGBA {
        let red = UInt8((Int((value >> 11) & 0x1F) * 255 + 15) / 31)
        let green = UInt8((Int((value >> 5) & 0x3F) * 255 + 31) / 63)
        let blue = UInt8((Int(value & 0x1F) * 255 + 15) / 31)
        return RGBA(red: red, green: green, blue: blue, alpha: 255)
    }

    private func blend(_ first: RGBA, _ second: RGBA, firstWeight: Int, secondWeight: Int, divisor: Int) -> RGBA {
        RGBA(
            red: UInt8((Int(first.red) * firstWeight + Int(second.red) * secondWeight) / divisor),
            green: UInt8((Int(first.green) * firstWeight + Int(second.green) * secondWeight) / divisor),
            blue: UInt8((Int(first.blue) * firstWeight + Int(second.blue) * secondWeight) / divisor),
            alpha: UInt8((Int(first.alpha) * firstWeight + Int(second.alpha) * secondWeight) / divisor)
        )
    }

    private func makeDXT5AlphaPalette(first: UInt8, second: UInt8) -> [UInt8] {
        if first > second {
            return [
                first, second,
                UInt8((Int(first) * 6 + Int(second)) / 7),
                UInt8((Int(first) * 5 + Int(second) * 2) / 7),
                UInt8((Int(first) * 4 + Int(second) * 3) / 7),
                UInt8((Int(first) * 3 + Int(second) * 4) / 7),
                UInt8((Int(first) * 2 + Int(second) * 5) / 7),
                UInt8((Int(first) + Int(second) * 6) / 7),
            ]
        }
        return [
            first, second,
            UInt8((Int(first) * 4 + Int(second)) / 5),
            UInt8((Int(first) * 3 + Int(second) * 2) / 5),
            UInt8((Int(first) * 2 + Int(second) * 3) / 5),
            UInt8((Int(first) + Int(second) * 4) / 5),
            0, 255,
        ]
    }

    private func makeImage(rgba: [UInt8], width: Int, height: Int) -> NSImage? {
        guard let provider = CGDataProvider(data: Data(rgba) as CFData) else { return nil }
        let bitmapInfo = CGBitmapInfo.byteOrder32Big.union(
            CGBitmapInfo(rawValue: CGImageAlphaInfo.last.rawValue)
        )
        guard let image = CGImage(
            width: width,
            height: height,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: bitmapInfo,
            provider: provider,
            decode: nil,
            shouldInterpolate: true,
            intent: .defaultIntent
        ) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: width, height: height))
    }

    private func findTEXBContainer() -> (version: Int, contentOffset: Int)? {
        for version in [4, 3, 2, 1] {
            let magic = "TEXB000\(version)\0"
            if let offset = findMagic(magic) {
                return (version, offset + magic.utf8.count)
            }
        }
        return nil
    }

    private func findMagic(_ magic: String) -> Int? {
        let bytes = Array(magic.utf8)
        guard !bytes.isEmpty, data.count >= bytes.count else { return nil }
        for offset in 0...(data.count - bytes.count) {
            if data[offset..<(offset + bytes.count)].elementsEqual(bytes) {
                return offset
            }
        }
        return nil
    }

    private func readUInt32(at offset: Int) -> UInt32? {
        guard offset >= 0, offset + 4 <= data.count else { return nil }
        return UInt32(data[offset])
            | (UInt32(data[offset + 1]) << 8)
            | (UInt32(data[offset + 2]) << 16)
            | (UInt32(data[offset + 3]) << 24)
    }

    private func skipNullTerminatedString(at cursor: inout Int) -> Bool {
        while cursor < data.count {
            if data[cursor] == 0 {
                cursor += 1
                return true
            }
            cursor += 1
        }
        return false
    }

    /// A small, bounds-checked LZ4 block decoder for TEXB compressed mipmaps.
    /// Wallpaper Engine stores standard raw LZ4 blocks, not an LZ4 frame.
    private func decompressLZ4(_ source: Data, expectedSize: Int) -> Data? {
        guard expectedSize >= 0 else { return nil }
        let input = Array(source)
        var inputIndex = 0
        var output = [UInt8]()
        output.reserveCapacity(expectedSize)

        while inputIndex < input.count {
            let token = input[inputIndex]
            inputIndex += 1

            var literalLength = Int(token >> 4)
            if literalLength == 15 {
                while true {
                    guard inputIndex < input.count else { return nil }
                    let value = Int(input[inputIndex])
                    inputIndex += 1
                    literalLength += value
                    if value != 255 { break }
                }
            }
            guard literalLength <= input.count - inputIndex,
                  output.count + literalLength <= expectedSize else { return nil }
            output.append(contentsOf: input[inputIndex..<(inputIndex + literalLength)])
            inputIndex += literalLength

            // A final literal run has no match offset.
            if inputIndex == input.count { break }
            guard inputIndex + 2 <= input.count else { return nil }
            let offset = Int(input[inputIndex]) | (Int(input[inputIndex + 1]) << 8)
            inputIndex += 2
            guard offset > 0, offset <= output.count else { return nil }

            var matchLength = Int(token & 0x0F)
            if matchLength == 15 {
                while true {
                    guard inputIndex < input.count else { return nil }
                    let value = Int(input[inputIndex])
                    inputIndex += 1
                    matchLength += value
                    if value != 255 { break }
                }
            }
            matchLength += 4
            guard output.count + matchLength <= expectedSize else { return nil }
            for _ in 0..<matchLength {
                output.append(output[output.count - offset])
            }
        }

        guard output.count == expectedSize else { return nil }
        return Data(output)
    }

    /// Find a named section (e.g. "TEXI", "TEXB") in the TEX data
    private func findSection(_ name: String) -> Range<Data.Index>? {
        guard let nameData = name.data(using: .ascii) else { return nil }
        let nameLen = nameData.count

        var i = data.startIndex
        while i + nameLen + 4 <= data.endIndex {
            if data[i..<i+nameLen] == nameData {
                // Section found — next 4 bytes after name are section length
                let lenStart = i + nameLen
                guard lenStart + 4 <= data.endIndex else { return nil }
                let sectionLen = UInt32(data[lenStart])
                    | (UInt32(data[lenStart+1]) << 8)
                    | (UInt32(data[lenStart+2]) << 16)
                    | (UInt32(data[lenStart+3]) << 24)
                let contentStart = lenStart + 4
                let contentEnd = contentStart + Int(sectionLen)
                guard contentEnd <= data.endIndex else {
                    return contentStart..<data.endIndex
                }
                return contentStart..<contentEnd
            }
            i += 1
        }
        return nil
    }

    /// Find JPEG end marker (FFD9) scanning from a given start position
    private func findJPEGEnd(in slice: Data, from start: Data.Index) -> Data.Index? {
        var i = start
        while i + 1 < slice.endIndex {
            if slice[i] == 0xFF && slice[i+1] == 0xD9 {
                return i + 1  // Include the D9 byte
            }
            i += 1
        }
        return nil
    }

    private func findJPEGMagic(in slice: Data) -> Data.Index? {
        var i = slice.startIndex
        while i + 1 < slice.endIndex {
            if slice[i] == 0xFF && slice[i+1] == 0xD8 {
                return i
            }
            i += 1
        }
        return nil
    }

    private func findPNGMagic(in slice: Data) -> Data.Index? {
        let pngMagic: [UInt8] = [0x89, 0x50, 0x4E, 0x47]
        var i = slice.startIndex
        while i + 3 < slice.endIndex {
            if slice[i] == pngMagic[0] && slice[i+1] == pngMagic[1]
                && slice[i+2] == pngMagic[2] && slice[i+3] == pngMagic[3] {
                return i
            }
            i += 1
        }
        return nil
    }
}
