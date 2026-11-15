import SwiftUI

/// Plays a test signal on every output, or every output a group uses, together or in turn.
@MainActor
struct TestAllOutputsSheet: View {
    /// Destinations currently assigned to groups, used for the In Use scope.
    let routedDestinations: [OutputDestination]
    let deviceUID: String?
    let channelCount: Int

    @Environment(\.dismiss) private var dismiss

    @State private var plan = OutputTestPlan()
    @State private var tester = OutputChannelTestPlayer.shared

    private var destinations: [OutputDestination] {
        plan.destinations(channelCount: channelCount, routed: routedDestinations)
    }

    private var isRunning: Bool {
        tester.isTestingAllOutputs
    }

    var body: some View {
        AppSheetContainer {
            NavigationStack {
                Form {
                    optionsSection
                    if isRunning {
                        statusSection
                    }
                }
                .formStyle(.grouped)
                .navigationTitle("Test All Outputs")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar { toolbarContent }
            }
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 320)
        #endif
        .onChange(of: plan) { _, _ in
            if isRunning {
                start()
            }
        }
        .onDisappear {
            if tester.isTestingAllOutputs {
                tester.stop()
            }
        }
    }

    private var optionsSection: some View {
        Section {
            optionPicker("Outputs", selection: $plan.scope, options: OutputTestPlan.Scope.allCases) { $0.displayName }
            optionPicker("Signal", selection: $plan.signal, options: OutputTestPlan.Signal.allCases) { $0.displayName }
            optionPicker("Order", selection: $plan.timing, options: OutputTestPlan.Timing.allCases) { $0.displayName }
        } footer: {
            Text(summary)
        }
    }

    private var statusSection: some View {
        Section {
            LabeledContent("Now Testing") {
                Text(statusText)
                    .monospacedDigit()
            }
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .cancellationAction) {
            Button("Done") { dismiss() }
        }
        ToolbarItem(placement: .confirmationAction) {
            Button(isRunning ? "Stop" : "Start") {
                if isRunning {
                    tester.stop()
                } else {
                    start()
                }
            }
            .disabled(!isRunning && destinations.isEmpty)
        }
    }

    private func optionPicker<Option: Hashable & Identifiable>(
        _ title: String,
        selection: Binding<Option>,
        options: [Option],
        label: @escaping (Option) -> String
    ) -> some View {
        Picker(title, selection: selection) {
            ForEach(options) { option in
                Text(label(option)).tag(option)
            }
        }
        .pickerStyle(.menu)
    }

    private var statusText: String {
        switch plan.timing {
        case .simultaneous:
            let total = destinations.count
            let ready = tester.preparedOutputCount
            if ready == 0 {
                return "Starting…"
            }
            if ready < total {
                return "\(ready) of \(total) outputs"
            }
            return total == 1 ? "1 output" : "\(total) outputs"
        case .series:
            return tester.currentSeriesDestination?.name ?? "Starting…"
        }
    }

    private var summary: String {
        let count = destinations.count
        guard count > 0 else {
            return "No group is assigned to an output on this device."
        }
        let outputs = count == 1 ? "1 output" : "\(count) outputs"
        switch (plan.timing, plan.signal) {
        case (.series, .announce):
            return "Tests \(outputs). Each output announces its number in turn, then the run repeats until you stop it."
        case (.series, .noise):
            return "Tests \(outputs). Pink noise moves from output to output in turn, then the run repeats until you stop it."
        case (.simultaneous, .announce):
            return "Tests \(outputs). Every output announces its own number at the same time until you stop it."
        case (.simultaneous, .noise):
            return "Tests \(outputs). Pink noise plays on every output at the same time until you stop it."
        }
    }

    private func start() {
        tester.startAllOutputs(
            plan,
            destinations: destinations,
            deviceUID: deviceUID,
            channelCount: channelCount
        )
    }
}
