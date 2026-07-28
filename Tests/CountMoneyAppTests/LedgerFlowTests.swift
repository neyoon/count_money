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

    func testJSONExportCanBeImportedByFreshStore() throws {
        let sourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-source-\(UUID().uuidString).sqlite")
        let destinationURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-destination-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: sourceURL)
            try? FileManager.default.removeItem(at: destinationURL)
        }

        let source = AppStore(database: try SQLiteDatabase(url: sourceURL))
        let account = try XCTUnwrap(source.paymentAccounts.first { $0.name == "借记卡" })
        var fund = try XCTUnwrap(source.assets.first { $0.kind == .fund })
        let salary = try XCTUnwrap(source.incomeCategories.first { $0.presetKey == "income_salary" })
        let food = try XCTUnwrap(source.expenseCategories.first { $0.presetKey == "expense_food" })

        fund.fundCost = 1_000
        fund.fundMarketValue = 1_050
        fund.balance = fund.fundCurrentValue
        try source.updateAsset(fund)
        try source.addFundActivity(assetID: fund.id, kind: .investment, amount: 500, note: "定投")
        try source.addFundActivity(assetID: fund.id, kind: .valuation, amount: -25, note: "回撤")
        try source.addTransaction(kind: .income, amount: 1_000, category: salary, account: account, title: "工资")
        try source.addTransaction(kind: .expense, amount: 38, category: food, account: account, title: "午饭")

        let data = try source.exportData()
        let exportFile = try JSONDecoder().decode(LedgerExportFile.self, from: data)
        let fundRecord = try XCTUnwrap(exportFile.assets.first { $0.id == fund.id.uuidString })

        XCTAssertEqual(exportFile.version, 2)
        XCTAssertEqual(exportFile.transactions.count, 2)
        XCTAssertTrue(exportFile.transactions.allSatisfy { $0.accountID != nil })
        XCTAssertTrue(exportFile.transactions.allSatisfy { $0.accountKind == AssetKind.debitCard.rawValue })
        XCTAssertEqual(fundRecord.kind, AssetKind.fund.rawValue)
        XCTAssertEqual(fundRecord.fundCost, "1500")
        XCTAssertEqual(fundRecord.fundMarketValue, "1025")
        XCTAssertEqual(fundRecord.balance, "1025")
        XCTAssertEqual(fundRecord.fundActivities.count, 2)

        let destination = AppStore(database: try SQLiteDatabase(url: destinationURL))
        try destination.importData(data)

        XCTAssertEqual(destination.transactions.count, 2)
        XCTAssertTrue(destination.transactions.contains { $0.title == "工资" })
        XCTAssertTrue(destination.transactions.contains { $0.title == "午饭" })
        XCTAssertEqual(destination.paymentAccounts.first { $0.name == "借记卡" }?.balance, 962)
        let importedFund = try XCTUnwrap(destination.assets.first { $0.id == fund.id })
        XCTAssertEqual(importedFund.fundCost, 1_500)
        XCTAssertEqual(importedFund.fundMarketValue, 1_025)
        XCTAssertEqual(importedFund.balance, 1_025)
        XCTAssertEqual(importedFund.fundActivities.count, 2)
        XCTAssertTrue(importedFund.fundActivities.contains { $0.kind == .investment && $0.amount == 500 && $0.note == "定投" })
        XCTAssertTrue(importedFund.fundActivities.contains { $0.kind == .valuation && $0.amount == -25 && $0.note == "回撤" })
    }

    func testClearingAllDataRestoresEmptyDefaultLedger() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let account = try XCTUnwrap(store.paymentAccounts.first { $0.name == "借记卡" })
        let salary = try XCTUnwrap(store.incomeCategories.first { $0.presetKey == "income_salary" })
        var fund = try XCTUnwrap(store.assets.first { $0.kind == .fund })

        try store.addCategory(name: "房租", kind: .expense)
        try store.addTransaction(kind: .income, amount: 1_000, category: salary, account: account, title: "工资")
        fund.fundCost = 1_000
        fund.fundMarketValue = 1_100
        fund.balance = fund.fundCurrentValue
        try store.updateAsset(fund)
        try store.addFundActivity(assetID: fund.id, kind: .valuation, amount: 50, note: "上涨")

        try store.clearAllData()

        XCTAssertTrue(store.transactions.isEmpty)
        XCTAssertFalse(store.expenseCategories.contains { $0.name == "房租" })
        XCTAssertEqual(store.assets.count, PreviewData.assets.count)
        XCTAssertEqual(store.paymentAccounts.first { $0.name == "借记卡" }?.balance, 0)
        let clearedFund = try XCTUnwrap(store.assets.first { $0.kind == .fund })
        XCTAssertEqual(clearedFund.fundCost, 0)
        XCTAssertEqual(clearedFund.fundMarketValue, 0)
        XCTAssertTrue(clearedFund.fundActivities.isEmpty)

        let reopenedStore = AppStore(database: try SQLiteDatabase(url: url))
        XCTAssertTrue(reopenedStore.transactions.isEmpty)
        XCTAssertFalse(reopenedStore.expenseCategories.contains { $0.name == "房租" })
        XCTAssertEqual(reopenedStore.paymentAccounts.first { $0.name == "借记卡" }?.balance, 0)
        let reopenedFund = try XCTUnwrap(reopenedStore.assets.first { $0.kind == .fund })
        XCTAssertEqual(reopenedFund.fundCost, 0)
        XCTAssertEqual(reopenedFund.fundMarketValue, 0)
        XCTAssertTrue(reopenedFund.fundActivities.isEmpty)
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

    func testBalanceAdjustmentChangesAccountWithoutCountingAsIncome() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let account = try XCTUnwrap(store.paymentAccounts.first { $0.name == "零钱通" })
        let adjustment = try XCTUnwrap(store.incomeCategories.first { $0.isBalanceAdjustment })

        try store.addTransaction(
            kind: .income,
            amount: 500,
            category: adjustment,
            account: account,
            title: "余额校正"
        )

        let transaction = try XCTUnwrap(store.transactions.first { $0.category.isBalanceAdjustment })
        XCTAssertEqual(store.ledgerAssets.first { $0.id == account.id }?.balance, 500)
        XCTAssertEqual(store.assetOverview.net, 500)
        XCTAssertEqual(store.overview.income, 0)
        XCTAssertEqual(store.overview.dailyCashflows.map(\.income).reduce(0, +), 0)
        XCTAssertFalse(store.overview.categoryIncome.contains { $0.category.isBalanceAdjustment })
        XCTAssertEqual(transaction.statisticsBalanceChange, 500)
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

    func testRecentOverviewKeepsTenTransactions() {
        let calendar = Calendar(identifier: .gregorian)
        let now = calendar.date(from: DateComponents(year: 2026, month: 6, day: 5, hour: 12))!
        let debit = asset(name: "借记卡", kind: .debitCard, balance: 0)
        let food = category(name: "餐饮", kind: .expense, presetKey: "expense_food")
        let transactions = (0..<12).map { index in
            var transaction = transaction(
                kind: .expense,
                title: "账目 \(index)",
                category: food,
                asset: debit,
                amount: Decimal(index + 1)
            )
            transaction.occurredAt = calendar.date(byAdding: .minute, value: -index, to: now)!
            return transaction
        }

        let overview = MonthlyOverview(transactions: transactions, calendar: calendar, now: now)

        XCTAssertEqual(overview.recentTransactions.count, 10)
        XCTAssertEqual(overview.recentTransactions.first?.title, "账目 0")
        XCTAssertEqual(overview.recentTransactions.last?.title, "账目 9")
    }

    func testHistorySnapshotUsesTransactionsAndFundRecordsThroughSelectedDate() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let calendar = Calendar(identifier: .gregorian)
        let dayOne = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 10)))
        let dayThree = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 10)))
        let store = AppStore(database: try SQLiteDatabase(url: url))
        let debit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "借记卡" })
        let credit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "信用卡" })
        let salary = try XCTUnwrap(store.incomeCategories.first { $0.presetKey == "income_salary" })
        let food = try XCTUnwrap(store.expenseCategories.first { $0.presetKey == "expense_food" })
        let fund = try XCTUnwrap(store.assets.first { $0.kind == .fund })

        try store.addTransaction(kind: .income, amount: 100, category: salary, account: debit, title: "工资", occurredAt: dayOne)
        try store.addTransaction(kind: .expense, amount: 30, category: food, account: debit, title: "午饭", occurredAt: dayThree)
        try store.addTransaction(kind: .expense, amount: 50, category: food, account: credit, title: "信用卡消费", occurredAt: dayThree)
        try store.addFundActivity(assetID: fund.id, kind: .investment, amount: 100, note: "", occurredAt: dayOne)
        try store.addFundActivity(assetID: fund.id, kind: .valuation, amount: 20, note: "", occurredAt: dayThree)

        let snapshot = store.historySnapshot(on: dayOne)
        let debitSnapshot = try XCTUnwrap(snapshot.assets.first { $0.id == debit.id })
        let creditSnapshot = try XCTUnwrap(snapshot.assets.first { $0.id == credit.id })
        let fundSnapshot = try XCTUnwrap(snapshot.assets.first { $0.id == fund.id })

        XCTAssertEqual(snapshot.overview.income, 100)
        XCTAssertEqual(snapshot.overview.expense, 0)
        XCTAssertEqual(debitSnapshot.balance, 100)
        XCTAssertEqual(creditSnapshot.totalDebt, 0)
        XCTAssertEqual(fundSnapshot.fundCost, 100)
        XCTAssertEqual(fundSnapshot.fundCurrentValue, 100)
        XCTAssertEqual(snapshot.assetOverview.net, 200)
    }

    func testHistoryComparisonSummarizesCurrentMinusHistoricalNetChange() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let calendar = Calendar(identifier: .gregorian)
        let dayOne = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 10)))
        let dayThree = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 3, day: 3, hour: 10)))
        let store = AppStore(database: try SQLiteDatabase(url: url))
        let debit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "借记卡" })
        let salary = try XCTUnwrap(store.incomeCategories.first { $0.presetKey == "income_salary" })
        let fund = try XCTUnwrap(store.assets.first { $0.kind == .fund })

        try store.addTransaction(kind: .income, amount: 100, category: salary, account: debit, title: "工资", occurredAt: dayOne)
        try store.addFundActivity(assetID: fund.id, kind: .investment, amount: 100, note: "", occurredAt: dayOne)
        try store.addFundActivity(assetID: fund.id, kind: .valuation, amount: 20, note: "", occurredAt: dayThree)

        let comparison = store.historyComparison(from: dayOne)

        XCTAssertEqual(comparison.netChange, 20)
        XCTAssertEqual(comparison.fundChange, 20)
        XCTAssertTrue(comparison.assetChanges.contains { $0.id == fund.id && $0.change == 20 })
    }

    func testAddingTransactionKeepsProvidedDate() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let debit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "借记卡" })
        let food = try XCTUnwrap(store.expenseCategories.first { $0.presetKey == "expense_food" })
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-05T10:20:30Z"))

        try store.addTransaction(
            kind: .expense,
            amount: 42,
            category: food,
            account: debit,
            title: "指定日期",
            occurredAt: date
        )

        let transaction = try XCTUnwrap(store.transactions.first { $0.title == "指定日期" })
        XCTAssertEqual(transaction.occurredAt, date)
    }

    func testUpdatingTransactionRecalculatesLedgerEffects() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let credit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "信用卡" })
        let debit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "借记卡" })
        let food = try XCTUnwrap(store.expenseCategories.first { $0.presetKey == "expense_food" })
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-05T10:20:30Z"))

        try store.addTransaction(
            kind: .expense,
            amount: 120,
            category: food,
            account: credit,
            title: "待修改"
        )
        let transaction = try XCTUnwrap(store.transactions.first { $0.title == "待修改" })

        try store.updateTransaction(
            transaction,
            kind: .expense,
            amount: 60,
            category: food,
            account: debit,
            title: "已修改",
            occurredAt: date
        )

        let updated = try XCTUnwrap(store.transactions.first { $0.id == transaction.id })
        XCTAssertEqual(updated.title, "已修改")
        XCTAssertEqual(updated.amount, 60)
        XCTAssertEqual(updated.account.id, debit.id)
        XCTAssertEqual(updated.occurredAt, date)
        XCTAssertEqual(store.ledgerAssets.first { $0.id == credit.id }?.currentMonthRepayment, 0)
        XCTAssertEqual(store.ledgerAssets.first { $0.id == credit.id }?.balance, 0)
        XCTAssertEqual(store.ledgerAssets.first { $0.id == debit.id }?.balance, -60)
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
        XCTAssertEqual(store.overview.expense, 120)
        XCTAssertEqual(store.overview.income, 0)
        XCTAssertFalse(store.overview.categorySpending.contains { $0.category.isRepayment })
        XCTAssertEqual(store.overview.dailyCashflows.map(\.expense).reduce(0, +), 120)
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

    func testTransferMovesMoneyWithoutChangingIncomeExpenseOrNetAssets() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        let importedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-imported-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
            try? FileManager.default.removeItem(at: importedURL)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let source = try XCTUnwrap(store.balanceAccounts.first { $0.name == "借记卡" })
        let destination = try XCTUnwrap(store.balanceAccounts.first { $0.name == "零钱通" })
        let transfer = try XCTUnwrap(store.expenseCategories.first(where: \.isTransfer))

        try store.addTransaction(
            kind: .transfer,
            amount: 500,
            category: transfer,
            account: destination,
            title: "银行卡提现",
            paymentAccount: source
        )

        XCTAssertEqual(store.ledgerAssets.first { $0.id == source.id }?.balance, -500)
        XCTAssertEqual(store.ledgerAssets.first { $0.id == destination.id }?.balance, 500)
        XCTAssertEqual(store.assetOverview.net, 0)
        XCTAssertEqual(store.overview.expense, 0)
        XCTAssertEqual(store.overview.income, 0)
        XCTAssertEqual(store.overview.dailyCashflows.map(\.expense).reduce(0, +), 0)
        XCTAssertFalse(store.overview.categorySpending.contains { $0.category.isTransfer })

        let transaction = try XCTUnwrap(store.transactions.first { $0.category.isTransfer })
        XCTAssertEqual(transaction.paymentAccount?.id, source.id)
        XCTAssertEqual(transaction.account.id, destination.id)

        let importedStore = AppStore(database: try SQLiteDatabase(url: importedURL))
        try importedStore.importData(store.exportData())
        let importedTransaction = try XCTUnwrap(importedStore.transactions.first { $0.category.isTransfer })
        XCTAssertEqual(importedTransaction.kind, .transfer)
        XCTAssertEqual(importedStore.ledgerAssets.first { $0.id == source.id }?.balance, -500)
        XCTAssertEqual(importedStore.ledgerAssets.first { $0.id == destination.id }?.balance, 500)

        try store.deleteTransaction(transaction)

        XCTAssertEqual(store.ledgerAssets.first { $0.id == source.id }?.balance, 0)
        XCTAssertEqual(store.ledgerAssets.first { $0.id == destination.id }?.balance, 0)
    }

    func testTransferRejectsMissingOrIdenticalAccounts() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let account = try XCTUnwrap(store.balanceAccounts.first { $0.name == "借记卡" })
        let otherAccount = try XCTUnwrap(store.balanceAccounts.first { $0.name == "零钱通" })
        let transfer = try XCTUnwrap(store.expenseCategories.first(where: \.isTransfer))

        XCTAssertThrowsError(
            try store.addTransaction(
                kind: .transfer,
                amount: 100,
                category: transfer,
                account: account,
                title: "无效转账"
            )
        )
        XCTAssertThrowsError(
            try store.addTransaction(
                kind: .transfer,
                amount: 100,
                category: transfer,
                account: account,
                title: "无效转账",
                paymentAccount: account
            )
        )
        XCTAssertThrowsError(
            try store.addTransaction(
                kind: .expense,
                amount: 100,
                category: transfer,
                account: otherAccount,
                title: "类型不匹配",
                paymentAccount: account
            )
        )
        XCTAssertFalse(store.transactions.contains { $0.category.isTransfer })
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
        XCTAssertTrue(store.expenseCategories.contains(where: \.isTransfer))
        XCTAssertTrue(store.expenseCategories.contains(where: \.isRepayment))
    }

    func testFundPurchaseMovesCashIntoFundWithoutCountingAsExpense() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let debit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "借记卡" })
        let fund = try XCTUnwrap(store.assets.first { $0.kind == .fund })
        let fundAccount = MoneyAccount(
            id: fund.id,
            name: fund.name,
            symbolName: fund.kind.symbolName,
            balance: fund.fundCurrentValue
        )
        let purchase = try XCTUnwrap(store.expenseCategories.first(where: \.isFundPurchase))

        try store.addTransaction(
            kind: .expense,
            amount: 300,
            category: purchase,
            account: fundAccount,
            title: "购买基金",
            paymentAccount: debit
        )

        let updatedFund = try XCTUnwrap(store.ledgerAssets.first { $0.id == fund.id })
        XCTAssertEqual(store.ledgerAssets.first { $0.id == debit.id }?.balance, -300)
        XCTAssertEqual(updatedFund.fundCost, 300)
        XCTAssertEqual(updatedFund.fundCurrentValue, 300)
        XCTAssertEqual(store.overview.expense, 0)
        XCTAssertTrue(store.transactions.contains {
            $0.category.isFundPurchase
                && $0.account.id == fund.id
                && $0.paymentAccount?.id == debit.id
        })
    }

    func testFundRedemptionMovesFundIntoCashWithoutCountingAsIncome() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("count-money-\(UUID().uuidString).sqlite")
        defer {
            try? FileManager.default.removeItem(at: url)
        }

        let store = AppStore(database: try SQLiteDatabase(url: url))
        let debit = try XCTUnwrap(store.paymentAccounts.first { $0.name == "借记卡" })
        var fund = try XCTUnwrap(store.assets.first { $0.kind == .fund })
        fund.fundCost = 500
        fund.fundMarketValue = 500
        fund.balance = fund.fundCurrentValue
        try store.updateAsset(fund)
        let fundAccount = MoneyAccount(
            id: fund.id,
            name: fund.name,
            symbolName: fund.kind.symbolName,
            balance: fund.fundCurrentValue
        )
        let redemption = try XCTUnwrap(store.incomeCategories.first(where: \.isFundRedemption))

        try store.addTransaction(
            kind: .income,
            amount: 200,
            category: redemption,
            account: debit,
            title: "基金赎回",
            paymentAccount: fundAccount
        )

        let updatedFund = try XCTUnwrap(store.ledgerAssets.first { $0.id == fund.id })
        XCTAssertEqual(store.ledgerAssets.first { $0.id == debit.id }?.balance, 200)
        XCTAssertEqual(updatedFund.fundCost, 300)
        XCTAssertEqual(updatedFund.fundCurrentValue, 300)
        XCTAssertEqual(store.overview.income, 0)
        XCTAssertTrue(store.transactions.contains {
            $0.category.isFundRedemption
                && $0.account.id == debit.id
                && $0.paymentAccount?.id == fund.id
        })
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
