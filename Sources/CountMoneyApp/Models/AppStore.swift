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

    var initializationMode: Bool {
        didSet {
            UserDefaults.standard.set(initializationMode, forKey: "initializationMode")
        }
    }

    var historyMode: Bool {
        didSet {
            UserDefaults.standard.set(historyMode, forKey: "historyMode")
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

    var ledgerAssets: [AssetItem] {
        LedgerCalculator.assetsWithLedgerBalances(assets: assets, transactions: transactions)
    }

    var assetOverview: AssetOverview {
        AssetOverview.make(from: ledgerAssets)
    }

    var paymentAccounts: [MoneyAccount] {
        ledgerAssets
            .filter { $0.kind.canSpend }
            .map { asset in
                MoneyAccount(
                    id: asset.id,
                    name: asset.name,
                    symbolName: asset.kind.symbolName,
                    balance: asset.balance
                )
            }
    }

    var repaymentAccounts: [MoneyAccount] {
        ledgerAssets
            .filter { $0.kind.isDebtAccount }
            .map { asset in
                MoneyAccount(
                    id: asset.id,
                    name: asset.name,
                    symbolName: asset.kind.symbolName,
                    balance: asset.balance
                )
            }
    }

    var repaymentPaymentAccounts: [MoneyAccount] {
        ledgerAssets
            .filter { $0.kind.canFundRepayment }
            .map { asset in
                MoneyAccount(
                    id: asset.id,
                    name: asset.name,
                    symbolName: asset.kind.symbolName,
                    balance: asset.balance
                )
            }
    }

    init(database providedDatabase: SQLiteDatabase? = nil) {
        let savedAppearance = UserDefaults.standard.string(forKey: "appearance")
            .flatMap(AppAppearance.init(rawValue:))
        appearance = savedAppearance ?? .system
        initializationMode = UserDefaults.standard.bool(forKey: "initializationMode")
        historyMode = UserDefaults.standard.bool(forKey: "historyMode")

        do {
            let database: SQLiteDatabase
            if let providedDatabase {
                database = providedDatabase
            } else {
                database = try SQLiteDatabase()
            }
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
                try ensureRecommendedAssetsAndNames()
                try ensureRecommendedCategories()
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
        case .fundProfit:
            []
        }
    }

    func addCategory(name: String, kind: CategoryKind, symbolName: String = "tag.fill") throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        let targetCategories = kind == .expense ? expenseCategories : incomeCategories
        let category = MoneyCategory(
            id: UUID(),
            presetKey: "custom_\(UUID().uuidString)",
            name: trimmed,
            kind: kind,
            symbolName: symbolName,
            color: AppColor.primary,
            sortOrder: ((targetCategories.map(\.sortOrder).min() ?? 10) - 10),
            isSystemPreset: false
        )

        var nextExpenseCategories = expenseCategories
        var nextIncomeCategories = incomeCategories
        switch kind {
        case .expense:
            nextExpenseCategories.append(category)
            nextExpenseCategories.sort { $0.sortOrder < $1.sortOrder }
        case .income:
            nextIncomeCategories.append(category)
            nextIncomeCategories.sort { $0.sortOrder < $1.sortOrder }
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
        paymentAccount: MoneyAccount? = nil,
        installmentMonths: Int? = nil,
        occurredAt: Date = Date()
    ) throws {
        guard kind != .fundProfit else { return }

        var nextTransactions = transactions
        var nextAssets = assets
        let transaction = makeTransaction(
            id: UUID(),
            kind: kind,
            amount: amount,
            category: category,
            account: account,
            title: title,
            paymentAccount: paymentAccount,
            installmentMonths: installmentMonths,
            occurredAt: occurredAt,
            assets: &nextAssets
        )

        nextTransactions.append(transaction)
        nextTransactions.sort { $0.occurredAt > $1.occurredAt }

        if transaction.repaymentAdjustments.isEmpty {
            try persistTransactions(nextTransactions)
        } else {
            try persistLedger(transactions: nextTransactions, assets: nextAssets)
            assets = nextAssets
        }
        transactions = nextTransactions
        quickEntryDraft = nil
    }

    func updateTransaction(
        _ original: MoneyTransaction,
        kind: TransactionKind,
        amount: Decimal,
        category: MoneyCategory,
        account: MoneyAccount,
        title: String,
        paymentAccount: MoneyAccount? = nil,
        installmentMonths: Int? = nil,
        occurredAt: Date
    ) throws {
        guard kind != .fundProfit else { return }

        var nextTransactions = transactions
        guard nextTransactions.contains(where: { $0.id == original.id }) else { return }

        var nextAssets = assets
        nextTransactions.removeAll { $0.id == original.id }
        _ = reverseRepaymentEffects(for: original, in: &nextAssets)

        let updatedTransaction = makeTransaction(
            id: original.id,
            kind: kind,
            amount: amount,
            category: category,
            account: account,
            title: title,
            paymentAccount: paymentAccount,
            installmentMonths: installmentMonths,
            occurredAt: occurredAt,
            assets: &nextAssets
        )

        nextTransactions.append(updatedTransaction)
        nextTransactions.sort { $0.occurredAt > $1.occurredAt }
        try persistLedger(transactions: nextTransactions, assets: nextAssets)
        assets = nextAssets
        transactions = nextTransactions
        quickEntryDraft = nil
    }

    func deleteTransaction(_ transaction: MoneyTransaction) throws {
        var nextTransactions = transactions
        var nextAssets = assets
        nextTransactions.removeAll { $0.id == transaction.id }

        let changedAssets = reverseRepaymentEffects(for: transaction, in: &nextAssets)
        if changedAssets {
            try persistLedger(transactions: nextTransactions, assets: nextAssets)
            assets = nextAssets
        } else {
            try persistTransactions(nextTransactions)
        }
        transactions = nextTransactions
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
        guard !transactions.contains(where: { $0.account.id == asset.id }) else {
            throw AppStoreFailure.assetInUse(asset.name)
        }

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

    func addFundActivity(assetID: UUID, kind: FundActivityKind, amount: Decimal, note: String, occurredAt: Date = Date()) throws {
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
            occurredAt: occurredAt,
            note: trimmedNote
        )

        nextAssets[index].fundActivities.insert(record, at: 0)

        switch kind {
        case .valuation:
            nextAssets[index].fundMarketValue = (nextAssets[index].fundMarketValue ?? 0) + amount
        case .investment:
            nextAssets[index].fundCost = (nextAssets[index].fundCost ?? 0) + amount
        }
        if kind == .investment,
           (nextAssets[index].fundMarketValue ?? 0) == 0 {
            nextAssets[index].fundMarketValue = nextAssets[index].fundCost
        }
        nextAssets[index].balance = nextAssets[index].fundCurrentValue

        try persistAssets(nextAssets)
        assets = nextAssets
    }

    func addFundProfit(assetID: UUID, amount: Decimal, note: String, occurredAt: Date = Date()) throws {
        try addFundActivity(assetID: assetID, kind: .valuation, amount: amount, note: note, occurredAt: occurredAt)
        quickEntryDraft = nil
    }

    func asset(for account: MoneyAccount) -> AssetItem? {
        ledgerAssets.first { $0.id == account.id }
    }

    func historySnapshot(on date: Date) -> HistorySnapshot {
        let calendar = Calendar.current
        let cutoff = calendar.endOfDay(for: date)
        let snapshotTransactions = transactions.filter { $0.occurredAt <= cutoff }
        let snapshotAssets = assetsForHistorySnapshot(cutoff: cutoff, transactions: snapshotTransactions)

        return HistorySnapshot(
            date: cutoff,
            overview: MonthlyOverview(transactions: snapshotTransactions, calendar: calendar, now: cutoff),
            assetOverview: AssetOverview.make(from: snapshotAssets),
            assets: snapshotAssets
        )
    }

    func currentHistorySnapshot() -> HistorySnapshot {
        HistorySnapshot(
            date: Date(),
            overview: overview,
            assetOverview: assetOverview,
            assets: ledgerAssets
        )
    }

    func historyComparison(from date: Date) -> HistoryComparison {
        let historical = historySnapshot(on: date)
        let current = currentHistorySnapshot()
        let historicalAssets = Dictionary(uniqueKeysWithValues: historical.assets.map { ($0.id, $0) })

        let assetChanges = current.assets.compactMap { asset -> AssetHistoryChange? in
            let beforeAsset = historicalAssets[asset.id]
            let before = netContribution(of: beforeAsset)
            let after = netContribution(of: asset)
            guard before != after else { return nil }

            return AssetHistoryChange(
                id: asset.id,
                name: asset.name,
                symbolName: asset.kind.symbolName,
                before: before,
                after: after
            )
        }
        .sorted { abs($0.change.doubleValue) > abs($1.change.doubleValue) }

        return HistoryComparison(
            historical: historical,
            current: current,
            assetChanges: Array(assetChanges.prefix(3))
        )
    }

    func exportData() throws -> Data {
        let exportFile = LedgerExportFile(
            version: 2,
            exportedAt: ISO8601DateFormatter().string(from: Date()),
            categories: (expenseCategories + incomeCategories).map(makeExportRecord),
            assets: assets.map(makeExportRecord),
            transactions: transactions.map(makeExportRecord)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(exportFile)
    }

    func importData(_ data: Data) throws {
        let decoder = JSONDecoder()
        if let exportFile = try? decoder.decode(LedgerExportFile.self, from: data) {
            try importLedger(exportFile)
            return
        }

        let records = try decoder.decode([TransactionExportRecord].self, from: data)
        try importTransactions(records)
    }

    func clearAllData() throws {
        let defaultExpenseCategories = PreviewData.expenseCategories
        let defaultIncomeCategories = PreviewData.incomeCategories
        let defaultAssets = PreviewData.assets
        let emptyTransactions: [MoneyTransaction] = []

        try persistCategories(defaultExpenseCategories + defaultIncomeCategories)
        try persistLedger(transactions: emptyTransactions, assets: defaultAssets)

        expenseCategories = defaultExpenseCategories
        incomeCategories = defaultIncomeCategories
        assets = defaultAssets
        transactions = emptyTransactions
        quickEntryDraft = nil
    }

    private func importLedger(_ exportFile: LedgerExportFile) throws {
        var nextExpenseCategories = expenseCategories
        var nextIncomeCategories = incomeCategories
        mergeCategories(
            exportFile.categories,
            expenseCategories: &nextExpenseCategories,
            incomeCategories: &nextIncomeCategories
        )

        var nextAssets = assets
        let importedAssets = try exportFile.assets.map(makeAsset)
        mergeAssets(importedAssets, into: &nextAssets)

        var nextTransactions = transactions
        try appendTransactions(
            exportFile.transactions,
            assets: &nextAssets,
            transactions: &nextTransactions,
            categories: nextExpenseCategories + nextIncomeCategories
        )

        nextTransactions.sort { $0.occurredAt > $1.occurredAt }
        try persistCategories(nextExpenseCategories + nextIncomeCategories)
        try persistLedger(transactions: nextTransactions, assets: nextAssets)
        expenseCategories = nextExpenseCategories
        incomeCategories = nextIncomeCategories
        assets = nextAssets
        transactions = nextTransactions
        quickEntryDraft = nil
    }

    private func importTransactions(_ records: [TransactionExportRecord]) throws {
        var nextAssets = assets
        var nextTransactions = transactions
        try appendTransactions(records, assets: &nextAssets, transactions: &nextTransactions)

        nextTransactions.sort { $0.occurredAt > $1.occurredAt }
        try persistLedger(transactions: nextTransactions, assets: nextAssets)
        assets = nextAssets
        transactions = nextTransactions
        quickEntryDraft = nil
    }

    private func appendTransactions(
        _ records: [TransactionExportRecord],
        assets: inout [AssetItem],
        transactions: inout [MoneyTransaction],
        categories: [MoneyCategory]? = nil
    ) throws {
        var knownTransactionIDs = Set(transactions.map(\.id))

        for record in records {
            guard let recordID = UUID(uuidString: record.id) else {
                throw AppStoreFailure.invalidImportRecord
            }
            guard !knownTransactionIDs.contains(recordID) else { continue }

            let transaction = try makeTransaction(from: record, assets: &assets, categories: categories)
            transactions.append(transaction)
            knownTransactionIDs.insert(transaction.id)
        }
    }

    private func makeExportRecord(from category: MoneyCategory) -> CategoryExportRecord {
        CategoryExportRecord(
            id: category.id.uuidString,
            presetKey: category.presetKey,
            name: category.name,
            kind: category.kind.rawValue,
            symbolName: category.symbolName,
            sortOrder: category.sortOrder,
            isSystemPreset: category.isSystemPreset
        )
    }

    private func makeExportRecord(from asset: AssetItem) -> AssetExportRecord {
        AssetExportRecord(
            id: asset.id.uuidString,
            name: asset.name,
            kind: asset.kind.rawValue,
            balance: decimalText(asset.balance),
            repayments: asset.repayments.map(makeExportRecord),
            fundCost: asset.fundCost.map(decimalText),
            fundMarketValue: asset.fundMarketValue.map(decimalText),
            fundActivities: asset.fundActivities.map(makeExportRecord)
        )
    }

    private func makeExportRecord(from repayment: RepaymentMonth) -> RepaymentExportRecord {
        RepaymentExportRecord(
            id: repayment.id.uuidString,
            monthOffset: repayment.monthOffset,
            amount: decimalText(repayment.amount)
        )
    }

    private func makeExportRecord(from activity: FundActivity) -> FundActivityExportRecord {
        FundActivityExportRecord(
            id: activity.id.uuidString,
            kind: activity.kind.rawValue,
            amount: decimalText(activity.amount),
            occurredAt: ISO8601DateFormatter().string(from: activity.occurredAt),
            note: activity.note
        )
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
            paymentAccountID: transaction.paymentAccount?.id.uuidString,
            paymentAccountName: transaction.paymentAccount?.name,
            paymentAccountKind: transaction.paymentAccount.flatMap { paymentAccount in
                assets.first { $0.id == paymentAccount.id }?.kind.rawValue
            },
            paymentAccountSymbolName: transaction.paymentAccount?.symbolName,
            amount: decimalText(transaction.amount),
            installmentMonths: transaction.installmentMonths,
            repaymentAdjustments: transaction.repaymentAdjustments,
            occurredAt: ISO8601DateFormatter().string(from: transaction.occurredAt)
        )
    }

    private func mergeCategories(
        _ records: [CategoryExportRecord],
        expenseCategories: inout [MoneyCategory],
        incomeCategories: inout [MoneyCategory]
    ) {
        for record in records {
            guard let category = makeCategory(from: record) else { continue }

            switch category.kind {
            case .expense:
                upsertCategory(category, into: &expenseCategories)
            case .income:
                upsertCategory(category, into: &incomeCategories)
            }
        }

        expenseCategories.sort { $0.sortOrder < $1.sortOrder }
        incomeCategories.sort { $0.sortOrder < $1.sortOrder }
    }

    private func upsertCategory(_ category: MoneyCategory, into categories: inout [MoneyCategory]) {
        if let index = categories.firstIndex(where: { $0.presetKey == category.presetKey }) {
            let existing = categories[index]
            categories[index] = MoneyCategory(
                id: existing.id,
                presetKey: category.presetKey,
                name: category.name,
                kind: category.kind,
                symbolName: category.symbolName,
                color: existing.color,
                sortOrder: category.sortOrder,
                isSystemPreset: category.isSystemPreset
            )
        } else {
            categories.append(category)
        }
    }

    private func makeCategory(from record: CategoryExportRecord) -> MoneyCategory? {
        guard let id = UUID(uuidString: record.id),
              let kind = CategoryKind(rawValue: record.kind)
        else {
            return nil
        }

        let color = PreviewData.allCategories.first { $0.presetKey == record.presetKey }?.color ?? AppColor.primary
        return MoneyCategory(
            id: id,
            presetKey: record.presetKey,
            name: record.name,
            kind: kind,
            symbolName: record.symbolName,
            color: color,
            sortOrder: record.sortOrder,
            isSystemPreset: record.isSystemPreset
        )
    }

    private func makeAsset(from record: AssetExportRecord) throws -> AssetItem {
        guard let id = UUID(uuidString: record.id),
              let kind = AssetKind(rawValue: record.kind),
              let balance = Decimal.moneyString(record.balance)
        else {
            throw AppStoreFailure.invalidImportRecord
        }

        var repayments = try record.repayments.map(makeRepayment)
        let loadedOffsets = Set(repayments.map(\.monthOffset))
        for offset in 0..<24 where !loadedOffsets.contains(offset) {
            repayments.append(RepaymentMonth(id: UUID(), monthOffset: offset, amount: 0))
        }
        repayments.sort { $0.monthOffset < $1.monthOffset }

        return AssetItem(
            id: id,
            name: record.name,
            kind: kind,
            balance: balance,
            repayments: repayments,
            fundCost: try optionalMoney(record.fundCost),
            fundMarketValue: try optionalMoney(record.fundMarketValue),
            fundActivities: try record.fundActivities.map(makeFundActivity).sorted { $0.occurredAt > $1.occurredAt }
        )
    }

    private func makeRepayment(from record: RepaymentExportRecord) throws -> RepaymentMonth {
        guard let id = UUID(uuidString: record.id),
              let amount = Decimal.moneyString(record.amount)
        else {
            throw AppStoreFailure.invalidImportRecord
        }

        return RepaymentMonth(id: id, monthOffset: record.monthOffset, amount: amount)
    }

    private func makeFundActivity(from record: FundActivityExportRecord) throws -> FundActivity {
        guard let id = UUID(uuidString: record.id),
              let kind = FundActivityKind(rawValue: record.kind),
              let amount = Decimal.moneyString(record.amount),
              let occurredAt = ISO8601DateFormatter().date(from: record.occurredAt)
        else {
            throw AppStoreFailure.invalidImportRecord
        }

        return FundActivity(
            id: id,
            kind: kind,
            amount: amount,
            occurredAt: occurredAt,
            note: record.note
        )
    }

    private func optionalMoney(_ text: String?) throws -> Decimal? {
        guard let text else { return nil }
        guard let value = Decimal.moneyString(text) else {
            throw AppStoreFailure.invalidImportAmount(text)
        }
        return value
    }

    private func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private func mergeAssets(_ importedAssets: [AssetItem], into assets: inout [AssetItem]) {
        for importedAsset in importedAssets {
            if let index = assets.firstIndex(where: { $0.id == importedAsset.id }) {
                assets[index] = importedAsset
                continue
            }

            if let replaceIndex = emptyLocalAssetIndexMatching(importedAsset, in: assets) {
                assets[replaceIndex] = importedAsset
            } else {
                assets.append(importedAsset)
            }
        }
    }

    private func emptyLocalAssetIndexMatching(_ importedAsset: AssetItem, in assets: [AssetItem]) -> Int? {
        assets.firstIndex { localAsset in
            localAsset.name == importedAsset.name
                && localAsset.kind == importedAsset.kind
                && localAsset.balance == 0
                && localAsset.repayments.allSatisfy { $0.amount == 0 }
                && (localAsset.fundCost == nil || localAsset.fundCost == 0)
                && (localAsset.fundMarketValue == nil || localAsset.fundMarketValue == 0)
                && localAsset.fundActivities.isEmpty
                && !transactions.contains { $0.account.id == localAsset.id || $0.paymentAccount?.id == localAsset.id }
        }
    }

    private func makeTransaction(
        from record: TransactionExportRecord,
        assets: inout [AssetItem],
        categories importCategories: [MoneyCategory]? = nil
    ) throws -> MoneyTransaction {
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
            category: category(record.categoryPresetKey, fallbackKind: kind, categories: importCategories),
            account: account(for: record, assets: &assets),
            paymentAccount: paymentAccount(for: record, assets: &assets),
            amount: amount,
            installmentMonths: record.installmentMonths,
            repaymentAdjustments: record.repaymentAdjustments ?? [],
            occurredAt: occurredAt
        )
    }

    private func paymentAccount(for record: TransactionExportRecord, assets: inout [AssetItem]) -> MoneyAccount? {
        guard record.paymentAccountID != nil || record.paymentAccountName != nil else { return nil }
        let kind = record.paymentAccountKind.flatMap(AssetKind.init(rawValue:))
        return account(
            id: record.paymentAccountID,
            name: record.paymentAccountName,
            kind: kind,
            symbolName: record.paymentAccountSymbolName,
            assets: &assets
        )
    }

    private func category(
        _ presetKey: String,
        fallbackKind: TransactionKind,
        categories importCategories: [MoneyCategory]? = nil
    ) -> MoneyCategory {
        let candidates = importCategories ?? (expenseCategories + incomeCategories)
        if let category = candidates.first(where: { $0.presetKey == presetKey }) {
            return category
        }
        return PreviewData.category(presetKey, fallbackKind: fallbackKind)
    }

    private func account(for record: TransactionExportRecord, assets: inout [AssetItem]) -> MoneyAccount {
        account(
            id: record.accountID,
            name: record.accountName,
            kind: record.accountKind.flatMap(AssetKind.init(rawValue:)),
            symbolName: record.accountSymbolName,
            assets: &assets
        ) ?? MoneyAccount(
            id: UUID(),
            name: record.accountName,
            symbolName: record.accountSymbolName ?? "creditcard.fill",
            balance: 0
        )
    }

    private func account(
        id: String?,
        name: String?,
        kind: AssetKind?,
        symbolName: String?,
        assets: inout [AssetItem]
    ) -> MoneyAccount? {
        guard let name else { return nil }

        if let accountID = id.flatMap(UUID.init(uuidString:)),
           let asset = assets.first(where: { $0.id == accountID }) {
            return MoneyAccount(
                id: asset.id,
                name: asset.name,
                symbolName: asset.kind.symbolName,
                balance: asset.balance
            )
        }

        if let kind,
           let asset = assets.first(where: { $0.name == name && $0.kind == kind }) {
            return MoneyAccount(
                id: asset.id,
                name: asset.name,
                symbolName: asset.kind.symbolName,
                balance: asset.balance
            )
        }

        if let asset = assets.first(where: { $0.name == name }) {
            return MoneyAccount(
                id: asset.id,
                name: asset.name,
                symbolName: asset.kind.symbolName,
                balance: asset.balance
            )
        }

        let kind = kind ?? .cash
        let asset = AssetItem(
            id: id.flatMap(UUID.init(uuidString:)) ?? UUID(),
            name: name,
            kind: kind,
            balance: 0,
            repayments: Self.makeEmptyRepayments(),
            fundCost: kind == .fund ? 0 : nil,
            fundMarketValue: kind == .fund ? 0 : nil
        )
        assets.append(asset)

        return MoneyAccount(
            id: asset.id,
            name: asset.name,
            symbolName: symbolName ?? asset.kind.symbolName,
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

    private func assetsForHistorySnapshot(cutoff: Date, transactions snapshotTransactions: [MoneyTransaction]) -> [AssetItem] {
        var snapshotAssets = assets

        for index in snapshotAssets.indices {
            if snapshotAssets[index].kind == .fund {
                reverseFutureFundActivities(in: &snapshotAssets[index], cutoff: cutoff)
            }
        }

        for transaction in transactions where transaction.occurredAt > cutoff {
            _ = reverseRepaymentEffects(for: transaction, in: &snapshotAssets)
        }

        return LedgerCalculator.assetsWithLedgerBalances(
            assets: snapshotAssets,
            transactions: snapshotTransactions
        )
    }

    private func reverseFutureFundActivities(in asset: inout AssetItem, cutoff: Date) {
        let futureActivities = asset.fundActivities.filter { $0.occurredAt > cutoff }
        for activity in futureActivities {
            switch activity.kind {
            case .investment:
                asset.fundCost = (asset.fundCost ?? 0) - activity.amount
            case .valuation:
                asset.fundMarketValue = (asset.fundMarketValue ?? 0) - activity.amount
            }
        }

        asset.fundActivities = asset.fundActivities
            .filter { $0.occurredAt <= cutoff }
            .sorted { $0.occurredAt > $1.occurredAt }
        asset.balance = asset.fundCurrentValue
    }

    private func netContribution(of asset: AssetItem?) -> Decimal {
        guard let asset else { return 0 }
        if asset.kind == .fund {
            return asset.fundCurrentValue
        }
        if asset.isDebtLike {
            return -asset.totalDebt
        }
        return asset.balance
    }

    private func makeTransaction(
        id: UUID,
        kind: TransactionKind,
        amount: Decimal,
        category: MoneyCategory,
        account: MoneyAccount,
        title: String,
        paymentAccount: MoneyAccount?,
        installmentMonths: Int?,
        occurredAt: Date,
        assets: inout [AssetItem]
    ) -> MoneyTransaction {
        let accountKind = assets.first { $0.id == account.id }?.kind
        let usesInstallmentPlan = kind == .expense
            && !category.isRepayment
            && (installmentMonths ?? 0) > 0
            && (accountKind?.supportsInstallment ?? false)
        let addsCurrentMonthRepayment = kind == .expense
            && !category.isRepayment
            && !usesInstallmentPlan
            && (accountKind?.isDebtAccount ?? false)
        let appliesRepayment = kind == .expense
            && category.isRepayment
            && (accountKind?.isDebtAccount ?? false)

        var repaymentAdjustments: [RepaymentAdjustment] = []
        if usesInstallmentPlan, let installmentMonths {
            repaymentAdjustments = addRepaymentPlan(to: &assets, accountID: account.id, amount: amount, months: installmentMonths)
        }
        if addsCurrentMonthRepayment {
            repaymentAdjustments = addCurrentMonthRepayment(to: &assets, accountID: account.id, amount: amount)
        }
        if appliesRepayment {
            repaymentAdjustments = applyRepayment(to: &assets, accountID: account.id, amount: amount)
        }

        return MoneyTransaction(
            id: id,
            kind: kind,
            title: title,
            category: category,
            account: account,
            paymentAccount: category.isRepayment ? paymentAccount : nil,
            amount: amount,
            installmentMonths: usesInstallmentPlan ? installmentMonths : nil,
            repaymentAdjustments: repaymentAdjustments,
            occurredAt: occurredAt
        )
    }

    private func addRepaymentPlan(to assets: inout [AssetItem], accountID: UUID, amount: Decimal, months: Int) -> [RepaymentAdjustment] {
        guard let assetIndex = assets.firstIndex(where: { $0.id == accountID }),
              assets[assetIndex].kind.supportsInstallment
        else {
            return []
        }

        let cappedMonths = min(max(months, 1), 24)
        var adjustments: [RepaymentAdjustment] = []

        for monthIndex in 0..<cappedMonths {
            let offset = monthIndex + 1
            guard let repaymentIndex = assets[assetIndex].repayments.firstIndex(where: { $0.monthOffset == offset }) else {
                continue
            }
            assets[assetIndex].repayments[repaymentIndex].amount += amount
            adjustments.append(RepaymentAdjustment(monthOffset: offset, amount: amount))
        }

        return adjustments
    }

    private func addCurrentMonthRepayment(to assets: inout [AssetItem], accountID: UUID, amount: Decimal) -> [RepaymentAdjustment] {
        guard let assetIndex = assets.firstIndex(where: { $0.id == accountID }),
              assets[assetIndex].kind.isDebtAccount,
              let repaymentIndex = assets[assetIndex].repayments.firstIndex(where: { $0.monthOffset == 0 })
        else {
            return []
        }

        assets[assetIndex].repayments[repaymentIndex].amount += amount
        return [RepaymentAdjustment(monthOffset: 0, amount: amount)]
    }

    private func applyRepayment(to assets: inout [AssetItem], accountID: UUID, amount: Decimal) -> [RepaymentAdjustment] {
        guard let assetIndex = assets.firstIndex(where: { $0.id == accountID }),
              assets[assetIndex].kind.isDebtAccount
        else {
            return []
        }

        var remaining = amount
        var adjustments: [RepaymentAdjustment] = []
        for repaymentIndex in assets[assetIndex].repayments.indices.sorted(by: {
            assets[assetIndex].repayments[$0].monthOffset < assets[assetIndex].repayments[$1].monthOffset
        }) {
            guard remaining > 0 else { break }
            let currentAmount = assets[assetIndex].repayments[repaymentIndex].amount
            guard currentAmount > 0 else { continue }

            let paidAmount = currentAmount <= remaining ? currentAmount : remaining
            assets[assetIndex].repayments[repaymentIndex].amount -= paidAmount
            remaining -= paidAmount
            adjustments.append(RepaymentAdjustment(
                monthOffset: assets[assetIndex].repayments[repaymentIndex].monthOffset,
                amount: -paidAmount
            ))
        }

        return adjustments
    }

    private func reverseRepaymentEffects(for transaction: MoneyTransaction, in assets: inout [AssetItem]) -> Bool {
        guard transaction.kind == .expense,
              let assetIndex = assets.firstIndex(where: { $0.id == transaction.account.id }),
              assets[assetIndex].kind.isDebtAccount
        else {
            return false
        }

        let adjustments = transaction.repaymentAdjustments.isEmpty
            ? fallbackRepaymentAdjustments(for: transaction)
            : transaction.repaymentAdjustments
        guard !adjustments.isEmpty else { return false }

        for adjustment in adjustments {
            guard let repaymentIndex = assets[assetIndex].repayments.firstIndex(where: { $0.monthOffset == adjustment.monthOffset }) else {
                continue
            }
            assets[assetIndex].repayments[repaymentIndex].amount -= adjustment.amount
        }

        return true
    }

    private func fallbackRepaymentAdjustments(for transaction: MoneyTransaction) -> [RepaymentAdjustment] {
        if transaction.category.isRepayment {
            return [RepaymentAdjustment(monthOffset: 0, amount: -transaction.amount)]
        }

        if let installmentMonths = transaction.installmentMonths, installmentMonths > 0 {
            return (1...min(installmentMonths, 24)).map {
                RepaymentAdjustment(monthOffset: $0, amount: transaction.amount)
            }
        }

        return [RepaymentAdjustment(monthOffset: 0, amount: transaction.amount)]
    }

    private func ensureRecommendedAssetsAndNames() throws {
        var changed = false
        let existingKinds = Set(assets.map(\.kind))

        for asset in PreviewData.assets where !existingKinds.contains(asset.kind) {
            assets.append(asset)
            changed = true
        }

        for index in assets.indices {
            guard let normalizedName = normalizedDefaultAssetName(for: assets[index]) else { continue }
            assets[index].name = normalizedName
            changed = true
        }

        for index in assets.indices where assets[index].kind == .fund {
            let cost = assets[index].fundCost ?? 0
            let marketValue = assets[index].fundMarketValue ?? 0
            let oldComputedValue = cost + marketValue
            if cost != 0,
               assets[index].balance == oldComputedValue,
               assets[index].balance != marketValue {
                assets[index].fundMarketValue = assets[index].balance
                changed = true
            }
        }

        if changed {
            try persistAssets(assets)
        }
    }

    private func ensureRecommendedCategories() throws {
        guard !expenseCategories.contains(where: \.isRepayment) else { return }
        expenseCategories.append(.repayment)
        expenseCategories.sort { $0.sortOrder < $1.sortOrder }
        try persistCategories(expenseCategories + incomeCategories)
    }

    private func normalizedDefaultAssetName(for asset: AssetItem) -> String? {
        switch asset.kind {
        case .alipayCredit where asset.name == "支付宝花呗":
            return "花呗"
        case .wechatChange where asset.name == "微信零钱":
            return "零钱"
        case .wechatCredit where asset.name == "微信待还":
            return "微信分付"
        default:
            return nil
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
    case assetInUse(String)

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
        case let .assetInUse(name):
            "“\(name)”已经被账目使用，不能直接删除"
        }
    }
}
