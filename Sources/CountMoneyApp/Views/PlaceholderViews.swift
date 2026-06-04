import PhotosUI
import SwiftUI
import UniformTypeIdentifiers

struct EntryView: View {
    var store: AppStore

    @State private var selectedKind: TransactionKind = .expense
    @State private var amountText = ""
    @State private var selectedCategory: MoneyCategory = PreviewData.expenseCategories[0]
    @State private var selectedAccountID: UUID?
    @State private var selectedImageItem: PhotosPickerItem?
    @State private var ocrError: String?
    @State private var saveError: String?
    @State private var isRecognizing = false
    @State private var isApplyingDraft = false
    @State private var useInstallment = false
    @State private var installmentMonths = 3
    @State private var isFundLoss = false
    @State private var appliedDraftID: UUID?

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
        selectedKind == .fundProfit ? fundAccounts : store.paymentAccounts
    }

    private var canUseInstallment: Bool {
        selectedKind == .expense && (selectedAsset?.kind.supportsInstallment ?? false)
    }

    private var canSaveEntry: Bool {
        guard let parsedAmount, selectedAccount != nil else { return false }
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
                        selectedAccountID = entryAccounts.first?.id
                        if newValue != .expense {
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
                    installmentSection
                    categorySection
                    if selectedKind != .fundProfit {
                        screenshotButton
                    }
                    saveButton

                    Spacer()
                }
            }
            .padding()
            .background(AppColor.background)
            .navigationTitle("记账")
            .onAppear {
                if selectedAccountID == nil {
                    selectedAccountID = store.paymentAccounts.first?.id
                }
                applyQuickEntryDraftIfNeeded(store.quickEntryDraft)
            }
            .onChange(of: store.quickEntryDraft) { _, draft in
                applyQuickEntryDraftIfNeeded(draft)
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
                Text(selectedKind == .fundProfit ? "请先在资产页添加基金。" : "请先在资产页添加银行卡、支付宝或微信账户。")
                    .font(.subheadline)
                    .foregroundStyle(AppColor.muted)
            } else {
                Picker("账户", selection: Binding(
                    get: { selectedAccount?.id ?? entryAccounts[0].id },
                    set: { newValue in
                        selectedAccountID = newValue
                        let asset = store.ledgerAssets.first { $0.id == newValue }
                        if !(asset?.kind.supportsInstallment ?? false) {
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

    private var accountTitle: String {
        switch selectedKind {
        case .expense:
            return "支付账户"
        case .income:
            return "收款账户"
        case .fundProfit:
            return "基金"
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
        if selectedKind != .fundProfit, let draft = store.quickEntryDraft {
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
        if selectedKind != .fundProfit {
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
                        }
                    }
                }
            }
            .surface()
        }
    }

    private var screenshotButton: some View {
        PhotosPicker(selection: $selectedImageItem, matching: .images) {
            Label("截图识别金额", systemImage: "viewfinder")
                .font(.headline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
        }
        .buttonStyle(.borderedProminent)
        .tint(AppColor.primary)
        .disabled(isRecognizing)
        .onChange(of: selectedImageItem) { _, item in
            guard let item else { return }
            Task {
                await recognizeAmount(from: item)
            }
        }
        .alert("识别失败", isPresented: Binding(
            get: { ocrError != nil },
            set: { if !$0 { ocrError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(ocrError ?? "")
        }
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
                    try store.addFundProfit(assetID: selectedAccount.id, amount: signedAmount, note: "")
                } else {
                    try store.addTransaction(
                        kind: selectedKind,
                        amount: parsedAmount,
                        category: selectedCategory,
                        account: selectedAccount,
                        title: selectedCategory.name,
                        installmentMonths: useInstallment && canUseInstallment ? installmentMonths : nil
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

    private func recognizeAmount(from item: PhotosPickerItem) async {
        isRecognizing = true
        defer {
            isRecognizing = false
            selectedImageItem = nil
        }

        do {
            guard let data = try await item.loadTransferable(type: Data.self) else {
                throw OCRFailure.invalidImage
            }

            let draft = try await ScreenshotOCRService.makeDraft(from: data)
            store.applyQuickEntryDraft(draft)
            applyAmount(draft.candidateAmount)
            selectedKind = draft.suggestedKind

            if let first = store.categories(for: draft.suggestedKind).first {
                selectedCategory = first
            }
        } catch {
            ocrError = error.localizedDescription
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
    @State private var message: String?

    private var sortedTransactions: [MoneyTransaction] {
        store.transactions.sorted { $0.occurredAt > $1.occurredAt }
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(sortedTransactions) { transaction in
                    TransactionRow(transaction: transaction)
                }
                .onDelete(perform: deleteTransactions)
            }
            .navigationTitle("明细")
            .alert("删除失败", isPresented: Binding(
                get: { message != nil },
                set: { if !$0 { message = nil } }
            )) {
                Button("好", role: .cancel) {}
            } message: {
                Text(message ?? "")
            }
        }
    }

    private func deleteTransactions(at offsets: IndexSet) {
        let transactionsToDelete = offsets.map { sortedTransactions[$0] }

        do {
            for transaction in transactionsToDelete {
                try store.deleteTransaction(transaction)
            }
        } catch {
            message = error.localizedDescription
        }
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
            .background(AppColor.background)
            .navigationTitle("资产")
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
                        moneyField(asset.kind.supportsRepayment ? "总欠款" : "余额", text: $balanceText)
                    }
                }

                if asset.kind == .fund {
                    Section("基金") {
                        moneyField("持有成本", text: $fundCostText)
                        moneyField("当前资产", text: $fundMarketValueText)
                    }
                }

                if asset.kind.supportsRepayment {
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
            asset.balance = try moneyValue(balanceText, field: asset.kind.supportsRepayment ? "总欠款" : "余额")
        }

        if asset.kind == .fund {
            asset.fundCost = try moneyValue(fundCostText, field: "持有成本")
            asset.fundMarketValue = try moneyValue(fundMarketValueText, field: "当前资产")
            asset.balance = asset.fundCurrentValue
        }

        if asset.kind.supportsRepayment {
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
    @State private var kind: AssetKind = .debitCard
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("名称", text: $name)

                Picker("类型", selection: $kind) {
                    ForEach(AssetKind.allCases) { kind in
                        Label(kind.title, systemImage: kind.symbolName).tag(kind)
                    }
                }
            }
            .navigationTitle("新增资产")
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
            .navigationTitle("设置")
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
    @State private var saveError: String?

    var body: some View {
        NavigationStack {
            Form {
                TextField("分类名称", text: $name)

                Picker("类型", selection: $kind) {
                    Text("支出").tag(CategoryKind.expense)
                    Text("收入").tag(CategoryKind.income)
                }
                .pickerStyle(.segmented)
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
                            try store.addCategory(name: name, kind: kind)
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
