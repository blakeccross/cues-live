import SwiftUI

struct RemoteSessionSettingsView: View {
    @Bindable private var settings = RemoteSessionSettingsStore.shared
    @Bindable private var host = RemoteSessionHostService.shared
    @Bindable private var client = RemoteSessionClientService.shared
    private let hostSession = RemoteHostSessionController.shared

    @State private var pinDraft = ""
    @State private var selectedPeer: RemoteSessionPeer?
    @State private var showingPINPrompt = false

    var body: some View {
        Form {
            hostSection
            joinSection
        }
        .formStyle(.grouped)
        .onAppear {
            hostSession.syncAdvertising()
            if case .idle = client.phase {
                client.startBrowsing()
            }
        }
        .onDisappear {
            if !client.isConnected {
                client.stopBrowsing()
            }
        }
        .onChange(of: settings.isHostingEnabled) { _, _ in
            hostSession.syncAdvertising()
        }
        .onChange(of: settings.pin) { _, _ in
            hostSession.syncAdvertising()
        }
        .onChange(of: settings.displayName) { _, _ in
            hostSession.syncAdvertising()
        }
        .alert("Enter Password", isPresented: $showingPINPrompt) {
            TextField("4-digit password", text: $pinDraft)
                #if os(iOS)
                .keyboardType(.numberPad)
                #endif
            Button("Connect") {
                // Defer so iOS commits the alert TextField into `pinDraft` first.
                DispatchQueue.main.async {
                    connectWithPIN()
                }
            }
            Button("Cancel", role: .cancel) {
                selectedPeer = nil
                pinDraft = ""
            }
        } message: {
            if let selectedPeer {
                Text("Enter the password shown on \(selectedPeer.name).")
            } else {
                Text("Enter the host password.")
            }
        }
    }

    private var hostSection: some View {
        Section {
            Toggle("Allow Remote Control", isOn: Binding(
                get: { settings.isHostingEnabled },
                set: { enabled in
                    hostSession.setHostingEnabled(enabled)
                }
            ))

            TextField("Device Name", text: $settings.displayName)

            LabeledContent("Password") {
                HStack(spacing: 8) {
                    Text(settings.pin)
                        .font(.body.monospaced())
                        .textSelection(.enabled)
                    Button("Regenerate") {
                        settings.regeneratePIN()
                    }
                    .controlSize(.small)
                    .disabled(!settings.isHostingEnabled)
                }
            }

            if settings.isHostingEnabled {
                LabeledContent("Status") {
                    Text(hostStatus)
                        .foregroundStyle(.secondary)
                }
                if host.isClientConnected {
                    Button("Disconnect Client", role: .destructive) {
                        hostSession.disconnectClient()
                    }
                }
            }
        } header: {
            Text("Host")
        }
    }

    private var hostStatus: String {
        if host.isClientAuthenticated {
            if let name = host.connectedClientName {
                return "Connected · \(name)"
            }
            return "Connected"
        }
        return host.statusMessage ?? "Advertising on local network"
    }

    private var joinSection: some View {
        Section {
            if client.isConnected {
                LabeledContent("Status") {
                    Text("Connected to \(client.hostDisplayName ?? "host")")
                        .foregroundStyle(.secondary)
                }
                if client.snapshot == nil {
                    Text("Waiting for setlist from host…")
                        .foregroundStyle(.secondary)
                }
                Button("Disconnect", role: .destructive) {
                    client.disconnect()
                    client.startBrowsing()
                }
            } else {
                if let status = client.phase.statusText,
                   client.phase != .browsing,
                   client.phase != .idle {
                    LabeledContent("Status") {
                        Text(status)
                            .foregroundStyle(.secondary)
                    }
                }

                if let lastError = client.lastError {
                    Text(lastError)
                        .foregroundStyle(.red)
                }

                switch client.phase {
                case .connecting, .authenticating:
                    ProgressView()
                    Button("Cancel") {
                        client.disconnect()
                        client.startBrowsing()
                    }
                default:
                    if client.discoveredPeers.isEmpty {
                        Text("Searching for hosts on this network…")
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(client.discoveredPeers) { peer in
                            Button(peer.name) {
                                selectedPeer = peer
                                pinDraft = ""
                                showingPINPrompt = true
                            }
                        }
                    }

                    Button("Refresh") {
                        client.startBrowsing()
                    }
                }
            }
        } header: {
            Text("Join")
        }
    }

    private func connectWithPIN() {
        guard let selectedPeer else { return }
        let pin = pinDraft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard RemoteSessionSettingsStore.isValidPIN(pin) else {
            client.reportLocalError("Enter the \(RemoteSessionBonjour.pinLength)-digit password")
            return
        }
        client.connect(to: selectedPeer, pin: pin)
        self.selectedPeer = nil
        pinDraft = ""
    }
}
