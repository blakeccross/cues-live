import SwiftUI

extension AppColors {
    /// Colors for the Video window and the video lane.
    enum Video {
        /// Behind and around the picture; projectors show this as no light.
        static let pictureBackground = Color.black
        /// Status text drawn over the black picture area.
        static let statusText = Color.white.opacity(0.55)
        /// Thumbnail slot that has not been decoded yet.
        static let thumbnailPlaceholder = Color.black.opacity(0.35)
        /// Hairline between thumbnails in the lane.
        static let thumbnailSeparator = Color.black.opacity(0.6)
        static let laneBody = TrackGroupPalette.colors(forPaletteKey: TrackGroupPalette.Key.darkGray.rawValue).body
        static let laneHeader = TrackGroupPalette.colors(forPaletteKey: TrackGroupPalette.Key.darkGray.rawValue).header
    }
}
