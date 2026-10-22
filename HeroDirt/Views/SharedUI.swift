import SwiftUI

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
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(disabled ? .disabled : .automatic)
        } else {
            self
        }
    }
}
