import AppKit
import Combine
import SwiftUI
import UserNotifications

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private let store = MawaqitStore()
    private var statusItem: NSStatusItem?
    private let popover = GlassPanel()
    private var timer: Timer?
    private var cancellables = Set<AnyCancellable>()
    private var started = false

    static func main() {
        let application = NSApplication.shared
        let delegate = AppDelegate()
        application.delegate = delegate
        application.setActivationPolicy(.accessory)
        delegate.start()
        application.finishLaunching()
        withExtendedLifetime(delegate) {
            application.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        start()
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        // Opening the app again shows the same glass panel, even if the menu-bar icon is hidden.
        store.showingSettings = false
        showPanel()
        return false
    }

    private func showPanel() {
        store.tick()
        if !popover.isVisible { popover.show(below: statusItem?.button) }
    }

    private func start() {
        guard !started else { return }
        started = true
        NSApp.setActivationPolicy(.accessory)
        installMainMenu()
        let statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        statusItem.autosaveName = "Mawaqit"
        statusItem.isVisible = true
        self.statusItem = statusItem
        if let button = statusItem.button {
            button.identifier = NSUserInterfaceItemIdentifier("Mawaqit")
            button.setAccessibilityIdentifier("Mawaqit")
            button.image = NSImage(systemSymbolName: "moon.stars.fill", accessibilityDescription: "Mawaqit Prayer Times")
            button.image?.isTemplate = true
            button.imagePosition = .imageLeading
            button.target = self
            button.action = #selector(togglePopover)
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
        }
        popover.contentViewController = GlassContentController(rootView: MenuContentView(store: store, openSettings: { [weak self] in self?.showSettings() }, onSizeChange: { [weak self] height in
            self?.popover.resizeContent(to: NSSize(width: 340, height: height))
        }))
        UNUserNotificationCenter.current().delegate = self

        store.$statusTitle.combineLatest(store.$iconOnlyMenuBar).sink { [weak self] title, iconOnly in
            guard let self, let statusItem = self.statusItem else { return }
            statusItem.isVisible = true
            statusItem.length = iconOnly ? NSStatusItem.squareLength : NSStatusItem.variableLength
            statusItem.button?.title = iconOnly || title.isEmpty ? "" : " \(title)"
            statusItem.button?.toolTip = title.isEmpty ? "Mawaqit Prayer Times" : title
        }.store(in: &cancellables)
        timer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.store.tick() }
        }
        store.tick()
    }

    @objc private func togglePopover() {
        guard let statusItem, let button = statusItem.button else { return }
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            addCommand("Open Mawaqit", action: #selector(showMainWindow), to: menu)
            addCommand("Settings…", action: #selector(showSettings), key: ",", to: menu)
            menu.addItem(.separator())
            addCommand("Quit Mawaqit", action: #selector(quit), key: "q", to: menu)
            statusItem.menu = menu
            button.performClick(nil)
            statusItem.menu = nil
        } else if popover.isVisible {
            popover.dismiss()
        } else {
            store.showingSettings = false
            showPanel()
        }
    }

    private func addCommand(_ title: String, action: Selector, key: String = "", to menu: NSMenu) {
        let item = menu.addItem(withTitle: title, action: action, keyEquivalent: key)
        item.target = self
    }

    private func installMainMenu() {
        let main = NSMenu()
        let appItem = main.addItem(withTitle: "Mawaqit", action: nil, keyEquivalent: "")
        let appMenu = NSMenu(title: "Mawaqit")
        appItem.submenu = appMenu
        addCommand("About Mawaqit", action: #selector(showAbout), to: appMenu)
        addCommand("Settings…", action: #selector(showSettings), key: ",", to: appMenu)
        appMenu.addItem(.separator())
        addCommand("Quit Mawaqit", action: #selector(quit), key: "q", to: appMenu)
        let editItem = main.addItem(withTitle: "Edit", action: nil, keyEquivalent: "")
        let edit = NSMenu(title: "Edit")
        editItem.submenu = edit
        for (title, action, key) in [("Undo", "undo:", "z"), ("Cut", "cut:", "x"),
                                     ("Copy", "copy:", "c"), ("Paste", "paste:", "v"),
                                     ("Select All", "selectAll:", "a")] {
            edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key)
        }
        let windowItem = main.addItem(withTitle: "Window", action: nil, keyEquivalent: "")
        let window = NSMenu(title: "Window")
        windowItem.submenu = window
        window.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m")
        window.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w")
        NSApp.windowsMenu = window
        NSApp.mainMenu = main
    }

    @objc private func showMainWindow() {
        _ = applicationShouldHandleReopen(NSApp, hasVisibleWindows: false)
    }

    @objc private func showAbout() {
        NSApp.orderFrontStandardAboutPanel(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    @objc private func showSettings() {
        showPanel()
        // Present after the panel is on screen so the popover has an anchor.
        DispatchQueue.main.async { self.store.showingSettings = true }
    }

    @objc private func quit() { NSApp.terminate(nil) }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound])
    }
}
