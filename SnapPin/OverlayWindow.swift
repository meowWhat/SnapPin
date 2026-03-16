import Cocoa

// MARK: - Toolbar action result
enum ToolbarAction {
    case cancel
    case pin
    case save
    case copy
}

// MARK: - Resize handle positions
enum HandlePosition {
    case topLeft, topCenter, topRight
    case middleLeft, middleRight
    case bottomLeft, bottomCenter, bottomRight
    case none
}

// MARK: - Interaction mode
enum InteractionMode {
    case idle
    case drawing
    case editing
    case moving
    case resizing
    case annotating
    case textEditing
}

// MARK: - OverlayWindow

class OverlayWindow: NSWindow {
    
    private weak var screenshotManager: ScreenshotManager?
    
    init(screen: NSScreen, screenshotManager: ScreenshotManager, backgroundImage: CGImage?) {
        self.screenshotManager = screenshotManager
        
        super.init(
            contentRect: screen.frame,
            styleMask: .borderless,
            backing: .buffered,
            defer: false
        )
        
        self.isOpaque = true
        self.backgroundColor = .black
        self.level = NSWindow.Level(rawValue: Int(CGShieldingWindowLevel()))
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        self.isReleasedWhenClosed = false
    
        let viewFrame = NSRect(origin: .zero, size: screen.frame.size)
        let overlayView = OverlayView(
            frame: viewFrame,
            screenshotManager: screenshotManager,
            screen: screen,
            backgroundImage: backgroundImage
        )
        self.contentView = overlayView
    }
    
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
    
    override func keyDown(with event: NSEvent) {
        guard let view = contentView as? OverlayView else {
            super.keyDown(with: event)
            return
        }
        
        // If in text editing mode, route through input context for IME support
        if view.isInTextEditingMode {
            view.handleKeyEventForTextEditing(event)
            return
        }
        
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask).subtracting(.function)
        
        // Cmd+Z for undo annotation
        if flags.contains(.command) && event.charactersIgnoringModifiers == "z" {
            view.undoAnnotation()
            return
        }
        
        // Shift + arrow keys for 1px movement
        if flags.contains(.shift) && view.hasSelection {
            switch event.keyCode {
            case 123: view.nudgeSelection(dx: -1, dy: 0); return
            case 124: view.nudgeSelection(dx: 1, dy: 0); return
            case 125: view.nudgeSelection(dx: 0, dy: -1); return
            case 126: view.nudgeSelection(dx: 0, dy: 1); return
            default: break
            }
        }
        
        // Escape to cancel (only when NOT in text editing)
        if event.keyCode == 53 {
            screenshotManager?.cancelCapture()
        }
    }
}

// MARK: - OverlayView

class OverlayView: NSView, NSTextInputClient {
    
    private weak var screenshotManager: ScreenshotManager?
    private var targetScreen: NSScreen
    private var backgroundImage: CGImage?
    
    private var screenBGImage: NSImage?
    
    // Interaction state
    private var mode: InteractionMode = .idle
    var hasSelection: Bool {
        return mode == .editing || mode == .moving || mode == .resizing
            || mode == .annotating || mode == .textEditing
    }
    var isInTextEditingMode: Bool { return mode == .textEditing }
    private var selectionRect: NSRect = .zero
    
    // Drawing new selection
    private var drawStartPoint: NSPoint = .zero
    
    // Moving selection
    private var moveStartMouse: NSPoint = .zero
    private var moveStartRect: NSRect = .zero
    
    // Resizing selection
    private var activeHandle: HandlePosition = .none
    private var resizeStartMouse: NSPoint = .zero
    private var resizeStartRect: NSRect = .zero
    
    // Mouse tracking
    private var mouseLocation: NSPoint = .zero
    private var trackingArea: NSTrackingArea?
    
    // Toolbar
    private var toolbarView: NSView?
    private var colorBarView: NSView?  // Sub-toolbar for color selection
    
    // Annotation state
    private var activeAnnotationTool: AnnotationTool = .none
    private var annotations: [Annotation] = []
    private var currentAnnotation: Annotation?
    
    // Current annotation color
    private var annotationColor: NSColor = .systemRed
    private let colorOptions: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen,
        .systemBlue, .systemPurple, .white, .black,
    ]
    
    // Text editing state
    private var textEditingAnnotation: Annotation?
    private var textCursorVisible = true
    private var textCursorTimer: Timer?
    
    // IME marked text state
    private var markedTextString: String = ""
    private var markedTextRange: NSRange = NSRange(location: NSNotFound, length: 0)
    private var selectedTextRange: NSRange = NSRange(location: 0, length: 0)
    
    // Toolbar button references for highlight
    private var arrowBtn: NSButton?
    private var rectBtn: NSButton?
    private var textBtn: NSButton?
    private var mosaicBtn: NSButton?
    
    // Handle size
    private let handleSize: CGFloat = 8.0
    
    // Mosaic brush size
    private let mosaicBrushSize: CGFloat = 20.0
    
    init(frame: NSRect, screenshotManager: ScreenshotManager, screen: NSScreen, backgroundImage: CGImage?) {
        self.screenshotManager = screenshotManager
        self.targetScreen = screen
        self.backgroundImage = backgroundImage
        super.init(frame: frame)
        
        prepareScreenImage()
        setupTrackingArea()
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    private func prepareScreenImage() {
        guard let bg = backgroundImage else { return }
        screenBGImage = NSImage(cgImage: bg, size: targetScreen.frame.size)
    }
    
    private func setupTrackingArea() {
        let opts: NSTrackingArea.Options = [.mouseMoved, .activeAlways, .inVisibleRect]
        trackingArea = NSTrackingArea(rect: bounds, options: opts, owner: self, userInfo: nil)
        addTrackingArea(trackingArea!)
    }
    
    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let t = trackingArea { removeTrackingArea(t) }
        setupTrackingArea()
    }
    
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool {
        return true
    }
    
    override var acceptsFirstResponder: Bool { true }
    
    // MARK: - Public methods
    
    func triggerPin() {
        guard hasSelection, selectionRect.width > 3, selectionRect.height > 3 else { return }
        commitTextIfNeeded()
        finishWithAction(.pin)
    }
    
    func triggerCopy() {
        guard hasSelection, selectionRect.width > 3, selectionRect.height > 3 else { return }
        commitTextIfNeeded()
        finishWithAction(.copy)
    }
    
    func undoAnnotation() {
        if mode == .textEditing {
            textEditingAnnotation = nil
            markedTextString = ""
            markedTextRange = NSRange(location: NSNotFound, length: 0)
            stopTextCursorBlink()
            mode = .editing
            needsDisplay = true
            return
        }
        if !annotations.isEmpty {
            annotations.removeLast()
            needsDisplay = true
        }
    }
    
    func nudgeSelection(dx: CGFloat, dy: CGFloat) {
        var newX = selectionRect.origin.x + dx
        var newY = selectionRect.origin.y + dy
        newX = max(0, min(newX, bounds.width - selectionRect.width))
        newY = max(0, min(newY, bounds.height - selectionRect.height))
        selectionRect.origin = NSPoint(x: newX, y: newY)
        repositionToolbar()
        needsDisplay = true
    }
    
    // MARK: - Text Editing via NSTextInputClient
    
    /// Called from OverlayWindow.keyDown when in text editing mode
    func handleKeyEventForTextEditing(_ event: NSEvent) {
        // Route through inputContext for IME support
        if let ic = self.inputContext {
            let handled = ic.handleEvent(event)
            if !handled {
                // If inputContext didn't handle it, process directly
                handleDirectTextKey(event)
            }
        } else {
            handleDirectTextKey(event)
        }
    }
    
    /// Fallback direct key handling (non-IME)
    private func handleDirectTextKey(_ event: NSEvent) {
        guard mode == .textEditing, textEditingAnnotation != nil else { return }
        
        if event.keyCode == 53 { // Esc
            cancelTextEditing()
            return
        }
        if event.keyCode == 36 { // Enter
            commitTextIfNeeded()
            return
        }
        if event.keyCode == 51 { // Backspace
            if !textEditingAnnotation!.text.isEmpty {
                textEditingAnnotation!.text.removeLast()
                needsDisplay = true
            }
            return
        }
    }
    
    private func cancelTextEditing() {
        textEditingAnnotation = nil
        markedTextString = ""
        markedTextRange = NSRange(location: NSNotFound, length: 0)
        stopTextCursorBlink()
        mode = .editing
        needsDisplay = true
    }
    
    // MARK: - NSTextInputClient Protocol
    
    func insertText(_ string: Any, replacementRange: NSRange) {
        guard mode == .textEditing, textEditingAnnotation != nil else { return }
        
        var chars: String = ""
        if let s = string as? NSAttributedString {
            chars = s.string
        } else if let s = string as? String {
            chars = s
        }
        
        // Clear marked text
        markedTextString = ""
        markedTextRange = NSRange(location: NSNotFound, length: 0)
        
        // Append committed text
        textEditingAnnotation!.text.append(chars)
        needsDisplay = true
    }
    
    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        guard mode == .textEditing else { return }
        
        var text: String = ""
        if let s = string as? NSAttributedString {
            text = s.string
        } else if let s = string as? String {
            text = s
        }
        
        markedTextString = text
        if text.isEmpty {
            markedTextRange = NSRange(location: NSNotFound, length: 0)
        } else {
            markedTextRange = NSRange(location: 0, length: text.count)
        }
        selectedTextRange = selectedRange
        needsDisplay = true
    }
    
    func unmarkText() {
        // Commit marked text
        if !markedTextString.isEmpty, textEditingAnnotation != nil {
            textEditingAnnotation!.text.append(markedTextString)
        }
        markedTextString = ""
        markedTextRange = NSRange(location: NSNotFound, length: 0)
        needsDisplay = true
    }
    
    func selectedRange() -> NSRange {
        let len = textEditingAnnotation?.text.count ?? 0
        return NSRange(location: len, length: 0)
    }
    
    func markedRange() -> NSRange {
        return markedTextRange
    }
    
    func hasMarkedText() -> Bool {
        return markedTextRange.location != NSNotFound
    }
    
    func attributedSubstring(forProposedRange range: NSRange, actualRange: NSRangePointer?) -> NSAttributedString? {
        return nil
    }
    
    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        return [.underlineStyle, .foregroundColor]
    }
    
    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        // Return the rect where IME candidate window should appear
        guard let ann = textEditingAnnotation else {
            return .zero
        }
        
        let fontSize: CGFloat = 16
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium)
        ]
        let committedText = ann.text
        let textSize = (committedText as NSString).size(withAttributes: attrs)
        
        // Convert from view coords to screen coords
        let viewPoint = NSPoint(x: ann.startPoint.x + textSize.width, y: ann.startPoint.y)
        let windowPoint = convert(viewPoint, to: nil)
        let screenPoint = window?.convertPoint(toScreen: windowPoint) ?? windowPoint
        
        return NSRect(x: screenPoint.x, y: screenPoint.y, width: 0, height: fontSize + 4)
    }
    
    func characterIndex(for point: NSPoint) -> Int {
        return 0
    }
    
    override func doCommand(by selector: Selector) {
        if selector == #selector(cancelOperation(_:)) {
            // Esc pressed — cancel text editing (delete text node), NOT close screenshot
            if mode == .textEditing {
                cancelTextEditing()
                return
            }
        }
        if selector == #selector(insertNewline(_:)) {
            // Enter pressed — commit text
            if mode == .textEditing {
                commitTextIfNeeded()
                return
            }
        }
        if selector == #selector(deleteBackward(_:)) {
            // Backspace
            if mode == .textEditing, textEditingAnnotation != nil {
                if !textEditingAnnotation!.text.isEmpty {
                    textEditingAnnotation!.text.removeLast()
                    needsDisplay = true
                }
                return
            }
        }
        // Don't call super — we handle everything ourselves
    }
    
    // MARK: - Text editing helpers
    
    private func commitTextIfNeeded() {
        if var ann = textEditingAnnotation {
            // Also commit any remaining marked text
            if !markedTextString.isEmpty {
                ann.text.append(markedTextString)
                markedTextString = ""
                markedTextRange = NSRange(location: NSNotFound, length: 0)
            }
            if !ann.text.isEmpty {
                ann.endPoint = ann.startPoint
                annotations.append(ann)
            }
        }
        textEditingAnnotation = nil
        stopTextCursorBlink()
        mode = .editing
        needsDisplay = true
    }
    
    private func startTextCursorBlink() {
        stopTextCursorBlink()
        textCursorVisible = true
        textCursorTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.textCursorVisible.toggle()
            self?.needsDisplay = true
        }
    }
    
    private func stopTextCursorBlink() {
        textCursorTimer?.invalidate()
        textCursorTimer = nil
    }
    
    // MARK: - Handle hit testing
    
    private func handleRects() -> [(HandlePosition, NSRect)] {
        let s = handleSize
        let hs = s / 2.0
        let r = selectionRect
        return [
            (.topLeft,      NSRect(x: r.minX - hs, y: r.maxY - hs, width: s, height: s)),
            (.topCenter,    NSRect(x: r.midX - hs, y: r.maxY - hs, width: s, height: s)),
            (.topRight,     NSRect(x: r.maxX - hs, y: r.maxY - hs, width: s, height: s)),
            (.middleLeft,   NSRect(x: r.minX - hs, y: r.midY - hs, width: s, height: s)),
            (.middleRight,  NSRect(x: r.maxX - hs, y: r.midY - hs, width: s, height: s)),
            (.bottomLeft,   NSRect(x: r.minX - hs, y: r.minY - hs, width: s, height: s)),
            (.bottomCenter, NSRect(x: r.midX - hs, y: r.minY - hs, width: s, height: s)),
            (.bottomRight,  NSRect(x: r.maxX - hs, y: r.minY - hs, width: s, height: s)),
        ]
    }
    
    private func hitTestHandle(at point: NSPoint) -> HandlePosition {
        let tolerance: CGFloat = 6.0
        for (pos, rect) in handleRects() {
            let expanded = rect.insetBy(dx: -tolerance, dy: -tolerance)
            if expanded.contains(point) { return pos }
        }
        return .none
    }
    
    private func cursorForHandle(_ handle: HandlePosition) -> NSCursor {
        switch handle {
        case .topLeft, .bottomRight: return NSCursor.crosshair
        case .topRight, .bottomLeft: return NSCursor.crosshair
        case .topCenter, .bottomCenter: return NSCursor.resizeUpDown
        case .middleLeft, .middleRight: return NSCursor.resizeLeftRight
        case .none: return NSCursor.arrow
        }
    }
    
    // MARK: - Drawing
    
    override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        
        // Draw background
        if let bgImg = screenBGImage {
            bgImg.draw(in: bounds, from: .zero, operation: .copy, fraction: 1.0)
        } else {
            ctx.setFillColor(NSColor.black.cgColor)
            ctx.fill(bounds)
        }
        
        if mode == .idle {
            // Dim entire screen and show crosshair
            ctx.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
            ctx.fill(bounds)
            drawCrosshair(ctx: ctx)
            return
        }
        
        // Dim outside selection
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.3).cgColor)
        
        // Top
        ctx.fill(NSRect(x: 0, y: selectionRect.maxY, width: bounds.width, height: bounds.height - selectionRect.maxY))
        // Bottom
        ctx.fill(NSRect(x: 0, y: 0, width: bounds.width, height: selectionRect.minY))
        // Left
        ctx.fill(NSRect(x: 0, y: selectionRect.minY, width: selectionRect.minX, height: selectionRect.height))
        // Right
        ctx.fill(NSRect(x: selectionRect.maxX, y: selectionRect.minY, width: bounds.width - selectionRect.maxX, height: selectionRect.height))
        
        // Selection border
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
        ctx.setLineWidth(1.0)
        ctx.stroke(selectionRect)
        
        // Draw completed annotations (clipped to selection)
        ctx.saveGState()
        ctx.clip(to: selectionRect)
        
        for ann in annotations {
            drawAnnotation(ann, ctx: ctx, isEditing: false)
        }
        
        // Draw current annotation being drawn
        if let current = currentAnnotation {
            drawAnnotation(current, ctx: ctx, isEditing: false)
        }
        
        // Draw text being edited
        if let textAnn = textEditingAnnotation {
            drawAnnotation(textAnn, ctx: ctx, isEditing: true)
        }
        
        ctx.restoreGState()
        
        // Draw handles in editing mode
        if mode == .editing || mode == .annotating || mode == .textEditing {
            for (_, rect) in handleRects() {
                ctx.setFillColor(NSColor.white.cgColor)
                ctx.fill(rect)
                ctx.setStrokeColor(NSColor.gray.cgColor)
                ctx.setLineWidth(0.5)
                ctx.stroke(rect)
            }
        }
        
        // Mosaic brush cursor preview
        if activeAnnotationTool == .mosaic && selectionRect.contains(mouseLocation) && (mode == .editing || mode == .annotating) {
            ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.8).cgColor)
            ctx.setLineWidth(1.0)
            let cursorRect = NSRect(
                x: mouseLocation.x - mosaicBrushSize,
                y: mouseLocation.y - mosaicBrushSize,
                width: mosaicBrushSize * 2,
                height: mosaicBrushSize * 2
            )
            ctx.strokeEllipse(in: cursorRect)
        }
        
        // Size label
        if mode == .drawing || mode == .editing || mode == .resizing {
            drawSizeLabel(ctx: ctx)
        }
        
        // Crosshair when drawing
        if mode == .drawing {
            drawCrosshair(ctx: ctx)
        }
    }
    
    private func drawAnnotation(_ ann: Annotation, ctx: CGContext, isEditing: Bool) {
        ctx.saveGState()
        
        switch ann.tool {
        case .arrow:
            ctx.setStrokeColor(ann.color.cgColor)
            ctx.setLineWidth(ann.lineWidth)
            ctx.setLineCap(.round)
            drawArrowCG(from: ann.startPoint, to: ann.endPoint, ctx: ctx, lineWidth: ann.lineWidth, color: ann.color)
        case .rectangle:
            ctx.setStrokeColor(ann.color.cgColor)
            ctx.setLineWidth(ann.lineWidth)
            let r = NSRect(
                x: min(ann.startPoint.x, ann.endPoint.x),
                y: min(ann.startPoint.y, ann.endPoint.y),
                width: abs(ann.endPoint.x - ann.startPoint.x),
                height: abs(ann.endPoint.y - ann.startPoint.y)
            )
            if r.width > 2 && r.height > 2 { ctx.stroke(r) }
        case .text:
            drawTextAnnotation(ann, ctx: ctx, isEditing: isEditing)
        case .mosaic:
            drawMosaicBrushCG(ann, ctx: ctx)
        case .none:
            break
        }
        
        ctx.restoreGState()
    }
    
    private func drawTextAnnotation(_ ann: Annotation, ctx: CGContext, isEditing: Bool) {
        let fontSize: CGFloat = 16
        
        // Build display text: committed text + marked text
        var displayText = ann.text
        if isEditing && !markedTextString.isEmpty {
            displayText += markedTextString
        }
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: ann.color
        ]
        let textSize = (displayText as NSString).size(withAttributes: attrs)
        
        // Background
        let pad: CGFloat = 4
        let bgRect = NSRect(
            x: ann.startPoint.x - pad,
            y: ann.startPoint.y - pad,
            width: max(textSize.width, 2) + pad * 2,
            height: textSize.height + pad * 2
        )
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.addPath(CGPath(roundedRect: bgRect, cornerWidth: 3, cornerHeight: 3, transform: nil))
        ctx.fillPath()
        
        // Draw committed text
        if !ann.text.isEmpty {
            let committedAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: ann.color
            ]
            (ann.text as NSString).draw(at: ann.startPoint, withAttributes: committedAttrs)
        }
        
        // Draw marked text (with underline to distinguish from committed text)
        if isEditing && !markedTextString.isEmpty {
            let committedSize = (ann.text as NSString).size(withAttributes: attrs)
            let markedAttrs: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
                .foregroundColor: ann.color,
                .underlineStyle: NSUnderlineStyle.single.rawValue,
                .underlineColor: ann.color
            ]
            let markedPoint = NSPoint(x: ann.startPoint.x + committedSize.width, y: ann.startPoint.y)
            (markedTextString as NSString).draw(at: markedPoint, withAttributes: markedAttrs)
        }
        
        // Cursor
        if isEditing && textCursorVisible {
            let fullDisplaySize = (displayText as NSString).size(withAttributes: attrs)
            let cursorX = ann.startPoint.x + (displayText.isEmpty ? 0 : fullDisplaySize.width)
            ctx.setStrokeColor(NSColor.white.cgColor)
            ctx.setLineWidth(1.5)
            ctx.move(to: CGPoint(x: cursorX, y: ann.startPoint.y))
            ctx.addLine(to: CGPoint(x: cursorX, y: ann.startPoint.y + fontSize))
            ctx.strokePath()
        }
    }
    
    /// Draw mosaic as a brush stroke along the path points
    private func drawMosaicBrushCG(_ ann: Annotation, ctx: CGContext) {
        guard let bgImage = backgroundImage else { return }
        guard ann.mosaicPath.count >= 1 else { return }
        
        let scale = CGFloat(bgImage.width) / targetScreen.frame.width
        let blockSize: CGFloat = 10
        let brushRadius = ann.mosaicBrushSize
        
        var drawnBlocks = Set<String>()
        
        for point in ann.mosaicPath {
            let minBX = Int(floor((point.x - brushRadius) / blockSize))
            let maxBX = Int(ceil((point.x + brushRadius) / blockSize))
            let minBY = Int(floor((point.y - brushRadius) / blockSize))
            let maxBY = Int(ceil((point.y + brushRadius) / blockSize))
            
            for bx in minBX...maxBX {
                for by in minBY...maxBY {
                    let blockCenterX = CGFloat(bx) * blockSize + blockSize / 2
                    let blockCenterY = CGFloat(by) * blockSize + blockSize / 2
                    
                    let dx = blockCenterX - point.x
                    let dy = blockCenterY - point.y
                    if dx * dx + dy * dy > brushRadius * brushRadius { continue }
                    
                    let blockRect = NSRect(x: CGFloat(bx) * blockSize, y: CGFloat(by) * blockSize, width: blockSize, height: blockSize)
                    guard blockRect.intersects(selectionRect) else { continue }
                    
                    let key = "\(bx),\(by)"
                    guard !drawnBlocks.contains(key) else { continue }
                    drawnBlocks.insert(key)
                    
                    let sampleX = blockCenterX * scale
                    let sampleY = (targetScreen.frame.height - blockCenterY) * scale
                    
                    let sampleRect = CGRect(x: max(0, sampleX - 1), y: max(0, sampleY - 1), width: 2, height: 2)
                    var fillColor = NSColor.gray
                    
                    if let sampleCG = bgImage.cropping(to: sampleRect) {
                        let sampleImg = NSImage(cgImage: sampleCG, size: NSSize(width: 2, height: 2))
                        if let tiff = sampleImg.tiffRepresentation,
                           let rep = NSBitmapImageRep(data: tiff),
                           let c = rep.colorAt(x: 0, y: 0) {
                            fillColor = c
                        }
                    }
                    
                    ctx.setFillColor(fillColor.cgColor)
                    ctx.fill(blockRect)
                }
            }
        }
    }
    
    private func drawArrowCG(from start: NSPoint, to end: NSPoint, ctx: CGContext, lineWidth: CGFloat, color: NSColor) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 5 else { return }
        
        let headLength: CGFloat = min(20, length * 0.3)
        let headWidth: CGFloat = headLength * 0.5
        let angle = atan2(dy, dx)
        
        let lineEndX = end.x - headLength * cos(angle)
        let lineEndY = end.y - headLength * sin(angle)
        
        ctx.move(to: CGPoint(x: start.x, y: start.y))
        ctx.addLine(to: CGPoint(x: lineEndX, y: lineEndY))
        ctx.strokePath()
        
        ctx.setFillColor(color.cgColor)
        let leftX = end.x - headLength * cos(angle) + headWidth * sin(angle)
        let leftY = end.y - headLength * sin(angle) - headWidth * cos(angle)
        let rightX = end.x - headLength * cos(angle) - headWidth * sin(angle)
        let rightY = end.y - headLength * sin(angle) + headWidth * cos(angle)
        
        ctx.move(to: CGPoint(x: end.x, y: end.y))
        ctx.addLine(to: CGPoint(x: leftX, y: leftY))
        ctx.addLine(to: CGPoint(x: rightX, y: rightY))
        ctx.closePath()
        ctx.fillPath()
    }
    
    private func drawCrosshair(ctx: CGContext) {
        ctx.setStrokeColor(NSColor.white.withAlphaComponent(0.5).cgColor)
        ctx.setLineWidth(0.5)
        ctx.setLineDash(phase: 0, lengths: [5, 5])
        
        ctx.move(to: CGPoint(x: 0, y: mouseLocation.y))
        ctx.addLine(to: CGPoint(x: bounds.width, y: mouseLocation.y))
        ctx.strokePath()
        
        ctx.move(to: CGPoint(x: mouseLocation.x, y: 0))
        ctx.addLine(to: CGPoint(x: mouseLocation.x, y: bounds.height))
        ctx.strokePath()
        
        ctx.setLineDash(phase: 0, lengths: [])
    }
    
    private func drawSizeLabel(ctx: CGContext) {
        let w = Int(selectionRect.width)
        let h = Int(selectionRect.height)
        let text = "\(w) x \(h)"
        
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 6
        
        var ly = selectionRect.origin.y - size.height - pad * 2 - 4
        if ly < 0 { ly = selectionRect.maxY + 4 }
        
        let bgRect = NSRect(x: selectionRect.origin.x, y: ly, width: size.width + pad * 2, height: size.height + pad * 2)
        
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.75).cgColor)
        ctx.addPath(CGPath(roundedRect: bgRect, cornerWidth: 4, cornerHeight: 4, transform: nil))
        ctx.fillPath()
        
        (text as NSString).draw(at: NSPoint(x: bgRect.origin.x + pad, y: bgRect.origin.y + pad), withAttributes: attrs)
    }
    
    // MARK: - Toolbar
    // Main toolbar: [Arrow][Rect][Text][Mosaic] | [X][Pin][Copy]
    // Color sub-bar: [color dots...] — shown below main toolbar when annotation tool is active
    
    private func showToolbar() {
        removeToolbar()
        
        let btnW: CGFloat = 32
        let btnH: CGFloat = 32
        let spacing: CGFloat = 4
        let dividerW: CGFloat = 12
        
        let toolCount: CGFloat = 4
        let actionCount: CGFloat = 4
        
        let tbW = toolCount * btnW + (toolCount - 1) * spacing
            + dividerW
            + actionCount * btnW + (actionCount - 1) * spacing
            + 16  // padding
        let tbH: CGFloat = 40
        
        var tx = selectionRect.maxX - tbW
        var ty = selectionRect.origin.y - tbH - 6
        if ty < 0 { ty = selectionRect.maxY + 6 }
        if tx < 0 { tx = selectionRect.origin.x }
        if tx + tbW > bounds.width { tx = bounds.width - tbW }
        
        let tb = NSView(frame: NSRect(x: tx, y: ty, width: tbW, height: tbH))
        tb.wantsLayer = true
        tb.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.9).cgColor
        tb.layer?.cornerRadius = 8
        
        var xOff: CGFloat = 8
        
        // --- Tool buttons ---
        let arrBtn = makeToolbarButton(
            icon: "arrow.up.right", tint: .white,
            frame: NSRect(x: xOff, y: (tbH - btnH) / 2, width: btnW, height: btnH),
            action: #selector(toolbarArrow)
        )
        tb.addSubview(arrBtn)
        arrowBtn = arrBtn
        xOff += btnW + spacing
        
        let rctBtn = makeToolbarButton(
            icon: "rectangle", tint: .white,
            frame: NSRect(x: xOff, y: (tbH - btnH) / 2, width: btnW, height: btnH),
            action: #selector(toolbarRectangle)
        )
        tb.addSubview(rctBtn)
        rectBtn = rctBtn
        xOff += btnW + spacing
        
        let txtBtn = makeToolbarButton(
            icon: "textformat", tint: .white,
            frame: NSRect(x: xOff, y: (tbH - btnH) / 2, width: btnW, height: btnH),
            action: #selector(toolbarText)
        )
        tb.addSubview(txtBtn)
        textBtn = txtBtn
        xOff += btnW + spacing
        
        let mosBtn = makeToolbarButton(
            icon: "circle.dotted", tint: .white,
            frame: NSRect(x: xOff, y: (tbH - btnH) / 2, width: btnW, height: btnH),
            action: #selector(toolbarMosaic)
        )
        tb.addSubview(mosBtn)
        mosaicBtn = mosBtn
        xOff += btnW + spacing
        
        // --- Divider ---
        addDivider(to: tb, at: xOff, height: tbH)
        xOff += dividerW
        
        // --- Action buttons ---
        let cancelBtn = makeToolbarButton(
            icon: "xmark", tint: .white,
            frame: NSRect(x: xOff, y: (tbH - btnH) / 2, width: btnW, height: btnH),
            action: #selector(toolbarCancel)
        )
        tb.addSubview(cancelBtn)
        xOff += btnW + spacing
        
        let pinBtn = makeToolbarButton(
            icon: "pin.fill", tint: .systemOrange,
            frame: NSRect(x: xOff, y: (tbH - btnH) / 2, width: btnW, height: btnH),
            action: #selector(toolbarPin)
        )
        tb.addSubview(pinBtn)
        xOff += btnW + spacing

        let saveBtn = makeToolbarButton(
            icon: "square.and.arrow.down", tint: .systemBlue,
            frame: NSRect(x: xOff, y: (tbH - btnH) / 2, width: btnW, height: btnH),
            action: #selector(toolbarSave)
        )
        tb.addSubview(saveBtn)
        xOff += btnW + spacing
        
        let copyBtn = makeToolbarButton(
            icon: "checkmark", tint: .systemGreen,
            frame: NSRect(x: xOff, y: (tbH - btnH) / 2, width: btnW, height: btnH),
            action: #selector(toolbarCopy)
        )
        tb.addSubview(copyBtn)
        
        addSubview(tb)
        toolbarView = tb
        
        updateToolbarHighlight()
    }
    
    private func showColorBar() {
        removeColorBar()
        guard let tb = toolbarView else { return }
        
        let dotSize: CGFloat = 18
        let dotSpacing: CGFloat = 6
        let colorCount = CGFloat(colorOptions.count)
        let barW = colorCount * dotSize + (colorCount - 1) * dotSpacing + 16
        let barH: CGFloat = 30
        
        // Position below the main toolbar
        let barX = tb.frame.origin.x + tb.frame.width - barW
        let barY = tb.frame.origin.y - barH - 4
        
        let bar = NSView(frame: NSRect(x: barX, y: barY, width: barW, height: barH))
        bar.wantsLayer = true
        bar.layer?.backgroundColor = NSColor(white: 0.15, alpha: 0.9).cgColor
        bar.layer?.cornerRadius = 6
        
        var xOff: CGFloat = 8
        for (i, color) in colorOptions.enumerated() {
            let dotBtn = NSButton(frame: NSRect(
                x: xOff,
                y: (barH - dotSize) / 2,
                width: dotSize,
                height: dotSize
            ))
            dotBtn.bezelStyle = .regularSquare
            dotBtn.isBordered = false
            dotBtn.title = ""
            dotBtn.wantsLayer = true
            dotBtn.layer?.cornerRadius = dotSize / 2
            dotBtn.layer?.backgroundColor = color.cgColor
            dotBtn.tag = i
            dotBtn.target = self
            dotBtn.action = #selector(colorDotClicked(_:))
            
            if color == annotationColor {
                dotBtn.layer?.borderWidth = 2.5
                dotBtn.layer?.borderColor = NSColor.white.cgColor
            } else {
                dotBtn.layer?.borderWidth = 1
                dotBtn.layer?.borderColor = NSColor.gray.withAlphaComponent(0.4).cgColor
            }
            
            bar.addSubview(dotBtn)
            xOff += dotSize + dotSpacing
        }
        
        addSubview(bar)
        colorBarView = bar
    }
    
    private func removeColorBar() {
        colorBarView?.removeFromSuperview()
        colorBarView = nil
    }
    
    private func addDivider(to parent: NSView, at x: CGFloat, height: CGFloat) {
        let divider = NSView(frame: NSRect(x: x, y: 8, width: 1, height: height - 16))
        divider.wantsLayer = true
        divider.layer?.backgroundColor = NSColor.gray.withAlphaComponent(0.5).cgColor
        parent.addSubview(divider)
    }
    
    private func makeToolbarButton(icon: String, tint: NSColor, frame: NSRect, action: Selector) -> NSButton {
        let btn = NSButton(frame: frame)
        btn.bezelStyle = .regularSquare
        btn.isBordered = false
        btn.wantsLayer = true
        btn.layer?.cornerRadius = 6
        
        if let img = NSImage(systemSymbolName: icon, accessibilityDescription: nil) {
            let cfg = NSImage.SymbolConfiguration(pointSize: 14, weight: .semibold)
            btn.image = img.withSymbolConfiguration(cfg)
            btn.contentTintColor = tint
        }
        
        btn.target = self
        btn.action = action
        
        return btn
    }
    
    private func updateToolbarHighlight() {
        arrowBtn?.layer?.backgroundColor = activeAnnotationTool == .arrow
            ? NSColor.white.withAlphaComponent(0.2).cgColor : NSColor.clear.cgColor
        rectBtn?.layer?.backgroundColor = activeAnnotationTool == .rectangle
            ? NSColor.white.withAlphaComponent(0.2).cgColor : NSColor.clear.cgColor
        textBtn?.layer?.backgroundColor = activeAnnotationTool == .text
            ? NSColor.white.withAlphaComponent(0.2).cgColor : NSColor.clear.cgColor
        mosaicBtn?.layer?.backgroundColor = activeAnnotationTool == .mosaic
            ? NSColor.white.withAlphaComponent(0.2).cgColor : NSColor.clear.cgColor
        
        // Show/hide color bar based on whether annotation tool is active
        if activeAnnotationTool != .none && activeAnnotationTool != .mosaic {
            showColorBar()
        } else {
            removeColorBar()
        }
    }
    
    private func updateColorBarHighlight() {
        guard let bar = colorBarView else { return }
        for subview in bar.subviews {
            guard let btn = subview as? NSButton else { continue }
            let idx = btn.tag
            guard idx >= 0 && idx < colorOptions.count else { continue }
            if colorOptions[idx] == annotationColor {
                btn.layer?.borderWidth = 2.5
                btn.layer?.borderColor = NSColor.white.cgColor
            } else {
                btn.layer?.borderWidth = 1
                btn.layer?.borderColor = NSColor.gray.withAlphaComponent(0.4).cgColor
            }
        }
    }
    
    private func removeToolbar() {
        removeColorBar()
        toolbarView?.removeFromSuperview()
        toolbarView = nil
        arrowBtn = nil
        rectBtn = nil
        textBtn = nil
        mosaicBtn = nil
    }
    
    private func repositionToolbar() {
        guard let tb = toolbarView else { return }
        let tbW = tb.frame.width
        let tbH = tb.frame.height
        
        var tx = selectionRect.maxX - tbW
        var ty = selectionRect.origin.y - tbH - 6
        if ty < 0 { ty = selectionRect.maxY + 6 }
        if tx < 0 { tx = selectionRect.origin.x }
        if tx + tbW > bounds.width { tx = bounds.width - tbW }
        
        tb.frame.origin = NSPoint(x: tx, y: ty)
        
        // Reposition color bar if visible
        if let bar = colorBarView {
            let barW = bar.frame.width
            let barH = bar.frame.height
            let barX = tb.frame.origin.x + tb.frame.width - barW
            let barY = tb.frame.origin.y - barH - 4
            bar.frame.origin = NSPoint(x: barX, y: barY)
        }
    }
    
    // MARK: - Toolbar Actions
    
    private func selectAnnotationTool(_ tool: AnnotationTool) {
        if mode == .textEditing {
            commitTextIfNeeded()
        }
        activeAnnotationTool = activeAnnotationTool == tool ? .none : tool
        updateToolbarHighlight()
        window?.invalidateCursorRects(for: self)
    }
    
    @objc private func toolbarArrow() { selectAnnotationTool(.arrow) }
    @objc private func toolbarRectangle() { selectAnnotationTool(.rectangle) }
    @objc private func toolbarText() { selectAnnotationTool(.text) }
    @objc private func toolbarMosaic() { selectAnnotationTool(.mosaic) }
    
    @objc private func colorDotClicked(_ sender: NSButton) {
        let idx = sender.tag
        guard idx >= 0 && idx < colorOptions.count else { return }
        annotationColor = colorOptions[idx]
        updateColorBarHighlight()
    }
    
    @objc private func toolbarCancel() {
        screenshotManager?.cancelCapture()
    }
    
    @objc private func toolbarPin() {
        commitTextIfNeeded()
        finishWithAction(.pin)
    }
    
    @objc private func toolbarSave() {
        commitTextIfNeeded()
        finishWithAction(.save)
    }

    @objc private func toolbarCopy() {
        commitTextIfNeeded()
        finishWithAction(.copy)
    }
    
    private func finishWithAction(_ action: ToolbarAction) {
        screenshotManager?.finishCapture(selectionRect, on: targetScreen, from: self, action: action, annotations: annotations)
    }
    
    // MARK: - Mouse Events
    
    override func mouseMoved(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        mouseLocation = loc
        
        if mode == .idle {
            needsDisplay = true
            return
        }
        
        if activeAnnotationTool == .mosaic {
            needsDisplay = true
        }
        
        if mode == .editing || mode == .annotating || mode == .textEditing {
            updateCursorForLocation(loc)
        }
    }
    
    private func updateCursorForLocation(_ loc: NSPoint) {
        if activeAnnotationTool != .none && selectionRect.contains(loc) {
            if activeAnnotationTool == .text {
                NSCursor.iBeam.set()
            } else {
                NSCursor.crosshair.set()
            }
            return
        }
        
        let handle = hitTestHandle(at: loc)
        if handle != .none {
            cursorForHandle(handle).set()
            return
        }
        
        if selectionRect.contains(loc) {
            NSCursor.openHand.set()
            return
        }
        
        NSCursor.crosshair.set()
    }
    
    override func mouseDown(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        
        // Check if click is in toolbar or color bar area
        if let tb = toolbarView, tb.frame.contains(loc) { return }
        if let cb = colorBarView, cb.frame.contains(loc) { return }
        
        // If in text editing mode: click anywhere = commit text and go back to editing
        if mode == .textEditing {
            commitTextIfNeeded()
            return
        }
        
        if mode == .editing || mode == .annotating {
            // Text tool: click inside selection to place text
            if activeAnnotationTool == .text && selectionRect.contains(loc) {
                mode = .textEditing
                textEditingAnnotation = Annotation(
                    tool: .text,
                    startPoint: loc,
                    endPoint: loc,
                    color: annotationColor,
                    lineWidth: 0,
                    text: ""
                )
                startTextCursorBlink()
                needsDisplay = true
                return
            }
            
            // Mosaic brush: drag to paint
            if activeAnnotationTool == .mosaic && selectionRect.contains(loc) {
                mode = .annotating
                currentAnnotation = Annotation(
                    tool: .mosaic,
                    startPoint: loc,
                    endPoint: loc,
                    color: .clear,
                    lineWidth: 0,
                    mosaicPath: [loc],
                    mosaicBrushSize: mosaicBrushSize
                )
                needsDisplay = true
                return
            }
            
            // Arrow/Rectangle: drag to draw
            if activeAnnotationTool == .arrow || activeAnnotationTool == .rectangle {
                if selectionRect.contains(loc) {
                    mode = .annotating
                    currentAnnotation = Annotation(
                        tool: activeAnnotationTool,
                        startPoint: loc,
                        endPoint: loc,
                        color: annotationColor,
                        lineWidth: 3.0
                    )
                    needsDisplay = true
                    return
                }
            }
            
            // Check resize handle
            let handle = hitTestHandle(at: loc)
            if handle != .none {
                mode = .resizing
                activeHandle = handle
                resizeStartMouse = loc
                resizeStartRect = selectionRect
                NSCursor.closedHand.set()
                return
            }
            
            // Move selection
            if selectionRect.contains(loc) {
                mode = .moving
                moveStartMouse = loc
                moveStartRect = selectionRect
                NSCursor.closedHand.set()
                return
            }
            
            // Outside: new selection
            resetSelection()
        }
        
        // Start new selection
        mode = .drawing
        drawStartPoint = loc
        selectionRect = NSRect(x: loc.x, y: loc.y, width: 0, height: 0)
        needsDisplay = true
    }
    
    override func mouseDragged(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        mouseLocation = loc
        
        switch mode {
        case .drawing:
            selectionRect = NSRect(
                x: min(drawStartPoint.x, loc.x),
                y: min(drawStartPoint.y, loc.y),
                width: abs(loc.x - drawStartPoint.x),
                height: abs(loc.y - drawStartPoint.y)
            )
            needsDisplay = true
            
        case .moving:
            let dx = loc.x - moveStartMouse.x
            let dy = loc.y - moveStartMouse.y
            var newX = moveStartRect.origin.x + dx
            var newY = moveStartRect.origin.y + dy
            newX = max(0, min(newX, bounds.width - moveStartRect.width))
            newY = max(0, min(newY, bounds.height - moveStartRect.height))
            selectionRect = NSRect(x: newX, y: newY, width: moveStartRect.width, height: moveStartRect.height)
            repositionToolbar()
            needsDisplay = true
            
        case .resizing:
            let dx = loc.x - resizeStartMouse.x
            let dy = loc.y - resizeStartMouse.y
            var newRect = resizeStartRect
            let minSize: CGFloat = 10
            
            switch activeHandle {
            case .topLeft:
                newRect.origin.x = min(resizeStartRect.maxX - minSize, resizeStartRect.origin.x + dx)
                newRect.size.width = resizeStartRect.maxX - newRect.origin.x
                newRect.size.height = max(minSize, resizeStartRect.height + dy)
            case .topCenter:
                newRect.size.height = max(minSize, resizeStartRect.height + dy)
            case .topRight:
                newRect.size.width = max(minSize, resizeStartRect.width + dx)
                newRect.size.height = max(minSize, resizeStartRect.height + dy)
            case .middleLeft:
                newRect.origin.x = min(resizeStartRect.maxX - minSize, resizeStartRect.origin.x + dx)
                newRect.size.width = resizeStartRect.maxX - newRect.origin.x
            case .middleRight:
                newRect.size.width = max(minSize, resizeStartRect.width + dx)
            case .bottomLeft:
                newRect.origin.x = min(resizeStartRect.maxX - minSize, resizeStartRect.origin.x + dx)
                newRect.size.width = resizeStartRect.maxX - newRect.origin.x
                let newH = resizeStartRect.height - dy
                if newH >= minSize {
                    newRect.origin.y = resizeStartRect.origin.y + dy
                    newRect.size.height = newH
                }
            case .bottomCenter:
                let newH = resizeStartRect.height - dy
                if newH >= minSize {
                    newRect.origin.y = resizeStartRect.origin.y + dy
                    newRect.size.height = newH
                }
            case .bottomRight:
                newRect.size.width = max(minSize, resizeStartRect.width + dx)
                let newH = resizeStartRect.height - dy
                if newH >= minSize {
                    newRect.origin.y = resizeStartRect.origin.y + dy
                    newRect.size.height = newH
                }
            case .none:
                break
            }
            
            selectionRect = newRect
            repositionToolbar()
            needsDisplay = true
            
        case .annotating:
            if currentAnnotation?.tool == .mosaic {
                currentAnnotation?.mosaicPath.append(loc)
                currentAnnotation?.endPoint = loc
            } else {
                currentAnnotation?.endPoint = loc
            }
            needsDisplay = true
            
        default:
            break
        }
    }
    
    override func mouseUp(with event: NSEvent) {
        let loc = convert(event.locationInWindow, from: nil)
        
        switch mode {
        case .drawing:
            selectionRect = NSRect(
                x: min(drawStartPoint.x, loc.x),
                y: min(drawStartPoint.y, loc.y),
                width: abs(loc.x - drawStartPoint.x),
                height: abs(loc.y - drawStartPoint.y)
            )
            
            if selectionRect.width > 3 && selectionRect.height > 3 {
                mode = .editing
                needsDisplay = true
                showToolbar()
            } else {
                screenshotManager?.cancelCapture()
            }
            
        case .moving:
            mode = .editing
            NSCursor.openHand.set()
            
        case .resizing:
            mode = .editing
            activeHandle = .none
            
        case .annotating:
            if var ann = currentAnnotation {
                if ann.tool == .mosaic {
                    ann.mosaicPath.append(loc)
                    if ann.mosaicPath.count > 1 {
                        annotations.append(ann)
                    }
                } else {
                    ann.endPoint = loc
                    let dx = abs(ann.endPoint.x - ann.startPoint.x)
                    let dy = abs(ann.endPoint.y - ann.startPoint.y)
                    if dx > 3 || dy > 3 {
                        annotations.append(ann)
                    }
                }
            }
            currentAnnotation = nil
            mode = .editing
            needsDisplay = true
            
        default:
            break
        }
    }
    
    private func resetSelection() {
        removeToolbar()
        mode = .idle
        selectionRect = .zero
        annotations.removeAll()
        currentAnnotation = nil
        textEditingAnnotation = nil
        markedTextString = ""
        markedTextRange = NSRange(location: NSNotFound, length: 0)
        stopTextCursorBlink()
        activeAnnotationTool = .none
        needsDisplay = true
    }
    
    override func resetCursorRects() {
        if mode == .idle {
            addCursorRect(bounds, cursor: .crosshair)
        }
    }
}
