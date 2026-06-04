import Foundation

enum QuickEntryShortcutStore {
    private static let pendingDraftKey = "quickEntryShortcut.pendingDraft"
    private static let shouldOpenEntryKey = "quickEntryShortcut.shouldOpenEntry"

    static func savePendingDraft(_ draft: QuickEntryDraft) throws {
        let payload = ShortcutQuickEntryDraft(draft: draft)
        let data = try JSONEncoder().encode(payload)
        let defaults = UserDefaults.standard
        defaults.set(data, forKey: pendingDraftKey)
        defaults.set(true, forKey: shouldOpenEntryKey)
    }

    static func takePendingDraft() -> QuickEntryDraft? {
        let defaults = UserDefaults.standard
        guard let data = defaults.data(forKey: pendingDraftKey),
              let payload = try? JSONDecoder().decode(ShortcutQuickEntryDraft.self, from: data)
        else {
            return nil
        }
        defaults.removeObject(forKey: pendingDraftKey)
        return payload.makeDraft()
    }

    static func shouldOpenEntry() -> Bool {
        UserDefaults.standard.bool(forKey: shouldOpenEntryKey)
    }

    static func clearOpenEntryRequest() {
        UserDefaults.standard.set(false, forKey: shouldOpenEntryKey)
    }
}

private struct ShortcutQuickEntryDraft: Codable {
    var id: UUID
    var candidateAmount: String
    var candidateAmounts: [String]
    var suggestedKind: String
    var recognizedTextPreview: String
    var confidence: Double
    var createdAt: Date

    init(draft: QuickEntryDraft) {
        id = draft.id
        candidateAmount = Self.text(from: draft.candidateAmount)
        candidateAmounts = draft.candidateAmounts.map(Self.text)
        suggestedKind = draft.suggestedKind.rawValue
        recognizedTextPreview = draft.recognizedTextPreview
        confidence = draft.confidence
        createdAt = draft.createdAt
    }

    func makeDraft() -> QuickEntryDraft? {
        guard let amount = Decimal.moneyString(candidateAmount),
              let kind = TransactionKind(rawValue: suggestedKind)
        else {
            return nil
        }

        return QuickEntryDraft(
            id: id,
            candidateAmount: amount,
            candidateAmounts: candidateAmounts.compactMap(Decimal.moneyString),
            suggestedKind: kind,
            recognizedTextPreview: recognizedTextPreview,
            confidence: confidence,
            createdAt: createdAt
        )
    }

    private static func text(from value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }
}
