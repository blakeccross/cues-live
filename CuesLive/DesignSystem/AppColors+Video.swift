import SwiftUI

extension AppColors {
    /// Colors for the Video window and the video lane.
    enum Video {
        /// Behind and around the picture; projectors show this as no light.
        static let pictureBackground = AppPalette.black
        /// Status text drawn over the black picture area.
        static let statusText = AppPalette.lift5
        /// Thumbnail slot that has not been decoded yet.
        static let thumbnailPlaceholder = AppPalette.shade4
        /// Hairline between thumbnails in the lane.
        static let thumbnailSeparator = AppPalette.shade5
        static let laneBody = TrackGroupPalette.colors(forPaletteKey: TrackGroupPalette.Key.darkGray.rawValue).body
        static let laneHeader = TrackGroupPalette.colors(forPaletteKey: TrackGroupPalette.Key.darkGray.rawValue).header
    }
}
