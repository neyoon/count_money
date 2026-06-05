import SwiftUI
#if os(iOS)
import UIKit
#endif

struct AppShellView: View {
    private let tabBarHeight: CGFloat = 56
    private let bottomContentInset: CGFloat = 96
    private let pageSwipeMinimumDistance: CGFloat = 28
    private let pageSwipeCommitDistance: CGFloat = 84

    @State private var store = AppStore()
    @State private var selectedTab: AppTab = .home
    @State private var dragOffset: CGFloat = 0
    @State private var shortcutDraftPollingTask: Task<Void, Never>?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        shellContent
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

    @ViewBuilder
    private var shellContent: some View {
        #if os(macOS)
        macShell
        #else
        phoneShell
        #endif
    }

    private var phoneShell: some View {
        ZStack(alignment: .bottom) {
            AppColor.background
                .ignoresSafeArea()

            pageContent
                .ignoresSafeArea(edges: .bottom)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: bottomContentInset)
                }

            tabBarOverlay
        }
    }

    #if os(macOS)
    private var macShell: some View {
        NavigationSplitView {
            List {
                ForEach(AppTab.mainTabs, id: \.self) { tab in
                    Button {
                        selectedTab = tab
                    } label: {
                        Label(tab.title, systemImage: tab.symbolName)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .foregroundStyle(selectedTab == tab ? AppColor.primary : AppColor.ink)
                    }
                    .buttonStyle(.plain)
                    .listRowBackground(
                        selectedTab == tab ? AppColor.primary.opacity(0.12) : Color.clear
                    )
                }
            }
            .navigationTitle("Ledgerly")
            .frame(minWidth: 190)
        } detail: {
            tabView(for: selectedTab)
                .background(AppColor.background)
        }
        .navigationSplitViewStyle(.balanced)
    }
    #endif

    private var tabBarOverlay: some View {
        PlatformTabBar(selectedTab: $selectedTab)
            .frame(height: tabBarHeight)
            .ignoresSafeArea(edges: .bottom)
    }

    private var selectedTabIndex: Int {
        AppTab.mainTabs.firstIndex(of: selectedTab) ?? 0
    }

    private var pageContent: some View {
        GeometryReader { geometry in
            HStack(spacing: 0) {
                ForEach(AppTab.mainTabs, id: \.self) { tab in
                    tabView(for: tab)
                        .frame(width: geometry.size.width, height: geometry.size.height)
                        .clipped()
                }
            }
            .offset(x: -CGFloat(selectedTabIndex) * geometry.size.width + dragOffset)
            .animation(.snappy, value: selectedTab)
            .clipped()
            .contentShape(Rectangle())
            .simultaneousGesture(pageSwipeGesture, including: .gesture)
        }
    }

    private var pageSwipeGesture: some Gesture {
        DragGesture(minimumDistance: pageSwipeMinimumDistance)
            .onChanged { value in
                let width = value.translation.width
                let height = value.translation.height
                guard abs(width) > abs(height) else {
                    return
                }
                guard !isBlockedBoundarySwipe(width: width) else {
                    dragOffset = 0
                    return
                }

                dragOffset = width
            }
            .onEnded { value in
                let width = value.translation.width
                let height = value.translation.height
                guard !isBlockedBoundarySwipe(width: width) else {
                    resetDragOffset()
                    return
                }
                guard abs(width) > abs(height) * 1.4, abs(width) > pageSwipeCommitDistance else {
                    resetDragOffset()
                    return
                }
                if width < 0 {
                    moveToAdjacentTab(offset: 1)
                } else {
                    moveToAdjacentTab(offset: -1)
                }
            }
    }

    private func isBlockedBoundarySwipe(width: CGFloat) -> Bool {
        if selectedTabIndex == AppTab.mainTabs.startIndex, width > 0 {
            return true
        }
        if selectedTabIndex == AppTab.mainTabs.index(before: AppTab.mainTabs.endIndex), width < 0 {
            return true
        }
        return false
    }

    @ViewBuilder
    private func tabView(for tab: AppTab) -> some View {
        switch tab {
        case .transactions:
            TransactionsView(store: store, isActive: selectedTab == .transactions)
        case .home:
            DashboardView(store: store, isActive: selectedTab == .home)
        case .entry:
            EntryView(store: store, isActive: selectedTab == .entry)
        case .accounts:
            AccountsView(store: store, isActive: selectedTab == .accounts)
        case .settings:
            SettingsView(store: store)
        }
    }

    private func moveToAdjacentTab(offset: Int) {
        guard let index = AppTab.mainTabs.firstIndex(of: selectedTab) else {
            resetDragOffset()
            return
        }

        let nextIndex = index + offset
        guard AppTab.mainTabs.indices.contains(nextIndex) else {
            resetDragOffset()
            return
        }

        withAnimation(.snappy) {
            selectedTab = AppTab.mainTabs[nextIndex]
            dragOffset = 0
        }
    }

    private func resetDragOffset() {
        withAnimation(.snappy) {
            dragOffset = 0
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

#if os(iOS)
private struct PlatformTabBar: UIViewRepresentable {
    @Binding var selectedTab: AppTab

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedTab: $selectedTab)
    }

    func makeUIView(context: Context) -> UITabBar {
        let tabBar = UITabBar()
        tabBar.delegate = context.coordinator
        tabBar.items = AppTab.mainTabs.enumerated().map { index, tab in
            UITabBarItem(
                title: tab.title,
                image: UIImage(systemName: tab.symbolName),
                tag: index
            )
        }
        tabBar.tintColor = UIColor(AppColor.primary)
        tabBar.isTranslucent = true
        tabBar.backgroundColor = .clear
        let appearance = UITabBarAppearance()
        appearance.configureWithTransparentBackground()
        appearance.backgroundEffect = UIBlurEffect(style: .systemChromeMaterial)
        appearance.shadowColor = .separator
        tabBar.standardAppearance = appearance
        tabBar.scrollEdgeAppearance = appearance
        return tabBar
    }

    func updateUIView(_ tabBar: UITabBar, context: Context) {
        context.coordinator.selectedTab = $selectedTab
        tabBar.selectedItem = tabBar.items?[selectedIndex]
    }

    private var selectedIndex: Int {
        AppTab.mainTabs.firstIndex(of: selectedTab) ?? 0
    }

    final class Coordinator: NSObject, UITabBarDelegate {
        var selectedTab: Binding<AppTab>

        init(selectedTab: Binding<AppTab>) {
            self.selectedTab = selectedTab
        }

        func tabBar(_ tabBar: UITabBar, didSelect item: UITabBarItem) {
            guard AppTab.mainTabs.indices.contains(item.tag) else {
                return
            }
            withAnimation(.snappy) {
                selectedTab.wrappedValue = AppTab.mainTabs[item.tag]
            }
        }
    }
}
#else
private struct PlatformTabBar: View {
    @Binding var selectedTab: AppTab

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.mainTabs, id: \.self) { tab in
                Button {
                    withAnimation(.snappy) {
                        selectedTab = tab
                    }
                } label: {
                    Label(tab.title, systemImage: tab.symbolName)
                        .labelStyle(.iconOnly)
                        .frame(maxWidth: .infinity)
                        .overlay(alignment: .bottom) {
                            Text(tab.title)
                                .font(.caption2)
                                .offset(y: 14)
                        }
                        .foregroundStyle(selectedTab == tab ? AppColor.primary : AppColor.muted)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 8)
        .background(.bar)
        .overlay(alignment: .top) {
            Divider()
        }
    }
}
#endif

enum AppTab: Hashable {
    case home
    case entry
    case transactions
    case accounts
    case settings

    static let mainTabs: [AppTab] = [.transactions, .home, .entry, .accounts, .settings]

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
