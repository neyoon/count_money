import Foundation
import SwiftUI

enum TransactionKind: String, CaseIterable, Identifiable {
    case expense
    case income
    case fundProfit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        case .fundProfit: "基金盈亏"
        }
    }
}

struct MoneyAccount: Identifiable, Hashable {
    let id: UUID
    var name: String
    var symbolName: String
    var balance: Decimal
}

enum AssetKind: String, CaseIterable, Identifiable {
    case debitCard
    case creditCard
    case alipayBalance = "alipay"
    case alipayYuEBao
    case alipayCredit
    case wechatChange = "wechatPay"
    case wechatChangePass
    case wechatCredit
    case meituan
    case jd
    case fund
    case cash

    var id: String { rawValue }

    var accountCategory: AssetAccountCategory {
        switch self {
        case .creditCard, .alipayCredit, .wechatCredit, .meituan, .jd:
            .debt
        case .fund:
            .investment
        case .debitCard, .alipayBalance, .alipayYuEBao, .wechatChange, .wechatChangePass, .cash:
            .balance
        }
    }

    var title: String {
        switch self {
        case .debitCard: "借记卡"
        case .creditCard: "信用卡"
        case .alipayBalance: "支付宝余额"
        case .alipayYuEBao: "余额宝"
        case .alipayCredit: "花呗"
        case .wechatChange: "零钱"
        case .wechatChangePass: "零钱通"
        case .wechatCredit: "微信分付"
        case .meituan: "美团月付"
        case .jd: "京东白条"
        case .fund: "基金"
        case .cash: "现金"
        }
    }

    var symbolName: String {
        switch self {
        case .debitCard: "creditcard.fill"
        case .creditCard: "creditcard.trianglebadge.exclamationmark"
        case .alipayBalance: "a.circle.fill"
        case .alipayYuEBao: "leaf.fill"
        case .alipayCredit: "a.circle"
        case .wechatChange: "message.fill"
        case .wechatChangePass: "leaf.circle.fill"
        case .wechatCredit: "message.badge"
        case .meituan: "takeoutbag.and.cup.and.straw.fill"
        case .jd: "shippingbox.fill"
        case .fund: "chart.line.uptrend.xyaxis"
        case .cash: "banknote.fill"
        }
    }

    var isDebtAccount: Bool {
        accountCategory == .debt
    }

    var canSpend: Bool {
        accountCategory != .investment
    }

    var canFundRepayment: Bool {
        accountCategory == .balance
    }

    var supportsInstallment: Bool {
        switch self {
        case .creditCard, .alipayCredit, .wechatCredit, .meituan, .jd:
            true
        case .debitCard, .alipayBalance, .alipayYuEBao, .wechatChange, .wechatChangePass, .fund, .cash:
            false
        }
    }
}

enum AssetAccountCategory: String, CaseIterable, Identifiable {
    case balance
    case debt
    case investment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .balance: "余额账户"
        case .debt: "待还账户"
        case .investment: "投资账户"
        }
    }

    var detail: String {
        switch self {
        case .balance: "可消费，也可作为还款支付账户"
        case .debt: "可消费，消费后形成待还"
        case .investment: "只用于基金资产和盈亏"
        }
    }

    var assetKinds: [AssetKind] {
        AssetKind.allCases.filter { $0.accountCategory == self }
    }
}

enum FundActivityKind: String, CaseIterable, Identifiable {
    case valuation
    case investment

    var id: String { rawValue }

    var title: String {
        switch self {
        case .valuation: "盈亏记录"
        case .investment: "投入/定投"
        }
    }

    var symbolName: String {
        switch self {
        case .valuation: "chart.line.uptrend.xyaxis"
        case .investment: "plus.circle.fill"
        }
    }
}

struct FundActivity: Identifiable, Hashable {
    let id: UUID
    var kind: FundActivityKind
    var amount: Decimal
    var occurredAt: Date
    var note: String
}

struct RepaymentMonth: Identifiable, Hashable {
    let id: UUID
    var monthOffset: Int
    var amount: Decimal

    var title: String {
        if monthOffset == 0 {
            return "本月"
        }
        if monthOffset == 1 {
            return "下月"
        }
        return "\(monthOffset) 个月后"
    }
}

struct AssetItem: Identifiable, Hashable {
    let id: UUID
    var name: String
    var kind: AssetKind
    var balance: Decimal
    var repayments: [RepaymentMonth]
    var fundCost: Decimal?
    var fundMarketValue: Decimal?
    var fundActivities: [FundActivity] = []

    var totalRepayment: Decimal {
        repayments.map(\.amount).reduce(0, +)
    }

    var fundCurrentValue: Decimal {
        guard kind == .fund else { return balance }
        return fundMarketValue ?? balance
    }

    var fundProfit: Decimal {
        fundCurrentValue - (fundCost ?? 0)
    }

    var nextMonthRepayment: Decimal {
        repayments.first { $0.monthOffset == 1 }?.amount ?? 0
    }

    var currentMonthRepayment: Decimal {
        repayments.first { $0.monthOffset == 0 }?.amount ?? 0
    }

    var totalDebt: Decimal {
        guard isDebtLike else { return 0 }
        return max(balance, totalRepayment)
    }

    var isDebtLike: Bool {
        kind.isDebtAccount
    }
}

enum CategoryKind: String, CaseIterable, Identifiable {
    case expense
    case income

    var id: String { rawValue }
}

struct MoneyCategory: Identifiable, Hashable {
    let id: UUID
    var presetKey: String
    var name: String
    var kind: CategoryKind
    var symbolName: String
    var color: Color
    var sortOrder: Int
    var isSystemPreset: Bool
}

extension MoneyCategory {
    static let repayment = MoneyCategory(
        id: UUID(uuidString: "7E8C5A30-017B-438A-BF87-A9814C2B1320")!,
        presetKey: "expense_repayment",
        name: "还款",
        kind: .expense,
        symbolName: "arrow.uturn.left.circle.fill",
        color: AppColor.primary,
        sortOrder: 25,
        isSystemPreset: true
    )

    static let fundPurchase = MoneyCategory(
        id: UUID(uuidString: "43BD6B55-FEBB-46FD-A94E-B9A44DE697D4")!,
        presetKey: "expense_fund_purchase",
        name: "购买基金",
        kind: .expense,
        symbolName: "chart.line.uptrend.xyaxis",
        color: AppColor.success,
        sortOrder: 27,
        isSystemPreset: true
    )

    static let fundRedemption = MoneyCategory(
        id: UUID(uuidString: "B28C9E31-A5A0-4A9D-B588-2F9045141D58")!,
        presetKey: "income_fund_redemption",
        name: "基金赎回",
        kind: .income,
        symbolName: "arrow.down.left.circle.fill",
        color: AppColor.success,
        sortOrder: 45,
        isSystemPreset: true
    )

    var isRepayment: Bool {
        presetKey == Self.repayment.presetKey
    }

    var isFundPurchase: Bool {
        presetKey == Self.fundPurchase.presetKey
    }

    var isFundRedemption: Bool {
        presetKey == Self.fundRedemption.presetKey
    }
}

struct MoneyTransaction: Identifiable, Hashable {
    let id: UUID
    var kind: TransactionKind
    var title: String
    var category: MoneyCategory
    var account: MoneyAccount
    var paymentAccount: MoneyAccount? = nil
    var amount: Decimal
    var installmentMonths: Int? = nil
    var repaymentAdjustments: [RepaymentAdjustment] = []
    var occurredAt: Date
}

struct RepaymentAdjustment: Hashable, Codable {
    var monthOffset: Int
    var amount: Decimal
}

struct QuickEntryDraft: Identifiable, Hashable {
    let id: UUID
    var candidateAmount: Decimal
    var candidateAmounts: [Decimal]
    var suggestedKind: TransactionKind
    var recognizedTextPreview: String
    var confidence: Double
    var createdAt: Date
}

struct DailyCashflow: Identifiable, Hashable {
    let id = UUID()
    var day: String
    var income: Decimal
    var expense: Decimal
}

struct CategorySpending: Identifiable, Hashable {
    let id = UUID()
    var category: MoneyCategory
    var amount: Decimal
}

struct AssetOverview: Hashable {
    var holdings: Decimal
    var fundHoldings: Decimal
    var debt: Decimal
    var currentMonthRepayment: Decimal

    var net: Decimal {
        holdings + fundHoldings - debt
    }

    var total: Decimal {
        holdings + fundHoldings + debt
    }

    static func make(from assets: [AssetItem]) -> AssetOverview {
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
            .map(\.totalDebt)
            .reduce(0, +)
        let currentMonthRepayment = usableAssets
            .filter(\.isDebtLike)
            .map(\.currentMonthRepayment)
            .reduce(0, +)

        return AssetOverview(
            holdings: holdings,
            fundHoldings: fundHoldings,
            debt: debt,
            currentMonthRepayment: currentMonthRepayment
        )
    }
}

struct HistorySnapshot: Hashable {
    var date: Date
    var overview: MonthlyOverview
    var assetOverview: AssetOverview
    var assets: [AssetItem]
}

struct AssetHistoryChange: Identifiable, Hashable {
    var id: UUID
    var name: String
    var symbolName: String
    var before: Decimal
    var after: Decimal

    var change: Decimal {
        after - before
    }
}

struct HistoryComparison: Hashable {
    var historical: HistorySnapshot
    var current: HistorySnapshot
    var assetChanges: [AssetHistoryChange]

    var netChange: Decimal {
        current.assetOverview.net - historical.assetOverview.net
    }

    var holdingsChange: Decimal {
        current.assetOverview.holdings - historical.assetOverview.holdings
    }

    var fundChange: Decimal {
        current.assetOverview.fundHoldings - historical.assetOverview.fundHoldings
    }

    var debtChange: Decimal {
        current.assetOverview.debt - historical.assetOverview.debt
    }
}

enum LedgerCalculator {
    static func balanceMap(assets: [AssetItem], transactions: [MoneyTransaction]) -> [UUID: Decimal] {
        var balances = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0.balance) })
        let assetKinds = Dictionary(uniqueKeysWithValues: assets.map { ($0.id, $0.kind) })

        for transaction in transactions {
            guard balances[transaction.account.id] != nil,
                  let assetKind = assetKinds[transaction.account.id]
            else {
                continue
            }

            if transaction.kind == .expense,
               transaction.category.isFundPurchase,
               let paymentAccount = transaction.paymentAccount,
               balances[paymentAccount.id] != nil,
               let paymentAssetKind = assetKinds[paymentAccount.id] {
                applyExpense(
                    amount: transaction.amount,
                    accountID: paymentAccount.id,
                    assetKind: paymentAssetKind,
                    balances: &balances
                )
                continue
            }

            if assetKind.isDebtAccount {
                switch transaction.kind {
                case .expense:
                    if transaction.category.isRepayment {
                        balances[transaction.account.id, default: 0] -= transaction.amount
                        if let paymentAccount = transaction.paymentAccount,
                           paymentAccount.id != transaction.account.id,
                           balances[paymentAccount.id] != nil,
                           let paymentAssetKind = assetKinds[paymentAccount.id] {
                            applyExpense(
                                amount: transaction.amount,
                                accountID: paymentAccount.id,
                                assetKind: paymentAssetKind,
                                balances: &balances
                            )
                        }
                    } else {
                        balances[transaction.account.id, default: 0] += transaction.amount
                    }
                case .income:
                    balances[transaction.account.id, default: 0] -= transaction.amount
                case .fundProfit:
                    break
                }
            } else {
                switch transaction.kind {
                case .expense:
                    balances[transaction.account.id, default: 0] -= transaction.amount
                case .income:
                    balances[transaction.account.id, default: 0] += transaction.amount
                case .fundProfit:
                    break
                }
            }
        }

        return balances
    }

    private static func applyExpense(
        amount: Decimal,
        accountID: UUID,
        assetKind: AssetKind,
        balances: inout [UUID: Decimal]
    ) {
        if assetKind.isDebtAccount {
            balances[accountID, default: 0] += amount
        } else {
            balances[accountID, default: 0] -= amount
        }
    }

    static func assetsWithLedgerBalances(
        assets: [AssetItem],
        transactions: [MoneyTransaction]
    ) -> [AssetItem] {
        let balances = balanceMap(assets: assets, transactions: transactions)

        return assets.map { asset in
            var next = asset
            if let balance = balances[asset.id], asset.kind != .fund {
                next.balance = balance
            }
            return next
        }
    }
}

struct MonthlyOverview: Hashable {
    var income: Decimal
    var expense: Decimal
    var dailyCashflows: [DailyCashflow]
    var categoryIncome: [CategorySpending]
    var categorySpending: [CategorySpending]
    var recentTransactions: [MoneyTransaction]

    var balance: Decimal {
        income - expense
    }

    init(
        transactions: [MoneyTransaction],
        calendar: Calendar = .current,
        now: Date = Date()
    ) {
        let cutoff = calendar.endOfDay(for: now)
        let monthTransactions = transactions.filter {
            calendar.isDate($0.occurredAt, equalTo: now, toGranularity: .month)
                && $0.occurredAt <= cutoff
        }
        let expenseTransactions = monthTransactions.filter { $0.kind == .expense }
        let incomeTransactions = monthTransactions.filter { $0.kind == .income }

        self.income = incomeTransactions.map(\.amount).reduce(0, +)
        self.expense = expenseTransactions.map(\.amount).reduce(0, +)
        self.dailyCashflows = MonthlyOverview.makeDailyCashflows(
            from: monthTransactions,
            calendar: calendar,
            now: now
        )
        self.categoryIncome = MonthlyOverview.makeCategorySpending(from: incomeTransactions)
        self.categorySpending = MonthlyOverview.makeCategorySpending(from: expenseTransactions)
        self.recentTransactions = monthTransactions
            .sorted { $0.occurredAt > $1.occurredAt }
            .prefix(10)
            .map { $0 }
    }

    private static func makeDailyCashflows(
        from transactions: [MoneyTransaction],
        calendar: Calendar,
        now: Date
    ) -> [DailyCashflow] {
        (0..<7).reversed().compactMap { offset in
            guard let date = calendar.date(byAdding: .day, value: -offset, to: now) else {
                return nil
            }

            let dayTransactions = transactions
                .filter { calendar.isDate($0.occurredAt, inSameDayAs: date) }

            let income = dayTransactions
                .filter { $0.kind == .income }
                .map(\.amount)
                .reduce(0, +)

            let expense = dayTransactions
                .filter { $0.kind == .expense }
                .map(\.amount)
                .reduce(0, +)

            return DailyCashflow(
                day: "\(calendar.component(.day, from: date))",
                income: income,
                expense: expense
            )
        }
    }

    private static func makeCategorySpending(from transactions: [MoneyTransaction]) -> [CategorySpending] {
        let grouped = Dictionary(grouping: transactions, by: \.category)

        return grouped
            .map { category, items in
                CategorySpending(category: category, amount: items.map(\.amount).reduce(0, +))
            }
            .sorted {
                if $0.amount == $1.amount {
                    return $0.category.sortOrder < $1.category.sortOrder
                }
                return $0.amount > $1.amount
            }
    }
}

extension Calendar {
    func endOfDay(for date: Date) -> Date {
        let start = startOfDay(for: date)
        return self.date(byAdding: DateComponents(day: 1, second: -1), to: start) ?? date
    }
}

extension Decimal {
    static func money(_ value: Int) -> Decimal {
        Decimal(value)
    }

    static func moneyString(_ value: String) -> Decimal? {
        let normalized = value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "¥", with: "")
            .replacingOccurrences(of: "￥", with: "")
            .replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "，", with: "")
            .replacingOccurrences(of: "。", with: ".")

        guard !normalized.isEmpty else { return nil }

        return Decimal(string: normalized, locale: Locale(identifier: "en_US_POSIX"))
            ?? Decimal(string: normalized)
    }

    var doubleValue: Double {
        NSDecimalNumber(decimal: self).doubleValue
    }
}

struct TransactionExportRecord: Codable, Identifiable {
    var id: String
    var kind: String
    var title: String
    var categoryPresetKey: String
    var accountID: String? = nil
    var accountName: String
    var accountKind: String? = nil
    var accountSymbolName: String? = nil
    var paymentAccountID: String? = nil
    var paymentAccountName: String? = nil
    var paymentAccountKind: String? = nil
    var paymentAccountSymbolName: String? = nil
    var amount: String
    var installmentMonths: Int? = nil
    var repaymentAdjustments: [RepaymentAdjustment]? = nil
    var occurredAt: String
}

struct LedgerExportFile: Codable {
    var version: Int
    var exportedAt: String
    var categories: [CategoryExportRecord]
    var assets: [AssetExportRecord]
    var transactions: [TransactionExportRecord]
}

struct CategoryExportRecord: Codable, Identifiable {
    var id: String
    var presetKey: String
    var name: String
    var kind: String
    var symbolName: String
    var sortOrder: Int
    var isSystemPreset: Bool
}

struct AssetExportRecord: Codable, Identifiable {
    var id: String
    var name: String
    var kind: String
    var balance: String
    var repayments: [RepaymentExportRecord]
    var fundCost: String? = nil
    var fundMarketValue: String? = nil
    var fundActivities: [FundActivityExportRecord] = []
}

struct RepaymentExportRecord: Codable, Identifiable {
    var id: String
    var monthOffset: Int
    var amount: String
}

struct FundActivityExportRecord: Codable, Identifiable {
    var id: String
    var kind: String
    var amount: String
    var occurredAt: String
    var note: String
}
