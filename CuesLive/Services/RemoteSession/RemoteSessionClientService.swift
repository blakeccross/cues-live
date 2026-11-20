import Foundation
import Network
import Observation

enum RemoteSessionClientPhase: Equatable {
    case idle
    case browsing
    case connecting
    case authenticating
    case connected
    case failed(String)

    var statusText: String? {
        switch self {
        case .idle:
            nil
        case .browsing:
            "Searching for hosts…"
        case .connecting:
            "Connecting…"
        case .authenticating:
            "Authenticating…"
        case .connected:
            "Connected"
        case .failed(let message):
            message
        }
    }
}

@MainActor
@Observable
final class RemoteSessionClientService {
    static let shared = RemoteSessionClientService()

    private(set) var phase: RemoteSessionClientPhase = .idle
    private(set) var discoveredPeers: [RemoteSessionPeer] = []
    private(set) var hostDisplayName: String?
    private(set) var snapshot: RemoteSessionSnapshot?
    private(set) var state: RemoteSessionState = .empty
    private(set) var lastError: String?

    var isConnected: Bool {
        if case .connected = phase { return true }
        return false
    }

    private var browser: NWBrowser?
    private var connection: NWConnection?
    private var reader: RemoteSessionConnectionReader?
    private var pendingPIN: String?
    private var authTimeoutTask: Task<Void, Never>?
    private var snapshotTimeoutTask: Task<Void, Never>?
    private var outboundQueue: [Data] = []
    private var isWriting = false

    private init() {}

    func startBrowsing() {
        stopBrowsing(keepConnection: true)
        phase = .browsing
        lastError = nil
        discoveredPeers = []

        let descriptor = NWBrowser.Descriptor.bonjourWithTXTRecord(
            type: RemoteSessionBonjour.serviceType,
            domain: nil
        )
        let parameters = RemoteSessionFraming.makeTCPParameters()
        let browser = NWBrowser(for: descriptor, using: parameters)
        browser.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleBrowserState(state)
            }
        }
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            Task { @MainActor in
                self?.handleBrowseResults(results)
            }
        }
        browser.start(queue: .main)
        self.browser = browser
    }

    func stopBrowsing(keepConnection: Bool = false) {
        browser?.cancel()
        browser = nil
        if !keepConnection, !isConnected {
            if case .browsing = phase {
                phase = .idle
            }
        }
    }

    func connect(to peer: RemoteSessionPeer, pin: String) {
        disconnect(clearSnapshot: false, resumeBrowsing: false)
        pendingPIN = pin
        hostDisplayName = peer.name
        phase = .connecting
        lastError = nil

        let parameters = RemoteSessionFraming.makeTCPParameters()
        let connection = NWConnection(to: peer.endpoint.endpoint, using: parameters)
        self.connection = connection

        let reader = RemoteSessionConnectionReader(
            onMessage: { [weak self] message in
                Task { @MainActor in
                    self?.handleMessage(message)
                }
            },
            onFailure: { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    // Keep the session up if one host frame fails to decode.
                    if self.isConnected, self.snapshot != nil {
                        self.lastError = "Ignored bad host frame: \(error.localizedDescription)"
                        return
                    }
                    let message: String
                    if let decoding = error as? DecodingError {
                        message = "Failed to read host data: \(String(describing: decoding))"
                    } else {
                        message = error.localizedDescription
                    }
                    self.fail(message)
                }
            }
        )
        self.reader = reader

        connection.stateUpdateHandler = { [weak self] state in
            Task { @MainActor in
                self?.handleConnectionState(state)
            }
        }
        connection.start(queue: .main)
        connection.receiveRemoteFrames(reader: reader) { [weak self] in
            Task { @MainActor in
                self?.handleDisconnect()
            }
        }

        authTimeoutTask?.cancel()
        authTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 15_000_000_000)
            guard let self, !Task.isCancelled else { return }
            if case .connecting = self.phase {
                self.fail("Timed out while connecting to the host.")
            } else if case .authenticating = self.phase {
                self.fail("Timed out waiting for the host to accept the password.")
            }
        }
    }

    func disconnect(clearSnapshot: Bool = true, resumeBrowsing: Bool = true) {
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = nil
        clearOutboundQueue()
        connection?.cancel()
        connection = nil
        reader = nil
        pendingPIN = nil
        if clearSnapshot {
            snapshot = nil
            state = .empty
            hostDisplayName = nil
        }
        if resumeBrowsing, browser != nil {
            phase = .browsing
        } else if resumeBrowsing {
            phase = .idle
        }
    }

    func send(_ command: RemoteSessionCommand) {
        guard isConnected else { return }
        applyOptimisticMixState(for: command)
        enqueueOutbound(.command(command))
    }

    /// Keep local fader/mute/solo UI in sync immediately. Without this, drag-end commits
    /// re-read stale host echo state and send the old volume back to the host.
    private func applyOptimisticMixState(for command: RemoteSessionCommand) {
        switch command {
        case .setGroupVolume(let groupID, let volume, _):
            var next = state
            if let groupID {
                next.groupVolumes[groupID.uuidString] = volume
            } else {
                next.ungroupedVolume = volume
            }
            state = next
        case .setGroupMuted(let groupID, let muted):
            var next = state
            if let groupID {
                if muted {
                    if !next.mutedGroupIDs.contains(groupID) {
                        next.mutedGroupIDs.append(groupID)
                    }
                } else {
                    next.mutedGroupIDs.removeAll { $0 == groupID }
                }
            } else {
                next.ungroupedIsMuted = muted
            }
            state = next
        case .setGroupSoloed(let groupID, let soloed):
            var next = state
            if let groupID {
                next.soloedGroupIDs.removeAll { $0 == groupID }
                if soloed {
                    next.soloedGroupIDs.append(groupID)
                }
            } else {
                next.ungroupedIsSoloed = soloed
            }
            state = next
        default:
            break
        }
    }

    private func enqueueOutbound(_ message: RemoteSessionMessage) {
        do {
            let data = try RemoteSessionFraming.encode(message)
            outboundQueue.append(data)
            pumpOutboundQueue()
        } catch {
            lastError = error.localizedDescription
        }
    }

    private func pumpOutboundQueue() {
        guard !isWriting else { return }
        guard let connection, connection.state == .ready else { return }
        guard !outboundQueue.isEmpty else { return }

        isWriting = true
        let data = outboundQueue.removeFirst()
        connection.send(
            content: data,
            contentContext: .defaultStream,
            isComplete: false,
            completion: .contentProcessed { [weak self] error in
                Task { @MainActor in
                    guard let self else { return }
                    self.isWriting = false
                    if let error {
                        self.lastError = error.localizedDescription
                        self.outboundQueue.removeAll()
                        return
                    }
                    self.pumpOutboundQueue()
                }
            }
        )
    }

    private func clearOutboundQueue() {
        outboundQueue.removeAll()
        isWriting = false
    }

    func reportLocalError(_ message: String) {
        lastError = message
        phase = .failed(message)
    }

    func clearFailure() {
        if case .failed = phase {
            lastError = nil
            phase = browser != nil ? .browsing : .idle
        }
    }

    private func handleBrowserState(_ state: NWBrowser.State) {
        switch state {
        case .ready:
            if !isConnected {
                phase = .browsing
            }
        case .failed(let error):
            lastError = error.localizedDescription
            if !isConnected {
                phase = .failed(error.localizedDescription)
            }
        case .cancelled:
            break
        default:
            break
        }
    }

    private func handleBrowseResults(_ results: Set<NWBrowser.Result>) {
        let settings = RemoteSessionSettingsStore.shared
        let localInstanceID = settings.instanceID

        discoveredPeers = results.compactMap { result in
            guard case .service(let name, _, _, _) = result.endpoint else { return nil }

            // Prefer the advertised instance ID so we never list this device as a join target.
            if case .bonjour(let txtRecord) = result.metadata,
               let peerInstanceID = txtRecord[RemoteSessionBonjour.instanceIDTXTKey],
               peerInstanceID == localInstanceID {
                return nil
            }

            return RemoteSessionPeer(
                id: String(describing: result.endpoint),
                name: name,
                endpoint: NWEndpointBox(endpoint: result.endpoint)
            )
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func handleConnectionState(_ state: NWConnection.State) {
        switch state {
        case .ready:
            phase = .authenticating
            sendAuthHandshake()
        case .waiting(let error):
            lastError = error.localizedDescription
        case .failed(let error):
            fail(error.localizedDescription)
        case .cancelled:
            handleDisconnect()
        default:
            break
        }
    }

    private func sendAuthHandshake() {
        let name = RemoteSessionSettingsStore.shared.displayName
        guard let connection, let pendingPIN else { return }
        // Single auth-first handshake; hello is informational after that.
        connection.sendRemoteMessage(.auth(pin: pendingPIN)) { [weak self] error in
            Task { @MainActor in
                if let error {
                    self?.fail(error.localizedDescription)
                    return
                }
                connection.sendRemoteMessage(.hello(
                    protocolVersion: RemoteSessionBonjour.protocolVersion,
                    displayName: name
                ))
            }
        }
    }

    private func handleMessage(_ message: RemoteSessionMessage) {
        switch message {
        case .hello(_, let name):
            hostDisplayName = name
        case .authResult(let success, let message):
            authTimeoutTask?.cancel()
            authTimeoutTask = nil
            if success {
                phase = .connected
                pendingPIN = nil
                stopBrowsing(keepConnection: true)
                startSnapshotTimeout()
            } else {
                fail(message ?? "Incorrect password")
            }
        case .snapshot(let snapshot):
            snapshotTimeoutTask?.cancel()
            snapshotTimeoutTask = nil
            self.snapshot = snapshot
            self.state = snapshot.state
            if case .connected = phase {
                break
            } else if case .authenticating = phase {
                phase = .connected
                authTimeoutTask?.cancel()
                authTimeoutTask = nil
                pendingPIN = nil
                stopBrowsing(keepConnection: true)
            }
        case .state(let state):
            // Ignore transport state until the setlist snapshot arrives.
            guard self.snapshot != nil else { break }
            self.state = state
        case .error(let message):
            fail(message)
        case .ping:
            connection?.sendRemoteMessage(.pong)
        case .pong, .auth, .command:
            break
        }
    }

    private func startSnapshotTimeout() {
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 12_000_000_000)
            guard let self, !Task.isCancelled else { return }
            guard self.isConnected, self.snapshot == nil else { return }
            self.fail("Timed out waiting for the host setlist. Confirm Remote Control is enabled on the host and try again.")
        }
    }

    private func fail(_ message: String) {
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = nil
        clearOutboundQueue()
        lastError = message
        phase = .failed(message)
        connection?.cancel()
        connection = nil
        reader = nil
        pendingPIN = nil
        snapshot = nil
        state = .empty
    }

    private func handleDisconnect() {
        authTimeoutTask?.cancel()
        authTimeoutTask = nil
        snapshotTimeoutTask?.cancel()
        snapshotTimeoutTask = nil
        clearOutboundQueue()
        let wasConnected = isConnected
        let wasHandshaking: Bool = {
            switch phase {
            case .connecting, .authenticating: return true
            default: return false
            }
        }()
        let wasWaitingForSnapshot = wasConnected && snapshot == nil
        connection = nil
        reader = nil
        pendingPIN = nil
        if wasWaitingForSnapshot {
            snapshot = nil
            state = .empty
            lastError = "Disconnected before the setlist arrived"
            phase = browser != nil ? .browsing : .failed("Disconnected before the setlist arrived")
        } else if wasConnected {
            snapshot = nil
            state = .empty
            lastError = "Disconnected from host"
            phase = browser != nil ? .browsing : .failed("Disconnected from host")
        } else if wasHandshaking {
            lastError = "Connection closed during authentication"
            phase = browser != nil ? .browsing : .failed("Connection closed during authentication")
        }
    }
}
