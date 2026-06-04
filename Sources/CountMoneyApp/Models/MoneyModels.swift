import Foundation
import SwiftUI

enum TransactionKind: String, CaseIterable, Identifiable {
    case expense
    case income
    case transfer

    var id: String { rawValue }

    var title: String {
        switch self {
        case .expense: "支出"
        case .income: "收入"
        case .transfer: "转账"
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

    var title: String {
        switch self {
        case .debitCard: "借记卡"
        case .creditCard: "信用卡"
        case .alipayBalance: "支付宝余额"
        case .alipayYuEBao: "余额宝"
        case .alipayCredit: "花呗"
        case .wechatChange: "微信零钱"
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

    var supportsRepayment: Bool {
        switch self {
        case .creditCard, .alipayCredit, .wechatCredit, .meituan, .jd:
            true
        case .debitCard, .alipayBalance, .alipayYuEBao, .wechatChange, .wechatChangePass, .fund, .cash:
            false
        }
    }

    var canPayTransaction: Bool {
        switch self {
        case .wechatCredit, .fund:
            false
        case .debitCard, .creditCard, .alipayBalance, .alipayYuEBao, .alipayCredit, .wechatChange, .wechatChangePass, .meituan, .jd, .cash:
            true
        }
    }

    var supportsInstallment: Bool {
        switch self {
        case .creditCard, .alipayCredit, .meituan, .jd:
            true
        case .debitCard, .alipayBalance, .alipayYuEBao, .wechatChange, .wechatChangePass, .wechatCredit, .fund, .cash:
            false
        }
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

    var nextMonthRepayment: Decimal {
        repayments.first { $0.monthOffset == 1 }?.amount ?? 0
    }

    var isDebtLike: Bool {
        kind.supportsRepayment
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

struct MoneyTransaction: Identifiable, Hashable {
    let id: UUID
    var kind: TransactionKind
    var title: String
    var category: MoneyCategory
    var account: MoneyAccount
    var amount: Decimal
    var occurredAt: Date
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
    var debt: Decimal

    var net: Decimal {
        holdings - debt
    }

    var total: Decimal {
        holdings + debt
    }
}

struct MonthlyOverview {
    var income: Decimal
    var expense: Decimal
    var dailyCashflows: [DailyCashflow]
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
        let monthTransactions = transactions.filter {
            calendar.isDate($0.occurredAt, equalTo: now, toGranularity: .month)
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
        self.categorySpending = MonthlyOverview.makeCategorySpending(from: expenseTransactions)
        self.recentTransactions = monthTransactions
            .sorted { $0.occurredAt > $1.occurredAt }
            .prefix(5)
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

extension MoneyTransaction {
    var exportRecord: TransactionExportRecord {
        TransactionExportRecord(
            id: id.uuidString,
            kind: kind.rawValue,
            title: title,
            categoryPresetKey: category.presetKey,
            accountName: account.name,
            amount: NSDecimalNumber(decimal: amount).stringValue,
            occurredAt: ISO8601DateFormatter().string(from: occurredAt)
        )
    }
}

struct TransactionExportRecord: Codable, Identifiable {
    var id: String
    var kind: String
    var title: String
    var categoryPresetKey: String
    var accountName: String
    var amount: String
    var occurredAt: String
}
