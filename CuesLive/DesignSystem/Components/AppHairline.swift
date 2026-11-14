import SwiftUI

/// Horizontal rule in the pane divider color, such as the line under the live window's
/// toolbar. Matches the weight of `AppResizableDivider`.
struct AppHairline: View {
    private static let thickness: CGFloat = 2

    var body: some View {
        Rectangle()
            .fill(AppColors.paneDivider)
            .frame(height: Self.thickness)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
