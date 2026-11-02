//
//  ZipArchive.swift
//  轻点记账
//
//  极简 ZIP 读写，用于 Excel(.xlsx) 导入导出。不依赖任何第三方库。
//  写入：仅 stored（不压缩），兼容性最好。
//  读取：支持 stored 与 deflate（用系统 Compression 框架）。
//

import Foundation
import Compression

// MARK: - CRC32

enum CRC32 {
    private static let table: [UInt32] = {
        (0..<256).map { index -> UInt32 in
            var value = UInt32(index)
            for _ in 0..<8 {
                value = (value & 1) != 0 ? (0xEDB8_8320 ^ (value >> 1)) : (value >> 1)
            }
            return value
        }
    }()

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xFFFF_FFFF
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xFF)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xFFFF_FFFF
    }
}

// MARK: - 写

enum ZipWriter {
    struct Entry {
        let path: String
        let data: Data
    }

    static func make(entries: [Entry]) -> Data {
        var output = Data()
        var central = Data()
        let (dosTime, dosDate) = dosDateTime(.now)

        for entry in entries {
            let nameData = Data(entry.path.utf8)
            let crc = CRC32.checksum(entry.data)
            let offset = UInt32(output.count)

            // Local file header
            output.append(uint32: 0x0403_4B50)
            output.append(uint16: 20)              // version needed
            output.append(uint16: 0x0800)           // UTF-8 filename flag
            output.append(uint16: 0)                // stored
            output.append(uint16: dosTime)
            output.append(uint16: dosDate)
            output.append(uint32: crc)
            output.append(uint32: UInt32(entry.data.count))
            output.append(uint32: UInt32(entry.data.count))
            output.append(uint16: UInt16(nameData.count))
            output.append(uint16: 0)
            output.append(nameData)
            output.append(entry.data)

            // Central directory record
            central.append(uint32: 0x0201_4B50)
            central.append(uint16: 20)              // version made by
            central.append(uint16: 20)              // version needed
            central.append(uint16: 0x0800)
            central.append(uint16: 0)
            central.append(uint16: dosTime)
            central.append(uint16: dosDate)
            central.append(uint32: crc)
            central.append(uint32: UInt32(entry.data.count))
            central.append(uint32: UInt32(entry.data.count))
            central.append(uint16: UInt16(nameData.count))
            central.append(uint16: 0)               // extra
            central.append(uint16: 0)               // comment
            central.append(uint16: 0)               // disk
            central.append(uint16: 0)               // internal attrs
            central.append(uint32: 0)               // external attrs
            central.append(uint32: offset)
            central.append(nameData)
        }

        let centralOffset = UInt32(output.count)
        output.append(central)

        output.append(uint32: 0x0605_4B50)
        output.append(uint16: 0)
        output.append(uint16: 0)
        output.append(uint16: UInt16(entries.count))
        output.append(uint16: UInt16(entries.count))
        output.append(uint32: UInt32(central.count))
        output.append(uint32: centralOffset)
        output.append(uint16: 0)

        return output
    }

    private static func dosDateTime(_ date: Date) -> (time: UInt16, date: UInt16) {
        let calendar = Calendar(identifier: .gregorian)
        let comps = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max((comps.year ?? 2024) - 1980, 0)
        let month = comps.month ?? 1
        let day = comps.day ?? 1
        let hour = comps.hour ?? 0
        let minute = comps.minute ?? 0
        let second = (comps.second ?? 0) / 2
        let time = UInt16((hour << 11) | (minute << 5) | second)
        let dateValue = UInt16((year << 9) | (month << 5) | day)
        return (time, dateValue)
    }
}

private extension Data {
    mutating func append(uint16 value: UInt16) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
    }

    mutating func append(uint32 value: UInt32) {
        append(UInt8(value & 0xFF))
        append(UInt8((value >> 8) & 0xFF))
        append(UInt8((value >> 16) & 0xFF))
        append(UInt8((value >> 24) & 0xFF))
    }
}

// MARK: - 读

enum ZipError: LocalizedError {
    case notAZip
    case corrupt(String)
    case unsupportedCompression(Int)

    var errorDescription: String? {
        switch self {
        case .notAZip: return "这不是一个有效的 xlsx 文件"
        case .corrupt(let detail): return "文件结构损坏：\(detail)"
        case .unsupportedCompression(let method): return "不支持的压缩方式（\(method)）"
        }
    }
}

enum ZipReader {
    struct Entry {
        let path: String
        let data: Data
    }

    /// 解压全部条目。返回 path → data
    static func unzip(_ archive: Data) throws -> [String: Data] {
        let bytes = [UInt8](archive)

        guard let eocdIndex = findEndOfCentralDirectory(bytes) else {
            throw ZipError.notAZip
        }

        let entryCount = Int(readUInt16(bytes, eocdIndex + 10))
        let centralOffset = Int(readUInt32(bytes, eocdIndex + 16))
        guard centralOffset < bytes.count else { throw ZipError.corrupt("中央目录偏移越界") }

        var result: [String: Data] = [:]
        var cursor = centralOffset

        for _ in 0..<entryCount {
            guard cursor + 46 <= bytes.count, readUInt32(bytes, cursor) == 0x0201_4B50 else {
                throw ZipError.corrupt("中央目录条目异常")
            }
            let method = Int(readUInt16(bytes, cursor + 10))
            let compressedSize = Int(readUInt32(bytes, cursor + 20))
            let uncompressedSize = Int(readUInt32(bytes, cursor + 24))
            let nameLength = Int(readUInt16(bytes, cursor + 28))
            let extraLength = Int(readUInt16(bytes, cursor + 30))
            let commentLength = Int(readUInt16(bytes, cursor + 32))
            let localOffset = Int(readUInt32(bytes, cursor + 42))

            guard cursor + 46 + nameLength <= bytes.count else { throw ZipError.corrupt("文件名越界") }
            let nameBytes = bytes[(cursor + 46)..<(cursor + 46 + nameLength)]
            let name = String(decoding: nameBytes, as: UTF8.self)

            cursor += 46 + nameLength + extraLength + commentLength

            guard localOffset + 30 <= bytes.count, readUInt32(bytes, localOffset) == 0x0403_4B50 else {
                throw ZipError.corrupt("本地头异常：\(name)")
            }
            let localNameLength = Int(readUInt16(bytes, localOffset + 26))
            let localExtraLength = Int(readUInt16(bytes, localOffset + 28))
            let dataStart = localOffset + 30 + localNameLength + localExtraLength
            guard dataStart + compressedSize <= bytes.count else {
                throw ZipError.corrupt("数据段越界：\(name)")
            }
            let raw = Data(bytes[dataStart..<(dataStart + compressedSize)])

            switch method {
            case 0:
                result[name] = raw
            case 8:
                if let inflated = inflate(raw, expectedSize: uncompressedSize) {
                    result[name] = inflated
                } else {
                    throw ZipError.corrupt("解压失败：\(name)")
                }
            default:
                throw ZipError.unsupportedCompression(method)
            }
        }
        return result
    }

    // MARK: 内部

    private static func findEndOfCentralDirectory(_ bytes: [UInt8]) -> Int? {
        guard bytes.count >= 22 else { return nil }
        let lowerBound = max(0, bytes.count - 65_557)
        var index = bytes.count - 22
        while index >= lowerBound {
            if readUInt32(bytes, index) == 0x0605_4B50 {
                return index
            }
            index -= 1
        }
        return nil
    }

    private static func readUInt16(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        guard offset + 1 < bytes.count else { return 0 }
        return UInt16(bytes[offset]) | (UInt16(bytes[offset + 1]) << 8)
    }

    private static func readUInt32(_ bytes: [UInt8], _ offset: Int) -> UInt32 {
        guard offset + 3 < bytes.count else { return 0 }
        return UInt32(bytes[offset])
            | (UInt32(bytes[offset + 1]) << 8)
            | (UInt32(bytes[offset + 2]) << 16)
            | (UInt32(bytes[offset + 3]) << 24)
    }

    /// raw deflate 解压。Compression 框架的 COMPRESSION_ZLIB 处理的是 RFC1951 裸流，
    /// 部分生成器会带 2 字节 zlib 头，所以这里做一次偏移兜底。
    private static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        if let result = inflateRaw(data, expectedSize: expectedSize), !result.isEmpty {
            return result
        }
        if data.count > 6 {
            let stripped = data.subdata(in: 2..<data.count)
            if let result = inflateRaw(stripped, expectedSize: expectedSize), !result.isEmpty {
                return result
            }
        }
        return nil
    }

    private static func inflateRaw(_ data: Data, expectedSize: Int) -> Data? {
        guard !data.isEmpty else { return nil }
        let capacity = max(expectedSize, data.count * 6, 64 * 1024)
        var output = Data(count: capacity)

        let written: Int = output.withUnsafeMutableBytes { destination -> Int in
            guard let destPointer = destination.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { source -> Int in
                guard let srcPointer = source.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_decode_buffer(
                    destPointer,
                    capacity,
                    srcPointer,
                    data.count,
                    nil,
                    COMPRESSION_ZLIB
                )
            }
        }

        guard written > 0 else { return nil }
        return output.prefix(written)
    }
}
