import SwiftUI

/// The app's font tokens. Each wraps one of Apple's text styles, so text keeps following Dynamic
/// Type on iOS; the suffix names the emphasis (`Medium`, or `Emphasized` for the style's bold
/// weight). Change a token here to restyle every use of it. Dense editor, ruler, and mixer text
/// that is smaller than any text style uses `AppTypography.Compact`.
enum AppTypography {
    static let largeTitle = Font.largeTitle
    static let largeTitleEmphasized = Font.largeTitle.weight(.bold)

    /// Section and sheet titles.
    static let title = Font.title3.weight(.semibold)
    static let title3 = Font.title3

    static let headline = Font.headline

    static let body = Font.body
    static let bodyMedium = Font.body.weight(.medium)
    static let bodyEmphasized = Font.body.weight(.semibold)

    static let callout = Font.callout
    static let calloutMedium = Font.callout.weight(.medium)
    static let calloutEmphasized = Font.callout.weight(.semibold)

    static let subheadline = Font.subheadline
    static let subheadlineMedium = Font.subheadline.weight(.medium)
    static let subheadlineEmphasized = Font.subheadline.weight(.semibold)

    static let caption = Font.caption
    static let captionEmphasized = Font.caption.weight(.semibold)

    static let caption2 = Font.caption2
    static let caption2Emphasized = Font.caption2.weight(.semibold)
}

extension View {
    func appTitle() -> some View {
        font(AppTypography.title)
            .foregroundStyle(AppColors.textPrimary)
    }

    func appCaptionText() -> some View {
        font(AppTypography.caption)
            .foregroundStyle(AppColors.textSecondary)
    }
}
