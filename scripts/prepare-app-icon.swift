#!/usr/bin/swift

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

private enum IconPreparationError: Error, CustomStringConvertible {
    case usage
    case unableToReadSource
    case unsupportedImage
    case unableToCreateContext
    case unableToCreateOutput
    case unableToWriteOutput

    var description: String {
        switch self {
        case .usage:
            "Usage: prepare-app-icon.swift <source.png> <output.png>"
        case .unableToReadSource:
            "Unable to read the source icon."
        case .unsupportedImage:
            "The source icon must be a non-empty PNG image."
        case .unableToCreateContext:
            "Unable to create the icon rendering context."
        case .unableToCreateOutput:
            "Unable to create the prepared icon image."
        case .unableToWriteOutput:
            "Unable to write the prepared icon PNG."
        }
    }
}

private func prepareIcon(sourceURL: URL, outputURL: URL) throws {
    guard
        let source = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(source, 0, nil)
    else {
        throw IconPreparationError.unableToReadSource
    }

    let width = image.width
    let height = image.height
    guard width > 0, height > 0 else {
        throw IconPreparationError.unsupportedImage
    }

    let bytesPerPixel = 4
    let bytesPerRow = width * bytesPerPixel
    var pixels = [UInt8](repeating: 0, count: height * bytesPerRow)
    guard let context = CGContext(
        data: &pixels,
        width: width,
        height: height,
        bitsPerComponent: 8,
        bytesPerRow: bytesPerRow,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            | CGBitmapInfo.byteOrder32Big.rawValue
    ) else {
        throw IconPreparationError.unableToCreateContext
    }

    context.interpolationQuality = .none
    context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

    // Only pixels connected to the canvas edge are eligible. This removes the
    // imported black corner matte without touching dark pixels inside the mark.
    let darkThreshold: UInt8 = 48
    let pixelCount = width * height
    var visited = [Bool](repeating: false, count: pixelCount)
    var queue = [Int]()
    queue.reserveCapacity(pixelCount / 4)

    func isDark(_ index: Int) -> Bool {
        let offset = index * bytesPerPixel
        return max(pixels[offset], pixels[offset + 1], pixels[offset + 2]) <= darkThreshold
    }

    func enqueue(_ index: Int) {
        guard !visited[index], isDark(index) else { return }
        visited[index] = true
        queue.append(index)
    }

    for x in 0..<width {
        enqueue(x)
        enqueue((height - 1) * width + x)
    }
    for y in 0..<height {
        enqueue(y * width)
        enqueue(y * width + width - 1)
    }

    var cursor = 0
    while cursor < queue.count {
        let index = queue[cursor]
        cursor += 1
        let x = index % width
        let y = index / width

        if x > 0 { enqueue(index - 1) }
        if x + 1 < width { enqueue(index + 1) }
        if y > 0 { enqueue(index - width) }
        if y + 1 < height { enqueue(index + width) }
    }

    for index in queue {
        let offset = index * bytesPerPixel
        pixels[offset] = 0
        pixels[offset + 1] = 0
        pixels[offset + 2] = 0
        pixels[offset + 3] = 0
    }

    guard let preparedImage = context.makeImage() else {
        throw IconPreparationError.unableToCreateOutput
    }
    guard
        let destination = CGImageDestinationCreateWithURL(
            outputURL as CFURL,
            UTType.png.identifier as CFString,
            1,
            nil
        )
    else {
        throw IconPreparationError.unableToWriteOutput
    }
    CGImageDestinationAddImage(destination, preparedImage, nil)
    guard CGImageDestinationFinalize(destination) else {
        throw IconPreparationError.unableToWriteOutput
    }

    print("Prepared TraceHalo icon: \(width)x\(height), transparent pixels: \(queue.count)")
}

do {
    guard CommandLine.arguments.count == 3 else {
        throw IconPreparationError.usage
    }
    try prepareIcon(
        sourceURL: URL(fileURLWithPath: CommandLine.arguments[1]),
        outputURL: URL(fileURLWithPath: CommandLine.arguments[2])
    )
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
