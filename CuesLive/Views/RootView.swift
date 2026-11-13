import SwiftData
import SwiftUI

struct RootView: View {
    @Bindable private var remoteClient = RemoteSessionClientService.shared
    @State private var showingDisconnectConfirm = false

    var body: some View {
        VStack(spacing: 0) {
            if remoteClient.isConnected {
                remoteConnectedStatusBanner
            }

            rootContent
        }
        .appBackground(.primary)
        .appLockToolbarDisplayMode()
        .alert("Disconnect?", isPresented: $showingDisconnectConfirm) {
            Button("Disconnect", role: .destructive) {
                remoteClient.disconnect()
                remoteClient.startBrowsing()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            let hostName = remoteClient.hostDisplayName
                ?? remoteClient.snapshot?.hostDisplayName
                ?? "the host"
            Text("Disconnect from \(hostName)?")
        }
        .onAppear {
            // Ensure host session bindings exist before any remote client connects.
            _ = RemoteHostSessionController.shared
            RemoteHostSessionController.shared.syncAdvertising()
            _ = InputMappingController.shared
        }
    }

    private var remoteConnectedStatusBanner: some View {
        let hostName = remoteClient.hostDisplayName
            ?? remoteClient.snapshot?.hostDisplayName
            ?? "Host"
        return Button {
            showingDisconnectConfirm = true
        } label: {
            Text("Connected to: \(hostName)")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
                .padding(.horizontal, AppSpacing.sm)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(AppColors.accent)
        // Fill the status-bar / Dynamic Island area without covering the nav toolbar.
        .background(alignment: .top) {
            AppColors.accent
                .ignoresSafeArea(edges: .top)
        }
        .accessibilityAddTraits(.isHeader)
        .accessibilityHint("Disconnect from remote session")
    }

    @ViewBuilder
    private var rootContent: some View {
        if remoteClient.isConnected {
            NavigationStack {
                if remoteClient.snapshot != nil {
                    RemoteLivePlaybackView()
                } else {
                    remoteSessionLoadingView
                }
            }
        } else if case .failed(let message) = remoteClient.phase {
            NavigationStack {
                remoteSessionErrorView(message: message)
            }
        } else {
            #if os(macOS)
            // Brings its own split view, which cannot sit inside a navigation stack.
            LivePlaybackView()
            #else
            NavigationStack {
                LivePlaybackView()
            }
            #endif
        }
    }

    private var remoteSessionLoadingView: some View {
        VStack(spacing: AppSpacing.md) {
            ProgressView()
            Text("Loading setlist from host…")
                .font(.callout)
                .foregroundStyle(AppColors.textSecondary)
            Text("This should only take a few seconds.")
                .font(.caption)
                .foregroundStyle(AppColors.textTertiary)
            if let host = remoteClient.hostDisplayName {
                Text(host)
                    .font(.caption)
                    .foregroundStyle(AppColors.textTertiary)
            }
            Button("Cancel") {
                remoteClient.disconnect()
                remoteClient.startBrowsing()
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Remote Session")
    }

    private func remoteSessionErrorView(message: String) -> some View {
        VStack(spacing: AppSpacing.md) {
            Image(systemName: "exclamationmark.triangle")
                .font(.largeTitle)
                .foregroundStyle(.yellow)
            Text("Remote Session Failed")
                .font(.headline)
            Text(message)
                .font(.callout)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("OK") {
                remoteClient.clearFailure()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .navigationTitle("Remote Session")
    }
}

#Preview {
    RootView()
        .modelContainer(for: [Song.self, AudioTrack.self, TrackGroup.self, OutputRoutingConfig.self, GroupOutputRoute.self, TimecodeSettings.self, Setlist.self, SetlistEntry.self], inMemory: true)
}
