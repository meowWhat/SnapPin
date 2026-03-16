import Cocoa
import ScreenCaptureKit

class ScreenshotManager {
    
    private var overlayWindows: [OverlayWindow] = []
    private var pinManager: PinManager
    private var isCapturing = false
    private var screenImages: [UInt32: CGImage] = [:]
    
    init(pinManager: PinManager) {
        self.pinManager = pinManager
    }
    
    var hasActiveSelection: Bool {
        return isCapturing && overlayWindows.contains(where: { ($0.contentView as? OverlayView)?.hasSelection == true })
    }
    
    func startCapture() {
        guard !isCapturing else { return }
        isCapturing = true
        closeOverlays()
        screenImages.removeAll()
        
        captureAllDisplays { [weak self] in
            guard let self = self else { return }
            
            DispatchQueue.main.async {
                NSApp.activate(ignoringOtherApps: true)
                
                var firstOverlay: OverlayWindow?
                for screen in NSScreen.screens {
                    let displayID = self.displayID(for: screen)
                    let bgImage = self.screenImages[displayID]
                    
                    let overlay = OverlayWindow(
                        screen: screen,
                        screenshotManager: self,
                        backgroundImage: bgImage
                    )
                    overlay.orderFrontRegardless()
                    self.overlayWindows.append(overlay)
                    
                    let mouseLocation = NSEvent.mouseLocation
                    if screen.frame.contains(mouseLocation) {
                        firstOverlay = overlay
                    }
                }
                
                if let primary = firstOverlay ?? self.overlayWindows.first {
                    primary.makeKeyAndOrderFront(nil)
                }
                
                NSCursor.crosshair.set()
            }
        }
    }
    
    private func displayID(for screen: NSScreen) -> UInt32 {
        return screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32 ?? 0
    }
    
    private func captureAllDisplays(completion: @escaping () -> Void) {
        SCShareableContent.getExcludingDesktopWindows(false, onScreenWindowsOnly: false) { [weak self] content, error in
            guard let self = self, let content = content else {
                print("[SnapPin] SCShareableContent error: \(error?.localizedDescription ?? "unknown")")
                completion()
                return
            }
            
            let displays = content.displays
            let group = DispatchGroup()
            
            for display in displays {
                group.enter()
                
                let filter = SCContentFilter(display: display, excludingWindows: [])
                let config = SCStreamConfiguration()
                config.width = display.width * 2
                config.height = display.height * 2
                config.showsCursor = false
                config.captureResolution = .best
                
                SCScreenshotManager.captureImage(contentFilter: filter, configuration: config) { [weak self] image, error in
                    if let image = image {
                        self?.screenImages[display.displayID] = image
                    } else {
                        print("[SnapPin] Capture failed for display \(display.displayID): \(error?.localizedDescription ?? "unknown")")
                    }
                    group.leave()
                }
            }
            
            group.notify(queue: .main) {
                completion()
            }
        }
    }
    
    func handleF3() {
        if isCapturing {
            for overlay in overlayWindows {
                if let view = overlay.contentView as? OverlayView, view.hasSelection {
                    view.triggerPin()
                    return
                }
            }
        }
    }
    
    func handleCmdC() {
        if isCapturing {
            for overlay in overlayWindows {
                if let view = overlay.contentView as? OverlayView, view.hasSelection {
                    view.triggerCopy()
                    return
                }
            }
        }
    }
    
    func finishCapture(_ viewRect: NSRect, on screen: NSScreen, from overlayView: OverlayView, action: ToolbarAction, annotations: [Annotation] = []) {
        let displayID = self.displayID(for: screen)
        guard let bgImage = screenImages[displayID] else {
            cancelCapture()
            return
        }
        
        let scale = CGFloat(bgImage.width) / screen.frame.width
        
        let cropX = viewRect.origin.x * scale
        let cropY = (screen.frame.height - viewRect.origin.y - viewRect.height) * scale
        let cropW = viewRect.width * scale
        let cropH = viewRect.height * scale
        
        let cropRect = CGRect(x: cropX, y: cropY, width: cropW, height: cropH)
        
        guard let croppedCG = bgImage.cropping(to: cropRect) else {
            cancelCapture()
            return
        }
        
        var image = NSImage(cgImage: croppedCG, size: NSSize(width: viewRect.width, height: viewRect.height))
        
        if !annotations.isEmpty {
            image = renderAnnotations(annotations, onto: image, bgImage: bgImage, selectionRect: viewRect, screenSize: screen.frame.size, scale: scale)
        }
        
        closeOverlays()
        isCapturing = false
        
        pinManager.lastCapturedImage = image
        pinManager.lastCapturedRect = NSRect(
            x: screen.frame.origin.x + viewRect.origin.x,
            y: screen.frame.origin.y + viewRect.origin.y,
            width: viewRect.width,
            height: viewRect.height
        )
        
        switch action {
        case .cancel:
            pinManager.lastCapturedImage = nil
            pinManager.lastCapturedRect = nil
        case .pin:
            DispatchQueue.main.async { [weak self] in
                self?.pinManager.pinLastScreenshot()
            }
        case .copy:
            let pb = NSPasteboard.general
            pb.clearContents()
            pb.writeObjects([image])
        }
    }
    
    /// Render all annotations onto the cropped image
    private func renderAnnotations(_ annotations: [Annotation], onto image: NSImage, bgImage: CGImage, selectionRect: NSRect, screenSize: NSSize, scale: CGFloat) -> NSImage {
        let size = NSSize(width: image.size.width * scale, height: image.size.height * scale)
        let result = NSImage(size: size)
        
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: size), from: .zero, operation: .copy, fraction: 1.0)
        
        if let ctx = NSGraphicsContext.current?.cgContext {
            let scaleX = size.width / selectionRect.width
            let scaleY = size.height / selectionRect.height
            
            // First pass: render mosaic annotations
            for ann in annotations where ann.tool == .mosaic {
                renderMosaicBrush(ann, ctx: ctx, bgImage: bgImage, selectionRect: selectionRect, screenSize: screenSize, scale: scale, scaleX: scaleX, scaleY: scaleY)
            }
            
            // Second pass: render other annotations
            for ann in annotations where ann.tool != .mosaic {
                ctx.saveGState()
                
                let startX = (ann.startPoint.x - selectionRect.origin.x) * scaleX
                let startY = (ann.startPoint.y - selectionRect.origin.y) * scaleY
                let endX = (ann.endPoint.x - selectionRect.origin.x) * scaleX
                let endY = (ann.endPoint.y - selectionRect.origin.y) * scaleY
                
                let scaledLineWidth = ann.lineWidth * scaleX
                
                ctx.setStrokeColor(ann.color.cgColor)
                ctx.setLineWidth(scaledLineWidth)
                ctx.setLineCap(.round)
                ctx.setLineJoin(.round)
                
                switch ann.tool {
                case .arrow:
                    renderArrow(from: NSPoint(x: startX, y: startY),
                               to: NSPoint(x: endX, y: endY),
                               ctx: ctx, lineWidth: scaledLineWidth, color: ann.color)
                case .rectangle:
                    let r = NSRect(
                        x: min(startX, endX), y: min(startY, endY),
                        width: abs(endX - startX), height: abs(endY - startY)
                    )
                    if r.width > 2 && r.height > 2 { ctx.stroke(r) }
                case .text:
                    renderText(ann, at: NSPoint(x: startX, y: startY), scaleX: scaleX, ctx: ctx)
                case .mosaic:
                    break  // Already rendered
                case .none:
                    break
                }
                
                ctx.restoreGState()
            }
        }
        
        result.unlockFocus()
        result.size = image.size
        return result
    }
    
    private func renderArrow(from start: NSPoint, to end: NSPoint, ctx: CGContext, lineWidth: CGFloat, color: NSColor) {
        let dx = end.x - start.x
        let dy = end.y - start.y
        let length = sqrt(dx * dx + dy * dy)
        guard length > 5 else { return }
        
        let headLength: CGFloat = min(20 * (lineWidth / 3.0), length * 0.3)
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
    
    private func renderText(_ ann: Annotation, at point: NSPoint, scaleX: CGFloat, ctx: CGContext) {
        guard !ann.text.isEmpty else { return }
        
        let fontSize: CGFloat = 16 * scaleX
        let attrs: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .medium),
            .foregroundColor: ann.color
        ]
        
        let textSize = (ann.text as NSString).size(withAttributes: attrs)
        let pad: CGFloat = 4 * scaleX
        let bgRect = NSRect(
            x: point.x - pad,
            y: point.y - pad,
            width: textSize.width + pad * 2,
            height: textSize.height + pad * 2
        )
        ctx.setFillColor(NSColor.black.withAlphaComponent(0.5).cgColor)
        ctx.addPath(CGPath(roundedRect: bgRect, cornerWidth: 3 * scaleX, cornerHeight: 3 * scaleX, transform: nil))
        ctx.fillPath()
        
        (ann.text as NSString).draw(at: point, withAttributes: attrs)
    }
    
    /// Render mosaic brush path onto the final image
    private func renderMosaicBrush(_ ann: Annotation, ctx: CGContext, bgImage: CGImage, selectionRect: NSRect, screenSize: NSSize, scale: CGFloat, scaleX: CGFloat, scaleY: CGFloat) {
        guard ann.mosaicPath.count >= 1 else { return }
        
        let blockSize: CGFloat = 10  // Mosaic pixel block size (in view coords)
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
                    
                    // Sample color from background
                    let sampleX = blockCenterX * scale
                    let sampleY = (screenSize.height - blockCenterY) * scale
                    
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
                    
                    // Draw in output image coordinates
                    let outX = (CGFloat(bx) * blockSize - selectionRect.origin.x) * scaleX
                    let outY = (CGFloat(by) * blockSize - selectionRect.origin.y) * scaleY
                    let outW = blockSize * scaleX
                    let outH = blockSize * scaleY
                    
                    ctx.setFillColor(fillColor.cgColor)
                    ctx.fill(CGRect(x: outX, y: outY, width: outW, height: outH))
                }
            }
        }
    }
    
    func cancelCapture() {
        closeOverlays()
        isCapturing = false
    }
    
    private func closeOverlays() {
        let windows = overlayWindows
        overlayWindows.removeAll()
        for w in windows {
            w.orderOut(nil)
            w.close()
        }
        screenImages.removeAll()
    }
}
