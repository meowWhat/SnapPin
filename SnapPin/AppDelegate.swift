import Cocoa
import Carbon
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem!
    var screenshotManager: ScreenshotManager!
    var pinManager: PinManager!
    var settingsController: SettingsWindowController!
    
    // HotKey library instances (Carbon RegisterEventHotKey under the hood)
    private var screenshotHotKey: HotKey?
    private var pinHotKey: HotKey?
    
    // Local monitor for overlay window key events
    var localKeyMonitor: Any?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        pinManager = PinManager()
        screenshotManager = ScreenshotManager(pinManager: pinManager)
        setupStatusItem()
        NSApp.setActivationPolicy(.accessory)
        
        // Always register hotkeys immediately on launch
        registerHotkeys()
        
        // Setup settings controller with hotkey change callback
        settingsController = SettingsWindowController()
        settingsController.onHotkeyChanged = { [weak self] in
            self?.registerHotkeys()
        }
        
        // Show settings if needed (first launch / version bump / relaunch after permission change)
        if CommandLine.arguments.contains("--relaunch-after-permission") {
            settingsController.forceShow()
        } else {
            settingsController.showIfNeeded()
        }
        
        // Install SIGTERM handler for auto-relaunch after permission changes
        // macOS sends SIGTERM when "Quit & Reopen" is triggered from permission dialogs
        installTerminationHandler()
        
        print("[SnapPin] App launched, hotkeys registered")
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        unregisterHotkeys()
    }
    
    // MARK: - Auto-Relaunch on Permission Change
    
    private func installTerminationHandler() {
        // Listen for SIGTERM which macOS sends when asking app to quit for permission changes
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        signal(SIGTERM, SIG_IGN) // Ignore default handler so we can handle it
        source.setEventHandler {
            // Schedule relaunch before terminating
            let bundleURL = Bundle.main.bundleURL
            DispatchQueue.global().async {
                // Small delay to let the current process finish cleanup
                Thread.sleep(forTimeInterval: 0.5)
                let task = Process()
                task.executableURL = URL(fileURLWithPath: "/usr/bin/open")
                task.arguments = [bundleURL.path, "--args", "--relaunch-after-permission"]
                try? task.run()
            }
            // Now actually terminate
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                NSApp.terminate(nil)
            }
        }
        source.resume()
        // Keep a reference to prevent deallocation
        _signalSource = source
    }
    
    private var _signalSource: DispatchSourceSignal?
    
    // MARK: - Status Bar
    
    func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        
        if let button = statusItem.button {
            button.image = NSImage(systemSymbolName: "scissors", accessibilityDescription: "SnapPin")
            button.image?.size = NSSize(width: 18, height: 18)
        }
        
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Screenshot (F1)", action: #selector(takeScreenshot), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Close All Pins", action: #selector(closeAllPins), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Settings...", action: #selector(showSettings), keyEquivalent: ","))
        menu.addItem(NSMenuItem(title: "Quit SnapPin", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    // MARK: - Global Hotkeys using HotKey library (Carbon RegisterEventHotKey)
    
    func registerHotkeys() {
        // Clear existing hotkeys
        screenshotHotKey = nil
        pinHotKey = nil
        
        // Screenshot hotkey
        let ssConfig = SettingsWindowController.screenshotHotkey()
        screenshotHotKey = HotKey(key: ssConfig.key, modifiers: ssConfig.modifiers)
        screenshotHotKey?.keyDownHandler = { [weak self] in
            print("[SnapPin] Screenshot hotkey pressed")
            self?.takeScreenshot()
        }
        
        // Pin hotkey
        let pinConfig = SettingsWindowController.pinHotkey()
        pinHotKey = HotKey(key: pinConfig.key, modifiers: pinConfig.modifiers)
        pinHotKey?.keyDownHandler = { [weak self] in
            print("[SnapPin] Pin hotkey pressed")
            self?.screenshotManager.handleF3()
        }
        
        // Local monitor for overlay window key events (Cmd+C, Enter, Esc)
        if localKeyMonitor == nil {
            localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
                if self?.handleLocalKeyEvent(event) == true {
                    return nil
                }
                return event
            }
        }
        
        print("[SnapPin] Hotkeys registered: Screenshot=\(ssConfig.key), Pin=\(pinConfig.key)")
    }
    
    func unregisterHotkeys() {
        screenshotHotKey = nil
        pinHotKey = nil
        
        if let m = localKeyMonitor {
            NSEvent.removeMonitor(m)
            localKeyMonitor = nil
        }
    }
    
    /// Handle key events when our overlay window is active
    @discardableResult
    private func handleLocalKeyEvent(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.function)
        
        // Cmd+C during capture: copy and close
        if flags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            if screenshotManager.hasActiveSelection {
                print("[SnapPin] Cmd+C pressed during capture - copy action")
                screenshotManager.handleCmdC()
                return true
            }
        }
        
        // Enter during capture (not in text editing): copy and close
        if event.keyCode == 36 || event.keyCode == 76 { // Return or Enter (numpad)
            if screenshotManager.hasActiveSelection && !screenshotManager.isInTextEditingMode {
                print("[SnapPin] Enter pressed during capture - copy action")
                screenshotManager.handleCmdC()
                return true
            }
        }
        
        // Escape during capture: cancel
        if event.keyCode == 53 {
            if screenshotManager.hasActiveSelection {
                screenshotManager.cancelCapture()
                return true
            }
        }
        
        return false
    }
    
    // MARK: - Actions
    
    @objc func takeScreenshot() {
        screenshotManager.startCapture()
    }
    
    @objc func closeAllPins() {
        pinManager.closeAllPins()
    }
    
    @objc func showSettings() {
        settingsController.forceShow()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
