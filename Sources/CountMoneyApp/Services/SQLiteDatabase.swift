import Foundation
import SQLite3
import SwiftUI

struct SQLiteSnapshot {
    var categories: [MoneyCategory]
    var transactions: [MoneyTransaction]
    var assets: [AssetItem]
}

final class SQLiteDatabase {
    private let db: OpaquePointer?

    init(url: URL? = nil) throws {
        let url = try url ?? Self.databaseURL()
        var handle: OpaquePointer?

        guard sqlite3_open(url.path, &handle) == SQLITE_OK else {
            throw SQLiteFailure.openFailed
        }

        db = handle
        try migrate()
    }

    deinit {
        sqlite3_close(db)
    }

    func loadSnapshot() throws -> SQLiteSnapshot {
        let categories = try loadCategories()
        let transactions = try loadTransactions(categories: categories)
        let assets = try loadAssets()

        return SQLiteSnapshot(
            categories: categories,
            transactions: transactions,
            assets: assets
        )
    }

    func saveCategories(_ categories: [MoneyCategory]) throws {
        try transaction {
            try execute("DELETE FROM categories")

            let sql = """
            INSERT INTO categories (
                id, preset_key, name, kind, symbol_name, sort_order, is_system_preset
            ) VALUES (?, ?, ?, ?, ?, ?, ?)
            """

            for category in categories {
                try withStatement(sql) { statement in
                    bind(statement, 1, category.id.uuidString)
                    bind(statement, 2, category.presetKey)
                    bind(statement, 3, category.name)
                    bind(statement, 4, category.kind.rawValue)
                    bind(statement, 5, category.symbolName)
                    sqlite3_bind_int(statement, 6, Int32(category.sortOrder))
                    sqlite3_bind_int(statement, 7, category.isSystemPreset ? 1 : 0)
                    try stepDone(statement)
                }
            }
        }
    }

    func saveTransactions(_ transactions: [MoneyTransaction]) throws {
        try transaction {
            try replaceTransactions(transactions)
        }
    }

    func saveAssets(_ assets: [AssetItem]) throws {
        try transaction {
            try replaceAssets(assets)
        }
    }

    func saveLedger(transactions: [MoneyTransaction], assets: [AssetItem]) throws {
        try transaction {
            try replaceTransactions(transactions)
            try replaceAssets(assets)
        }
    }

    private func migrate() throws {
        try execute("""
        CREATE TABLE IF NOT EXISTS categories (
            id TEXT PRIMARY KEY,
            preset_key TEXT NOT NULL,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            symbol_name TEXT NOT NULL,
            sort_order INTEGER NOT NULL,
            is_system_preset INTEGER NOT NULL
        )
        """)

        try execute("""
        CREATE TABLE IF NOT EXISTS transactions (
            id TEXT PRIMARY KEY,
            kind TEXT NOT NULL,
            title TEXT NOT NULL,
            category_id TEXT NOT NULL,
            account_id TEXT,
            account_name TEXT NOT NULL,
            account_symbol_name TEXT,
            amount TEXT NOT NULL,
            occurred_at TEXT NOT NULL
        )
        """)

        try addColumnIfNeeded(table: "transactions", column: "account_id", definition: "TEXT")
        try addColumnIfNeeded(table: "transactions", column: "account_symbol_name", definition: "TEXT")
        try addColumnIfNeeded(table: "transactions", column: "payment_account_id", definition: "TEXT")
        try addColumnIfNeeded(table: "transactions", column: "payment_account_name", definition: "TEXT")
        try addColumnIfNeeded(table: "transactions", column: "payment_account_symbol_name", definition: "TEXT")
        try addColumnIfNeeded(table: "transactions", column: "installment_months", definition: "INTEGER")
        try addColumnIfNeeded(table: "transactions", column: "repayment_adjustments", definition: "TEXT")

        try execute("""
        CREATE TABLE IF NOT EXISTS assets (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            kind TEXT NOT NULL,
            balance TEXT NOT NULL,
            fund_cost TEXT,
            fund_market_value TEXT
        )
        """)

        try execute("""
        CREATE TABLE IF NOT EXISTS repayments (
            id TEXT PRIMARY KEY,
            asset_id TEXT NOT NULL,
            month_offset INTEGER NOT NULL,
            amount TEXT NOT NULL,
            FOREIGN KEY(asset_id) REFERENCES assets(id) ON DELETE CASCADE
        )
        """)

        try execute("""
        CREATE TABLE IF NOT EXISTS fund_records (
            id TEXT PRIMARY KEY,
            asset_id TEXT NOT NULL,
            kind TEXT NOT NULL,
            amount TEXT NOT NULL,
            occurred_at TEXT NOT NULL,
            note TEXT NOT NULL,
            FOREIGN KEY(asset_id) REFERENCES assets(id) ON DELETE CASCADE
        )
        """)
    }

    private func loadCategories() throws -> [MoneyCategory] {
        let sql = """
        SELECT id, preset_key, name, kind, symbol_name, sort_order, is_system_preset
        FROM categories
        ORDER BY sort_order ASC
        """

        return try rows(sql) { statement in
            let presetKey = text(statement, 1)

            return MoneyCategory(
                id: UUID(uuidString: text(statement, 0)) ?? UUID(),
                presetKey: presetKey,
                name: text(statement, 2),
                kind: CategoryKind(rawValue: text(statement, 3)) ?? .expense,
                symbolName: text(statement, 4),
                color: color(for: presetKey),
                sortOrder: Int(sqlite3_column_int(statement, 5)),
                isSystemPreset: sqlite3_column_int(statement, 6) == 1
            )
        }
    }

    private func loadTransactions(categories: [MoneyCategory]) throws -> [MoneyTransaction] {
        let sql = """
        SELECT id, kind, title, category_id, account_id, account_name, account_symbol_name, amount, occurred_at,
               payment_account_id, payment_account_name, payment_account_symbol_name, installment_months,
               repayment_adjustments
        FROM transactions
        ORDER BY occurred_at DESC
        """

        return try rows(sql) { statement in
            let kind = TransactionKind(rawValue: text(statement, 1)) ?? .expense
            let categoryId = text(statement, 3)
            let category = categories.first { $0.id.uuidString == categoryId }
                ?? PreviewData.category("", fallbackKind: kind)

            return MoneyTransaction(
                id: UUID(uuidString: text(statement, 0)) ?? UUID(),
                kind: kind,
                title: text(statement, 2),
                category: category,
                account: MoneyAccount(
                    id: UUID(uuidString: text(statement, 4)) ?? UUID(),
                    name: text(statement, 5),
                    symbolName: optionalText(statement, 6) ?? "creditcard.fill",
                    balance: 0
                ),
                paymentAccount: optionalAccount(
                    id: optionalText(statement, 9),
                    name: optionalText(statement, 10),
                    symbolName: optionalText(statement, 11)
                ),
                amount: try decimal(statement, 7, table: "transactions", column: "amount"),
                installmentMonths: optionalInt(statement, 12),
                repaymentAdjustments: try repaymentAdjustments(statement, 13),
                occurredAt: ISO8601DateFormatter().date(from: text(statement, 8)) ?? Date()
            )
        }
    }

    private func loadAssets() throws -> [AssetItem] {
        let repayments = try loadRepayments()
        let fundActivities = try loadFundActivities()
        let sql = """
        SELECT id, name, kind, balance, fund_cost, fund_market_value
        FROM assets
        ORDER BY rowid ASC
        """

        return try rows(sql) { statement in
            let assetId = text(statement, 0)
            let kind = AssetKind(rawValue: text(statement, 2)) ?? .cash
            let loadedRepayments = repayments[assetId] ?? emptyRepayments()

            return AssetItem(
                id: UUID(uuidString: assetId) ?? UUID(),
                name: text(statement, 1),
                kind: kind,
                balance: try decimal(statement, 3, table: "assets", column: "balance"),
                repayments: loadedRepayments,
                fundCost: try optionalDecimal(statement, 4, table: "assets", column: "fund_cost"),
                fundMarketValue: try optionalDecimal(statement, 5, table: "assets", column: "fund_market_value"),
                fundActivities: fundActivities[assetId] ?? []
            )
        }
    }

    private func loadRepayments() throws -> [String: [RepaymentMonth]] {
        let sql = """
        SELECT id, asset_id, month_offset, amount
        FROM repayments
        ORDER BY month_offset ASC
        """

        let pairs = try rows(sql) { statement in
            (
                assetId: text(statement, 1),
                repayment: RepaymentMonth(
                    id: UUID(uuidString: text(statement, 0)) ?? UUID(),
                    monthOffset: Int(sqlite3_column_int(statement, 2)),
                    amount: try decimal(statement, 3, table: "repayments", column: "amount")
                )
            )
        }

        return Dictionary(grouping: pairs, by: \.assetId)
            .mapValues { items in
                let loaded = items.map(\.repayment)
                return (0..<24).map { offset in
                    loaded.first { $0.monthOffset == offset }
                        ?? RepaymentMonth(id: UUID(), monthOffset: offset, amount: 0)
                }
            }
    }

    private func loadFundActivities() throws -> [String: [FundActivity]] {
        let sql = """
        SELECT id, asset_id, kind, amount, occurred_at, note
        FROM fund_records
        ORDER BY occurred_at DESC
        """

        let pairs = try rows(sql) { statement in
            (
                assetId: text(statement, 1),
                record: FundActivity(
                    id: UUID(uuidString: text(statement, 0)) ?? UUID(),
                    kind: FundActivityKind(rawValue: text(statement, 2)) ?? .valuation,
                    amount: try decimal(statement, 3, table: "fund_records", column: "amount"),
                    occurredAt: ISO8601DateFormatter().date(from: text(statement, 4)) ?? Date(),
                    note: text(statement, 5)
                )
            )
        }

        return Dictionary(grouping: pairs, by: \.assetId)
            .mapValues { $0.map(\.record) }
    }

    private func addColumnIfNeeded(table: String, column: String, definition: String) throws {
        let existing = try tableColumns(table)
        guard !existing.contains(column) else { return }
        try execute("ALTER TABLE \(table) ADD COLUMN \(column) \(definition)")
    }

    private func tableColumns(_ table: String) throws -> Set<String> {
        let safeTable = table.replacingOccurrences(of: "'", with: "''")
        return Set(try rows("PRAGMA table_info('\(safeTable)')") { statement in
            text(statement, 1)
        })
    }

    private func transaction(_ body: () throws -> Void) throws {
        try execute("BEGIN IMMEDIATE")
        do {
            try body()
            try execute("COMMIT")
        } catch {
            try? execute("ROLLBACK")
            throw error
        }
    }

    private func replaceTransactions(_ transactions: [MoneyTransaction]) throws {
        try execute("DELETE FROM transactions")

        let sql = """
        INSERT INTO transactions (
            id, kind, title, category_id, account_id, account_name, account_symbol_name,
            payment_account_id, payment_account_name, payment_account_symbol_name, installment_months,
            repayment_adjustments, amount, occurred_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """

        for item in transactions {
            try withStatement(sql) { statement in
                bind(statement, 1, item.id.uuidString)
                bind(statement, 2, item.kind.rawValue)
                bind(statement, 3, item.title)
                bind(statement, 4, item.category.id.uuidString)
                bind(statement, 5, item.account.id.uuidString)
                bind(statement, 6, item.account.name)
                bind(statement, 7, item.account.symbolName)
                bind(statement, 8, item.paymentAccount?.id.uuidString)
                bind(statement, 9, item.paymentAccount?.name)
                bind(statement, 10, item.paymentAccount?.symbolName)
                bind(statement, 11, item.installmentMonths)
                bind(statement, 12, try repaymentAdjustmentsText(item.repaymentAdjustments))
                bind(statement, 13, decimalText(item.amount))
                bind(statement, 14, ISO8601DateFormatter().string(from: item.occurredAt))
                try stepDone(statement)
            }
        }
    }

    private func replaceAssets(_ assets: [AssetItem]) throws {
        try execute("DELETE FROM fund_records")
        try execute("DELETE FROM repayments")
        try execute("DELETE FROM assets")

        let assetSQL = """
        INSERT INTO assets (
            id, name, kind, balance, fund_cost, fund_market_value
        ) VALUES (?, ?, ?, ?, ?, ?)
        """
        let repaymentSQL = """
        INSERT INTO repayments (
            id, asset_id, month_offset, amount
        ) VALUES (?, ?, ?, ?)
        """
        let fundRecordSQL = """
        INSERT INTO fund_records (
            id, asset_id, kind, amount, occurred_at, note
        ) VALUES (?, ?, ?, ?, ?, ?)
        """

        for asset in assets {
            try withStatement(assetSQL) { statement in
                bind(statement, 1, asset.id.uuidString)
                bind(statement, 2, asset.name)
                bind(statement, 3, asset.kind.rawValue)
                bind(statement, 4, decimalText(asset.balance))
                bind(statement, 5, asset.fundCost.map(decimalText))
                bind(statement, 6, asset.fundMarketValue.map(decimalText))
                try stepDone(statement)
            }

            for repayment in asset.repayments {
                try withStatement(repaymentSQL) { statement in
                    bind(statement, 1, repayment.id.uuidString)
                    bind(statement, 2, asset.id.uuidString)
                    sqlite3_bind_int(statement, 3, Int32(repayment.monthOffset))
                    bind(statement, 4, decimalText(repayment.amount))
                    try stepDone(statement)
                }
            }

            for record in asset.fundActivities {
                try withStatement(fundRecordSQL) { statement in
                    bind(statement, 1, record.id.uuidString)
                    bind(statement, 2, asset.id.uuidString)
                    bind(statement, 3, record.kind.rawValue)
                    bind(statement, 4, decimalText(record.amount))
                    bind(statement, 5, ISO8601DateFormatter().string(from: record.occurredAt))
                    bind(statement, 6, record.note)
                    try stepDone(statement)
                }
            }
        }
    }

    private func rows<T>(_ sql: String, map: (OpaquePointer?) throws -> T) throws -> [T] {
        var result: [T] = []

        try withStatement(sql) { statement in
            while sqlite3_step(statement) == SQLITE_ROW {
                result.append(try map(statement))
            }
        }

        return result
    }

    private func execute(_ sql: String) throws {
        guard sqlite3_exec(db, sql, nil, nil, nil) == SQLITE_OK else {
            throw SQLiteFailure.statementFailed(message: lastError)
        }
    }

    private func withStatement<T>(_ sql: String, body: (OpaquePointer?) throws -> T) throws -> T {
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(db, sql, -1, &statement, nil) == SQLITE_OK else {
            throw SQLiteFailure.statementFailed(message: lastError)
        }

        defer {
            sqlite3_finalize(statement)
        }

        return try body(statement)
    }

    private func stepDone(_ statement: OpaquePointer?) throws {
        guard sqlite3_step(statement) == SQLITE_DONE else {
            throw SQLiteFailure.statementFailed(message: lastError)
        }
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: String?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_text(statement, index, value, -1, SQLITE_TRANSIENT)
    }

    private func bind(_ statement: OpaquePointer?, _ index: Int32, _ value: Int?) {
        guard let value else {
            sqlite3_bind_null(statement, index)
            return
        }
        sqlite3_bind_int(statement, index, Int32(value))
    }

    private func text(_ statement: OpaquePointer?, _ index: Int32) -> String {
        guard let cString = sqlite3_column_text(statement, index) else { return "" }
        return String(cString: cString)
    }

    private func optionalText(_ statement: OpaquePointer?, _ index: Int32) -> String? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return text(statement, index)
    }

    private func optionalInt(_ statement: OpaquePointer?, _ index: Int32) -> Int? {
        guard sqlite3_column_type(statement, index) != SQLITE_NULL else { return nil }
        return Int(sqlite3_column_int(statement, index))
    }

    private func optionalAccount(id: String?, name: String?, symbolName: String?) -> MoneyAccount? {
        guard let id,
              let accountID = UUID(uuidString: id),
              let name
        else {
            return nil
        }

        return MoneyAccount(
            id: accountID,
            name: name,
            symbolName: symbolName ?? "creditcard.fill",
            balance: 0
        )
    }

    private func decimal(_ statement: OpaquePointer?, _ index: Int32, table: String, column: String) throws -> Decimal {
        let raw = text(statement, index)
        guard let value = Decimal.moneyString(raw) else {
            throw SQLiteFailure.invalidStoredAmount(table: table, column: column, value: raw)
        }
        return value
    }

    private func optionalDecimal(
        _ statement: OpaquePointer?,
        _ index: Int32,
        table: String,
        column: String
    ) throws -> Decimal? {
        guard let raw = optionalText(statement, index) else { return nil }
        guard let value = Decimal.moneyString(raw) else {
            throw SQLiteFailure.invalidStoredAmount(table: table, column: column, value: raw)
        }
        return value
    }

    private func repaymentAdjustments(_ statement: OpaquePointer?, _ index: Int32) throws -> [RepaymentAdjustment] {
        guard let raw = optionalText(statement, index),
              let data = raw.data(using: .utf8)
        else {
            return []
        }

        do {
            return try JSONDecoder().decode([RepaymentAdjustment].self, from: data)
        } catch {
            throw SQLiteFailure.statementFailed(message: "无法读取本地待还调整记录")
        }
    }

    private func repaymentAdjustmentsText(_ adjustments: [RepaymentAdjustment]) throws -> String? {
        guard !adjustments.isEmpty else { return nil }

        do {
            let data = try JSONEncoder().encode(adjustments)
            return String(data: data, encoding: .utf8)
        } catch {
            throw SQLiteFailure.statementFailed(message: "无法保存本地待还调整记录")
        }
    }

    private func color(for presetKey: String) -> Color {
        PreviewData.allCategories.first { $0.presetKey == presetKey }?.color ?? AppColor.primary
    }

    private func emptyRepayments() -> [RepaymentMonth] {
        (0..<24).map {
            RepaymentMonth(id: UUID(), monthOffset: $0, amount: 0)
        }
    }

    private func decimalText(_ value: Decimal) -> String {
        NSDecimalNumber(decimal: value).stringValue
    }

    private var lastError: String {
        guard let message = sqlite3_errmsg(db) else { return "SQLite error" }
        return String(cString: message)
    }

    private static func databaseURL() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let folder = base.appendingPathComponent("Ledgerly", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent("ledgerly.sqlite")
    }
}

enum SQLiteFailure: LocalizedError {
    case openFailed
    case statementFailed(message: String)
    case invalidStoredAmount(table: String, column: String, value: String)

    var errorDescription: String? {
        switch self {
        case .openFailed:
            "无法打开本地 SQLite 数据库"
        case let .statementFailed(message):
            message
        case let .invalidStoredAmount(table, column, value):
            "数据库金额格式错误：\(table).\(column) = \(value)"
        }
    }
}

private let SQLITE_TRANSIENT = unsafeBitCast(-1, to: sqlite3_destructor_type.self)
