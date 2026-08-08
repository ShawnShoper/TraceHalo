#!/usr/bin/swift

import Foundation

private enum ICNSError: Error, CustomStringConvertible {
    case usage
    case invalidType(String)
    case unreadableFile(String)
    case fileTooLarge(String)

    var description: String {
        switch self {
        case .usage:
            "Usage: make-icns.swift <output.icns> <four-character-type>=<image.png> [...]"
        case let .invalidType(value):
            "Invalid ICNS chunk type: \(value)"
        case let .unreadableFile(path):
            "Unable to read ICNS source image: \(path)"
        case let .fileTooLarge(path):
            "ICNS source image is too large: \(path)"
        }
    }
}

private func bigEndianBytes(_ value: UInt32) -> [UInt8] {
    let encoded = value.bigEndian
    return withUnsafeBytes(of: encoded) { Array($0) }
}

do {
    guard CommandLine.arguments.count >= 3 else { throw ICNSError.usage }

    let outputURL = URL(fileURLWithPath: CommandLine.arguments[1])
    var chunks = Data()

    for argument in CommandLine.arguments.dropFirst(2) {
        guard let separator = argument.firstIndex(of: "=") else {
            throw ICNSError.usage
        }
        let type = String(argument[..<separator])
        let path = String(argument[argument.index(after: separator)...])
        guard type.utf8.count == 4 else { throw ICNSError.invalidType(type) }
        guard let payload = FileManager.default.contents(atPath: path) else {
            throw ICNSError.unreadableFile(path)
        }
        guard payload.count <= Int(UInt32.max) - 8 else {
            throw ICNSError.fileTooLarge(path)
        }

        chunks.append(contentsOf: type.utf8)
        chunks.append(contentsOf: bigEndianBytes(UInt32(payload.count + 8)))
        chunks.append(payload)
    }

    guard chunks.count <= Int(UInt32.max) - 8 else {
        throw ICNSError.fileTooLarge(outputURL.path)
    }

    var result = Data("icns".utf8)
    result.append(contentsOf: bigEndianBytes(UInt32(chunks.count + 8)))
    result.append(chunks)
    try result.write(to: outputURL, options: .atomic)
    print("Created TraceHalo ICNS with \(CommandLine.arguments.count - 2) icon representations")
} catch {
    FileHandle.standardError.write(Data("\(error)\n".utf8))
    exit(1)
}
