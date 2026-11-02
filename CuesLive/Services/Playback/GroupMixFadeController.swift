import Foundation
import Observation
import SwiftData

/// Ramps all group faders except Click and Timecode (plus No Group) between their levels and silence.
@MainActor
@Observable
final class GroupMixFadeController {
    static let duration: TimeInterval = 5
    private static let stepInterval: TimeInterval = 1.0 / 60.0
    private static let ungroupedID = OutputRoutingStore.ungroupedRouteID

    private(set) var isFadedOut = false
    private(set) var isFading = false

    private var phase: Phase = .idle
    private var savedVolumes: [UUID: Double] = [:]
    private var rampGeneration = 0

    private enum Phase {
        case idle
        case fadingOut
        case fadedOut
        case fadingIn
    }

    private func setPhase(_ newPhase: Phase) {
        phase = newPhase
        isFadedOut = newPhase == .fadingOut || newPhase == .fadedOut
        isFading = newPhase == .fadingOut || newPhase == .fadingIn
    }

    func cancel() {
        rampGeneration += 1
        switch phase {
        case .fadingOut, .fadingIn:
            setPhase(.fadedOut)
        case .idle, .fadedOut:
            break
        }
    }

    func reset() {
        rampGeneration += 1
        savedVolumes = [:]
        setPhase(.idle)
    }

    /// Stops any in-flight fade and immediately restores saved group levels.
    func clearFade(context: ModelContext, onMixChange: @escaping () -> Void) {
        rampGeneration += 1

        guard !savedVolumes.isEmpty else {
            setPhase(.idle)
            return
        }

        let groups = fadeableGroups(in: context)
        for group in groups {
            if let volume = savedVolumes[group.id] {
                group.volume = volume
            }
        }
        if let volume = savedVolumes[Self.ungroupedID] {
            OutputRoutingStore.config(in: context).ungroupedVolume = volume
        }

        savedVolumes = [:]
        setPhase(.idle)
        onMixChange()
    }

    func toggleFade(
        context: ModelContext,
        onMixChange: @escaping () -> Void,
        onComplete: (() -> Void)? = nil
    ) {
        switch phase {
        case .idle, .fadingIn:
            beginFadeOut(context: context, onMixChange: onMixChange, onComplete: onComplete)
        case .fadingOut, .fadedOut:
            beginFadeIn(context: context, onMixChange: onMixChange, onComplete: onComplete)
        }
    }

    private func beginFadeOut(
        context: ModelContext,
        onMixChange: @escaping () -> Void,
        onComplete: (() -> Void)?
    ) {
        let groups = fadeableGroups(in: context)
        let routingConfig = OutputRoutingStore.config(in: context)

        if savedVolumes.isEmpty {
            var snapshot: [UUID: Double] = [:]
            snapshot.reserveCapacity(groups.count + 1)
            for group in groups {
                snapshot[group.id] = group.volume
            }
            snapshot[Self.ungroupedID] = routingConfig.ungroupedVolume
            savedVolumes = snapshot
        }

        var targets: [UUID: Double] = [:]
        targets.reserveCapacity(groups.count + 1)
        for group in groups {
            targets[group.id] = 0
        }
        targets[Self.ungroupedID] = 0

        setPhase(.fadingOut)
        startRamp(targets: targets, context: context, onMixChange: onMixChange) { [weak self] in
            self?.setPhase(.fadedOut)
            onComplete?()
        }
    }

    private func beginFadeIn(
        context: ModelContext,
        onMixChange: @escaping () -> Void,
        onComplete: (() -> Void)?
    ) {
        guard !savedVolumes.isEmpty else {
            setPhase(.idle)
            return
        }

        let groups = fadeableGroups(in: context)
        let routingConfig = OutputRoutingStore.config(in: context)
        var targets: [UUID: Double] = [:]
        targets.reserveCapacity(groups.count + 1)
        for group in groups {
            targets[group.id] = savedVolumes[group.id] ?? group.volume
        }
        targets[Self.ungroupedID] = savedVolumes[Self.ungroupedID] ?? routingConfig.ungroupedVolume

        setPhase(.fadingIn)
        startRamp(targets: targets, context: context, onMixChange: onMixChange) { [weak self] in
            self?.savedVolumes = [:]
            self?.setPhase(.idle)
            onComplete?()
        }
    }

    private func startRamp(
        targets: [UUID: Double],
        context: ModelContext,
        onMixChange: @escaping () -> Void,
        onComplete: @escaping () -> Void
    ) {
        rampGeneration += 1
        let generation = rampGeneration
        let groups = fadeableGroups(in: context)
        let routingConfig = OutputRoutingStore.config(in: context)

        var starts: [UUID: Double] = [:]
        starts.reserveCapacity(groups.count + 1)
        for group in groups {
            guard targets[group.id] != nil else { continue }
            starts[group.id] = group.volume
        }
        if targets[Self.ungroupedID] != nil {
            starts[Self.ungroupedID] = routingConfig.ungroupedVolume
        }

        let duration = Self.duration
        let stepInterval = Self.stepInterval
        let steps = max(1, Int((duration / stepInterval).rounded(.up)))

        for step in 0...steps {
            let t = Double(step) / Double(steps)
            let delay = duration * t
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.rampGeneration == generation else { return }

                let liveGroups = self.fadeableGroups(in: context)
                for group in liveGroups {
                    guard let start = starts[group.id], let target = targets[group.id] else { continue }
                    group.volume = start + (target - start) * t
                }

                if let start = starts[Self.ungroupedID], let target = targets[Self.ungroupedID] {
                    let config = OutputRoutingStore.config(in: context)
                    config.ungroupedVolume = start + (target - start) * t
                }

                onMixChange()

                if step == steps {
                    onComplete()
                }
            }
        }
    }

    private func fadeableGroups(in context: ModelContext) -> [TrackGroup] {
        TrackGroupStore.sortedGroups(from: context).filter { !Self.isExcludedFromFade($0) }
    }

    private static func isExcludedFromFade(_ group: TrackGroup) -> Bool {
        isClickGroup(group) || TimecodePlaybackSupport.isTimecodeGroup(group)
    }

    private static func isClickGroup(_ group: TrackGroup) -> Bool {
        group.name
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .caseInsensitiveCompare("Click") == .orderedSame
    }
}
