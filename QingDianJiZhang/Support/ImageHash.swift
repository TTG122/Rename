//
//  ImageHash.swift
//  轻点记账
//
//  图片指纹：用于「同一张截图被重复导入」的查重。
//

import Foundation
import CryptoKit
import UIKit

enum ImageHash {
    /// SHA256（对压缩后的 PNG 数据）。截图重新压缩后字节可能变化，
    /// 所以额外提供 perceptual 指纹作为兜底。
    static func sha256(of image: UIImage) -> String {
        guard let data = image.pngData() else { return "" }
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    static func sha256(of data: Data) -> String {
        let digest = SHA256.hash(data: data)
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    /// 感知指纹：缩放到 8x8 灰度 + 均值二值化，得到 64bit → 16 位十六进制。
    /// 同一张图即使被重新压缩也能得到相同的指纹。
    static func perceptual(of image: UIImage) -> String {
        let side = 8
        guard let cgImage = image.cgImage else { return "" }
        var pixels = [UInt8](repeating: 0, count: side * side)
        let colorSpace = CGColorSpaceCreateDeviceGray()
        guard let context = CGContext(
            data: &pixels,
            width: side,
            height: side,
            bitsPerComponent: 8,
            bytesPerRow: side,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.none.rawValue
        ) else { return "" }
        context.interpolationQuality = .high
        context.draw(cgImage, in: CGRect(x: 0, y: 0, width: side, height: side))

        let average = pixels.reduce(0) { $0 + Int($1) } / pixels.count
        var bits = ""
        for value in pixels {
            bits.append(Int(value) >= average ? "1" : "0")
        }

        var hex = ""
        var index = bits.startIndex
        while index < bits.endIndex {
            let end = bits.index(index, offsetBy: 4, limitedBy: bits.endIndex) ?? bits.endIndex
            let chunk = String(bits[index..<end]).padding(toLength: 4, withPad: "0", startingAt: 0)
            hex += String(UInt8(chunk, radix: 2) ?? 0, radix: 16)
            index = end
        }
        return hex
    }

    /// 两份感知指纹的汉明距离
    static func hammingDistance(_ a: String, _ b: String) -> Int {
        guard a.count == b.count, !a.isEmpty else { return .max }
        var distance = 0
        for (ca, cb) in zip(a, b) {
            guard let va = UInt8(String(ca), radix: 16), let vb = UInt8(String(cb), radix: 16) else {
                return .max
            }
            distance += (va ^ vb).nonzeroBitCount
        }
        return distance
    }
}
