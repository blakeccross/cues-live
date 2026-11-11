import SwiftUI
#if os(macOS)
import AppKit
#endif
#if os(iOS)
import UIKit
#endif

enum AppBackgroundLevel {
    case primary
    case secondary
    case surface
    case elevated
}

extension View {
    func appBackground(_ level: AppBackgroundLevel = .primary) -> some View {
        background(backgroundColor(for: level).ignoresSafeArea())
    }

    func appPressable(isEnabled: Bool = true) -> some View {
        modifier(AppPressableModifier(isEnabled: isEnabled))
    }

    /// Lets a dialog use the system title bar. Sheets opened from the sidebar
    /// otherwise keep an empty leading slot for the sidebar toggle, and they
    /// inherit the main window's inline title.
    func standardDialogToolbar() -> some View {
        modifier(StandardDialogToolbarModifier())
    }

    func appLinkPointer() -> some View {
        modifier(AppLinkPointerModifier())
    }

    /// Locks the window toolbar to icon-only and removes the native
    /// "Icon and Text" / "Icon Only" / "Text Only" right-click options (macOS 15+).
    func appLockToolbarDisplayMode() -> some View {
        #if os(macOS)
        background(MacToolbarDisplayModeLock())
        #else
        self
        #endif
    }

    #if os(iOS)
    /// Restricts interface orientations while this view is visible.
    func locksInterfaceOrientations(_ mask: UIInterfaceOrientationMask) -> some View {
        modifier(InterfaceOrientationLockModifier(mask: mask))
    }
    #endif
}

private func backgroundColor(for level: AppBackgroundLevel) -> Color {
    switch level {
    case .primary: AppColors.backgroundPrimary
    case .secondary: AppColors.backgroundSecondary
    case .surface: AppColors.surface
    case .elevated: AppColors.surfaceElevated
    }
}

#if os(iOS)
enum AppOrientationLock {
    /// Matches Info.plist supported orientations for iPhone/iPad.
    static let unlockedMask: UIInterfaceOrientationMask = .all

    private(set) static var mask: UIInterfaceOrientationMask = unlockedMask

    static func set(_ mask: UIInterfaceOrientationMask) {
        Self.mask = mask

        guard let scene = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .first(where: { $0.activationState == .foregroundActive })
                ?? UIApplication.shared.connectedScenes
                .compactMap({ $0 as? UIWindowScene })
                .first
        else {
            return
        }

        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask))
        scene.windows.forEach { window in
            window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
        }
    }
}

final class CuesLiveAppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?
    ) -> UIInterfaceOrientationMask {
        AppOrientationLock.mask
    }
}

private struct InterfaceOrientationLockModifier: ViewModifier {
    let mask: UIInterfaceOrientationMask

    func body(content: Content) -> some View {
        content
            .onAppear {
                AppOrientationLock.set(mask)
            }
            .onDisappear {
                AppOrientationLock.set(AppOrientationLock.unlockedMask)
            }
    }
}
#endif

private struct AppLinkPointerModifier: ViewModifier {
    func body(content: Content) -> some View {
        #if os(macOS)
        if #available(macOS 15.0, *) {
            content.pointerStyle(.link)
        } else {
            content.onHover { hovering in
                if hovering {
                    NSCursor.pointingHand.push()
                } else {
                    NSCursor.pop()
                }
            }
        }
        #else
        content
        #endif
    }
}

private struct AppPressableModifier: ViewModifier {
    let isEnabled: Bool
    @State private var isPressed = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(isPressed && isEnabled ? 0.97 : 1)
            .animation(AppAnimation.springSnappy, value: isPressed)
            .simultaneousGesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { _ in
                        guard isEnabled else { return }
                        isPressed = true
                    }
                    .onEnded { _ in
                        isPressed = false
                    }
            )
    }
}

private struct StandardDialogToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .toolbar(removing: .sidebarToggle)
            #if os(macOS)
            .background(StandardDialogWindowStyle())
            #endif
    }
}

#if os(macOS)
private struct StandardDialogWindowStyle: NSViewRepresentable {
    func makeNSView(context: Context) -> DialogWindowStyleView {
        DialogWindowStyleView()
    }

    func updateNSView(_ nsView: DialogWindowStyleView, context: Context) {
        nsView.apply()
    }
}

/// Sheets inherit the scene's unified toolbar, which leaves the title indented.
/// Expanded is the system style where the title sits in the title bar.
private final class DialogWindowStyleView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        apply()
        DispatchQueue.main.async { [weak self] in
            self?.apply()
        }
    }

    override func layout() {
        super.layout()
        apply()
    }

    func apply() {
        guard let window, window.isSheet else { return }
        if window.toolbarStyle != .expanded {
            window.toolbarStyle = .expanded
        }
    }
}

private struct MacToolbarDisplayModeLock: NSViewRepresentable {
    func makeNSView(context: Context) -> ToolbarDisplayModeLockView {
        ToolbarDisplayModeLockView()
    }

    func updateNSView(_ nsView: ToolbarDisplayModeLockView, context: Context) {
        nsView.lockToolbarDisplayMode()
    }
}

private final class ToolbarDisplayModeLockView: NSView {
    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        lockToolbarDisplayMode()
        // SwiftUI often installs the NSToolbar after the first attach.
        DispatchQueue.main.async { [weak self] in
            self?.lockToolbarDisplayMode()
        }
    }

    override func layout() {
        super.layout()
        lockToolbarDisplayMode()
    }

    func lockToolbarDisplayMode() {
        guard let toolbar = window?.toolbar else { return }
        toolbar.displayMode = .iconOnly
        toolbar.allowsUserCustomization = false
        if #available(macOS 15.0, *) {
            toolbar.allowsDisplayModeCustomization = false
        }
        // Hide Liquid Glass shared backgrounds on toolbar items (API may be absent on older SDKs).
        for item in toolbar.items {
            guard item.responds(to: Selector(("setHidesSharedBackground:"))) else { continue }
            item.setValue(true, forKey: "hidesSharedBackground")
        }
    }
}
#endif
