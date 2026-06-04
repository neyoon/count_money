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
        let text = lines.map(\.text).joined(separator: "\n")
        let candidates = rankedAmountCandidates(from: lines)

        guard let best = candidates.first else {
            throw OCRFailure.noAmountFound
        }
        let displayedCandidates = visibleCandidates(from: candidates)

        return QuickEntryDraft(
            id: UUID(),
            candidateAmount: best.amount,
            candidateAmounts: displayedCandidates,
            suggestedKind: best.suggestedKind,
            recognizedTextPreview: String(text.prefix(220)),
            confidence: best.score,
            createdAt: Date()
        )
    }

    private static func recognizeText(in image: CGImage) async throws -> [RecognizedLine] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    continuation.resume(throwing: error)
                    return
                }

                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let lines = observations.compactMap { observation -> RecognizedLine? in
                    guard let text = observation.topCandidates(1).first?.string else { return nil }
                    return RecognizedLine(text: text, boundingBox: observation.boundingBox)
                }
                .sorted { lhs, rhs in
                    if abs(lhs.topY - rhs.topY) > 0.012 {
                        return lhs.topY < rhs.topY
                    }
                    return lhs.boundingBox.minX < rhs.boundingBox.minX
                }

                continuation.resume(returning: lines)
            }
            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = false
            request.recognitionLanguages = ["zh-Hans", "en-US"]

            let handler = VNImageRequestHandler(cgImage: image, options: [:])

            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    private static func rankedAmountCandidates(from lines: [RecognizedLine]) -> [AmountCandidate] {
        var candidates: [AmountCandidate] = []
        let fullText = lines.map(\.normalizedText).joined(separator: "\n")

        for index in lines.indices {
            let line = lines[index]
            let normalized = line.normalizedText
            for extractedAmount in extractAmounts(from: normalized) {
                let context = nearbyText(lines: lines, index: index)
                let score = score(
                    line: line,
                    context: context,
                    fullText: fullText,
                    value: extractedAmount.amount
                )
                guard score > 0 else { continue }
                candidates.append(AmountCandidate(
                    amount: extractedAmount.amount.magnitude,
                    score: score,
                    topY: line.topY,
                    centerX: line.centerX,
                    text: normalized,
                    suggestedKind: suggestedKind(
                        amount: extractedAmount,
                        context: context,
                        fullText: fullText
                    )
                ))
            }
        }

        return Dictionary(grouping: candidates, by: \.amount)
            .compactMap { _, items in items.max { $0.score < $1.score } }
            .sorted {
                if $0.score != $1.score {
                    return $0.score > $1.score
                }
                if $0.topY != $1.topY {
                    return $0.topY < $1.topY
                }
                return $0.centerX < $1.centerX
            }
    }

    private static func visibleCandidates(from candidates: [AmountCandidate]) -> [Decimal] {
        guard let best = candidates.first else { return [] }
        let threshold = max(0.55, best.score - 0.22)
        let visible = candidates
            .filter { $0.score >= threshold }
            .prefix(5)
            .map(\.amount)

        return visible.isEmpty ? [best.amount] : Array(visible)
    }

    private static func extractAmounts(from text: String) -> [ExtractedAmount] {
        let pattern = #"(?<![\dA-Za-z])([+\-−＋－])?\s*(?:¥|￥|CNY|RMB)?\s*([0-9]{1,6}(?:,[0-9]{3})*(?:\.[0-9]{1,2})?|[0-9]{1,6}\.[0-9]{1,2})(?![\dA-Za-z])"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)

        return regex.matches(in: text, range: range).compactMap { match in
            guard let amountRange = Range(match.range(at: 2), in: text) else { return nil }
            let raw = String(text[amountRange])
            guard !looksLikeDateOrTime(raw, line: text),
                  let amount = Decimal.moneyString(raw),
                  amount > 0
            else {
                return nil
            }
            let sign = Range(match.range(at: 1), in: text).map { String(text[$0]) } ?? ""
            return ExtractedAmount(amount: amount, sign: sign)
        }
    }

    private static func suggestedKind(
        amount: ExtractedAmount,
        context: String,
        fullText: String
    ) -> TransactionKind {
        if amount.sign == "+" || amount.sign == "＋" {
            return .income
        }
        if amount.sign == "-" || amount.sign == "−" || amount.sign == "－" {
            return .expense
        }

        let incomeKeywords = ["你已收款", "收款成功", "资金正在转入", "已收款"]
        if incomeKeywords.contains(where: fullText.contains) || incomeKeywords.contains(where: context.contains) {
            return .income
        }

        return .expense
    }

    private static func score(
        line: RecognizedLine,
        context: String,
        fullText: String,
        value: Decimal
    ) -> Double {
        let text = line.normalizedText
        var score = 0.15
        let isPaymentSuccessScreen = fullText.contains("支付成功")
            || fullText.contains("转账成功")
            || fullText.contains("付款成功")
            || fullText.contains("交易成功")
            || fullText.contains("你已收款")
            || fullText.contains("收款成功")
            || fullText.contains("资金正在转入")

        let positiveKeywords = [
            "实付", "支付", "付款", "合计", "总计", "金额", "收款", "已支付", "订单金额",
            "转账成功", "支付成功", "交易成功", "你已收款", "收款成功", "资金正在转入"
        ]
        let strongestKeywords = [
            "实付", "实际支付", "已支付", "付款金额", "支付成功", "转账成功", "交易成功",
            "你已收款", "收款成功", "资金正在转入"
        ]
        let negativeKeywords = [
            "余额", "优惠", "立减", "券", "积分", "订单号", "单号", "手机号", "验证码",
            "时间", "日期", "原价", "广告", "红包", "最高", "领取", "一键领", "抽免单",
            "商户单号", "交易单号", "预约转账", "回首页"
        ]

        if positiveKeywords.contains(where: context.contains) {
            score += 0.24
        }

        if strongestKeywords.contains(where: context.contains) {
            score += 0.25
        }

        if text.contains("¥") || text.contains("￥") || text.localizedCaseInsensitiveContains("RMB") {
            score += 0.22
        }

        if text.contains("+") || text.contains("＋") {
            score += 0.18
        }

        if text.contains("-") || text.contains("−") || text.contains("－") {
            score += 0.16
        }

        if isPaymentSuccessScreen {
            if line.topY > 0.10 && line.topY < 0.42 {
                score += 0.22
            }
            if abs(line.centerX - 0.5) < 0.20 {
                score += 0.16
            }
            if line.boundingBox.height > 0.025 {
                score += 0.18
            }
        }

        if negativeKeywords.contains(where: text.contains) {
            score -= 0.55
        } else if negativeKeywords.contains(where: context.contains),
                  !strongestKeywords.contains(where: context.contains) {
            score -= 0.25
        }

        if text.contains(":") || text.contains("：") {
            score -= 0.35
        }

        if line.topY < 0.08 {
            score -= 0.25
        }

        if line.topY > 0.65 {
            score -= 0.25
        }

        if value >= 1 && value <= 100_000 {
            score += 0.08
        }

        return max(0, min(score, 1))
    }

    private static func nearbyText(lines: [RecognizedLine], index: Int) -> String {
        let lower = max(0, index - 2)
        let upper = min(lines.count - 1, index + 2)
        return lines[lower...upper].map(\.normalizedText).joined(separator: " ")
    }

    fileprivate static func normalize(_ text: String) -> String {
        text
            .replacingOccurrences(of: "，", with: ",")
            .replacingOccurrences(of: "。", with: ".")
            .replacingOccurrences(of: "￥", with: "¥")
            .replacingOccurrences(of: "＋", with: "+")
            .replacingOccurrences(of: "－", with: "-")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func looksLikeDateOrTime(_ raw: String, line: String) -> Bool {
        let compact = raw.replacingOccurrences(of: ",", with: "")
        if compact.count >= 8, compact.allSatisfy(\.isNumber) {
            return true
        }
        if line.contains(":") || line.contains("：") {
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

private struct RecognizedLine: Hashable {
    var text: String
    var boundingBox: CGRect

    var normalizedText: String {
        ScreenshotOCRService.normalize(text)
    }

    var topY: Double {
        Double(1 - boundingBox.maxY)
    }

    var centerX: Double {
        Double(boundingBox.midX)
    }
}

private struct ExtractedAmount: Hashable {
    var amount: Decimal
    var sign: String
}

private struct AmountCandidate: Hashable {
    var amount: Decimal
    var score: Double
    var topY: Double
    var centerX: Double
    var text: String
    var suggestedKind: TransactionKind
}
