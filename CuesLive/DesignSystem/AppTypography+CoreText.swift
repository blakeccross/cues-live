import CoreText
#if os(macOS)
import AppKit

private typealias PlatformFont = NSFont
#else
import UIKit

private typealias PlatformFont = UIFont
#endif

/// The compact fonts for text drawn with Core Text, such as clip names on the editor's lane
/// canvas and the rulers drawn during a live zoom. Each matches the SwiftUI font of the same name.
extension AppTypography.Compact {
    static let labelCTFont: CTFont = PlatformFont.systemFont(ofSize: labelSize, weight: .semibold) as CTFont
    static let timecodeCTFont: CTFont = PlatformFont.monospacedSystemFont(ofSize: 9, weight: .regular) as CTFont
    /// `rulerValue` with `.monospacedDigit()`.
    static let rulerValueCTFont: CTFont = {
        let base = PlatformFont.systemFont(ofSize: 9, weight: .semibold)
        let rounded = base.fontDescriptor.withDesign(.rounded) ?? base.fontDescriptor
        let digits = CTFontDescriptorCreateCopyWithFeature(
            rounded as CTFontDescriptor,
            NSNumber(value: kNumberSpacingType),
            NSNumber(value: kMonospacedNumbersSelector)
        )
        return CTFontCreateWithFontDescriptor(digits, 9, nil)
    }()
    static let sectionNameCTFont: CTFont = PlatformFont.systemFont(ofSize: 11, weight: .semibold) as CTFont
}
