import AppIntents
import Foundation

@available(iOS 17.0, macOS 15.0, *)
struct QuickEntryFromScreenshotIntent: AppIntent {
    static let title: LocalizedStringResource = "用截图记账"
    static let description = IntentDescription("识别截图里的金额，并在记账页生成一条待确认草稿。")
    static let openAppWhenRun = true

    @Parameter(
        title: "截图",
        description: "快捷指令里“截屏”动作输出的图片。",
        inputConnectionBehavior: .connectToPreviousIntentResult
    )
    var screenshot: IntentFile

    static var parameterSummary: some ParameterSummary {
        Summary("用 \(\.$screenshot) 记账")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let draft = try await ScreenshotOCRService.makeDraft(from: screenshot.data)
        try QuickEntryShortcutStore.savePendingDraft(draft)
        return .result(dialog: "已识别金额 \(MoneyFormat.yuan(draft.candidateAmount))，请在记账页确认后保存。")
    }
}

@available(iOS 17.0, macOS 15.0, *)
struct CountMoneyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuickEntryFromScreenshotIntent(),
            phrases: [
                "用 \(.applicationName) 截图记账",
                "用 \(.applicationName) 记账"
            ],
            shortTitle: "截图记账",
            systemImageName: "viewfinder"
        )
    }
}
