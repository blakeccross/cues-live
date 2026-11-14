import SwiftUI

/// The app's spacing scale, smallest to largest: `xxxs` 2, `xxs` 4, `compact` 6, `xs` 8, `sm` 12,
/// `md` 16, `lg` 20, `xl` 24. Use these for stack spacing and padding; a one-off value that belongs to
/// a single component's geometry goes in that component's metrics as a named constant.
enum AppSpacing {
    /// Between stacked lines of one item, such as a title and its subtitle.
    static let xxxs: CGFloat = 2
    static let xxs: CGFloat = 4
    /// Between controls in dense editor UI: track headers, MIDI lanes, edit bars.
    static let compact: CGFloat = 6
    static let xs: CGFloat = 8
    static let sm: CGFloat = 12
    static let md: CGFloat = 16
    static let lg: CGFloat = 20
    static let xl: CGFloat = 24

    /// Padding inside a small text tag or badge. Apply it through `appTag` rather than directly.
    static let tagInsets = EdgeInsets(top: 2, leading: 5, bottom: 2, trailing: 5)
    /// Padding inside a compact chip button, such as a track header's group picker.
    static let chipInsets = EdgeInsets(top: 3, leading: 6, bottom: 3, trailing: 6)
    /// Between a glyph and its label inside a tag.
    static let tagGlyphGap: CGFloat = 3

    static let rowMinHeight: CGFloat = 52
}
