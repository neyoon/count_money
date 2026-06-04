import Foundation
import SwiftUI

@Observable
final class AppStore {
    private let database: SQLiteDatabase?

    var appearance: AppAppearance {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: "appearance")
        }
    }

    var transactions: [MoneyTransaction]
    var expenseCategories: [MoneyCategory]
    var incomeCategories: [MoneyCategory]
    var assets: [AssetItem]
    var quickEntryDraft: QuickEntryDraft?

    var overview: MonthlyOverview {
        MonthlyOverview(transactions: transactions)
    }

    var assetOverview: AssetOverview {
        let usableAssets = assets.filter { $0.kind != .fund }
        let holdings = usableAssets
            .filter { !$0.isDebtLike }
            .map(\.balance)
            .reduce(0, +)
        let debt = usableAssets
            .filter(\.isDebtLike)
            .map(\.totalRepayment)
            .reduce(0, +)

        return AssetOverview(holdings: holdings, debt: debt)
    }

    var paymentAccounts: [MoneyAccount] {
        assets
            .filter { $0.kind.canPayTransaction }
            .map { asset in
                MoneyAccount(
                    id: asset.id,
                    name: asset.name,
                    symbolName: asset.kind.symbolName,
                    balance: asset.balance
                )
            }
    }

    init() {
        database = try? SQLiteDatabase()

        let savedAppearance = UserDefaults.standard.string(forKey: "appearance")
            .flatMap(AppAppearance.init(rawValue:))
        appearance = savedAppearance ?? .system

        let snapshot = try? database?.loadSnapshot()
        let loadedCategories = snapshot?.categories ?? []

        if loadedCategories.isEmpty {
            expenseCategories = PreviewData.expenseCategories
            incomeCategories = PreviewData.incomeCategories
            assets = PreviewData.assets
            transactions = []
            persistCategories()
            persistAssets()
        } else {
            expenseCategories = loadedCategories
                .filter { $0.kind == .expense }
                .sorted { $0.sortOrder < $1.sortOrder }
            incomeCategories = loadedCategories
                .filter { $0.kind == .income }
                .sorted { $0.sortOrder < $1.sortOrder }
            assets = snapshot?.assets ?? PreviewData.assets
            transactions = snapshot?.transactions ?? []
            ensureRecommendedAssets()
        }
    }

    func categories(for kind: TransactionKind) -> [MoneyCategory] {
        switch kind {
        case .expense:
            expenseCategories
        case .income:
            incomeCategories
        case .transfer:
            []
        }
    }

    func addCategory(name: String, kind: CategoryKind) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let category = MoneyCategory(
            id: UUID(),
            presetKey: "custom_\(UUID().uuidString)",
            name: trimmed,
            kind: kind,
            symbolName: "tag.fill",
            color: AppColor.primary,
            sortOrder: (kind == .expense ? expenseCategories.count : incomeCategories.count) * 10 + 1000,
            isSystemPreset: false
        )

        switch kind {
        case .expense:
            expenseCategories.append(category)
        case .income:
            incomeCategories.append(category)
        }
        persistCategories()
    }

    func deleteCategory(_ category: MoneyCategory) {
        guard !category.isSystemPreset else { return }
        guard !transactions.contains(where: { $0.category.id == category.id }) else { return }

        switch category.kind {
        case .expense:
            expenseCategories.removeAll { $0.id == category.id }
        case .income:
            incomeCategories.removeAll { $0.id == category.id }
        }
        persistCategories()
    }

    func startManualEntry() {
        quickEntryDraft = nil
    }

    func applyQuickEntryDraft(_ draft: QuickEntryDraft) {
        quickEntryDraft = draft
    }

    func addTransaction(
        kind: TransactionKind,
        amount: Decimal,
        category: MoneyCategory,
        account: MoneyAccount,
        title: String,
        installmentMonths: Int? = nil
    ) {
        transactions.insert(
            MoneyTransaction(
                id: UUID(),
                kind: kind,
                title: title,
                category: category,
                account: account,
                amount: amount,
                occurredAt: Date()
            ),
            at: 0
        )
        quickEntryDraft = nil
        persistTransactions()

        if kind == .expense,
           let installmentMonths,
           installmentMonths > 0 {
            addRepaymentPlan(accountID: account.id, amount: amount, months: installmentMonths)
        }
    }

    func addAsset(name: String, kind: AssetKind) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        assets.append(
            AssetItem(
                id: UUID(),
                name: trimmed,
                kind: kind,
                balance: 0,
                repayments: Self.makeEmptyRepayments(),
                fundCost: kind == .fund ? 0 : nil,
                fundMarketValue: kind == .fund ? 0 : nil
            )
        )
        persistAssets()
    }

    func deleteAsset(_ asset: AssetItem) {
        assets.removeAll { $0.id == asset.id }
        persistAssets()
    }

    func updateAsset(_ asset: AssetItem) {
        guard let index = assets.firstIndex(where: { $0.id == asset.id }) else { return }
        assets[index] = asset
        persistAssets()
    }

    func addFundActivity(assetID: UUID, kind: FundActivityKind, amount: Decimal, note: String) {
        guard let index = assets.firstIndex(where: { $0.id == assetID }),
              assets[index].kind == .fund
        else {
            return
        }

        let trimmedNote = note.trimmingCharacters(in: .whitespacesAndNewlines)
        let record = FundActivity(
            id: UUID(),
            kind: kind,
            amount: amount,
            occurredAt: Date(),
            note: trimmedNote
        )

        assets[index].fundActivities.insert(record, at: 0)

        switch kind {
        case .valuation:
            assets[index].fundMarketValue = (assets[index].fundMarketValue ?? 0) + amount
            assets[index].balance = assets[index].fundMarketValue ?? 0
        case .investment:
            assets[index].fundCost = (assets[index].fundCost ?? 0) + amount
        }

        persistAssets()
    }

    func asset(for account: MoneyAccount) -> AssetItem? {
        assets.first { $0.id == account.id }
    }

    func exportData() throws -> Data {
        let records = transactions.map(\.exportRecord)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }

    func importData(_ data: Data) throws {
        let records = try JSONDecoder().decode([TransactionExportRecord].self, from: data)
        transactions = records.compactMap(makeTransaction)
        quickEntryDraft = nil
        persistTransactions()
    }

    private func makeTransaction(from record: TransactionExportRecord) -> MoneyTransaction? {
        guard
            let id = UUID(uuidString: record.id),
            let kind = TransactionKind(rawValue: record.kind),
            let amount = Decimal.moneyString(record.amount),
            let occurredAt = ISO8601DateFormatter().date(from: record.occurredAt)
        else {
            return nil
        }

        return MoneyTransaction(
            id: id,
            kind: kind,
            title: record.title,
            category: category(record.categoryPresetKey, fallbackKind: kind),
            account: PreviewData.wallet,
            amount: amount,
            occurredAt: occurredAt
        )
    }

    private func category(_ presetKey: String, fallbackKind: TransactionKind) -> MoneyCategory {
        let categories = expenseCategories + incomeCategories
        if let category = categories.first(where: { $0.presetKey == presetKey }) {
            return category
        }
        return PreviewData.category(presetKey, fallbackKind: fallbackKind)
    }

    private func persistCategories() {
        try? database?.saveCategories(expenseCategories + incomeCategories)
    }

    private func persistTransactions() {
        try? database?.saveTransactions(transactions)
    }

    private func persistAssets() {
        try? database?.saveAssets(assets)
    }

    private func addRepaymentPlan(accountID: UUID, amount: Decimal, months: Int) {
        guard let assetIndex = assets.firstIndex(where: { $0.id == accountID }),
              assets[assetIndex].kind.supportsInstallment
        else {
            return
        }

        let cappedMonths = min(max(months, 1), 24)

        for monthIndex in 0..<cappedMonths {
            let offset = monthIndex + 1
            guard let repaymentIndex = assets[assetIndex].repayments.firstIndex(where: { $0.monthOffset == offset }) else {
                continue
            }
            assets[assetIndex].repayments[repaymentIndex].amount += amount
        }

        persistAssets()
    }

    private func ensureRecommendedAssets() {
        var changed = false
        let existingKinds = Set(assets.map(\.kind))

        for asset in PreviewData.assets where !existingKinds.contains(asset.kind) {
            assets.append(asset)
            changed = true
        }

        if changed {
            persistAssets()
        }
    }

    private static func makeEmptyRepayments() -> [RepaymentMonth] {
        (0..<24).map {
            RepaymentMonth(id: UUID(), monthOffset: $0, amount: 0)
        }
    }
}
