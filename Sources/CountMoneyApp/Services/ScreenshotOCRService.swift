import Foundation
import ImageIO
import Vision

enum ScreenshotOCRService {
    static func makeDraft(from imageData: Data) async throws -> QuickEntryDraft {
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil),
              let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
        else {
            throw OCRFailure.invalidImage
        }

        let lines = try await recognizeText(in: image)
        let text = lines.joined(separator: "\n")
        let candidates = rankedAmountCandidates(from: lines)

        guard let best = candidates.first else {
            throw OCRFailure.noAmountFound
        }

        return QuickEntryDraft(
            id: UUID(),
            candidateAmount: best.amount,
            candidateAmounts: Array(candidates.prefix(5).map(\.amount)),
            recognizedTextPreview: String(text.prefix(220)),
            confidence: best.score,
            createdAt: Date()
        )
    }

    private static func recognizeText(in image: CGImage) async throws -> [String] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func rankedAmountCandidates(from lines: [String]) -> [AmountCandidate] {
        var candidates: [AmountCandidate] = []

        for line in lines {
            let normalized = normalize(line)
            for value in extractAmounts(from: normalized) {
                let score = score(line: normalized, value: value)
                guard score > 0 else { continue }
                candidates.append(AmountCandidate(amount: value, score: score))
            }
        }

        return Dictionary(grouping: candidates, by: \.amount)
            .compactMap { _, items in items.max { $0.score < $1.score } }
            .sorted { $0.score > $1.score }
    }

    private static func extractAmounts(from text: String) -> [Decimal] {
        let pattern = #"(?<!\d)(?:¥|￥|CNY|RMB)?\s*([0-9]{1,5}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]{1,5}\.[0-9]{1,2})(?!\d)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return regex.matches(in: text, range: range).compactMap { match in
            guard let amountRange = Range(match.range(at: 1), in: text) else { return nil }
            let raw = String(text[amountRange])
            guard !looksLikeDateOrTime(raw),
                  let amount = Decimal.moneyString(raw),
                  amount > 0
            else {
                return nil
            }
            return amount
        }
    }

    private static func score(line: String, value: Decimal) -> Double {
        var score = 0.35

        let positiveKeywords = ["实付", "支付", "付款", "合计", "总计", "金额", "收款", "已支付", "订单金额"]
        let strongestKeywords = ["实付", "实际支付", "已支付", "付款金额"]
        let negativeKeywords = ["余额", "优惠", "立减", "券", "积分", "订单号", "单号", "手机号", "验证码", "时间", "日期", "原价"]

        if positiveKeywords.contains(where: line.contains) {
            score += 0.35
        }

        if strongestKeywords.contains(where: line.contains) {
            score += 0.25
        }

        if line.contains("¥") || line.contains("￥") || line.localizedCaseInsensitiveContains("RMB") {
            score += 0.15
        }

        if negativeKeywords.contains(where: line.contains) {
            score -= 0.4
        }

        if value >= 1 && value <= 100_000 {
            score += 0.08
        }

        return max(0, min(score, 1))
    }

    private static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "￥", with: "¥")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeDateOrTime(_ raw: String) -> Bool {
        let compact = raw.replacingOccurrences(of: ",", with: "")
        if compact.count >= 8, compact.allSatisfy(\.isNumber) {
            return true
        }
        return false
    }
}

enum OCRFailure: LocalizedError {
    case invalidImage
    case noAmountFound

    var errorDescription: String? {
        switch self {
        case .invalidImage:
            "无法读取这张图片"
        case .noAmountFound:
            "没有识别到可用金额"
        }
    }
}

private struct AmountCandidate: Hashable {
    var amount: Decimal
    var score: Double
}
