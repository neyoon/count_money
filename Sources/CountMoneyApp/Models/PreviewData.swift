import Foundation
import SwiftUI

enum PreviewData {
    static let expenseCategories: [MoneyCategory] = [
        MoneyCategory(
            id: UUID(),
            presetKey: "expense_food",
            name: "餐饮",
            kind: .expense,
            symbolName: "fork.knife",
            color: Color(red: 0.89, green: 0.34, blue: 0.31),
            sortOrder: 10,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "expense_transport",
            name: "交通",
            kind: .expense,
            symbolName: "tram.fill",
            color: Color(red: 0.19, green: 0.48, blue: 0.77),
            sortOrder: 20,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "expense_daily",
            name: "日用",
            kind: .expense,
            symbolName: "basket.fill",
            color: Color(red: 0.18, green: 0.60, blue: 0.45),
            sortOrder: 30,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "expense_shopping",
            name: "购物",
            kind: .expense,
            symbolName: "bag.fill",
            color: Color(red: 0.58, green: 0.42, blue: 0.78),
            sortOrder: 40,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "expense_subscription",
            name: "订阅",
            kind: .expense,
            symbolName: "play.rectangle.fill",
            color: Color(red: 0.75, green: 0.42, blue: 0.18),
            sortOrder: 50,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "expense_entertainment",
            name: "娱乐",
            kind: .expense,
            symbolName: "gamecontroller.fill",
            color: Color(red: 0.13, green: 0.54, blue: 0.52),
            sortOrder: 60,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "expense_health",
            name: "医疗",
            kind: .expense,
            symbolName: "cross.case.fill",
            color: Color(red: 0.80, green: 0.23, blue: 0.25),
            sortOrder: 70,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "expense_education",
            name: "学习",
            kind: .expense,
            symbolName: "book.fill",
            color: Color(red: 0.31, green: 0.47, blue: 0.73),
            sortOrder: 80,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "expense_family",
            name: "家庭",
            kind: .expense,
            symbolName: "person.2.fill",
            color: Color(red: 0.59, green: 0.37, blue: 0.56),
            sortOrder: 90,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "expense_other",
            name: "其他支出",
            kind: .expense,
            symbolName: "ellipsis.circle.fill",
            color: Color(red: 0.45, green: 0.49, blue: 0.54),
            sortOrder: 100,
            isSystemPreset: true
        )
    ]

    static let incomeCategories: [MoneyCategory] = [
        MoneyCategory(
            id: UUID(),
            presetKey: "income_salary",
            name: "工资",
            kind: .income,
            symbolName: "banknote.fill",
            color: Color(red: 0.12, green: 0.56, blue: 0.71),
            sortOrder: 10,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "income_bonus",
            name: "奖金",
            kind: .income,
            symbolName: "gift.fill",
            color: Color(red: 0.30, green: 0.57, blue: 0.34),
            sortOrder: 20,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "income_freelance",
            name: "副业",
            kind: .income,
            symbolName: "laptopcomputer",
            color: Color(red: 0.47, green: 0.41, blue: 0.73),
            sortOrder: 30,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "income_investment",
            name: "投资收益",
            kind: .income,
            symbolName: "chart.line.uptrend.xyaxis",
            color: Color(red: 0.12, green: 0.48, blue: 0.60),
            sortOrder: 40,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "income_interest",
            name: "利息",
            kind: .income,
            symbolName: "percent",
            color: Color(red: 0.51, green: 0.55, blue: 0.28),
            sortOrder: 50,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "income_reimbursement",
            name: "报销",
            kind: .income,
            symbolName: "doc.text.fill",
            color: Color(red: 0.25, green: 0.53, blue: 0.63),
            sortOrder: 60,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "income_refund",
            name: "退款",
            kind: .income,
            symbolName: "arrow.uturn.left.circle.fill",
            color: Color(red: 0.72, green: 0.45, blue: 0.19),
            sortOrder: 70,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "income_transfer_in",
            name: "转入调整",
            kind: .income,
            symbolName: "arrow.down.left.circle.fill",
            color: Color(red: 0.36, green: 0.49, blue: 0.58),
            sortOrder: 80,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "income_gift",
            name: "礼金",
            kind: .income,
            symbolName: "envelope.fill",
            color: Color(red: 0.80, green: 0.34, blue: 0.38),
            sortOrder: 90,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "income_sale",
            name: "闲置出售",
            kind: .income,
            symbolName: "shippingbox.fill",
            color: Color(red: 0.37, green: 0.47, blue: 0.41),
            sortOrder: 100,
            isSystemPreset: true
        ),
        MoneyCategory(
            id: UUID(),
            presetKey: "income_other",
            name: "其他收入",
            kind: .income,
            symbolName: "ellipsis.circle.fill",
            color: Color(red: 0.45, green: 0.49, blue: 0.54),
            sortOrder: 110,
            isSystemPreset: true
        )
    ]

    static var allCategories: [MoneyCategory] {
        expenseCategories + incomeCategories
    }

    static let wallet = MoneyAccount(
        id: UUID(),
        name: "默认钱包",
        symbolName: "creditcard.fill",
        balance: 0
    )

    static let assets: [AssetItem] = [
        AssetItem(
            id: UUID(),
            name: "借记卡",
            kind: .debitCard,
            balance: 0,
            repayments: emptyRepayments(),
            fundCost: nil,
            fundMarketValue: nil
        ),
        AssetItem(
            id: UUID(),
            name: "信用卡",
            kind: .creditCard,
            balance: 0,
            repayments: emptyRepayments(),
            fundCost: nil,
            fundMarketValue: nil
        ),
        AssetItem(
            id: UUID(),
            name: "支付宝余额",
            kind: .alipayBalance,
            balance: 0,
            repayments: emptyRepayments(),
            fundCost: nil,
            fundMarketValue: nil
        ),
        AssetItem(
            id: UUID(),
            name: "余额宝",
            kind: .alipayYuEBao,
            balance: 0,
            repayments: emptyRepayments(),
            fundCost: nil,
            fundMarketValue: nil
        ),
        AssetItem(
            id: UUID(),
            name: "花呗",
            kind: .alipayCredit,
            balance: 0,
            repayments: emptyRepayments(),
            fundCost: nil,
            fundMarketValue: nil
        ),
        AssetItem(
            id: UUID(),
            name: "微信零钱",
            kind: .wechatChange,
            balance: 0,
            repayments: emptyRepayments(),
            fundCost: nil,
            fundMarketValue: nil
        ),
        AssetItem(
            id: UUID(),
            name: "零钱通",
            kind: .wechatChangePass,
            balance: 0,
            repayments: emptyRepayments(),
            fundCost: nil,
            fundMarketValue: nil
        ),
        AssetItem(
            id: UUID(),
            name: "微信分付",
            kind: .wechatCredit,
            balance: 0,
            repayments: emptyRepayments(),
            fundCost: nil,
            fundMarketValue: nil
        ),
        AssetItem(
            id: UUID(),
            name: "美团月付",
            kind: .meituan,
            balance: 0,
            repayments: emptyRepayments(),
            fundCost: nil,
            fundMarketValue: nil
        ),
        AssetItem(
            id: UUID(),
            name: "京东白条",
            kind: .jd,
            balance: 0,
            repayments: emptyRepayments(),
            fundCost: nil,
            fundMarketValue: nil
        ),
        AssetItem(
            id: UUID(),
            name: "指数基金",
            kind: .fund,
            balance: 0,
            repayments: emptyRepayments(),
            fundCost: 0,
            fundMarketValue: 0
        )
    ]

    static let transactions: [MoneyTransaction] = [
        income("工资", category: "income_salary", amount: 22000, daysAgo: 3),
        income("项目尾款", category: "income_freelance", amount: 3200, daysAgo: 1),
        income("订单退款", category: "income_refund", amount: 89, daysAgo: 2),
        expense("午饭", category: "expense_food", amount: 38, daysAgo: 0),
        expense("打车", category: "expense_transport", amount: 62, daysAgo: 0),
        expense("超市", category: "expense_daily", amount: 186, daysAgo: 1),
        expense("会员订阅", category: "expense_subscription", amount: 68, daysAgo: 2),
        expense("衣服", category: "expense_shopping", amount: 560, daysAgo: 2),
        expense("电影", category: "expense_entertainment", amount: 96, daysAgo: 3),
        expense("体检", category: "expense_health", amount: 780, daysAgo: 4),
        expense("课程", category: "expense_education", amount: 1299, daysAgo: 5),
        expense("家人红包", category: "expense_family", amount: 500, daysAgo: 6),
        expense("晚饭", category: "expense_food", amount: 128, daysAgo: 6),
        expense("日用品", category: "expense_daily", amount: 119, daysAgo: 8)
    ]

    static let overview = MonthlyOverview(
        transactions: transactions
    )

    static func categories(for kind: TransactionKind) -> [MoneyCategory] {
        switch kind {
        case .expense:
            expenseCategories
        case .income:
            incomeCategories
        }
    }

    private static func expense(
        _ title: String,
        category presetKey: String,
        amount: Int,
        daysAgo: Int
    ) -> MoneyTransaction {
        transaction(
            kind: .expense,
            title: title,
            category: presetKey,
            amount: amount,
            daysAgo: daysAgo
        )
    }

    private static func income(
        _ title: String,
        category presetKey: String,
        amount: Int,
        daysAgo: Int
    ) -> MoneyTransaction {
        transaction(
            kind: .income,
            title: title,
            category: presetKey,
            amount: amount,
            daysAgo: daysAgo
        )
    }

    private static func transaction(
        kind: TransactionKind,
        title: String,
        category presetKey: String,
        amount: Int,
        daysAgo: Int
    ) -> MoneyTransaction {
        MoneyTransaction(
            id: UUID(),
            kind: kind,
            title: title,
            category: category(presetKey),
            account: wallet,
            amount: .money(amount),
            occurredAt: Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date()) ?? Date()
        )
    }

    static func category(_ presetKey: String, fallbackKind: TransactionKind = .expense) -> MoneyCategory {
        if let category = allCategories.first(where: { $0.presetKey == presetKey }) {
            return category
        }

        switch fallbackKind {
        case .income:
            return incomeCategories.last!
        case .expense:
            return expenseCategories.last!
        }
    }

    private static func emptyRepayments() -> [RepaymentMonth] {
        repaymentPlan([:])
    }

    private static func repaymentPlan(_ values: [Int: Int]) -> [RepaymentMonth] {
        (0..<24).map { offset in
            RepaymentMonth(
                id: UUID(),
                monthOffset: offset,
                amount: .money(values[offset] ?? 0)
            )
        }
    }
}
