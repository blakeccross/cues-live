import SwiftUI

/// An on/off icon control drawn like `AppIconButton`. Built on `Toggle`, so VoiceOver and
/// Full Keyboard Access report it as a toggle with its current state.
struct AppIconToggle: View {
    let title: String
    let systemImage: String
    let isOn: Bool
    var size: CGFloat = 44
    var isEnabled: Bool = true
    var tint: Color? = nil
    var iconScale: CGFloat = 0.38
    var flipsImageHorizontally: Bool = false
    /// Called when the user flips the toggle; the owner updates `isOn`.
    let action: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isOn }, set: { _ in action() })) {
            Label(title, systemImage: systemImage)
        }
        .toggleStyle(.button)
        .buttonStyle(AppIconButtonStyle(
            size: size,
            isOn: isOn,
            tint: tint,
            iconScale: iconScale,
            flipsImageHorizontally: flipsImageHorizontally
        ))
        .disabled(!isEnabled)
    }
}
