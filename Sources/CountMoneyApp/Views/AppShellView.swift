import SwiftUI

struct AppShellView: View {
    @State private var store = AppStore()
    @State private var selectedTab: AppTab = .home

    var body: some View {
        TabView(selection: $selectedTab) {
            TransactionsView(store: store)
                .tabItem {
                    Label(AppTab.transactions.title, systemImage: AppTab.transactions.symbolName)
                }
                .tag(AppTab.transactions)

            DashboardView(
                overview: store.overview,
                assetOverview: store.assetOverview
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
