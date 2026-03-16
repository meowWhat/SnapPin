import Cocoa

class OnboardingWindowController: NSObject {
    
    // Bump this version whenever the app is updated and needs re-onboarding
    static let currentOnboardingVersion = 5
    
    private var window: NSWindow?
    
    func showIfNeeded() {
        let savedVersion = UserDefaults.standard.integer(forKey: "onboardingVersion")
        if savedVersion >= OnboardingWindowController.currentOnboardingVersion {
            return
        }
        showOnboardingWindow()
    }
    
    func forceShow() {
        showOnboardingWindow()
    }
    
    private func showOnboardingWindow() {
        let w: CGFloat = 520
        let h: CGFloat = 500
        
        let screenFrame = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1440, height: 900)
        let rect = NSRect(x: (screenFrame.width - w) / 2, y: (screenFrame.height - h) / 2, width: w, height: h)
        
        window = NSWindow(contentRect: rect, styleMask: [.titled, .closable], backing: .buffered, defer: false)
        window?.title = "Welcome to SnapPin"
        window?.isReleasedWhenClosed = false
        window?.level = .floating
        
        let cv = NSView(frame: NSRect(x: 0, y: 0, width: w, height: h))
        cv.wantsLayer = true
        
        var y = h - 60
        
        // Title
        let title = makeLabel("SnapPin", font: .systemFont(ofSize: 28, weight: .bold), frame: NSRect(x: 0, y: y, width: w, height: 36))
        title.alignment = .center
        cv.addSubview(title)
        y -= 26
        
        let subtitle = makeLabel("Screenshot & Pin Tool for macOS", font: .systemFont(ofSize: 14), frame: NSRect(x: 0, y: y, width: w, height: 20))
        subtitle.alignment = .center
        subtitle.textColor = .secondaryLabelColor
        cv.addSubview(subtitle)
        y -= 24
        
        let sep1 = NSBox(frame: NSRect(x: 40, y: y, width: w - 80, height: 1))
        sep1.boxType = .separator
        cv.addSubview(sep1)
        y -= 30
        
        // Permissions title
        let permTitle = makeLabel("Required Permissions", font: .systemFont(ofSize: 16, weight: .semibold), frame: NSRect(x: 40, y: y, width: w - 80, height: 22))
        cv.addSubview(permTitle)
        y -= 10
        
        // Screen Recording
        y -= 60
        let srBox = makePermissionRow(
            icon: "camera.fill",
            title: "Screen Recording",
            desc: "Capture screen content for screenshots.",
            buttonTitle: "Open Screen Recording Settings",
            action: #selector(openScreenRecordingSettings),
            yPos: y, width: w
        )
        cv.addSubview(srBox)
        
        // Accessibility
        y -= 70
        let accBox = makePermissionRow(
            icon: "keyboard",
            title: "Accessibility (Optional)",
            desc: "May improve global hotkey reliability.",
            buttonTitle: "Open Accessibility Settings",
            action: #selector(openAccessibilitySettings),
            yPos: y, width: w
        )
        cv.addSubview(accBox)
        
        // Separator
        y -= 20
        let sep2 = NSBox(frame: NSRect(x: 40, y: y, width: w - 80, height: 1))
        sep2.boxType = .separator
        cv.addSubview(sep2)
        y -= 30
        
        // Hotkey info
        let hkTitle = makeLabel("Keyboard Shortcuts", font: .systemFont(ofSize: 16, weight: .semibold), frame: NSRect(x: 40, y: y, width: w - 80, height: 22))
        cv.addSubview(hkTitle)
        y -= 70
        
        let hkInfo = makeLabel(
            "F1       Take screenshot (drag to select area)\nF3       Pin screenshot (after selection)\nCmd+C    Copy screenshot (after selection)\nCmd+Z    Undo last annotation\nEsc      Cancel / Close",
            font: .monospacedSystemFont(ofSize: 12, weight: .regular),
            frame: NSRect(x: 50, y: y, width: w - 100, height: 75)
        )
        hkInfo.maximumNumberOfLines = 0
        hkInfo.textColor = .secondaryLabelColor
        cv.addSubview(hkInfo)
        
        // Version label
        let verLabel = makeLabel(
            "v\(OnboardingWindowController.currentOnboardingVersion)",
            font: .systemFont(ofSize: 10),
            frame: NSRect(x: 40, y: 24, width: 60, height: 16)
        )
        verLabel.textColor = .tertiaryLabelColor
        cv.addSubview(verLabel)
        
        // Get Started button
        let startBtn = NSButton(frame: NSRect(x: w - 190, y: 20, width: 150, height: 36))
        startBtn.title = "Get Started"
        startBtn.bezelStyle = .rounded
        startBtn.keyEquivalent = "\r"
        startBtn.contentTintColor = .white
        startBtn.target = self
        startBtn.action = #selector(getStarted)
        cv.addSubview(startBtn)
        
        window?.contentView = cv
        window?.center()
        window?.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    
    private func makeLabel(_ text: String, font: NSFont, frame: NSRect) -> NSTextField {
        let l = NSTextField(frame: frame)
        l.stringValue = text
        l.font = font
        l.isBezeled = false
        l.drawsBackground = false
        l.isEditable = false
        l.isSelectable = false
        return l
    }
    
    private func makePermissionRow(icon: String, title: String, desc: String, buttonTitle: String, action: Selector, yPos: CGFloat, width: CGFloat) -> NSView {
        let box = NSView(frame: NSRect(x: 40, y: yPos, width: width - 80, height: 60))
        
        let iconView = NSImageView(frame: NSRect(x: 0, y: 28, width: 28, height: 28))
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: title) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 18, weight: .medium)
            iconView.image = img.withSymbolConfiguration(cfg)
            iconView.contentTintColor = .systemBlue
        }
        box.addSubview(iconView)
        
        let tl = makeLabel(title, font: .systemFont(ofSize: 13, weight: .semibold), frame: NSRect(x: 38, y: 38, width: 200, height: 18))
        box.addSubview(tl)
        
        let dl = makeLabel(desc, font: .systemFont(ofSize: 11), frame: NSRect(x: 38, y: 20, width: 260, height: 16))
        dl.textColor = .secondaryLabelColor
        box.addSubview(dl)
        
        let btn = NSButton(frame: NSRect(x: 38, y: -4, width: 250, height: 24))
        btn.title = buttonTitle
        btn.bezelStyle = .inline
        btn.controlSize = .small
        btn.font = .systemFont(ofSize: 11)
        btn.contentTintColor = .systemBlue
        btn.target = self
        btn.action = action
        box.addSubview(btn)
        
        return box
    }
    
    @objc private func openScreenRecordingSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }
    
    @objc private func getStarted() {
        UserDefaults.standard.set(OnboardingWindowController.currentOnboardingVersion, forKey: "onboardingVersion")
        window?.close()
        window = nil
    }
}
