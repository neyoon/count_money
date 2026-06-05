import SwiftUI
#if os(iOS)
import UIKit
#endif

enum AppColor {
    #if os(iOS)
    static let background = Color(uiColor: .systemGroupedBackground)
    static let surface = Color(uiColor: .secondarySystemGroupedBackground)
    static let line = Color(uiColor: .separator)
    #else
    static let background = Color(nsColor: .windowBackgroundColor)
    static let surface = Color(nsColor: .controlBackgroundColor)
    static let line = Color(nsColor: .separatorColor)
    #endif

    static let ink = Color.primary
    static let muted = Color.secondary
    static let primary = Color(red: 0.12, green: 0.48, blue: 0.60)
    static let success = Color(red: 0.15, green: 0.57, blue: 0.38)
    static let warning = Color(red: 0.88, green: 0.53, blue: 0.18)
    static let danger = Color(red: 0.84, green: 0.22, blue: 0.22)
}

enum AppLayout {
    static let tabBarScrollableContentInset: CGFloat = 75
    static let historyPullDistance: CGFloat = 240
}

enum AppDateRange {
    static var history: ClosedRange<Date> {
        let calendar = Calendar.current
        let start = calendar.date(from: DateComponents(year: 1998, month: 1, day: 1)) ?? Date.distantPast
        let end = calendar.date(from: DateComponents(year: 2100, month: 12, day: 31)) ?? Date.distantFuture
        return start...end
    }
}

enum HistorySelectionPurpose {
    case view
    case compare

    var title: String {
        switch self {
        case .view:
            return "选择历史日期"
        case .compare:
            return "选择对比日期"
        }
    }
}

enum MoneyFormat {
    static func yuan(_ value: Decimal, signed: Bool = false) -> String {
        let number = NSDecimalNumber(decimal: value)
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CNY"
        formatter.currencySymbol = "¥"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 0

        let formatted = formatter.string(from: number) ?? "¥0"
        guard signed, value > 0 else { return formatted }
        return "+\(formatted)"
    }
}

struct SurfaceModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(16)
            .background(AppColor.surface)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(AppColor.line, lineWidth: 1)
            )
    }
}

extension View {
    func surface() -> some View {
        modifier(SurfaceModifier())
    }

    func tabBarScrollableContentInset() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: AppLayout.tabBarScrollableContentInset)
        }
    }

    func historyPull(enabled: Bool, onTrigger: @escaping () -> Void) -> some View {
        modifier(HistoryPullModifier(enabled: enabled, onTrigger: onTrigger))
    }

    @ViewBuilder
    func installKeyboardDismissGesture() -> some View {
        #if os(iOS)
        background(KeyboardDismissInstaller())
        #else
        self
        #endif
    }
}

private struct HistoryPullModifier: ViewModifier {
    var enabled: Bool
    var onTrigger: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    guard enabled else { return }
                    let width = abs(value.translation.width)
                    let height = value.translation.height
                    guard height > AppLayout.historyPullDistance, height > width * 1.6 else { return }
                    onTrigger()
                }
        )
    }
}

struct HistoryDateBanner: View {
    var date: Date
    var onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Label(Self.text(for: date), systemImage: "clock.arrow.circlepath")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(AppColor.primary)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.caption.weight(.semibold))
            }
            .buttonStyle(.plain)
            .foregroundStyle(AppColor.muted)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(AppColor.primary.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private static func text(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy 年 M 月 d 日历史"
        return formatter.string(from: date)
    }
}

struct HistoryActionButtons: View {
    var onSelectDate: () -> Void
    var onCompare: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Button(action: onSelectDate) {
                Label("选择日期", systemImage: "calendar")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColor.primary)

            Button(action: onCompare) {
                Label("对比", systemImage: "arrow.left.arrow.right")
                    .font(.subheadline.weight(.semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.bordered)
            .tint(AppColor.primary)
        }
        .padding(12)
        .background(AppColor.surface)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(AppColor.line, lineWidth: 1)
        )
    }
}

struct HistoryDatePickerSheet: View {
    var title: String
    @Binding var date: Date
    var onComplete: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            DatePicker(title, selection: $date, in: AppDateRange.history, displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle(title)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("取消") {
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("完成") {
                            onComplete()
                            dismiss()
                        }
                    }
                }
        }
        .presentationDetents([.large])
    }
}

struct HistoryComparisonSheet: View {
    var comparison: HistoryComparison
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(headline)
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(AppColor.ink)

                        Text("从 \(dateText(comparison.historical.date)) 到今天")
                            .font(.subheadline)
                            .foregroundStyle(AppColor.muted)
                    }
                    .surface()

                    VStack(spacing: 0) {
                        HistoryComparisonRow(title: "现金/余额", value: comparison.holdingsChange, color: AppColor.success)
                        Divider()
                        HistoryComparisonRow(title: "基金资产", value: comparison.fundChange, color: AppColor.success)
                        Divider()
                        HistoryComparisonRow(title: "债务变化", value: -comparison.debtChange, color: comparison.debtChange > 0 ? AppColor.danger : AppColor.success)
                    }
                    .surface()

                    if !comparison.assetChanges.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("变化最大的资产")
                                .font(.headline)
                                .foregroundStyle(AppColor.ink)

                            ForEach(comparison.assetChanges) { change in
                                HStack(spacing: 10) {
                                    Image(systemName: change.symbolName)
                                        .foregroundStyle(AppColor.primary)
                                        .frame(width: 30, height: 30)
                                        .background(AppColor.primary.opacity(0.12))
                                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                                    Text(change.name)
                                        .font(.subheadline.weight(.medium))

                                    Spacer()

                                    Text(MoneyFormat.yuan(change.change, signed: change.change > 0))
                                        .font(.subheadline.weight(.semibold))
                                        .foregroundStyle(change.change < 0 ? AppColor.danger : AppColor.success)
                                        .monospacedDigit()
                                }
                            }
                        }
                        .surface()
                    }
                }
                .padding()
            }
            .background(AppColor.background)
            .navigationTitle("历史对比")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("完成") {
                        dismiss()
                    }
                }
            }
        }
    }

    private var headline: String {
        let change = comparison.netChange
        if change == 0 {
            return "净资产基本持平"
        }
        return "净资产\(change > 0 ? "增加" : "减少") \(MoneyFormat.yuan(abs(change)))"
    }

    private func dateText(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy 年 M 月 d 日"
        return formatter.string(from: date)
    }
}

private struct HistoryComparisonRow: View {
    var title: String
    var value: Decimal
    var color: Color

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(AppColor.muted)

            Spacer()

            Text(MoneyFormat.yuan(value, signed: value > 0))
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(value < 0 ? AppColor.danger : color)
                .monospacedDigit()
        }
        .padding(.vertical, 10)
    }
}

#if os(iOS)
private struct KeyboardDismissInstaller: UIViewRepresentable {
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> UIView {
        let view = UIView(frame: .zero)
        view.isUserInteractionEnabled = false
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: view)
        }
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        DispatchQueue.main.async {
            context.coordinator.installIfNeeded(from: uiView)
        }
    }

    static func dismantleUIView(_ uiView: UIView, coordinator: Coordinator) {
        coordinator.uninstall()
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        private weak var window: UIWindow?
        private weak var recognizer: UITapGestureRecognizer?

        func installIfNeeded(from view: UIView) {
            guard recognizer == nil, let window = view.window else { return }

            let recognizer = UITapGestureRecognizer(target: self, action: #selector(dismissKeyboard))
            recognizer.cancelsTouchesInView = false
            recognizer.delegate = self
            window.addGestureRecognizer(recognizer)

            self.window = window
            self.recognizer = recognizer
        }

        func uninstall() {
            if let recognizer {
                window?.removeGestureRecognizer(recognizer)
            }
            recognizer = nil
            window = nil
        }

        @objc private func dismissKeyboard() {
            window?.endEditing(true)
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            var view: UIView? = touch.view
            while let current = view {
                if current is UITextField || current is UITextView {
                    return false
                }
                view = current.superview
            }
            return true
        }

        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }
    }
}
#endif
