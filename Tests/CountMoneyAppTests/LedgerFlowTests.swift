import Foundation
import SwiftUI
import XCTest
@testable import CountMoneyApp

final class LedgerFlowTests: XCTestCase {
    func testLedgerBalancesReflectRealSpendingAndDebt() {
        let debit = asset(name: "招行借记卡", kind: .debitCard, balance: 5_000)
        let credit = asset(name: "信用卡", kind: .creditCard, balance: 0)
        let food = category(name: "餐饮", kind: .expense, presetKey: "expense_food")
        let salary = category(name: "工资", kind: .income, presetKey: "income_salary")
        let refund = category(name: "退款", kind: .income, presetKey: "income_refund")

        let transactions = [
            transaction(kind: .income, title: "工资", category: salary, asset: debit, amount: 22_000),
            transaction(kind: .expense, title: "午饭", category: food, asset: debit, amount: 38),
            transaction(kind: .income, title: "订单退款", category: refund, asset: debit, amount: 89),
            transaction(kind: .expense, title: "手机", category: food, asset: credit, amount: 1_200),
            transaction(kind: .income, title: "还款", category: refund, asset: credit, amount: 200)
        ]

        let balances = LedgerCalculator.balanceMap(assets: [debit, credit], transactions: transactions)

        XCTAssertEqual(balances[debit.id], 27_051)
        XCTAssertEqual(balances[credit.id], 1_000)
    }

    func testJSONImportAppendsTransactionsIntoMatchingAndNewAccounts() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let debit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "借记卡" })
        let food = try XCTUnwrap(store.expenseCategories.first { $0.presetKey == "expense_food" })
        try store.addTransaction(kind: .expense, amount: 38, category: food, account: debit, title: "午饭")

        let now = ISO8601DateFormatter().string(from: Date())
        let records = [
            TransactionExportRecord(
                id: UUID().uuidString,
                kind: TransactionKind.income.rawValue,
                title: "工资",
                categoryPresetKey: "income_salary",
                accountID: debit.id.uuidString,
                accountName: debit.name,
                accountKind: AssetKind.debitCard.rawValue,
                amount: "22000",
                occurredAt: now
            ),
            TransactionExportRecord(
                id: UUID().uuidString,
                kind: TransactionKind.income.rawValue,
                title: "现金退款",
                categoryPresetKey: "income_refund",
                accountID: UUID().uuidString,
                accountName: "现金钱包",
                accountKind: AssetKind.cash.rawValue,
                amount: "12",
                occurredAt: now
            )
        ]
        let data = try JSONEncoder().encode(records)

        try store.importData(data)

        XCTAssertEqual(store.transactions.count, 3)
        XCTAssertTrue(store.transactions.contains { $0.title == "午饭" })
        XCTAssertEqual(store.paymentAccounts.first { $0.id == debit.id }?.balance, 21_962)
        XCTAssertEqual(store.paymentAccounts.first { $0.name == "现金钱包" }?.balance, 12)

        try store.importData(data)

        XCTAssertEqual(store.transactions.count, 3)
    }

    func testDeletingAccountUsedByTransactionsIsRejected() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let debit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "借记卡" })
        let food = try XCTUnwrap(store.expenseCategories.first { $0.presetKey == "expense_food" })
        try store.addTransaction(kind: .expense, amount: 38, category: food, account: debit, title: "午饭")
        let asset = try XCTUnwrap(store.assets.first { $0.id == debit.id })

        XCTAssertThrowsError(try store.deleteAsset(asset)) { error in
            XCTAssertEqual(error.localizedDescription, "“借记卡”已经被账目使用，不能直接删除")
        }
        XCTAssertTrue(store.assets.contains { $0.id == debit.id })
    }

    func testLegacyDefaultAssetNamesAreNormalizedOnStartup() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let database = try SQLiteDatabase(url: url)
        try database.saveCategories(PreviewData.expenseCategories + PreviewData.incomeCategories)
        try database.saveAssets([
            asset(name: "支付宝花呗", kind: .alipayCredit, balance: 0),
            asset(name: "微信零钱", kind: .wechatChange, balance: 0),
            asset(name: "微信待还", kind: .wechatCredit, balance: 0)
        ])

        let store = AppStore(database: database)

        XCTAssertTrue(store.assets.contains { $0.kind == .alipayCredit && $0.name == "花呗" })
        XCTAssertTrue(store.assets.contains { $0.kind == .wechatChange && $0.name == "零钱" })
        XCTAssertTrue(store.assets.contains { $0.kind == .wechatCredit && $0.name == "微信分付" })
        XCTAssertFalse(store.assets.contains { $0.name == "支付宝花呗" || $0.name == "微信零钱" || $0.name == "微信待还" })
    }

    private func transaction(
        kind: TransactionKind,
        title: String,
        category: MoneyCategory,
        asset: AssetItem,
        amount: Decimal
    ) -> MoneyTransaction {
        MoneyTransaction(
            id: UUID(),
            kind: kind,
            title: title,
            category: category,
            account: MoneyAccount(
                id: asset.id,
                name: asset.name,
                symbolName: asset.kind.symbolName,
                balance: asset.balance
            ),
            amount: amount,
            occurredAt: Date()
        )
    }

    private func category(name: String, kind: CategoryKind, presetKey: String) -> MoneyCategory {
        MoneyCategory(
            id: UUID(),
            presetKey: presetKey,
            name: name,
            kind: kind,
            symbolName: "tag.fill",
            color: .red,
            sortOrder: 0,
            isSystemPreset: true
        )
    }

    private func asset(name: String, kind: AssetKind, balance: Decimal) -> AssetItem {
        AssetItem(
            id: UUID(),
            name: name,
            kind: kind,
            balance: balance,
            repayments: (0..<24).map {
                RepaymentMonth(id: UUID(), monthOffset: $0, amount: 0)
            },
            fundCost: nil,
            fundMarketValue: nil
        )
    }
}
