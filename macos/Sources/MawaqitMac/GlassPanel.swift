import AppKit
import SwiftUI

/// A floating menu-bar surface with a single native glass background.
@MainActor
final class GlassContentController<Content: View>: NSViewController {
    private let hosting: NSHostingController<Content>

    init(rootView: Content) {
        hosting = NSHostingController(rootView: rootView)
        super.init(nibName: nil, bundle: nil)
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override func loadView() {
        addChild(hosting)
        if #available(macOS 26.0, *) {
            let glass = NSGlassEffectView()
            glass.style = .regular
            glass.cornerRadius = 22
            glass.contentView = hosting.view
            view = glass
        } else {
            let material = NSVisualEffectView()
            material.material = .popover
            material.blendingMode = .behindWindow
            material.state = .active
            material.wantsLayer = true
            material.layer?.cornerRadius = 22
            material.layer?.masksToBounds = true
            material.addSubview(hosting.view)
            view = material
        }
        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])
    }
}

@MainActor
final class GlassPanel: NSPanel, NSWindowDelegate {
    private var outsideClickMonitor: Any?
    private var localClickMonitor: Any?
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init() {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 340, height: 440),
                   styleMask: [.borderless], backing: .buffered, defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        level = .popUpMenu
        isReleasedWhenClosed = false
        hidesOnDeactivate = true
        collectionBehavior = [.transient, .fullScreenAuxiliary]
        delegate = self
    }

    func resizeContent(to size: NSSize) {
        let top = frame.maxY
        setContentSize(size)
        setFrameOrigin(NSPoint(x: frame.minX, y: top - frame.height))
    }

    /// Shows the panel under the menu-bar button, or at the top centre of the screen
    /// when a menu-bar manager has hidden the button.
    func show(below button: NSStatusBarButton?) {
        let anchorWindow = button?.window
        if let button, let anchorWindow, anchorWindow.occlusionState.contains(.visible) {
            let anchor = anchorWindow.convertToScreen(button.convert(button.bounds, to: nil))
            let visible = (anchorWindow.screen ?? NSScreen.main)?.visibleFrame ?? anchor
            let x = min(max(anchor.midX - frame.width / 2, visible.minX + 8), visible.maxX - frame.width - 8)
            setFrameOrigin(NSPoint(x: x, y: anchor.minY - frame.height - 6))
        } else if let visible = NSScreen.main?.visibleFrame {
            setFrameOrigin(NSPoint(x: visible.midX - frame.width / 2, y: visible.maxY - frame.height - 6))
        }
        NSApp.activate(ignoringOtherApps: true)
        makeKeyAndOrderFront(nil)
        removeMonitors()
        outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            self?.dismiss()
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self, weak anchorWindow] event in
            if let self, event.window !== self, event.window?.parent !== self,
               event.window !== anchorWindow { self.dismiss() }
            return event
        }
    }

    func dismiss() {
        orderOut(nil)
        removeMonitors()
    }

    override func cancelOperation(_ sender: Any?) { dismiss() }
    func windowDidResignKey(_ notification: Notification) {
        // A popover from this panel (Settings) becomes key without closing the panel.
        DispatchQueue.main.async { [weak self] in
            guard let self, NSApp.keyWindow !== self, NSApp.keyWindow?.parent !== self else { return }
            self.dismiss()
        }
    }

    private func removeMonitors() {
        if let outsideClickMonitor { NSEvent.removeMonitor(outsideClickMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
        outsideClickMonitor = nil
        localClickMonitor = nil
    }
}
