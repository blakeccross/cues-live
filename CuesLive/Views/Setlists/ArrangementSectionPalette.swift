import SwiftUI

/// Rotating fill/accent pairs that give each arrangement section its own color in the live waveform.
enum ArrangementSectionPalette {
    /// Saturated section fills — clear section identity without overpowering the waveform.
    private static let pairs: [(background: Color, accent: Color)] = [
        (Color(.arrangementSection1Background), Color(.arrangementSection1Accent)),
        (Color(.arrangementSection2Background), Color(.arrangementSection2Accent)),
        (Color(.arrangementSection3Background), Color(.arrangementSection3Accent)),
        (Color(.arrangementSection4Background), Color(.arrangementSection4Accent)),
        (Color(.arrangementSection5Background), Color(.arrangementSection5Accent)),
        (Color(.arrangementSection6Background), Color(.arrangementSection6Accent)),
    ]

    static let backgroundFillOpacity: Double = 0.30
    static let backgroundCueFillOpacity: Double = 0.48

    static func colors(for index: Int) -> (background: Color, accent: Color) {
        pairs[index % pairs.count]
    }
}
