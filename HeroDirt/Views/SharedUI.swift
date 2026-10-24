import SwiftUI
import UIKit

extension Double {
    func formatMillimeters() -> String {
        self < 10 ? String(format: "%.1f", self) : String(format: "%.0f", self)
    }
}

extension CGFloat {
    static let cornerSmall: CGFloat = 6
    static let cornerMedium: CGFloat = 12
    static let cornerLarge: CGFloat = 16
}


extension View {
    /// Opts out of the iPhone Duo's vertical bar (navigation bar items in a
    /// column along the trailing edge). Used for the split-layout sidebar,
    /// where that column would eat a third of an already narrow pane.
    @ViewBuilder
    func verticalBarDisabled(_ disabled: Bool) -> some View {
        // Xcode 26's SwiftUI SDK has no declaration for this modifier.
        // A runtime availability check alone cannot hide it from that compiler.
        #if compiler(>=6.4)
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(disabled ? .disabled : .automatic)
        } else {
            self
        }
        #else
        self
        #endif
    }
}

/// Softer condition colors, with lighter variants that stay legible on dark cards.
enum ConditionPalette {
    static let soaked = adaptive(light: (0.38, 0.34, 0.61), dark: (0.66, 0.62, 0.86))
    static let muddy = adaptive(light: (0.23, 0.45, 0.64), dark: (0.55, 0.73, 0.90))
    static let hero = adaptive(light: (0.25, 0.49, 0.37), dark: (0.48, 0.74, 0.59))
    static let dry = adaptive(light: (0.65, 0.43, 0.19), dark: (0.87, 0.68, 0.40))
    static let dusty = adaptive(light: (0.65, 0.34, 0.27), dark: (0.91, 0.59, 0.48))

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}
