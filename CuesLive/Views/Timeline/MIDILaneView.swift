import SwiftUI

struct MIDITrackHeaderView: View {
    @Bindable var track: MIDITrack
    let laneHeight: CGFloat
    let isSelected: Bool
    let onSelect: () -> Void
    let onConfigChange: () -> Void
    let onSendTest: () -> Void
    let onEditDevice: () -> Void
    let onDelete: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                Image(systemName: "pianokeys")
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)

                TextField("MIDI Track", text: $track.displayName)
                    .textFieldStyle(.plain)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(isSelected ? AppColors.textPrimary : AppColors.textSecondary)
                    .onSubmit { onConfigChange() }

                Button(role: .destructive, action: onDelete) {
                    Image(systemName: "trash")
                        .font(.system(size: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(AppColors.textTertiary)
            }

            Button(action: onEditDevice) {
                HStack(spacing: 4) {
                    Text(deviceLabel)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 8, weight: .semibold))
                }
                .font(.caption2)
                .foregroundStyle(track.device == nil ? AppColors.textTertiary : AppColors.textPrimary)
                .padding(.horizontal, 6)
                .padding(.vertical, 3)
                .background(Color.dawMixButtonBackground)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }
            .buttonStyle(.plain)

            HStack(spacing: 6) {
                Text(routingLabel)
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.textTertiary)
                    .lineLimit(1)

                Spacer(minLength: 0)

                Button(action: onSendTest) {
                    Text("Test")
                        .font(.system(size: 9, weight: .semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Color.dawMixButtonBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                }
                .buttonStyle(.plain)
                .disabled(!canSendTest)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .frame(width: TimelineLayout.trackHeaderWidth, height: laneHeight, alignment: .topLeading)
        .background {
            if isSelected {
                Rectangle()
                    .fill(Color.dawTrackHeaderSelected)
            }
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onSelect)
    }

    private var deviceLabel: String {
        track.device?.name ?? "No Device"
    }

    private var routingLabel: String {
        guard let device = track.device else { return "No device selected" }
        let destination = device.destinationName ?? "No destination"
        return "Ch \(device.midiChannel) • \(destination)"
    }

    private var canSendTest: Bool {
        guard let device = track.device else { return false }
        return device.destinationUniqueID != nil && !device.commands.isEmpty
    }
}

struct MIDILaneView: View {
    @Bindable var track: MIDITrack
    let device: MIDIDevice?
    let timelineDuration: TimeInterval
    let timelineContentWidth: CGFloat
    let laneHeight: CGFloat
    @Binding var events: [MIDIEvent]
    let tempoChanges: [TempoChange]
    let timeSignatureChanges: [TimeSignatureChange]
    let onCommit: () -> Void

    @State private var editingEventID: UUID?
    @State private var draggingEventID: UUID?
    @State private var dragPreviewTime: TimeInterval?

    private var trackColors: (header: Color, body: Color) {
        TrackGroupPalette.colors(forPaletteKey: nil)
    }

    private var safeDuration: TimeInterval {
        max(timelineDuration, 0.001)
    }

    private var trackEvents: [MIDIEvent] {
        events
            .filter { $0.trackID == track.id }
            .sorted { $0.timelineSeconds < $1.timelineSeconds }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: TimelineLayout.clipCornerRadius, style: .continuous)
                .fill(trackColors.body.opacity(0.35))
                .padding(.vertical, TimelineLayout.clipLaneInset)

            Color.clear
                .contentShape(Rectangle())
                .gesture(addEventGesture)

            ForEach(trackEvents) { event in
                eventMarker(event)
            }
        }
        .frame(width: timelineContentWidth, height: laneHeight)
        .background(trackColors.body.opacity(0.12))
        .sheet(isPresented: editorPresented) {
            if let id = editingEventID, let event = events.first(where: { $0.id == id }) {
                MIDIEventEditorView(
                    event: event,
                    device: device,
                    onSave: { updated in
                        if let index = events.firstIndex(where: { $0.id == updated.id }) {
                            events[index] = updated
                        }
                        onCommit()
                        editingEventID = nil
                    },
                    onDelete: {
                        events.removeAll { $0.id == id }
                        onCommit()
                        editingEventID = nil
                    }
                )
            }
        }
    }

    private var editorPresented: Binding<Bool> {
        Binding(
            get: { editingEventID != nil },
            set: { if !$0 { editingEventID = nil } }
        )
    }

    private var addEventGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onEnded { value in
                guard abs(value.translation.width) < 4, abs(value.translation.height) < 4 else { return }
                addEvent(atX: value.location.x)
            }
    }

    private func addEvent(atX x: CGFloat) {
        let raw = TimelineLayout.time(at: x, duration: safeDuration, contentWidth: timelineContentWidth)
        let snapped = MeasureTiming.snapToNearestBeat(
            raw,
            tempoChanges: tempoChanges,
            timeSignatureChanges: timeSignatureChanges
        )
        let firstCommand = device?.commands.first
        let event = MIDIEvent(
            trackID: track.id,
            timelineSeconds: max(0, snapped),
            commandID: firstCommand?.id ?? UUID(),
            label: firstCommand?.name ?? ""
        )
        events.append(event)
        onCommit()
        editingEventID = event.id
    }

    @ViewBuilder
    private func eventMarker(_ event: MIDIEvent) -> some View {
        let time = draggingEventID == event.id ? (dragPreviewTime ?? event.timelineSeconds) : event.timelineSeconds
        let x = TimelineLayout.xPosition(
            for: time,
            duration: safeDuration,
            contentWidth: timelineContentWidth
        )

        VStack(alignment: .leading, spacing: 0) {
            Text(flagText(event))
                .font(.system(size: 9, weight: .semibold))
                .lineLimit(1)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .foregroundStyle(.white)
                .background(trackColors.header)
                .clipShape(RoundedRectangle(cornerRadius: TimelineLayout.clipCornerRadius, style: .continuous))

            Rectangle()
                .fill(trackColors.header)
                .frame(width: 2)
                .frame(maxHeight: .infinity)
        }
        .frame(height: laneHeight, alignment: .top)
        .fixedSize(horizontal: true, vertical: false)
        .contentShape(Rectangle())
        .offset(x: x)
        .gesture(markerGesture(event))
    }

    private func flagText(_ event: MIDIEvent) -> String {
        if let command = device?.command(withID: event.commandID) {
            return command.name.isEmpty ? "Note \(command.note)" : command.name
        }
        return event.label.isEmpty ? "(no command)" : event.label
    }

    private func markerGesture(_ event: MIDIEvent) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                draggingEventID = event.id
                let secondsPerPixel = safeDuration / TimeInterval(max(timelineContentWidth, 1))
                let proposed = event.timelineSeconds + TimeInterval(value.translation.width) * secondsPerPixel
                let snapped = MeasureTiming.snapToNearestBeat(
                    proposed,
                    tempoChanges: tempoChanges,
                    timeSignatureChanges: timeSignatureChanges
                )
                dragPreviewTime = max(0, snapped)
            }
            .onEnded { value in
                defer {
                    draggingEventID = nil
                    dragPreviewTime = nil
                }
                if abs(value.translation.width) < 4 {
                    editingEventID = event.id
                    return
                }
                if let index = events.firstIndex(where: { $0.id == event.id }) {
                    events[index].timelineSeconds = dragPreviewTime ?? event.timelineSeconds
                    onCommit()
                }
            }
    }
}

struct MIDIEventEditorView: View {
    let event: MIDIEvent
    let device: MIDIDevice?
    let onSave: (MIDIEvent) -> Void
    let onDelete: () -> Void

    @Environment(\.dismiss) private var dismiss

    @State private var commandID: UUID

    init(
        event: MIDIEvent,
        device: MIDIDevice?,
        onSave: @escaping (MIDIEvent) -> Void,
        onDelete: @escaping () -> Void
    ) {
        self.event = event
        self.device = device
        self.onSave = onSave
        self.onDelete = onDelete
        _commandID = State(initialValue: event.commandID)
    }

    private var commands: [MIDICommand] {
        device?.commands ?? []
    }

    private var selectedCommand: MIDICommand? {
        commands.first { $0.id == commandID }
    }

    var body: some View {
        AppSheetContainer {
            VStack(spacing: 0) {
                Form {
                    Section("Command") {
                        if commands.isEmpty {
                            Text("This track's device has no commands. Edit the device to add commands.")
                                .font(.caption)
                                .foregroundStyle(AppColors.textTertiary)
                        } else {
                            Picker("Command", selection: $commandID) {
                                ForEach(commands) { command in
                                    Text(commandLabel(command)).tag(command.id)
                                }
                            }
                        }

                        if let selectedCommand {
                            LabeledContent("Note", value: "\(selectedCommand.note)")
                        }
                    }

                    Section {
                        LabeledContent("Time", value: formattedTime)
                        Button("Send Now") {
                            sendTest()
                        }
                        .disabled(!canSend)

                        Button("Delete Event", role: .destructive) {
                            onDelete()
                        }
                    }
                }
                .formStyle(.grouped)
                .scrollContentBackground(.hidden)

                HStack {
                    AppSecondaryButton(title: "Cancel") {
                        dismiss()
                    }
                    Spacer()
                    AppPrimaryButton(title: "Save", isEnabled: !commands.isEmpty) {
                        onSave(makeEvent())
                    }
                }
                .padding(AppSpacing.md)
            }
        }
        .frame(minWidth: 320, minHeight: 320)
    }

    private var canSend: Bool {
        guard let device, device.destinationUniqueID != nil, selectedCommand != nil else { return false }
        return true
    }

    private func commandLabel(_ command: MIDICommand) -> String {
        let name = command.name.isEmpty ? "Note \(command.note)" : command.name
        return "\(name) (note \(command.note))"
    }

    private var formattedTime: String {
        let totalSeconds = max(0, Int(event.timelineSeconds))
        let minutes = totalSeconds / 60
        let seconds = totalSeconds % 60
        let millis = Int((event.timelineSeconds - Double(totalSeconds)) * 1000)
        return String(format: "%d:%02d.%03d", minutes, seconds, millis)
    }

    private func makeEvent() -> MIDIEvent {
        MIDIEvent(
            id: event.id,
            trackID: event.trackID,
            timelineSeconds: event.timelineSeconds,
            commandID: commandID,
            label: selectedCommand?.name ?? event.label
        )
    }

    private func sendTest() {
        guard let device, let uniqueID = device.destinationUniqueID, let command = selectedCommand else { return }
        MIDIOutputService.shared.sendNoteTestNow(
            note: command.note,
            channel: device.midiChannel,
            toUniqueID: uniqueID
        )
    }
}
