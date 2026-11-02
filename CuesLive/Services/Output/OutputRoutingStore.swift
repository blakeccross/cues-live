import Foundation
import SwiftData

struct OutputRoutingSnapshot {
    let deviceUID: String?
    let routesByGroupID: [UUID: OutputDestination]
    let ungroupedDestination: OutputDestination
    let channelCount: Int

    /// True when any group (or the ungrouped bus) is routed somewhere other than
    /// the default full stereo pair — e.g. pinned to a single mono channel. On a
    /// stereo-only device this signals that AU channel-map routing is needed
    /// instead of the plain master-mixer path, so that routing is honored.
    var hasNonDefaultRouting: Bool {
        if ungroupedDestination != .defaultDestination { return true }
        return routesByGroupID.values.contains { $0 != .defaultDestination }
    }
}

enum OutputRoutingStore {
    static let ungroupedRouteID = UUID(uuidString: "00000000-0000-0000-0000-000000000001")!

    static func ensureConfig(in context: ModelContext) {
        let existing = (try? context.fetch(FetchDescriptor<OutputRoutingConfig>())) ?? []
        guard existing.isEmpty else { return }
        context.insert(OutputRoutingConfig())
        try? context.save()
    }

    static func config(in context: ModelContext) -> OutputRoutingConfig {
        ensureConfig(in: context)
        if let existing = (try? context.fetch(FetchDescriptor<OutputRoutingConfig>()))?.first {
            return existing
        }
        let created = OutputRoutingConfig()
        context.insert(created)
        try? context.save()
        return created
    }

    static func destinations(for channelCount: Int) -> (stereo: [OutputDestination], mono: [OutputDestination]) {
        let safeCount = max(channelCount, 2)
        var stereo: [OutputDestination] = []
        var start = 1
        while start + 1 <= safeCount {
            stereo.append(.stereoPair(startChannel: start))
            start += 2
        }
        if stereo.isEmpty {
            stereo = [.stereoPair(startChannel: 1)]
        }

        let mono = (1...safeCount).map { OutputDestination.mono(channel: $0) }
        return (stereo, mono)
    }

    static func route(for groupID: UUID, deviceUID: String?, in context: ModelContext) -> OutputDestination {
        let key = deviceKey(deviceUID)
        let routes = (try? context.fetch(FetchDescriptor<GroupOutputRoute>())) ?? []
        let fallback: OutputDestination = groupID == ungroupedRouteID ? .none : .defaultDestination
        return routes.first { $0.groupID == groupID && $0.deviceUID == key }?.destination ?? fallback
    }

    static func ungroupedRoute(deviceUID: String?, in context: ModelContext) -> OutputDestination {
        route(for: ungroupedRouteID, deviceUID: deviceUID, in: context)
    }

    static func setRoute(
        _ destination: OutputDestination,
        for groupID: UUID,
        deviceUID: String?,
        in context: ModelContext
    ) {
        let key = deviceKey(deviceUID)
        let routes = (try? context.fetch(FetchDescriptor<GroupOutputRoute>())) ?? []
        if let existing = routes.first(where: { $0.groupID == groupID && $0.deviceUID == key }) {
            existing.destination = destination
        } else {
            context.insert(GroupOutputRoute(groupID: groupID, deviceUID: key, destination: destination))
        }
        try? context.save()
    }

    static func setSelectedDevice(uid: String?, in context: ModelContext) {
        let config = config(in: context)
        let previous = config.selectedDeviceUID
        // Routes saved before per-device memory belong to the device already in
        // use. If none was stored yet, they belong to the device being selected.
        let legacyOwner = (previous?.isEmpty == false) ? previous : uid
        claimLegacyRoutes(for: legacyOwner, in: context)
        config.selectedDeviceUID = uid
        try? context.save()
    }

    static func snapshot(in context: ModelContext, channelCount: Int) -> OutputRoutingSnapshot {
        let config = config(in: context)
        claimLegacyRoutes(for: config.selectedDeviceUID, in: context)
        let key = deviceKey(config.selectedDeviceUID)
        let routes = (try? context.fetch(FetchDescriptor<GroupOutputRoute>())) ?? []
        var routesByGroupID: [UUID: OutputDestination] = [:]
        for route in routes where route.groupID != ungroupedRouteID && route.deviceUID == key {
            routesByGroupID[route.groupID] = route.destination
        }

        return OutputRoutingSnapshot(
            deviceUID: config.selectedDeviceUID,
            routesByGroupID: routesByGroupID,
            ungroupedDestination: ungroupedRoute(deviceUID: config.selectedDeviceUID, in: context),
            channelCount: max(channelCount, 2)
        )
    }

    private static func deviceKey(_ uid: String?) -> String {
        uid ?? ""
    }

    /// Assigns routes that predate per-device memory to one device.
    private static func claimLegacyRoutes(for deviceUID: String?, in context: ModelContext) {
        let key = deviceKey(deviceUID)
        guard !key.isEmpty else { return }
        let routes = (try? context.fetch(FetchDescriptor<GroupOutputRoute>())) ?? []
        var claimed = false
        for route in routes where route.deviceUID.isEmpty {
            route.deviceUID = key
            claimed = true
        }
        if claimed {
            try? context.save()
        }
    }

    static func destination(
        for groupID: UUID?,
        snapshot: OutputRoutingSnapshot
    ) -> OutputDestination {
        guard let groupID else {
            return snapshot.ungroupedDestination
        }
        return snapshot.routesByGroupID[groupID] ?? .defaultDestination
    }
}
