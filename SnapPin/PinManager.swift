import Cocoa

class PinManager {
    
    var lastCapturedImage: NSImage?
    var lastCapturedRect: NSRect?
    private var pinWindows: [PinWindow] = []
    
    func pinLastScreenshot() {
        guard let image = lastCapturedImage else {
            return
        }
        
        // Determine position: use the capture rect if available, otherwise center of main screen
        let position: NSPoint
        if let rect = lastCapturedRect {
            position = rect.origin
        } else {
            let screenFrame = NSScreen.main?.frame ?? NSRect(x: 100, y: 100, width: 800, height: 600)
            position = NSPoint(
                x: screenFrame.midX - image.size.width / 2,
                y: screenFrame.midY - image.size.height / 2
            )
        }
        
        let pinWindow = PinWindow(image: image, position: position, pinManager: self)
        pinWindow.makeKeyAndOrderFront(nil)
        pinWindows.append(pinWindow)
    }
    
    func removePinWindow(_ window: PinWindow) {
        pinWindows.removeAll { $0 === window }
    }
    
    func closeAllPins() {
        let windows = pinWindows
        pinWindows.removeAll()
        for window in windows {
            window.orderOut(nil)
            window.close()
        }
    }
}
