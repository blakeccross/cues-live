import SwiftUI

/// Segmented control that fills its width with equal segments on both platforms.
/// SwiftUI's segmented `Picker` hugs its content on macOS, so macOS uses `NSSegmentedControl`.
struct AppSegmentedPicker<Value: Hashable>: View {
    let title: String
    let options: [(title: String, value: Value)]
    @Binding var selection: Value

    var body: some View {
        #if os(macOS)
        FillingSegmentedControl(
            segmentTitles: options.map(\.title),
            selectedIndex: Binding(
                get: { options.firstIndex { $0.value == selection } ?? -1 },
                set: { index in
                    guard options.indices.contains(index) else { return }
                    selection = options[index].value
                }
            )
        )
        .frame(maxWidth: .infinity)
        .accessibilityLabel(title)
        #else
        Picker(title, selection: $selection) {
            ForEach(options, id: \.value) { option in
                Text(option.title).tag(option.value)
            }
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        #endif
    }
}

#if os(macOS)
private struct FillingSegmentedControl: NSViewRepresentable {
    let segmentTitles: [String]
    @Binding var selectedIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(selectedIndex: $selectedIndex)
    }

    func makeNSView(context: Context) -> NSSegmentedControl {
        let control = NSSegmentedControl(
            labels: segmentTitles,
            trackingMode: .selectOne,
            target: context.coordinator,
            action: #selector(Coordinator.selectionChanged(_:))
        )
        control.segmentDistribution = .fillEqually
        control.setContentHuggingPriority(.defaultLow, for: .horizontal)
        control.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return control
    }

    func updateNSView(_ control: NSSegmentedControl, context: Context) {
        context.coordinator.selectedIndex = $selectedIndex
        if control.segmentCount != segmentTitles.count {
            control.segmentCount = segmentTitles.count
        }
        for (index, title) in segmentTitles.enumerated() where control.label(forSegment: index) != title {
            control.setLabel(title, forSegment: index)
        }
        if control.selectedSegment != selectedIndex {
            control.selectedSegment = selectedIndex
        }
    }

    @MainActor
    final class Coordinator: NSObject {
        var selectedIndex: Binding<Int>

        init(selectedIndex: Binding<Int>) {
            self.selectedIndex = selectedIndex
        }

        @objc func selectionChanged(_ sender: NSSegmentedControl) {
            selectedIndex.wrappedValue = sender.selectedSegment
        }
    }
}
#endif
