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

/// A middle ground between the original vivid palette and the softened colors.
enum ConditionPalette {
    static let soaked = adaptive(light: (0.33, 0.31, 0.68), dark: (0.52, 0.49, 0.88))
    static let muddy = adaptive(light: (0.12, 0.46, 0.82), dark: (0.31, 0.66, 0.95))
    static let hero = adaptive(light: (0.23, 0.64, 0.36), dark: (0.33, 0.78, 0.47))
    static let dry = adaptive(light: (0.83, 0.51, 0.10), dark: (0.94, 0.69, 0.20))
    static let dusty = adaptive(light: (0.83, 0.29, 0.23), dark: (0.96, 0.47, 0.38))

    private static func adaptive(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(uiColor: UIColor { traits in
            let rgb = traits.userInterfaceStyle == .dark ? dark : light
            return UIColor(red: rgb.0, green: rgb.1, blue: rgb.2, alpha: 1)
        })
    }
}
