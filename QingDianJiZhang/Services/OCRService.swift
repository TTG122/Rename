//
//  OCRService.swift
//  轻点记账
//
//  Apple Vision 本机文字识别。所有识别都在设备端完成，图片不出设备。
//

import Foundation
import UIKit
import Vision

// MARK: - 结果模型

struct OCRLine: Identifiable, Sendable {
    let id = UUID()
    let text: String
    let confidence: Float
    /// Vision 原始坐标（左下角原点，0...1）
    let boundingBox: CGRect

    /// 转成「从上往下」的 y，方便按阅读顺序排序
    var topDownY: CGFloat { 1 - boundingBox.maxY }
    var height: CGFloat { boundingBox.height }
}

struct OCRDocument: Sendable {
    let lines: [OCRLine]
    let imageSize: CGSize
    let imageHash: String
    let perceptualHash: String

    /// 按阅读顺序（从上到下、从左到右）排列
    var orderedLines: [OCRLine] {
        lines.sorted { lhs, rhs in
            if abs(lhs.topDownY - rhs.topDownY) < 0.012 {
                return lhs.boundingBox.minX < rhs.boundingBox.minX
            }
            return lhs.topDownY < rhs.topDownY
        }
    }

    var fullText: String {
        orderedLines.map(\.text).joined(separator: "\n")
    }

    var isEmpty: Bool { lines.isEmpty }

    static let empty = OCRDocument(lines: [], imageSize: .zero, imageHash: "", perceptualHash: "")
}

// MARK: - 错误

enum OCRError: LocalizedError {
    case invalidImage
    case noTextFound
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .invalidImage: return "图片无法解析，请换一张截图试试"
        case .noTextFound: return "没有在图片里识别到文字，请确认截图包含金额信息"
        case .failed(let message): return message
        }
    }
}

// MARK: - 识别服务

final class OCRService {
    static let shared = OCRService()

    private let queue = DispatchQueue(label: "com.qingdianjizhang.ocr", qos: .userInitiated)

    private init() {}

    /// 识别图片中的文字。优先简体中文 + 英文。
    func recognize(image: UIImage) async throws -> OCRDocument {
        guard let cgImage = image.cgImageNormalized() else {
            throw OCRError.invalidImage
        }
        let size = image.size
        let sha = ImageHash.sha256(of: image)
        let perceptual = ImageHash.perceptual(of: image)

        return try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do {
                    let lines = try Self.performRecognition(cgImage: cgImage)
                    if lines.isEmpty {
                        continuation.resume(throwing: OCRError.noTextFound)
                        return
                    }
                    let document = OCRDocument(
                        lines: lines,
                        imageSize: size,
                        imageHash: sha,
                        perceptualHash: perceptual
                    )
                    continuation.resume(returning: document)
                } catch {
                    continuation.resume(throwing: OCRError.failed(error.localizedDescription))
                }
            }
        }
    }

    private static func performRecognition(cgImage: CGImage) throws -> [OCRLine] {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        request.recognitionLanguages = ["zh-Hans", "en-US"]
        // 支付截图文字通常较小，允许更激进的候选
        request.minimumTextHeight = 0.008

        let handler = VNImageRequestHandler(cgImage: cgImage, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw OCRError.failed("Vision 识别失败：\(error.localizedDescription)")
        }

        guard let observations = request.results else { return [] }

        return observations.compactMap { observation -> OCRLine? in
            guard let candidate = observation.topCandidates(1).first else { return nil }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return OCRLine(
                text: text,
                confidence: candidate.confidence,
                boundingBox: observation.boundingBox
            )
        }
    }

    /// 同时识别多张图片（批量导入截图）
    func recognize(images: [UIImage]) async -> [(image: UIImage, document: OCRDocument?)] {
        var results: [(UIImage, OCRDocument?)] = []
        for image in images {
            let document = try? await recognize(image: image)
            results.append((image, document))
        }
        return results
    }
}

// MARK: - UIImage 归一化

extension UIImage {
    /// 把任意方向 / 任意色彩空间的 UIImage 转成可直接喂给 Vision 的 CGImage
    func cgImageNormalized(maxSide: CGFloat = 2400) -> CGImage? {
        let longest = max(size.width, size.height)
        let scale = longest > maxSide ? maxSide / longest : 1
        let targetSize = CGSize(width: size.width * scale, height: size.height * scale)

        if imageOrientation == .up, scale == 1, let cgImage {
            return cgImage
        }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: targetSize, format: format)
        let redrawn = renderer.image { _ in
            draw(in: CGRect(origin: .zero, size: targetSize))
        }
        return redrawn.cgImage
    }
}
