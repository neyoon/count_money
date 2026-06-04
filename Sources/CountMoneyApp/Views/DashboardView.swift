import Charts
import SwiftUI

struct DashboardView: View {
    let overview: MonthlyOverview
    let assetOverview: AssetOverview

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    hero
                    metrics
                    weeklyChart
                    categoryChart
                    recentTransactions
                }
                .padding()
            }
            .background(AppColor.background)
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("净资产")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.muted)

                    Text(MoneyFormat.yuan(assetOverview.net, signed: true))
                        .font(.system(size: 38, weight: .semibold, design: .rounded))
                        .foregroundStyle(AppColor.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer(minLength: 0)
            }

            AssetBalanceAxis(
                holdings: assetOverview.holdings,
                fundHoldings: assetOverview.fundHoldings,
                debt: assetOverview.debt
            )

            AssetEquationView(assetOverview: assetOverview)
        }
        .surface()
    }

    private var metrics: some View {
        LazyVGrid(columns: columns, spacing: 12) {
            MetricTile(
                title: "收入",
                value: MoneyFormat.yuan(overview.income),
                symbolName: "arrow.down.left.circle.fill",
                color: AppColor.success
            )

            MetricTile(
                title: "支出",
                value: MoneyFormat.yuan(overview.expense),
                symbolName: "arrow.up.right.circle.fill",
                color: AppColor.danger
            )
        }
    }

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "近 7 天收支",
                value: MoneyFormat.yuan(overview.dailyCashflows.map { $0.income + $0.expense }.reduce(0, +))
            )

            Chart(weeklyChartItems) { item in
                BarMark(
                    x: .value("日期", item.day),
                    y: .value("金额", item.amount.doubleValue)
                )
                .foregroundStyle(by: .value("类型", item.kind))
                .position(by: .value("类型", item.kind))
                .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            }
            .chartForegroundStyleScale([
                "收入": AppColor.success,
                "支出": AppColor.danger
            ])
            .chartYAxis {
                AxisMarks(position: .leading)
            }
            .frame(height: 190)
        }
        .surface()
    }

    private var weeklyChartItems: [WeeklyCashflowBar] {
        overview.dailyCashflows.flatMap { item in
            [
                WeeklyCashflowBar(day: item.day, kind: "收入", amount: item.income),
                WeeklyCashflowBar(day: item.day, kind: "支出", amount: item.expense)
            ]
        }
    }

    private var categoryChart: some View {
        VStack(alignment: .leading, spacing: 14) {
            SectionHeader(title: "支出分类占比", value: "本月")

            HStack(spacing: 16) {
                Chart(overview.categorySpending) { item in
                    SectorMark(
                        angle: .value("金额", item.amount.doubleValue),
                        innerRadius: .ratio(0.58),
                        angularInset: 2
                    )
                    .foregroundStyle(item.category.color)
                    .cornerRadius(4)
                }
                .frame(width: 150, height: 150)

                VStack(alignment: .leading, spacing: 10) {
                    ForEach(overview.categorySpending) { item in
                        CategoryLegendRow(item: item)
                    }
                }
            }
        }
        .surface()
    }

    private var recentTransactions: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(title: "最近账目", value: "查看全部")

            VStack(spacing: 0) {
                ForEach(overview.recentTransactions) { transaction in
                    TransactionRow(transaction: transaction)

                    if transaction.id != overview.recentTransactions.last?.id {
                        Divider()
                            .padding(.leading, 52)
                    }
                }
            }
        }
        .surface()
    }
}

struct WeeklyCashflowBar: Identifiable {
    let id = UUID()
    var day: String
    var kind: String
    var amount: Decimal
}

struct AssetBalanceAxis: View {
    var holdings: Decimal
    var fundHoldings: Decimal
    var debt: Decimal

    private var scaleBase: Double {
        max((holdings + fundHoldings).doubleValue, debt.doubleValue, 1)
    }

    var body: some View {
        VStack(spacing: 10) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("待还")
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)

                    Text(MoneyFormat.yuan(debt))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.danger)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("资产")
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)

                    Text(MoneyFormat.yuan(holdings + fundHoldings))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.success)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }

            GeometryReader { proxy in
                let centerWidth: CGFloat = 2
                let halfWidth = max((proxy.size.width - centerWidth) / 2, 0)
                let leftWidth = halfWidth * min(max(debt.doubleValue / scaleBase, 0), 1)
                let positiveAssets = max((holdings + fundHoldings).doubleValue, 0)
                let rightWidth = halfWidth * min(max(positiveAssets / scaleBase, 0), 1)
                let fundRatio = positiveAssets == 0 ? 0 : max(fundHoldings.doubleValue, 0) / positiveAssets
                let fundWidth = rightWidth * min(max(fundRatio, 0), 1)
                let holdingWidth = max(rightWidth - fundWidth, 0)

                ZStack {
                    Capsule()
                        .fill(AppColor.line.opacity(0.28))

                    HStack(spacing: 0) {
                        ZStack(alignment: .trailing) {
                            Capsule()
                                .fill(AppColor.danger)
                                .frame(width: max(leftWidth, debt > 0 ? 4 : 0))
                        }
                        .frame(width: halfWidth, alignment: .trailing)

                        Rectangle()
                            .fill(AppColor.ink.opacity(0.45))
                            .frame(width: centerWidth, height: 18)

                        ZStack(alignment: .leading) {
                            HStack(spacing: 0) {
                                Capsule()
                                    .fill(AppColor.success)
                                    .frame(width: max(holdingWidth, holdings > 0 ? 4 : 0))

                                Capsule()
                                    .fill(AppColor.muted.opacity(0.65))
                                    .frame(width: max(fundWidth, fundHoldings > 0 ? 4 : 0))
                            }
                        }
                        .frame(width: halfWidth, alignment: .leading)
                    }
                }
            }
            .frame(height: 12)
        }
        .padding(12)
        .background(AppColor.background.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColor.line.opacity(0.8), lineWidth: 1)
        )
    }
}

struct AssetEquationView: View {
    var assetOverview: AssetOverview

    var body: some View {
        VStack(alignment: .trailing, spacing: 8) {
            EquationRow(
                symbol: "+",
                title: "可用资产",
                value: assetOverview.holdings,
                color: AppColor.success
            )
            EquationRow(
                symbol: "+",
                title: "基金资产",
                value: assetOverview.fundHoldings,
                color: AppColor.muted
            )
            EquationRow(
                symbol: "-",
                title: "待还",
                value: assetOverview.debt,
                color: AppColor.danger
            )

            Divider()

            EquationRow(
                symbol: "=",
                title: "净资产",
                value: assetOverview.net,
                color: AppColor.ink
            )
            .font(.headline)
        }
    }
}

struct EquationRow: View {
    var symbol: String
    var title: String
    var value: Decimal
    var color: Color

    var body: some View {
        HStack(spacing: 10) {
            Text(symbol)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .frame(width: 18, alignment: .trailing)

            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppColor.muted)

            Spacer()

            Text(MoneyFormat.yuan(value, signed: value > 0 && symbol == "="))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
                .monospacedDigit()
        }
    }
}

struct MetricTile: View {
    var title: String
    var value: String
    var symbolName: String
    var color: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: symbolName)
                .font(.title3)
                .foregroundStyle(color)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.caption)
                    .foregroundStyle(AppColor.muted)

                Text(value)
                    .font(.headline)
                    .foregroundStyle(AppColor.ink)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }

            Spacer(minLength: 0)
        }
        .surface()
    }
}

struct SectionHeader: View {
    var title: String
    var value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColor.ink)

            Spacer()

            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColor.muted)
        }
    }
}

struct CategoryLegendRow: View {
    var item: CategorySpending

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(item.category.color)
                .frame(width: 10, height: 10)

            Text(item.category.name)
                .font(.subheadline)
                .foregroundStyle(AppColor.ink)

            Spacer()

            Text(MoneyFormat.yuan(item.amount))
                .font(.subheadline.weight(.medium))
                .foregroundStyle(AppColor.muted)
        }
    }
}

struct TransactionRow: View {
    var transaction: MoneyTransaction

    private var amountText: String {
        switch transaction.kind {
        case .expense:
            "-\(MoneyFormat.yuan(transaction.amount))"
        case .income:
            MoneyFormat.yuan(transaction.amount, signed: true)
        }
    }

    private var amountColor: Color {
        switch transaction.kind {
        case .expense:
            AppColor.danger
        case .income:
            AppColor.success
        }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: transaction.category.symbolName)
                .font(.subheadline)
                .foregroundStyle(transaction.category.color)
                .frame(width: 38, height: 38)
                .background(transaction.category.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(transaction.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(AppColor.ink)

                Text(transaction.account.name)
                    .font(.caption)
                    .foregroundStyle(AppColor.muted)
            }

            Spacer()

            Text(amountText)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(amountColor)
        }
        .padding(.vertical, 10)
    }
}
