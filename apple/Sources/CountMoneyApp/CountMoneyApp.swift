import SwiftUI

@main
struct CountMoneyApp: App {
    var body: some Scene {
        WindowGroup {
            AppShellView()
        }
        #if os(macOS)
        .defaultSize(width: 1120, height: 760)
        #endif
    }
}
