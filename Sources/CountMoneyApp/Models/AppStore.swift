import Foundation
import SwiftUI

@Observable
final class AppStore {
    private var database: SQLiteDatabase?

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
    var startupError: String?

    var overview: MonthlyOverview {
        MonthlyOverview(transactions: transactions)
    }

    var assetOverview: AssetOverview {
        let usableAssets = assets.filter { $0.kind != .fund }
        let holdings = usableAssets
            .filter { !$0.isDebtLike }
            .map(\.balance)
            .reduce(0, +)
        let fundHoldings = assets
            .filter { $0.kind == .fund }
            .map(\.fundCurrentValue)
            .reduce(0, +)
        let debt = usableAssets
            .filter(\.isDebtLike)
            .map { max($0.balance, 0) + $0.totalRepayment }
            .reduce(0, +)

        return AssetOverview(holdings: holdings, fundHoldings: fundHoldings, debt: debt)
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
        let savedAppearance = UserDefaults.standard.string(forKey: "appearance")
            .flatMap(AppAppearance.init(rawValue:))
        appearance = savedAppearance ?? .system

        do {
            let database = try SQLiteDatabase()
            self.database = database
            let snapshot = try database.loadSnapshot()
            let loadedCategories = snapshot.categories

            if loadedCategories.isEmpty {
                expenseCategories = PreviewData.expenseCategories
                incomeCategories = PreviewData.incomeCategories
                assets = PreviewData.assets
                transactions = []
                try persistCategories(expenseCategories + incomeCategories)
                try persistAssets(assets)
            } else {
                expenseCategories = loadedCategories
                    .filter { $0.kind == .expense }
                    .sorted { $0.sortOrder < $1.sortOrder }
                incomeCategories = loadedCategories
                    .filter { $0.kind == .income }
                    .sorted { $0.sortOrder < $1.sortOrder }
                assets = snapshot.assets
                transactions = snapshot.transactions
                try ensureRecommendedAssets()
            }
            startupError = nil
        } catch {
            self.database = nil
            expenseCategories = PreviewData.expenseCategories
            incomeCategories = PreviewData.incomeCategories
            assets = PreviewData.assets
            transactions = []
            startupError = error.localizedDescription
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

    func addCategory(name: String, kind: CategoryKind) throws {
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

        var nextExpenseCategories = expenseCategories
        var nextIncomeCategories = incomeCategories
        switch kind {
        case .expense:
            nextExpenseCategories.append(category)
        case .income:
            nextIncomeCategories.append(category)
        }
        try persistCategories(nextExpenseCategories + nextIncomeCategories)
        expenseCategories = nextExpenseCategories
        incomeCategories = nextIncomeCategories
    }

    func deleteCategory(_ category: MoneyCategory) throws {
        guard !category.isSystemPreset else { return }
        guard !transactions.contains(where: { $0.category.id == category.id }) else { return }

        var nextExpenseCategories = expenseCategories
        var nextIncomeCategories = incomeCategories
        switch category.kind {
        case .expense:
            nextExpenseCategories.removeAll { $0.id == category.id }
        case .income:
            nextIncomeCategories.removeAll { $0.id == category.id }
        }
        try persistCategories(nextExpenseCategories + nextIncomeCategories)
        expenseCategories = nextExpenseCategories
        incomeCategories = nextIncomeCategories
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
    ) throws {
        let usesInstallmentPlan = kind == .expense
            && (installmentMonths ?? 0) > 0
            && (asset(for: account)?.kind.supportsInstallment ?? false)

        var nextTransactions = transactions
        var nextAssets = assets

        nextTransactions.insert(
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

        let changedAssetBalance = applyTransactionBalanceChange(
            to: &nextAssets,
            kind: kind,
            amount: amount,
            accountID: account.id,
            usesInstallmentPlan: usesInstallmentPlan
        )

        if usesInstallmentPlan, let installmentMonths {
            addRepaymentPlan(to: &nextAssets, accountID: account.id, amount: amount, months: installmentMonths)
        }

        if changedAssetBalance || usesInstallmentPlan {
            try persistLedger(transactions: nextTransactions, assets: nextAssets)
            assets = nextAssets
        } else {
            try persistTransactions(nextTransactions)
        }
        transactions = nextTransactions
        quickEntryDraft = nil
    }

    func addAsset(name: String, kind: AssetKind) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        var nextAssets = assets
        nextAssets.append(
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
        try persistAssets(nextAssets)
        assets = nextAssets
    }

    func deleteAsset(_ asset: AssetItem) throws {
        var nextAssets = assets
        nextAssets.removeAll { $0.id == asset.id }
        try persistAssets(nextAssets)
        assets = nextAssets
    }

    func updateAsset(_ asset: AssetItem) throws {
        var nextAssets = assets
        guard let index = nextAssets.firstIndex(where: { $0.id == asset.id }) else { return }
        nextAssets[index] = asset
        try persistAssets(nextAssets)
        assets = nextAssets
    }

    func addFundActivity(assetID: UUID, kind: FundActivityKind, amount: Decimal, note: String) throws {
        var nextAssets = assets
        guard let index = nextAssets.firstIndex(where: { $0.id == assetID }),
              nextAssets[index].kind == .fund
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

        nextAssets[index].fundActivities.insert(record, at: 0)

        switch kind {
        case .valuation:
            nextAssets[index].fundMarketValue = (nextAssets[index].fundMarketValue ?? 0) + amount
        case .investment:
            nextAssets[index].fundCost = (nextAssets[index].fundCost ?? 0) + amount
        }
        nextAssets[index].balance = nextAssets[index].fundCurrentValue

        try persistAssets(nextAssets)
        assets = nextAssets
    }

    func asset(for account: MoneyAccount) -> AssetItem? {
        assets.first { $0.id == account.id }
    }

    func exportData() throws -> Data {
        let records = transactions.map(makeExportRecord)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(records)
    }

    func importData(_ data: Data) throws {
        let records = try JSONDecoder().decode([TransactionExportRecord].self, from: data)
        let nextTransactions = try records.map(makeTransaction)
        try persistTransactions(nextTransactions)
        transactions = nextTransactions
        quickEntryDraft = nil
    }

    private func makeExportRecord(from transaction: MoneyTransaction) -> TransactionExportRecord {
        let asset = assets.first { $0.id == transaction.account.id }
        return TransactionExportRecord(
            id: transaction.id.uuidString,
            kind: transaction.kind.rawValue,
            title: transaction.title,
            categoryPresetKey: transaction.category.presetKey,
            accountID: transaction.account.id.uuidString,
            accountName: transaction.account.name,
            accountKind: asset?.kind.rawValue,
            accountSymbolName: transaction.account.symbolName,
            amount: NSDecimalNumber(decimal: transaction.amount).stringValue,
            occurredAt: ISO8601DateFormatter().string(from: transaction.occurredAt)
        )
    }

    private func makeTransaction(from record: TransactionExportRecord) throws -> MoneyTransaction {
        guard
            let id = UUID(uuidString: record.id),
            let kind = TransactionKind(rawValue: record.kind),
            let occurredAt = ISO8601DateFormatter().date(from: record.occurredAt)
        else {
            throw AppStoreFailure.invalidImportRecord
        }

        guard let amount = Decimal.moneyString(record.amount) else {
            throw AppStoreFailure.invalidImportAmount(record.amount)
        }

        return MoneyTransaction(
            id: id,
            kind: kind,
            title: record.title,
            category: category(record.categoryPresetKey, fallbackKind: kind),
            account: account(for: record),
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

    private func account(for record: TransactionExportRecord) -> MoneyAccount {
        if let accountID = record.accountID.flatMap(UUID.init(uuidString:)),
           let asset = assets.first(where: { $0.id == accountID }) {
            return MoneyAccount(
                id: asset.id,
                name: asset.name,
                symbolName: asset.kind.symbolName,
                balance: asset.balance
            )
        }

        if let accountKind = record.accountKind.flatMap(AssetKind.init(rawValue:)),
           let asset = assets.first(where: { $0.name == record.accountName && $0.kind == accountKind }) {
            return MoneyAccount(
                id: asset.id,
                name: asset.name,
                symbolName: asset.kind.symbolName,
                balance: asset.balance
            )
        }

        if let asset = assets.first(where: { $0.name == record.accountName }) {
            return MoneyAccount(
                id: asset.id,
                name: asset.name,
                symbolName: asset.kind.symbolName,
                balance: asset.balance
            )
        }

        return MoneyAccount(
            id: record.accountID.flatMap(UUID.init(uuidString:)) ?? UUID(),
            name: record.accountName,
            symbolName: record.accountSymbolName ?? "creditcard.fill",
            balance: 0
        )
    }

    private func persistCategories(_ categories: [MoneyCategory]) throws {
        guard let database else { throw AppStoreFailure.databaseUnavailable }
        try database.saveCategories(categories)
    }

    private func persistTransactions(_ transactions: [MoneyTransaction]) throws {
        guard let database else { throw AppStoreFailure.databaseUnavailable }
        try database.saveTransactions(transactions)
    }

    private func persistAssets(_ assets: [AssetItem]) throws {
        guard let database else { throw AppStoreFailure.databaseUnavailable }
        try database.saveAssets(assets)
    }

    private func persistLedger(transactions: [MoneyTransaction], assets: [AssetItem]) throws {
        guard let database else { throw AppStoreFailure.databaseUnavailable }
        try database.saveLedger(transactions: transactions, assets: assets)
    }

    private func applyTransactionBalanceChange(
        to assets: inout [AssetItem],
        kind: TransactionKind,
        amount: Decimal,
        accountID: UUID,
        usesInstallmentPlan: Bool
    ) -> Bool {
        guard kind != .transfer,
              let assetIndex = assets.firstIndex(where: { $0.id == accountID })
        else {
            return false
        }

        if assets[assetIndex].kind.supportsRepayment {
            if usesInstallmentPlan {
                return false
            }

            switch kind {
            case .expense:
                assets[assetIndex].balance += amount
            case .income:
                assets[assetIndex].balance -= amount
            case .transfer:
                return false
            }
        } else {
            switch kind {
            case .expense:
                assets[assetIndex].balance -= amount
            case .income:
                assets[assetIndex].balance += amount
            case .transfer:
                return false
            }
        }

        return true
    }

    private func addRepaymentPlan(to assets: inout [AssetItem], accountID: UUID, amount: Decimal, months: Int) {
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
    }

    private func ensureRecommendedAssets() throws {
        var changed = false
        let existingKinds = Set(assets.map(\.kind))

        for asset in PreviewData.assets where !existingKinds.contains(asset.kind) {
            assets.append(asset)
            changed = true
        }

        if changed {
            try persistAssets(assets)
        }
    }

    private static func makeEmptyRepayments() -> [RepaymentMonth] {
        (0..<24).map {
            RepaymentMonth(id: UUID(), monthOffset: $0, amount: 0)
        }
    }
}

enum AppStoreFailure: LocalizedError {
    case databaseUnavailable
    case invalidImportRecord
    case invalidImportAmount(String)
    case invalidMoneyInput(String)

    var errorDescription: String? {
        switch self {
        case .databaseUnavailable:
            "本地数据库不可用，数据没有保存成功"
        case .invalidImportRecord:
            "导入文件里有无法识别的账目记录"
        case let .invalidImportAmount(value):
            "导入文件里有无法识别的金额：\(value)"
        case let .invalidMoneyInput(field):
            "\(field) 的金额格式不正确"
        }
    }
}
