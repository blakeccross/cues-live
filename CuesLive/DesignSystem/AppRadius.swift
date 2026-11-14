import CoreGraphics

/// Corner radii, smallest to largest. Draw rounded shapes with `style: .continuous` to match the system.
enum AppRadius {
    /// Compact chip buttons in track headers.
    static let chip: CGFloat = 3
    /// Color swatches and fader thumbs.
    static let xxs: CGFloat = 4
    /// Compact buttons and floating cards.
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
}
