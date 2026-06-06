import Charts
import SwiftUI

struct DashboardView: View {
    var store: AppStore
    var isActive = true

    @State private var historyDate: Date?
    @State private var draftHistoryDate = Date()
    @State private var historySelectionPurpose: HistorySelectionPurpose = .view
    @State private var isShowingHistoryActions = false
    @State private var isSelectingHistoryDate = false
    @State private var comparisonDate: Date?
    @State private var isShowingComparison = false

    private var overview: MonthlyOverview {
        activeHistorySnapshot?.overview ?? store.overview
    }

    private var assetOverview: AssetOverview {
        activeHistorySnapshot?.assetOverview ?? store.assetOverview
    }

    private var activeHistorySnapshot: HistorySnapshot? {
        historyDate.map { store.historySnapshot(on: $0) }
    }

    private var columns: [GridItem] {
        [
            GridItem(.flexible(), spacing: 12),
            GridItem(.flexible(), spacing: 12)
        ]
    }

    var body: some View {
        NavigationStack {
            GeometryReader { proxy in
                ScrollView {
                    dashboardContent(width: proxy.size.width)
                        .padding(.vertical, pageVerticalPadding)
                        .padding(.horizontal, pageHorizontalPadding)
                        .frame(maxWidth: pageMaxWidth, alignment: .topLeading)
                        .frame(maxWidth: .infinity, alignment: .top)
                }
                .tabBarScrollableContentInset()
                .historyPull(enabled: store.historyMode) {
                    withAnimation(.snappy) {
                        isShowingHistoryActions = true
                    }
                }
                .background(AppColor.background)
            }
            .navigationTitle("总览")
            .sheet(isPresented: $isSelectingHistoryDate) {
                HistoryDatePickerSheet(title: historySelectionPurpose.title, date: $draftHistoryDate) {
                    applySelectedHistoryDate()
                }
            }
            .sheet(isPresented: $isShowingComparison) {
                HistoryComparisonSheet(comparison: store.historyComparison(from: comparisonDate ?? historyDate ?? Date()))
            }
            .onChange(of: isActive) { _, isActive in
                if !isActive {
                    historyDate = nil
                    isShowingHistoryActions = false
                    isSelectingHistoryDate = false
                    isShowingComparison = false
                }
            }
        }
    }

    @ViewBuilder
    private func dashboardContent(width: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if let snapshot = activeHistorySnapshot {
                HistoryDateBanner(date: snapshot.date) {
                    historyDate = nil
                }
            }

            if isShowingHistoryActions {
                HistoryActionButtons(
                    onSelectDate: { beginHistoryDateSelection(.view) },
                    onCompare: { beginHistoryDateSelection(.compare) }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if usesDesktopLayout(width: width) {
                HStack(alignment: .top, spacing: 16) {
                    hero
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    metrics
                        .frame(width: 320, alignment: .top)
                }

                HStack(alignment: .top, spacing: 16) {
                    weeklyChart
                        .frame(maxWidth: .infinity, alignment: .topLeading)

                    categoryChart
                        .frame(width: 360, alignment: .top)
                }
            } else {
                hero
                metrics
                weeklyChart
                categoryChart
            }
        }
    }

    private var pageMaxWidth: CGFloat {
        #if os(macOS)
        1120
        #else
        .infinity
        #endif
    }

    private var pageHorizontalPadding: CGFloat {
        #if os(macOS)
        24
        #else
        16
        #endif
    }

    private var pageVerticalPadding: CGFloat {
        #if os(macOS)
        20
        #else
        16
        #endif
    }

    private func usesDesktopLayout(width: CGFloat) -> Bool {
        #if os(macOS)
        width >= 760
        #else
        false
        #endif
    }

    private func beginHistoryDateSelection(_ purpose: HistorySelectionPurpose) {
        historySelectionPurpose = purpose
        draftHistoryDate = historyDate ?? Date()
        isShowingHistoryActions = false
        isSelectingHistoryDate = true
    }

    private func applySelectedHistoryDate() {
        switch historySelectionPurpose {
        case .view:
            historyDate = draftHistoryDate
        case .compare:
            comparisonDate = draftHistoryDate
            isShowingComparison = true
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
        VStack(spacing: 12) {
            LazyVGrid(columns: columns, spacing: 12) {
                MetricTile(
                    title: "本月收入",
                    value: MoneyFormat.yuan(overview.income),
                    symbolName: "arrow.down.left.circle.fill",
                    color: AppColor.success
                )

                MetricTile(
                    title: "本月支出",
                    value: MoneyFormat.yuan(overview.expense),
                    symbolName: "arrow.up.right.circle.fill",
                    color: AppColor.danger
                )
            }

            RepaymentMetricTile(
                value: MoneyFormat.yuan(assetOverview.currentMonthRepayment)
            )
        }
    }

    private var weeklyChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "近 7 天收支",
                value: MoneyFormat.yuan(weeklyNetCashflow, signed: true)
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

    private var weeklyNetCashflow: Decimal {
        overview.dailyCashflows
            .map { $0.income - $0.expense }
            .reduce(0, +)
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

}

struct AssetBalanceRow: View {
    var asset: AssetItem
    var scaleBase: Double

    private var value: Decimal {
        if asset.kind == .fund {
            return asset.fundCurrentValue
        }
        return asset.balance
    }

    private var valueText: String {
        MoneyFormat.yuan(value)
    }

    private var valueColor: Color {
        if value == 0 {
            return AppColor.muted
        }
        return barColor
    }

    private var barColor: Color {
        if asset.kind == .fund {
            return AppColor.success
        }
        if asset.isDebtLike || value < 0 {
            return AppColor.danger
        }
        return AppColor.success
    }

    private var barRatio: Double {
        min(abs(value.doubleValue) / scaleBase, 1)
    }

    var body: some View {
        VStack(spacing: 7) {
            HStack(spacing: 10) {
                Image(systemName: asset.kind.symbolName)
                    .font(.subheadline)
                    .foregroundStyle(barColor)
                    .frame(width: 32, height: 32)
                    .background(barColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(asset.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(AppColor.ink)

                    Text(asset.isDebtLike ? "当前欠款" : asset.kind.title)
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)
                }

                Spacer()

                Text(valueText)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(valueColor)
                    .monospacedDigit()
            }

            if asset.kind == .fund {
                VStack(spacing: 6) {
                    AssetBalanceBar(
                        title: "实时金额",
                        value: asset.fundCurrentValue,
                        scaleBase: scaleBase,
                        color: AppColor.success
                    )
                    AssetBalanceBar(
                        title: "投入金额",
                        value: asset.fundCost ?? 0,
                        scaleBase: scaleBase,
                        color: AppColor.muted
                    )
                }
                .padding(.leading, 42)

                HStack(spacing: 12) {
                    Text("总盈亏 \(MoneyFormat.yuan(asset.fundProfit, signed: asset.fundProfit > 0))")
                        .foregroundStyle(fundProfitColor)

                    Spacer()
                }
                .font(.caption)
                .padding(.leading, 42)
            } else {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(AppColor.line.opacity(0.24))

                        Capsule()
                            .fill(barColor)
                            .frame(width: value == 0 ? 0 : max(proxy.size.width * barRatio, 4))
                    }
                }
                .frame(height: 7)
                .padding(.leading, 42)
            }
        }
        .padding(.vertical, 9)
    }

    private var fundProfitColor: Color {
        if asset.fundProfit < 0 {
            return AppColor.danger
        }
        if asset.fundProfit > 0 {
            return AppColor.success
        }
        return AppColor.muted
    }
}

struct AssetBalanceBar: View {
    var title: String
    var value: Decimal
    var scaleBase: Double
    var color: Color

    private var ratio: Double {
        min(abs(value.doubleValue) / max(scaleBase, 1), 1)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(title)
                    .foregroundStyle(AppColor.muted)

                Spacer()

                Text(MoneyFormat.yuan(value))
                    .foregroundStyle(color)
                    .monospacedDigit()
            }
            .font(.caption)

            GeometryReader { proxy in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColor.line.opacity(0.24))

                    Capsule()
                        .fill(color)
                        .frame(width: value == 0 ? 0 : max(proxy.size.width * ratio, 4))
                }
            }
            .frame(height: 7)
        }
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
                let debtBarWidth = max(leftWidth, debt > 0 ? 4 : 0)
                let holdingBarWidth = max(holdingWidth, holdings > 0 ? 4 : 0)
                let fundBarWidth = max(fundWidth, fundHoldings > 0 ? 4 : 0)

                ZStack {
                    Capsule()
                        .fill(AppColor.line.opacity(0.28))

                    HStack(spacing: 0) {
                        ZStack(alignment: .trailing) {
                            if debtBarWidth > 0 {
                                leftRoundedAxisSegment(color: AppColor.danger, width: debtBarWidth)
                            }
                        }
                        .frame(width: halfWidth, alignment: .trailing)

                        Rectangle()
                            .fill(AppColor.ink.opacity(0.45))
                            .frame(width: centerWidth, height: 18)

                        ZStack(alignment: .leading) {
                            HStack(spacing: 0) {
                                if holdingBarWidth > 0 {
                                    if fundBarWidth > 0 {
                                        flatAxisSegment(color: AppColor.success, width: holdingBarWidth)
                                    } else {
                                        rightRoundedAxisSegment(color: AppColor.success, width: holdingBarWidth)
                                    }
                                }

                                if fundBarWidth > 0 {
                                    rightRoundedAxisSegment(color: AppColor.muted.opacity(0.65), width: fundBarWidth)
                                }
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

    private func leftRoundedAxisSegment(color: Color, width: CGFloat) -> some View {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 6,
                bottomLeading: 6,
                bottomTrailing: 0,
                topTrailing: 0
            ),
            style: .continuous
        )
        .fill(color)
        .frame(width: width, height: 12)
    }

    private func rightRoundedAxisSegment(color: Color, width: CGFloat) -> some View {
        UnevenRoundedRectangle(
            cornerRadii: RectangleCornerRadii(
                topLeading: 0,
                bottomLeading: 0,
                bottomTrailing: 6,
                topTrailing: 6
            ),
            style: .continuous
        )
        .fill(color)
        .frame(width: width, height: 12)
    }

    private func flatAxisSegment(color: Color, width: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .frame(width: width, height: 12)
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

struct RepaymentMetricTile: View {
    var value: String

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "calendar.badge.clock")
                .font(.title3)
                .foregroundStyle(AppColor.warning)

            VStack(alignment: .leading, spacing: 4) {
                Text("本月待还")
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
        case .fundProfit:
            MoneyFormat.yuan(transaction.amount, signed: transaction.amount > 0)
        }
    }

    private var amountColor: Color {
        switch transaction.kind {
        case .expense:
            AppColor.danger
        case .income:
            AppColor.success
        case .fundProfit:
            transaction.amount < 0 ? AppColor.danger : AppColor.success
        }
    }

    private var accountText: String {
        if (transaction.category.isRepayment || transaction.category.isFundPurchase),
           let paymentAccount = transaction.paymentAccount {
            return "\(paymentAccount.name) -> \(transaction.account.name)"
        }

        if transaction.category.isFundRedemption,
           let fundAccount = transaction.paymentAccount {
            return "\(fundAccount.name) -> \(transaction.account.name)"
        }

        return transaction.account.name
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

                Text(accountText)
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
