import SwiftUI

struct AppShellView: View {
    @State private var store = AppStore()
    @State private var selectedTab: AppTab = .home
    @State private var shortcutDraftPollingTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        TabView(selection: $selectedTab) {
            TransactionsView(store: store)
                .tabItem {
                    Label(AppTab.transactions.title, systemImage: AppTab.transactions.symbolName)
                }
                .tag(AppTab.transactions)

            DashboardView(
                store: store,
                selectedTab: $selectedTab
            )
                .tabItem {
                    Label(AppTab.home.title, systemImage: AppTab.home.symbolName)
                }
                .tag(AppTab.home)

            EntryView(store: store)
                .tabItem {
                    Label(AppTab.entry.title, systemImage: AppTab.entry.symbolName)
                }
                .tag(AppTab.entry)

            AccountsView(store: store)
                .tabItem {
                    Label(AppTab.accounts.title, systemImage: AppTab.accounts.symbolName)
                }
                .tag(AppTab.accounts)

            SettingsView(store: store)
                .tabItem {
                    Label(AppTab.settings.title, systemImage: AppTab.settings.symbolName)
                }
                .tag(AppTab.settings)
        }
        .tint(AppColor.primary)
        .preferredColorScheme(store.appearance.colorScheme)
        .installKeyboardDismissGesture()
        .onAppear(perform: startShortcutDraftPolling)
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                startShortcutDraftPolling()
            }
        }
        .onDisappear {
            shortcutDraftPollingTask?.cancel()
        }
        .alert("数据加载失败", isPresented: Binding(
            get: { store.startupError != nil },
            set: { if !$0 { store.startupError = nil } }
        )) {
            Button("好", role: .cancel) {}
        } message: {
            Text(store.startupError ?? "")
        }
    }

    private func startShortcutDraftPolling() {
        shortcutDraftPollingTask?.cancel()
        shortcutDraftPollingTask = Task { @MainActor in
            for attempt in 0..<12 {
                if applyShortcutDraftIfNeeded() {
                    return
                }

                if attempt < 11 {
                    try? await Task.sleep(nanoseconds: 250_000_000)
                }
            }
        }
    }

    private func applyShortcutDraftIfNeeded() -> Bool {
        if let draft = QuickEntryShortcutStore.takePendingDraft() {
            store.applyQuickEntryDraft(draft)
            QuickEntryShortcutStore.clearOpenEntryRequest()
            selectedTab = .entry
            return true
        } else if QuickEntryShortcutStore.shouldOpenEntry() {
            selectedTab = .entry
        }

        return false
    }
}

enum AppTab: Hashable {
    case home
    case entry
    case transactions
    case accounts
    case settings

    var title: String {
        switch self {
        case .home: "总览"
        case .entry: "记账"
        case .transactions: "明细"
        case .accounts: "资产"
        case .settings: "设置"
        }
    }

    var symbolName: String {
        switch self {
        case .home: "chart.pie.fill"
        case .entry: "plus.app.fill"
        case .transactions: "list.bullet.rectangle.fill"
        case .accounts: "creditcard.fill"
        case .settings: "gearshape.fill"
        }
    }
}
