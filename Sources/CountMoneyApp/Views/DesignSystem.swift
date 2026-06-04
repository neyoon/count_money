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

    @ViewBuilder
    func installKeyboardDismissGesture() -> some View {
        #if os(iOS)
        background(KeyboardDismissInstaller())
        #else
        self
        #endif
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
