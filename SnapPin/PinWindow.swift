import Cocoa

class PinWindow: NSPanel {
    
    private var pinView: PinView!
    private weak var pinManager: PinManager?
    var pinnedImage: NSImage
    
    init(image: NSImage, position: NSPoint, pinManager: PinManager) {
        self.pinnedImage = image
        self.pinManager = pinManager
        
        let contentRect = NSRect(x: position.x, y: position.y, width: image.size.width, height: image.size.height)
        
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = false
        self.backgroundColor = .clear
        self.level = .floating
        self.hasShadow = true
        self.isMovableByWindowBackground = false
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.hidesOnDeactivate = false
        self.isFloatingPanel = true
        self.isReleasedWhenClosed = false
        
        pinView = PinView(frame: NSRect(origin: .zero, size: contentRect.size), image: image, pinWindow: self)
        self.contentView = pinView
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    
    func closePinWindow() {
        pinManager?.removePinWindow(self)
        self.orderOut(nil)
        self.close()
    }
    
    override func keyDown(with event: NSEvent) {
        // Cmd+C to copy
        if event.modifierFlags.contains(.command) && event.charactersIgnoringModifiers == "c" {
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([pinnedImage])
            pinView.flashCopyFeedback()
            return
        }
        
        if event.keyCode == 53 { // Escape
            closePinWindow()
        } else {
            super.keyDown(with: event)
        }
    }
}

// MARK: - PinView (no extra UI, clean image only)

class PinView: NSView {
    
    private var image: NSImage
    private weak var pinWindow: PinWindow?
    
    private var isDragging = false
    private var dragStartPoint: NSPoint = .zero
    private var windowStartOrigin: NSPoint = .zero
    
    private var isResizing = false
    private var resizeStartPoint: NSPoint = .zero
    private var resizeStartSize: NSSize = .zero
    private var resizeEdge: ResizeEdge = .none
    
    private var trackingArea: NSTrackingArea?
    
    private var showCopyFlash = false
    
    enum ResizeEdge {
        case none, bottomRight, bottomLeft, topRight, topLeft
    }
    
    init(frame: NSRect, image: NSImage, pinWindow: PinWindow) {
        self.image = image
        self.pinWindow = pinWindow
        super.init(frame: frame)
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func setupTrackingArea() {
        let opts: NSTrackingArea.Options = [.mouseEnteredAndExited, .activeAlways, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        setupTrackingArea()
    }
    
    func flashCopyFeedback() {
        showCopyFlash = true
        needsDisplay = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.showCopyFlash = false
            self?.needsDisplay = true
        }
    }
    
    // MARK: - Drawing (clean, no extra UI)
    
    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        
        // Just draw the image, nothing else
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1.0)
        
        // Copy flash feedback (subtle green overlay)
        if showCopyFlash {
            if let ctx = NSGraphicsContext.current?.cgContext {
                ctx.setFillColor(NSColor.systemGreen.withAlphaComponent(0.15).cgColor)
                ctx.fill(bounds)
            }
        }
    }
    
    // MARK: - Mouse
    
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        
        let cs: CGFloat = 15
        resizeEdge = getEdge(at: loc, cs: cs)
        
        if resizeEdge != .none {
            isResizing = true
            resizeStartPoint = NSEvent.mouseLocation
            resizeStartSize = bounds.size
        } else {
            isDragging = true
            dragStartPoint = NSEvent.mouseLocation
            windowStartOrigin = window?.frame.origin ?? .zero
        }
    }
    
    override func mouseDragged(with event: NSEvent) {
        let cur = NSEvent.mouseLocation
        
        if isResizing, let win = self.window {
            let dx = cur.x - resizeStartPoint.x
            var nw = resizeStartSize.width
            var nh = resizeStartSize.height
            var no = win.frame.origin
            let ar = resizeStartSize.width / resizeStartSize.height
            
            switch resizeEdge {
            case .bottomRight:
                nw = max(50, resizeStartSize.width + dx); nh = nw / ar
                no.y = win.frame.origin.y + (win.frame.height - nh)
            case .bottomLeft:
                nw = max(50, resizeStartSize.width - dx); nh = nw / ar
                no.x = win.frame.origin.x + (win.frame.width - nw)
                no.y = win.frame.origin.y + (win.frame.height - nh)
            case .topRight:
                nw = max(50, resizeStartSize.width + dx); nh = nw / ar
            case .topLeft:
                nw = max(50, resizeStartSize.width - dx); nh = nw / ar
                no.x = win.frame.origin.x + (win.frame.width - nw)
            case .none: break
            }
            win.setFrame(NSRect(x: no.x, y: no.y, width: nw, height: nh), display: true)
            
        } else if isDragging, let win = self.window {
            let dx = cur.x - dragStartPoint.x
            let dy = cur.y - dragStartPoint.y
            win.setFrameOrigin(NSPoint(x: windowStartOrigin.x + dx, y: windowStartOrigin.y + dy))
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        isDragging = false
        isResizing = false
        resizeEdge = .none
    }
    
    override func rightMouseDown(with event: NSEvent) {
        let menu = NSMenu()
        menu.addItem(NSMenuItem(title: "Copy to Clipboard", action: #selector(doCopy), keyEquivalent: ""))
        menu.addItem(NSMenuItem(title: "Save to Desktop", action: #selector(doSave), keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Close", action: #selector(doClose), keyEquivalent: ""))
        NSMenu.popUpContextMenu(menu, with: event, for: self)
    }
    
    @objc func doClose() { pinWindow?.closePinWindow() }
    
    @objc func doCopy() {
        guard let img = pinWindow?.pinnedImage else { return }
        let pb = NSPasteboard.general
        pb.clearContents()
        pb.writeObjects([img])
        flashCopyFeedback()
    }
    
    @objc func doSave() {
        let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask).first!
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let url = desktop.appendingPathComponent("SnapPin_\(fmt.string(from: Date())).png")
        if let tiff = image.tiffRepresentation,
           let rep = NSBitmapImageRep(data: tiff),
           let png = rep.representation(using: .png, properties: [:]) {
            try? png.write(to: url)
        }
    }
    
    // MARK: - Scroll to resize
    override func scrollWheel(with event: NSEvent) {
        guard let win = self.window else { return }
        let s: CGFloat = event.deltaY > 0 ? 1.05 : 0.95
        let f = win.frame
        let ar = f.width / f.height
        var nw = f.width * s
        nw = max(50, min(nw, 2000))
        let nh = nw / ar
        win.setFrame(NSRect(x: f.midX - nw / 2, y: f.midY - nh / 2, width: nw, height: nh), display: true)
    }
    
    private func getEdge(at p: NSPoint, cs: CGFloat) -> ResizeEdge {
        let l = p.x < cs, r = p.x > bounds.width - cs
        let t = p.y > bounds.height - cs, b = p.y < cs
        if b && r { return .bottomRight }
        if b && l { return .bottomLeft }
        if t && r { return .topRight }
        if t && l { return .topLeft }
        return .none
    }
    
    override func resetCursorRects() {
        let cs: CGFloat = 15
        addCursorRect(NSRect(x: bounds.width - cs, y: 0, width: cs, height: cs), cursor: .crosshair)
        addCursorRect(NSRect(x: 0, y: 0, width: cs, height: cs), cursor: .crosshair)
        addCursorRect(NSRect(x: bounds.width - cs, y: bounds.height - cs, width: cs, height: cs), cursor: .crosshair)
        addCursorRect(NSRect(x: 0, y: bounds.height - cs, width: cs, height: cs), cursor: .crosshair)
    }
}
