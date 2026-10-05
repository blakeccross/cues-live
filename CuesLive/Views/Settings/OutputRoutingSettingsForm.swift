import SwiftData
import SwiftUI

/// Shared audio output device, group routing, and LTC controls.
/// Used by the Manage Outputs sheet and the macOS Settings panes.
struct OutputRoutingSettingsForm: View {
    struct Sections: OptionSet {
        let rawValue: Int

        static let device = Sections(rawValue: 1 << 0)
        static let groupOutputs = Sections(rawValue: 1 << 1)
        static let timecode = Sections(rawValue: 1 << 2)
        static let footer = Sections(rawValue: 1 << 3)

        static let all: Sections = [.device, .groupOutputs, .timecode, .footer]
        static let audio: Sections = [.device, .groupOutputs, .footer]
        static let timecodeOnly: Sections = [.timecode]
    }

    @Environment(\.modelContext) private var modelContext

    @Query(sort: [SortDescriptor(\TrackGroup.sortOrder), SortDescriptor(\TrackGroup.name)])
    private var groups: [TrackGroup]

    var sections: Sections = .all
    var onRoutingChanged: (() -> Void)?

    @State private var devices: [AudioOutputDevice] = []
    @State private var selectedDeviceUID: String?
    @State private var channelCount = 2
    @State private var groupDestinations: [UUID: OutputDestination] = [:]
    @State private var ungroupedDestination: OutputDestination = .none
    @State private var timecodeEnabled = false
    @State private var timecodeMode: TimecodeMode = .resetPerSong
    @State private var timecodeStartingHour = 1
    @State private var timecodeFrameRate: TimecodeFrameRate = .fps30
    @State private var outputTester = OutputChannelTestPlayer.shared

    private var stereoDestinations: [OutputDestination] {
        OutputRoutingStore.destinations(for: channelCount).stereo
    }

    private var monoDestinations: [OutputDestination] {
        OutputRoutingStore.destinations(for: channelCount).mono
    }

    var body: some View {
        Form {
            if sections.contains(.device) {
                deviceSection
            }
            if sections.contains(.groupOutputs) {
                groupOutputsSection
            }
            if sections.contains(.timecode) {
                timecodeSection
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: loadState)
        .onDisappear {
            outputTester.stop()
        }
    }

    private var deviceSection: some View {
        Section {
            if devices.isEmpty {
                Text("No output devices found.")
                    .foregroundStyle(.secondary)
            } else {
                Picker("Output Device", selection: $selectedDeviceUID) {
                    ForEach(devices) { device in
                        Text(device.name).tag(Optional(device.id))
                    }
                }
                .onChange(of: selectedDeviceUID) { _, newValue in
                    applyDeviceSelection(newValue)
                }
            }
        } footer: {
            deviceFooter
        }
    }

    @ViewBuilder
    private var deviceFooter: some View {
        if !devices.isEmpty {
            Text("\(channelCount) output channels available.")
        }
        #if os(iOS)
        Text("On iOS, connect a multi-channel USB interface for additional outputs. Device selection follows the current audio route.")
        #endif
    }

    private var groupOutputsSection: some View {
        Section {
            ForEach(groups) { group in
                groupRouteRow(title: group.name, routeID: group.id)
            }
            groupRouteRow(title: "No Group", routeID: OutputRoutingStore.ungroupedRouteID)
        } header: {
            Text("Group Outputs")
        } footer: {
            if sections.contains(.footer) {
                Text("Assign each track group to a stereo pair or mono output channel on the selected device. Route the Timecode group to a dedicated mono output for lighting or video gear.")
            }
        }
    }

    private var timecodeSection: some View {
        Section {
            Toggle("Enable LTC", isOn: $timecodeEnabled)
                .onChange(of: timecodeEnabled) { _, _ in
                    persistTimecodeSettings()
                }

            if timecodeEnabled {
                Picker("Mode", selection: $timecodeMode) {
                    ForEach(TimecodeMode.allCases) { mode in
                        Text(mode.displayName).tag(mode)
                    }
                }
                #if os(macOS)
                .pickerStyle(.radioGroup)
                #endif
                .onChange(of: timecodeMode) { _, _ in
                    persistTimecodeSettings()
                }

                LabeledContent("Starting Hour") {
                    Stepper(value: $timecodeStartingHour, in: 0...23) {
                        Text(String(format: "%02d", timecodeStartingHour))
                            .monospacedDigit()
                    }
                    .fixedSize()
                }
                .onChange(of: timecodeStartingHour) { _, _ in
                    persistTimecodeSettings()
                }

                Picker("Frame Rate", selection: $timecodeFrameRate) {
                    ForEach(TimecodeFrameRate.allCases) { rate in
                        Text(rate.displayName).tag(rate)
                    }
                }
                .onChange(of: timecodeFrameRate) { _, _ in
                    persistTimecodeSettings()
                }
            }
        } header: {
            Text("Timecode")
        }
    }

    private func groupRouteRow(title: String, routeID: UUID) -> some View {
        LabeledContent(title) {
            HStack(spacing: 8) {
                destinationPicker(selection: binding(for: routeID), title: title)
                outputTestButton(routeID: routeID)
            }
        }
    }

    private func binding(for routeID: UUID) -> Binding<OutputDestination> {
        Binding(
            get: {
                if routeID == OutputRoutingStore.ungroupedRouteID {
                    return ungroupedDestination
                }
                return groupDestinations[routeID] ?? .defaultDestination
            },
            set: { newValue in
                if routeID == OutputRoutingStore.ungroupedRouteID {
                    ungroupedDestination = newValue
                } else {
                    groupDestinations[routeID] = newValue
                }
                OutputRoutingStore.setRoute(
                    newValue,
                    for: routeID,
                    deviceUID: selectedDeviceUID,
                    in: modelContext
                )
                scheduleRoutingChange()
                if outputTester.isTesting(routeID) {
                    if newValue == .none {
                        outputTester.stop()
                    } else {
                        outputTester.start(
                            routeID: routeID,
                            destination: newValue,
                            deviceUID: selectedDeviceUID,
                            channelCount: channelCount
                        )
                    }
                }
            }
        )
    }

    private func destination(for routeID: UUID) -> OutputDestination {
        if routeID == OutputRoutingStore.ungroupedRouteID {
            return ungroupedDestination
        }
        return groupDestinations[routeID] ?? .defaultDestination
    }

    private func outputTestButton(routeID: UUID) -> some View {
        let isTesting = outputTester.isTesting(routeID)
        return Button(isTesting ? "Stop" : "Test") {
            if isTesting {
                outputTester.stop()
            } else {
                outputTester.start(
                    routeID: routeID,
                    destination: destination(for: routeID),
                    deviceUID: selectedDeviceUID,
                    channelCount: channelCount
                )
            }
        }
        .buttonStyle(.bordered)
        .controlSize(.small)
        .fixedSize()
        .disabled(destination(for: routeID) == .none)
        .accessibilityLabel(isTesting ? "Stop output test" : "Test output")
        .help(isTesting ? "Stop the output test" : "Play this output's name until you stop it")
    }

    private func destinationPicker(
        selection: Binding<OutputDestination>,
        title: String
    ) -> some View {
        Picker("Destination", selection: selection) {
            Text("No Output").tag(OutputDestination.none)
            Section("Stereo") {
                ForEach(stereoDestinations) { destination in
                    Text(destination.displayLabel).tag(destination)
                }
            }
            Section("Mono") {
                ForEach(monoDestinations) { destination in
                    Text(destination.displayLabel).tag(destination)
                }
            }
        }
        .labelsHidden()
        .fixedSize()
        .accessibilityLabel("Destination for \(title)")
    }

    private func loadState() {
        OutputRoutingStore.ensureConfig(in: modelContext)
        TimecodeSettingsStore.ensureConfig(in: modelContext)
        TrackGroupStore.ensureDefaults(in: modelContext)
        _ = TimecodePlaybackSupport.resolveGroupID(in: modelContext)

        devices = AudioOutputDeviceService.availableDevices()
        let config = OutputRoutingStore.config(in: modelContext)

        if let uid = config.selectedDeviceUID, devices.contains(where: { $0.id == uid }) {
            selectedDeviceUID = uid
            channelCount = AudioOutputDeviceService.channelCount(for: uid)
            OutputRoutingStore.setSelectedDevice(uid: uid, in: modelContext)
        } else if let first = devices.first {
            selectedDeviceUID = first.id
            channelCount = first.channelCount
            OutputRoutingStore.setSelectedDevice(uid: first.id, in: modelContext)
        } else {
            selectedDeviceUID = nil
            channelCount = AudioOutputDeviceService.currentSystemChannelCount()
        }

        reloadDestinations()

        let timecode = TimecodeSettingsStore.settings(in: modelContext)
        timecodeEnabled = timecode.isEnabled
        timecodeMode = timecode.mode
        timecodeStartingHour = timecode.startingHour
        timecodeFrameRate = timecode.frameRate
    }

    private func persistTimecodeSettings() {
        TimecodeSettingsStore.save({ settings in
            settings.isEnabled = timecodeEnabled
            settings.mode = timecodeMode
            settings.startingHour = timecodeStartingHour
            settings.frameRate = timecodeFrameRate
        }, in: modelContext)
        scheduleRoutingChange()
    }

    private func applyDeviceSelection(_ uid: String?) {
        outputTester.stop()
        OutputRoutingStore.setSelectedDevice(uid: uid, in: modelContext)
        channelCount = AudioOutputDeviceService.channelCount(for: uid)
        reloadDestinations()

        scheduleRoutingChange {
            AudioEngineManager.shared.selectOutputDevice(uid: uid)
        }
    }

    private func reloadDestinations() {
        var loaded: [UUID: OutputDestination] = [:]
        for group in groups {
            loaded[group.id] = OutputRoutingStore.route(
                for: group.id,
                deviceUID: selectedDeviceUID,
                in: modelContext
            )
        }
        groupDestinations = loaded
        ungroupedDestination = OutputRoutingStore.ungroupedRoute(
            deviceUID: selectedDeviceUID,
            in: modelContext
        )
    }

    private func scheduleRoutingChange(_ preparation: (() -> Void)? = nil) {
        DispatchQueue.main.async {
            preparation?()
            onRoutingChanged?()
            NotificationCenter.default.post(name: .outputRoutingDidChange, object: nil)
        }
    }
}

extension Notification.Name {
    static let outputRoutingDidChange = Notification.Name("live.cues.outputRoutingDidChange")
}
