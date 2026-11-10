import SwiftData
import SwiftUI

/// Sheet shown when adding a MIDI track: pick an existing device or create a new one.
struct MIDIDevicePickerView: View {
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \MIDIDevice.name) private var devices: [MIDIDevice]
    let onSelect: (MIDIDevice) -> Void
    @State private var selectedDeviceID: UUID?

    var body: some View {
        NavigationStack {
            List(selection: $selectedDeviceID) {
                if !devices.isEmpty {
                    Section("Devices") {
                        ForEach(devices) { device in
                            deviceRow(device)
                                .tag(device.id)
                        }
                    }
                }

                Section {
                    NavigationLink {
                        MIDIDeviceEditorView(device: nil) { created in
                            onSelect(created)
                            dismiss()
                        }
                    } label: {
                        Label("Create New Device", systemImage: "plus")
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset)
            #else
            .listStyle(.insetGrouped)
            #endif
            .navigationTitle("Add MIDI Device")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .onChange(of: selectedDeviceID) { _, id in
                guard let id, let device = devices.first(where: { $0.id == id }) else { return }
                onSelect(device)
                dismiss()
            }
        }
        .formSheetFrame(minWidth: 420, minHeight: 460)
    }

    private func deviceRow(_ device: MIDIDevice) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(device.name)
            Text(subtitle(for: device))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func subtitle(for device: MIDIDevice) -> String {
        let commandText = "\(device.commands.count) command\(device.commands.count == 1 ? "" : "s")"
        let destinationText = device.destinationName ?? "No destination"
        return "\(commandText) • \(destinationText)"
    }
}

/// Create or edit a MIDI device: name, destination, channel, and named commands.
struct MIDIDeviceEditorView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    let device: MIDIDevice?
    let onSave: (MIDIDevice) -> Void

    @State private var name: String
    @State private var destinationUniqueID: Int32?
    @State private var destinationName: String?
    @State private var channel: Int
    @State private var commands: [MIDICommand]
    @State private var destinations: [MIDIOutputService.Destination] = []

    init(device: MIDIDevice?, onSave: @escaping (MIDIDevice) -> Void) {
        self.device = device
        self.onSave = onSave
        _name = State(initialValue: device?.name ?? "")
        _destinationUniqueID = State(initialValue: device?.destinationUniqueID)
        _destinationName = State(initialValue: device?.destinationName)
        _channel = State(initialValue: device?.midiChannel ?? 1)
        _commands = State(initialValue: device?.commands ?? [])
    }

    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Form {
            Section("Device") {
                TextField("Device Name", text: $name)
                destinationPicker
                channelPicker
            }

            Section {
                ForEach($commands) { $command in
                    TextField("Name", text: $command.name)
                    TextField("Note", value: $command.note, format: .number)
                        .onChange(of: command.note) { _, newValue in
                            command.note = min(127, max(0, newValue))
                        }
                }
                .onDelete { offsets in
                    commands.remove(atOffsets: offsets)
                }

                Button("Add Command", systemImage: "plus") {
                    commands.append(MIDICommand(name: "", note: 60))
                }
            } header: {
                Text("Commands")
            } footer: {
                Text("Add commands to trigger on this device. Each command is a named MIDI note.")
            }
        }
        .formStyle(.grouped)
        .navigationTitle(device == nil ? "New Device" : "Edit Device")
        #if os(iOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") { save() }
                    .disabled(!isValid)
            }
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
            }
        }
        .onAppear { destinations = MIDIOutputService.shared.availableDestinations() }
        .onReceive(NotificationCenter.default.publisher(for: MIDIOutputService.destinationsDidChangeNotification)) { _ in
            destinations = MIDIOutputService.shared.availableDestinations()
        }
    }

    private var destinationPicker: some View {
        Picker("Destination", selection: $destinationUniqueID) {
            Text("No Destination").tag(Optional<Int32>.none)
            ForEach(destinations) { destination in
                Text(destination.name).tag(Optional(destination.uniqueID))
            }
            // Keep a saved-but-currently-unreachable destination selectable
            // (e.g. device unplugged) instead of silently losing the selection.
            if let destinationUniqueID, !destinations.contains(where: { $0.uniqueID == destinationUniqueID }) {
                Text(destinationName ?? "Unavailable").tag(Optional(destinationUniqueID))
            }
        }
        .onChange(of: destinationUniqueID) { _, newValue in
            destinationName = destinations.first { $0.uniqueID == newValue }?.name
        }
    }

    private var channelPicker: some View {
        Picker("Channel", selection: $channel) {
            ForEach(1...16, id: \.self) { channel in
                Text("Channel \(channel)").tag(channel)
            }
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let target = device ?? MIDIDevice(name: trimmedName)
        target.name = trimmedName
        target.destinationUniqueID = destinationUniqueID
        target.destinationName = destinationName
        target.midiChannel = channel
        target.commands = commands

        if device == nil {
            modelContext.insert(target)
        }
        try? modelContext.save()

        onSave(target)
        dismiss()
    }
}

extension View {
    /// System form-sheet size, with a minimum for macOS 14.
    func formSheetFrame(minWidth: CGFloat, minHeight: CGFloat) -> some View {
        modifier(FormSheetFrame(minWidth: minWidth, minHeight: minHeight))
    }
}

private struct FormSheetFrame: ViewModifier {
    let minWidth: CGFloat
    let minHeight: CGFloat

    func body(content: Content) -> some View {
        let sized = content.frame(minWidth: minWidth, minHeight: minHeight)
        if #available(macOS 15.0, iOS 18.0, *) {
            sized.presentationSizing(.form)
        } else {
            sized
        }
    }
}
