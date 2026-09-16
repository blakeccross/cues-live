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

    static func route(for groupID: UUID, in context: ModelContext) -> OutputDestination {
        let routes = (try? context.fetch(FetchDescriptor<GroupOutputRoute>())) ?? []
        return routes.first(where: { $0.groupID == groupID })?.destination ?? .defaultDestination
    }

    static func ungroupedRoute(in context: ModelContext) -> OutputDestination {
        route(for: ungroupedRouteID, in: context)
    }

    static func setRoute(_ destination: OutputDestination, for groupID: UUID, in context: ModelContext) {
        let routes = (try? context.fetch(FetchDescriptor<GroupOutputRoute>())) ?? []
        if let existing = routes.first(where: { $0.groupID == groupID }) {
            existing.destination = destination
        } else {
            context.insert(GroupOutputRoute(groupID: groupID, destination: destination))
        }
        try? context.save()
    }

    static func setSelectedDevice(uid: String?, in context: ModelContext) {
        let config = config(in: context)
        config.selectedDeviceUID = uid
        try? context.save()
    }

    static func snapshot(in context: ModelContext, channelCount: Int) -> OutputRoutingSnapshot {
        let config = config(in: context)
        let routes = (try? context.fetch(FetchDescriptor<GroupOutputRoute>())) ?? []
        var routesByGroupID: [UUID: OutputDestination] = [:]
        for route in routes where route.groupID != ungroupedRouteID {
            routesByGroupID[route.groupID] = route.destination
        }

        return OutputRoutingSnapshot(
            deviceUID: config.selectedDeviceUID,
            routesByGroupID: routesByGroupID,
            ungroupedDestination: ungroupedRoute(in: context),
            channelCount: max(channelCount, 2)
        )
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
