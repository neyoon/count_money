import SwiftUI
import UniformTypeIdentifiers

struct EntryView: View {
    var store: AppStore
    var isActive = true

    @State private var selectedKind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var selectedCategory: MoneyCategory = PreviewData.expenseCategories[0]
    @State private var selectedAccountID: UUID?
    @State private var selectedPaymentAccountID: UUID?
    @State private var saveError: String?
    @State private var isApplyingDraft = false
    @State private var useInstallment = false
    @State private var installmentMonths = 3
    @State private var isFundLoss = false
    @State private var appliedDraftID: UUID?
    @State private var entryDate = Date()
    @State private var isSelectingEntryDate = false

    private var visibleCategories: [MoneyCategory] {
        store.categories(for: selectedKind)
    }

    private var categoryColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 78), spacing: 10)
        ]
    }

    private var parsedAmount: Decimal? {
        Decimal.moneyString(amountText)
    }

    private var selectedAccount: MoneyAccount? {
        if let selectedAccountID,
           let account = entryAccounts.first(where: { $0.id == selectedAccountID }) {
            return account
        }

        return entryAccounts.first
    }

    private var selectedAsset: AssetItem? {
        selectedAccount.flatMap(store.asset(for:))
    }

    private var selectedPaymentAccount: MoneyAccount? {
        if let selectedPaymentAccountID,
           let account = repaymentPaymentAccounts.first(where: { $0.id == selectedPaymentAccountID }) {
            return account
        }

        return repaymentPaymentAccounts.first
    }

    private var fundAccounts: [MoneyAccount] {
        store.ledgerAssets
            .filter { $0.kind == .fund }
            .map { asset in
                MoneyAccount(
                    id: asset.id,
                    name: asset.name,
                    symbolName: asset.kind.symbolName,
                    balance: asset.fundCurrentValue
                )
            }
    }

    private var entryAccounts: [MoneyAccount] {
        switch selectedKind {
        case .fundProfit:
            fundAccounts
        case .expense where selectedCategory.isRepayment:
            store.repaymentAccounts
        case .expense, .income:
            store.paymentAccounts
        }
    }

    private var canUseInstallment: Bool {
        selectedKind == .expense
            && !selectedCategory.isRepayment
            && (selectedAsset?.kind.supportsInstallment ?? false)
    }

    private var isRepaymentEntry: Bool {
        selectedKind == .expense && selectedCategory.isRepayment
    }

    private var repaymentPaymentAccounts: [MoneyAccount] {
        store.repaymentPaymentAccounts
            .filter { $0.id != selectedAccount?.id }
    }

    private var canSaveEntry: Bool {
        guard let parsedAmount, selectedAccount != nil else { return false }
        if isRepaymentEntry, selectedPaymentAccount == nil {
            return false
        }
        if selectedKind == .fundProfit {
            return parsedAmount > 0
        }
        return parsedAmount > 0
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    Picker("类型", selection: $selectedKind) {
                        ForEach(TransactionKind.allCases) { kind in
                            Text(kind.title).tag(kind)
                        }
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: selectedKind) { _, newValue in
                        if let first = store.categories(for: newValue).first {
                            selectedCategory = first
                        }
                        ensureSelectedAccountsAreValid()
                        if newValue != .expense || selectedCategory.isRepayment {
                            useInstallment = false
                        }
                        if newValue != .fundProfit {
                            isFundLoss = false
                        }
                    }

                    amountSection
                    fundProfitDirectionSection
                    draftSection
                    accountSection
                    repaymentPaymentAccountSection
                    installmentSection
                    categorySection
                    saveButton
                    entryDateButton

                    Spacer()
                }
            }
            .tabBarScrollableContentInset()
            .padding()
            .background(AppColor.background)
            .onAppear {
                resetEntryDateToToday()
                ensureSelectedAccountsAreValid()
                applyQuickEntryDraftIfNeeded(store.quickEntryDraft)
            }
            .onChange(of: isActive) { _, isActive in
                if !isActive {
                    resetEntryDateToToday()
                }
            }
            .onChange(of: store.quickEntryDraft) { _, draft in
                applyQuickEntryDraftIfNeeded(draft)
            }
            .sheet(isPresented: $isSelectingEntryDate) {
                EntryDatePickerSheet(selectedDate: $entryDate)
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("金额")
                .font(.subheadline)
                .foregroundStyle(AppColor.muted)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("¥")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(AppColor.muted)

                TextField("0", text: $amountText)
                    .font(.system(size: 44, weight: .semibold, design: .rounded))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
                    .onChange(of: amountText) {
                        if !isApplyingDraft {
                            store.startManualEntry()
                        }
                    }
            }
        }
        .surface()
    }

    @ViewBuilder
    private var fundProfitDirectionSection: some View {
        if selectedKind == .fundProfit {
            VStack(alignment: .leading, spacing: 12) {
                Text("方向")
                    .font(.headline)
                    .foregroundStyle(AppColor.ink)

                Picker("方向", selection: $isFundLoss) {
                    Text("+").tag(false)
                    Text("-").tag(true)
                }
                .pickerStyle(.segmented)
            }
            .surface()
        }
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(accountTitle)
                .font(.headline)
                .foregroundStyle(AppColor.ink)

            if entryAccounts.isEmpty {
                Text(emptyAccountText)
                    .font(.subheadline)
                    .foregroundStyle(AppColor.muted)
            } else {
                Picker("账户", selection: Binding(
                    get: { selectedAccount?.id ?? entryAccounts[0].id },
                    set: { newValue in
                        selectedAccountID = newValue
                        ensureSelectedPaymentAccountIsValid()
                        let asset = store.ledgerAssets.first { $0.id == newValue }
                        if selectedCategory.isRepayment || !(asset?.kind.supportsInstallment ?? false) {
                            useInstallment = false
                        }
                    }
                )) {
                    ForEach(entryAccounts) { account in
                        Label(account.name, systemImage: account.symbolName)
                            .tag(account.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .surface()
    }

    @ViewBuilder
    private var repaymentPaymentAccountSection: some View {
        if isRepaymentEntry {
            VStack(alignment: .leading, spacing: 12) {
                Text("支付账户")
                    .font(.headline)
                    .foregroundStyle(AppColor.ink)

                if repaymentPaymentAccounts.isEmpty {
                    Text("请先在资产页添加可支付的余额账户。")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.muted)
                } else {
                    Picker("支付账户", selection: Binding(
                        get: { selectedPaymentAccount?.id ?? repaymentPaymentAccounts[0].id },
                        set: { selectedPaymentAccountID = $0 }
                    )) {
                        ForEach(repaymentPaymentAccounts) { account in
                            Label(account.name, systemImage: account.symbolName)
                                .tag(account.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .surface()
        }
    }

    private var accountTitle: String {
        switch selectedKind {
        case .expense where selectedCategory.isRepayment:
            return "还款账户"
        case .expense:
            return "支付账户"
        case .income:
            return "收款账户"
        case .fundProfit:
            return "基金"
        }
    }

    private var emptyAccountText: String {
        switch selectedKind {
        case .fundProfit:
            return "请先在资产页添加基金。"
        case .expense where selectedCategory.isRepayment:
            return "请先在资产页添加信用卡、花呗或其他待还账户。"
        case .expense, .income:
            return "请先在资产页添加银行卡、支付宝或微信账户。"
        }
    }

    @ViewBuilder
    private var installmentSection: some View {
        if canUseInstallment {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $useInstallment) {
                    Label("分期付款", systemImage: "calendar.badge.clock")
                        .font(.headline)
                        .foregroundStyle(AppColor.ink)
                }

                if useInstallment {
                    Picker("分期月数", selection: $installmentMonths) {
                        ForEach(1...24, id: \.self) { month in
                            Text("\(month) 个月").tag(month)
                        }
                    }
                    .pickerStyle(.menu)

                    if let parsedAmount, parsedAmount > 0 {
                        Text("这里的金额按每月待还金额记录，不是分期总额。保存后会从下月开始，连续 \(installmentMonths) 个月各增加 \(MoneyFormat.yuan(parsedAmount)) 待还。")
                            .font(.caption)
                            .foregroundStyle(AppColor.muted)
                    } else {
                        Text("开启分期后，金额填每月待还金额，不填分期总额，系统不会自动平均分摊。")
                            .font(.caption)
                            .foregroundStyle(AppColor.muted)
                    }
                }
            }
            .surface()
        }
    }

    @ViewBuilder
    private var draftSection: some View {
        if (selectedKind == .expense || selectedKind == .income), let draft = store.quickEntryDraft {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Label("截图识别结果", systemImage: "viewfinder")
                        .font(.headline)
                        .foregroundStyle(AppColor.ink)

                    Spacer()

                    Text("\(Int(draft.confidence * 100))%")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(AppColor.muted)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(draft.candidateAmounts, id: \.self) { amount in
                            Button(MoneyFormat.yuan(amount)) {
                                applyAmount(amount)
                            }
                            .buttonStyle(.bordered)
                            .tint(AppColor.primary)
                        }
                    }
                }

                if !draft.recognizedTextPreview.isEmpty {
                    Text(draft.recognizedTextPreview)
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)
                        .lineLimit(3)
                }
            }
            .surface()
        }
    }

    @ViewBuilder
    private var categorySection: some View {
        if selectedKind == .expense || selectedKind == .income {
            VStack(alignment: .leading, spacing: 12) {
                Text(selectedKind == .expense ? "支出分类" : "收入分类")
                    .font(.headline)
                    .foregroundStyle(AppColor.ink)

                LazyVGrid(columns: categoryColumns, spacing: 10) {
                    ForEach(visibleCategories) { category in
                        CategoryButton(
                            category: category,
                            isSelected: category.id == selectedCategory.id
                        ) {
                            selectCategory(category)
                        }
                    }
                }
            }
            .surface()
        }
    }

    private var entryDateButton: some View {
        Button {
            isSelectingEntryDate = true
        } label: {
            HStack {
                Text("记账日期")
                    .font(.headline)
                Spacer()
                if let entryDateText {
                    Text(entryDateText)
                        .font(.subheadline.weight(.semibold))
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
        }
        .buttonStyle(.bordered)
        .tint(AppColor.primary)
    }

    private var entryDateText: String? {
        if Calendar.current.isDateInToday(entryDate) {
            return nil
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter.string(from: entryDate)
    }

    private var saveButton: some View {
        Button {
            guard let parsedAmount,
                  let selectedAccount
            else {
                return
            }

            do {
                if selectedKind == .fundProfit {
                    let signedAmount = isFundLoss ? -parsedAmount : parsedAmount
                    try store.addFundProfit(
                        assetID: selectedAccount.id,
                        amount: signedAmount,
                        note: "",
                        occurredAt: EntryDateHelper.occurredAt(on: entryDate)
                    )
                } else {
                    try store.addTransaction(
                        kind: selectedKind,
                        amount: parsedAmount,
                        category: selectedCategory,
                        account: selectedAccount,
                        title: selectedCategory.name,
                        paymentAccount: isRepaymentEntry ? selectedPaymentAccount : nil,
                        installmentMonths: useInstallment && canUseInstallment ? installmentMonths : nil,
                        occurredAt: EntryDateHelper.occurredAt(on: entryDate)
                    )
                }
                amountText = ""
                useInstallment = false
            } catch {
                saveError = error.localizedDescription
            }
        } label: {
            Label("保存", systemImage: "checkmark")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColor.success)
        .disabled(!canSaveEntry)
    }

    private func selectCategory(_ category: MoneyCategory) {
        selectedCategory = category
        ensureSelectedAccountsAreValid()
        if category.isRepayment {
            useInstallment = false
        }
    }

    private func applyAmount(_ amount: Decimal) {
        isApplyingDraft = true
        amountText = NSDecimalNumber(decimal: amount).stringValue
        isApplyingDraft = false
    }

    private func applyQuickEntryDraftIfNeeded(_ draft: QuickEntryDraft?) {
        guard let draft, appliedDraftID != draft.id else { return }
        appliedDraftID = draft.id
        applyAmount(draft.candidateAmount)
        selectedKind = draft.suggestedKind

        if let first = store.categories(for: draft.suggestedKind).first {
            selectedCategory = first
        }
        ensureSelectedAccountsAreValid()
    }

    private func ensureSelectedAccountsAreValid() {
        ensureSelectedEntryAccountIsValid()
        ensureSelectedPaymentAccountIsValid()
    }

    private func ensureSelectedEntryAccountIsValid() {
        if let selectedAccountID,
           entryAccounts.contains(where: { $0.id == selectedAccountID }) {
            return
        }

        selectedAccountID = entryAccounts.first?.id
    }

    private func ensureSelectedPaymentAccountIsValid() {
        guard isRepaymentEntry else { return }
        if let selectedPaymentAccountID,
           repaymentPaymentAccounts.contains(where: { $0.id == selectedPaymentAccountID }) {
            return
        }

        selectedPaymentAccountID = repaymentPaymentAccounts.first?.id
    }

    private func resetEntryDateToToday() {
        entryDate = Date()
    }
}

private struct EntryDatePickerSheet: View {
    @Binding var selectedDate: Date
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(
                "记账日期",
                selection: $selectedDate,
                in: EntryDateHelper.allowedRange,
                displayedComponents: .date
            )
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle("记账日期")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.large])
    }
}

private enum EntryDateHelper {
    static var allowedRange: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 1998, month: 1, day: 1)) ?? Date.distantPast
        let end = calendar.date(from: DateComponents(year: 2100, month: 12, day: 31)) ?? Date.distantFuture
        return start...end
    }

    static func occurredAt(on date: Date, keepingTimeFrom time: Date = Date()) -> Date {
        let calendar = Calendar.current
        let dateComponents = calendar.dateComponents([.year, .month, .day], from: date)
        let timeComponents = calendar.dateComponents([.hour, .minute, .second], from: time)
        return calendar.date(from: DateComponents(
            year: dateComponents.year,
            month: dateComponents.month,
            day: dateComponents.day,
            hour: timeComponents.hour,
            minute: timeComponents.minute,
            second: timeComponents.second
        )) ?? date
    }
}

struct CategoryButton: View {
    var category: MoneyCategory
    var isSelected: Bool
    var action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 7) {
                Image(systemName: category.symbolName)
                    .font(.headline)
                    .frame(width: 34, height: 34)
                    .background(category.color.opacity(isSelected ? 0.20 : 0.11))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Text(category.name)
                    .font(.caption.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(isSelected ? category.color : AppColor.ink)
            .padding(.vertical, 10)
            .background(isSelected ? category.color.opacity(0.08) : AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(isSelected ? category.color : AppColor.line, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}

struct TransactionsView: View {
    var store: AppStore
    var isActive = true
    @State private var message: String?
    @State private var listResetID = UUID()
    @State private var selectedYear = Calendar.current.component(.year, from: Date())
    @State private var selectedMonth = Calendar.current.component(.month, from: Date())

    private var sortedTransactions: [MoneyTransaction] {
        store.transactions.sorted { $0.occurredAt > $1.occurredAt }
    }

    private var recentTransactions: [MoneyTransaction] {
        store.overview.recentTransactions
    }

    private var availableYears: [Int] {
        Array(1998...2100)
    }

    private var availableMonths: [Int] {
        Array(1...12)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    MonthTransactionCalendarView(
                        store: store,
                        transactions: sortedTransactions,
                        selectedYear: $selectedYear,
                        selectedMonth: $selectedMonth,
                        availableYears: availableYears,
                        availableMonths: availableMonths
                    )

                    RecentTransactionsSection(
                        store: store,
                        transactions: recentTransactions,
                        message: $message
                    )
                }
                .padding([.horizontal, .top])
            }
            .tabBarScrollableContentInset()
            .background(AppColor.background)
            .id(listResetID)
            .alert("删除失败", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
            .onChange(of: isActive) { _, isActive in
                if !isActive {
                    listResetID = UUID()
                } else {
                    resetSelectedDateToCurrentMonth()
                }
            }
            .onAppear(perform: resetSelectedDateToCurrentMonth)
        }
    }

    private func resetSelectedDateToCurrentMonth() {
        let calendar = Calendar.current
        selectedYear = calendar.component(.year, from: Date())
        selectedMonth = calendar.component(.month, from: Date())
    }

}

struct MonthTransactionCalendarView: View {
    var store: AppStore
    var transactions: [MoneyTransaction]
    @Binding var selectedYear: Int
    @Binding var selectedMonth: Int
    var availableYears: [Int]
    var availableMonths: [Int]
    @State private var isSelectingMonth = false

    private let dayColumns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 7)

    private var calendar: Calendar {
        Calendar.current
    }

    private var monthDate: Date {
        calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: 1)) ?? Date()
    }

    private var transactionsByDay: [Date: [MoneyTransaction]] {
        Dictionary(grouping: transactions) {
            calendar.startOfDay(for: $0.occurredAt)
        }
    }

    private var days: [TransactionCalendarDay] {
        let leadingBlanks = leadingBlankCount
        let blankDays = (0..<leadingBlanks).map {
            TransactionCalendarDay(id: "blank-\($0)", day: nil, date: nil, transactions: [])
        }

        let monthDays = (1...daysInMonth).map { day in
            let date = calendar.startOfDay(
                for: calendar.date(from: DateComponents(year: selectedYear, month: selectedMonth, day: day)) ?? monthDate
            )
            return TransactionCalendarDay(
                id: "\(selectedYear)-\(selectedMonth)-\(day)",
                day: day,
                date: date,
                transactions: transactionsByDay[date] ?? []
            )
        }

        return blankDays + monthDays
    }

    private var leadingBlankCount: Int {
        let weekday = calendar.component(.weekday, from: monthDate)
        return (weekday - calendar.firstWeekday + 7) % 7
    }

    private var daysInMonth: Int {
        calendar.range(of: .day, in: .month, for: monthDate)?.count ?? 0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Spacer()

                Button {
                    isSelectingMonth = true
                } label: {
                    HStack(spacing: 6) {
                        Text(verbatim: "\(selectedYear) 年 \(selectedMonth) 月")
                            .font(.headline)
                        Image(systemName: "chevron.down")
                            .font(.caption.weight(.semibold))
                    }
                    .foregroundStyle(AppColor.ink)
                }
                .buttonStyle(.plain)

                Spacer()
            }

            LazyVGrid(columns: dayColumns, spacing: 8) {
                ForEach(Self.weekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(AppColor.muted)
                        .frame(maxWidth: .infinity)
                }

                ForEach(days) { day in
                    CalendarDayCell(store: store, day: day)
                }
            }
        }
        .surface()
        .sheet(isPresented: $isSelectingMonth) {
            MonthPickerSheet(
                selectedYear: $selectedYear,
                selectedMonth: $selectedMonth,
                availableYears: availableYears,
                availableMonths: availableMonths
            )
        }
    }

    private static var weekdaySymbols: [String] {
        let formatter = DateFormatter()
        var symbols = formatter.shortWeekdaySymbols ?? ["日", "一", "二", "三", "四", "五", "六"]
        let firstWeekday = Calendar.current.firstWeekday - 1
        if firstWeekday > 0 {
            symbols = Array(symbols[firstWeekday...]) + Array(symbols[..<firstWeekday])
        }
        return symbols
    }
}

struct MonthPickerSheet: View {
    @Binding var selectedYear: Int
    @Binding var selectedMonth: Int
    var availableYears: [Int]
    var availableMonths: [Int]
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            HStack(spacing: 0) {
                yearPicker
                monthPicker
            }
            .padding()
            .navigationTitle("选择月份")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.height(320)])
    }

    @ViewBuilder
    private var yearPicker: some View {
        #if os(iOS)
        Picker("年份", selection: $selectedYear) {
            ForEach(availableYears, id: \.self) { year in
                Text(verbatim: "\(year) 年").tag(year)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
        #else
        Picker("年份", selection: $selectedYear) {
            ForEach(availableYears, id: \.self) { year in
                Text(verbatim: "\(year) 年").tag(year)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
        #endif
    }

    @ViewBuilder
    private var monthPicker: some View {
        #if os(iOS)
        Picker("月份", selection: $selectedMonth) {
            ForEach(availableMonths, id: \.self) { month in
                Text(verbatim: "\(month) 月").tag(month)
            }
        }
        .pickerStyle(.wheel)
        .frame(maxWidth: .infinity)
        .clipped()
        #else
        Picker("月份", selection: $selectedMonth) {
            ForEach(availableMonths, id: \.self) { month in
                Text(verbatim: "\(month) 月").tag(month)
            }
        }
        .pickerStyle(.menu)
        .frame(maxWidth: .infinity)
        #endif
    }
}

struct TransactionCalendarDay: Identifiable {
    var id: String
    var day: Int?
    var date: Date?
    var transactions: [MoneyTransaction]

    var hasTransactions: Bool {
        !transactions.isEmpty
    }
}

struct CalendarDayCell: View {
    var store: AppStore
    var day: TransactionCalendarDay

    var body: some View {
        Group {
            if let date = day.date, day.hasTransactions {
                NavigationLink {
                    TransactionDateDetailView(store: store, date: date)
                } label: {
                    cellContent
                }
                .buttonStyle(.plain)
            } else {
                cellContent
            }
        }
    }

    private var cellContent: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(day.hasTransactions ? AppColor.primary.opacity(0.16) : Color.clear)
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(day.hasTransactions ? AppColor.primary.opacity(0.45) : AppColor.line.opacity(0.35), lineWidth: 1)
                )

            if let dayNumber = day.day {
                Text(verbatim: "\(dayNumber)")
                    .font(.title3.weight(day.hasTransactions ? .semibold : .regular))
                    .foregroundStyle(day.hasTransactions ? AppColor.primary : AppColor.ink)
                    .padding(.top, 2)
            }
        }
        .frame(height: 38)
        .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }
}

struct TransactionDateDetailView: View {
    var store: AppStore
    var date: Date
    @State private var message: String?

    private var sortedTransactions: [MoneyTransaction] {
        let calendar = Calendar.current
        return store.transactions
            .filter { calendar.isDate($0.occurredAt, inSameDayAs: date) }
            .sorted { $0.occurredAt > $1.occurredAt }
    }

    var body: some View {
        List {
            ForEach(sortedTransactions) { transaction in
                EditableTransactionRow(
                    store: store,
                    transaction: transaction,
                    message: $message
                )
            }
        }
        .tabBarScrollableContentInset()
        .listStyle(.plain)
        .navigationTitle(Self.dateText(for: date))
        .alert("删除失败", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private static func dateText(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M 月 d 日 EEEE"
        return formatter.string(from: date)
    }
}

private struct EditableTransactionRow: View {
    var store: AppStore
    var transaction: MoneyTransaction
    @Binding var message: String?
    @State private var transactionBeingEdited: MoneyTransaction?

    var body: some View {
        TransactionRow(transaction: transaction)
            .swipeActions(edge: .leading, allowsFullSwipe: false) {
                Button(role: .destructive) {
                    deleteTransaction()
                } label: {
                    Image(systemName: "trash")
                }
                .tint(.red)

                Button {
                    transactionBeingEdited = transaction
                } label: {
                    Image(systemName: "pencil.circle")
                }
                .tint(AppColor.primary)
            }
            .sheet(item: $transactionBeingEdited) { transaction in
                TransactionEditView(store: store, transaction: transaction)
            }
    }

    private func deleteTransaction() {
        do {
            try store.deleteTransaction(transaction)
        } catch {
            message = error.localizedDescription
        }
    }
}

private struct TransactionEditView: View {
    var store: AppStore
    var transaction: MoneyTransaction

    @Environment(\.dismiss) private var dismiss
    @State private var selectedKind: TransactionKind
    @State private var titleText: String
    @State private var amountText: String
    @State private var selectedCategory: MoneyCategory
    @State private var selectedAccountID: UUID?
    @State private var selectedPaymentAccountID: UUID?
    @State private var selectedDate: Date
    @State private var useInstallment: Bool
    @State private var installmentMonths: Int
    @State private var saveError: String?

    init(store: AppStore, transaction: MoneyTransaction) {
        self.store = store
        self.transaction = transaction
        let initialKind = transaction.kind == .income ? TransactionKind.income : .expense
        let visibleCategories = store.categories(for: initialKind)
        let initialCategory = visibleCategories.first { $0.id == transaction.category.id }
            ?? visibleCategories.first
            ?? transaction.category

        _selectedKind = State(initialValue: initialKind)
        _titleText = State(initialValue: transaction.title)
        _amountText = State(initialValue: NSDecimalNumber(decimal: transaction.amount).stringValue)
        _selectedCategory = State(initialValue: initialCategory)
        _selectedAccountID = State(initialValue: transaction.account.id)
        _selectedPaymentAccountID = State(initialValue: transaction.paymentAccount?.id)
        _selectedDate = State(initialValue: transaction.occurredAt)
        _useInstallment = State(initialValue: transaction.installmentMonths != nil)
        _installmentMonths = State(initialValue: transaction.installmentMonths ?? 3)
    }

    private var visibleCategories: [MoneyCategory] {
        store.categories(for: selectedKind)
    }

    private var parsedAmount: Decimal? {
        Decimal.moneyString(amountText)
    }

    private var selectedAccount: MoneyAccount? {
        if let selectedAccountID,
           let account = entryAccounts.first(where: { $0.id == selectedAccountID }) {
            return account
        }

        return entryAccounts.first
    }

    private var selectedAsset: AssetItem? {
        selectedAccount.flatMap(store.asset(for:))
    }

    private var selectedPaymentAccount: MoneyAccount? {
        if let selectedPaymentAccountID,
           let account = repaymentPaymentAccounts.first(where: { $0.id == selectedPaymentAccountID }) {
            return account
        }

        return repaymentPaymentAccounts.first
    }

    private var entryAccounts: [MoneyAccount] {
        if isRepaymentEntry {
            return store.repaymentAccounts
        }

        return store.paymentAccounts
    }

    private var repaymentPaymentAccounts: [MoneyAccount] {
        store.repaymentPaymentAccounts
            .filter { $0.id != selectedAccount?.id }
    }

    private var canUseInstallment: Bool {
        selectedKind == .expense
            && !selectedCategory.isRepayment
            && (selectedAsset?.kind.supportsInstallment ?? false)
    }

    private var isRepaymentEntry: Bool {
        selectedKind == .expense && selectedCategory.isRepayment
    }

    private var canSave: Bool {
        guard let parsedAmount, parsedAmount > 0, selectedAccount != nil else { return false }
        if isRepaymentEntry, selectedPaymentAccount == nil {
            return false
        }
        return true
    }

    private var categoryColumns: [GridItem] {
        [
            GridItem(.adaptive(minimum: 78), spacing: 10)
        ]
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    kindSection
                    amountSection
                    titleSection
                    dateSection
                    accountSection
                    repaymentPaymentAccountSection
                    installmentSection
                    categorySection
                    saveButton
                }
                .padding()
            }
            .background(AppColor.background)
            .navigationTitle("修改账目")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }
            }
            .onAppear(perform: ensureSelectedAccountsAreValid)
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var kindSection: some View {
        Picker("类型", selection: $selectedKind) {
            Text(TransactionKind.expense.title).tag(TransactionKind.expense)
            Text(TransactionKind.income.title).tag(TransactionKind.income)
        }
        .pickerStyle(.segmented)
        .onChange(of: selectedKind) { _, newValue in
            if let first = store.categories(for: newValue).first {
                selectedCategory = first
            }
            ensureSelectedAccountsAreValid()
            if newValue != .expense || selectedCategory.isRepayment {
                useInstallment = false
            }
        }
    }

    private var amountSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("金额")
                .font(.subheadline)
                .foregroundStyle(AppColor.muted)

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("¥")
                    .font(.title2.weight(.medium))
                    .foregroundStyle(AppColor.muted)

                TextField("0", text: $amountText)
                    .font(.system(size: 38, weight: .semibold, design: .rounded))
                    #if os(iOS)
                    .keyboardType(.decimalPad)
                    #endif
            }
        }
        .surface()
    }

    private var titleSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("名称")
                .font(.headline)
                .foregroundStyle(AppColor.ink)

            TextField("账目名称", text: $titleText)
                .textFieldStyle(.roundedBorder)
        }
        .surface()
    }

    private var dateSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("日期")
                .font(.headline)
                .foregroundStyle(AppColor.ink)

            DatePicker(
                "记账日期",
                selection: $selectedDate,
                in: EntryDateHelper.allowedRange,
                displayedComponents: .date
            )
        }
        .surface()
    }

    private var accountSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(accountTitle)
                .font(.headline)
                .foregroundStyle(AppColor.ink)

            if entryAccounts.isEmpty {
                Text(isRepaymentEntry ? "请先在资产页添加待还账户。" : "请先在资产页添加可记账账户。")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.muted)
            } else {
                Picker("账户", selection: Binding(
                    get: { selectedAccount?.id ?? entryAccounts[0].id },
                    set: { newValue in
                        selectedAccountID = newValue
                        ensureSelectedPaymentAccountIsValid()
                        let asset = store.ledgerAssets.first { $0.id == newValue }
                        if selectedCategory.isRepayment || !(asset?.kind.supportsInstallment ?? false) {
                            useInstallment = false
                        }
                    }
                )) {
                    ForEach(entryAccounts) { account in
                        Label(account.name, systemImage: account.symbolName)
                            .tag(account.id)
                    }
                }
                .pickerStyle(.menu)
            }
        }
        .surface()
    }

    private var accountTitle: String {
        if isRepaymentEntry {
            return "还款账户"
        }

        return selectedKind == .expense ? "支付账户" : "收款账户"
    }

    @ViewBuilder
    private var repaymentPaymentAccountSection: some View {
        if isRepaymentEntry {
            VStack(alignment: .leading, spacing: 12) {
                Text("支付账户")
                    .font(.headline)
                    .foregroundStyle(AppColor.ink)

                if repaymentPaymentAccounts.isEmpty {
                    Text("请先在资产页添加可支付的余额账户。")
                        .font(.subheadline)
                        .foregroundStyle(AppColor.muted)
                } else {
                    Picker("支付账户", selection: Binding(
                        get: { selectedPaymentAccount?.id ?? repaymentPaymentAccounts[0].id },
                        set: { selectedPaymentAccountID = $0 }
                    )) {
                        ForEach(repaymentPaymentAccounts) { account in
                            Label(account.name, systemImage: account.symbolName)
                                .tag(account.id)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .surface()
        }
    }

    @ViewBuilder
    private var installmentSection: some View {
        if canUseInstallment {
            VStack(alignment: .leading, spacing: 12) {
                Toggle(isOn: $useInstallment) {
                    Label("分期付款", systemImage: "calendar.badge.clock")
                        .font(.headline)
                        .foregroundStyle(AppColor.ink)
                }

                if useInstallment {
                    Picker("分期月数", selection: $installmentMonths) {
                        ForEach(1...24, id: \.self) { month in
                            Text("\(month) 个月").tag(month)
                        }
                    }
                    .pickerStyle(.menu)
                }
            }
            .surface()
        }
    }

    @ViewBuilder
    private var categorySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(selectedKind == .expense ? "支出分类" : "收入分类")
                .font(.headline)
                .foregroundStyle(AppColor.ink)

            LazyVGrid(columns: categoryColumns, spacing: 10) {
                ForEach(visibleCategories) { category in
                    CategoryButton(
                        category: category,
                        isSelected: category.id == selectedCategory.id
                    ) {
                        selectedCategory = category
                        ensureSelectedAccountsAreValid()
                        if category.isRepayment {
                            useInstallment = false
                        }
                    }
                }
            }
        }
        .surface()
    }

    private var saveButton: some View {
        Button {
            save()
        } label: {
            Label("保存修改", systemImage: "checkmark")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColor.success)
        .disabled(!canSave)
    }

    private func save() {
        guard let parsedAmount,
              let selectedAccount
        else {
            return
        }

        do {
            let trimmedTitle = titleText.trimmingCharacters(in: .whitespacesAndNewlines)
            try store.updateTransaction(
                transaction,
                kind: selectedKind,
                amount: parsedAmount,
                category: selectedCategory,
                account: selectedAccount,
                title: trimmedTitle.isEmpty ? selectedCategory.name : trimmedTitle,
                paymentAccount: isRepaymentEntry ? selectedPaymentAccount : nil,
                installmentMonths: useInstallment && canUseInstallment ? installmentMonths : nil,
                occurredAt: EntryDateHelper.occurredAt(on: selectedDate, keepingTimeFrom: transaction.occurredAt)
            )
            dismiss()
        } catch {
            saveError = error.localizedDescription
        }
    }

    private func ensureSelectedAccountsAreValid() {
        ensureSelectedEntryAccountIsValid()
        ensureSelectedPaymentAccountIsValid()
    }

    private func ensureSelectedEntryAccountIsValid() {
        if let selectedAccountID,
           entryAccounts.contains(where: { $0.id == selectedAccountID }) {
            return
        }

        selectedAccountID = entryAccounts.first?.id
    }

    private func ensureSelectedPaymentAccountIsValid() {
        guard isRepaymentEntry else { return }
        if let selectedPaymentAccountID,
           repaymentPaymentAccounts.contains(where: { $0.id == selectedPaymentAccountID }) {
            return
        }

        selectedPaymentAccountID = repaymentPaymentAccounts.first?.id
    }
}

struct RecentTransactionsSection: View {
    var store: AppStore
    var transactions: [MoneyTransaction]
    @Binding var message: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("最近账目")
                .font(.headline)
                .foregroundStyle(AppColor.ink)

            if transactions.isEmpty {
                Text("本月还没有账目")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.muted)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(spacing: 0) {
                    ForEach(transactions) { transaction in
                        EditableTransactionRow(
                            store: store,
                            transaction: transaction,
                            message: $message
                        )

                        if transaction.id != transactions.last?.id {
                            Divider()
                                .padding(.leading, 52)
                        }
                    }
                }
            }
        }
        .surface()
    }
}

struct AccountsView: View {
    var store: AppStore
    @State private var isAddingAsset = false
    @State private var editingAsset: AssetItem?
    @State private var assetPendingDeletion: AssetItem?
    @State private var message: String?

    private var regularAssets: [AssetItem] {
        store.ledgerAssets.filter { !$0.isDebtLike }.sorted {
            if $0.kind == .fund && $1.kind != .fund {
                return true
            }
            if $0.kind != .fund && $1.kind == .fund {
                return false
            }
            return false
        }
    }

    private var debtAssets: [AssetItem] {
        store.ledgerAssets.filter(\.isDebtLike)
    }

    private var liveBalanceScaleBase: Double {
        let maxValue = regularAssets
            .map { abs(liveBalanceValue(for: $0).doubleValue) }
            .max() ?? 0
        return max(maxValue, 1)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    AssetSection(title: "实时余额") {
                        ForEach(regularAssets) { asset in
                            AssetBalanceRow(asset: asset, scaleBase: liveBalanceScaleBase)
                        }
                    }

                    if !debtAssets.isEmpty {
                        AssetSection(title: "待还款") {
                            ForEach(debtAssets) { asset in
                                AssetCard(
                                    asset: asset,
                                    canManage: store.initializationMode,
                                    onEdit: { editingAsset = store.assets.first { $0.id == asset.id } ?? asset },
                                    onDelete: { assetPendingDeletion = asset }
                                )
                            }
                        }
                    }

                    if store.initializationMode {
                        AssetSection(title: "初始化数据") {
                            ForEach(store.ledgerAssets) { asset in
                                AssetCard(
                                    asset: asset,
                                    canManage: true,
                                    onEdit: { editingAsset = store.assets.first { $0.id == asset.id } ?? asset },
                                    onDelete: { assetPendingDeletion = asset }
                                )
                            }
                        }
                    }
                }
                .padding()
            }
            .tabBarScrollableContentInset()
            .background(AppColor.background)
            .toolbar {
                if store.initializationMode {
                    Button {
                        isAddingAsset = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $isAddingAsset) {
                AddAssetView(store: store)
            }
            .sheet(item: $editingAsset) { asset in
                AssetEditorView(store: store, asset: asset)
            }
            .confirmationDialog(
                "删除资产",
                isPresented: Binding(
                    get: { assetPendingDeletion != nil },
                    set: { if !$0 { assetPendingDeletion = nil } }
                ),
                presenting: assetPendingDeletion
            ) { asset in
                Button("删除“\(asset.name)”", role: .destructive) {
                    deleteAsset(asset)
                }
                Button("取消", role: .cancel) {}
            } message: { asset in
                Text("删除后这个资产不会再出现在资产列表。已经被账目使用的资产不会被删除。")
            }
            .alert("提示", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func deleteAsset(_ asset: AssetItem) {
        do {
            try store.deleteAsset(asset)
        } catch {
            message = error.localizedDescription
        }
    }

    private func liveBalanceValue(for asset: AssetItem) -> Decimal {
        if asset.kind == .fund {
            return asset.fundCurrentValue
        }
        return asset.balance
    }
}

struct AssetSection<Content: View>: View {
    var title: String
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.headline)
                .foregroundStyle(AppColor.ink)

            VStack(spacing: 12) {
                content
            }
        }
    }
}

struct AssetCard: View {
    var asset: AssetItem
    var canManage: Bool
    var onEdit: () -> Void
    var onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: asset.kind.symbolName)
                    .foregroundStyle(AppColor.primary)
                    .frame(width: 42, height: 42)
                    .background(AppColor.primary.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(asset.name)
                        .font(.headline)
                        .foregroundStyle(AppColor.ink)

                    Text(asset.kind.title)
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)
                }

                Spacer()

                if canManage {
                    Button(action: onEdit) {
                        Image(systemName: "pencil")
                    }
                    .buttonStyle(.borderless)

                    Button(role: .destructive, action: onDelete) {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                }
            }

            if asset.kind == .fund {
                AssetValueRow(title: "当前资产", value: MoneyFormat.yuan(asset.fundCurrentValue))
                AssetValueRow(title: "持有成本", value: MoneyFormat.yuan(asset.fundCost ?? 0))
                AssetValueRow(
                    title: "总盈亏",
                    value: MoneyFormat.yuan(asset.fundProfit, signed: asset.fundProfit > 0),
                    color: asset.fundProfit < 0 ? AppColor.danger : (asset.fundProfit > 0 ? AppColor.success : AppColor.muted)
                )

                if !asset.fundActivities.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(asset.fundActivities.prefix(5)) { record in
                            FundActivityRow(record: record)
                        }
                    }
                    .padding(.top, 4)
                }
            } else {
                AssetValueRow(title: asset.isDebtLike ? "总欠款" : "余额", value: MoneyFormat.yuan(asset.isDebtLike ? asset.totalDebt : asset.balance))
            }

            if asset.isDebtLike {
                AssetValueRow(title: "本月待还", value: MoneyFormat.yuan(asset.currentMonthRepayment))
                AssetValueRow(title: "下月待还", value: MoneyFormat.yuan(asset.nextMonthRepayment))
            }
        }
        .surface()
    }
}

struct FundActivityRow: View {
    var record: FundActivity

    private var dateText: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MM-dd"
        return formatter.string(from: record.occurredAt)
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: record.kind.symbolName)
                .foregroundStyle(record.kind == .investment ? AppColor.success : AppColor.primary)
                .frame(width: 28, height: 28)
                .background((record.kind == .investment ? AppColor.success : AppColor.primary).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(record.kind.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(AppColor.ink)

                Text(record.note.isEmpty ? dateText : "\(dateText) · \(record.note)")
                    .font(.caption)
                    .foregroundStyle(AppColor.muted)
                    .lineLimit(1)
            }

            Spacer()

            Text(MoneyFormat.yuan(record.amount, signed: record.kind == .valuation))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(fundActivityAmountColor)
        }
    }

    private var fundActivityAmountColor: Color {
        guard record.kind == .valuation else { return AppColor.ink }
        if record.amount < 0 {
            return AppColor.danger
        }
        if record.amount > 0 {
            return AppColor.success
        }
        return AppColor.muted
    }
}

struct FundActivityView: View {
    var store: AppStore
    var asset: AssetItem
    @Environment(\.dismiss) private var dismiss

    @State private var kind: FundActivityKind = .valuation
    @State private var amountText = ""
    @State private var note = ""
    @State private var saveError: String?

    private var amount: Decimal? {
        Decimal.moneyString(amountText)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基金") {
                    LabeledContent("名称", value: asset.name)

                    Picker("记录类型", selection: $kind) {
                        ForEach(FundActivityKind.allCases) { kind in
                            Label(kind.title, systemImage: kind.symbolName).tag(kind)
                        }
                    }
                }

                Section(kind == .valuation ? "盈亏金额" : "投入金额") {
                    TextField(kind == .valuation ? "盈利填正数，亏损填负数" : "投入/定投金额", text: $amountText)
                        #if os(iOS)
                        .keyboardType(kind == .valuation ? .numbersAndPunctuation : .decimalPad)
                        #endif

                    TextField("备注", text: $note)
                }
            }
            .navigationTitle("记录基金")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        guard let amount, canSave else { return }
                        do {
                            try store.addFundActivity(assetID: asset.id, kind: kind, amount: amount, note: note)
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var canSave: Bool {
        guard let amount else { return false }
        switch kind {
        case .valuation:
            return amount != 0
        case .investment:
            return amount > 0
        }
    }
}

struct AssetEditorView: View {
    var store: AppStore
    @Environment(\.dismiss) private var dismiss

    @State private var asset: AssetItem
    @State private var balanceText: String
    @State private var fundCostText: String
    @State private var fundMarketValueText: String
    @State private var repaymentTexts: [String]
    @State private var saveError: String?

    init(store: AppStore, asset: AssetItem) {
        self.store = store
        _asset = State(initialValue: asset)
        _balanceText = State(initialValue: Self.text(from: asset.balance))
        _fundCostText = State(initialValue: Self.text(from: asset.fundCost ?? 0))
        _fundMarketValueText = State(initialValue: Self.text(from: asset.fundMarketValue ?? 0))
        _repaymentTexts = State(initialValue: asset.repayments.map { Self.text(from: $0.amount) })
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("基本信息") {
                    TextField("名称", text: $asset.name)
                    LabeledContent("类型", value: asset.kind.title)
                    if asset.kind != .fund {
                        moneyField(asset.kind.isDebtAccount ? "总欠款" : "余额", text: $balanceText)
                    }
                }

                if asset.kind == .fund {
                    Section("基金") {
                        moneyField("持有成本", text: $fundCostText)
                        moneyField("当前资产", text: $fundMarketValueText)
                    }
                }

                if asset.kind.isDebtAccount {
                    Section("24 个月待还") {
                        ForEach(asset.repayments.indices, id: \.self) { index in
                            moneyField(asset.repayments[index].title, text: $repaymentTexts[index])
                        }
                    }
                }
            }
            .navigationTitle("编辑资产")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try save()
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private func moneyField(_ title: String, text: Binding<String>) -> some View {
        TextField(title, text: text)
            #if os(iOS)
            .keyboardType(.decimalPad)
            #endif
    }

    private func save() throws {
        if asset.kind != .fund {
            asset.balance = try moneyValue(balanceText, field: asset.kind.isDebtAccount ? "总欠款" : "余额")
        }

        if asset.kind == .fund {
            asset.fundCost = try moneyValue(fundCostText, field: "持有成本")
            asset.fundMarketValue = try moneyValue(fundMarketValueText, field: "当前资产")
            asset.balance = asset.fundCurrentValue
        }

        if asset.kind.isDebtAccount {
            asset.repayments = try asset.repayments.indices.map { index in
                RepaymentMonth(
                    id: asset.repayments[index].id,
                    monthOffset: asset.repayments[index].monthOffset,
                    amount: try moneyValue(repaymentTexts[index], field: asset.repayments[index].title)
                )
            }
        }

        try store.updateAsset(asset)
    }

    private func moneyValue(_ text: String, field: String) throws -> Decimal {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return 0 }
        guard let value = Decimal.moneyString(trimmed) else {
            throw AppStoreFailure.invalidMoneyInput(field)
        }
        return value
    }

    private static func text(from value: Decimal) -> String {
        value == 0 ? "" : NSDecimalNumber(decimal: value).stringValue
    }
}

struct AssetValueRow: View {
    var title: String
    var value: String
    var color: Color = AppColor.ink

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppColor.muted)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(color)
        }
    }
}

struct AddAssetView: View {
    var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var accountCategory: AssetAccountCategory = .balance
    @State private var kind: AssetKind = .debitCard
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $name)

                Section("账户分类") {
                    Picker("分类", selection: $accountCategory) {
                        ForEach(AssetAccountCategory.allCases) { category in
                            Text(category.title).tag(category)
                        }
                    }

                    Text(accountCategory.detail)
                        .font(.caption)
                        .foregroundStyle(AppColor.muted)
                }

                Section("账户类型") {
                    Picker("类型", selection: $kind) {
                        ForEach(accountCategory.assetKinds) { kind in
                            Label(kind.title, systemImage: kind.symbolName).tag(kind)
                        }
                    }
                }
            }
            .navigationTitle("新增资产")
            .onChange(of: accountCategory) { _, newValue in
                if !newValue.assetKinds.contains(kind),
                   let firstKind = newValue.assetKinds.first {
                    kind = firstKind
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try store.addAsset(name: name, kind: kind)
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }
}

struct SettingsView: View {
    var store: AppStore

    @State private var exportDocument = JSONExportDocument()
    @State private var isExporting = false
    @State private var isImporting = false
    @State private var message: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("外观") {
                    Picker("主题", selection: Binding(
                        get: { store.appearance },
                        set: { store.appearance = $0 }
                    )) {
                        ForEach(AppAppearance.allCases) { appearance in
                            Text(appearance.title).tag(appearance)
                        }
                    }
                }

                Section("数据") {
                    Toggle(isOn: Binding(
                        get: { store.initializationMode },
                        set: { store.initializationMode = $0 }
                    )) {
                        Label("初始化数据模式", systemImage: "slider.horizontal.3")
                    }

                    NavigationLink {
                        CategoryManagerView(store: store)
                    } label: {
                        Label("分类管理", systemImage: "tag.fill")
                    }

                    Button {
                        exportJSON()
                    } label: {
                        Label("导出 JSON", systemImage: "square.and.arrow.up")
                    }

                    Button {
                        isImporting = true
                    } label: {
                        Label("导入 JSON", systemImage: "square.and.arrow.down")
                    }

                    Label("iCloud 同步暂未开启", systemImage: "icloud.slash")
                        .foregroundStyle(AppColor.muted)
                }
            }
            .tabBarScrollableContentInset()
            .fileExporter(
                isPresented: $isExporting,
                document: exportDocument,
                contentType: .json,
                defaultFilename: "ledgerly-export.json"
            ) { result in
                if case let .failure(error) = result {
                    message = error.localizedDescription
                }
            }
            .fileImporter(isPresented: $isImporting, allowedContentTypes: [.json]) { result in
                importJSON(result)
            }
            .alert("提示", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func exportJSON() {
        do {
            exportDocument = JSONExportDocument(data: try store.exportData())
            isExporting = true
        } catch {
            message = error.localizedDescription
        }
    }

    private func importJSON(_ result: Result<URL, Error>) {
        do {
            let url = try result.get()
            let didAccess = url.startAccessingSecurityScopedResource()
            defer {
                if didAccess {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            try store.importData(Data(contentsOf: url))
            message = "导入完成"
        } catch {
            message = error.localizedDescription
        }
    }
}

struct CategoryManagerView: View {
    var store: AppStore
    @State private var isAdding = false
    @State private var message: String?

    var body: some View {
        List {
            Section("支出") {
                ForEach(store.expenseCategories) { category in
                    CategoryManagerRow(category: category) {
                        deleteCategory(category)
                    }
                }
            }

            Section("收入") {
                ForEach(store.incomeCategories) { category in
                    CategoryManagerRow(category: category) {
                        deleteCategory(category)
                    }
                }
            }
        }
        .tabBarScrollableContentInset()
        .navigationTitle("分类管理")
        .toolbar {
            Button {
                isAdding = true
            } label: {
                Image(systemName: "plus")
            }
        }
        .sheet(isPresented: $isAdding) {
            AddCategoryView(store: store)
        }
        .alert("提示", isPresented: Binding(
            get: { message != nil },
            set: { if !$0 { message = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(message ?? "")
        }
    }

    private func deleteCategory(_ category: MoneyCategory) {
        do {
            try store.deleteCategory(category)
        } catch {
            message = error.localizedDescription
        }
    }
}

struct CategoryManagerRow: View {
    var category: MoneyCategory
    var onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: category.symbolName)
                .foregroundStyle(category.color)
                .frame(width: 30, height: 30)
                .background(category.color.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            Text(category.name)

            Spacer()

            if category.isSystemPreset {
                Text("预设")
                    .font(.caption)
                    .foregroundStyle(AppColor.muted)
            } else {
                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                }
                .buttonStyle(.borderless)
            }
        }
    }
}

struct AddCategoryView: View {
    var store: AppStore
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var kind: CategoryKind = .expense
    @State private var symbolName = Self.iconOptions[0]
    @State private var saveError: String?

    private static let iconOptions = [
        "tag.fill",
        "fork.knife",
        "cart.fill",
        "bag.fill",
        "cup.and.saucer.fill",
        "car.fill",
        "tram.fill",
        "house.fill",
        "cross.case.fill",
        "book.fill",
        "gamecontroller.fill",
        "gift.fill",
        "banknote.fill",
        "creditcard.fill",
        "chart.line.uptrend.xyaxis",
        "percent",
        "doc.text.fill",
        "envelope.fill",
        "shippingbox.fill",
        "ellipsis.circle.fill"
    ]

    private let iconColumns = Array(repeating: GridItem(.flexible(), spacing: 10), count: 5)

    var body: some View {
        NavigationStack {
            Form {
                TextField("分类名称", text: $name)

                Picker("类型", selection: $kind) {
                    Text("支出").tag(CategoryKind.expense)
                    Text("收入").tag(CategoryKind.income)
                }
                .pickerStyle(.segmented)

                Section("图标") {
                    LazyVGrid(columns: iconColumns, spacing: 10) {
                        ForEach(Self.iconOptions, id: \.self) { option in
                            Button {
                                symbolName = option
                            } label: {
                                Image(systemName: option)
                                    .font(.title3)
                                    .foregroundStyle(symbolName == option ? AppColor.primary : AppColor.ink)
                                    .frame(width: 44, height: 44)
                                    .background(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .fill(symbolName == option ? AppColor.primary.opacity(0.14) : AppColor.surface)
                                    )
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                                            .stroke(symbolName == option ? AppColor.primary : AppColor.line, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .navigationTitle("新增分类")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消") {
                        dismiss()
                    }
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        do {
                            try store.addCategory(name: name, kind: kind, symbolName: symbolName)
                            dismiss()
                        } catch {
                            saveError = error.localizedDescription
                        }
                    }
                    .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .alert("保存失败", isPresented: Binding(
                get: { saveError != nil },
                set: { if !$0 { saveError = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(saveError ?? "")
            }
        }
    }
}

struct JSONExportDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }

    var data: Data

    init(data: Data = Data()) {
        self.data = data
    }

    init(configuration: ReadConfiguration) throws {
        data = configuration.file.regularFileContents ?? Data()
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
