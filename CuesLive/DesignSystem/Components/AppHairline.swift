import SwiftUI

/// Horizontal rule in the pane divider color, such as the line under the live window's
/// toolbar. Matches the weight of `AppResizableDivider`.
struct AppHairline: View {
    var body: some View {
        Rectangle()
            .fill(AppColors.paneDivider)
            .frame(height: 2)
            .frame(maxWidth: .infinity)
            .accessibilityHidden(true)
    }
}
