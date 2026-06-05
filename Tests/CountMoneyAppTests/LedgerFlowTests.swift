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

    func testIncomeUpdatesRealtimeAccountAndOverviewBalanceUntilDeleted() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let account = try XCTUnwrap(store.paymentAccounts.first { $0.name == "零钱通" })
        let salary = try XCTUnwrap(store.incomeCategories.first { $0.presetKey == "income_salary" })

        try store.addTransaction(kind: .income, amount: 1_000, category: salary, account: account, title: "工资")

        XCTAssertEqual(store.paymentAccounts.first { $0.id == account.id }?.balance, 1_000)
        XCTAssertEqual(store.ledgerAssets.first { $0.id == account.id }?.balance, 1_000)
        XCTAssertEqual(store.assetOverview.net, 1_000)

        let transaction = try XCTUnwrap(store.transactions.first { $0.title == "工资" })
        try store.deleteTransaction(transaction)

        XCTAssertEqual(store.paymentAccounts.first { $0.id == account.id }?.balance, 0)
        XCTAssertEqual(store.assetOverview.net, 0)
    }

    func testFundProfitIsCalculatedFromCurrentValueAndCost() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        var fund = try XCTUnwrap(store.assets.first { $0.kind == .fund })
        fund.fundCost = 1_000
        fund.fundMarketValue = 1_100
        fund.balance = fund.fundCurrentValue
        try store.updateAsset(fund)

        XCTAssertEqual(store.ledgerAssets.first { $0.id == fund.id }?.fundCurrentValue, 1_100)
        XCTAssertEqual(store.ledgerAssets.first { $0.id == fund.id }?.fundProfit, 100)
        XCTAssertEqual(store.assetOverview.fundHoldings, 1_100)

        try store.addFundProfit(assetID: fund.id, amount: -50, note: "")

        XCTAssertEqual(store.ledgerAssets.first { $0.id == fund.id }?.fundCurrentValue, 1_050)
        XCTAssertEqual(store.ledgerAssets.first { $0.id == fund.id }?.fundProfit, 50)
    }

    func testCustomCategoryKeepsChosenIconAndAppearsFirst() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))

        try store.addCategory(name: "房租", kind: .expense, symbolName: "house.fill")

        let category = try XCTUnwrap(store.expenseCategories.first)
        XCTAssertEqual(category.name, "房租")
        XCTAssertEqual(category.symbolName, "house.fill")
        XCTAssertFalse(category.isSystemPreset)
    }

    func testInstallmentRepaymentPlanCountsAsOverviewDebt() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let credit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "信用卡" })
        let food = try XCTUnwrap(store.expenseCategories.first { $0.presetKey == "expense_food" })

        try store.addTransaction(
            kind: .expense,
            amount: 100,
            category: food,
            account: credit,
            title: "分期",
            installmentMonths: 3
        )

        XCTAssertEqual(store.ledgerAssets.first { $0.id == credit.id }?.totalRepayment, 300)
        XCTAssertEqual(store.assetOverview.debt, 300)
    }

    func testWechatCreditSupportsInstallmentRepaymentPlan() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let wechatCredit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "微信分付" })
        let food = try XCTUnwrap(store.expenseCategories.first { $0.presetKey == "expense_food" })

        try store.addTransaction(
            kind: .expense,
            amount: 80,
            category: food,
            account: wechatCredit,
            title: "微信分付分期",
            installmentMonths: 2
        )

        let transaction = try XCTUnwrap(store.transactions.first { $0.title == "微信分付分期" })
        XCTAssertEqual(transaction.installmentMonths, 2)
        XCTAssertEqual(store.ledgerAssets.first { $0.id == wechatCredit.id }?.totalRepayment, 160)
        XCTAssertEqual(store.assetOverview.debt, 160)
    }

    func testCreditExpenseWithoutInstallmentAddsCurrentMonthRepayment() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let credit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "信用卡" })
        let food = try XCTUnwrap(store.expenseCategories.first { $0.presetKey == "expense_food" })

        try store.addTransaction(
            kind: .expense,
            amount: 120,
            category: food,
            account: credit,
            title: "晚饭"
        )

        let asset = try XCTUnwrap(store.ledgerAssets.first { $0.id == credit.id })
        XCTAssertEqual(asset.currentMonthRepayment, 120)
        XCTAssertEqual(asset.balance, 120)
        XCTAssertEqual(store.assetOverview.debt, 120)
        XCTAssertEqual(store.assetOverview.currentMonthRepayment, 120)
    }

    func testDeletingTransactionRemovesItFromRecentOverview() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let debit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "借记卡" })
        let food = try XCTUnwrap(store.expenseCategories.first { $0.presetKey == "expense_food" })

        try store.addTransaction(
            kind: .expense,
            amount: 42,
            category: food,
            account: debit,
            title: "待删除账目"
        )
        let transaction = try XCTUnwrap(store.transactions.first { $0.title == "待删除账目" })
        XCTAssertTrue(store.overview.recentTransactions.contains { $0.id == transaction.id })

        try store.deleteTransaction(transaction)

        XCTAssertFalse(store.transactions.contains { $0.id == transaction.id })
        XCTAssertFalse(store.overview.recentTransactions.contains { $0.id == transaction.id })
    }

    func testDebtAccountsCanSpendButCannotFundRepayment() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))

        XCTAssertTrue(store.paymentAccounts.contains { $0.name == "微信分付" })
        XCTAssertTrue(store.paymentAccounts.contains { $0.name == "美团月付" })
        XCTAssertTrue(store.paymentAccounts.contains { $0.name == "花呗" })
        XCTAssertTrue(store.paymentAccounts.contains { $0.name == "京东白条" })
        XCTAssertTrue(store.paymentAccounts.contains { $0.name == "信用卡" })

        XCTAssertFalse(store.repaymentPaymentAccounts.contains { $0.name == "微信分付" })
        XCTAssertFalse(store.repaymentPaymentAccounts.contains { $0.name == "美团月付" })
        XCTAssertFalse(store.repaymentPaymentAccounts.contains { $0.name == "花呗" })
        XCTAssertFalse(store.repaymentPaymentAccounts.contains { $0.name == "京东白条" })
        XCTAssertFalse(store.repaymentPaymentAccounts.contains { $0.name == "信用卡" })
    }

    func testDeletingCreditExpenseRestoresCurrentMonthRepayment() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let credit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "信用卡" })
        let food = try XCTUnwrap(store.expenseCategories.first { $0.presetKey == "expense_food" })

        try store.addTransaction(
            kind: .expense,
            amount: 120,
            category: food,
            account: credit,
            title: "晚饭"
        )
        let transaction = try XCTUnwrap(store.transactions.first { $0.title == "晚饭" })

        try store.deleteTransaction(transaction)

        let asset = try XCTUnwrap(store.ledgerAssets.first { $0.id == credit.id })
        XCTAssertEqual(asset.currentMonthRepayment, 0)
        XCTAssertEqual(asset.balance, 0)
        XCTAssertEqual(store.assetOverview.debt, 0)
        XCTAssertEqual(store.assetOverview.currentMonthRepayment, 0)
    }

    func testDeletingInstallmentExpenseRestoresRepaymentPlan() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let credit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "信用卡" })
        let food = try XCTUnwrap(store.expenseCategories.first { $0.presetKey == "expense_food" })

        try store.addTransaction(
            kind: .expense,
            amount: 100,
            category: food,
            account: credit,
            title: "分期",
            installmentMonths: 3
        )
        let transaction = try XCTUnwrap(store.transactions.first { $0.title == "分期" })

        try store.deleteTransaction(transaction)

        let asset = try XCTUnwrap(store.ledgerAssets.first { $0.id == credit.id })
        XCTAssertEqual(asset.totalRepayment, 0)
        XCTAssertEqual(asset.balance, 0)
        XCTAssertEqual(store.assetOverview.debt, 0)
    }

    func testRepaymentReducesDebtAndPendingRepayment() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let credit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "信用卡" })
        let debit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "借记卡" })
        let food = try XCTUnwrap(store.expenseCategories.first { $0.presetKey == "expense_food" })
        let repayment = try XCTUnwrap(store.expenseCategories.first(where: \.isRepayment))

        try store.addTransaction(
            kind: .expense,
            amount: 120,
            category: food,
            account: credit,
            title: "晚饭"
        )
        let repaymentAccount = try XCTUnwrap(store.repaymentAccounts.first { $0.id == credit.id })

        try store.addTransaction(
            kind: .expense,
            amount: 50,
            category: repayment,
            account: repaymentAccount,
            title: "还款",
            paymentAccount: debit
        )

        let asset = try XCTUnwrap(store.ledgerAssets.first { $0.id == credit.id })
        XCTAssertEqual(asset.currentMonthRepayment, 70)
        XCTAssertEqual(asset.balance, 70)
        XCTAssertEqual(store.ledgerAssets.first { $0.id == debit.id }?.balance, -50)
        XCTAssertEqual(store.assetOverview.debt, 70)
        XCTAssertEqual(store.assetOverview.currentMonthRepayment, 70)
        XCTAssertEqual(store.overview.expense, 170)
        XCTAssertEqual(store.overview.income, 0)
        XCTAssertTrue(store.transactions.contains {
            $0.kind == .expense
                && $0.category.isRepayment
                && $0.amount == 50
                && $0.account.id == credit.id
                && $0.paymentAccount?.id == debit.id
        })
    }

    func testDeletingRepaymentRestoresDebtAndPaymentAccount() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let credit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "信用卡" })
        let debit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "借记卡" })
        let food = try XCTUnwrap(store.expenseCategories.first { $0.presetKey == "expense_food" })
        let repayment = try XCTUnwrap(store.expenseCategories.first(where: \.isRepayment))

        try store.addTransaction(
            kind: .expense,
            amount: 120,
            category: food,
            account: credit,
            title: "晚饭"
        )
        let repaymentAccount = try XCTUnwrap(store.repaymentAccounts.first { $0.id == credit.id })
        try store.addTransaction(
            kind: .expense,
            amount: 50,
            category: repayment,
            account: repaymentAccount,
            title: "还款",
            paymentAccount: debit
        )
        let repaymentTransaction = try XCTUnwrap(store.transactions.first { $0.category.isRepayment })

        try store.deleteTransaction(repaymentTransaction)

        let asset = try XCTUnwrap(store.ledgerAssets.first { $0.id == credit.id })
        XCTAssertEqual(asset.currentMonthRepayment, 120)
        XCTAssertEqual(asset.balance, 120)
        XCTAssertEqual(store.ledgerAssets.first { $0.id == debit.id }?.balance, 0)
        XCTAssertEqual(store.assetOverview.debt, 120)
        XCTAssertEqual(store.assetOverview.currentMonthRepayment, 120)
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
        XCTAssertTrue(store.expenseCategories.contains(where: \.isRepayment))
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
