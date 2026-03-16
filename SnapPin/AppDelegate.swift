import Cocoa
import Carbon
import HotKey

class AppDelegate: NSObject, NSApplicationDelegate {
    
    var statusItem: NSStatusItem!
    var screenshotManager: ScreenshotManager!
    var pinManager: PinManager!
    var onboardingController: OnboardingWindowController!
    
    // HotKey library instances (Carbon RegisterEventHotKey under the hood)
    private var f1HotKey: HotKey?
    private var f3HotKey: HotKey?
    
    // Local monitor for overlay window key events
    var localKeyMonitor: Any?
    
    func applicationDidFinishLaunching(_ aNotification: Notification) {
        pinManager = PinManager()
        screenshotManager = ScreenshotManager(pinManager: pinManager)
        
        setupStatusItem()
        NSApp.setActivationPolicy(.accessory)
        
        // Always register hotkeys immediately on launch
        registerHotkeys()
        
        // Show onboarding if needed (non-blocking)
        onboardingController = OnboardingWindowController()
        onboardingController.showIfNeeded()
        
        print("[SnapPin] App launched, hotkeys registered")
    }
    
    func applicationWillTerminate(_ aNotification: Notification) {
        unregisterHotkeys()
    }
    
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
        menu.addItem(NSMenuItem(title: "Show Onboarding", action: #selector(showOnboarding), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Quit SnapPin", action: #selector(quitApp), keyEquivalent: "q"))
        
        statusItem.menu = menu
    }
    
    // MARK: - Global Hotkeys using HotKey library (Carbon RegisterEventHotKey)
    
    func registerHotkeys() {
        // F1 - Screenshot (no modifiers)
        f1HotKey = HotKey(key: .f1, modifiers: [])
        f1HotKey?.keyDownHandler = { [weak self] in
            print("[SnapPin] F1 pressed - starting capture")
            self?.takeScreenshot()
        }
        
        // F3 - Pin shortcut (no modifiers)
        f3HotKey = HotKey(key: .f3, modifiers: [])
        f3HotKey?.keyDownHandler = { [weak self] in
            print("[SnapPin] F3 pressed - pin action")
            self?.screenshotManager.handleF3()
        }
        
        // Local monitor for overlay window key events (Cmd+C, Esc)
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            if self?.handleLocalKeyEvent(event) == true {
                return nil
            }
            return event
        }
        
        print("[SnapPin] HotKey (Carbon) registered for F1 and F3")
    }
    
    func unregisterHotkeys() {
        f1HotKey = nil
        f3HotKey = nil
        
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
    
    @objc func showOnboarding() {
        onboardingController.forceShow()
    }
    
    @objc func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
