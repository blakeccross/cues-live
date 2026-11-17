#if os(macOS)
import AppKit
import CoreText

extension TimelineLiveRulerPainter {
    /// A meter or tempo row, as `TimelineTimeSignatureRulerView` and `TimelineTempoRulerView` draw
    /// it: each value clipped to its segment, then a dot where each segment starts.
    func drawValueRow(_ values: [Value], top: CGFloat, height: CGFloat, minimumLabelWidth: CGFloat, in context: CGContext) {
        let font = AppTypography.Compact.rulerValueCTFont
        let baseline = Self.baseline(centering: font, on: top + height / 2)
        for (index, value) in values.enumerated() {
            let startX = x(for: value.start)
            let endX = index + 1 == values.count ? displayWidth - offset : x(for: value.end)
            let width = max(0, endX - startX)
            guard width >= minimumLabelWidth, endX > 0, startX < viewportWidth else { continue }
            context.saveGState()
            context.clip(to: CGRect(x: startX, y: top, width: width, height: height))
            drawText(value.text, font: font, color: scene.valueColor, x: startX + RulerChangeDot.labelInset, baseline: baseline, in: context)
            context.restoreGState()
        }
        context.setFillColor(scene.changeMarkerColor)
        let diameter = RulerChangeDot.diameter
        for value in values {
            let x = x(for: value.start)
            guard x + diameter > 0, x - diameter < viewportWidth else { continue }
            context.fillEllipse(in: CGRect(x: x - diameter / 2, y: top + (height - diameter) / 2, width: diameter, height: diameter))
        }
        drawDivider(atBottomOf: top + height, in: context)
    }

    /// The section blocks, as `TimelineSectionMarkerRowView` draws them.
    func drawSectionRow(top: CGFloat, height: CGFloat, rect: CGRect, in context: CGContext) {
        let inset = TimelineSectionMarkerRowView.blockInset
        for section in scene.sections {
            let startX = x(for: section.start)
            // One point wider so neighbouring blocks share a single border line.
            let width = max(0, x(for: section.end) - startX) + 1
            guard startX < rect.maxX, startX + width > rect.minX else { continue }
            let block = CGRect(x: startX, y: top + inset, width: width, height: max(0, height - inset * 2))
            context.setFillColor(section.fillColor)
            context.fill(block)
            context.setStrokeColor(scene.blockBorderColor)
            context.setLineWidth(1)
            context.stroke(block.insetBy(dx: 0.5, dy: 0.5))
            context.saveGState()
            context.clip(to: block)
            drawBlockLabel(section, in: block, context: context)
            context.restoreGState()
        }
    }

    private func drawBlockLabel(_ section: Section, in block: CGRect, context: CGContext) {
        var x = block.minX + AppSpacing.tagInsets.leading
        if section.loops, let glyph = Self.loopGlyph(color: section.textColor) {
            let size = glyph.size
            let frame = CGRect(x: x, y: block.midY - size.height / 2, width: size.width, height: size.height)
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: true)
            glyph.draw(in: frame, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
            NSGraphicsContext.restoreGraphicsState()
            x += size.width + AppSpacing.tagGlyphGap
        }
        let name = section.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        let font = AppTypography.Compact.sectionNameCTFont
        drawText(name, font: font, color: section.textColor, x: x, baseline: Self.baseline(centering: font, on: block.midY), in: context)
    }

    /// The loop symbol at `AppTypography.Compact.glyphEmphasized`'s size and weight.
    private static func loopGlyph(color: CGColor) -> NSImage? {
        let configuration = NSImage.SymbolConfiguration(pointSize: 8, weight: .bold)
            .applying(NSImage.SymbolConfiguration(paletteColors: [NSColor(cgColor: color) ?? .labelColor]))
        return NSImage(systemSymbolName: "repeat", accessibilityDescription: nil)?
            .withSymbolConfiguration(configuration)
    }
}
#endif
