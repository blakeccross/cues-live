import Foundation

enum InputMappingSession: Equatable {
    case idle
    case keyMapping
    case midiMapping
}

@MainActor
@Observable
final class InputMappingController {
    static let shared = InputMappingController()

    private(set) var session: InputMappingSession = .idle
    private(set) var pendingAction: MappableLiveAction?
    private(set) var statusMessage: String?

    /// True while any view has an input mapping session open.
    var isLiveSessionActive: Bool { !liveSessions.isEmpty }

    let store: InputMappingStore

    var isMapping: Bool { session != .idle }

    var showsLiveHighlights: Bool {
        isMapping && isLiveSessionActive
    }

    func liveAssignmentBadge(for action: MappableLiveAction) -> String? {
        guard let record = store.mapping(for: action) else { return nil }
        switch session {
        case .keyMapping:
            return record.key?.displayName
        case .midiMapping:
            return record.midi?.compactDisplayName
        case .idle:
            return nil
        }
    }

    /// Open sessions, oldest first. Only the newest receives actions, so an editor pushed
    /// over the live setlist takes over, and the setlist gets them back when it closes.
    private var liveSessions: [LiveSession] = []
    private var statusClearTask: Task<Void, Never>?
    private(set) var endsSessionAfterAssign = false

    init(store: InputMappingStore? = nil, bindsHardware: Bool = true) {
        self.store = store ?? .shared
        guard bindsHardware else { return }
        MIDIInputService.shared.onNoteOn = { [weak self] binding in
            self?.handleMIDI(binding)
        }
        MIDIInputService.shared.start()
        KeyboardInputMonitor.shared.onKeyDown = { [weak self] binding in
            self?.handleKey(binding) ?? false
        }
        KeyboardInputMonitor.shared.start()
    }

    @discardableResult
    func activateLiveSession(
        playbackActionsEnabled: Bool = true,
        handler: @escaping (MappableLiveAction) -> Void
    ) -> UUID {
        let token = UUID()
        liveSessions.append(
            LiveSession(token: token, handler: handler, arePlaybackActionsEnabled: playbackActionsEnabled)
        )
        return token
    }

    func setPlaybackActionsEnabled(_ enabled: Bool, token: UUID) {
        guard let index = liveSessions.firstIndex(where: { $0.token == token }) else { return }
        liveSessions[index].arePlaybackActionsEnabled = enabled
    }

    func deactivateLiveSession(token: UUID) {
        guard let index = liveSessions.firstIndex(where: { $0.token == token }) else { return }
        liveSessions.remove(at: index)
        if !endsSessionAfterAssign {
            endMapping()
        }
    }

    func beginKeyMapping(endsAfterAssign: Bool = false) {
        session = .keyMapping
        endsSessionAfterAssign = endsAfterAssign
        if !endsAfterAssign {
            pendingAction = nil
        }
        clearStatus()
    }

    func beginMIDIMapping(endsAfterAssign: Bool = false) {
        session = .midiMapping
        endsSessionAfterAssign = endsAfterAssign
        if !endsAfterAssign {
            pendingAction = nil
        }
        clearStatus()
    }

    func toggleKeyMapping() {
        if session == .keyMapping {
            endMapping()
        } else {
            beginKeyMapping()
        }
    }

    func toggleMIDIMapping() {
        if session == .midiMapping {
            endMapping()
        } else {
            beginMIDIMapping()
        }
    }

    func endMapping() {
        session = .idle
        pendingAction = nil
        endsSessionAfterAssign = false
        clearStatus()
    }

    func selectAction(_ action: MappableLiveAction) {
        guard isMapping else { return }
        if pendingAction == action {
            pendingAction = nil
            clearStatus()
            return
        }
        pendingAction = action
        clearStatus()
    }

    func startSettingsLearn(action: MappableLiveAction, session: InputMappingSession) {
        pendingAction = action
        endsSessionAfterAssign = true
        self.session = session
        clearStatus()
    }

    @discardableResult
    func handleKey(_ binding: KeyBinding) -> Bool {
        if binding.isEscape {
            return handleEscape()
        }
        if binding.isReserved {
            return false
        }

        switch session {
        case .keyMapping:
            guard let pendingAction else { return false }
            assignKey(binding, to: pendingAction)
            return true
        case .midiMapping:
            return false
        case .idle:
            guard let session = activeLiveSession,
                  let action = store.action(forKey: binding) else {
                return false
            }
            session.handler(action)
            return true
        }
    }

    func handleMIDI(_ binding: MIDINoteBinding) {
        switch session {
        case .midiMapping:
            guard let pendingAction else { return }
            assignMIDI(binding, to: pendingAction)
        case .keyMapping:
            return
        case .idle:
            guard let session = activeLiveSession,
                  let action = store.action(forMIDI: binding) else {
                return
            }
            session.handler(action)
        }
    }

    var sessionTitle: String {
        switch session {
        case .keyMapping: "Key Mapping"
        case .midiMapping: "MIDI Mapping"
        case .idle: "Mapping"
        }
    }

    /// The newest session, when it currently accepts playback actions.
    private var activeLiveSession: LiveSession? {
        guard let session = liveSessions.last, session.arePlaybackActionsEnabled else { return nil }
        return session
    }

    private func assignKey(_ binding: KeyBinding, to action: MappableLiveAction) {
        store.assignKey(binding, to: action)
        finishAssign(action: action, label: binding.displayName)
    }

    private func assignMIDI(_ binding: MIDINoteBinding, to action: MappableLiveAction) {
        store.assignMIDI(binding, to: action)
        finishAssign(action: action, label: binding.displayName)
    }

    private func finishAssign(action: MappableLiveAction, label: String) {
        pendingAction = nil
        if endsSessionAfterAssign {
            endMapping()
        } else {
            showStatus("\(action.title) → \(label)")
        }
    }

    private func handleEscape() -> Bool {
        guard session != .idle else { return false }
        if pendingAction != nil {
            pendingAction = nil
            clearStatus()
        } else {
            endMapping()
        }
        return true
    }

    private func showStatus(_ message: String) {
        statusMessage = message
        statusClearTask?.cancel()
        statusClearTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            if statusMessage == message {
                statusMessage = nil
            }
        }
    }

    private func clearStatus() {
        statusClearTask?.cancel()
        statusMessage = nil
    }
}

private struct LiveSession {
    let token: UUID
    let handler: (MappableLiveAction) -> Void
    var arePlaybackActionsEnabled: Bool
}
